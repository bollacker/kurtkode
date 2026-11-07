import Foundation
import Testing
@testable import AgentCore

@Suite struct ProgressRelayTests {
    final class Sink: @unchecked Sendable {
        let lock = NSLock()
        var batches: [String] = []
        func add(_ s: String) { lock.withLock { batches.append(s) } }
        var all: [String] { lock.withLock { batches } }
    }

    @Test func batchesManyPiecesInOrder() async throws {
        let sink = Sink()
        let relay = ProgressRelay(interval: .milliseconds(50)) { sink.add($0) }
        let pieces = (0..<5000).map { "line \($0)\n" }
        DispatchQueue.concurrentPerform(iterations: 1) { _ in for p in pieces { relay.add(p) } }
        try await Task.sleep(for: .milliseconds(20))
        for p in pieces.prefix(10) { relay.add(p) }
        await relay.flush()
        #expect(sink.all.joined() == pieces.joined() + pieces.prefix(10).joined())   // nothing lost or reordered
        #expect(sink.all.count <= 3)                                                     // not 5010 updates
    }

    @Test func liveOutputArrivesBeforeTheResult() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "bash", #"{"command":"for i in $(seq 1 3000); do echo line $i; done"}"#),
            SSE.content("Done."),
        ]))
        final class Log: @unchecked Sendable {
            let lock = NSLock(); var events: [AgentEvent] = []
            func add(_ e: AgentEvent) { lock.withLock { events.append(e) } }
        }
        let log = Log()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")],
                            config: AgentConfig(tools: AllTools.all), workspace: ws) { log.add($0) }
        let events = log.lock.withLock { log.events }
        let progress = events.enumerated().compactMap { i, e -> (Int, String)? in
            if case .toolProgress(_, let t) = e { (i, t) } else { nil }
        }
        let finished = try #require(events.firstIndex { if case .toolFinished = $0 { true } else { false } })
        #expect(!progress.isEmpty && progress.count < 100)
        #expect(progress.allSatisfy { $0.0 < finished })
        let text = progress.map(\.1).joined()
        #expect(text.contains("line 1\n") && text.contains("line 3000\n"))
    }
}
