import AgentCore
import Foundation

/// Real-sized tasks (COST_AUDIT.md, experiment P2; REAL_TASKS_PLAN.md): a real repository as it stood before a commit,
/// and the task written from the commit. Each set is a folder with a `tasks.json` and one `<id>.tgz` fixture per task:
/// `eval-results/real-fixtures/` itself (P2's responsedigger set) and each of its subfolders that has a `tasks.json`
/// (`KURTKODE_REAL_FIXTURES` overrides the folder). Tasks can be added without code. `--bank real` runs every set,
/// `--bank real:<set>` one (a subfolder's name; the top folder's set is `real` unless its `name` says otherwise); not
/// part of `all` or `hard`.
///
/// What gold checks depends on the task:
/// - **edit** (the default; also fix, refactor): the test suite passes and no existing test line was removed or
///   changed. With `hiddenTests`, the commit's tests are kept out of the fixture and laid over the run's tree only
///   while gold runs the suite.
/// - **write-tests**: the suite passes, the run added tests and kept the existing ones, and its tests fail when the
///   `buggy` files (the source before the fix) are laid over its tree.
/// - **lookup** (a task with `answer`): every required fact is in the report and no wrong one is; nothing may change.
///
/// Overlays are put back as they were afterwards, so the re-run check and the judges see the tree as the run left it.
extension TaskBank {
    struct RealSet: Decodable {
        struct Entry: Decodable {
            let id: String
            let sha: String?
            let title: String
            let prompt: String
            let maxSteps: Int?
            let wallClock: Double?
            /// The card's kind (`TaskCard.Kind`'s raw value); default edit, or search for a task with an `answer`.
            let kind: String?
            /// Overrides the set's test command (`{python}` is replaced).
            let testCommand: String?
            /// Overrides the set's `mayChange`.
            let mayChange: [String]?
            /// A `.tgz` beside `tasks.json`, extracted over the run's tree while gold runs the suite.
            let hiddenTests: String?
            /// write-tests: a `.tgz` of the files before the fix, extracted over the run's tree to see its tests fail.
            let buggy: String?
            /// A lookup's facts, checked in the report.
            let answer: [Fact]?
        }
        /// One fact a lookup's report must state: any of `anyOf` matches, none of `noneOf` does (regular expressions,
        /// any case).
        struct Fact: Decodable {
            let name: String
            let anyOf: [String]
            let noneOf: [String]?
        }
        /// The set's name for `--bank real:<name>`; default: its folder's name (`real` for the top folder).
        let name: String?
        /// The interpreter the tests need (the fixture's dependencies must already be installed for it).
        let python: String?
        /// Run in the fixture root; `{python}` is replaced. Also the card's verify command.
        let testCommand: String
        /// Where the repository's tests are, for "existing tests kept"; default `tests`.
        let testsPath: String?
        /// Run in each fixture after it's unpacked, outside the sandbox, before the run's clock starts (a cold
        /// `swift build`); a failure fails the fixture.
        let prepareCommand: String?
        /// Lines added to the fixture's own `.gitignore`; without it the fixture's `.gitignore` is replaced by
        /// Python's caches (P2's set).
        let gitignore: [String]?
        /// The paths edit tasks may change; default P2's.
        let mayChange: [String]?
        /// Seconds the suite may run when gold checks it; default 900.
        let checkTimeout: Int?
        /// Gold runs the suite in the command sandbox (`SandboxPolicy()`: no network, writes only in the fixture and
        /// temp), as the model's own runs are: for third-party repositories, whose code the user allows to run only
        /// there. Default false (the user's own repositories, P2's behavior).
        let gradeInSandbox: Bool?
        let tasks: [Entry]
    }

    /// `KURTKODE_REAL_FIXTURES` (from the working folder), else the repository's `eval-results/real-fixtures`
    /// (`EvalPaths.root`, so `swift run` from AgentCore/ finds them too).
    public static var realFixtures: URL {
        if let path = ProcessInfo.processInfo.environment["KURTKODE_REAL_FIXTURES"] {
            return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        }
        return EvalPaths.root.appending(path: "eval-results/real-fixtures")
    }

    /// Every real set, or nothing when there's no `tasks.json` where the process runs from.
    public static var real: [BankTask] { (try? loadRealSets(from: realFixtures).flatMap(\.tasks)) ?? [] }

    /// One real set by name, or nothing.
    public static func real(set name: String) -> [BankTask] {
        ((try? loadRealSets(from: realFixtures)) ?? []).first { $0.name == name }?.tasks ?? []
    }

    /// The top folder's set (if it has a `tasks.json`) and each subfolder's, in name order. Task ids must be unique
    /// across sets: a run's record names its task, not its set.
    static func loadRealSets(from root: URL) throws -> [(name: String, tasks: [BankTask])] {
        let fm = FileManager.default
        var sets: [(name: String, tasks: [BankTask])] = []
        if fm.fileExists(atPath: root.appending(path: "tasks.json").path) {
            sets.append(try loadRealSet(from: root, defaultName: "real"))
        }
        let subfolders = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { fm.fileExists(atPath: $0.appending(path: "tasks.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for folder in subfolders { sets.append(try loadRealSet(from: folder, defaultName: folder.lastPathComponent)) }
        var seen = Set<String>()
        for t in sets.flatMap(\.tasks) where !seen.insert(t.id).inserted {
            throw NSError(domain: "TaskBankReal", code: 1, userInfo: [NSLocalizedDescriptionKey: "task id \(t.id) is in two real sets"])
        }
        return sets
    }

    /// The top folder's set alone (P2's layout).
    static func loadReal(from root: URL) throws -> [BankTask] { try loadRealSet(from: root, defaultName: "real").tasks }

    static func loadRealSet(from root: URL, defaultName: String) throws -> (name: String, tasks: [BankTask]) {
        let set = try JSONDecoder().decode(RealSet.self, from: Data(contentsOf: root.appending(path: "tasks.json")))
        func expand(_ command: String) -> String { command.replacingOccurrences(of: "{python}", with: set.python ?? "python3") }
        let testsPath = set.testsPath ?? "tests"
        let timeout = set.checkTimeout ?? 900
        let boxed = set.gradeInSandbox ?? false
        let tasks = try set.tasks.map { e -> BankTask in
            let lookup = e.answer != nil
            guard let kind = TaskCard.Kind(rawValue: e.kind ?? (lookup ? "search" : "edit")) else {
                throw NSError(domain: "TaskBankReal", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(e.id): unknown kind \(e.kind ?? "")"])
            }
            let readOnly: Set<TaskCard.Kind> = [.search, .explain, .summarize, .research, .review]
            let test = expand(e.testCommand ?? set.testCommand)
            let tgz = root.appending(path: "\(e.id).tgz")
            let hidden = e.hiddenTests.map { root.appending(path: $0) }
            let buggy = e.buggy.map { root.appending(path: $0) }
            let mayChange = e.mayChange ?? (readOnly.contains(kind) ? []
                : set.mayChange ?? ["src/", "tests/", "docs/", "README.md", "HANDOFF.md", "DESIGN.md"])
            return BankTask(
                id: e.id, summary: e.title, agent: readOnly.contains(kind) ? "explore" : "general",
                card: TaskCard(kind: kind, importance: .normal, verify: lookup ? nil : test),
                maxSteps: e.maxSteps ?? 50, wallClock: e.wallClock ?? 1800, mayChange: mayChange, rebuild: set.prepareCommand,
                prepare: { dir in
                    // A set's interpreter that isn't on this Mac fails the fixture (an infrastructure failure), not
                    // every run's suite as the model's.
                    if let python = set.python, python.hasPrefix("/"), !FileManager.default.isExecutableFile(atPath: python) {
                        throw NSError(domain: "TaskBankReal", code: 3, userInfo: [NSLocalizedDescriptionKey: "the set's python \(python) isn't here"])
                    }
                    try Fixtures.untar(tgz, into: dir)
                    let ignore = dir.appending(path: ".gitignore")
                    if let extra = set.gitignore {
                        let own = (try? String(contentsOf: ignore, encoding: .utf8)) ?? ""
                        let text = (own.isEmpty || own.hasSuffix("\n") ? own : own + "\n") + extra.joined(separator: "\n") + "\n"
                        try Data(text.utf8).write(to: ignore)
                    } else {
                        try Data("__pycache__/\n*.pyc\n.pytest_cache/\n*.egg-info/\n.coverage\n".utf8).write(to: ignore)
                    }
                    if let command = set.prepareCommand {
                        let r = shell("cd \(q(dir.path)) && \(command) 2>&1")
                        guard r.status == 0 else {
                            throw NSError(domain: "TaskBankReal", code: Int(r.status),
                                          userInfo: [NSLocalizedDescriptionKey: "prepare failed: " + String(r.output.suffix(500))])
                        }
                    }
                    try Fixtures.commitAll(dir)
                    return e.prompt
                },
                check: { dir, report, _ in
                    if let facts = e.answer { return lookupResult(facts, report: report) }
                    // A test edited to pass is a failure; added tests, in new files or existing ones, are fine. When the
                    // run changed existing test lines (a helper given a parameter, a setup extended), its code must pass
                    // the original tests folder, with the hidden tests and without the run's own new tests, which may
                    // need its helper changes (the user's decision, 2026-10-28; before, any changed line failed).
                    let edited = editedTests(dir, testsPath)
                    var run = withOverlay(hidden, in: dir) { suite(test, in: dir, timeout: timeout, sandboxed: boxed) }
                    // A new test file of the run's that declares a type the hidden tests declare too (both name the suite
                    // after the feature) stops the tests compiling, whatever the code does: it is set aside and the suite
                    // run again, as the run's own new tests are for the edited-tests check. Only when the compiler said
                    // so: a suite that fails for another reason keeps the run's tests (a run's own failing test isn't
                    // removed to let it pass).
                    var clashNote: String?
                    if run.status != 0, let hidden, redeclared(run.output) {
                        let clashing = clashingNewTests(dir, testsPath, hidden)
                        if !clashing.isEmpty {
                            run = withAside(clashing, in: dir) { withOverlay(hidden, in: dir) { suite(test, in: dir, timeout: timeout, sandboxed: boxed) } }
                            clashNote = "the run's \(clashing.joined(separator: ", ")) declares a type the hidden tests declare; set aside, the suite "
                                + (run.status == 0 ? "passes" : "still fails")
                        }
                    }
                    var kept = true, keptNote: String?
                    if !edited.isEmpty {
                        let originals = withOriginalTests(testsPath, in: dir) { withOverlay(hidden, in: dir) { suite(test, in: dir, timeout: timeout, sandboxed: boxed) } }
                        kept = originals.status == 0
                        keptNote = "existing tests changed (\(edited.joined(separator: ", "))); with the originals the suite "
                            + (kept ? "passes" : "fails: " + String(originals.output.suffix(200)))
                    }
                    var parts = [("test suite passes" + (hidden == nil ? "" : " (with the hidden tests)"), run.status == 0),
                                 ("existing tests kept", kept)]
                    if kind == .writeTests, let buggy {
                        let added = changedPaths(dir).contains { $0.hasPrefix(testsPath) }
                        let caught = withOverlay(buggy, in: dir) { suite(test, in: dir, timeout: timeout, sandboxed: boxed) }
                        parts += [("tests added", added), ("the tests fail on the code before the fix", added && caught.status != 0)]
                    }
                    var r = result(parts)
                    if let keptNote { r.notes.append(keptNote) }
                    if let clashNote { r.notes.append(clashNote) }
                    r.notes.append("suite: " + suiteNote(run.output))
                    return r
                },
                checkTimeout: timeout)
        }
        return (set.name ?? defaultName, tasks)
    }

    /// Runs `ARGV[1...]` in a process group of its own and ends the whole group when it exits or after `ARGV[0]`
    /// seconds: a suite's children (a server, a `while True`) can't outlive it or keep gold's pipe open. A timeout
    /// prints a line gold's note keeps and exits 124.
    static let groupTimeout = #"""
        my $t = shift; my $pid = fork; die "fork: $!" unless defined $pid;
        if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127 }
        setpgrp($pid, $pid);
        $SIG{ALRM} = sub { kill 'KILL', -$pid; print "\n[gold: the suite timed out after ${t}s]\n"; exit 124 };
        alarm $t; waitpid($pid, 0); my $s = $?; alarm 0; kill 'KILL', -$pid;
        exit($s & 127 ? 128 + ($s & 127) : $s >> 8);
        """#

    /// The suite, with a time limit and its process group ended afterwards (`groupTimeout`); its exit status, not
    /// tail's. `sandboxed`: inside the command sandbox, with the fixture as the workspace (`gradeInSandbox`).
    static func suite(_ test: String, in dir: URL, timeout: Int, sandboxed: Bool = false) -> (status: Int32, output: String) {
        var argv = ["/usr/bin/perl", "-e", groupTimeout, "--", "\(timeout)", "/bin/zsh", "-f", "-c", test]
        if sandboxed {
            let add = SandboxPolicy.cacheVariables(for: ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
            argv = SandboxPolicy().wrap((add.isEmpty ? [] : ["/usr/bin/env"] + add) + argv, workspace: dir, tag: "kkgold")
        }
        return shell("cd \(q(dir.path)) && \(argv.map(q).joined(separator: " ")) 2>&1")
    }

    /// The fixture's files under `testsPath` with a line removed or changed since its base commit (`Fixtures.base`:
    /// a run's own commits count), deleted files included. A removed line shows as "-" in the diff (not the "---"
    /// header).
    static func editedTests(_ dir: URL, _ testsPath: String) -> [String] {
        let base = Fixtures.base(dir)
        return shell("git -C \(q(dir.path)) -c core.quotePath=false diff \(base) --name-only --no-renames --diff-filter=MD -- \(q(testsPath))")
            .output.split(separator: "\n").map(String.init).filter { file in
                shell("git -C \(q(dir.path)) diff \(base) -- \(q(file))").output.split(separator: "\n")
                    .contains { $0.hasPrefix("-") && !$0.hasPrefix("---") }
            }
    }

    /// Whether a suite's output says a name is declared twice (Go's "redeclared in this block", Swift's "invalid
    /// redeclaration"): the only failure that setting the run's clashing tests aside can fix.
    static func redeclared(_ output: String) -> Bool {
        output.range(of: #"redeclared in this block|invalid redeclaration of"#, options: .regularExpression) != nil
    }

    /// Gold's note on the suite: the lines that name a failure (Go's `--- FAIL`, `FAIL`, `panic:` and a stack overflow,
    /// compiler errors at `file:line:col:`, pytest's `FAILED` and `ERROR`, Swift Testing's `✘`, a gold timeout), up to
    /// 20 of them, then the output's last 300 characters. Before 2026-11-03 only the tail was kept, which often didn't
    /// name the test that failed.
    static func suiteNote(_ output: String) -> String {
        let re = try! NSRegularExpression(pattern: #"^\s*(--- FAIL|FAIL\b|panic:|fatal error:|runtime: goroutine stack exceeds|FAILED\b|ERROR\b|✘|\[gold:)"#
            + #"|^\S+\.\w+:\d+:\d+: (error: )?"#)
        let failing = output.split(separator: "\n").map(String.init).filter { line in
            re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        let tail = String(output.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !failing.isEmpty else { return tail }
        let shown = failing.prefix(20).map { $0.count > 200 ? String($0.prefix(200)) + "…" : $0 }
        return "failing: " + shown.joined(separator: "\n") + (failing.count > 20 ? "\n(\(failing.count - 20) more)" : "")
            + "\n… " + tail
    }

    /// The run's new files under `testsPath` that declare a type (struct, class, enum, actor) a file in `hidden` declares,
    /// or a top-level Go function or type: Go won't compile a package that declares one twice.
    static func clashingNewTests(_ dir: URL, _ testsPath: String, _ hidden: URL) -> [String] {
        func types(_ text: String) -> Set<String> {
            let re = try! NSRegularExpression(pattern: #"\b(?:struct|class|enum|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#
                + #"|(?m)^(?:func|type)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
            return Set(re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
                (Range(m.range(at: 1), in: text) ?? Range(m.range(at: 2), in: text)).map { String(text[$0]) }
            })
        }
        let theirs = types(shell("tar -xzOf \(q(hidden.path))").output)
        guard !theirs.isEmpty else { return [] }
        return shell("git -C \(q(dir.path)) -c core.quotePath=false ls-files --others --exclude-standard -- \(q(testsPath))").output
            .split(separator: "\n").map(String.init).filter { file in
                let text = (try? String(contentsOf: dir.appending(path: file), encoding: .utf8)) ?? ""
                return !types(text).isDisjoint(with: theirs)
            }
    }

    /// `body` with `files` moved out of `dir`, then put back.
    static func withAside<T>(_ files: [String], in dir: URL, _ body: () -> T) -> T {
        let fm = FileManager.default
        let backup = fm.temporaryDirectory.appending(path: "kk-aside-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: backup) }
        var moved: [String] = []
        for f in files {
            let to = backup.appending(path: f)
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: dir.appending(path: f), to: to)) != nil { moved.append(f) }
        }
        let value = body()
        for f in moved { try? fm.moveItem(at: backup.appending(path: f), to: dir.appending(path: f)) }
        return value
    }

    /// `body` with the tests as the fixture's base commit has them (`Fixtures.base`: the run's changes, new files and
    /// own commits set aside), then the run's files put back. Works file by file, so `testsPath` may be a folder or a
    /// git pathspec with magic (`:(glob)**/*_test.go`, Go's tests beside the code). git's index is left as the run left
    /// it (the checkout goes through a copy of it).
    static func withOriginalTests<T>(_ testsPath: String, in dir: URL, _ body: () -> T) -> T {
        let fm = FileManager.default
        let base = Fixtures.base(dir)
        let git = "git -C \(q(dir.path)) -c core.quotePath=false"
        let changed = shell("\(git) diff --name-only --no-renames \(base) -- \(q(testsPath))").output
            + "\n" + shell("\(git) ls-files --others --exclude-standard -- \(q(testsPath))").output
        let paths = Array(Set(changed.split(separator: "\n").map(String.init))).sorted()
        let backup = fm.temporaryDirectory.appending(path: "kk-originals-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: backup) }
        for p in paths where fm.fileExists(atPath: dir.appending(path: p).path) {
            try? fm.createDirectory(at: backup.appending(path: p).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: dir.appending(path: p), to: backup.appending(path: p))
        }
        for p in paths { try? fm.removeItem(at: dir.appending(path: p)) }
        let index = fm.temporaryDirectory.appending(path: "kk-index-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: index) }
        let own = shell("\(git) rev-parse --git-path index").output.trimmingCharacters(in: .whitespacesAndNewlines)
        try? fm.copyItem(at: URL(fileURLWithPath: own, relativeTo: dir), to: index)
        _ = shell("GIT_INDEX_FILE=\(q(index.path)) \(git) checkout \(base) -- \(q(testsPath)) 2>/dev/null")
        let value = body()
        for p in paths {
            try? fm.removeItem(at: dir.appending(path: p))
            try? fm.createDirectory(at: dir.appending(path: p).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: backup.appending(path: p), to: dir.appending(path: p))   // fails for a file the run deleted
        }
        return value
    }

    /// `body` with `tgz` extracted over `dir`, then each file it overwrote put back and each it added removed.
    static func withOverlay<T>(_ tgz: URL?, in dir: URL, _ body: () -> T) -> T {
        guard let tgz else { return body() }
        let fm = FileManager.default
        let members = shell("tar -tzf \(q(tgz.path))").output.split(separator: "\n").map { m in
            m.hasPrefix("./") ? String(m.dropFirst(2)) : String(m)
        }.filter { !$0.isEmpty && !$0.hasSuffix("/") }
        let backup = fm.temporaryDirectory.appending(path: "kk-overlay-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: backup) }
        var saved = Set<String>()
        for m in members where fm.fileExists(atPath: dir.appending(path: m).path) {
            let to = backup.appending(path: m)
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.copyItem(at: dir.appending(path: m), to: to)) != nil { saved.insert(m) }
        }
        _ = shell("tar -xzf \(q(tgz.path)) -C \(q(dir.path))")
        let value = body()
        for m in members {
            try? fm.removeItem(at: dir.appending(path: m))
            if saved.contains(m) { try? fm.moveItem(at: backup.appending(path: m), to: dir.appending(path: m)) }
        }
        return value
    }

    /// A lookup's gold: each fact stated, none stated wrongly.
    static func lookupResult(_ facts: [RealSet.Fact], report: String) -> CheckResult {
        func found(_ patterns: [String]) -> Bool {
            patterns.contains { report.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
        }
        return result(facts.map { f in (f.name, found(f.anyOf) && !found(f.noneOf ?? [])) })
    }
}
