import Foundation
import Testing
@testable import AgentCore

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    var approvals = 0
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    func approved() { lock.withLock { approvals += 1 } }
    var events: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var notices: [String] { events.compactMap { if case .hookNotice(let s) = $0 { s } else { nil } } }
    var injected: [ChatMessage] { events.compactMap { if case .injected(let m) = $0 { m } else { nil } } }
}

/// Hooks from inline shell commands, for one event.
private func hooks(_ event: HookEvent, matcher: String? = nil, _ commands: String..., cwd: URL) -> Hooks {
    Hooks(matchers: [event: [HookMatcher(matcher: matcher, hooks: commands.map { HookCommand(type: "command", command: $0, timeout: 10) })]],
          sessionID: "test-session", cwd: cwd)
}

private func run(_ turns: [[Data]], hooks: Hooks, mode: PermissionMode, ws: Workspace) async -> Log {
    let (client, _) = MockServer.client(.init(turns: turns))
    let log = Log()
    var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: mode),
                             approve: { _ in log.approved(); return .allow })
    config.hooks = hooks
    config.sandbox = nil
    await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { log.add($0) }
    return log
}

@Suite struct HookTests {
    @Test func preToolUseExit2BlocksWithTheReason() async throws {
        let ws = try makeProject()
        let log = await run([
            SSE.toolCall("call_1", "bash", #"{"command":"touch ran.txt"}"#),
            SSE.content("Blocked, so I stopped."),
        ], hooks: hooks(.preToolUse, matcher: "Bash", "echo 'no shell commands in this project' >&2; exit 2", cwd: ws.root),
           mode: .fullAuto, ws: ws)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "ran.txt").path))
        #expect(log.results.first?.content == "A hook blocked this bash call: no shell commands in this project")
        #expect(log.notices.contains { $0.contains("blocked bash") })
    }

    @Test func preToolUseCanAllowOrForceAnApproval() async throws {
        let ws = try makeProject()
        let allow = #"echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'"#
        let allowed = await run([
            SSE.toolCall("call_1", "bash", #"{"command":"touch ok.txt"}"#), SSE.content("Done."),
        ], hooks: hooks(.preToolUse, allow, cwd: ws.root), mode: .ask, ws: ws)
        #expect(allowed.approvals == 0)                                              // no card
        #expect(FileManager.default.fileExists(atPath: ws.root.appending(path: "ok.txt").path))

        let ask = #"echo '{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"check first"}}'"#
        let asked = await run([
            SSE.toolCall("call_1", "bash", #"{"command":"true"}"#), SSE.content("Done."),
        ], hooks: hooks(.preToolUse, ask, cwd: ws.root), mode: .fullAuto, ws: ws)
        #expect(asked.approvals == 1)                                               // asked even in Full Auto
    }

    @Test func postToolUseSeesTheCallAndSendsFeedback() async throws {
        let ws = try makeProject()
        let capture = ws.root.appending(path: "hook-input.json").path
        let log = await run([
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#), SSE.content("OK."),
        ], hooks: hooks(.postToolUse, matcher: "Read", "cat > '\(capture)'; echo 'remember to update the changelog' >&2; exit 2", cwd: ws.root),
           mode: .ask, ws: ws)
        #expect(log.results.first?.content.hasSuffix("[Hook feedback: remember to update the changelog]") == true)
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: capture)))
        guard case .object(let o) = input, case .object(let toolInput)? = o["tool_input"], case .object(let response)? = o["tool_response"] else {
            Issue.record("bad hook input"); return
        }
        #expect(o["hook_event_name"] == "PostToolUse" && o["tool_name"] == "read_file" && o["session_id"] == "test-session")
        #expect(toolInput["path"] == "README.md")
        #expect(response["output"]?.stringValue?.contains("# Demo") == true)
    }

    @Test func stopHookSendsTheAgentBackAtMostThreeTimes() async throws {
        let ws = try makeProject()
        // Blocks the first time, then lets it stop.
        let once = "if [ -f stopped-once ]; then exit 0; fi; touch stopped-once; echo 'the tests still fail' >&2; exit 2"
        let log = await run([SSE.content("Done?"), SSE.content("Fixed the tests; done.")],
                            hooks: hooks(.stop, once, cwd: ws.root), mode: .ask, ws: ws)
        #expect(log.injected.map(\.content) == ["A Stop hook says the task isn't done: the tests still fail"])
        let always = await run([SSE.content("Done?")], hooks: hooks(.stop, "echo nope >&2; exit 2", cwd: ws.root), mode: .ask, ws: ws)
        #expect(always.injected.count == 3)
        if case .finished(let s)? = always.events.last { #expect(s == .completed) } else { Issue.record("didn't finish") }
    }

    @Test func userPromptSubmitAddsContextOrBlocks() async throws {
        let ws = try makeProject()
        let context = await hooks(.userPromptSubmit, "echo 'Current branch: main'", cwd: ws.root).userPromptSubmit("hi")
        #expect(context.context == ["Current branch: main"] && !context.blocked)
        let block = await hooks(.userPromptSubmit, "grep -q secret && { echo 'no secrets in prompts' >&2; exit 2; }; exit 0", cwd: ws.root)
            .userPromptSubmit("my secret key")
        #expect(block.blocked && block.reason == "no secrets in prompts")
        let failing = await hooks(.userPromptSubmit, "exit 1", cwd: ws.root).userPromptSubmit("hi")
        #expect(!failing.blocked && failing.errors.count == 1)
    }

    @Test func loadsUserHooksAndHoldsProjectOnesForApproval() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-hooks-\(UUID().uuidString.prefix(8))")
        let home = root.appending(path: "home"), project = root.appending(path: "p")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ url: URL, _ c: HookConfig) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(c).write(to: url)
        }
        let cmd = { (s: String) in [HookMatcher(matcher: nil, hooks: [HookCommand(type: "command", command: s, timeout: nil)])] }
        try write(HookConfig.userFile(home: home), HookConfig(hooks: ["Stop": cmd("say done")]))
        let projectConfig = HookConfig(hooks: ["PreToolUse": cmd("./check.sh")])
        try write(HookConfig.projectFile(project), projectConfig)
        let approvals = HookApprovals(fileURL: root.appending(path: "approvals.json"))
        var (h, pending, problem) = Hooks.load(workspace: project, approvals: approvals, sessionID: "s", home: home)
        #expect(problem == nil && h.matchers[.stop]?.count == 1 && h.matchers[.preToolUse] == nil)
        #expect(pending?.commands == ["PreToolUse: ./check.sh"])
        try approvals.approve(projectConfig, workspace: project)
        (h, pending, _) = Hooks.load(workspace: project, approvals: approvals, sessionID: "s", home: home)
        #expect(pending == nil && h.matchers[.preToolUse]?.count == 1)
        #expect(HookMatcher(matcher: "Edit|Write", hooks: []).matches("edit_file"))       // Claude Code names work
        #expect(!HookMatcher(matcher: "Edit", hooks: []).matches("bash"))
        #expect(HookMatcher(matcher: "mcp__.*", hooks: []).matches("mcp__github__create_issue"))
    }
}
