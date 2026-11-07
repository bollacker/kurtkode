import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

/// The real set (TaskBankReal.swift): tasks read from a `tasks.json` with a `.tgz` fixture each; gold = the test
/// suite passes and no existing test was changed. Checked on a tiny generated project so the test needs no real repository.
@Suite struct TaskBankRealTests {
    /// A Python that has pytest. Gold's shell doesn't read the user's profile (`shell`, BUG_HUNT_2026-11-02.md item
    /// 44), so a bare `python3` is whichever is first on the eval's PATH; the real sets name theirs.
    static let python: String = {
        let candidates = ["python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
            + ((try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/.pyenv/versions")) ?? []).sorted()
                .map { NSHomeDirectory() + "/.pyenv/versions/\($0)/bin/python3" }
        return candidates.first { shell("\(q($0)) -c 'import pytest' 2>/dev/null").status == 0 } ?? "python3"
    }()

    /// `json` with the tests' `"python": "python3"` replaced by `python`.
    static func withPython(_ json: String) -> String {
        json.replacingOccurrences(of: #""python": "python3""#, with: #""python": "\#(python)""#)
    }

    /// A fixtures folder with one task: `src/calc.py` lacks `double`, which `tests/test_calc.py` needs.
    static func fixtures() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "kk-real-\(UUID().uuidString.prefix(6))")
        let src = root.appending(path: "src-of-t1")
        try fm.createDirectory(at: src.appending(path: "src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: src.appending(path: "tests"), withIntermediateDirectories: true)
        try "def add(a, b):\n    return a + b\n".write(to: src.appending(path: "src/calc.py"), atomically: true, encoding: .utf8)
        let test = "import sys, os\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))\nimport calc\n"
            + "def test_double():\n    assert calc.double(4) == 8\n"
        try test.write(to: src.appending(path: "tests/test_calc.py"), atomically: true, encoding: .utf8)
        #expect(shell("cd \(q(src.path)) && tar -czf ../t1.tgz .").status == 0)
        let json = """
        {"python": "python3", "testCommand": "{python} -m pytest -q -p no:cacheprovider tests",
         "tasks": [{"id": "t1", "title": "Add double", "prompt": "Add double(x) to calc.", "maxSteps": 12, "wallClock": 120}]}
        """
        try withPython(json).write(to: root.appending(path: "tasks.json"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func loadsTasksAndGoldNeedsPassingTestsAndUntouchedTests() throws {
        let root = try Self.fixtures()
        defer { try? FileManager.default.removeItem(at: root) }
        let tasks = try TaskBank.loadReal(from: root)
        let task = try #require(tasks.first)
        #expect(tasks.count == 1 && task.id == "t1" && task.maxSteps == 12 && task.wallClock == 120 && task.mayChange.first == "src/" && task.mayChange.contains("tests/"))
        #expect(task.card.verify == "\(Self.python) -m pytest -q -p no:cacheprovider tests")
        let dir = root.appending(path: "run")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(try task.prepare(dir) == "Add double(x) to calc.")
        #expect(shell("git -C \(q(dir.path)) status --porcelain").output.isEmpty, "the fixture is committed clean")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".gitignore").path))
        // Nothing done: the new test fails.
        #expect(!TaskBank.gold(task, dir: dir, report: "", record: RunRecord()).passed)
        // The feature added in src/: passes, and the pytest cache it leaves is ignored.
        try "def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n"
            .write(to: dir.appending(path: "src/calc.py"), atomically: true, encoding: .utf8)
        let good = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(good.passed, "\(good.notes)")
        // A new test file is fine; a test edited to pass is a failure even though the suite passes.
        try "def test_more():\n    assert True\n".write(to: dir.appending(path: "tests/test_more.py"), atomically: true, encoding: .utf8)
        #expect(TaskBank.gold(task, dir: dir, report: "done", record: RunRecord()).passed)
        // A test function appended to an existing file is fine too.
        let appended = try String(contentsOf: dir.appending(path: "tests/test_calc.py"), encoding: .utf8) + "\ndef test_add():\n    assert calc.add(1, 2) == 3\n"
        try appended.write(to: dir.appending(path: "tests/test_calc.py"), atomically: true, encoding: .utf8)
        #expect(TaskBank.gold(task, dir: dir, report: "done", record: RunRecord()).passed)
        // An existing test rewritten: judged by whether the code passes the original tests. With the right code it does
        // (a helper or setup edited along the way); with wrong code behind a weakened test it doesn't.
        try "def test_double():\n    assert True\n".write(to: dir.appending(path: "tests/test_calc.py"), atomically: true, encoding: .utf8)
        let edited = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(edited.passed && edited.notes.contains { $0.contains("with the originals the suite passes") }, "\(edited.notes)")
        // The run's own new tests may need its edit (a helper it added): they're set aside with the originals.
        try "from test_calc import helper\n\ndef test_uses_helper():\n    assert helper() == 1\n"
            .write(to: dir.appending(path: "tests/test_uses.py"), atomically: true, encoding: .utf8)
        try "def helper():\n    return 1\n\ndef test_double():\n    assert True\n".write(to: dir.appending(path: "tests/test_calc.py"), atomically: true, encoding: .utf8)
        let helper = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(helper.passed, "\(helper.notes)")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "tests/test_uses.py").path))
        try "def add(a, b):\n    return a + b\n\ndef double(x):\n    return x\n"
            .write(to: dir.appending(path: "src/calc.py"), atomically: true, encoding: .utf8)
        let cheat = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!cheat.passed && cheat.notes.contains { $0.contains("existing tests kept") && $0.hasPrefix("✗") }, "\(cheat.notes)")
        // The run's own version is back after the check.
        #expect(try String(contentsOf: dir.appending(path: "tests/test_calc.py"), encoding: .utf8).contains("assert True"))
    }

    /// `gradeInSandbox`: gold's suite runs in the command sandbox, so it can't write outside the fixture and temp.
    @Test func aSandboxedSuiteCanWriteOnlyInTheFixture() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "kk-gold-box-\(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let outside = fm.homeDirectoryForCurrentUser.appending(path: "Library/Caches/kk-gold-box-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: outside) }
        let write = "echo x > here.txt && echo x > \(q(outside.path))"
        let boxed = TaskBank.suite(write, in: dir, timeout: 30, sandboxed: true)
        #expect(boxed.status != 0)
        #expect(fm.fileExists(atPath: dir.appending(path: "here.txt").path))
        #expect(!fm.fileExists(atPath: outside.path))
        #expect(TaskBank.suite("exit 3", in: dir, timeout: 30).status == 3)
    }

    @Test func theShippedRealSetsAreConsistentWhenPresent() throws {
        let root = TaskBank.realFixtures
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.appending(path: "tasks.json").path) else { return }
        let folders = [root] + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { fm.fileExists(atPath: $0.appending(path: "tasks.json").path) }
        var all: [String] = []
        for folder in folders {
            let tasks = try TaskBank.loadRealSet(from: folder, defaultName: folder.lastPathComponent).tasks
            #expect(!tasks.isEmpty)
            for t in tasks {
                #expect(fm.fileExists(atPath: folder.appending(path: "\(t.id).tgz").path), "\(t.id) has no fixture (the kurtkode sets' are gitignored: sh spike/real-set-2/build_kk.sh)")
                #expect(!t.summary.isEmpty && t.maxSteps >= 30)
            }
            all += tasks.map(\.id)
        }
        #expect(TaskBank.named(["real"]).map(\.id).sorted() == all.sorted())
        #expect(Set(TaskBank.every.map(\.id)).count == TaskBank.every.count, "task ids are unique across sets")
    }
}

/// `Escalation.asksForChange` on the bank's own prompts, read as a main run's request (no card): it agrees with each
/// task's card, so the "changed no files" reason fires on the change tasks only.
@Suite struct ChangeRequestTests {
    @Test func everyBankPromptReadsAsItsCardSays() throws {
        let change: Set<TaskCard.Kind> = [.edit, .refactor, .fix, .writeTests]
        let top = FileManager.default.temporaryDirectory.appending(path: "kk-asks-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: top) }
        for task in TaskBank.all + TaskBank.hard {
            let dir = top.appending(path: task.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let prompt = try task.prepare(dir)
            #expect(Escalation.asksForChange(prompt) == change.contains(task.card.kind ?? .edit), "\(task.id)")
        }
        // The real-sized sets, from their tasks.json (unpacking the fixtures isn't needed for the prompt).
        struct Entry: Decodable { var id: String; var kind: String?; var prompt: String }
        struct Set_: Decodable { var tasks: [Entry] }
        // This repository's sets, wherever the tests run from.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../eval-results/real-fixtures").standardizedFileURL
        let folders = [root] + ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
        var seen = 0
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: "tasks.json")),
                  let set = try? JSONDecoder().decode(Set_.self, from: data) else { continue }
            for t in set.tasks {
                let kind = t.kind.flatMap(TaskCard.Kind.init(rawValue:)) ?? .edit
                #expect(Escalation.asksForChange(t.prompt) == change.contains(kind), "\(t.id)")
                seen += 1
            }
        }
        #expect(seen >= 21)
    }
}

/// REAL_TASKS_PLAN.md's harness changes: several sets, hidden tests, write-tests and lookup tasks.
@Suite struct RealSetsTests {
    private let fm = FileManager.default

    /// A folder holding `files` (path → text), packed as `name` in `into`.
    private func pack(_ files: [String: String], as name: String, into: URL) throws {
        let src = into.appending(path: "src-of-\(name)")
        for (path, text) in files {
            try fm.createDirectory(at: src.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: src.appending(path: path), atomically: true, encoding: .utf8)
        }
        #expect(shell("cd \(q(src.path)) && tar -czf \(q(into.appending(path: name).path)) .").status == 0)
    }

    private func write(_ text: String, _ path: String, in dir: URL) throws {
        try fm.createDirectory(at: dir.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = path.hasSuffix("tasks.json") ? TaskBankRealTests.withPython(text) : text
        try text.write(to: dir.appending(path: path), atomically: true, encoding: .utf8)
    }

    private let header = "import sys, os\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))\nimport calc\n"

    private func runDir(_ root: URL) throws -> URL {
        let dir = root.appending(path: "run-\(UUID().uuidString.prefix(4))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func setsLoadFromTheTopFolderAndSubfoldersByName() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        let sub = root.appending(path: "kk")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try pack(["README.md": "x\n", ".gitignore": "build/\n"], as: "k1.tgz", into: sub)
        try write(#"""
            {"testCommand": "true", "gitignore": [".build/"], "prepareCommand": "mkdir -p .build && touch .build/made",
             "tasks": [{"id": "k1", "title": "Find it", "prompt": "Where?", "answer": [{"name": "names it", "anyOf": ["x"]}]}]}
            """#, "tasks.json", in: sub)
        let sets = try TaskBank.loadRealSets(from: root)
        #expect(sets.map(\.name) == ["real", "kk"] && sets.map { $0.tasks.map(\.id) } == [["t1"], ["k1"]])
        // The fixture's own .gitignore is kept and added to; the prepare command ran and its output is ignored.
        let dir = try runDir(root)
        _ = try sets[1].tasks[0].prepare(dir)
        #expect(TaskBank.read(dir, ".gitignore") == "build/\n.build/\n")
        #expect(fm.fileExists(atPath: dir.appending(path: ".build/made").path))
        #expect(shell("git -C \(q(dir.path)) status --porcelain").output.isEmpty)
        // A re-grade makes the build again in a restored copy (a `.build` is bound to its folder); a set without one has nothing.
        #expect(sets[1].tasks[0].rebuild == "mkdir -p .build && touch .build/made" && sets[0].tasks[0].rebuild == nil)
        // A failing prepare command fails the fixture.
        try write(#"{"testCommand": "true", "prepareCommand": "exit 3", "tasks": [{"id": "k1", "title": "t", "prompt": "p"}]}"#, "tasks.json", in: sub)
        #expect(throws: (any Error).self) { _ = try TaskBank.loadRealSets(from: root)[1].tasks[0].prepare(try runDir(root)) }
        // Two sets can't share an id.
        try write(#"{"testCommand": "true", "tasks": [{"id": "t1", "title": "t", "prompt": "p"}]}"#, "tasks.json", in: sub)
        #expect(throws: (any Error).self) { _ = try TaskBank.loadRealSets(from: root) }
    }

    @Test func hiddenTestsCountForGoldAndAreGoneAfterwards() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        // The visible test is t1's; the hidden one needs triple, and replaces the visible file with a stricter version.
        try pack(["tests/test_hidden.py": header + "def test_triple():\n    assert calc.triple(2) == 6\n",
                  "tests/test_calc.py": header + "def test_double():\n    assert calc.double(4) == 8\n    assert calc.double(0) == 0\n"],
                 as: "t1-hidden.tgz", into: root)
        try write(#"""
            {"python": "python3", "testCommand": "{python} -m pytest -q -p no:cacheprovider tests",
             "tasks": [{"id": "t1", "title": "Add double and triple", "prompt": "p", "hiddenTests": "t1-hidden.tgz"}]}
            """#, "tasks.json", in: root)
        let task = try #require(try TaskBank.loadReal(from: root).first)
        let dir = try runDir(root)
        _ = try task.prepare(dir)
        try write("def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n", "src/calc.py", in: dir)
        let visibleOnly = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!visibleOnly.passed && visibleOnly.notes.contains { $0.hasPrefix("✗ test suite passes (with the hidden tests)") })
        // The tree is as the run left it: no hidden file, the visible test file unchanged, so the re-run sees the run's suite.
        #expect(!fm.fileExists(atPath: dir.appending(path: "tests/test_hidden.py").path))
        #expect(shell("git -C \(q(dir.path)) status --porcelain").output.trimmingCharacters(in: .whitespacesAndNewlines) == "M src/calc.py")
        try write("def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n\ndef triple(x):\n    return 3 * x\n", "src/calc.py", in: dir)
        let both = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(both.passed, "\(both.notes)")
        #expect(!fm.fileExists(atPath: dir.appending(path: "tests/test_hidden.py").path))
    }

    @Test func aNewTestThatClashesWithTheHiddenTestsIsSetAside() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        // As Swift won't compile two suites of one name, the run's own file fails beside the hidden one that names the
        // same type (here it fails when the hidden file is there, saying what Swift would).
        try pack(["tests/test_hidden.py": header + "class Tripling:\n    pass\n\ndef test_triple():\n    assert calc.triple(2) == 6\n"],
                 as: "t1-hidden.tgz", into: root)
        try write(#"""
            {"python": "python3", "testCommand": "{python} -m pytest -q -p no:cacheprovider tests",
             "tasks": [{"id": "t1", "title": "Add double and triple", "prompt": "p", "hiddenTests": "t1-hidden.tgz"}]}
            """#, "tasks.json", in: root)
        let task = try #require(try TaskBank.loadReal(from: root).first)
        let dir = try runDir(root)
        _ = try task.prepare(dir)
        try write("def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n\ndef triple(x):\n    return 3 * x\n", "src/calc.py", in: dir)
        let mine = "import os\n\nclass Tripling:\n    pass\n\ndef test_mine():\n    assert not os.path.exists(os.path.join(os.path.dirname(__file__), 'test_hidden.py')), "
            + "\"invalid redeclaration of 'Tripling'\"\n"
        try write(mine, "tests/test_mine.py", in: dir)
        let clash = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(clash.passed && clash.notes.contains { $0.contains("tests/test_mine.py declares a type the hidden tests declare") }, "\(clash.notes)")
        #expect(fm.fileExists(atPath: dir.appending(path: "tests/test_mine.py").path))
        // Without a shared name nothing is set aside: the run's failing test fails gold.
        try write(mine.replacingOccurrences(of: "Tripling", with: "Mine"), "tests/test_mine.py", in: dir)
        #expect(!TaskBank.gold(task, dir: dir, report: "done", record: RunRecord()).passed)
        // A shared name, but the suite fails for another reason (the run's own test is wrong): nothing is set aside, so
        // a failing test of the run's can't be removed to let it pass (BUG_HUNT_2026-11-02.md item 48).
        try write("class Tripling:\n    pass\n\ndef test_mine():\n    assert 1 == 2\n", "tests/test_mine.py", in: dir)
        let wrong = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!wrong.passed && !wrong.notes.contains { $0.contains("set aside") }, "\(wrong.notes)")
    }

    @Test func goTestsBesideTheCodeAreKeptAndClashesSetAside() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        let sub = root.appending(path: "go")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        // Go's tests sit beside the code. The check stands in for `go test`: the original test needs the code right, a
        // "loose" one passes anything, and it fails to "compile" when two test files declare TestTriple.
        let check = #"{ grep -q loose pkg/calc_test.go || grep -q right pkg/calc.go; } && "#
            + #"{ [ "$(cat pkg/*_test.go | grep -c '^func TestTriple(')" -le 1 ] || { echo "pkg/triple_test.go:1:6: TestTriple redeclared in this block"; exit 1; }; }"#
        try pack(["pkg/calc.go": "wrong\n", "pkg/calc_test.go": "strict\n", "check.sh": check + "\n"], as: "g1.tgz", into: sub)
        try pack(["pkg/triple_test.go": "func TestTriple(t *testing.T) {}\n"], as: "g1-hidden.tgz", into: sub)
        try write(#"""
            {"testCommand": "sh check.sh", "testsPath": ":(glob)**/*_test.go", "gitignore": [], "mayChange": ["pkg/"],
             "tasks": [{"id": "g1", "title": "t", "prompt": "p", "hiddenTests": "g1-hidden.tgz"}]}
            """#, "tasks.json", in: sub)
        let task = try #require(try TaskBank.loadRealSets(from: root).first { $0.name == "go" }?.tasks.first)
        let dir = try runDir(root)
        _ = try task.prepare(dir)
        // Wrong code behind a weakened test, with a new test file of the run's: the originals catch it, and the run's
        // files are all back afterwards.
        try write("loose\n", "pkg/calc_test.go", in: dir)
        try write("func TestMine(t *testing.T) {}\n", "pkg/mine_test.go", in: dir)
        let cheat = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!cheat.passed, "\(cheat.notes)")
        #expect(TaskBank.read(dir, "pkg/calc_test.go") == "loose\n" && TaskBank.read(dir, "pkg/mine_test.go") == "func TestMine(t *testing.T) {}\n")
        // Right code with the test only edited along the way passes, judged on the originals.
        try write("right\n", "pkg/calc.go", in: dir)
        let edited = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(edited.passed && edited.notes.contains { $0.contains("with the originals the suite passes") }, "\(edited.notes)")
        // A new test file declaring a function the hidden file declares is set aside, then put back.
        try write("strict\n", "pkg/calc_test.go", in: dir)
        try write("func TestTriple(t *testing.T) {}\n", "pkg/mine_test.go", in: dir)
        let clash = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(clash.passed && clash.notes.contains { $0.contains("pkg/mine_test.go declares") }, "\(clash.notes)")
        #expect(fm.fileExists(atPath: dir.appending(path: "pkg/mine_test.go").path))
        #expect(!fm.fileExists(atPath: dir.appending(path: "pkg/triple_test.go").path))
    }

    @Test func writeTestsNeedsNewTestsThatCatchTheBug() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        // The fixture is the fixed code with its old tests; the buggy double is off by one for odd numbers.
        try pack(["src/calc.py": "def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x\n",
                  "tests/test_calc.py": header + "def test_add():\n    assert calc.add(1, 2) == 3\n"], as: "w1.tgz", into: root)
        try pack(["src/calc.py": "def add(a, b):\n    return a + b\n\ndef double(x):\n    return 2 * x + x % 2\n"], as: "w1-buggy.tgz", into: root)
        try write(#"""
            {"python": "python3", "testCommand": "{python} -m pytest -q -p no:cacheprovider tests",
             "tasks": [{"id": "w1", "title": "Test double", "prompt": "p", "kind": "write-tests", "buggy": "w1-buggy.tgz"}]}
            """#, "tasks.json", in: root)
        let task = try #require(try TaskBank.loadReal(from: root).first)
        #expect(task.card.kind == .writeTests && task.agent == "general")
        let dir = try runDir(root)
        _ = try task.prepare(dir)
        let none = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!none.passed && none.notes.contains("✗ tests added"))
        try write(header + "def test_trivial():\n    assert calc.double(2) == 4\n", "tests/test_double.py", in: dir)
        let weak = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(!weak.passed && weak.notes.contains("✗ the tests fail on the code before the fix"), "\(weak.notes)")
        try write(header + "def test_odd():\n    assert calc.double(3) == 6\n", "tests/test_double.py", in: dir)
        let good = TaskBank.gold(task, dir: dir, report: "done", record: RunRecord())
        #expect(good.passed, "\(good.notes)")
        #expect(TaskBank.read(dir, "src/calc.py").contains("return 2 * x\n"), "the fixed code is back after the check")
    }

    @Test func lookupsCheckTheReportsFactsAndChangeNothing() throws {
        let root = try TaskBankRealTests.fixtures()
        defer { try? fm.removeItem(at: root) }
        try write(#"""
            {"python": "python3", "testCommand": "true",
             "tasks": [{"id": "t1", "title": "Where is add", "prompt": "p",
                        "answer": [{"name": "the file", "anyOf": ["src/calc\\.py"]},
                                   {"name": "the function, not the test", "anyOf": ["\\badd\\b"], "noneOf": ["test_add"]}]}]}
            """#, "tasks.json", in: root)
        let task = try #require(try TaskBank.loadReal(from: root).first)
        #expect(task.agent == "explore" && task.card.kind == .search && task.card.verify == nil && task.mayChange.isEmpty)
        let dir = try runDir(root)
        _ = try task.prepare(dir)
        #expect(TaskBank.gold(task, dir: dir, report: "add is defined in SRC/calc.py:1.", record: RunRecord()).passed)
        #expect(!TaskBank.gold(task, dir: dir, report: "add is in src/calc.py, see test_add.", record: RunRecord()).passed)
        try write("x", "notes.txt", in: dir)
        #expect(!TaskBank.gold(task, dir: dir, report: "add is defined in src/calc.py:1.", record: RunRecord()).passed)
    }
}
