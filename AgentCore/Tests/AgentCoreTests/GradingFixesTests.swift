import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

/// The eval harness's grading fixes from BUG_HUNT_2026-11-02.md's P3 (items 43–49) and the gold note that names the
/// failing tests (2026-11-03).
@Suite struct GradingFixesTests {
    private let fm = FileManager.default

    private func write(_ text: String, _ path: String, in dir: URL) throws {
        try fm.createDirectory(at: dir.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: dir.appending(path: path), atomically: true, encoding: .utf8)
    }

    private func commit(_ dir: URL, _ message: String) {
        #expect(shell("cd \(q(dir.path)) && git add -A && git -c user.name=m -c user.email=m@example.com -c commit.gpgsign=false commit -qm \(q(message))").status == 0)
    }

    /// Item 43: a run that commits its own work is judged on it. Before, every check diffed against the current HEAD,
    /// so committed work looked like no change: a stray file passed, and a weakened test went unseen.
    @Test func aRunThatCommitsItsWorkIsJudgedOnIt() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        let task = try #require(try TaskBank.loadReal(from: root).first)
        let dir = root.appending(path: "run")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try task.setUp(dir)
        #expect(shell("git -C \(q(dir.path)) rev-parse -q --verify \(Fixtures.baseRef)").status == 0)

        // The right fix, committed: it counts as the run's change, and gold passes.
        try write("def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n", "src/calc.py", in: dir)
        commit(dir, "add double")
        #expect(TaskBank.changedPaths(dir) == ["src/calc.py"])
        let good = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(good.passed, "\(good.notes)")

        // A committed file outside what the task may change fails gold.
        try write("x\n", "notes.txt", in: dir)
        commit(dir, "notes")
        let stray = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!stray.passed && stray.notes.contains { $0.contains("changed outside the task") && $0.contains("notes.txt") }, "\(stray.notes)")
        #expect(shell("cd \(q(dir.path)) && git rm -q notes.txt").status == 0)
        commit(dir, "drop notes")

        // Wrong code behind a weakened test, both committed: the originals (from the base, not HEAD) catch it.
        try write("def add(a, b):\n    return a + b\n\ndef double(x):\n    return x\n", "src/calc.py", in: dir)
        try write("def test_double():\n    assert True\n", "tests/test_calc.py", in: dir)
        commit(dir, "weaken")
        #expect(TaskBank.editedTests(dir, "tests") == ["tests/test_calc.py"])
        let cheat = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!cheat.passed && cheat.notes.contains { $0.hasPrefix("✗ existing tests kept") }, "\(cheat.notes)")
        // The tree and git's index are as the run left them.
        #expect(shell("git -C \(q(dir.path)) status --porcelain").output.isEmpty)
        #expect(TaskBank.read(dir, "tests/test_calc.py") == "def test_double():\n    assert True\n")
    }

    /// Gold's note names the failing tests, not just the output's last 300 characters (the Go round's flake on
    /// 2026-11-03 couldn't be traced from the tail).
    @Test func goldsNoteNamesTheFailingTests() {
        let output = (["ok  \tpkg/a\t0.1s", "--- FAIL: TestEncoders (0.01s)", "    enc_test.go:12: wrong order", "FAIL\tpkg/b\t0.2s"]
                      + (0..<40).map { "ok  \tpkg/c\($0)\t0.1s" }).joined(separator: "\n")
        let note = TaskBank.suiteNote(output)
        #expect(note.contains("--- FAIL: TestEncoders") && note.contains("FAIL\tpkg/b"), "\(note)")
        #expect(note.contains("ok  \tpkg/c39"), "the tail is kept too")
        #expect(TaskBank.suiteNote("ok  \tpkg/a\t0.1s") == "ok  \tpkg/a\t0.1s")
        #expect(TaskBank.suiteNote("ext/lists.go:330:45: cannot use x").hasPrefix("failing: ext/lists.go:330:45:"))
        #expect(TaskBank.suiteNote("FAILED tests/test_x.py::test_y - assert 1 == 2").hasPrefix("failing: FAILED tests/test_x.py"))
        #expect(TaskBank.suiteNote("runtime: goroutine stack exceeds 1000000000-byte limit\nFAIL\tpkg").hasPrefix("failing: runtime: goroutine stack exceeds"))
    }

    /// Item 44: gold's suite runs in a process group of its own. A timeout ends the whole group (before, `perl alarm`
    /// killed only the shell, and a child kept the pipe open), and children still running after the suite exits are
    /// ended too.
    @Test func aSuiteThatHangsIsStoppedWithItsChildren() throws {
        let dir = fm.temporaryDirectory.appending(path: "kk-suite-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        var start = Date()
        let hung = TaskBank.suite("sleep 30 & sleep 30", in: dir, timeout: 1)
        #expect(hung.status == 124 && hung.output.contains("[gold: the suite timed out after 1s]"), "\(hung)")
        #expect(Date().timeIntervalSince(start) < 10)
        start = Date()
        let leftover = TaskBank.suite("(sleep 30 &); echo done", in: dir, timeout: 60)
        #expect(leftover.status == 0 && leftover.output.contains("done"))
        #expect(Date().timeIntervalSince(start) < 10, "a child left running doesn't hold gold")
        #expect(TaskBank.suite("exit 3", in: dir, timeout: 60).status == 3)
    }

    /// Item 46: a fixture that can't be made is an infrastructure failure, and the model isn't called. Item 47: a save
    /// that fails leaves no run behind.
    @Test func aFixtureThatCantBeMadeIsInfraAndTheModelIsntCalled() async throws {
        let root = fm.temporaryDirectory.appending(path: "kk-runs-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: root) }
        let store = RunStore(root: root)
        let task = BankTask(id: "broken", summary: "s", agent: "general", card: TaskCard(kind: .fix, importance: .normal),
                            prepare: { _ in throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "no fixture"]) },
                            check: { _, _, _ in CheckResult(passed: false, score: 0, notes: []) })
        final class Called: @unchecked Sendable { var n = 0 }
        let called = Called()
        let target = ModelTarget(endpoint: Endpoint(name: "M", kind: .openai, baseURL: URL(string: "http://127.0.0.1:9")!), model: "m",
                                 contextLength: 32_768)
        let start = Date()
        let runs = await Runner.recordBank(task, on: target, trial: 1, store: store, config: "fp",
                                           makeClient: { t in called.n += 1; return ChatClient(baseURL: t.endpoint.baseURL) })
        let run = try #require(runs.first)
        #expect(called.n == 0, "the model's client wasn't made")
        #expect(run.infra?.hasPrefix("fixture setup failed: ") == true && run.infra?.contains("no fixture") == true, "\(run.infra ?? "")")
        #expect(run.steps == 0 && run.config == "fp")
        #expect(Date().timeIntervalSince(start) < 15, "no retry after a pause")

        var other = run
        other.id = "never-saved"
        #expect(throws: (any Error).self) { try store.save(other, fixture: root.appending(path: "no-such-folder")) }
        #expect(!fm.fileExists(atPath: root.appending(path: "never-saved/run.json").path))
        #expect(!fm.fileExists(atPath: root.appending(path: "never-saved/fixture.tgz.partial").path))
        #expect(store.runs().map(\.id) == [run.id])
    }

    /// Item 48: the re-run check gets the task's time limit, and one that runs out is recorded as not finished, not
    /// as a failure.
    @Test func aRecheckThatRunsOutOfTimeIsNotAFailure() async throws {
        let dir = fm.temporaryDirectory.appending(path: "kk-recheck-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func task(_ verify: String, _ timeout: Int?) -> BankTask {
            BankTask(id: "slow", summary: "s", agent: "general", card: TaskCard(kind: .fix, importance: .normal, verify: verify),
                     prepare: { _ in "" }, check: { _, _, _ in CheckResult(passed: true, score: 1, notes: []) }, checkTimeout: timeout)
        }
        let config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: dir))
        let slow = try #require(await Runner.recheck(task("sleep 20", 1), config: config, dir: dir))
        #expect(slow.ran && slow.exit == nil && slow.timedOut)
        let failing = try #require(await Runner.recheck(task("exit 2", 30), config: config, dir: dir))
        #expect(failing.ran && failing.exit == 2 && !failing.timedOut)
    }

    /// Item 49: fixture git commands that fail throw; unknown task ids are reported; one cost-per-pass formula; the
    /// eval's folders are anchored at the repository's top.
    @Test func smallerHarnessFixes() throws {
        let empty = fm.temporaryDirectory.appending(path: "kk-git-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: empty) }
        #expect(throws: (any Error).self) { try Fixtures.commitAll(empty) }   // nothing to commit

        #expect(TaskBank.unknown(["fix-calc", "no-such-task"]) == ["no-such-task"])
        #expect(TaskBank.unknown(["all"]).isEmpty && TaskBank.unknown(["hard"]).isEmpty)
        #expect(TaskBank.unknown(["real:no-such-set"]) == ["real:no-such-set"])

        #expect(fm.fileExists(atPath: EvalPaths.root.appending(path: "AgentCore/Package.swift").path), "\(EvalPaths.root.path)")
    }

    @Test func oneCostPerPassFormula() throws {
        func run(_ passed: Bool, _ price: Double?) -> StoredRun {
            StoredRun(id: UUID().uuidString, task: "t", kind: "fix", agent: "general", card: TaskCard(kind: .fix, importance: .normal),
                      model: "m", trial: 1, prompt: "", report: "", checks: GroundedChecks.evaluate(messages: [], report: "", stop: nil,
                      maxSteps: 1, workspace: Workspace(root: fm.temporaryDirectory), verify: nil), rechecked: false,
                      gold: CheckResult(passed: passed, score: passed ? 1 : 0, notes: []), stop: "none", seconds: 1, steps: 1,
                      toolCalls: 0, promptTokens: 0, completionTokens: 0, listPrice: price, unpricedRequests: 0, recordedAt: Date(),
                      transcript: [])
        }
        // Two runs, one priced at $1 and passing, one unpriced: the unpriced run counts at the mean, so a pass costs $2
        // in both the frontier and the models table (before, the table said $1).
        let rs = [run(true, 1.0), run(false, nil)]
        #expect(EvalReport.perSuccess(rs) == 2.0)
        #expect(EvalReport.frontier(rs).first?.perSuccess == 2.0)
    }
}
