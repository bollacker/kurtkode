import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// Round 7 (FUNCTIONAL_TESTS.md §21): probes for what three code reviews of Phase 3 found. Each failed before its fix.

private func dir(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "kk-r7-\(name)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@discardableResult
private func run(_ command: String, in d: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.currentDirectoryURL = d
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

private func put(_ data: Data, _ rel: String, in d: URL) throws {
    let url = d.appending(path: rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private func repo() throws -> URL {
    let p = try dir("proj")
    try put(Data("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\n".utf8), "a.txt", in: p)
    try run("git init -q && git add -A && git commit -qm init", in: p)
    return p
}

@Suite struct R7SnapshotTests {
    /// R7-1 (A): the project's attributes ran on the way in only, so a restore wrote LF over CRLF (or an LFS pointer over
    /// the real file).
    @Test func r7_1_aRestoreIsByteForByte() async throws {
        let p = try repo()
        try put(Data("* text=auto\n".utf8), ".gitattributes", in: p)
        try put(Data("x\r\ny\r\n".utf8), "crlf.txt", in: p)
        try run("git add -A && git commit -qm attrs", in: p)
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        try put(Data("changed\n".utf8), "crlf.txt", in: p)
        try await snaps.restore(["crlf.txt"], to: s.commit)
        #expect(try Data(contentsOf: p.appending(path: "crlf.txt")) == Data("x\r\ny\r\n".utf8))
        #expect(try await snaps.unchanged("crlf.txt", since: s.commit))
    }

    /// R7-2 (A): a folder left out at a run's start and captured at its end looked "added", and a rewind deleted it.
    @Test func r7_2_whatWasLeftOutStaysOutForTheSession() async throws {
        let p = try repo()
        for i in 0..<8 { try put(Data("d\(i)".utf8), "data/f\(i).csv", in: p) }
        var snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        snaps.limits.untrackedFolderFiles = 5
        let session = UUID()
        let start = try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        #expect(start.skipped.contains { $0.hasPrefix("data/") })
        for i in 0..<4 { try FileManager.default.removeItem(at: p.appending(path: "data/f\(i).csv")) }   // now under the limit
        let end = try await snaps.take(session: session, turn: nil, run: nil, phase: .end)
        #expect(try await snaps.changes(session: session, from: start.commit, to: end.commit).isEmpty)
        #expect(end.skipped.contains { $0.hasPrefix("data/") })
    }

    /// R7-3 (A): a case-only rename's revert wrote the old name, then deleted the new one: the same file on this disk.
    @Test func r7_3_aCaseOnlyRenameRevertsWithoutLosingTheFile() async throws {
        let p = try repo()
        try put(Data("let x = 1\n".utf8), "Utils.swift", in: p)
        try run("git add -A && git commit -qm u", in: p)
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        try run("git mv Utils.swift utils.swift", in: p)
        try await snaps.restore(["Utils.swift", "utils.swift"], to: s.commit)
        let names = try FileManager.default.contentsOfDirectory(atPath: p.path)
        #expect(names.contains("Utils.swift"))
        #expect(try String(contentsOf: p.appending(path: "Utils.swift"), encoding: .utf8) == "let x = 1\n")
    }

    /// R7-7 (A/B): "Revert This Part" took the hunk at the index shown; a new edit above it shifted the index, and another
    /// hunk (possibly the user's own) was reverted.
    @Test func r7_7_aHunkIsRevertedByItsContent() async throws {
        let p = try repo()
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let session = UUID()
        let s = try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        try run("sed -i '' 's/^eleven$/ELEVEN/' a.txt", in: p)
        let c = try #require(try await snaps.changes(session: session, from: s.commit, to: nil).first)
        let shown = UnifiedDiff.split(try await snaps.patch(session: session, from: s.commit, to: nil, change: c)).hunks[0]
        try run("sed -i '' 's/^one$/ONE (the user)/' a.txt", in: p)      // a new hunk above, after the view was drawn
        try await snaps.revertHunk(session: session, from: s.commit, change: c, hunk: shown)
        let text = try String(contentsOf: p.appending(path: "a.txt"), encoding: .utf8)
        #expect(text.contains("ONE (the user)") && text.contains("eleven\n") && !text.contains("ELEVEN"))
    }

    /// R7-8 (B): a restore wrote through a link the run put where a folder was, outside the project.
    @Test func r7_8_noRestoreThroughALinkOutOfTheProject() async throws {
        let p = try repo()
        try put(Data("doc\n".utf8), "docs/a.md", in: p)
        try run("git add -A && git commit -qm docs", in: p)
        let outside = try dir("outside")
        try put(Data("theirs\n".utf8), "a.md", in: outside)
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let s = try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        try FileManager.default.removeItem(at: p.appending(path: "docs"))
        try FileManager.default.createSymbolicLink(at: p.appending(path: "docs"), withDestinationURL: outside)
        await #expect(throws: ProjectSnapshots.Failure.self) { try await snaps.restore(["docs/a.md"], to: s.commit) }
        #expect(try String(contentsOf: outside.appending(path: "a.md"), encoding: .utf8) == "theirs\n")
    }

    /// R7-9 (B): a file that became a folder made every later snapshot of the session fail.
    @Test func r7_9_aFileCanBecomeAFolder() async throws {
        let p = try repo()
        try put(Data("c".utf8), "config", in: p)
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let session = UUID()
        try await snaps.take(session: session, turn: nil, run: nil, phase: .start)
        try FileManager.default.removeItem(at: p.appending(path: "config"))
        try put(Data("a".utf8), "config/a", in: p)
        let end = try await snaps.take(session: session, turn: nil, run: nil, phase: .end)
        #expect(try await snaps.shadow(["ls-tree", "-r", "--name-only", end.tree]).contains("config/a"))
    }

    /// R7-10 (B): the user's global git config reached the shadow repository (diff.noprefix broke `apply -R`).
    @Test func r7_10_noGlobalConfig() async throws {
        let p = try repo()
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        try await snaps.take(session: UUID(), turn: nil, run: nil, phase: .start)
        #expect(try await snaps.shadow(["config", "--global", "--list"], okStatuses: [0, 1]).trimmed.isEmpty)
    }

    /// R7-13 (C), R7-14: one folder reached by two paths shares a repository; big standard folders get none.
    @Test func r7_13_oneRepositoryPerFolderAndNoneForTheHomeFolders() throws {
        let p = try repo()
        let link = try dir("link").appending(path: "p")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: p)
        let root = try dir("snaps")
        #expect(ProjectSnapshots(project: link, root: root).gitDir == ProjectSnapshots(project: p, root: root).gitDir)
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!ProjectSnapshots.allowed(home.appending(path: "Documents")) && !ProjectSnapshots.allowed(URL(fileURLWithPath: "/Users")))
    }

    /// R7-6 (A/B): a rewind from snapshots dropped the edit-tool checkpoints of files the snapshots don't cover (an
    /// extra folder, an ignored file), so they weren't restored any more.
    @Test func r7_6_filesOnlyTheCheckpointsHaveAreStillRestored() async throws {
        let p = try repo()
        try put(Data("secret.cfg\n".utf8), ".gitignore", in: p)
        try put(Data("old\n".utf8), "secret.cfg", in: p)
        try run("git add .gitignore && git commit -qm ig", in: p)
        let snaps = ProjectSnapshots(project: p, root: try dir("snaps"))
        let checkpoints = CheckpointStore(directory: try dir("cp"))
        let session = UUID(), ask = ChatMessage.user("Change the config")
        var r = AgentRunRecord.test(agent: "main")
        r.userMessage = ask.id
        let s = try await snaps.take(session: session, turn: ask.id, run: r.id, phase: .start)
        try await checkpoints.snapshot(p.appending(path: "secret.cfg"), turn: ask.id)     // the edit tool's undo
        try put(Data("new\n".utf8), "secret.cfg", in: p)
        let e = try await snaps.take(session: session, turn: ask.id, run: r.id, phase: .end)
        r.snapshots = RunSnapshotRefs(start: s.commit, end: e.commit, skipped: [], changed: false)
        let plan = await RewindPlan.make(target: ask.id, messages: [ask], runs: [r], snapshots: snaps, session: session, checkpoints: checkpoints)
        #expect(plan.coversCommands && plan.checkpointFiles.map { ($0 as NSString).lastPathComponent } == ["secret.cfg"])
        _ = try await plan.restoreFiles(snapshots: snaps, checkpoints: checkpoints)
        #expect(try String(contentsOf: p.appending(path: "secret.cfg"), encoding: .utf8) == "old\n")
    }
}

@Suite struct R7ReviewAndEscalationTests {
    /// R7-4 (A): review and hand-over diffs went to remote models with files Settings withholds from them.
    @Test func r7_4_withheldFilesStayOutOfDiffsForRemoteModels() {
        let patch = """
            diff --git a/.env b/.env
            new file mode 100644
            --- /dev/null
            +++ b/.env
            @@ -0,0 +1 @@
            +API_KEY=sk-123
            diff --git a/app.py b/app.py
            --- a/app.py
            +++ b/app.py
            @@ -1 +1 @@
            -x = 1
            +x = 2
            diff --git a/keys/id.pem b/keys/id.pem
            +-----BEGIN PRIVATE KEY-----
            """
        let (kept, dropped) = UnifiedDiff.withholding(patch, patterns: WithheldFiles.defaults)
        #expect(!kept.contains("sk-123") && !kept.contains("PRIVATE KEY") && kept.contains("+x = 2"))
        #expect(dropped == [".env", "keys/id.pem"])
        var input = ReviewInput(request: "r", report: nil, checks: [], diff: patch, run: nil)
        input.withholding(WithheldFiles.defaults)
        #expect(input.prompt.contains("2 files withheld from remote models left out of the diff") && !input.prompt.contains("sk-123"))
    }

    /// R7-15 (A): a local session's reviewer could be any server kurtkode doesn't recognize (Azure, a cloud VM).
    @Test func r7_15_aLocalSessionKeepsToSurelyLocalReviewers() {
        let azure = Endpoint(name: "Azure", kind: .openai, baseURL: URL(string: "https://acme.openai.azure.com/openai/v1")!)
        let pool = ModelPool(entries: [PoolEntry(endpoint: azure.id.uuidString, model: "gpt-5.6-mini", tier: .cheap, roles: [.reviewer])])
        #expect(ReviewRouting.reviewer(for: "google/gemma-4-26b", endpoint: .localLMStudio, pool: pool, endpoints: [azure]) == nil)
        // And such a server is an unknown tier for escalation, not "local" (R7-17): no offer goes down or sideways.
        #expect(Escalation.tier(endpoint: azure, model: "gpt-5.6", pool: .shipped, endpoints: [azure]) == nil)
    }

    /// R7-18 (B): the reviewer was picked against the session's current model, so a change could be reviewed by its
    /// own vendor after a switch.
    @Test func r7_18_theReviewersVendorIsNotTheChangesMaker() {
        var or = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        or.usesAPIKey = true
        let pick = ReviewRouting.reviewer(excluding: ["deepseek", "anthropic"], session: or, pool: .shipped, endpoints: [or])
        #expect(pick == nil)            // the shipped reviewers are deepseek and Anthropic's
        #expect(ReviewRouting.reviewer(excluding: ["deepseek"], session: or, pool: .shipped, endpoints: [or])?.model == "anthropic/claude-haiku-5.5")
    }

    /// R7-26 (C): the reviewer's judgment said it read the files (it saw a diff); a session-wide verdict landed on the
    /// latest run.
    @Test func r7_26_aReviewSaysWhatItSawAndASessionsVerdictIsNoRunsLabel() {
        let r = CodeReview(verdict: .wrong, findings: [], summary: nil, reviewer: "x")
        #expect(r.judgment(run: UUID()).checked == RunJudgment.Checked.spotChecked.rawValue)
    }

    /// R7-31 (B): the new built-ins hid a user's own `/review` (a common Claude Code command); they yield now.
    @Test func r7_31_aUsersOwnReviewCommandStillWorks() throws {
        let root = try dir("cmds")
        try put(Data("Review $ARGUMENTS for bugs.\n".utf8), ".claude/commands/review.md", in: root)
        try put(Data("Can't replace a built-in.\n".utf8), ".claude/commands/help.md", in: root)
        let all = SlashCommands.all(workspace: root, home: try dir("home"))
        #expect(all.first { $0.name == "review" }?.isBuiltIn == false)
        #expect(all.first { $0.name == "help" }?.isBuiltIn == true)
        #expect(all.first { $0.name == "diff" }?.isBuiltIn == true)
    }

    /// R7-33 (B): a written task call into Claude with thinking on breaks its next request; OpenRouter's Claude with a
    /// reasoning level can't take a forced choice either.
    @Test func r7_33_noForcedOrWrittenCallForThinkingClaude() {
        let anthropic = ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, api: .anthropic)
        #expect(!ToolForcing.supported(client: anthropic, model: "claude-opus-5-5", effort: nil))
        #expect(!ToolForcing.canWrite(client: anthropic, model: "claude-opus-5-5", effort: nil))
        let or = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        #expect(!ToolForcing.supported(client: or, model: "anthropic/claude-haiku-5.5", effort: "high"))
        #expect(!ToolForcing.canWrite(client: or, model: "anthropic/claude-haiku-5.5", effort: "high"))
        #expect(ToolForcing.supported(client: or, model: "anthropic/claude-haiku-5.5", effort: nil))
        let local = ChatClient(baseURL: URL(string: "http://127.0.0.1:1234/v1")!)
        #expect(!ToolForcing.supported(client: local, model: "g", effort: nil) && ToolForcing.canWrite(client: local, model: "g", effort: nil))
    }
}

@Suite struct R7CLITests {
    private func settings(_ support: URL) throws -> (AppSettings, Endpoint) {
        let local = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://127.0.0.1:59999/v1")!)
        var or = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        or.usesAPIKey = true
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([local, or])
        let defaults = try #require(UserDefaults(suiteName: "kk-r7-\(UUID().uuidString.prefix(8))"))
        defaults.set(local.id.uuidString, forKey: "defaultEndpointID")
        defaults.set("test-model", forKey: "defaultModel")
        defaults.set(SkillRouting.off.rawValue, forKey: RunSettings.Key.skillRouting)
        return (AppSettings(support: support, defaults: defaults, environment: ["KURTKODE_NO_KEYCHAIN": "1"]), or)
    }

    /// R7-16 (A), R7-20 (B), R7-21 (B), R7-27 (C): accepting carries the pool entry's provider pins; the hand-over
    /// carries the offer's run's own request; a run gets one offer from its signals; `/review -m` with a name the CLI
    /// doesn't know refuses instead of using the default endpoint.
    @Test func r7_16_theOffersRunAndPinsGoAlong() async throws {
        let support = try dir("support")
        let (settings, or) = try settings(support)
        let p = try repo()
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
        #expect(try await session.send("First request") == .stepLimit)
        let offer = try #require(await session.escalationOffer())
        #expect(await session.escalationOffer() == nil)                         // R7-21: once a run
        #expect(offer.toProviders?.dataCollection == "deny")
        let handOver = try #require(await session.decide(offer, accept: true))
        #expect(handOver.contains("on the request \"First request\""))
        #expect(session.endpoint.id == or.id && session.profile.providers?.dataCollection == "deny")   // R7-16
        let (text, review) = await session.review("-m nosuch:model")
        #expect(review == nil && text.hasPrefix("No endpoint named nosuch"))     // R7-27
    }

    /// Decision 4: the offer's review goes to the offer's model, is kept as reviewed, and escalating stays possible.
    @Test func theOffersReviewRunsOnTheOffersModel() async throws {
        let support = try dir("support")
        let (settings, _) = try settings(support)
        let p = try repo()
        let review = #"{"verdict":"wrong","findings":[{"severity":"high","problem":"a.txt gets two lines, not one"}]}"#
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"echo one >> a.txt"}"#),
            SSE.toolCall("c2", "bash", #"{"command":"echo two >> a.txt"}"#),
            SSE.toolCall("r1", "submit_review", review),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        options.mode = .fullAuto
        options.maxSteps = 2
        let session = try await CLISession(settings: settings, workspace: p, options: options) { _, _ in client }
        #expect(try await session.send("Add one line to a.txt") == .stepLimit)
        let offer = try #require(await session.escalationOffer())
        #expect(offer.canReview)
        let (text, r) = await session.reviewForEscalation(offer)
        #expect(r?.verdict == .wrong && r?.findings.count == 1, "\(text)")
        let body = String(decoding: try #require(MockServer.requestBodies(host).last), as: UTF8.self)
        #expect(body.contains("submit_review") && body.contains(#""model":"\#(offer.toModel)""#))
        #expect(body.contains("data_collection"))                                // the pool entry's pins go along
        #expect(session.session.escalations.last?.decision == .reviewed)
        #expect(session.session.judgments.contains { $0.run == offer.run })
        #expect(try #require(await session.decide(offer, accept: true)).contains("on the request \"Add one line to a.txt\""))
        #expect(session.session.escalations.last?.decision == .accepted)
    }

    /// COST_AUDIT.md §10, point 4: Settings' automatic review offers escalation only when it finds the change wrong;
    /// "has problems" is kept as findings for the session's model to fix.
    @Test(arguments: [("has_problems", false), ("wrong", true)])
    func onlyAWrongReviewEarnsAnOffer(verdict: String, offers: Bool) async throws {
        let support = try dir("support")
        let (settings, or) = try settings(support)
        settings.defaults.set(true, forKey: RunSettings.Key.escalationReview)
        let p = try repo()
        let review = #"{"verdict":"\#(verdict)","findings":[{"severity":"medium","problem":"no test for the new line"}]}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"echo one >> a.txt"}"#),
            SSE.content("Added the line."),
            SSE.toolCall("r1", "submit_review", review),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        options.mode = .fullAuto
        options.model = or.name + ":anthropic/claude-haiku-5.5"     // a hosted model below the frontier
        let session = try await CLISession(settings: settings, workspace: p, options: options) { _, _ in client }
        #expect(try await session.send("Add one line to a.txt") == .completed)
        let offer = await session.escalationOffer()
        #expect((offer != nil) == offers)
        #expect(offer.map { $0.source == "review" && $0.reasonText.contains("found it wrong") } ?? true)
        #expect((session.reviewToFix != nil) == !offers)
        #expect(session.reviewToFix.map { $0.fixRequest.contains("no test for the new line") } ?? true)
    }
}

@Suite struct R7DelegationTests {
    /// R7-34 (B): a message the user queued while the sixth read ran was followed by a task call kurtkode wrote from the
    /// old request; the queued message decides now.
    @Test func r7_34_queuedInputComesBeforeAWrittenCall() async throws {
        let ws = try dir("ws")
        let reads = try (1...6).map { i -> [Data] in
            try put(Data(String(repeating: "Line \(i) of the notes about the system.\n", count: 18).utf8), "notes/n\(i).md", in: ws)
            return SSE.toolCall("r\(i)", "read_file", #"{"path":"notes/n\#(i).md"}"#)
        }
        let (client, host) = MockServer.client(.init(turns: reads + [SSE.content("Fixing Foo instead.")]))
        final class Queue: @unchecked Sendable { let lock = NSLock(); var calls = 0 }
        let q = Queue()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws), context: ContextBudget(limit: 4000, outputReserve: 100))
        config.subagents = SubagentSetup()
        // The seventh time the loop looks for queued input, the user's message is there.
        config.takeInput = { q.lock.withLock { q.calls += 1; return q.calls == 7 ? [ChatMessage.user("stop reading, just fix Foo")] : [] } }
        final class Box: @unchecked Sendable { var results: [ChatMessage] = [] }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is X?")], config: config,
                            workspace: Workspace(root: ws)) { if case .toolFinished(let m) = $0 { box.results.append(m) } }
        #expect(!box.results.contains { $0.toolCallID?.hasPrefix("kk_delegate_") == true })
        #expect(MockServer.requestBodies(host).count == 7)
    }
}
