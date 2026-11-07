import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit
@testable import KurtkodeCLI

// Phase 3 of GAP_ANALYSIS.md (review and cost, part 2): C1 task diff and revert, C3 rewind options, A6 cross-vendor
// review, A4 the cheap-first cascade, A7 kurtkode-initiated delegation.

private func temp(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "kk-p3-\(name)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
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

/// A git project with a committed file, an ignored file and an ignored folder.
private func gitProject() throws -> URL {
    let p = try temp("proj")
    try write("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\n", "a.txt", in: p)
    try write("secret.log\nout/\n", ".gitignore", in: p)
    try write("x", "secret.log", in: p)
    try write("built", "out/app.bin", in: p)
    try sh("git init -q && git add -A && git commit -qm init", in: p)
    return p
}

@Suite struct SnapshotTests {
    @Test func catchesWhatCommandsChangeWithoutTouchingTheProjectsRepository() async throws {
        let p = try gitProject(), root = try temp("snaps")
        let snaps = ProjectSnapshots(project: p, root: root)
        let session = UUID(), turn = UUID()
        let start = try await snaps.take(session: session, turn: turn, run: nil, phase: .start)
        // A command edits, adds, deletes and renames; an ignored file changes too.
        try sh("sed -i '' 's/two/TWO/' a.txt && echo new > b.txt && echo y >> secret.log && git mv a.txt c.txt 2>/dev/null || mv a.txt c.txt", in: p)
        let end = try await snaps.take(session: session, turn: turn, run: nil, phase: .end)
        let changes = try await snaps.changes(session: session, from: start.commit, to: end.commit)
        #expect(changes.map(\.path) == ["b.txt", "c.txt"])
        #expect(changes.first { $0.path == "c.txt" }?.kind == .renamed)
        #expect(changes.first { $0.path == "c.txt" }?.oldPath == "a.txt")
        #expect(changes.first { $0.path == "c.txt" }?.additions == 1)
        #expect(changes.first { $0.path == "b.txt" }?.kind == .added)
        // The project's own repository has no new refs or index entries; its status is the command's doing only.
        #expect(try sh("git for-each-ref", in: p).split(separator: "\n").count == 1)
        #expect(!FileManager.default.fileExists(atPath: p.appending(path: ".git/refs/sessions").path))
        let listed = try await snaps.list(session: session)
        #expect(listed.map(\.phase) == [.start, .end])
        #expect(listed.first?.turn == turn)
    }

    @Test func revertsAFileAndAHunk() async throws {
        let p = try gitProject(), root = try temp("snaps")
        let snaps = ProjectSnapshots(project: p, root: root)
        let session = UUID()
        let start = try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        try sh("sed -i '' 's/^two$/TWO/; s/^eleven$/ELEVEN/' a.txt && echo new > b.txt", in: p)
        let changes = try await snaps.changes(session: session, from: start.commit, to: nil)
        let a = try #require(changes.first { $0.path == "a.txt" })
        let patch = try await snaps.patch(session: session, from: start.commit, to: nil, change: a)
        let hunks = UnifiedDiff.split(patch).hunks
        #expect(hunks.count == 2)
        try await snaps.revertHunk(session: session, from: start.commit, change: a, hunk: hunks[1])
        #expect(read("a.txt", in: p)?.contains("ELEVEN") == false)
        #expect(read("a.txt", in: p)?.contains("TWO") == true)
        // A hunk that's no longer there: refused, nothing changed.
        await #expect(throws: (any Error).self) { try await snaps.revertHunk(session: session, from: start.commit, change: a, hunk: hunks[1]) }
        let restored = try await snaps.restore(["a.txt", "b.txt"], to: start.commit)
        #expect(restored.count == 2 && restored.contains { $0.deleted })
        #expect(read("a.txt", in: p)?.contains("two\n") == true)
        #expect(!FileManager.default.fileExists(atPath: p.appending(path: "b.txt").path))
        #expect(try await snaps.changes(session: session, from: start.commit, to: nil).isEmpty)
    }

    @Test func leavesOutBigUntrackedFoldersAndFiles() async throws {
        let p = try gitProject(), root = try temp("snaps")
        var snaps = ProjectSnapshots(project: p, root: root)
        snaps.limits.untrackedFolderFiles = 5
        snaps.limits.fileBytes = 1000
        for i in 0..<8 { try write("o\(i)", "junk/f\(i).o", in: p) }
        try write(String(repeating: "x", count: 2000), "big.dat", in: p)
        try write("kept", "small/keep.txt", in: p)
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        #expect(s.skipped.contains { $0.hasPrefix("junk/") })
        #expect(s.skipped.contains { $0.hasPrefix("big.dat") })
        let files = try await snaps.shadow(["ls-tree", "-r", "--name-only", s.tree])
        #expect(files.contains("small/keep.txt") && files.contains("a.txt") && !files.contains("junk/") && !files.contains("secret.log"))
        // The skipped list survives the trip through the commit message.
        let listed = try await snaps.list(session: s.session)
        #expect(listed.first?.skipped == s.skipped)
    }

    @Test func worksInASubfolderOfARepository() async throws {
        let top = try gitProject()
        try write("inner\n", "sub/i.txt", in: top)
        try sh("git add -A && git commit -qm sub", in: top)
        let p = top.appending(path: "sub")
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let session = UUID()
        let start = try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        let files = try await snaps.shadow(["ls-tree", "-r", "--name-only", start.tree])
        #expect(files.trimmed == "i.txt")
        try write("inner\nmore\n", "i.txt", in: p)
        let c = try #require(try await snaps.changes(session: session, from: start.commit, to: nil).first)
        let only = UnifiedDiff.split(try await snaps.patch(session: session, from: start.commit, to: nil, change: c)).hunks[0]
        try await snaps.revertHunk(session: session, from: start.commit, change: c, hunk: only)
        #expect(read("i.txt", in: p) == "inner\n")
    }

    @Test func foldersThatArentRepositories() async throws {
        let p = try temp("plain"), root = try temp("snaps")
        try write("print(1)\n", "main.py", in: p)
        try write("dep", "node_modules/x/index.js", in: p)
        try write("c", "__pycache__/m.pyc", in: p)
        var snaps = ProjectSnapshots(project: p, root: root)
        let session = UUID()
        let start = try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        let files = try await snaps.shadow(["ls-tree", "-r", "--name-only", start.tree])
        #expect(files.trimmed == "main.py")
        try write("print(2)\n", "main.py", in: p)
        #expect(try await snaps.changes(session: session, from: start.commit, to: nil).map(\.path) == ["main.py"])
        // Past the size cap: no snapshot, and a reason.
        snaps.limits.folderFiles = 1
        try write("x", "other.py", in: p)
        await #expect(throws: ProjectSnapshots.Failure.self) { try await snaps.take(session: session, turn: nil, run: nil, phase: .end) }
    }

    @Test func sessionsAreSeparateAndDroppable() async throws {
        let p = try gitProject(), root = try temp("snaps")
        let snaps = ProjectSnapshots(project: p, root: root)
        let s1 = UUID(), s2 = UUID()
        try await snaps.take(session: s1, turn: nil, run: nil, phase: .start)
        try await snaps.take(session: s2, turn: nil, run: nil, phase: .start)
        try await snaps.take(session: s2, turn: nil, run: nil, phase: .end)
        #expect(try await snaps.list(session: s1).count == 1)
        #expect(try await snaps.list(session: s2).count == 2)
        try await snaps.prune(olderThan: 3600, now: Date().addingTimeInterval(7200))
        #expect(try await snaps.list(session: s1).isEmpty)
        #expect(!ProjectSnapshots.allowed(FileManager.default.homeDirectoryForCurrentUser))
        #expect(ProjectSnapshots.allowed(p))
    }
}

@Suite struct SnapshotRangeTests {
    private func snap(_ phase: ProjectSnapshots.Snapshot.Phase, turn: UUID, run: UUID, _ t: Double) -> ProjectSnapshots.Snapshot {
        .init(commit: "\(phase)\(t)", tree: "", session: UUID(), turn: turn, run: run, phase: phase, date: Date(timeIntervalSince1970: t), skipped: [])
    }

    @Test func picksTheScopesSnapshots() {
        let t1 = UUID(), t2 = UUID(), r1 = UUID(), r2 = UUID(), r3 = UUID()
        let list = [snap(.start, turn: t1, run: r1, 1), snap(.end, turn: t1, run: r1, 2),
                    snap(.start, turn: t1, run: r2, 3), snap(.end, turn: t1, run: r2, 4),     // a Continue of turn 1
                    snap(.start, turn: t2, run: r3, 5)]                                       // still running
        #expect(ProjectSnapshots.range(list, .session).map { [$0.from.commit, $0.to?.commit ?? "now"] } == ["start1.0", "now"])
        #expect(ProjectSnapshots.range(list, .lastRun).map { [$0.from.commit, $0.to?.commit ?? "now"] } == ["start5.0", "now"])
        #expect(ProjectSnapshots.range(list, .turn(t1)).map { [$0.from.commit, $0.to?.commit ?? "now"] } == ["start1.0", "end4.0"])
        #expect(ProjectSnapshots.range(Array(list.prefix(2)), .lastRun).map { [$0.from.commit, $0.to?.commit ?? "now"] } == ["start1.0", "end2.0"])
        #expect(ProjectSnapshots.range([], .session) == nil)
    }

    @Test func knowsWhenAFileChangedSinceASnapshot() async throws {
        let p = try gitProject()
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .end)
        #expect(try await snaps.unchanged("a.txt", since: s.commit))
        #expect(try await snaps.unchanged("nothere.txt", since: s.commit))
        try write("changed\n", "a.txt", in: p)
        try write("new\n", "nothere.txt", in: p)
        #expect(!(try await snaps.unchanged("a.txt", since: s.commit)))
        #expect(!(try await snaps.unchanged("nothere.txt", since: s.commit)))
    }
}

@Suite struct RunSnapshotTests {
    @Test func aMainRunRecordsItsSnapshotsAndACommandsChange() async throws {
        let p = try gitProject()
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"sed -i '' 's/two/TWO/' a.txt"}"#),
            SSE.content("Done."),
        ]))
        let session = UUID(), turn = UUID()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: p))
        config.costScope = CostScope(run: UUID(), agent: "main", userMessage: turn)
        config.snapshots = RunSnapshots(store: snaps, session: session, turn: turn)
        final class Box: @unchecked Sendable { var run: AgentRunRecord? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Capitalize two")], config: config,
                            workspace: Workspace(root: p)) { if case .runEnded(let r) = $0 { box.run = r } }
        let refs = try #require(box.run?.snapshots)
        let end = try #require(refs.end)
        #expect(refs.changed == true)
        #expect(try await snaps.changes(session: session, from: refs.start, to: end).map(\.path) == ["a.txt"])
        let listed = try await snaps.list(session: session)
        #expect(listed.map(\.phase) == [.start, .end] && listed.allSatisfy { $0.turn == turn && $0.run == box.run?.id })
    }

    @Test func aFailedSnapshotIsANoticeOnceNotTheRunsEnd() async throws {
        let p = try temp("plain")
        try write("x", "a.py", in: p)
        try write("y", "b.py", in: p)
        var snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        snaps.limits.folderFiles = 1
        let (client, _) = MockServer.client(.init(turns: [SSE.content("Hi.")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: p))
        config.snapshots = RunSnapshots(store: snaps, session: UUID(), turn: UUID())
        final class Box: @unchecked Sendable { var notices: [String] = []; var run: AgentRunRecord?; var stop: AgentStop? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Hi")], config: config,
                            workspace: Workspace(root: p)) { e in
            switch e {
            case .hookNotice(let t): box.notices.append(t)
            case .runEnded(let r): box.run = r
            case .finished(let s): box.stop = s
            default: break
            }
        }
        #expect(box.stop == .completed)
        #expect(box.run?.snapshots == nil)
        #expect(box.notices.count == 1 && box.notices[0].contains("too large"))
    }
}

@Suite struct DiffReportTests {
    @Test func listsFilesThenTheDiff() async throws {
        let p = try gitProject()
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let session = UUID(), run = UUID()
        #expect(try await snaps.report(session: session, scope: .lastRun).hasPrefix("No snapshots"))
        try await snaps.take(session: session, turn: nil, run: run, phase: .start)
        try sh("echo more >> a.txt && echo n > n.txt", in: p)
        try await snaps.take(session: session, turn: nil, run: run, phase: .end)
        let r = try await snaps.report(session: session, scope: .lastRun)
        #expect(r.hasPrefix("The latest run changed 2 files:\n  modified a.txt  +1 −0\n  added    n.txt  +1 −0\n\ndiff --git"))
        try sh("echo later > l.txt", in: p)
        let s = try await snaps.report(session: session, scope: .session, maxBytes: 0)
        #expect(s.hasPrefix("This session changed 3 files (up to now):"))
        #expect(s.contains("(cut;"))
    }
}

@Suite struct LocalEndpointNameTests {
    @Test func theAppsNameForTheLocalServerWorksInTheCLI() throws {
        // The default endpoint is a keyed one, as on this Mac: a name it doesn't know must not fall through to it.
        let support = try temp("support")
        let keyed = Endpoint(name: "Keyed", kind: .anthropic, baseURL: URL(string: "http://keyed.invalid/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([keyed])
        let defaults = try #require(UserDefaults(suiteName: "kk-p3-\(UUID().uuidString.prefix(8))"))
        defaults.set(keyed.id.uuidString, forKey: "defaultEndpointID")
        let settings = AppSettings(support: support, defaults: defaults, environment: [:])
        for spec in ["This Mac:qwen/qwen3-coder-30b", "This Mac (LM Studio):qwen/qwen3-coder-30b", "lmstudio:qwen/qwen3-coder-30b"] {
            let (e, m) = CLIOptions.splitModel(spec, settings: settings)
            #expect(e.id == Endpoint.localLMStudio.id && m == "qwen/qwen3-coder-30b")
        }
    }
}

@Suite struct RewindTests {
    /// Two requests: A's run changes a.txt by command; the user then edits b.txt by hand; B's run changes b.txt and adds
    /// c.txt.
    private func twoTurns() async throws -> (p: URL, snaps: ProjectSnapshots, session: UUID, messages: [ChatMessage],
                                              runs: [AgentRunRecord], checkpoints: CheckpointStore) {
        let p = try gitProject()
        try write("b1\n", "b.txt", in: p)
        try sh("git add -A && git commit -qm b", in: p)
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let session = UUID()
        let a = ChatMessage.user("Do A"), b = ChatMessage.user("Do B")
        var runs: [AgentRunRecord] = []
        for (i, (turn, work)) in [(a, "sed -i '' 's/two/TWO/' a.txt"), (b, "echo b3 > b.txt && echo c > c.txt")].enumerated() {
            if i == 1 { try write("b2 by hand\n", "b.txt", in: p) }
            var r = AgentRunRecord.test(agent: "main", started: Date().addingTimeInterval(Double(i)))
            r.userMessage = turn.id
            let s = try await snaps.take(session: session, turn: turn.id, run: r.id, phase: .start)
            try sh(work, in: p)
            let e = try await snaps.take(session: session, turn: turn.id, run: r.id, phase: .end)
            r.snapshots = RunSnapshotRefs(start: s.commit, end: e.commit, skipped: [])
            runs.append(r)
        }
        let messages = [a, ChatMessage(role: .assistant, content: "did A"), b, ChatMessage(role: .assistant, content: "did B")]
        return (p, snaps, session, messages, runs, CheckpointStore(directory: try temp("cp")))
    }

    @Test func restoresWhatTheRunsChangedButNotTheUsersEdits() async throws {
        let t = try await twoTurns()
        // The user edits c.txt after B: c.txt is theirs now too.
        try write("c by hand\n", "c.txt", in: t.p)
        let plan = await RewindPlan.make(target: t.messages[0].id, messages: t.messages, runs: t.runs, snapshots: t.snaps,
                                         session: t.session, checkpoints: t.checkpoints)
        #expect(plan.coversCommands)
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == ["a.txt"])
        #expect(plan.keptUserEdits.map { ($0 as NSString).lastPathComponent } == ["b.txt", "c.txt"])
        #expect(plan.summary(.both, root: t.p.path).contains("Left as they are, because you changed them too: b.txt, c.txt."))
        let restored = try await plan.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(restored.count == 1)
        #expect(read("a.txt", in: t.p)?.contains("two\n") == true)
        #expect(read("b.txt", in: t.p) == "b3\n" && read("c.txt", in: t.p) == "c by hand\n")
    }

    @Test func rewindingTheSecondTurnKeepsTheEditBeforeIt() async throws {
        let t = try await twoTurns()
        let plan = await RewindPlan.make(target: t.messages[2].id, messages: t.messages, runs: t.runs, snapshots: t.snaps,
                                         session: t.session, checkpoints: t.checkpoints)
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == ["b.txt", "c.txt"] && plan.keptUserEdits.isEmpty)
        _ = try await plan.restoreFiles(snapshots: t.snaps, checkpoints: t.checkpoints)
        #expect(read("b.txt", in: t.p) == "b2 by hand\n")                 // as it was when B started
        #expect(!FileManager.default.fileExists(atPath: t.p.appending(path: "c.txt").path))
        #expect(read("a.txt", in: t.p)?.contains("TWO") == true)           // A's change stays
    }

    @Test func withoutSnapshotsItFallsBackToTheCheckpoints() async throws {
        var t = try await twoTurns()
        t.runs[1].snapshots = nil
        try await t.checkpoints.snapshot(t.p.appending(path: "c.txt"), turn: t.messages[2].id)
        let plan = await RewindPlan.make(target: t.messages[0].id, messages: t.messages, runs: t.runs, snapshots: t.snaps,
                                         session: t.session, checkpoints: t.checkpoints)
        #expect(!plan.coversCommands)
        #expect(plan.files.map { ($0 as NSString).lastPathComponent } == ["c.txt"])
        #expect(plan.summary(.files, root: t.p.path).contains("Changes made by commands can't be undone"))
        #expect(plan.summary(.conversation, root: t.p.path).hasSuffix("Files stay as they are."))
    }

    @Test func listsTheRequestsWithTheirFiles() async throws {
        let t = try await twoTurns()
        let points = await RewindPoint.list(messages: t.messages, runs: t.runs, snapshots: t.snaps, session: t.session)
        #expect(points.map(\.number) == [1, 2] && points.map(\.text) == ["Do A", "Do B"] && points.map(\.files) == [1, 2])
        let plan = await RewindPlan.make(target: t.messages[2].id, messages: t.messages, runs: t.runs, snapshots: t.snaps,
                                         session: t.session, checkpoints: t.checkpoints)
        #expect(plan.note(request: "Do B", root: t.p.path).contains("before the request \"Do B\", undoing the changes made since then: b.txt, c.txt."))
    }
}

@Suite struct NoteLabelTests {
    @Test func eachNoteSaysWhatItIs() {
        #expect(FrozenSystemPrompt.noteLabel(FrozenSystemPrompt.note("Today is …")).hasPrefix("Told the model today's date"))
        #expect(FrozenSystemPrompt.noteLabel(SkillRouter.header("codemod") + " for this request]") == "The skill router gave the model the codemod skill")
        let plan = RewindPlan(turns: [], files: ["/p/a.txt"], keptUserEdits: [], base: "x")
        #expect(FrozenSystemPrompt.noteLabel(plan.note(request: "Do A", root: "/p")) == "Told the model that files were restored (rewind)")
        #expect(FrozenSystemPrompt.noteLabel("[kurtkode: other]") == "A note to the model from kurtkode")
    }
}

@Suite struct CLIRewindTests {
    @Test func aCommandsChangeRewindsThroughTheCLISession() async throws {
        let support = try temp("support")
        let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://mock.invalid/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock])
        let defaults = try #require(UserDefaults(suiteName: "kk-p3-cli-\(UUID().uuidString.prefix(8))"))
        defaults.set(mock.id.uuidString, forKey: "defaultEndpointID")
        defaults.set("test-model", forKey: "defaultModel")
        defaults.set(SkillRouting.off.rawValue, forKey: RunSettings.Key.skillRouting)
        let settings = AppSettings(support: support, defaults: defaults, environment: [:])
        let p = try gitProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"sed -i '' 's/two/TWO/' a.txt && echo x > made.txt"}"#),
            SSE.content("Done."),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        options.mode = .fullAuto
        let session = try await CLISession(settings: settings, workspace: p, options: options) { _, _ in client }
        #expect(try await session.send("Capitalize two") == .completed)
        let points = await session.rewindPoints()
        #expect(points.count == 1 && points[0].files == 2)
        let plan = await session.rewindPlan(to: points[0].message)
        #expect(plan.coversCommands && plan.files.count == 2)
        let (restored, request) = try await session.rewind(to: points[0].message, choice: .both)
        #expect(restored.count == 2 && request == "Capitalize two")
        #expect(read("a.txt", in: p)?.contains("two\n") == true)
        #expect(!FileManager.default.fileExists(atPath: p.appending(path: "made.txt").path))
        #expect(session.session.messages.isEmpty)
        #expect(session.session.judgments.contains { $0.note == "rewound" })
    }
}

@Suite struct CodeReviewTests {
    @Test func readsTheReviewersVerdictAndFindings() async throws {
        let args = #"{"verdict":"has_problems","summary":"Off by one.","findings":[{"file":"calc.py","line":12,"severity":"high","problem":"divides by n-1"},{"severity":"low","problem":"no test"}]}"#
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("r1", "submit_review", args)]))
        let reviewer = SubagentModel(client: client, model: "rev-model", endpointID: UUID())
        let prompt = CodeReview.prompt(request: "Fix mean()", report: "Fixed it.", checks: ["pytest → exit 0"], diff: "diff --git a/calc.py b/calc.py\n+x")
        let r = await CodeReview.run(reviewer, prompt: prompt, costs: nil, meter: nil, limits: TurnLimits())
        #expect(r.verdict == .hasProblems && r.findings.count == 2)
        #expect(r.findings[0].line1 == "high · calc.py:12 · divides by n-1")
        #expect(r.text.hasPrefix("Review by rev-model: has problems. Off by one.\n- high · calc.py:12"))
        let j = r.judgment(run: UUID())
        #expect(j.judge == .reviewer && j.verdict == 1 && j.evidence?.count == 2)
        // What was sent: the review tool only, and the four parts.
        let body = String(decoding: try #require(MockServer.requestBody(host)), as: UTF8.self)
        #expect(body.contains("submit_review") && !body.contains("\"bash\""))
        #expect(prompt.contains("## What was asked") && prompt.contains("## What the agent says it did") && prompt.contains("pytest → exit 0") && prompt.contains("```diff"))
    }

    @Test func aReplyWithoutTheCallHasNoVerdictAndSaysWhy() async {
        let (client, _) = MockServer.client(.init(turns: [SSE.content("Looks fine to me.")]))
        let r = await CodeReview.run(SubagentModel(client: client, model: "m"), prompt: "p", costs: nil, meter: nil, limits: TurnLimits())
        #expect(r.verdict == nil && r.problem == "no submit_review call")
        #expect(r.judgment(run: UUID()).verdict == nil)
    }

    @Test func emptyDiffsAndLongOnesAreSaid() {
        #expect(CodeReview.prompt(request: "r", report: nil, checks: [], diff: "").contains("(No files changed.)"))
        #expect(CodeReview.prompt(request: "r", report: nil, checks: [], diff: String(repeating: "x", count: 100), maxDiffBytes: 10).contains("(cut: the whole diff is"))
    }

    @Test func vendors() {
        #expect(ModelVendor.of("anthropic/claude-haiku-5.5") == "anthropic")
        #expect(ModelVendor.of("haiku", endpoint: Endpoint(name: "A", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!)) == "anthropic")
        #expect(ModelVendor.of("google/gemma-4-26b-a4b-qat") == "google")
        #expect(ModelVendor.of("gemini-3.8-flash") == "google")
        #expect(ModelVendor.of("qwen/qwen3-coder-30b") == "alibaba")
        #expect(ModelVendor.of("deepseek/deepseek-v4-flash-0731") == "deepseek")
        #expect(ModelVendor.of("inclusionai/ling-3.0-flash") == "inclusionai")
        #expect(ModelVendor.of("openai/gpt-5.6-sol") == "openai")
        #expect(ModelVendor.of("somelab/thing-7b") == "somelab")
    }

    @Test func picksAnotherVendorAndKeepsLocalSessionsLocal() {
        let or = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        let lan = Endpoint(name: "bang", kind: .lmstudio, baseURL: URL(string: "http://192.168.1.20:1234/v1")!)
        let pool = ModelPool(entries: [
            PoolEntry(endpoint: "openrouter", model: "anthropic/claude-haiku-5.5", tier: .standard, roles: [.reviewer]),
            PoolEntry(endpoint: "openrouter", model: "deepseek/deepseek-v4-flash-0731", reasoning: "none", tier: .cheap, roles: [.reviewer]),
            PoolEntry(endpoint: lan.id.uuidString, model: "qwen/qwen3.5-9b", tier: .local, roles: [.reviewer]),
        ])
        let eps = [or, lan, .localLMStudio]
        // A Claude session: any other vendor, the lowest tier first: the LAN model's (local is below cheap).
        #expect(ReviewRouting.reviewer(for: "anthropic/claude-opus-5.5", endpoint: or, pool: pool, endpoints: eps)?.model == "qwen/qwen3.5-9b")
        // A local Gemma session: never a remote reviewer.
        #expect(ReviewRouting.reviewer(for: "google/gemma-4-26b", endpoint: .localLMStudio, pool: pool, endpoints: eps)?.model == "qwen/qwen3.5-9b")
        // A local qwen session: the only local reviewer is the same vendor; nothing remote: none.
        #expect(ReviewRouting.reviewer(for: "qwen/qwen3-coder-30b", endpoint: .localLMStudio, pool: pool, endpoints: eps) == nil)
        // A hosted qwen session: the cheapest other vendor.
        #expect(ReviewRouting.reviewer(for: "qwen/qwen3-max", endpoint: or, pool: pool, endpoints: eps)?.model == "deepseek/deepseek-v4-flash-0731")
    }

    @Test func gathersTheLatestRunsChange() async throws {
        let p = try gitProject()
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        var session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: p.path), messages: [], model: "m")
        let ask = ChatMessage.user("Capitalize two")
        var run = AgentRunRecord.test(agent: "main")
        run.userMessage = ask.id
        run.signals = RunSignals(lastCheck: SessionFacts.Check(command: "python3 -m pytest", exitCode: 1))
        let s = try await snaps.take(session: session.header.id, turn: ask.id, run: run.id, phase: .start)
        try sh("sed -i '' 's/two/TWO/' a.txt", in: p)
        let e = try await snaps.take(session: session.header.id, turn: ask.id, run: run.id, phase: .end)
        run.snapshots = RunSnapshotRefs(start: s.commit, end: e.commit, skipped: [])
        session.messages = [ask, ChatMessage(role: .assistant, content: "Done: capitalized it.")]
        session.runs = [run]
        let input = try await ReviewInput.gather(scope: .lastRun, session: session, snapshots: snaps)
        #expect(input.request == "Capitalize two" && input.report == "Done: capitalized it.")
        #expect(input.checks == ["python3 -m pytest → exit 1"])
        #expect(input.diff.contains("-two") && input.diff.contains("+TWO"))
        #expect(input.run?.id == run.id)
    }

    @Test func theReviewersVerdictRanksBelowTheGradersAboveTheParents() {
        let run = UUID()
        var js = [RunJudgment(run: run, judge: .parent, verdict: 3), RunJudgment(run: run, judge: .reviewer, verdict: 0)]
        #expect(js.label == 0)
        js.append(RunJudgment(run: run, judge: .grader, verdict: 3))
        #expect(js.label == 1)
    }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var judgments: [RunJudgment] { all.compactMap { if case .judged(let j) = $0 { j } else { nil } } }
    var costs: [CostEntry] { all.compactMap { if case .cost(let e) = $0 { e } else { nil } } }
}

@Suite struct SubagentReviewTests {
    /// An important task that changes a file (here by a command) is reviewed by another model; the parent reads it.
    @Test func importantChangesAreReviewedAndTheParentReadsIt() async throws {
        let p = try gitProject()
        let ws = Workspace(root: p)
        let store = SessionStore(root: try temp("store").appending(path: "sessions"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: p.path)
        try await store.create(parent)
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Capitalize","prompt":"Capitalize two in a.txt","agent":"general","importance":"high"}"#),
            SSE.toolCall("s1", "bash", #"{"command":"sed -i '' 's/two/TWO/' a.txt"}"#),
            SSE.content("Capitalized two in a.txt."),
            SSE.content("Done."),
            SSE.content("No rating."),
        ]))
        let (reviewerClient, reviewerHost) = MockServer.client(.init(turns: [
            SSE.toolCall("r1", "submit_review", #"{"verdict":"has_problems","findings":[{"file":"a.txt","line":2,"severity":"medium","problem":"only the first occurrence"}]}"#),
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow }, shell: ShellState(cwd: p))
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        config.subagents?.reviewer = { _, _ in SubagentModel(client: reviewerClient, model: "other-vendor") }
        config.snapshots = RunSnapshots(store: try #require(store.snapshots(for: p)), session: parent.id, turn: UUID())
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Capitalize two")],
                            config: config, workspace: ws) { events.add($0) }
        let text = try #require(events.results.first?.content)
        #expect(text.contains("[Cross-vendor review by other-vendor: has problems.\n- medium · a.txt:2 · only the first occurrence]"))
        let asked = String(decoding: try #require(MockServer.requestBodies(reviewerHost).first), as: UTF8.self)
        #expect(asked.contains("-two") && asked.contains("+TWO") && asked.contains("Capitalized two in a.txt."))
        let reviewed = try #require(events.judgments.first { $0.judge == .reviewer })
        #expect(reviewed.verdict == 1 && reviewed.judgeModel == "other-vendor")
        #expect(events.costs.contains { $0.purpose == .review })
        // The run's own index in the shadow repository is gone.
        let snaps = try #require(store.snapshots(for: p))
        #expect(!FileManager.default.fileExists(atPath: snaps.gitDir.appending(path: "index-\(reviewed.run.uuidString)").path))
    }

    @Test func noReviewWithoutAChangeOrForOrdinaryTasks() async throws {
        let p = try gitProject()
        let store = SessionStore(root: try temp("store").appending(path: "sessions"))
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Look","prompt":"What's in a.txt?","agent":"explore","importance":"high"}"#),
            SSE.content("It lists numbers one to twelve."),
            SSE.content("Done."),
        ]))
        let (reviewerClient, reviewerHost) = MockServer.client(.init(turns: [SSE.content("x")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow }, shell: ShellState(cwd: p))
        config.subagents = SubagentSetup()
        config.subagents?.reviewer = { _, _ in SubagentModel(client: reviewerClient, model: "other-vendor") }
        config.snapshots = RunSnapshots(store: try #require(store.snapshots(for: p)), session: UUID(), turn: UUID())
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Look")],
                            config: config, workspace: Workspace(root: p)) { events.add($0) }
        #expect(MockServer.requestBodies(reviewerHost).isEmpty)
        #expect(events.results.first?.content.contains("Cross-vendor") == false)
    }
}

@Suite struct CLINoKeychainTests {
    @Test func noKeychainReadsWhenAsked() throws {
        let support = try temp("support")
        var keyed = Endpoint(name: "Keyed", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        keyed.usesAPIKey = true
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([keyed])
        var settings = AppSettings(support: support, defaults: try #require(UserDefaults(suiteName: "kk-p3-nk-\(UUID().uuidString.prefix(6))")),
                                   environment: ["KURTKODE_NO_KEYCHAIN": "1"])
        // R7-29: a Keychain stand-in that has the key, so the test fails if the switch is ignored.
        settings.keychain = { _ in "from-the-keychain" }
        #expect(settings.apiKey(for: keyed) == nil)
        settings = AppSettings(support: support, defaults: try #require(UserDefaults(suiteName: "kk-p3-nk3-\(UUID().uuidString.prefix(6))")),
                               environment: [:])
        settings.keychain = { _ in "from-the-keychain" }
        #expect(settings.apiKey(for: keyed) == "from-the-keychain")
        let withEnv = AppSettings(support: support, defaults: try #require(UserDefaults(suiteName: "kk-p3-nk2-\(UUID().uuidString.prefix(6))")),
                                  environment: ["KURTKODE_NO_KEYCHAIN": "1", "KURTKODE_API_KEY_KEYED": "k"])
        #expect(withEnv.apiKey(for: keyed) == "k")
    }
}

@Suite struct ShippedReviewerTests {
    @Test func theShippedPoolReviewsClaudeAndGeminiWithDeepseekAndDeepseekWithHaiku() {
        var or = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        or.usesAPIKey = true
        let gemini = Endpoint(name: "Google Gemini", kind: .gemini, baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!)
        let eps = [or, gemini]
        #expect(ReviewRouting.reviewer(for: "anthropic/claude-opus-5.5", endpoint: or, pool: .shipped, endpoints: eps)?.model == "deepseek/deepseek-v4-flash-0731")
        #expect(ReviewRouting.reviewer(for: "gemini-4-argon", endpoint: gemini, pool: .shipped, endpoints: eps)?.entry.reasoning == "none")
        #expect(ReviewRouting.reviewer(for: "deepseek/deepseek-v4-flash-0731", endpoint: or, pool: .shipped, endpoints: eps)?.model == "anthropic/claude-haiku-5.5")
        // A Haiku run gets no grader: neither Opus nor the cheap reviewer, whose judging isn't measured.
        #expect(SubagentRouting.grader(main: or, runEndpointID: or.id, runModel: "anthropic/claude-haiku-5.5", pool: .shipped, endpoints: eps) == nil)
    }
}

@Suite struct EscalationTests {
    private let or: Endpoint = {
        var e = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        e.usesAPIKey = true
        return e
    }()

    @Test func groundedReasonsFromHowTheRunEnded() {
        var run = AgentRunRecord.test(agent: "main")
        #expect(Escalation.reasons(run).isEmpty)
        run.outcome.stop = "stepLimit"
        run.signals = RunSignals(lastCheck: SessionFacts.Check(command: "pytest -q", exitCode: 1), unfinishedTodos: ["a", "b"])
        // A failing check in a run that changed nothing is a report ("run the tests and tell me"), not a failure.
        #expect(Escalation.reasons(run) == ["it stopped at the step limit", "it left 2 todos unfinished"])
        run.snapshots = RunSnapshotRefs(start: "a", end: "b", skipped: [], changed: true)
        #expect(Escalation.reasons(run) == ["it stopped at the step limit", "its last check failed (exit 1): pytest -q", "it left 2 todos unfinished"])
        run.outcome.stop = "costLimit"
        run.signals = nil
        #expect(Escalation.reasons(run).isEmpty)                  // the user's limit, not the model's failure
        run.outcome.stop = "\(AgentStop.turnStopped(.repetition))"
        #expect(Escalation.reasons(run) == ["it got stuck repeating itself"])
        // A server error or the wall clock isn't the model's failure (R7-19).
        run.outcome.stop = "\(AgentStop.turnStopped(.failed))"
        #expect(Escalation.reasons(run).isEmpty)
        run.outcome.stop = "\(AgentStop.turnStopped(.timedOut))"
        #expect(Escalation.reasons(run).isEmpty)
    }

    /// COST_AUDIT.md §10, point 6: a run that finished with no change on a request for one is a reason; not when it
    /// couldn't edit (Plan mode), was denied, asked the user something, or the request asked for none.
    @Test func aChangeRequestThatChangedNothingIsAReason() {
        let reason = "it changed no files, though the request asked for a change"
        let gaveUp = [ChatMessage(role: .assistant, content: "## Handoff\n\nStopped before any edits.")]
        var run = AgentRunRecord.test(agent: "main")
        run.setup.tools = ["read_file", "edit_file", "bash"]
        run.snapshots = RunSnapshotRefs(start: "a", end: "a", skipped: [], changed: false)
        run.signals = RunSignals.evaluate(gaveUp, request: "Please add retries to the outage handler in job.py.")
        #expect(Escalation.reasons(run) == [reason])
        run.snapshots?.changed = true
        #expect(Escalation.reasons(run).isEmpty)                                 // it changed something
        run.snapshots = nil
        #expect(Escalation.reasons(run).isEmpty)                                 // no snapshots: a command may have
        run.snapshots = RunSnapshotRefs(start: "a", end: "a", skipped: [], changed: false)
        run.setup.tools = ["read_file", "bash"]
        #expect(Escalation.reasons(run).isEmpty)                                 // Plan mode: no edit tools
        run.setup.tools = ["apply_patch"]
        run.outcome.denied = 1
        #expect(Escalation.reasons(run).isEmpty)                                 // the user said no
        run.outcome.denied = 0
        run.outcome.stop = "stepLimit"
        #expect(Escalation.reasons(run) == ["it stopped at the step limit"])     // its own reason, not both
        run.outcome.stop = "completed"
        run.signals = RunSignals.evaluate([ChatMessage(role: .assistant, content: "Which handler do you mean?")],
                                          request: "Add retries to the handler.")
        #expect(Escalation.reasons(run).isEmpty)                                 // waiting on the user
        run.signals = RunSignals.evaluate(gaveUp, request: "Where are retries handled?")
        #expect(Escalation.reasons(run).isEmpty)
        run.signals = RunSignals.evaluate(gaveUp, request: "Where are retries handled?", card: TaskCard(kind: .fix))
        #expect(Escalation.reasons(run) == [reason])                             // the card says it's a fix
    }

    @Test func whichRequestsAskForAChange() {
        for yes in ["Fix the off-by-one in calc.py", "please add a --dry-run flag", "Can you rename Foo to Bar?",
                    "OK, now implement the parser.", "Could you, please, update the README's install steps",
                    "Make the tests pass", "write tests for sizes.py", "Let's refactor the store",
                    "The shop tests fail. Find the bug in the shop package and fix it.",
                    "Retries count against the SUT.\nThey shouldn't. When you're done, report what you changed and why."] {
            #expect(Escalation.asksForChange(yes), "\(yes)")
        }
        for no in ["Why does calc.py need a fix?", "What does the retry ladder do?", "Explain how compaction works",
                   "Make sure nothing else changed", "Write a summary of the design", "Run the tests and tell me what fails",
                   "Review the change", "addition is broken where?", "Read the parser and explain how errors flow",
                   "Count the WARN lines and then add up the totals", "Is your change safe?", ""] {
            #expect(!Escalation.asksForChange(no), "\(no)")
        }
        #expect(!Escalation.asksForChange("Fix it", card: TaskCard(kind: .search)))
        #expect(Escalation.asksForChange("Tests for sizes.py", card: TaskCard(kind: .writeTests)))
    }

    @Test func onlyAWrongReviewEscalates() {
        let r = CodeReview(verdict: .hasProblems, findings: [], reviewer: "deepseek")
        #expect(!r.escalates)
        #expect(CodeReview(verdict: .wrong, findings: [], reviewer: "deepseek").escalates)
        #expect(!CodeReview(verdict: nil, findings: [], reviewer: "deepseek").escalates)
    }

    @Test func offersOneTierUpWithAnEstimate() throws {
        let eps = [or, Endpoint.localLMStudio]
        let price = PriceList.Price(standard: .init(input: 1, output: 5, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2))
        // A local Gemma session: one tier up is the cheap tier's main model.
        let local = try #require(Escalation.offer(run: UUID(), reasons: ["it stopped at the step limit"], source: "signals",
                                                  endpoint: .localLMStudio, model: "google/gemma-4-26b", pool: .shipped, endpoints: eps,
                                                  contextTokens: 10_000, price: { _ in price }))
        #expect(local.toModel == "inclusionai/ling-3.0-flash" && local.toLabel == "ling-3.0-flash")
        // The 10k-token history is written to the new model's cache: 1.25× input here (B7 of the cost audit).
        #expect(abs((local.estimate ?? 0) - (TypicalTask.cost(price) + 0.0125)) < 1e-9)
        // A run that changed files adds the hand-over's diff allowance (3,000 tokens at input).
        #expect(abs(Escalation.estimate(price, contextTokens: 10_000, changedFiles: true) - (TypicalTask.cost(price) + 0.0125 + 0.003)) < 1e-9)
        #expect(local.buttonTitle.hasPrefix("Escalate to ling-3.0-flash for ≈$"))
        // ling → Haiku (standard) → Sonnet (frontier) → nowhere.
        #expect(Escalation.offer(run: nil, reasons: ["x"], source: "signals", endpoint: or, model: "inclusionai/ling-3.0-flash", pool: .shipped,
                                 endpoints: eps, contextTokens: nil, price: { _ in nil })?.toModel == "anthropic/claude-haiku-5.5")
        #expect(Escalation.offer(run: nil, reasons: ["x"], source: "signals", endpoint: or, model: "anthropic/claude-haiku-5.5", pool: .shipped,
                                 endpoints: eps, contextTokens: nil, price: { _ in nil })?.toModel == "anthropic/claude-sonnet-5.5")
        #expect(Escalation.offer(run: nil, reasons: ["x"], source: "signals", endpoint: or, model: "anthropic/claude-sonnet-5.5", pool: .shipped,
                                 endpoints: eps, contextTokens: nil, price: { _ in nil }) == nil)
        // A hosted model the pool doesn't know: no tier, no offer on its own; and no reason, no offer.
        #expect(Escalation.offer(run: nil, reasons: ["x"], source: "signals", endpoint: or, model: "somelab/new-model", pool: .shipped,
                                 endpoints: eps, contextTokens: nil, price: { _ in nil }) == nil)
        #expect(Escalation.offer(run: nil, reasons: [], source: "signals", endpoint: .localLMStudio, model: "g", pool: .shipped,
                                 endpoints: eps, contextTokens: nil, price: { _ in nil }) == nil)
    }

    /// Decision 4 (P3): a run that changed files is offered one review on the offer's model first, priced as one request;
    /// not when A6's review made the offer, nor for a run that changed nothing, nor in records from before.
    @Test func aRunThatChangedFilesIsOfferedAReviewFirst() throws {
        let eps = [or, Endpoint.localLMStudio]
        let price = PriceList.Price(standard: .init(input: 1, output: 5, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2))
        func offer(_ source: String, changed: Bool) throws -> EscalationOffer {
            try #require(Escalation.offer(run: UUID(), reasons: ["x"], source: source, endpoint: or, model: "inclusionai/ling-3.0-flash",
                                          pool: .shipped, endpoints: eps, contextTokens: 10_000, changedFiles: changed, price: { _ in price }))
        }
        let o = try offer("signals", changed: true)
        #expect(o.canReview)
        // 4,000 tokens in at $1, 800 out at $5 a million.
        #expect(abs((o.reviewEstimate ?? 0) - 0.008) < 1e-9)
        #expect(o.reviewTitle == "Review on \(o.toLabel) for ≈" + TypicalTask.money(0.008))
        #expect((o.reviewEstimate ?? 1) < (o.estimate ?? 0))
        #expect(!(try offer("review", changed: true)).canReview)
        #expect(!(try offer("signals", changed: false)).canReview)
        // An offer recorded before decision 4 decodes without the review.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(o)) as! [String: Any]
        old["reviewable"] = nil
        old["reviewEstimate"] = nil
        let decoded = try JSONDecoder().decode(EscalationOffer.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(!decoded.canReview && decoded.reviewEstimate == nil)
    }

    @Test func theHandOverCarriesTheReasonAndTheDiff() {
        let offer = EscalationOffer(run: nil, reasons: ["its last check failed (exit 1): pytest -q"], source: "signals",
                                    fromModel: "google/gemma-4-26b", toModel: "m", toEndpointID: UUID(), toLabel: "m")
        let text = Escalation.handOver(offer, request: "Fix the parser\nso it handles tabs", diff: "diff --git a/p.py b/p.py\n+x")
        #expect(text.hasPrefix("[kurtkode: the user escalated this request from google/gemma-4-26b to you, because its last check failed (exit 1): pytest -q.]"))
        #expect(text.contains("on the request \"Fix the parser\""))
        #expect(text.contains("```diff\ndiff --git a/p.py b/p.py\n+x\n```"))
        #expect(Escalation.handOver(offer, request: "r", diff: "").hasSuffix("It changed no files."))
    }

    @Test func offersAreKeptInTheSessionAsLastDecided() async throws {
        let store = SessionStore(root: try temp("store").appending(path: "sessions"))
        let header = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(header)
        var offer = EscalationOffer(run: UUID(), reasons: ["r"], source: "signals", fromModel: "a", toModel: "b", toEndpointID: UUID(), toLabel: "b")
        try await store.append(.escalation(offer), to: header.id)
        offer.decision = .declined
        try await store.append(.escalation(offer), to: header.id)
        let loaded = try #require(try await store.load(header.id))
        #expect(loaded.escalations.count == 1 && loaded.escalations[0].decision == .declined)
    }
}

@Suite struct CLIEscalationTests {
    @Test func aRunAtTheStepLimitEarnsAnOfferAndYesSwitchesTheModel() async throws {
        let support = try temp("support")
        // A server on this Mac (the mock client answers for it): local tier. An unknown remote name gets no offer (R7-17).
        let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://127.0.0.1:59999/v1")!)
        var or = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        or.usesAPIKey = true
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock, or])
        let defaults = try #require(UserDefaults(suiteName: "kk-p3-esc-\(UUID().uuidString.prefix(8))"))
        defaults.set(mock.id.uuidString, forKey: "defaultEndpointID")
        defaults.set("test-model", forKey: "defaultModel")
        defaults.set(SkillRouting.off.rawValue, forKey: RunSettings.Key.skillRouting)
        let settings = AppSettings(support: support, defaults: defaults, environment: ["KURTKODE_NO_KEYCHAIN": "1"])
        let p = try gitProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"echo one >> a.txt"}"#),
            SSE.toolCall("c2", "bash", #"{"command":"echo two >> a.txt"}"#),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        options.mode = .fullAuto
        options.maxSteps = 2
        let session = try await CLISession(settings: settings, workspace: p, options: options) { _, _ in client }
        #expect(try await session.send("Append lines") == .stepLimit)
        let offer = try #require(await session.escalationOffer())
        #expect(offer.reasons == ["it stopped at the step limit"] && offer.toModel == "inclusionai/ling-3.0-flash")
        let handOver = try #require(await session.decide(offer, accept: true))
        #expect(handOver.contains("because it stopped at the step limit") && handOver.contains("+one") && handOver.contains("+two"))
        #expect(session.model == "inclusionai/ling-3.0-flash" && session.endpoint.id == or.id)
        #expect(session.session.escalations.map(\.decision) == [.accepted])
    }
}

/// Six files of ~700 bytes and a read of each: six reads in a row that fill a fifth of a 4,000-token context.
private func sixFiles(_ ws: Workspace) throws -> [[Data]] {
    try (1...6).map { i in
        try write(String(repeating: "Line \(i) of the notes about the system.\n", count: 18), "notes/n\(i).md", in: ws.root)
        return SSE.toolCall("r\(i)", "read_file", #"{"path":"notes/n\#(i).md"}"#)
    }
}

@Suite struct DelegationForceTests {
    private func request(_ forced: String?) -> ChatRequest {
        var r = ChatRequest(model: "m", messages: [.user("hi")], tools: [
            ToolDefinition(name: "task", description: "t", parameters: ["type": "object"]),
            ToolDefinition(name: "read_file", description: "r", parameters: ["type": "object"])], maxTokens: 100)
        r.forcedTool = forced
        return r
    }

    @Test func eachWireForcesTheCallItsOwnWay() throws {
        let openai = String(decoding: try WireFormat.encodeRequest(request("task")), as: UTF8.self)
        #expect(openai.contains(#""tool_choice":{"function":{"name":"task"},"type":"function"}"#))
        #expect(!String(decoding: try WireFormat.encodeRequest(request(nil)), as: UTF8.self).contains("tool_choice"))
        let gemini = String(decoding: try GeminiWire.encodeRequest(request("task")), as: UTF8.self)
        #expect(gemini.contains("functionCallingConfig") && gemini.contains(#""allowedFunctionNames":["task"]"#) && gemini.contains(#""mode":"ANY""#))
        // Claude: never with thinking on, which the newest models always have.
        var claude = request("task")
        claude.model = "claude-opus-5-5"
        #expect(!String(decoding: try AnthropicWire.encodeRequest(claude), as: UTF8.self).contains("tool_choice"))
        #expect(!AnthropicWire.canForceTool(model: "claude-opus-5-5", effort: nil))
    }

    @Test func whoCanBeForced() {
        #expect(ToolForcing.supported(client: ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!), model: "x", effort: nil))
        #expect(!ToolForcing.supported(client: ChatClient(baseURL: URL(string: "http://127.0.0.1:1234/v1")!), model: "x", effort: nil))
        #expect(ToolForcing.supported(client: ChatClient(baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!, api: .gemini), model: "gemini-3.8-flash", effort: nil))
    }

    /// Six reads that fill a fifth of a small context: the next request must call task (a forceable server).
    @Test func atTheThresholdTheNextRequestMustCallTask() async throws {
        let ws = try makeProject()
        let reads = try sixFiles(ws)
        let (client, host) = MockServer.client(.init(turns: reads + [
            SSE.toolCall("t1", "task", #"{"description":"Read the rest","prompt":"Find X","agent":"explore"}"#),
            SSE.content("X is in README.md."),          // the subagent
            SSE.content("Done."),
        ]), host: ".openrouter.ai")
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root), context: ContextBudget(limit: 4000, outputReserve: 100))
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is X?")], config: config,
                            workspace: ws) { events.add($0) }
        let bodies = MockServer.requestBodies(host).map { String(decoding: $0, as: UTF8.self) }
        let forced = bodies.firstIndex { $0.contains("tool_choice") }
        #expect(forced == 6)                                   // the seventh request, right after the sixth read
        #expect(bodies.filter { $0.contains("tool_choice") }.count == 1)
        #expect(events.results.contains { $0.content.contains("your next step is a task call") })
        #expect(events.results.contains { $0.toolCallID == "t1" && $0.content.contains("X is in README.md.") })
    }

    /// Improvement 7: in a big context the share rule never trips; the absolute one gives the note, but forces nothing.
    @Test func inABigContextTheTokenThresholdGivesTheNoteOnly() async throws {
        let ws = try makeProject()
        let reads = try sixFiles(ws)
        for tokens in [500, 0] {
            let (client, host) = MockServer.client(.init(turns: reads + [SSE.content("Done.")]), host: ".openrouter.ai")
            var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                     shell: ShellState(cwd: ws.root), context: ContextBudget(limit: 1_000_000, outputReserve: 100))
            config.subagents = SubagentSetup()
            config.delegationTokens = tokens
            let events = Events()
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is X?")], config: config,
                                workspace: ws) { events.add($0) }
            let bodies = MockServer.requestBodies(host).map { String(decoding: $0, as: UTF8.self) }
            #expect(!bodies.contains { $0.contains("tool_choice") })
            #expect(!events.results.contains { $0.content.contains("your next step is a task call") })
            let advised = events.results.filter { $0.content.contains("the explore subagent can do the searching") }
            #expect(advised.count == (tokens > 0 ? 1 : 0))
        }
    }

    /// The same where the server can't be made to call a tool: kurtkode writes the task call itself.
    @Test func whereItCantBeForcedKurtkodeWritesTheCall() async throws {
        let ws = try makeProject()
        let reads = try sixFiles(ws)
        let (client, host) = MockServer.client(.init(turns: reads + [
            SSE.content("X is in README.md."),          // the subagent, started by kurtkode
            SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root), context: ContextBudget(limit: 4000, outputReserve: 100))
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is X?")], config: config,
                            workspace: ws) { events.add($0) }
        let bodies = MockServer.requestBodies(host).map { String(decoding: $0, as: UTF8.self) }
        #expect(!bodies.contains { $0.contains("tool_choice") })
        #expect(bodies.count == 8)                             // six reads, the subagent, the final answer: no request for the call
        let task = try #require(events.results.first { $0.toolCallID?.hasPrefix("kk_delegate_") == true })
        #expect(task.content.contains("X is in README.md."))
        #expect(bodies[6].contains("The main agent is working on this request") && bodies[6].contains("Where is X?") && bodies[6].contains("notes/n3.md"))
        #expect(events.results.contains { $0.content.contains("kurtkode is handing the rest of the reading to it now") })
    }

    @Test func offMeansTheNoteOnly() async throws {
        let ws = try makeProject()
        let reads = try sixFiles(ws)
        let (client, host) = MockServer.client(.init(turns: reads + [SSE.content("Done.")]), host: ".openrouter.ai")
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root), context: ContextBudget(limit: 4000, outputReserve: 100))
        config.subagents = SubagentSetup()
        config.delegationForce = false
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is X?")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(!MockServer.requestBodies(host).contains { String(decoding: $0, as: UTF8.self).contains("tool_choice") })
        #expect(events.results.contains { $0.content.contains("the explore subagent can do the searching") && !$0.content.contains("next step") })
    }
}

/// Improvement 11b (COST_AUDIT.md): the project's own tests, run again after a main run, as an escalation reason.
@Suite struct TestSuiteTests {
    @Test func theProjectNamesItsTestCommand() throws {
        let p = try temp("suite")
        #expect(TestSuite.command(root: p) == nil)
        try write(#"{"testCommand": "swift test"}"#, ".kurtkode/settings.json", in: p)
        #expect(TestSuite.command(root: p) == "swift test")
        try write(#"{"testCommand": "  "}"#, ".kurtkode/settings.local.json", in: p)
        #expect(TestSuite.command(root: p) == "swift test")                     // a blank local one doesn't hide it
        try write(#"{"testCommand": "make test"}"#, ".kurtkode/settings.local.json", in: p)
        #expect(TestSuite.command(root: p) == "make test")
    }

    @Test func theTestsAfterTheRunOutrankTheModelsLastCheck() throws {
        var run = AgentRunRecord.test(agent: "main")
        run.snapshots = RunSnapshotRefs(start: "a", end: "b", skipped: [], changed: true)
        run.signals = RunSignals(lastCheck: SessionFacts.Check(command: "pytest -q tests/test_one.py", exitCode: 1))
        #expect(Escalation.reasons(run) == ["its last check failed (exit 1): pytest -q tests/test_one.py"])
        run.signals?.suite = SessionFacts.Check(command: "pytest -q", exitCode: 0)
        #expect(Escalation.reasons(run).isEmpty)                                // the suite passes: the red check was mid-work
        run.signals?.suite = SessionFacts.Check(command: "pytest -q", exitCode: 2)
        #expect(Escalation.reasons(run) == ["the project's tests fail after the run (exit 2): pytest -q"])
        run.signals?.suite = SessionFacts.Check(command: "pytest -q", exitCode: nil, timedOut: true)
        #expect(Escalation.reasons(run) == ["the project's tests timed out after the run: pytest -q"])
        run.signals = RunSignals()
        run.signals?.failedRechecks = ["make check"]
        #expect(Escalation.reasons(run) == ["a delegated task's check fails after the run: make check"])
        // Records from before 11b decode without the fields.
        let old = try JSONDecoder().decode(RunSignals.self, from: Data(#"{"filesNotNamed":[],"unfinishedTodos":[]}"#.utf8))
        #expect(old.suite == nil && old.failedRechecks == nil)
    }

    private func run(_ turns: [[Data]], suite: String?, agent: String = "main") async throws -> (AgentRunRecord?, [String]) {
        let p = try gitProject()
        let snaps = ProjectSnapshots(project: p, root: try temp("snaps"))
        let (client, _) = MockServer.client(.init(turns: turns))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: p))
        config.costScope = CostScope(run: UUID(), agent: agent, userMessage: UUID())
        config.snapshots = RunSnapshots(store: snaps, session: UUID(), turn: UUID())
        config.testSuite = suite
        final class Box: @unchecked Sendable { var run: AgentRunRecord?; var status: [String] = [] }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Capitalize two")], config: config,
                            workspace: Workspace(root: p)) { e in
            switch e {
            case .runEnded(let r): box.run = r
            case .status(let s): box.status.append(s)
            default: break
            }
        }
        return (box.run, box.status)
    }

    private let edit = [SSE.toolCall("c1", "bash", #"{"command":"sed -i '' 's/two/TWO/' a.txt"}"#), SSE.content("Done.")]

    @Test func aMainRunThatChangedFilesRunsTheTestsAgain() async throws {
        let (passed, status) = try await run(edit, suite: "grep -q TWO a.txt")
        #expect(passed?.signals?.suite == SessionFacts.Check(command: "grep -q TWO a.txt", exitCode: 0))
        #expect(status.contains("Running the project's tests after the run: grep -q TWO a.txt"))
        let (failed, _) = try await run(edit, suite: "grep -q '^two$' a.txt")
        #expect(failed?.signals?.suite?.exitCode == 1)
        #expect(Escalation.reasons(try #require(failed)) == ["the project's tests fail after the run (exit 1): grep -q '^two$' a.txt"])
    }

    /// The suite is named from the project's root, so it runs there even when the model's last command `cd`'d away
    /// (kk01 #3 in the Opus cascade escalated on "run-tests.sh: No such file", exit 127).
    @Test func theTestsRunFromTheRootWhereverTheModelLeftTheShell() async throws {
        let away = [SSE.toolCall("c1", "bash", #"{"command":"sed -i '' 's/two/TWO/' a.txt && mkdir -p sub && cd sub"}"#),
                    SSE.content("Done.")]
        let (run, _) = try await run(away, suite: "grep -q TWO a.txt")
        #expect(run?.signals?.suite == SessionFacts.Check(command: "grep -q TWO a.txt", exitCode: 0))
    }

    @Test func notForARunThatChangedNothingNorForASubagent() async throws {
        let (unchanged, status) = try await run([SSE.content("Nothing to do.")], suite: "false")
        #expect(unchanged?.signals?.suite == nil && !status.contains { $0.contains("project's tests") })
        let (sub, _) = try await run(edit, suite: "false", agent: "general")
        #expect(sub?.signals?.suite == nil)
        let (none, _) = try await run(edit, suite: nil)
        #expect(none?.signals?.suite == nil)
    }
}
