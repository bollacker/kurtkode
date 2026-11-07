import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// Worktrees, the sandbox around them, isolated subagents, and the Git panel's operations, on real repositories.

/// Outside the temp folders: the sandbox lets commands write those, so a repository there couldn't show what it blocks.
private func scratch(_ file: String = #filePath) throws -> URL {
    let base = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/kk-wt-\(UUID().uuidString.prefix(8))")
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

private func repo(in base: URL, _ name: String = "project") throws -> GitRepo {
    let d = base.appending(path: name)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    try sh("git init -q -b main && git config user.email t@t && git config user.name t && echo one > a.txt && echo keep > b.txt "
           + "&& git add . && git commit -qm first", in: d)
    return GitRepo(root: d)
}

private func sandboxed(_ command: String, in root: URL) async -> ToolOutput {
    let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(["command": .string(command)])), as: UTF8.self)
    var config = AgentConfig(tools: [BashTool()])
    config.sandbox = SandboxPolicy()
    return await AgentLoop.execute(ToolCall(id: "t", name: "bash", arguments: json), tools: ["bash": BashTool()],
                                   config: config, workspace: Workspace(root: root))
}

@Suite struct WorktreeTests {
    @Test func namesAreMadeSafe() {
        #expect(GitRepo.worktreeName("  my feature ") == "my-feature")
        #expect(GitRepo.worktreeName("../../etc") == "etc")
        #expect(GitRepo.worktreeName("-x") == "x")
        #expect(GitRepo.worktreeName("...") == nil)
        #expect(GitRepo.worktreeName("a;rm /x") == "arm-x")
    }

    @Test func readsGitsList() {
        let list = GitRepo.parseWorktrees("worktree /r\nHEAD abc\nbranch refs/heads/main\n\nworktree /r/.worktrees/x\nHEAD def\nbranch refs/heads/kk/x\n\nworktree /r/y\nHEAD 123\ndetached\n")
        #expect(list.map(\.branch) == ["main", "kk/x", nil] && list[0].isMain && !list[1].isMain && list[1].name == "x")
    }

    @Test func makesAWorktreeOnItsOwnBranchAndKeepsItOutOfStatus() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "my feature")
        #expect(w.branch == "kk/my-feature" && w.path.hasSuffix("/.worktrees/my-feature"))
        #expect(try await r.status().files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: w.path + "/a.txt"))
        let again = try await r.addWorktree(name: "my feature")
        #expect(again.path == w.path)
        let linked = GitRepo(root: URL(fileURLWithPath: w.path))
        #expect(linked.isLinkedWorktree && !r.isLinkedWorktree)
        #expect(try await linked.mainRoot().path == r.root.path)
        #expect(try await linked.addWorktree(name: "second").path.hasPrefix(r.root.path + "/.worktrees/"))
        let exclude = try String(contentsOf: r.root.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude.components(separatedBy: "/.worktrees/").count == 2)      // once, however many are made
    }

    @Test func removalWarnsAboutWhatItWouldLose() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        var state = try await r.worktreeState(w)
        #expect(state.uncommitted == 0 && state.unmerged == 0)
        try sh("echo more >> a.txt && git commit -qam work && echo new > c.txt", in: dir)
        state = try await r.worktreeState(w)
        #expect(state.uncommitted == 1 && state.unmerged == 1)
        await #expect(throws: GitRepo.Failure.self) { try await r.removeWorktree(w) }
        try await r.removeWorktree(w, force: true)
        #expect(!FileManager.default.fileExists(atPath: w.path))
        #expect(try await r.branches().contains { $0.name == "kk/x" })           // the branch keeps the work
        await #expect(throws: GitRepo.Failure.self) { try await r.removeWorktree(try await r.worktrees()[0]) }
    }

    @Test func mergesCleanlyOrLeavesThingsAsTheyWere() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        try sh("echo more >> a.txt && git commit -qam work", in: URL(fileURLWithPath: w.path))
        try await r.merge("kk/x")
        #expect(try String(contentsOf: r.root.appending(path: "a.txt"), encoding: .utf8) == "one\nmore\n")
        let w2 = try await r.addWorktree(name: "y")
        try sh("echo theirs > a.txt && git commit -qam theirs", in: URL(fileURLWithPath: w2.path))
        try sh("echo ours > a.txt && git commit -qam ours", in: r.root)
        await #expect(throws: GitRepo.Failure.self) { try await r.merge("kk/y") }
        #expect(try await r.status().files.isEmpty)
    }
}

@Suite struct SandboxInWorktreeTests {
    @Test func gitWorksInAWorktreeUnderTheSandbox() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        let out = await sandboxed("echo two >> a.txt && git add a.txt && git -c user.email=t@t -c user.name=t commit -qm sandboxed && git log --oneline | wc -l", in: dir)
        #expect(!out.isError && out.text.contains("2"), "\(out.text)")
    }

    @Test func whatRunsCodeLaterStaysClosed() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        let git = r.root.appending(path: ".git").path
        let name = dir.lastPathComponent
        for attempt in ["echo evil > \(git)/hooks/pre-commit", "echo evil >> \(git)/config", "echo evil > \(git)/config.worktree",
                        "echo evil > \(git)/worktrees/\(name)/config.worktree", "echo /tmp/evil > \(git)/worktrees/\(name)/commondir",
                        "echo /tmp/evil > \(git)/worktrees/\(name)/gitdir", "echo gitdir: /tmp/evil > .git"] {
            let out = await sandboxed(attempt, in: dir)
            #expect(out.isError && out.text.contains("Operation not permitted") || out.text.contains("The sandbox blocked"), "\(attempt): \(out.text)")
        }
        #expect(!FileManager.default.fileExists(atPath: git + "/hooks/pre-commit"))
        #expect(try String(contentsOf: dir.appending(path: ".git"), encoding: .utf8).contains(git))
    }

    @Test func aWrittenGitFileOpensNothing() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let secret = base.appending(path: "secret")
        try FileManager.default.createDirectory(at: secret.appending(path: "worktrees/x"), withIntermediateDirectories: true)
        // A project anywhere, with the `.git` file a command could have written, naming a folder to open up.
        let plain = base.appending(path: "plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try "gitdir: \(secret.path)/worktrees/x\n".write(to: plain.appending(path: ".git"), atomically: true, encoding: .utf8)
        #expect(LinkedGit.of(plain) == nil)
        #expect(await sandboxed("echo x > \(secret.path)/stolen", in: plain).text.contains("not permitted"))
        // In the right place, naming another repository's folder.
        let r = try repo(in: base)
        let fake = r.root.appending(path: ".worktrees/fake")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        try "gitdir: \(secret.path)/worktrees/x\n".write(to: fake.appending(path: ".git"), atomically: true, encoding: .utf8)
        #expect(LinkedGit.of(fake) == nil)
        // Inside this repository's folder, with no link back.
        try FileManager.default.createDirectory(at: r.root.appending(path: ".git/worktrees/fake"), withIntermediateDirectories: true)
        try "gitdir: \(r.root.path)/.git/worktrees/fake\n".write(to: fake.appending(path: ".git"), atomically: true, encoding: .utf8)
        #expect(LinkedGit.of(fake) == nil)
        #expect(!FileManager.default.fileExists(atPath: secret.path + "/stolen"))
    }

    @Test func aNormalRepositoryIsAsBeforeAndItsCommondirClosed() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        #expect(LinkedGit.of(r.root) == nil)
        let out = await sandboxed("git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x && git log --oneline | wc -l", in: r.root)
        #expect(out.text.contains("2"), "\(out.text)")
        #expect(await sandboxed("echo /tmp/evil > .git/commondir", in: r.root).text.contains("not permitted"))
    }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var results: [ChatMessage] { lock.withLock { items.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } } }
    var injected: [ChatMessage] { lock.withLock { items.compactMap { if case .injected(let m) = $0 { m } else { nil } } } }
}

@Suite struct IsolatedSubagentTests {
    private let writing = #"{"description":"Add a file","prompt":"Add c.txt.","agent":"general","isolation":"worktree"}"#
    private func run(_ turns: [[Data]], in root: URL, background: Bool = false) async -> Events {
        let (client, _) = MockServer.client(.init(chunks: [], turns: turns))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        config.policy = PermissionPolicy(mode: .fullAuto)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("go")], config: config,
                            workspace: Workspace(root: root)) { events.add($0) }
        return events
    }

    @Test func itsWorkIsOnABranchAndTheProjectIsUntouched() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let events = await run([SSE.toolCall("c1", "task", writing),
                                SSE.toolCall("s1", "write_file", #"{"path":"c.txt","content":"new\n"}"#),
                                SSE.content("Added c.txt."), SSE.content("Done.")], in: r.root)
        let report = try #require(events.results.first?.content)
        #expect(!FileManager.default.fileExists(atPath: r.root.appending(path: "c.txt").path))    // not in the project
        let branch = try #require(try await r.branches().first { $0.name.hasPrefix("kk/task-") })
        #expect(report.contains(branch.name) && report.contains("not merged"), "\(report)")
        #expect(try sh("git show \(branch.name):c.txt", in: r.root) == "new\n")
        #expect(try await r.worktrees().count == 1)                                               // the worktree is gone
        #expect(try await r.status().files.isEmpty)
    }

    @Test func aRunThatChangedNothingLeavesNoBranch() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let events = await run([SSE.toolCall("c1", "task", writing), SSE.content("Nothing to do."), SSE.content("Done.")], in: r.root)
        #expect(events.results.first?.content.contains("changed nothing") == true)
        #expect(try await r.branches().map(\.name) == ["main"])
        #expect(try await r.worktrees().count == 1)
    }

    @Test func itSeesTheCommittedProjectInItsOwnFolder() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("echo uncommitted >> a.txt", in: r.root)
        _ = await run([SSE.toolCall("c1", "task", writing), SSE.toolCall("s1", "bash", #"{"command":"pwd > where.txt; cat a.txt >> where.txt"}"#),
                       SSE.content("Looked."), SSE.content("Done.")], in: r.root)
        let branch = try #require(try await r.branches().first { $0.name.hasPrefix("kk/task-") })
        let output = try sh("git show \(branch.name):where.txt", in: r.root)
        #expect(output.contains("/.worktrees/task-") && !output.contains("uncommitted"), "\(output)")
    }

    @Test func aProjectWithoutGitIsToldSo() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let events = await run([SSE.toolCall("c1", "task", writing), SSE.content("Done.")], in: base)
        #expect(events.results.first?.content.contains("git repository") == true)
    }

    @Test func isolationLetsAWriterRunInTheBackground() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let plain = #"{"description":"Add a file","prompt":"Add c.txt.","agent":"general","background":true}"#
        let refused = await run([SSE.toolCall("c1", "task", plain), SSE.content("Done.")], in: r.root)
        #expect(refused.results.first?.content.contains("background runs are for") == true)
        let isolated = #"{"description":"Add a file","prompt":"Add c.txt.","agent":"general","background":true,"isolation":"worktree"}"#
        let events = await run([SSE.toolCall("c1", "task", isolated), SSE.content("It'll report."), SSE.content("Added."), SSE.content("Thanks.")], in: r.root)
        #expect(events.results.first?.content.contains("Started the general subagent") == true)
    }

    @Test func anAgentFileCanAskForIt() throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appending(path: ".kurtkode/agents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: fixer\ndescription: Fixes things\nisolation: worktree\n---\nFix it.\n".write(to: dir.appending(path: "fixer.md"), atomically: true, encoding: .utf8)
        let agent = AgentDefinitions.load(workspace: base, home: base).first { $0.name == "fixer" }
        #expect(agent?.isolated == true)
    }
}

@Suite struct GitPanelOperationTests {
    @Test func branchesAndSwitching() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try await r.createBranch("feature")
        #expect(try await r.status().branch == "feature")
        #expect(try await r.branches().first { $0.isCurrent }?.name == "feature")
        try await r.switchBranch("main")
        #expect(try await r.branches().count == 2)
        #expect(await r.defaultBranch() == "main")
    }

    @Test func aStashTakesNewFilesAndComesBack() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("echo more >> a.txt && echo new > n.txt", in: r.root)
        try await r.stash(message: "half done")
        #expect(try await r.status().files.isEmpty)
        let s = try #require(try await r.stashes().first)
        #expect(s.message.contains("half done"))
        try await r.stashPop(s)
        #expect(try await r.status().files.count == 2)
        #expect(try await r.stashes().isEmpty)
    }

    @Test func pushesAndSetsTheUpstreamTheFirstTime() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("git init -q --bare ../remote.git && git remote add origin ../remote.git", in: r.root)
        try await r.push(try await r.status())
        var s = try await r.status()
        #expect(s.upstream == "origin/main")
        try sh("echo more >> a.txt && git commit -qam second", in: r.root)
        s = try await r.status()
        #expect(s.ahead == 1)
        try await r.push(s)
        #expect(try await r.status().ahead == 0)
        try await r.pull()
    }

    @Test func aPullRequestsPageComesFromTheRemote() {
        func url(_ remote: String, _ base: String? = "main") -> String? {
            GitRepo.compareURL(remote: remote, branch: "kk/x", base: base)?.absoluteString
        }
        #expect(url("git@github.com:me/repo.git") == "https://github.com/me/repo/compare/main...kk/x?expand=1")
        #expect(url("https://github.com/me/repo") == "https://github.com/me/repo/compare/main...kk/x?expand=1")
        #expect(url("https://x:SECRET@github.com/me/repo.git", nil) == "https://github.com/me/repo/compare/kk/x?expand=1")
        #expect(url("git@gitlab.com:me/repo.git")?.hasPrefix("https://gitlab.com/me/repo/-/merge_requests/new") == true)
        #expect(url("https://example.com/me/repo.git") == nil && url("/local/path") == nil)
    }

    @Test func diffsAgainstTheLastCommitAndTheBranchesStart() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try await r.createBranch("feature")
        try sh("echo more >> a.txt && git commit -qam work && echo typed >> b.txt && echo new > n.txt && git mv a.txt moved.txt", in: r.root)
        let now = try await r.changes(.uncommitted)
        #expect(Set(now.map(\.path)) == ["b.txt", "moved.txt", "n.txt"])
        #expect(now.first { $0.path == "moved.txt" }?.oldPath == "a.txt")
        #expect(now.first { $0.path == "n.txt" }?.kind == .added && now.first { $0.path == "n.txt" }?.additions == 1)
        #expect(now.first { $0.path == "b.txt" }?.additions == 1)
        let all = try await r.changes(.branch("main"))
        #expect(Set(all.map(\.path)).isSuperset(of: ["b.txt", "moved.txt", "n.txt"]))    // the commit counts here too
        #expect(try await r.patch(.branch("main")).contains("+more"))
        let new = try #require(now.first { $0.path == "n.txt" })
        #expect(try await r.patch(.uncommitted, change: new).contains("+new"))
        #expect(try await r.patch(.uncommitted).contains("+typed"))
    }

    @Test func commentsPointAtTheNewFilesLines() {
        let hunk: [Substring] = ["@@ -10,3 +20,4 @@ func f()", " same", "-gone", "+new one", "+new two", " same"]
        #expect(UnifiedDiff.newLineNumbers(hunk) == [nil, 20, nil, 21, 22, 23])
        let text = ReviewComment.message([ReviewComment(path: "b.swift", line: 9, quote: "+x", text: "Why?"),
                                          ReviewComment(path: "a.swift", line: nil, quote: "-y", text: "Keep this\nplease")])
        #expect(text.range(of: "a.swift (a removed line)")!.lowerBound < text.range(of: "b.swift:9")!.lowerBound)
        #expect(text.contains("  Keep this\n  please") && text.contains("> +x"))
    }

    @Test func editorsOpenAtTheLine() {
        #expect(Editor.vscode.arguments(path: "/a.swift", line: 7) == ["-g", "/a.swift:7"])
        #expect(Editor.zed.arguments(path: "/a.swift", line: 7) == ["/a.swift:7"])
        #expect(Editor.xcode.arguments(path: "/a.swift", line: 7) == ["-l", "7", "/a.swift"])
        #expect(Editor.vscode.arguments(path: "/a.swift", line: nil) == ["-g", "/a.swift"])
        #expect(Editor.system.command(path: "/a", line: 1) == nil)
    }

    @Test func aCommitMessageLosesItsFence() {
        #expect(CommitMessage.clean("```\nFix the parser\n\nIt split on spaces.\n```\n") == "Fix the parser\n\nIt split on spaces.")
        #expect(CommitMessage.clean("  \n") == nil)
    }

    @Test func aCommitMessageIsWrittenAndItsCostRecorded() async throws {
        let (client, host) = MockServer.client(.init(chunks: SSE.content("Fix the parser")))
        final class Box: @unchecked Sendable { let lock = NSLock(); var entries: [CostEntry] = [] }
        let box = Box()
        let sink = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: nil) { e in box.lock.withLock { box.entries.append(e) } }
        let text = await CommitMessage.write(diff: "+a line", client: client, model: "m", limits: TurnLimits(), costs: sink)
        #expect(text == "Fix the parser" && box.lock.withLock { box.entries.map(\.purpose) } == [.commitMessage])
        #expect(String(decoding: try #require(MockServer.requestBody(host)), as: UTF8.self).contains("+a line"))
    }
}
