import Foundation
import Testing
@testable import AgentCore

private let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)

private func entry(_ model: String, reasoning: String? = nil, ladder: Int? = nil, roles: Set<PoolEntry.Role> = [.subagent]) -> PoolEntry {
    PoolEntry(endpoint: "openrouter", model: model, reasoning: reasoning, tier: .cheap, roles: roles, ladder: ladder)
}

@Suite struct PoolEditingTests {
    @Test func aNewEntryNeedsAnEndpointAModelAndADistinctIdentity() {
        let pool = ModelPool(entries: [entry("a/one"), entry("a/one", reasoning: "none")])
        #expect(pool.problems(entry(""), at: nil) == ["Enter a model."])
        var noEndpoint = entry("x/y")
        noEndpoint.endpoint = " "
        #expect(pool.problems(noEndpoint, at: nil) == ["Choose an endpoint."])
        #expect(pool.problems(entry("a/one"), at: nil) == ["Entry 1 already has this endpoint, model and reasoning."])
        // The same model with another reasoning setting is another entry.
        #expect(pool.problems(entry("a/one", reasoning: "high"), at: nil).isEmpty)
        // Saving an entry over itself isn't a clash.
        #expect(pool.problems(entry("a/one"), at: 0).isEmpty)
        // ...but turning entry 1 into entry 2 is.
        #expect(!pool.problems(entry("a/one", reasoning: "none"), at: 0).isEmpty)
        let claude = PoolEntry(endpoint: "claude", model: "claude-haiku-5-5", tier: .standard, roles: [.judge])
        #expect(pool.problems(claude, at: nil) == ["The Claude endpoint takes haiku, sonnet or opus."])
    }

    @Test func warningsCoverEntriesNothingWouldPick() {
        let pool = ModelPool(entries: [])
        #expect(pool.warnings(entry("a/one"), endpoints: [openRouter]).isEmpty)
        #expect(pool.warnings(entry("a/one", roles: []), endpoints: [openRouter]).contains { $0.contains("no role") })
        #expect(pool.warnings(entry("a/one", ladder: 0, roles: [.judge]), endpoints: [openRouter]).contains { $0.contains("subagent role") })
        #expect(pool.warnings(entry("a/one"), endpoints: []).contains { $0.contains("No endpoint") })
    }

    @Test func putAddsReplacesAndRefusesClashes() throws {
        var pool = ModelPool(entries: [entry("a/one")])
        try pool.put(entry(" a/two "), at: nil, rung: nil)
        #expect(pool.entries.map(\.model) == ["a/one", "a/two"])
        var changed = entry("a/three")
        changed.note = "n"
        try pool.put(changed, at: 0, rung: nil)
        #expect(pool.entries.map(\.model) == ["a/three", "a/two"])
        #expect(pool.entries[0].note == "n")
        #expect(throws: PoolEditError.self) { try pool.put(entry("a/two"), at: nil, rung: nil) }
        #expect(pool.entries.count == 2)
    }

    @Test func rungsStayNumberedInOrderAsEntriesMoveOnAndOff() throws {
        var pool = ModelPool(entries: [entry("a", ladder: 0), entry("b", ladder: 1), entry("c", ladder: 2), entry("d")])
        // d goes in at rung 1 (the second): b and c move up one.
        try pool.put(pool.entries[3], at: 3, rung: 1)
        #expect(pool.entries.map(\.ladder) == [0, 2, 3, 1])
        // a comes off: the rest close up.
        pool.setRung(of: 0, to: nil)
        #expect(pool.entries.map(\.ladder) == [nil, 1, 2, 0])
        // A rung past the end goes to the end.
        pool.setRung(of: 0, to: 99)
        #expect(pool.entries.map(\.ladder) == [3, 1, 2, 0])
        // Removing an entry closes the gap.
        pool.remove(at: 3)
        #expect(pool.entries.map(\.ladder) == [2, 0, 1])
        #expect(pool.rungCount == 3)
    }

    @Test func handWrittenGapsAreClosedOnTheFirstChange() throws {
        var pool = ModelPool(entries: [entry("a", ladder: 5), entry("b", ladder: 2), entry("c")])
        try pool.put(entry("c", ladder: nil), at: 2, rung: nil)
        #expect(pool.entries.map(\.ladder) == [1, 0, nil])
    }

    @Test func movingChangesPoolOrderButNotRungs() {
        var pool = ModelPool(entries: [entry("a", ladder: 0), entry("b"), entry("c", ladder: 1)])
        pool.move(2, by: -1)
        #expect(pool.entries.map(\.model) == ["a", "c", "b"])
        #expect(pool.entries.map(\.ladder) == [0, 1, nil])
        pool.move(0, by: -1)   // already first
        #expect(pool.entries.map(\.model) == ["a", "c", "b"])
    }

    @Test func anUnreadablePoolIsCopiedAsideBeforeItsReplaced() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pool-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "pool.json")
        #expect(try ModelPool.backUpUnreadable(url) == nil)          // none there
        try ModelPool.shipped.save(url)
        #expect(try ModelPool.backUpUnreadable(url) == nil)          // readable
        try Data("{\"entries\": [ {\"endpoint\": \"openrouter\"".utf8).write(to: url)
        let copy = try #require(try ModelPool.backUpUnreadable(url, now: Date(timeIntervalSince1970: 0)))
        #expect(copy.lastPathComponent.hasPrefix("pool.json.unreadable-"))
        #expect(try Data(contentsOf: copy) == Data(contentsOf: url))
    }

    @Test func savedEntriesRoundTripThroughPoolJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pool-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var pool = ModelPool.shipped
        var e = PoolEntry.blank
        e.model = "z-ai/glm-5-air"
        e.roles = [.subagent, .summarizer]
        e.note = "trial"
        try pool.put(e, at: nil, rung: 0)
        let url = dir.appending(path: "pool.json")
        try pool.save(url)
        let (back, problem) = ModelPool.loadChecked(url)
        #expect(problem == nil)
        #expect(back == pool)
        #expect(back.entries.last?.ladder == 0)
        #expect(back.entries.last?.providers?.dataCollection == "deny")
    }
}
