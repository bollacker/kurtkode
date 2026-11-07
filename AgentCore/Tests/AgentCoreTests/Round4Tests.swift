import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// Round 4 of the functional tests, unit level (FUNCTIONAL_TESTS.md 18A): probes for what the round-4 code reviews
// and live runs suggested. A test that shows a bug stays here as `withKnownIssue` until the bug is fixed.

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var injected: [ChatMessage] { all.compactMap { if case .injected(let m) = $0 { m } else { nil } } }
    var finished: AgentStop? { all.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last }
}

private func scratch(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-r4-\(name)-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return Workspace.canonical(url)
}

private func rules(_ allow: [String] = [], ask: [String] = [], deny: [String] = [], root: URL) -> PermissionRules {
    PermissionRules(rules: PermissionsSection(allow: allow, ask: ask, deny: deny).rules(source: "test", includeAllow: true), root: root)
}

private func bashAction(_ r: PermissionRules, _ command: String) -> PermissionRule.Action? {
    r.decision(toolName: "bash", args: ToolArguments(["command": .string(command)]))?.action
}

private func hooks(_ event: HookEvent, matcher: String? = nil, _ command: String, timeout: Double = 10, cwd: URL) -> Hooks {
    Hooks(matchers: [event: [HookMatcher(matcher: matcher, hooks: [HookCommand(type: "command", command: command, timeout: timeout)])]],
          sessionID: "r4", cwd: cwd)
}

// MARK: 18A.1 Command splitting and the danger check (safety review S1–S7, S11)

@Suite struct R4ShellTests {
    let roots = ["/Users/k/proj"]

    @Test func crlfAndCombiningMarksSeparateCommands() {
        let r = rules(deny: ["Bash(rm:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        #expect(bashAction(r, "echo a\r\nrm x") == .deny)
        #expect(DangerousCommands.reason("echo a\r\nrm -rf ~", roots: roots) != nil)
        #expect(DangerousCommands.reason("echo '\u{301}x'; rm -rf ~; echo 'y'", roots: roots) != nil)
    }

    @Test func ansiCQuotingKeepsTheParserInStep() {
        #expect(DangerousCommands.reason(#"echo $'\'' ; rm -rf ~ ; echo 'y'"#, roots: roots) != nil)
    }

    @Test func aShiftIsNotAHeredoc() {
        #expect(DangerousCommands.reason("(( y = 1 << 2 ))\nrm -rf ~", roots: roots) != nil)
        #expect(DangerousCommands.reason("cat <<\"E O F\"\nhi\nE O F\nrm -rf ~", roots: roots) != nil)
    }

    @Test func nestingPastTheDepthLimitIsNotSafe() {
        #expect(DangerousCommands.reason("eval eval eval eval eval rm -rf ~", roots: roots) != nil)
        #expect(DangerousCommands.reason("sh -c \"sh -c 'sh -c \\\"sh -c \\\\\\\"sh -c \\\\\\\\\\\\\\\"rm -rf ~\\\\\\\\\\\\\\\"\\\\\\\"\\\"'\"", roots: roots) != nil)
    }

    @Test func zshPrecommandsAndNonLiteralCommandWords() {
        let r = rules(deny: ["Bash(rm:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        for c in ["noglob rm -rf ~", "nocorrect rm -rf ~", "=rm -rf ~", "/bin/r? -rf ~", "repeat 1 rm -rf ~", "$'rm' -rf ~"] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
        for c in ["noglob rm x", "=rm x", "repeat 2 rm x"] {
            #expect(bashAction(r, c) == .deny, "\(c)")
        }
        for c in ["/bin/r? x", "$cmd x", "$(printf rm) x"] {                       // can't be read: asked, not allowed
            #expect(bashAction(r, c) == .ask, "\(c)")
        }
        let allowAll = rules(["Bash(echo:*)"], root: URL(fileURLWithPath: "/Users/k/proj"))
        #expect(bashAction(allowAll, "echo hi") == .allow)
        #expect(bashAction(allowAll, "echo hi | sh") == nil)
    }

    @Test func shellsWithOptionValuesAndEnvSplitString() {
        for c in ["bash -o pipefail -c 'rm -rf ~'", "zsh -o errexit -c 'git reset --hard'", "env -S 'rm -rf ~'"] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
    }

    @Test func commandsCarriedInsideArguments() {
        for c in ["git -c alias.x='!git reset --hard' x", "find . -exec /bin/rm -rf ~ \\;", "find /tmp/x -execdir rm -rf {} +",
                  "bash <<< 'rm -rf ~'", "echo 'rm -rf ~' | sh"] {
            #expect(DangerousCommands.reason(c, roots: roots) != nil, "\(c)")
        }
    }

    @Test(.timeLimit(.minutes(1))) func aLongWordIsParsedInLinearTime() {
        // Four times the text should take about four times as long (it took sixteen: quadratic), whatever the build.
        let r = rules(deny: (0..<10).map { "Bash(tool\($0):*)" }, root: URL(fileURLWithPath: "/Users/k/proj"))
        func time(_ n: Int) -> Duration {
            let line = "echo " + String(repeating: "a", count: n)
            let start = ContinuousClock.now
            _ = bashAction(r, line)
            _ = DangerousCommands.reason(line, roots: roots)
            return ContinuousClock.now - start
        }
        _ = time(10_000)
        let small = time(50_000), large = time(200_000)
        #expect(large < small * 8, "50 KB: \(small), 200 KB: \(large)")
    }
}

// MARK: 18A.2 Hooks (loop review L3, L4)

@Suite struct R4HookTests {
    private func run(_ hooks: Hooks, command: String, ws: Workspace) async -> Events {
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("b1", "bash", #"{"command":"\#(command)"}"#), SSE.content("Done.")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow })
        config.hooks = hooks
        config.sandbox = nil
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { events.add($0) }
        return events
    }

    @Test func aBlockDecisionStopsTheCall() async throws {
        let ws = try makeProject()
        _ = await run(hooks(.preToolUse, #"echo '{"decision":"block","reason":"no writes here"}'"#, cwd: ws.root), command: "touch ran.txt", ws: ws)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "ran.txt").path))
    }

    @Test func continueFalseStopsTheCall() async throws {
        let ws = try makeProject()
        _ = await run(hooks(.preToolUse, #"echo '{"continue":false,"stopReason":"halt"}'"#, cwd: ws.root), command: "touch ran2.txt", ws: ws)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "ran2.txt").path))
    }

    @Test(.timeLimit(.minutes(1))) func aHookTimeoutBoundsAPipeline() async throws {
        let ws = try makeProject()
        let start = ContinuousClock.now
        _ = await run(hooks(.preToolUse, "sleep 20 | cat", timeout: 1, cwd: ws.root), command: "true", ws: ws)
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}

// MARK: 18A.3 The loop's state (loop review L1, L6, L8)

@Suite struct R4LoopTests {
    @Test func aSubagentsEditClearsTheParentsReadCache() async throws {
        let ws = try makeProject()
        let task = #"{"description":"Change the readme","prompt":"Replace README.md with the word changed.","agent":"general"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#),                     // main
            SSE.toolCall("t1", "task", task),                                              // main
            SSE.toolCall("s1", "bash", #"{"command":"echo changed > README.md"}"#),        // subagent
            SSE.content("Done."),                                                          // subagent
            SSE.toolCall("r2", "read_file", #"{"path":"README.md"}"#),                     // main
            SSE.content("It says changed."),                                               // main
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow })
        config.subagents = SubagentSetup()
        config.sandbox = nil
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        let second = try #require(events.results.last { $0.toolCallID == "r2" })
        #expect(second.content.contains("changed"))
        #expect(!second.content.contains("You already called"))
    }

    @Test func aDeniedSubagentIsAnErrorForTheParent() async throws {
        let ws = try makeProject()
        let task = #"{"description":"Touch a file","prompt":"Run touch x.","agent":"general"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("t1", "task", task),
            SSE.toolCall("s1", "bash", #"{"command":"touch x"}"#),
            SSE.content("ok"),
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .ask), approve: { _ in .deny(feedback: nil) })
        config.subagents = SubagentSetup()
        config.sandbox = nil
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        let result = try #require(events.results.first { $0.toolCallID == "t1" })
        #expect(result.toolResult?.isError == true || events.finished == AgentStop.denied)
    }

    @Test(.timeLimit(.minutes(1))) func queuedInputIsNotTakenAfterStop() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("b1", "bash", #"{"command":"sleep 2"}"#), SSE.content("Done.")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow })
        config.sandbox = nil
        // Typed only after Stop (at 0.7 s): offered from 1 s on, while the stopped run is still finishing its command.
        final class Once: @unchecked Sendable { var given = false; let lock = NSLock(); let start = Date() }
        let once = Once()
        config.takeInput = {
            once.lock.withLock {
                if once.given || Date().timeIntervalSince(once.start) < 1 { return [] }
                once.given = true
                return [.user("one more thing")]
            }
        }
        let events = Events()
        let run = Task {
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        }
        try await Task.sleep(for: .milliseconds(700))
        run.cancel()
        await run.value
        #expect(events.injected.isEmpty)
    }
}

// MARK: 18A.4 Persistence (cost review C2, C4; live E4)

@Suite struct R4StoreTests {
    @Test func twoStoresAppendingAtOnceLoseNothing() async throws {
        let root = scratch("store")
        let a = SessionStore(root: root), b = SessionStore(root: root)
        let header = SessionHeader(endpointID: UUID(), model: "m")
        try await a.create(header)
        _ = try await b.load(header.id)
        await withTaskGroup(of: Void.self) { group in
            for (name, store) in [("a", a), ("b", b)] {
                group.addTask {
                    for i in 0..<200 { try? await store.append(.message(.user("\(name)\(i)")), to: header.id) }
                }
            }
        }
        let s = try #require(try await SessionStore(root: root).load(header.id))
        #expect(s.messages.count == 400)
    }

    @Test func aForkDoesNotDoubleSubagentCostsOrRuns() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: scratch("fork"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let task = #"{"description":"Find greet","prompt":"Where is greet() defined?","agent":"explore"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", task), SSE.content("At src/main.swift:12."), SSE.content("It's at src/main.swift:12."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let user = ChatMessage.user("Where is greet?")
        config.costScope = CostScope(run: UUID(), agent: "main", userMessage: user.id)
        try await store.append(.message(user), to: parent.id)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [user], config: config, workspace: ws) { e in
            events.add(e)
        }
        for e in events.all {
            switch e {
            case .assistant(let m), .toolFinished(let m): try await store.append(.message(m), to: parent.id)
            default: break
            }
        }
        let runsBefore = try await store.runRecords().count
        let costsBefore = try await store.costEntries().count
        let session = try #require(try await store.load(parent.id))
        let reply = try #require(session.messages.last { $0.role == .assistant })
        let fork = try await store.fork(session, atReply: reply.id, after: true, title: "fork")
        #expect(try await store.subagentRuns(of: fork.header).count == 1)          // the fork has the run (as designed)
        let runsAfter = try await store.runRecords().count, costsAfter = try await store.costEntries().count
        #expect(runsAfter == runsBefore)
        #expect(costsAfter == costsBefore)
    }
}

// MARK: 18A.5 Costs (cost review C8, C11)

@Suite struct R4CostTests {
    @Test func placeholderPricesAreNotPrices() throws {
        let data = Data(#"{"data":[{"id":"openrouter/auto","pricing":{"prompt":"-1","completion":"-1"}}]}"#.utf8)
        #expect(RemotePrices.parse(data)["openrouter/auto"] == nil)
    }

    @Test func anOlderRunTotalsRecordStillDecodes() throws {
        let old = #"{"requests":2,"listPrice":{"uncachedInput":0,"cacheRead":0,"cacheWrite5m":0,"cacheWrite1h":0,"output":0,"reasoning":0,"searches":0,"requests":0,"total":0},"unpricedRequests":2,"promptTokens":200,"cacheReadTokens":0,"cacheWriteTokens":0,"completionTokens":20,"reasoningTokens":0,"searches":0,"wallSeconds":1,"modelSeconds":1}"#
        let decoded = try JSONDecoder().decode(RunTotals.self, from: Data(old.utf8))
        #expect(decoded.requests == 2 && decoded.reconciledRequests == 0 && decoded.charged == nil)
        #expect(try JSONDecoder().decode(ComponentCosts.self, from: Data(#"{"total":1.5}"#.utf8)).total == 1.5)
    }
}

// MARK: 18A.6 The model layer (wire review W1, W2, W4, W5, W6)

@Suite struct R4WireTests {
    private func request() -> ChatRequest { ChatRequest(model: "m", messages: [.user("hi")], maxTokens: 100) }

    @Test func anErrorInsideTheStreamIsNotACompletedReply() async throws {
        let chunks = [
            SSE.line(#"{"id":"gen-1","model":"m","choices":[{"index":0,"delta":{"content":"Here is the fi"},"finish_reason":null}]}"#),
            SSE.line(#"{"id":"gen-1","model":"m","error":{"code":"server_error","message":"Provider disconnected"},"choices":[{"index":0,"delta":{"content":""},"finish_reason":"error"}]}"#),
            SSE.line("[DONE]"),
        ]
        let (client, _) = MockServer.client(.init(chunks: chunks))
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits()) { _ in }
        #expect(msg.meta?.stopReason != .completed)
    }

    @Test func aMalformedGeminiCallDoesNotEndTheRunAsCompleted() async throws {
        let ws = try makeProject()
        let malformed = [SSE.line(#"{"candidates":[{"content":{"parts":[{"text":"I'll update the file now."}],"role":"model"},"finishReason":"MALFORMED_FUNCTION_CALL","index":0}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15},"modelVersion":"gemini-3-flash-preview"}"#)]
        let ok = [SSE.line(#"{"candidates":[{"content":{"parts":[{"text":"Done."}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15},"modelVersion":"gemini-3-flash-preview"}"#)]
        let (client, host) = MockServer.client(.init(turns: [malformed, ok]), api: .gemini)
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow })
        config.sandbox = nil
        let events = Events()
        await AgentLoop.run(client: client, model: "gemini-3-flash-preview", systemPrompt: "S", history: [.user("edit it")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(MockServer.requestBodies(host).count == 2 || events.finished != .completed)
    }

    @Test(.timeLimit(.minutes(1))) func theWallClockLimitHoldsWhileOnlyPingsArrive() async throws {
        let (client, _) = MockServer.client(.init(chunks: [Data(": ping\n\n".utf8)], delay: 0.05, repeatForever: true))
        let start = ContinuousClock.now
        let msg = await TurnRunner.run(client: client, request: request(), limits: TurnLimits(wallClock: 0.5)) { _ in }
        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(msg.meta?.stopReason == .timedOut)
    }

    @Test func mergedUserMessagesKeepTheirImages() {
        var second = ChatMessage.user("look at this")
        second.images = [ImageAttachment(mediaType: "image/png", path: "/tmp/x.png", width: 10, height: 10)]
        let shaped = HistoryShaper.shape([.user("first"), second], for: HistoryShape(mergeConsecutive: true))
        #expect(shaped.flatMap { $0.images ?? [] }.count == 1)
    }

    @Test func aToolCallQuotedInACodeFenceIsNotRun() throws {
        let text = "The parser handles this form:\n```\n<tool_call>{\"name\":\"bash\",\"arguments\":{\"command\":\"rm -rf build\"}}</tool_call>\n```\nThat's all."
        #expect(TextToolCalls.extract(from: text, knownTools: ["bash"]) == nil)
        let span = "Calls look like `<tool_call>{\"name\":\"bash\",\"arguments\":{\"command\":\"rm -rf build\"}}</tool_call>` here."
        #expect(TextToolCalls.extract(from: span, knownTools: ["bash"]) == nil)
        // A real call after the example is still taken, and one whose content holds a fence too.
        let real = text + "\n<tool_call>{\"name\":\"bash\",\"arguments\":{\"command\":\"ls\"}}</tool_call>"
        let found = try #require(TextToolCalls.extract(from: real, knownTools: ["bash"]))
        #expect(found.calls.map(\.arguments) == [#"{"command":"ls"}"#])
        #expect(found.remaining.contains("<tool_call>{\"name\":\"bash\",\"arguments\":{\"command\":\"rm -rf build\"}}</tool_call>"))
        let xml = "<function=write_file>\n<parameter=path>\nREADME.md\n</parameter>\n<parameter=content>\n```sh\nmake\n```\n</parameter>\n</function>\n"
            + "<function=read_file>\n<parameter=path>\nREADME.md\n</parameter>\n</function>"
        #expect(TextToolCalls.extract(from: xml, knownTools: ["write_file", "read_file"])?.calls.map(\.name) == ["write_file", "read_file"])
    }
}

// MARK: 18A.7 Tools and commands (tools review T1, T3, T4, T5, T10)

@Suite struct R4ToolTests {
    private func call(_ tool: some Tool, _ args: [String: JSONValue], in ws: Workspace) async -> ToolOutput {
        let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(args)), as: UTF8.self)
        return await AgentLoop.execute(ToolCall(id: "t", name: tool.name, arguments: json), tools: [tool.name: tool],
                                       config: AgentConfig(tools: [tool], maxToolOutputBytes: 16_000), workspace: ws)
    }

    @Test func editingALatin1FileKeepsItsOtherBytes() async throws {
        let ws = try makeProject()
        let url = ws.root.appending(path: "latin.txt")
        try Data([0x63, 0x61, 0x66, 0xE9, 0x0A] + Array("x = 1\n".utf8)).write(to: url)
        let out = await call(EditFileTool(), ["path": "latin.txt", "old_string": "x = 1", "new_string": "x = 2"], in: ws)
        #expect(out.isError && out.text.contains("isn't UTF-8"))
        #expect(try Data(contentsOf: url) == Data([0x63, 0x61, 0x66, 0xE9, 0x0A] + Array("x = 1\n".utf8)))   // untouched
        let appended = await call(WriteFileTool(), ["path": "latin.txt", "content": "y = 3", "append": true], in: ws)
        #expect(appended.isError)
        #expect(try Data(contentsOf: url).count == 11)
    }

    @Test(.timeLimit(.minutes(2))) func anAmbiguousShortEditFailsFast() async throws {
        let ws = try makeProject()
        // 8,000 one-character lines (16 KB): the refusal should be instant; it scales with matches × file size.
        try Data(String(repeating: "x\n", count: 8_000).utf8).write(to: ws.root.appending(path: "big.txt"))
        let start = ContinuousClock.now
        let out = await call(EditFileTool(), ["path": "big.txt", "old_string": "x", "new_string": "y"], in: ws)
        #expect(out.isError)
        #expect(ContinuousClock.now - start < .milliseconds(300))
    }

    @Test func crlfFilesTakeMultiLineEdits() async throws {
        let ws = try makeProject()
        try Data("a\r\nb\r\nc\r\n".utf8).write(to: ws.root.appending(path: "crlf.txt"))
        let multi = await call(EditFileTool(), ["path": "crlf.txt", "old_string": "a\nb", "new_string": "A\nB"], in: ws)
        #expect(!multi.isError)
        let single = await call(EditFileTool(), ["path": "crlf.txt", "old_string": "c", "new_string": "C"], in: ws)
        #expect(single.text.contains("3\t"))
        #expect(try Data(contentsOf: ws.root.appending(path: "crlf.txt")) == Data("A\r\nB\r\nC\r\n".utf8))   // still CRLF
        #expect(EditFileTool.lineNumbers(of: "c", in: "a\r\nb\r\nc\r\n") == [3])
        let added = await call(EditFileTool(), ["path": "crlf.txt", "old_string": "C", "new_string": "C\nD"], in: ws)
        #expect(!added.isError)
        #expect(try Data(contentsOf: ws.root.appending(path: "crlf.txt")) == Data("A\r\nB\r\nC\r\nD\r\n".utf8))
    }

    @Test func positionalArgumentsAreNotSubstitutedInsideTheUsersText() {
        #expect(SlashCommands.expand("Fix: $ARGUMENTS", arguments: "price is $1 off") == "Fix: price is $1 off")
        #expect(SlashCommands.expand("Compare $1 with $2 ($ARGUMENTS) for $5", arguments: "a.swift b.swift") == "Compare a.swift with b.swift (a.swift b.swift) for ")
        #expect(SlashCommands.expand("Costs $ and $0", arguments: "x") == "Costs $ and $0\n\nx")
    }

    @Test(.timeLimit(.minutes(1))) func aCommandStartedAfterStopDoesNotRun() async throws {
        let ws = try makeProject()
        let start = ContinuousClock.now
        let t = Task { () -> ToolOutput in
            withUnsafeCurrentTask { $0?.cancel() }
            return await call(BashTool(), ["command": "sleep 2"], in: ws)
        }
        _ = await t.value
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}

// MARK: 18A.8 Debug views and undo (persistence review P2, P5)

@Suite struct R4DebugTests {
    @Test func repeatedCallIDsKeepEachTurnsOwnResult() async throws {
        let store = SessionStore(root: scratch("ids"))
        let h = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(h)
        try await store.append(.message(.user("go")), to: h.id)
        for text in ["first", "second"] {
            try await store.append(.message(ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "call_0", name: "bash", arguments: "{}")])), to: h.id)
            try await store.append(.message(ChatMessage(role: .tool, content: text, toolCallID: "call_0")), to: h.id)
        }
        let s = try #require(try await store.load(h.id))
        let turns = SessionTimeline.items(s).compactMap { if case .turn(let t) = $0 { t } else { nil } }
        #expect(turns.count >= 2)
        #expect(turns.first?.calls.first?.result?.content == "first")
        #expect(turns.last?.calls.first?.result?.content == "second")
        let journal = SessionJournal(session: s, contexts: [])
        #expect(Set(journal.entries.map(\.id)).count == journal.entries.count)          // unique ids
    }

    @Test func anotherProcesssUndoEntriesSurviveThisOnesNextSave() async throws {
        let dir = scratch("cp")
        let ws = scratch("cpws")
        let f1 = ws.appending(path: "one.txt"), f2 = ws.appending(path: "two.txt")
        try Data("1".utf8).write(to: f1); try Data("2".utf8).write(to: f2)
        let app = CheckpointStore(directory: dir), cli = CheckpointStore(directory: dir)
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        try await app.snapshot(f1, turn: t1)
        try await cli.snapshot(f2, turn: t2)
        try await app.snapshot(f1, turn: t3)
        let files = await CheckpointStore(directory: dir).changedFiles(inTurns: [t2])
        // A rewind in one process keeps what the other added meanwhile.
        try Data("2b".utf8).write(to: f2)
        let restored = try await app.restore(turns: [t2])
        #expect(restored.map(\.path) == [f2.standardizedFileURL.path])
        #expect(try String(contentsOf: f2, encoding: .utf8) == "2")
        #expect(await cli.changedFiles(inTurns: [t1, t3]) == [f1.standardizedFileURL.path])
        #expect(files == [f2.standardizedFileURL.path])
    }
}

// MARK: 18A.9 Git panel and cost check (tools review T9, cost review C6)

@Suite struct R4MoreTests {
    private func git(_ args: [String], in dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }

    @Test func discardingAnAddAddConflictKeepsTheCommittedFile() async throws {
        let dir = scratch("aa")
        try git(["init", "-q", "-b", "main"], in: dir)
        try Data("base\n".utf8).write(to: dir.appending(path: "base.txt"))
        try git(["add", "."], in: dir); try git(["commit", "-qm", "base"], in: dir)
        try git(["checkout", "-qb", "other"], in: dir)
        try Data("theirs\n".utf8).write(to: dir.appending(path: "both.txt"))
        try git(["add", "."], in: dir); try git(["commit", "-qm", "theirs"], in: dir)
        try git(["checkout", "-q", "main"], in: dir)
        try Data("ours\n".utf8).write(to: dir.appending(path: "both.txt"))
        try git(["add", "."], in: dir); try git(["commit", "-qm", "ours"], in: dir)
        try git(["merge", "-q", "other"], in: dir)                                    // conflicts (add/add)
        let repo = GitRepo(root: dir)
        let file = try #require(try await repo.status().files.first { $0.path == "both.txt" })
        #expect(file.isConflicted)
        try await repo.discard(file)
        let text = try? String(contentsOf: dir.appending(path: "both.txt"), encoding: .utf8)
        #expect(text == "ours\n")                                                      // "its last committed version"
    }

    @Test func discardTakesFileNamesLiterally() async throws {
        let dir = scratch("lit")
        try git(["init", "-q", "-b", "main"], in: dir)
        for name in ["a[1].txt", "a1.txt"] { try Data("v1\n".utf8).write(to: dir.appending(path: name)) }
        try git(["add", "."], in: dir); try git(["commit", "-qm", "base"], in: dir)
        for name in ["a[1].txt", "a1.txt"] { try Data("v2\n".utf8).write(to: dir.appending(path: name)) }
        let repo = GitRepo(root: dir)
        let file = try #require(try await repo.status().files.first { $0.path == "a[1].txt" })
        try await repo.discard(file)
        #expect(try String(contentsOf: dir.appending(path: "a[1].txt"), encoding: .utf8) == "v1\n")
        #expect(try String(contentsOf: dir.appending(path: "a1.txt"), encoding: .utf8) == "v2\n")     // untouched
    }

    @Test func aCostCheckDayIsTwentyFiveHoursAtTheEndOfDaylightTime() async throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-r4dst-\(UUID().uuidString.prefix(6))")
        var settings = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-r4dst-\(UUID().uuidString)")!, environment: [:])
        let claude = Endpoint(name: "Claude", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!)
        settings.endpoints.append(claude)
        let store = settings.sessionStore
        let h = SessionHeader(endpointID: claude.id, model: "claude-opus-5-5", workspace: nil)
        try await store.create(h)
        // 23:30 PST on 2026-11-01 (the day clocks go back in Los Angeles) is 07:30 UTC on 2026-11-02.
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "claude-opus-5-5", usage: Usage(promptTokens: 1000, completionTokens: 10), stopReason: .completed, duration: 1)
        let at = ISO8601DateFormatter().date(from: "2026-11-02T07:30:00Z")!
        let p = PriceList.price(api: .anthropic, model: "claude-opus-5-5").map { PriceLookup.known($0, source: "test", version: "t") } ?? .unknown("x")
        let e = CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: ChatClient(endpoint: claude), endpointID: claude.id, start: at, price: p)
        try await store.append(.cost(e), to: h.id)
        final class Out: @unchecked Sendable { let lock = NSLock(); var text = "" }
        let out = Out()
        _ = await DebugCommands.run(["cost", "check", "--day", "2026-11-01", "--tz", "America/Los_Angeles", "--json"], settings: settings,
                                    cwd: FileManager.default.temporaryDirectory) { s in out.lock.withLock { out.text += s } }
        #expect(out.text.contains("claude-opus-5-5"))
    }
}

// MARK: Round 4 B fixes

@Suite struct R4LimitTests {
    @Test func theMeterCountsListPriceFromTheCostRecord() {
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "pm/model", usage: Usage(promptTokens: 400_000, completionTokens: 100), stopReason: .completed, duration: 1)
        let price = PriceList.Price(standard: PriceList.Rates(input: 2, output: 10, cacheRead: 0.5, cacheWrite5m: 2, cacheWrite1h: 2),
                                    longAbove: nil, long: nil, perSearch: nil, perRequest: nil)
        let client = ChatClient(baseURL: URL(string: "https://example.com/v1")!)
        let e = CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: nil, start: Date(),
                               price: .known(price, source: "test", version: "t"))
        let meter = CostMeter(runLimit: 2, sessionLimit: nil, sessionBefore: 0)
        for _ in 0..<2 { meter.add(e) }
        #expect(meter.reached == nil)                                   // $1.60
        meter.add(e)
        #expect(meter.reached != nil)                                   // $2.40: the run's limit
    }
}

@Suite struct R4DateTests {
    @Test func priceDaysAreGregorianWhateverTheRegion() {
        let f = DayFormat.formatter()
        #expect(f.date(from: "2026-10-16").map { f.string(from: $0) } == "2026-10-16")
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        let d = DayFormat.formatter().date(from: "2026-11-30")!
        #expect(buddhist.component(.year, from: d) == 2569)                       // the region's year…
        #expect(DayFormat.formatter().string(from: d) == "2026-11-30")             // …isn't what the price list compares
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let start = DayFormat.formatter(zone: la).date(from: "2026-11-01")!
        let day = DayFormat.day(starting: start, zone: la)
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 25 * 3600)
    }
}

@Suite struct R4CostRecordTests {
    @Test func aReplaysCheckedCostStaysInItsReplayRecord() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-r4rep-\(UUID().uuidString.prefix(6))"))
        let h = SessionHeader(endpointID: UUID(), model: "vendor/model", workspace: nil)
        try await store.create(h)
        let endpointID = UUID()
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "vendor/model", usage: Usage(promptTokens: 100, completionTokens: 10), stopReason: .completed, duration: 1)
        m.meta?.requestIDs = ["gen-replay"]
        let or = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        let cost = CostEntry.make(reply: m, purpose: .replay, run: nil, agent: "replay", client: or, endpointID: endpointID,
                                  start: Date().addingTimeInterval(-600), price: .unknown("x"))
        let wire = WireRecord(replyID: m.id, startedAt: Date(), duration: 1, url: "https://openrouter.ai/api/v1", request: .object([:]),
                              statuses: [200], lines: [], linesTruncated: nil, errorBody: nil)
        let record = ReplayRecord(id: UUID(), sourceReply: UUID(), startedAt: Date(), endpointName: "Openrouter", endpointID: endpointID,
                                  options: ReplayOptions(model: "vendor/model"), reply: m, wire: wire, warnings: [], cost: cost)
        try Replay.save(record, wire: store.wireDirectory(for: h))
        var route = MockServer.Route()
        route.gets = ["generation": Data(#"{"data":{"id":"gen-replay","total_cost":0.0009,"native_tokens_prompt":100,"native_tokens_completion":10}}"#.utf8)]
        let (mock, _) = MockServer.client(route)
        let first = await CostReconciler.run(store: store, since: Date().addingTimeInterval(-86_400), minAge: 60, client: { _ in mock })
        #expect(first.checked == 1)
        #expect(try await store.load(h.id)?.costs.isEmpty == true)                     // nothing appended to the session
        let entries = try await store.costEntries()
        #expect(entries.count == 1 && entries.first?.entry.charged == 0.0009)            // the replay's record, checked
        let again = await CostReconciler.run(store: store, since: Date().addingTimeInterval(-86_400), minAge: 60, client: { _ in mock })
        #expect(again.pending == 0)
    }

    @Test func aRunsJSONCostIncludesItsSubagents() async throws {
        // A run record (from a real loop on a mock), given one priced subagent child.
        let (client, _) = MockServer.client(.init(turns: [SSE.content("ok")]))
        var config = AgentConfig(tools: [])
        let runID = UUID()
        config.costScope = CostScope(run: runID, agent: "main")
        final class Box: @unchecked Sendable { var r: AgentRunRecord? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: nil) { e in
            if case .runEnded(let r) = e { box.r = r }
        }
        var record = try #require(box.r)
        record.children = [ChildRun(run: UUID(), agent: "explore", stop: "completed", listPrice: 0.012, unpricedRequests: 0, requests: 2, spent: 0.010)]
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "pm/model", usage: Usage(promptTokens: 1000, completionTokens: 100), stopReason: .completed, duration: 1)
        let price = PriceList.Price(standard: PriceList.Rates(input: 2, output: 10, cacheRead: 2, cacheWrite5m: 2, cacheWrite1h: 2),
                                    longAbove: nil, long: nil, perSearch: nil, perRequest: nil)
        let own = CostEntry.make(reply: m, purpose: .reply, run: runID, agent: "main", client: ChatClient(baseURL: URL(string: "https://example.com/v1")!),
                                 endpointID: nil, start: Date(), price: .known(price, source: "t", version: "t"))
        final class Out: @unchecked Sendable { let lock = NSLock(); var text = "" }
        let out = Out()
        let r = Renderer(style: .print(.json), out: { s in out.lock.withLock { out.text += s } }, err: { _ in })
        r.handle(.cost(own))
        r.handle(.runEnded(record))
        r.handle(.finished(.completed))
        r.finish(session: UUID(), model: "pm/model")
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(out.text.utf8)) else { Issue.record("no JSON"); return }
        guard case .number(let cost)? = o["cost_usd"], case .number(let list)? = o["list_price_usd"] else { Issue.record("no cost"); return }
        #expect(abs(cost - (0.003 + 0.010)) < 1e-9)                       // the run's own $0.003 and its subagent's $0.010
        #expect(abs(list - (0.003 + 0.012)) < 1e-9)
        #expect(o["subagents_cost_usd"] == .number(0.010))
    }
}
