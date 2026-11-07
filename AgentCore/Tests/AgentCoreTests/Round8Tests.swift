import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// Round 8's probes (FUNCTIONAL_TESTS.md section 22): one per finding of the four reviews. Each states what should hold,
// so it fails while the finding stands.

/// Outside the temp folders: the sandbox lets commands write those, so a repository there couldn't show what it blocks.
private func scratch(_ file: String = #filePath) throws -> URL {
    let base = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/kk-r8-\(UUID().uuidString.prefix(8))")
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

private func sandboxed(_ command: String, in root: URL, policy: SandboxPolicy = SandboxPolicy()) async -> ToolOutput {
    let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(["command": .string(command)])), as: UTF8.self)
    var config = AgentConfig(tools: [BashTool()])
    config.sandbox = policy
    return await AgentLoop.execute(ToolCall(id: "t", name: "bash", arguments: json), tools: ["bash": BashTool()],
                                   config: config, workspace: Workspace(root: root))
}

/// A script that leaves `marker` if anything runs it.
private func tripwire(in base: URL) throws -> (script: String, marker: String) {
    let script = base.appending(path: "tripwire.sh"), marker = base.appending(path: "RAN").path
    try "#!/bin/sh\ntouch '\(marker)'\n".write(to: script, atomically: true, encoding: .utf8)
    try sh("chmod +x '\(script.path)'", in: base)
    return (script.path, marker)
}

private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

@Suite(.serialized) struct Round8WorktreeTests {
    // W1: a repository the sandbox may make, whose config git follows when kurtkode runs it outside the sandbox.
    @Test func r8_w1_aNestedRepositorysConfigDoesntRunWhenASubagentFinishes() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let wire = try tripwire(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let dir = URL(fileURLWithPath: run.worktree.path)
        let out = await sandboxed("git init -q sub && git -C sub config core.fsmonitor '\(wire.script)' && git -C sub -c user.email=t@t "
            + "-c user.name=t commit -q --allow-empty -m x && git add sub && echo $?", in: dir)
        #expect(out.text.contains("0"), "\(out.text)")
        _ = await run.finish(title: "work")
        #expect(!exists(wire.marker), "the nested repository's core.fsmonitor ran outside the sandbox")
    }

    @Test func r8_w1b_aNestedRepositorysConfigDoesntRunOnAStatus() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let wire = try tripwire(in: base)
        _ = await sandboxed("git init -q sub && git -C sub config core.fsmonitor '\(wire.script)' && git -C sub -c user.email=t@t "
            + "-c user.name=t commit -q --allow-empty -m x && git add sub", in: r.root)
        _ = try await r.status()
        #expect(!exists(wire.marker), "a Git panel refresh ran the nested repository's core.fsmonitor")
    }

    // W2: what another worktree's git would follow.
    @Test func r8_w2a_oneWorktreeCantRedirectAnother() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let a = try await r.addWorktree(name: "a"), b = try await r.addWorktree(name: "b")
        let wire = try tripwire(in: base)
        let evil = "/tmp/kk-r8-\(UUID().uuidString.prefix(8))"; defer { try? FileManager.default.removeItem(atPath: evil) }
        let git = r.root.appending(path: ".git").path
        let bName = URL(fileURLWithPath: b.path).lastPathComponent
        _ = await sandboxed("git init -q \(evil) && git -C \(evil) config core.fsmonitor '\(wire.script)' && echo \(evil)/.git > \(git)/worktrees/\(bName)/commondir",
                            in: URL(fileURLWithPath: a.path))
        #expect(try String(contentsOfFile: "\(git)/worktrees/\(bName)/commondir", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "../..",
                "worktree a rewrote worktree b's commondir")
        _ = try? await GitRepo(root: URL(fileURLWithPath: b.path)).status()
        #expect(!exists(wire.marker), "git in worktree b ran another repository's core.fsmonitor outside the sandbox")
    }

    @Test func r8_w2b_aWorktreeCantForgeANewOne() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let a = try await r.addWorktree(name: "a")
        let git = r.root.appending(path: ".git").path
        let out = await sandboxed("mkdir -p \(git)/worktrees/pwn && echo /tmp/pwn/.git > \(git)/worktrees/pwn/gitdir", in: URL(fileURLWithPath: a.path))
        #expect(!exists("\(git)/worktrees/pwn/gitdir"), "\(out.text)")
    }

    @Test func r8_w2c_theMainCheckoutCantRedirectAWorktree() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let name = URL(fileURLWithPath: w.path).lastPathComponent
        _ = await sandboxed("echo /tmp/evil > .git/worktrees/\(name)/commondir; echo gitdir: /tmp/evil > .worktrees/\(name)/.git; echo evil > .git/config.worktree", in: r.root)
        #expect(try String(contentsOf: r.root.appending(path: ".git/worktrees/\(name)/commondir"), encoding: .utf8).contains("../.."), "commondir rewritten")
        #expect(try String(contentsOf: URL(fileURLWithPath: w.path).appending(path: ".git"), encoding: .utf8).contains(r.root.path), ".git file rewritten")
        #expect(!exists(r.root.appending(path: ".git/config.worktree").path), "config.worktree written")
    }

    @Test func r8_w2d_aWorktreeCantMoveTheMainCheckoutsHead() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let a = try await r.addWorktree(name: "a")
        _ = await sandboxed("echo 'ref: refs/heads/kk/a' > \(r.root.path)/.git/HEAD", in: URL(fileURLWithPath: a.path))
        #expect(try String(contentsOf: r.root.appending(path: ".git/HEAD"), encoding: .utf8).contains("refs/heads/main"))
    }

    // W3: a rename is checked on the path it names, not on what's under it.
    @Test func r8_w3a_renamingAWorktreesGitFolderDoesntGetRoundItsGuards() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let name = URL(fileURLWithPath: w.path).lastPathComponent
        let git = r.root.appending(path: ".git").path, away = "/tmp/kk-r8-\(UUID().uuidString.prefix(8))"
        _ = await sandboxed("mv \(git)/worktrees/\(name) \(away) && echo /tmp/evil > \(away)/commondir; mv \(away) \(git)/worktrees/\(name)", in: URL(fileURLWithPath: w.path))
        #expect(try String(contentsOfFile: "\(git)/worktrees/\(name)/commondir", encoding: .utf8).contains("../.."), "commondir rewritten by a rename")
    }

    @Test func r8_w3b_renamingDotGitDoesntGetRoundItsGuards() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let away = "/tmp/kk-r8-\(UUID().uuidString.prefix(8))"
        _ = await sandboxed("mv .git \(away) && echo '#!/bin/sh' > \(away)/hooks/pre-commit; mv \(away) .git", in: r.root)
        #expect(!exists(r.root.appending(path: ".git/hooks/pre-commit").path), "a hook written through a rename of .git")
    }

    @Test func r8_w3c_renamingAWorktreeDoesntGetRoundItsGuards() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let away = "/tmp/kk-r8-\(UUID().uuidString.prefix(8))"
        _ = await sandboxed("cd / && mv \(w.path) \(away) && echo gitdir: /tmp/evil > \(away)/.git; mv \(away) \(w.path)", in: URL(fileURLWithPath: w.path))
        #expect(try String(contentsOf: URL(fileURLWithPath: w.path).appending(path: ".git"), encoding: .utf8).contains(r.root.path), ".git file rewritten by a rename")
    }

    // W4, W5: a subagent's work.
    @Test func r8_w4_aCommitThatFailsDoesntLoseTheWork() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("git config commit.gpgsign true && git config gpg.program /usr/bin/false", in: r.root)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        try "the work\n".write(to: URL(fileURLWithPath: run.worktree.path).appending(path: "new.txt"), atomically: true, encoding: .utf8)
        let report = await run.finish(title: "work")
        #expect(!report.contains("changed nothing"), "\(report)")
        let kept = try sh("git log --all --format=%s", in: r.root).contains("work") || exists(run.worktree.path + "/new.txt")
        #expect(kept, "the subagent's file is gone")
    }

    @Test func r8_w4b_workThatCantBeCommittedStaysInItsWorktree() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let dir = URL(fileURLWithPath: run.worktree.path)
        try sh("echo x > new.txt && touch \"$(git rev-parse --git-dir)/index.lock\"", in: dir)
        let report = await run.finish(title: "work")
        #expect(exists(run.worktree.path), "\(report)")
        #expect(report.contains(run.worktree.path))
    }

    @Test func r8_w5c_aDetachedHeadsCommitsGoOnTheBranch() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let branch = try #require(run.worktree.branch)
        let sha = try sh("git checkout -q --detach && echo x > c.txt && git add . && git commit -qm detached && git rev-parse HEAD", in: URL(fileURLWithPath: run.worktree.path))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = await run.finish(title: "work")
        #expect(try sh("git rev-parse \(branch)", in: r.root).contains(sha), "\(report)")
        #expect(report.contains(branch))
    }

    @Test func r8_w5d_aCommitAndItsRevertAreNotChangedNothing() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        try sh("echo x > c.txt && git add . && git commit -qm in && git rm -q c.txt && git commit -qm out", in: URL(fileURLWithPath: run.worktree.path))
        let report = await run.finish(title: "work")
        #expect(!report.contains("changed nothing"), "\(report)")
    }

    @Test func r8_nothingDoneStillLeavesNothingBehind() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let report = await run.finish(title: "work")
        #expect(report.contains("changed nothing") && !exists(run.worktree.path))
        #expect(try !sh("git branch", in: r.root).contains("task-"))
    }

    @Test func r8_w8_removalAsksAgainIfTheWorktreeChanged() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let told = try await r.worktreeState(w)
        try sh("echo x > c.txt", in: URL(fileURLWithPath: w.path))
        let now = try await r.removeWorktree(w, told: told, deleteBranch: true)
        #expect(now?.uncommitted == 1 && exists(w.path + "/c.txt"))
        _ = try await r.removeWorktree(w, told: try #require(now), deleteBranch: true)
        #expect(!exists(w.path))
    }

    @Test func r8_w11_mergeChecksWhatsCheckedOut() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        try sh("echo x > c.txt && git add . && git commit -qm work", in: URL(fileURLWithPath: w.path))
        try sh("git switch -q -c elsewhere", in: r.root)
        await #expect(throws: GitRepo.Failure.self) { try await r.merge("kk/x", into: "main") }
        #expect(!exists(r.root.appending(path: "c.txt").path))
    }

    @Test func r8_w10b_aStashThatsGoneIsSaidToBe() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("echo one >> a.txt", in: r.root)
        try await r.stash(message: "first")
        let shown = try await r.stashes()[0]
        try await r.stashDrop(shown)
        await #expect(throws: GitRepo.Failure.self) { try await r.stashDrop(shown) }
    }

    @Test func r8_w5a_commitsOnADetachedHeadAreKept() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let dir = URL(fileURLWithPath: run.worktree.path)
        let sha = try sh("git checkout -q --detach && echo x > c.txt && git add . && git commit -qm detached && git rev-parse HEAD", in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = await run.finish(title: "work")
        let refs = try sh("git for-each-ref --contains \(sha)", in: r.root)
        #expect(!refs.isEmpty || exists(run.worktree.path), "\(report)")
    }

    @Test func r8_w5b_commitsLeftOnTheBranchAreKeptAfterASwitch() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let run = try await IsolatedRun.start(from: r.root, id: UUID())
        let dir = URL(fileURLWithPath: run.worktree.path)
        let sha = try sh("echo x > c.txt && git add . && git commit -qm mine && git rev-parse HEAD", in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        try sh("git switch -q -c other \(run.start)", in: dir)
        let report = await run.finish(title: "work")
        let refs = try sh("git for-each-ref --contains \(sha)", in: r.root)
        #expect(!refs.isEmpty, "\(report)")
    }

    // W6, W7, W10, W12: the Git panel's operations.
    @Test func r8_w6_mergeLeavesAMergeTheUserHadOpen() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x"), y = try await r.addWorktree(name: "y")
        try sh("echo theirs > a.txt && git commit -qam theirs", in: URL(fileURLWithPath: w.path))
        try sh("echo other > z.txt && git add . && git commit -qm other", in: URL(fileURLWithPath: y.path))
        try sh("echo ours > a.txt && git commit -qam ours; git merge kk/x; echo resolved by hand > a.txt", in: r.root)
        #expect(exists(r.root.appending(path: ".git/MERGE_HEAD").path))
        try? await r.merge("kk/y")
        #expect(exists(r.root.appending(path: ".git/MERGE_HEAD").path), "the user's open merge was aborted")
        #expect(try String(contentsOf: r.root.appending(path: "a.txt"), encoding: .utf8).contains("resolved by hand"), "the hand resolution is gone")
    }

    @Test func r8_w7_aDetachedWorktreesCommitsCountAsUnmerged() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        try sh("git checkout -q --detach && echo x > c.txt && git add . && git commit -qm detached", in: URL(fileURLWithPath: w.path))
        let now = try await r.worktrees().first { $0.path == w.path }!
        #expect(try await r.worktreeState(now).unmerged == 1)
    }

    @Test func r8_w9_aBranchNameIsNotAnOptionToPush() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        // In /tmp: a ref's path can't have a component starting with a dot, and `.build` does.
        let tmp = URL(fileURLWithPath: "/private/tmp/kk-r8-\(UUID().uuidString.prefix(8))"); defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let wire = try tripwire(in: tmp)
        try sh("git init -q --bare ../remote.git && git remote add origin ../remote.git", in: r.root)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path), ref = "refs/heads/--receive-pack=\(wire.script)"
        let out = await sandboxed("git update-ref '\(ref)' HEAD && git symbolic-ref HEAD '\(ref)' && git status | head -1", in: dir)
        let here = GitRepo(root: dir)
        let status = try await here.status()
        #expect(status.branch?.hasPrefix("--") == true, "\(out.text)")
        try? await here.push(status)
        #expect(!exists(wire.marker), "a branch name ran a program through git push")
    }

    @Test func r8_w10_droppingAStashDropsThatStash() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("echo one >> a.txt", in: r.root)
        try await r.stash(message: "keep me not")
        let shown = try await r.stashes()[0]
        try sh("echo two >> a.txt", in: r.root)
        try await r.stash(message: "another session's")
        try await r.stashDrop(shown)
        let left = try await r.stashes().map(\.message).joined()
        #expect(left.contains("another session's"), "dropped the wrong stash; left: \(left)")
    }

    @Test func r8_w12_aWorktreeFromAWorktreeStartsAtItsHead() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        let head = try sh("echo x > c.txt && git add . && git commit -qm feature && git rev-parse HEAD", in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
        let run = try await IsolatedRun.start(from: dir, id: UUID())
        #expect(run.start == head)
    }

    @Test func r8_w13_planModesSandboxIsReadOnlyInAWorktree() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        let policy = AgentLoop.planSandbox(Workspace(root: dir), nil)!
        let git = r.root.appending(path: ".git").path
        let out = await sandboxed("git update-ref refs/heads/planned HEAD; echo x > \(git)/refs/heads/planned2", in: dir, policy: policy)
        #expect(!exists("\(git)/refs/heads/planned") && !exists("\(git)/refs/heads/planned2"), "\(out.text)")
    }
}

@Suite struct Round8CapabilityTests {
    private func fetchRule(_ url: String) -> PermissionRule? {
        let rules = PermissionRules(rules: [PermissionRule(action: .deny, tool: "WebFetch", specifier: "domain:evil.example", source: "t")])
        return rules.decision(toolName: "web_fetch", args: ToolArguments(["url": .string(url)]))
    }

    // C1
    @Test func r8_c1a_aSpaceBeforeTheAddressDoesntEscapeADeny() { #expect(fetchRule(" https://evil.example/a")?.action == .deny) }
    @Test func r8_c1b_aTrailingDotDoesntEscapeADeny() { #expect(fetchRule("https://evil.example./a")?.action == .deny) }

    @Test func r8_c1c_otherSpellingsOfAHostDontEscapeADeny() {
        for url in ["https://EVIL.example../a", "https://%65vil.example/a", "\nhttps://sub.evil.example/a"] {
            #expect(fetchRule(url)?.action == .deny, "\(url)")
        }
        #expect(fetchRule("https://notevil.example/a") == nil)
    }

    @Test func r8_c1d_anAddressWithNoHostDoesntPassADeny() { #expect(fetchRule("not a url")?.action == .deny) }

    // C2
    @Test func r8_c2b_otherServersAndAllowsStayApart() throws {
        let deny = PermissionRules(rules: [try #require(PermissionRule("mcp__srv", action: .deny, source: "t"))])
        #expect(deny.decision(toolName: "mcp_read_resource", args: ToolArguments(["server": .string("other"), "uri": .string("x")])) == nil)
        let allow = PermissionRules(rules: [try #require(PermissionRule("mcp__srv", action: .allow, source: "t"))])
        #expect(allow.decision(toolName: "mcp_list_resources", args: ToolArguments()) == nil, "an allow on one server doesn't allow listing them all")
        #expect(allow.decision(toolName: "mcp_read_resource", args: ToolArguments(["server": .string("srv"), "uri": .string("x")]))?.action == .allow)
        let oneTool = PermissionRules(rules: [try #require(PermissionRule("mcp__srv__search", action: .deny, source: "t"))])
        #expect(oneTool.decision(toolName: "mcp_read_resource", args: ToolArguments(["server": .string("srv"), "uri": .string("x")])) == nil)
    }

    @Test func r8_c2c_aHookMatcherOnAServerFindsItsResources() {
        #expect(HookMatcher(matcher: "mcp__srv__.*", hooks: []).matches("mcp_read_resource", server: "srv"))
        #expect(!HookMatcher(matcher: "mcp__srv__.*", hooks: []).matches("mcp_read_resource", server: "other"))
    }

    @Test func r8_f2_aTitleRequestKeepsTheModelsProviders() {
        let only = ProviderRouting(order: ["acme"], allowFallbacks: false)
        #expect(ChatTitle.question(request: "r", reply: "a", model: "m", providers: only).provider == only)
    }

    // C2
    @Test func r8_c2_aDenyOnAServerCoversItsResources() throws {
        let rule = try #require(PermissionRule("mcp__srv", action: .deny, source: "t"))
        let rules = PermissionRules(rules: [rule])
        let args = ToolArguments(["server": .string("srv"), "uri": .string("file:///x")])
        #expect(rules.decision(toolName: "mcp_read_resource", args: args)?.action == .deny)
        #expect(rules.decision(toolName: "mcp_list_resources", args: ToolArguments(["server": .string("srv")]))?.action == .deny)
    }

    // C3
    @Test func r8_c3a_aWithheldNameIsWithheldThroughALink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "config"), withIntermediateDirectories: true)
        try "SECRET=1\n".write(to: root.appending(path: "config/prod.conf"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: ".env").path, withDestinationPath: "config/prod.conf")
        var ws = Workspace(root: root)
        ws.withheld = WithheldFiles(patterns: WithheldFiles.defaults, host: "api.example.com")
        #expect(throws: ToolFailure.self) { try ws.resolve(".env") }
    }

    @Test func r8_c3c_aLinkToAWithheldFileIsWithheld() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "SECRET=1\n".write(to: root.appending(path: ".env"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "notes.txt").path, withDestinationPath: ".env")
        var ws = Workspace(root: root)
        ws.withheld = WithheldFiles(patterns: WithheldFiles.defaults, host: "api.example.com")
        #expect(throws: ToolFailure.self) { try ws.resolve("notes.txt") }
    }

    @Test func r8_c3d_anAllowGoesByTheFileNotTheLink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "docs"), withIntermediateDirectories: true)
        try "SECRET=1\n".write(to: root.appending(path: "secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "docs/ok.txt").path, withDestinationPath: "../secret.txt")
        let rules = PermissionRules(rules: [try #require(PermissionRule("Read(docs/**)", action: .allow, source: "t"))], root: root)
        #expect(rules.decision(toolName: "read_file", args: ToolArguments(["path": .string("docs/ok.txt")])) == nil)
    }

    @Test func r8_c3b_aReadDenyHoldsThroughALink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "config"), withIntermediateDirectories: true)
        try "SECRET=1\n".write(to: root.appending(path: "config/prod.conf"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: ".env").path, withDestinationPath: "config/prod.conf")
        let rule = try #require(PermissionRule("Read(./.env)", action: .deny, source: "t"))
        let rules = PermissionRules(rules: [rule], root: root)
        #expect(rules.decision(toolName: "read_file", args: ToolArguments(["path": .string(".env")]))?.action == .deny)
    }

    // C5
    @Test func r8_c5_aHookMatcherInClaudeCodesNameFindsWebFetch() {
        #expect(HookMatcher(matcher: "WebFetch", hooks: []).matches("web_fetch"))
    }

    // C6
    @Test func r8_c6_aPageOfUnclosedCommentsIsNotQuadratic() {
        func time(_ n: Int) -> Double {
            let html = String(repeating: "<!-- ", count: n)
            let start = ContinuousClock.now
            _ = HTMLText.markdown(html, base: URL(string: "https://a.example/")!)
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        // It took 26 s before, and goes up with the square of the count.
        let seconds = time(16_000)
        #expect(seconds < 10, "\(seconds) s")
    }

    @Test func r8_c6b_noOtherUnclosedTagIsQuadraticEither() {
        func time(_ text: String) -> Double {
            let start = ContinuousClock.now
            _ = HTMLText.markdown(text, base: URL(string: "https://a.example/")!)
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        for piece in ["<script>", "<a href=x>", "<b>", "<a ", "<", "<main>", "<pre>", "<h1>", "<a></a ", "<p "] {
            let seconds = time(String(repeating: piece, count: 16_000))
            #expect(seconds < 10, "\(piece): \(seconds) s")
        }
    }

    @Test func r8_c6c_ordinaryPagesReadAsBefore() {
        let html = """
            <html><head><title>T</title></head><body><!-- gone --><script>x()</script><h1>One</h1>
            <p>Some <b>bold</b> and <a href="/l">a link</a>.</p><pre>code  here</pre><pre>more</pre><ul><li>item</ul></body></html>
            """
        let md = HTMLText.markdown(html, base: URL(string: "https://a.example/")!)
        #expect(md.contains("# One") && md.contains("**bold**") && md.contains("[a link](https://a.example/l)"), "\(md)")
        #expect(md.contains("```\ncode  here\n```") && md.contains("```\nmore\n```") && md.contains("- item"), "\(md)")
        #expect(!md.contains("gone") && !md.contains("x()"), "\(md)")
    }

    // C7
    @Test func r8_c7_readFileRefusesWhatIsntAFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sh("mkfifo pipe", in: root)
        let context = ToolContext(workspace: Workspace(root: root), maxOutputBytes: 8000)
        await #expect(throws: ToolFailure.self) { try await ReadFileTool().run(ToolArguments(["path": .string("pipe")]), context: context) }
    }

    // C12
    @Test func r8_c12_whatACompactionSummarizedIsntStillInContext() {
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
        var session = Session(header: header, messages: [.user("a"), .user("b"), .user("c")], model: "m", endpointID: header.endpointID)
        session.compactions = [Compaction(summary: "s", lastSummarizedID: session.messages[1].id, continuation: nil, tokensBefore: 1, tokensAfter: 1)]
        #expect(session.messagesInContext.map(\.content) == ["c"])
    }

    // C11
    @Test func r8_c11_aPageInsideAFormKeepsItsText() {
        let md = HTMLText.markdown("<html><body><form><p>the whole page lives in here</p></form></body></html>", base: URL(string: "https://a.example/")!)
        #expect(md.contains("the whole page lives in here"), "got: [\(md)]")
    }

    // C14
    @Test func r8_c14_aLongLatestMessageStillGivesAConversation() {
        let text = SideQuestion.transcript([.user("first"), .user(String(repeating: "x", count: 30_000))])
        #expect(!text.isEmpty)
    }

    // C15
    @Test func r8_c15_ipv6FormsOfPrivateAddressesAreRefused() {
        for a in ["::7f00:1", "fec0::1", "2002:7f00:1::", "64:ff9b::a9fe:a9fe", "ff02::1"] {
            #expect(WebFetchTool.isPrivate(a), "\(a)")
        }
    }
}

@Suite struct Round8SessionTests {
    // F12
    @Test func r8_f12_aForkIsntACutOffRun() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
        try await store.create(header)
        let answer = ChatMessage(role: .assistant, content: "one")
        for m in [ChatMessage.user("first"), answer] { try await store.append(.message(m), to: header.id) }
        let session = try #require(try await store.load(header.id))
        let fork = try await store.fork(session, atReply: answer.id, after: false, title: "forked")
        #expect(!fork.wasInterrupted)
    }

    // F14
    @Test func r8_f14_searchIgnoresAccentsWhenTheQueryHasNone() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-r8-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
        try await store.create(header)
        try await store.append(.message(.user("meet at the café")), to: header.id)
        #expect(try await store.search("cafe").map(\.id) == [header.id])
    }
}

@Suite struct Round8TerminalTests {
    private let plain = TerminalStyle(on: false)
    private func frame(_ input: InputState = InputState(), live: String = "", width: Int = 80) -> Frame {
        Frame.make(input: input, status: StatusInfo(), live: live, tail: [], width: width, height: 24, style: plain)
    }

    // T1
    @Test func r8_t1_escapesInTextDontReachTheTerminal() {
        let rows = frame(live: "before\u{1B}]52;c;aGVsbG8=\u{07}after\u{1B}[2K").rows
        #expect(!rows.joined().contains("\u{1B}"), "\(rows)")
    }

    @Test func r8_t1b_whatRunsIsShownEvenWhereAnEscapeWouldHideIt() {
        let shown = TerminalText.visible("ls -la \u{1B}]0;;touch pwned\u{07}\rx\u{202E}y")
        #expect(shown.contains("touch pwned") && !shown.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x202E }, "\(shown)")
    }

    @Test func r8_t1c_onlyThisProgramsStylesGetThroughTheLastCheck() {
        #expect(TerminalText.safe("\u{1B}[1mbold\u{1B}[0m") == "\u{1B}[1mbold\u{1B}[0m")
        #expect(TerminalText.safe("a\u{1B}[8mb\u{1B}[2Kc\u{1B}]52;c;x\u{1B}\\d\u{9B}2Je") == "abcde")
        #expect(TerminalText.plain("a\u{1B}]0;open").hasSuffix("open"), "what follows an unclosed sequence still shows")
        #expect(TerminalText.plain("one\r\ntwo\rthree\u{7}") == "one\ntwo\nthree")
    }

    // T4
    @Test func r8_t4_aFollowUpPromptTakesWholeWords() {
        #expect(!PromptWord.says("explain it", "e", "escalate") && PromptWord.says(" E ", "e", "escalate"))
        #expect(!PromptWord.yes("yeah but first look at it") && PromptWord.yes("Yes") && !PromptWord.yes(nil))
    }

    // C4
    @Test func r8_c4_aNumberTooBigIsNotACrash() throws {
        for number in ["1e20", "-1e20", "9.3e18", "1e308"] {
            let args = try ToolArguments(json: "{\"start\": \(number), \"path\": \(number)}")
            #expect(args.int("start") == nil)
            #expect(args.string("path")?.isEmpty == false)
        }
        #expect(try ToolArguments(json: "{\"n\": 3.7}").int("n") == 3)
        #expect(try ToolArguments(json: "{\"n\": 12}").string("n") == "12")
        #expect(ToolArguments(["n": .string("9223372036854775807")]).int("n") == nil)
    }

    // F1
    @Test func r8_f1_aPasteIsAMessageWhateverItStartsWith() {
        for start in ["!rm -rf x", "/compact", "# a heading"] {
            let paste = PastedText(id: 1, text: start + String(repeating: "\nline", count: 20))
            let text = PastedText.text(of: paste.token, [paste])
            #expect(UserShell.command(in: text) == nil && SlashCommands.parse(text) == nil && Memory.note(in: text) == nil)
            #expect(!InputState.isCommand(text))
            #expect(PastedText.withoutMark(text) == paste.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @Test func r8_f1b_aCommandTypedBeforeAPasteIsStillACommand() {
        let paste = PastedText(id: 1, text: String(repeating: "line\n", count: 20))
        #expect(UserShell.command(in: PastedText.text(of: "!cat <<EOF\n" + paste.token, [paste])) != nil)
    }

    @Test func r8_f1c_theComposerNeverSubmitsAPasteAsACommand() {
        var i = InputState()
        _ = i.handle(.paste("!touch pasted-ran" + String(repeating: "\nmore", count: 20)))
        guard case .submit(let text)? = i.handle(.enter) else { Issue.record("not submitted"); return }
        #expect(UserShell.command(in: text) == nil)
    }

    // T2
    @Test func r8_t2_wordsTypedAsAQuestionOpensDontAnswerIt() {
        let t = Date(timeIntervalSince1970: 0)
        var i = InputState()
        i.beginQuestion("Allow? ", now: t)
        _ = i.handle(.text("y"), now: t.addingTimeInterval(0.05))
        #expect(i.handle(.enter, now: t.addingTimeInterval(0.1)) == nil)
        #expect(i.buffer.isEmpty, "what was typed goes on the draft, not in the answer")
        i.endQuestion()
        #expect(i.buffer.string == "y")
    }

    @Test func r8_t2b_aWordTypedOnceTheQuestionIsUpAnswersIt() {
        let t = Date(timeIntervalSince1970: 0)
        var i = InputState()
        i.beginQuestion("Allow? ", now: t)
        _ = i.handle(.text("n"), now: t.addingTimeInterval(1))
        #expect(i.handle(.enter, now: t.addingTimeInterval(1)) == .answer("n"))
    }

    // T6
    @Test func r8_t6a_aLongQuestionFitsItsRows() {
        var i = InputState()
        i.beginQuestion(String(repeating: "Escalate to the stronger model for a price? ", count: 3))
        for row in frame(i, width: 80).rows { #expect(TerminalText.width(row) < 80, "\(row)") }
    }

    @Test func r8_t6b_anOptionsNewlinesStayOutOfItsRows() {
        var i = InputState()
        let q = UserQuestion(question: "Which?", header: "", options: [.init("a\nb", description: "two\nlines")], multiple: false)
        i.beginQuestion("  › ", choices: QuestionChoices(q))
        for row in frame(i).rows { #expect(!row.contains("\n"), "\(row)") }
    }

    // F9
    @Test func r8_f9_commandsPutBackDontTakeWhatFollows() {
        #expect(UserShell.command(in: joinedDraft(["!npm test", "and then fix it"])) == nil)
        #expect(joinedDraft(["fix it", "!npm test"]) == "fix it\n\n!npm test")
        #expect(joinedDraft(["!npm test", ""]) == "!npm test")
    }

    // F10
    @Test func r8_f10_aMessageStaysBehindACommand() {
        var i = InputState()
        i.enqueue("first")
        i.enqueue("!npm test")
        i.enqueue("then this")
        #expect(i.takeQueuedMessages() == ["first"])
        #expect(i.takeQueuedMessages().isEmpty)
        #expect(i.nextQueued() == "!npm test")
        #expect(i.nextQueued() == "then this")
    }

    // F11
    @Test func r8_f11_upAfterDownWalksTheCurrentHistory() {
        var i = InputState(history: ["alpha"])
        _ = i.handle(.up)
        _ = i.handle(.down)
        i.buffer.set("beta")
        _ = i.handle(.enter)
        _ = i.handle(.up)
        #expect(i.buffer.string == "beta")
    }

    // F13
    @Test func r8_f13_sendingARecalledPromptKeepsWhatWasTyped() {
        var i = InputState(history: ["alpha"])
        i.buffer.set("half a thought")
        _ = i.handle(.up)
        #expect(i.buffer.string == "alpha")
        #expect(i.handle(.enter) == .submit("alpha"))
        #expect(i.buffer.string == "half a thought")
    }

    // T7
    @Test func r8_t7_aQuestionEndsAHistorySearch() {
        var i = InputState(history: ["yes"])
        _ = i.handle(.ctrl("r"))
        i.beginQuestion("Allow? ", now: .distantPast)
        _ = i.handle(.text("y"))
        #expect(i.handle(.enter) == .answer("y"))
    }

    // T9
    @Test func r8_t9_aLongPasteInAnAnswerIsTheText() {
        var i = InputState()
        i.beginQuestion("Why not? ", now: .distantPast)
        let text = (1...30).map { "line \($0)" }.joined(separator: "\n")
        _ = i.handle(.paste(text))
        guard case .answer(let a)? = i.handle(.enter) else { Issue.record("no answer"); return }
        #expect(a == text, "\(a ?? "nil")")
    }

    // T10
    @Test func r8_t10_anImageAloneDuringARunIsntABlankMessage() {
        var i = InputState()
        i.busy = true
        i.addImage(ImageAttachment(mediaType: "image/png", path: "/tmp/x.png", width: 1, height: 1))
        #expect(i.handle(.enter) != .submit(""))
    }

    // T12
    @Test func r8_t12_aTabAndAnEscapeInTheBufferAreNotDrawnRaw() {
        var i = InputState()
        _ = i.handle(.paste("a\tb\u{1B}[2Kc"))
        let rows = frame(i).rows.joined()
        #expect(!rows.contains("\t") && !rows.contains("\u{1B}"), "\(rows)")
    }

    // T13
    @Test func r8_t13_wideEmojiMeasureTwo() {
        for s in ["✅", "❌", "⭐", "⚡"] { #expect(TerminalText.width(s) == 2, "\(s)") }
    }

    // T14
    @Test func r8_t14_altLetterIsntEsc() {
        var d = KeyDecoder()
        #expect(!d.feed(Array("\u{1B}d".utf8)).contains(.esc))
    }
}

// Found while fixing the others: it killed the test run twice, and would end the app or the CLI the same way.
@Suite struct Round8ChildPipeTests {
    @Test func r8_aChildThatDoesntReadItsInputDoesntEndThisProcess() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        for _ in 0..<5 { _ = try await r.git(["rev-parse", "HEAD"], input: String(repeating: "x", count: 1_000_000)) }
    }
}

// W1 and W3 again, through every operation kurtkode's git has, and what a worktree's commands still have to be able to do.
@Suite(.serialized) struct Round8SandboxFollowUpTests {
    @Test func r8_w1c_noOperationRunsANestedRepositorysConfig() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let wire = try tripwire(in: base)
        _ = await sandboxed("git init -q sub && git -C sub config core.fsmonitor '\(wire.script)' && git -C sub -c user.email=t@t "
            + "-c user.name=t commit -q --allow-empty -m x && echo dirty > sub/f && git add sub && echo two >> a.txt", in: r.root)
        let status = try await r.status()
        #expect(status.files.contains { $0.path == "sub" }, "a new submodule still shows: \(status.files)")
        for f in status.files { _ = try await r.diff(f) }
        _ = try await r.changes(.uncommitted)
        _ = try await r.patch(.uncommitted)
        _ = await Workspace(root: r.root).gitSummary()
        _ = await Workspace(root: r.root).files()
        try await r.stage(["a.txt"])
        try await r.stageAll()
        _ = try await r.stagedDiff()
        try await r.commit(message: "with the nested one")
        try await r.createBranch("two")
        try await r.switchBranch("main")
        try "x\n".write(to: r.root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try await r.stash(message: "s")
        try await r.stashPop(try await r.stashes()[0])
        let w = try await r.addWorktree(name: "x")
        _ = try await r.worktreeState(w)
        #expect(!exists(wire.marker), "an operation ran the nested repository's core.fsmonitor")
    }

    @Test func r8_w1d_aSubmodulesNewCommitStillShows() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("git init -q sub && git -C sub commit -q --allow-empty -m one && git add sub && git commit -qm sub && git -C sub commit -q --allow-empty -m two", in: r.root)
        #expect(try await r.status().files.map(\.path) == ["sub"])
    }

    @Test func r8_w3d_aFolderAboveTheProjectCantBeRenamed() async throws {
        let base = URL(fileURLWithPath: "/private/tmp/kk-r8-\(UUID().uuidString.prefix(8))"); defer { try? FileManager.default.removeItem(at: base) }
        let d = base.appending(path: "a/project")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try sh("git init -q", in: d)
        let moved = base.appending(path: "b").path
        _ = await sandboxed("mv \(base.path)/a \(moved)", in: d)
        #expect(!exists(moved), "the project's parent was renamed")
    }

    @Test func r8_w3e_aHardLinkDoesntReachAGuardedFile() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let link = "/private/tmp/kk-r8-\(UUID().uuidString.prefix(8))"; defer { try? FileManager.default.removeItem(atPath: link) }
        _ = await sandboxed("ln .git/config \(link); echo '[core]' >> \(link)", in: r.root)
        #expect(try !String(contentsOf: r.root.appending(path: ".git/config"), encoding: .utf8).hasSuffix("[core]\n"))
    }

    @Test func r8_w3f_aPreparedFolderCantBecomeDotGit() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let d = base.appending(path: "plain")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let away = "/private/tmp/kk-r8-\(UUID().uuidString.prefix(8))"; defer { try? FileManager.default.removeItem(atPath: away) }
        _ = await sandboxed("mkdir -p \(away)/hooks && mv \(away) .git", in: d)
        #expect(!exists(d.appending(path: ".git/hooks").path))
    }

    @Test func r8_w2e_theMainCheckoutsCommandsLeaveWorktreesAlone() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        let w = try await r.addWorktree(name: "x")
        _ = await sandboxed("echo mine >> .worktrees/x/a.txt; rm -rf .worktrees", in: r.root)
        #expect(try String(contentsOf: URL(fileURLWithPath: w.path).appending(path: "a.txt"), encoding: .utf8) == "one\n")
    }

    /// What a session working in a worktree does with git, each step in the sandbox. Not `git gc`: it locks every
    /// checkout's HEAD, which are out of reach. A commit's automatic one only leaves that to a later run.
    @Test func r8_worktreeCommandsStillWork() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let r = try repo(in: base)
        try sh("git switch -q -c other && echo other > o.txt && git add . && git commit -qm other && git switch -q main", in: r.root)
        let w = try await r.addWorktree(name: "x")
        let dir = URL(fileURLWithPath: w.path)
        for step in ["echo x > c.txt && git add . && git commit -qm one", "git switch -q -c feature && git switch -q kk/x",
                     "echo y >> c.txt && git stash push -q && git stash pop -q && git checkout -q -- c.txt",
                     "git merge -q --no-edit other", "git rebase -q other", "git tag v1 && git tag -d v1",
                     "git branch -D feature", "git pack-refs --all",
                     "git commit -q --allow-empty -m two && git reset -q --hard HEAD~1", "git status --porcelain"] {
            let out = await sandboxed(step, in: dir)
            #expect(out.exitCode == 0, "\(step): \(out.text)")
        }
    }
}
