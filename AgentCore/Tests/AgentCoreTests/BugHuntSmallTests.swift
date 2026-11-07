import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

/// Bug hunt 2026-11-02, Part 1 item 42: a fork's copies of its original's subagent runs.
@Suite struct BugHuntSmallTests {
    private func store() -> SessionStore {
        SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "bh-small-\(UUID().uuidString)/sessions"))
    }

    /// An original session with one subagent run (and a priced request in the run), and a fork holding a copy of it.
    private func originalAndFork(_ store: SessionStore) async throws -> (original: SessionHeader, fork: SessionHeader, run: SessionHeader) {
        let original = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(original)
        var runHeader = SessionHeader(endpointID: UUID(), model: "m")
        runHeader.parent = original.id
        runHeader.parentCallID = "call_1"
        runHeader.agent = "explore"
        try await store.create(runHeader)
        let fork = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(fork)
        let to = store.subagentDirectory(for: fork)
        try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.subagentDirectory(for: original).appending(path: "\(runHeader.id.uuidString).jsonl"),
                                         to: to.appending(path: "\(runHeader.id.uuidString).jsonl"))
        return (original, fork, runHeader)
    }

    @Test func aForksTotalsLeaveOutTheOriginalsSubagentRuns() async throws {
        let store = store()
        let (original, fork, _) = try await originalAndFork(store)
        let runs = await store.subagentRuns(of: fork)
        #expect(runs.count == 1)                                       // listed, so it can be opened
        func stats(_ h: SessionHeader) async -> SessionStats {
            var s = SessionStats(Session(header: h, messages: [], model: "m"))
            s.add(subagents: await store.subagentRuns(of: h), of: h)
            return s
        }
        #expect(await stats(fork).subagents == 0)
        #expect(await stats(original).subagents == 1)
    }

    @Test func aJudgmentGoesToTheRunFileTheCallerNamesEvenWhenACopyHasTheSameId() async throws {
        let store = store()
        let (original, fork, run) = try await originalAndFork(store)
        let j = RunJudgment(run: run.id, judge: .user, verdict: 3)
        // A fresh store knows no locations: the id alone could mean either file.
        let fresh = SessionStore(root: store.root)
        try await fresh.append(.judgment(j), toRun: run.id, of: fork)
        #expect(await fresh.subagentRun(run.id, of: fork)?.judgments.count == 1)
        #expect(await fresh.subagentRun(run.id, of: original)?.judgments.isEmpty == true)
        let other = SessionStore(root: store.root)
        try await other.append(.judgment(RunJudgment(run: run.id, judge: .user, verdict: 1)), toRun: run.id, of: original)
        #expect(await other.subagentRun(run.id, of: fork)?.judgments.count == 1)
        #expect(await other.subagentRun(run.id, of: original)?.judgments.count == 1)
    }

    @Test func aSubagentRunsReplayCostIsCounted() async throws {
        let store = store()
        let (original, _, run) = try await originalAndFork(store)
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "m", usage: Usage(promptTokens: 100, completionTokens: 10), stopReason: .completed, duration: 1)
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        let cost = CostEntry.make(reply: m, purpose: .replay, run: nil, agent: "replay", client: client, endpointID: UUID(),
                                  start: Date(), price: .unknown("x"))
        let wire = WireRecord(replyID: m.id, startedAt: Date(), duration: 1, url: "https://x", request: .object([:]),
                              statuses: [200], lines: [], linesTruncated: nil, errorBody: nil)
        let record = ReplayRecord(id: UUID(), sourceReply: UUID(), startedAt: Date(), endpointName: "x", endpointID: nil,
                                  options: ReplayOptions(model: "m"), reply: m, wire: wire, warnings: [], cost: cost)
        try Replay.save(record, wire: store.wireDirectory(for: run))
        let entries = try await store.costEntries()
        #expect(entries.count == 1 && entries.first?.session.id == run.id)
        _ = original
    }
}
