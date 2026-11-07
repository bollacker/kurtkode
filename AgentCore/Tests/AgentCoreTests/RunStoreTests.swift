import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

/// Record once, judge many (EVAL_PLAN.md E1–E3): statistics, degradations, and the run store end to end.
@Suite struct RunStoreTests {
    @Test func wilsonAndKappa() throws {
        let w = try #require(Stats.wilson(5, 10))
        #expect(abs(w.lo - 0.237) < 0.001 && abs(w.hi - 0.763) < 0.001)
        #expect(Stats.wilson(0, 0) == nil && Stats.rate(0, 0) == "–")
        #expect(Stats.rate(10, 10).hasPrefix("100% (72–100%)"))
        #expect(Stats.kappa([(true, true), (false, false), (true, true), (false, false)]) == 1)
        let k = try #require(Stats.kappa([(true, true), (true, false), (false, true), (false, false)]))
        #expect(abs(k) < 1e-9)                                     // agreement no better than chance
    }

    private func fixture(_ id: String) throws -> (BankTask, URL) {
        let task = try #require(TaskBank.all.first { $0.id == id })
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-deg-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try task.prepare(dir)
        return (task, dir)
    }

    @Test func eachDegradationMakesAGoodRunFail() throws {
        // A right fix-calc (two hunks), then each degradation of it: gold must fail.
        let (task, dir) = try fixture("fix-calc")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try TaskBankTests.oracle("fix-calc", dir)
        #expect(TaskBank.gold(task, dir: dir, report: report, record: RunRecord()).passed)
        for kind in [Degradation.undoHalf, .undoAll, .strayEdit] {
            let copy = FileManager.default.temporaryDirectory.appending(path: "kk-degc-\(UUID().uuidString.prefix(6))")
            defer { try? FileManager.default.removeItem(at: copy) }
            #expect(shell("cp -R \(q(dir.path)) \(q(copy.path))").status == 0)
            let bad = try #require(Degradation.apply(kind, report: report, dir: copy), "\(kind) didn't apply")
            #expect(!TaskBank.gold(task, dir: copy, report: bad, record: RunRecord()).passed, "\(kind) still passes")
        }
        // Half undone: one of the two fixes is left.
        let half = FileManager.default.temporaryDirectory.appending(path: "kk-degh-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: half) }
        _ = shell("cp -R \(q(dir.path)) \(q(half.path))")
        _ = Degradation.apply(.undoHalf, report: report, dir: half)
        let calc = TaskBank.read(half, "calc.py")
        #expect(calc.contains("return a - b") != !calc.contains("len(values) - 1"))
        // Nothing to vanish (no new file); a list to halve.
        #expect(Degradation.apply(.vanish, report: report, dir: dir) == nil)
        #expect(Degradation.dropHalf("- a.py: X\n- b.py: Y\n- c.py: Z\n- d.py: W") == "- a.py: X\n- c.py: Z")
        #expect(Degradation.dropHalf("Just one line about a.py") == nil)
    }

    @Test func wrongFileSwapsPathsAndNames() throws {
        let (task, dir) = try fixture("find-reserve-def")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try TaskBankTests.oracle("find-reserve-def", dir)
        let bad = try #require(Degradation.apply(.wrongFile, report: report, dir: dir))
        #expect(bad != report && !bad.contains("storage.py"))
        #expect(!TaskBank.gold(task, dir: dir, report: bad, record: RunRecord()).passed)
        #expect(Degradation.apply(.digits, report: report, dir: dir) != report)
    }

    /// Record a run (and its degraded copies) from a mock subagent, judge them from the store with a mock judge,
    /// and report: the whole E1 loop without a real model.
    @Test func recordJudgeAndReport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-runs-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RunStore(root: root)
        let task = try #require(TaskBank.all.first { $0.id == "find-reserve-def" })
        let (client, _) = MockServer.client(.init(turns: [SSE.content("reserve_stock is at inventory/storage.py:\(Fixtures.reserveStockLine).")]))
        let target = ModelTarget(endpoint: Endpoint(name: "M", kind: .openai, baseURL: client.baseURL), model: "sub", contextLength: 32_768)
        let recorded = await Runner.recordBank(task, on: target, trial: 1, store: store, degrade: true,
                                               makeClient: { ChatClient(baseURL: $0.endpoint.baseURL, session: MockServer.session) })
        #expect(recorded.first?.gold.passed == true)
        #expect(Set(recorded.compactMap(\.degradation)) == ["digits", "wrong-file", "stray-edit"])
        #expect(recorded.dropFirst().allSatisfy { !$0.gold.passed && $0.parent == recorded.first?.id })
        #expect(store.runs().count == 4)

        // The stray edit is in the stored fixture, and only there.
        let stray = try #require(store.runs().first { $0.degradation == "stray-edit" })
        let restored = try store.restore(stray)
        defer { try? FileManager.default.removeItem(at: restored) }
        #expect(TaskBank.read(restored, "README.md").contains("Edited outside the task."))
        #expect(TaskBank.gold(task, dir: restored, report: stray.report, record: RunRecord()).passed == false)

        // A judge rates every stored run; verdicts are appended and kept.
        let verdicts = (0..<4).map { i in SSE.toolCall("g\(i)", "rate_task", #"{"task":"x","verdict":\#(i == 0 ? 3 : 0),"checked":"spot-checked"}"#) }
        let (judgeClient, _) = MockServer.client(.init(turns: verdicts))
        let judge = ModelTarget(endpoint: Endpoint(name: "J", kind: .openai, baseURL: judgeClient.baseURL), model: "judge", contextLength: 32_768)
        for run in store.runs().sorted(by: { ($0.degradation ?? "") < ($1.degradation ?? "") }) {
            let o = await Runner.judgeStored(run, store: store, judge: judge, path: "grader",
                                             makeClient: { ChatClient(baseURL: $0.endpoint.baseURL, session: MockServer.session) })
            #expect(o?.verdict != nil)
        }
        #expect(store.runs().allSatisfy { store.judgments(of: $0.id).count == 1 })
        let md = EvalReport.markdown(store)
        // The stray edit of a read-only task is left out (explore agents can't edit).
        #expect(md.contains("Runs: 1 recorded, 2 degraded copies; 3 judgments. (1 stray-edit copies of read-only tasks left out"))
        #expect(md.contains("| j:judge (grader) | 3 | 0 |"))
        #expect(md.contains("failures caught"))
    }

    @Test func aReviewSeesOnlyTheRunsOwnChange() throws {
        // The fixture as the run started (its first commit), then a model commit, an edit, a new file and an ignored
        // build folder: the diff has the commit's and the edit's change and the new file, not the ignored folder.
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-own-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appending(path: ".build"), withIntermediateDirectories: true)
        try Data("a = 1\n".utf8).write(to: dir.appending(path: "a.py"))
        try Data(".build/\n".utf8).write(to: dir.appending(path: ".gitignore"))
        try Fixtures.commitAll(dir)
        try Data("a = 2\n".utf8).write(to: dir.appending(path: "a.py"))
        #expect(shell("cd \(q(dir.path)) && git -c user.email=m@m -c user.name=m commit -qam model").status == 0)
        try Data("a = 3\n".utf8).write(to: dir.appending(path: "a.py"))
        try Data("b = 1\n".utf8).write(to: dir.appending(path: "b.py"))
        try Data("binary".utf8).write(to: dir.appending(path: ".build/x.o"))
        let d = try #require(ReviewSim.ownDiff(dir))
        #expect(d.contains("-a = 1") && d.contains("+a = 3") && !d.contains("+a = 2"))
        #expect(d.contains("+++ b/b.py") && !d.contains(".build"))
        // A fixture of two commits (the eval's "fixture", then "broken" adding the bug): a run that fixed the bug
        // changed the file, though the tree matches the first commit again.
        let two = FileManager.default.temporaryDirectory.appending(path: "kk-two-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: two) }
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        let eval = "git -c user.name=eval -c user.email=eval@example.com"
        try Data("total = a + b\n".utf8).write(to: two.appending(path: "calc.py"))
        #expect(shell("cd \(q(two.path)) && git init -q && git add -A && \(eval) commit -qm fixture").status == 0)
        try Data("total = a - b\n".utf8).write(to: two.appending(path: "calc.py"))
        #expect(shell("cd \(q(two.path)) && \(eval) commit -qam broken").status == 0)
        try Data("total = a + b\n".utf8).write(to: two.appending(path: "calc.py"))
        let fixed = try #require(ReviewSim.ownDiff(two))
        #expect(fixed.contains("-total = a - b") && fixed.contains("+total = a + b"))
        // No history: nil, and the caller falls back to a fresh fixture.
        let bare = FileManager.default.temporaryDirectory.appending(path: "kk-bare-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: bare) }
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        #expect(ReviewSim.ownDiff(bare) == nil)
    }
}
