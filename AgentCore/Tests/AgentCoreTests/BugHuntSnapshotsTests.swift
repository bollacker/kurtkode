import Foundation
import Testing
@testable import AgentCore

// BUG_HUNT_2026-11-02.md items 17 (kurtkode's own restores counted as the user's edits), 18 (a rewind deleting a file
// that was there before the run; nested repositories never captured; a crashed first run's base), 21 (worktree removal
// losing ignored files) and 22 (a worktree's command rewriting the main repository's objects).

private func temp(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "kk-bhs-\(name)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Outside the temp folders: the sandbox lets commands write those, so a repository there couldn't show what it blocks.
private func scratch(_ file: String = #filePath) throws -> URL {
    let base = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/kk-bhs-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.resolvingSymlinksInPath()
}

@discardableResult
private func sh(_ command: String, in dir: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.currentDirectoryURL = dir
    var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    env["GIT_AUTHOR_NAME"] = "t"; env["GIT_AUTHOR_EMAIL"] = "t@t"; env["GIT_COMMITTER_NAME"] = "t"; env["GIT_COMMITTER_EMAIL"] = "t@t"
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

private func write(_ text: String, _ rel: String, in dir: URL) throws {
    let url = dir.appending(path: rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func read(_ rel: String, in dir: URL) -> String? {
    (try? Data(contentsOf: dir.appending(path: rel))).map { String(decoding: $0, as: UTF8.self) }
}

/// A git project with a committed file and an ignored one.
private func gitProject() throws -> URL {
    let p = try temp("proj")
    try write("one\ntwo\nthree\n", "a.txt", in: p)
    try write(".env\n", ".gitignore", in: p)
    try write("SECRET=1\n", ".env", in: p)
    try sh("git init -q && git add -A && git commit -qm init", in: p)
    return p
}

private func sandboxed(_ command: String, in root: URL) async -> ToolOutput {
    let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(["command": .string(command)])), as: UTF8.self)
    var config = AgentConfig(tools: [BashTool()])
    config.sandbox = SandboxPolicy()
    return await AgentLoop.execute(ToolCall(id: "t", name: "bash", arguments: json), tools: ["bash": BashTool()],
                                   config: config, workspace: Workspace(root: root))
}

/// A session of main runs on a project, each a shell command between a start and an end snapshot, with its record.
private struct Runs {
    let p: URL, snaps: ProjectSnapshots, session = UUID(), checkpoints: CheckpointStore
    var messages: [ChatMessage] = [], runs: [AgentRunRecord] = []

    init() throws {
        p = try gitProject()
        snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        checkpoints = CheckpointStore(directory: try temp("cp"))
    }

    /// One request answered by one run; `record` false: the run crashed after its end snapshot, before its record.
    @discardableResult
    mutating func turn(_ text: String, _ work: String, record: Bool = true, end: Bool = true) async throws -> ChatMessage {
        let m = ChatMessage.user(text)
        var r = AgentRunRecord.test(agent: "main", started: Date().addingTimeInterval(Double(runs.count)))
        r.userMessage = m.id
        let s = try await snaps.take(session: session, turn: m.id, run: r.id, phase: .start)
        try sh(work, in: p)
        var e: ProjectSnapshots.Snapshot?
        if end { e = try await snaps.take(session: session, turn: m.id, run: r.id, phase: .end) }
        r.snapshots = RunSnapshotRefs(start: s.commit, end: e?.commit, skipped: [])
        messages += [m, ChatMessage(role: .assistant, content: "did " + text)]
        if record { runs.append(r) }
        return m
    }

    func plan(to m: ChatMessage) async -> RewindPlan {
        await RewindPlan.make(target: m.id, messages: messages, runs: runs, snapshots: snaps, session: session, checkpoints: checkpoints)
    }
}

@Suite struct BugHuntRewindTests {
    /// 17: two runs edit a.txt; a files-only rewind of the second is kurtkode's doing, not the user's, so a rewind of the
    /// first still restores a.txt (to the first run's start).
    @Test func aFilesOnlyRewindIsNotTheUsersEdit() async throws {
        var t = try Runs()
        try await t.turn("one", "echo r1 > a.txt")
        let two = try await t.turn("two", "echo r2 > a.txt")
        let three = try await t.turn("three", "echo r3 > a.txt")
        let p3 = await t.plan(to: three)
        #expect(p3.files.map { ($0 as NSString).lastPathComponent } == ["a.txt"] && p3.session == t.session)
        _ = try await p3.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(read("a.txt", in: t.p) == "r2\n")
        #expect(try await t.snaps.list(session: t.session).last?.phase == .restore)
        let p2 = await t.plan(to: two)
        #expect(p2.keptUserEdits.isEmpty, "\(p2.keptUserEdits)")
        #expect(p2.files.map { ($0 as NSString).lastPathComponent } == ["a.txt"])
        _ = try await p2.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(read("a.txt", in: t.p) == "r1\n")
    }

    /// 17: the Changes tab's revert by file and by hunk are recorded too; a hand edit between is still the user's.
    @Test func changesTabRevertsAreRecordedAndHandEditsStillKept() async throws {
        var t = try Runs()
        let one = try await t.turn("one", "echo r1 > a.txt && echo b > b.txt")
        let two = try await t.turn("two", "printf 'x\\ny\\n' > a.txt && echo b2 > b.txt")
        let list = try await t.snaps.list(session: t.session)
        let start = list.first { $0.phase == .start && $0.turn == two.id }!
        // Revert b.txt whole, then one hunk of a.txt, as the tab does.
        _ = try await t.snaps.restore(["b.txt"], to: start.commit, session: t.session)
        let change = try await t.snaps.changes(session: t.session, from: start.commit, to: nil).first { $0.path == "a.txt" }!
        let hunks = UnifiedDiff.split(try await t.snaps.patch(session: t.session, from: start.commit, to: nil, change: change)).hunks
        try await t.snaps.revertHunk(session: t.session, from: start.commit, change: change, hunk: hunks[0])
        #expect(read("a.txt", in: t.p) == "r1\n" && read("b.txt", in: t.p) == "b\n")
        #expect(try await t.snaps.list(session: t.session).suffix(2).allSatisfy { $0.phase == .restore })
        // The user edits b.txt by hand now: theirs.
        try write("mine\n", "b.txt", in: t.p)
        let plan = await t.plan(to: one)
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == ["a.txt"])
        #expect(plan.keptUserEdits.map { ($0 as NSString).lastPathComponent } == ["b.txt"])
    }

    /// 18 (area D): the first run of a request crashed after its end snapshot, before its record: the base is still its
    /// start, from the chain, and its changes rewind.
    @Test func aCrashedFirstRunsStartIsTheBase() async throws {
        var t = try Runs()
        let one = try await t.turn("one", "echo crashed > a.txt && echo c > c.txt", record: false)
        // The continuation: a second run of the same request, recorded.
        var r = AgentRunRecord.test(agent: "main", started: Date().addingTimeInterval(5))
        r.userMessage = one.id
        let s = try await t.snaps.take(session: t.session, turn: one.id, run: r.id, phase: .start)
        try sh("echo cont > a.txt", in: t.p)
        let e = try await t.snaps.take(session: t.session, turn: one.id, run: r.id, phase: .end)
        r.snapshots = RunSnapshotRefs(start: s.commit, end: e.commit, skipped: [])
        t.runs.append(r)
        let plan = await t.plan(to: one)
        #expect(plan.coversCommands)
        #expect(plan.base == (try await t.snaps.list(session: t.session).first?.commit))
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == ["a.txt", "c.txt"] && plan.keptUserEdits.isEmpty)
        _ = try await plan.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(read("a.txt", in: t.p) == "one\ntwo\nthree\n" && !FileManager.default.fileExists(atPath: t.p.appending(path: "c.txt").path))
    }

    /// 18 (area D): a run whose end snapshot is missing (it crashed before it) isn't covered: the checkpoints then.
    @Test func aRunWithoutAnEndIsNotCovered() async throws {
        var t = try Runs()
        let one = try await t.turn("one", "echo crashed > a.txt", record: false, end: false)
        try await t.turn("two", "echo r2 > a.txt")
        let plan = await t.plan(to: one)
        #expect(!plan.coversCommands)
        #expect(plan.summary(.files, root: t.p.path).contains("Changes made by commands can't be undone"))
    }

    /// 18: a run stops ignoring `.env`, so the end snapshot has it and the start doesn't; the diff calls it added, but a
    /// rewind or revert must not delete the user's file.
    @Test func aFileThatWasIgnoredBeforeTheRunIsNotDeleted() async throws {
        var t = try Runs()
        let one = try await t.turn("one", "echo r1 > a.txt && : > .gitignore && echo NEW=2 >> .env")
        let list = try await t.snaps.list(session: t.session)
        let changes = try await t.snaps.changes(session: t.session, from: list[0].commit, to: list[1].commit)
        #expect(changes.first { $0.path == ".env" }?.kind == .added)
        let plan = await t.plan(to: one)
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == [".gitignore", "a.txt"])
        #expect(plan.keptOutside.map { ($0 as NSString).lastPathComponent } == [".env"])
        #expect(plan.summary(.both, root: t.p.path).contains("outside the snapshots (ignored by git then): .env"))
        _ = try await plan.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(read(".env", in: t.p) == "SECRET=1\nNEW=2\n" && read("a.txt", in: t.p) == "one\ntwo\nthree\n")
        // The Changes tab's "Delete File" on it: left alone, with a note.
        try sh("echo r1 > a.txt", in: t.p)
        await #expect(throws: ProjectSnapshots.Failure.self) {
            try await t.snaps.restore([".env", "a.txt"], to: list[0].commit, session: t.session)
        }
        #expect(read(".env", in: t.p) == "SECRET=1\nNEW=2\n" && read("a.txt", in: t.p) == "one\ntwo\nthree\n")
        // A file the run really added is still deleted.
        try sh("echo new > d.txt", in: t.p)
        _ = try await t.snaps.restore(["d.txt"], to: list[0].commit, session: t.session)
        #expect(!FileManager.default.fileExists(atPath: t.p.appending(path: "d.txt").path))
    }

    /// 18: repositories inside the project (a clone, a submodule) are named as not captured instead of left out silently.
    @Test func nestedRepositoriesAreListedAsSkipped() async throws {
        let p = try gitProject(), snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        try sh("mkdir -p vendor/lib && cd vendor/lib && git init -q && echo l > l.txt && git add . && git commit -qm l", in: p)
        try sh("git -c protocol.file.allow=always submodule add -q ./vendor/lib sub 2>/dev/null && git commit -qm sub", in: p)
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        #expect(s.skipped.contains("vendor/lib/ (nested repository)") && s.skipped.contains("sub/ (nested repository)"), "\(s.skipped)")
        let tree = try await snaps.shadow(["ls-tree", "-r", "--name-only", s.tree])
        #expect(!tree.contains("l.txt"))
    }
}

@Suite struct BugHuntWorktreeRemovalTests {
    private func repo(in base: URL) throws -> GitRepo {
        let d = base.appending(path: "project")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try sh("git init -q -b main && git config user.email t@t && git config user.name t && echo one > a.txt && echo .env > .gitignore "
               + "&& git add . && git commit -qm first", in: d)
        return GitRepo(root: d)
    }

    /// 21: ignored files count as lost too, and a change that keeps the counts is still a change.
    @Test func removalNamesIgnoredFilesAndSeesAChangedSet() async throws {
        let base = try temp("wt"); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        try sh("echo SECRET=1 > .env && mkdir data && echo d > data/db.sqlite && echo new > c.txt", in: dir)
        try write("data/\n", ".git/info/exclude", in: r.root)
        let told = try await r.worktreeState(w)
        #expect(told.uncommittedFiles == ["c.txt"] && told.ignoredFiles == [".env", "data/"] && told.unmerged == 0, "\(told)")
        #expect(told.lostNames() == "c.txt, .env, data/")
        // Without force, the ignored files are named instead of deleted.
        await #expect(throws: GitRepo.Failure.self) { try await r.removeWorktree(w) }
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".env").path))
        // Same counts, different files: asked again.
        try sh("rm c.txt && echo other > e.txt", in: dir)
        let now = try await r.removeWorktree(w, told: told, deleteBranch: false)
        #expect(now?.uncommittedFiles == ["e.txt"])
        #expect(FileManager.default.fileExists(atPath: w.path))
        #expect(try await r.removeWorktree(w, told: now!, deleteBranch: false) == nil)
        #expect(!FileManager.default.fileExists(atPath: w.path))
    }
}

@Suite struct BugHuntWorktreeObjectsTests {
    private func repo(in base: URL) throws -> GitRepo {
        let d = base.appending(path: "project")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try sh("git init -q -b main && git config user.email t@t && git config user.name t && echo one > a.txt && echo keep > b.txt "
               + "&& git add . && git commit -qm first", in: d)
        return GitRepo(root: d)
    }

    /// 22: a worktree's command can commit (new loose objects), but not replace, remove or rename what main's objects
    /// hold, nor add a pack or an alternates file; main's contents stay what they were.
    @Test func aWorktreeCommandCannotRewriteMainsObjects() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        let objects = r.root.appending(path: ".git/objects").path
        let blob = try sh("git rev-parse HEAD:a.txt", in: r.root).trimmingCharacters(in: .whitespacesAndNewlines)
        let object = "\(objects)/\(blob.prefix(2))/\(blob.dropFirst(2))"
        let folder = "\(objects)/\(blob.prefix(2))"
        // Commits work, of new content and of content main already has.
        var out = await sandboxed("echo two >> a.txt && cp b.txt c.txt && git add . && git -c user.email=t@t -c user.name=t commit -qm wt && git log --oneline | wc -l", in: dir)
        #expect(!out.isError && out.text.contains("2"), "\(out.text)")
        for attempt in ["echo evil > \(object)", "truncate -s 0 \(object)", "rm \(object)", "chmod 644 \(object)",
                        "echo evil > \(folder)/tmp_obj_evil && mv -f \(folder)/tmp_obj_evil \(object)",
                        "mv \(folder) \(objects)/zz", "ln \(object) \(dir.path)/alias && echo evil > \(dir.path)/alias",
                        "ln -s /etc/passwd \(folder)/0000000000000000000000000000000000000000",
                        "echo /tmp > \(objects)/info/alternates", "git repack -q"] {
            out = await sandboxed(attempt, in: dir)
            #expect(out.isError || out.text.lowercased().contains("operation not permitted") || out.text.contains("The sandbox blocked"), "\(attempt): \(out.text)")
        }
        #expect(try sh("git cat-file -p \(blob)", in: r.root) == "one\n")
        #expect(FileManager.default.fileExists(atPath: object) && !FileManager.default.fileExists(atPath: "\(objects)/info/alternates"))
        #expect(try sh("git count-objects -v | grep '^packs'", in: r.root).contains("packs: 0"))
        #expect(try sh("git fsck 2>&1 | grep -v dangling", in: r.root).isEmpty)
        // And main can still merge what the worktree committed.
        try sh("git merge -q --no-edit kk/x", in: r.root)
        #expect(read("a.txt", in: r.root) == "one\ntwo\n" && read("c.txt", in: r.root) == "keep\n")
    }
}
