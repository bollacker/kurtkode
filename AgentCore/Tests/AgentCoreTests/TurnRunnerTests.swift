import Foundation
import Testing
@testable import AgentCore

private func request(_ model: String = "qwen/qwen3-coder-30b") -> ChatRequest {
    ChatRequest(model: model, messages: [.user("hi")], maxTokens: 100)
}

private final class Updates: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TurnSnapshot] = []
    func add(_ s: TurnSnapshot) { lock.withLock { items.append(s) } }
    var all: [TurnSnapshot] { lock.withLock { items } }
}

@Suite struct TurnRunnerTests {
    @Test func streamsContentToCompletion() async throws {
        let (client, host) = MockServer.client(try MockServer.sse(fixture: "sse_qwen_content"))
        let updates = Updates()
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits(maxTokens: 321),
                                       updateInterval: .zero) { updates.add($0) }
        #expect(msg.role == .assistant)
        #expect(msg.content.contains("```"))
        #expect(msg.meta?.stopReason == .completed)
        #expect(msg.meta?.finishReason == .stop)
        #expect(msg.meta?.usage != nil)
        #expect(msg.meta?.modelMismatch == false)
        #expect(msg.meta?.timeToFirstToken != nil)
        #expect(updates.all.count > 3)
        #expect(updates.all.last?.content == msg.content)
        // The runner's limit overrides the request's max_tokens.
        let body = try #require(MockServer.requestBody(host))
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        guard case .object(let o) = json else { Issue.record("body"); return }
        #expect(o["max_tokens"] == .number(321))
    }

    @Test func flagsModelSubstitution() async throws {
        // LM Studio answered a request for an unknown model with whatever model was loaded.
        let (client, _) = MockServer.client(try MockServer.sse(fixture: "sse_qwen_unknown_model_substituted"))
        let msg = await TurnRunner.run(client: client, request: request("no-such-model"), limits: TurnLimits()) { _ in }
        #expect(msg.meta?.reportedModel == "qwen/qwen3-coder-30b")
        #expect(msg.meta?.modelMismatch == true)
    }

    @Test func retriesRateLimitsThenStreams() async throws {
        var route = try MockServer.sse(fixture: "sse_qwen_content")
        route.turns = [[Data(#"{"error":{"message":"rate limited"}}"#.utf8)], route.chunks]
        route.turnStatuses = [0: 429]
        let (client, host) = MockServer.client(route)
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits()) { _ in }
        #expect(msg.meta?.stopReason == .completed)
        #expect(!msg.content.isEmpty)
        #expect(MockServer.requestBodies(host).count == 2)
    }

    @Test func givesUpAfterTheLastRetry() async throws {
        let (client, host) = MockServer.client(.init(status: 503, chunks: [Data(#"{"error":"overloaded"}"#.utf8)]))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits()) { _ in }
        #expect(msg.meta?.stopReason == .failed)
        #expect(msg.meta?.error?.contains("HTTP 503") == true)
        #expect(MockServer.requestBodies(host).count == 3)   // the request and two retries
    }

    @Test func reportsHTTPErrorsAsFailedTurns() async throws {
        let body = Data(#"{"error":"Model not loaded"}"#.utf8)
        let (client, _) = MockServer.client(.init(status: 400, chunks: [body]))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits()) { _ in }
        #expect(msg.meta?.stopReason == .failed)
        #expect(msg.meta?.error?.contains("HTTP 400") == true)
        #expect(msg.meta?.error?.contains("Model not loaded") == true)
    }

    /// A chunk, then the connection closes: no finish reason, no [DONE] (seen with a server that died mid-reply).
    @Test func aStreamCutMidReplyFails() async throws {
        let chunk = #"data: {"model":"m","choices":[{"index":0,"delta":{"content":"Partial answer"},"finish_reason":null}]}"#
        let call = #"data: {"model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash","arguments":"{\"command\": \"rm -rf bu"}}]},"finish_reason":null}]}"#
        let (client, _) = MockServer.client(.init(chunks: [Data((chunk + "\n").utf8), Data((call + "\n").utf8)]))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits(maxTokens: 100)) { _ in }
        #expect(msg.meta?.stopReason == .failed)
        #expect(msg.meta?.error?.contains("connection closed before the reply finished") == true)
        #expect(msg.content == "Partial answer")      // kept, marked incomplete
    }

    /// Some servers end with a finish reason and no [DONE]: that's a whole reply.
    @Test func aFinishReasonWithoutDoneCompletes() async throws {
        let a = #"data: {"model":"m","choices":[{"index":0,"delta":{"content":"All of it"},"finish_reason":null}]}"#
        let b = #"data: {"model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
        let (client, _) = MockServer.client(.init(chunks: [Data((a + "\n").utf8), Data((b + "\n").utf8)]))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits(maxTokens: 100)) { _ in }
        #expect(msg.meta?.stopReason == .completed)
        #expect(msg.content == "All of it")
    }

    @Test func stopsAtWallClockLimitAndClosesConnection() async throws {
        var route = try MockServer.sse(fixture: "sse_qwen_content")
        route.delay = 0.05                         // ~56 lines → ~2.8 s total
        let (client, host) = MockServer.client(route)
        let msg = await TurnRunner.run(client: client, request: request(),
                                       limits: TurnLimits(wallClock: 0.5)) { _ in }
        #expect(msg.meta?.stopReason == .timedOut)
        #expect((msg.meta?.duration ?? 99) < 1.5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(MockServer.wasCancelled(host))
    }

    @Test func stopsWhenOutputRepeats() async throws {
        let chunk = #"data: {"model":"m","choices":[{"index":0,"delta":{"content":"I will list the directory again. "},"finish_reason":null}]}"#
        let (client, host) = MockServer.client(.init(chunks: [Data((chunk + "\n").utf8)], delay: 0.001, repeatForever: true))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits(wallClock: 10)) { _ in }
        #expect(msg.meta?.stopReason == .repetition)
        #expect(msg.content.hasPrefix("I will list the directory again."))
        try await Task.sleep(for: .milliseconds(200))
        #expect(MockServer.wasCancelled(host))
    }

    @Test func cancellationKeepsPartialOutput() async throws {
        var route = try MockServer.sse(fixture: "sse_qwen_content")
        route.delay = 0.05
        let (client, host) = MockServer.client(route)
        // Cancel once some text has arrived (a fixed wait failed under the full parallel test run).
        final class Seen: @unchecked Sendable { let lock = NSLock(); var text = false }
        let seen = Seen()
        let task = Task {
            await TurnRunner.run(client: client, request: request(), limits: TurnLimits()) { snap in
                if !snap.content.isEmpty { seen.lock.withLock { seen.text = true } }
            }
        }
        for _ in 0..<100 where !seen.lock.withLock({ seen.text }) { try await Task.sleep(for: .milliseconds(50)) }
        task.cancel()
        let msg = await task.value
        #expect(msg.meta?.stopReason == .cancelled)
        #expect(!msg.content.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(MockServer.wasCancelled(host))
    }
}

@Suite struct RepetitionDetectorTests {
    @Test func detectsARepeatedPhrase() {
        var d = RepetitionDetector()
        var fired = false
        for _ in 0..<40 where !fired { fired = d.append("Let me check the file again. ") }
        #expect(fired)
    }

    @Test func detectsARepeatedCharacter() {
        var d = RepetitionDetector()
        var fired = false
        for _ in 0..<100 where !fired { fired = d.append("\n\n\n\n\n\n\n\n") }
        #expect(fired)
    }

    @Test func ignoresOrdinaryTextAndCode() {
        var d = RepetitionDetector()
        let prose = """
        A closure is a function that captures variables from its surrounding scope. In Swift, closures are \
        reference types, so capturing self strongly inside an escaping closure can create a retain cycle. \
        Use a capture list such as [weak self] to break it, and check for nil before use.
        """
        let code = (1...30).map { "    let value\($0) = compute(\($0), scale: \($0 * 3))\n" }.joined()
        let table = "| a | b |\n|---|---|\n" + (1...20).map { "| \($0) | \($0 * $0) |\n" }.joined()
        var fired = false
        for piece in [prose, code, table, prose] { fired = fired || d.append(piece) }
        #expect(!fired)
    }
}
