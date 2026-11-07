import Foundation
import Testing
@testable import AgentCore

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var assistants: [ChatMessage] { lock.withLock { items }.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
    var results: [ChatMessage] { lock.withLock { items }.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
}

private func run(_ route: MockServer.Route, config: (inout AgentConfig) -> Void = { _ in }) async throws -> (Collected, URL) {
    let (client, _) = MockServer.client(route)
    let wire = FileManager.default.temporaryDirectory.appending(path: "kk-wire-\(UUID().uuidString.prefix(8))")
    var c = AgentConfig(tools: ReadTools.all)
    c.wireLog = WireLog(directory: wire)
    config(&c)
    let events = Collected()
    await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [.user("What is this project?")],
                        config: c, workspace: try makeProject()) { events.add($0) }
    return (events, wire)
}

@Suite struct WireLogTests {
    @Test func everyTurnIsRecordedWithItsRequestAndRawStream() async throws {
        let (events, wire) = try await run(.init(turns: [
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("It is a demo project."),
        ]))
        #expect(events.assistants.count == 2)
        for reply in events.assistants {
            let r = try #require(WireLog.read(wire, replyID: reply.id))
            #expect(r.statuses == [200] && r.url.hasSuffix("/v1/chat/completions"))
            guard case .object(let o) = r.request else { Issue.record("no request"); return }
            #expect(o["model"] == "test-model" && o["tools"] != nil)
            #expect(r.lines.contains { $0.hasPrefix("data: ") } && r.lines.last == "data: [DONE]")
        }
        // The second request carries the first reply's call and its result.
        let second = try #require(WireLog.read(wire, replyID: events.assistants[1].id))
        #expect(second.messages.count == 4)
        let first = try #require(WireLog.read(wire, replyID: events.assistants[0].id))
        let diff = WireDiff(previous: first, current: second)
        #expect(diff.commonPrefix == 2 && !diff.systemChanged && !diff.toolsChanged)
        #expect(diff.summary.contains("adds 2 messages"))
    }

    @Test func retriedStatusesAndErrorBodiesAreKept() async throws {
        let (events, wire) = try await run(.init(turns: [[Data(#"{"error":"busy"}"#.utf8)], SSE.content("Fine.")],
                                                 turnStatuses: [0: 429]))
        let reply = try #require(events.assistants.first)
        let r = try #require(WireLog.read(wire, replyID: reply.id))
        #expect(r.statuses == [429, 200])
        #expect(r.errorBody?.contains("busy") == true)
    }

    @Test func imagesAreLeftOutOfTheRecordedRequest() {
        let body = Data(#"{"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,AAAA"}}]}]}"#.utf8)
        let v = WireRecord.compactRequest(body)
        let text = String(decoding: try! JSONEncoder().encode(v), as: UTF8.self)
        #expect(!text.contains("base64") && text.contains("[image, 0 KB as a data URL]"))
    }
}

@Suite struct TurnNotesTests {
    @Test func recoveredTextCallsKeepTheRawTextAndANote() async throws {
        let (events, _) = try await run(.init(turns: [
            SSE.content("<function=read_file><parameter=path>README.md</parameter></function>"),
            SSE.content("Done."),
        ]), config: { $0.historyShape = HistoryShape(parseTextToolCalls: true) })
        let first = try #require(events.assistants.first)
        #expect(first.toolCalls.map(\.name) == ["read_file"])
        #expect(first.meta?.rawContent?.contains("<function=read_file>") == true)
        #expect(first.meta?.notes?.contains { $0.hasPrefix("Recovered 1 tool call written as text") } == true)
    }

    @Test func aNudgeIsRecordedOnTheEmptyReply() async throws {
        let (events, _) = try await run(.init(turns: [SSE.content(""), SSE.content("Answer.")]))
        #expect(events.assistants.count == 2)
        #expect(events.assistants[0].meta?.notes?.first?.hasPrefix("The reply was empty; the loop asked again") == true)
        #expect(events.assistants[1].meta?.notes == nil)
    }

    @Test func reshapedHistoryIsNoted() async throws {
        let (events, _) = try await run(.init(turns: [SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#), SSE.content("Ok.")]),
                                        config: { $0.historyShape = HistoryShape(toolCallIDs: .alphanumeric9) })
        // The first request has no tool calls to rewrite; the second does.
        #expect(events.assistants[0].meta?.notes == nil)
        #expect(events.assistants[1].meta?.notes?.contains { $0.contains("reshaped") } == true)
    }
}

@Suite struct ToolRecordTests {
    @Test func approvalsSayWhoDecided() async throws {
        // A read runs without asking; an edit in Ask mode waits for the user, who allows it.
        let (events, _) = try await run(.init(turns: [
            SSE.toolCalls([("c1", "read_file", #"{"path":"README.md"}"#),
                           ("c2", "edit_file", ##"{"path":"README.md","old_string":"# Demo","new_string":"# Demo!"}"##)]),
            SSE.content("Done."),
        ]), config: { c in
            c.tools = AllTools.all
            c.policy = PermissionPolicy(mode: .ask)
            c.approve = { _ in try? await Task.sleep(for: .milliseconds(50)); return .allow }
        })
        let read = try #require(events.results.first { $0.toolCallID == "c1" }?.toolResult?.approval)
        #expect(read.decider == .mode && read.allowed)
        let edit = try #require(events.results.first { $0.toolCallID == "c2" }?.toolResult?.approval)
        #expect(edit.decider == .user && edit.allowed && (edit.waited ?? 0) >= 0.04)
    }

    @Test func rulesAndRefusalsAreNamed() async throws {
        let (events, _) = try await run(.init(turns: [
            SSE.toolCalls([("c1", "bash", #"{"command":"ls"}"#), ("c2", "edit_file", #"{"path":"README.md","old_string":"x","new_string":"y"}"#)]),
            SSE.content("Done."),
        ]), config: { c in
            c.tools = AllTools.all
            c.policy = PermissionPolicy(mode: .ask, rules: [AllowRule(kind: .commandPrefix, value: "ls")])
        })
        let bash = try #require(events.results.first { $0.toolCallID == "c1" }?.toolResult?.approval)
        #expect(bash.decider == .rule && bash.detail?.contains("ls") == true)
        // No one to ask (no approve function): refused, and the reason is recorded.
        let edit = try #require(events.results.first { $0.toolCallID == "c2" }?.toolResult?.approval)
        #expect(edit.decider == .refused || edit.detail?.contains("preview") == true)
    }

    @Test func badArgumentsAndRepeatsAreFlagged() async throws {
        let (events, _) = try await run(.init(turns: [
            SSE.toolCalls([("c1", "read_file", "{}"), ("c2", "list_dir", #"{"path":"."}"#)]),
            SSE.toolCall("c3", "list_dir", #"{"path": "."}"#),
            SSE.toolCall("c4", "no_such_tool", "{}"),
            SSE.content("Done."),
        ]))
        let r = events.results
        #expect(r.first { $0.toolCallID == "c1" }?.toolResult?.argumentProblems?.first == "missing required \"path\"")
        #expect(r.first { $0.toolCallID == "c2" }?.toolResult?.argumentProblems == nil)
        #expect(r.first { $0.toolCallID == "c3" }?.toolResult?.notes?.first?.hasPrefix("Not run: the same read") == true)
        #expect(r.first { $0.toolCallID == "c4" }?.toolResult?.argumentProblems == ["there is no tool named \"no_such_tool\""])
    }
}

@Suite struct ArgumentCheckTests {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["path": ["type": "string"], "offset": ["type": "integer"], "all": ["type": "boolean"]],
        "required": ["path"],
    ]

    @Test func findsWhatAModelGetsWrong() {
        #expect(ArgumentCheck.problems(#"{"path":"a","offset":3}"#, schema: schema).isEmpty)
        #expect(ArgumentCheck.problems("{}", schema: schema) == ["missing required \"path\"", "no arguments at all (a provider may have dropped them)"])
        #expect(ArgumentCheck.problems("", schema: schema).first == "missing required \"path\"")
        #expect(ArgumentCheck.problems(#"{"path":"a","offset":"3"}"#, schema: schema) == ["\"offset\" should be integer, got a string"])
        #expect(ArgumentCheck.problems(#"{"path":"a","offset":1.5}"#, schema: schema) == ["\"offset\" should be integer, got a number"])
        #expect(ArgumentCheck.problems(#"{"path":"a","bogus":1}"#, schema: schema) == ["unknown argument \"bogus\""])
        #expect(ArgumentCheck.problems(#"{"path":"a"#, schema: schema).first?.hasPrefix("the arguments aren't valid JSON") == true)
        #expect(ArgumentCheck.problems(#"["a"]"#, schema: schema) == ["the arguments are an array, not an object"])
    }
}

@Suite struct TimelineTests {
    @Test func turnsJoinTheirResultsAndStatsCountThem() {
        let call = ToolCall(id: "c1", name: "read_file", arguments: "{}")
        var info = ToolResultInfo(toolName: "read_file", isError: true, truncated: false, duration: 0.1)
        info.argumentProblems = ["missing required \"path\""]
        let meta = TurnMeta(requestedModel: "m", usage: Usage(promptTokens: 100, completionTokens: 20, cost: 0.01),
                            finishReason: .toolCalls, stopReason: .completed, duration: 1)
        var replyMeta = meta
        replyMeta.provider = "DeepInfra"
        let first = ChatMessage(role: .assistant, content: "", toolCalls: [call], meta: replyMeta)
        var session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil), messages: [
            .user("hi"),
            first,
            ChatMessage(role: .tool, content: "Error", toolCallID: "c1", toolResult: info),
            ChatMessage(role: .assistant, content: "Done.", meta: meta),
        ], model: "m")
        // Costs come from the session's cost records (the first reply's: OpenRouter reported $0.01).
        let openRouter = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        session.costs = [CostEntry.make(reply: first, purpose: .reply, run: nil, agent: "main", client: openRouter, endpointID: nil,
                                        start: Date(), price: .unknown("x"))]
        let items = SessionTimeline.items(session)
        #expect(items.count == 3)
        guard case .turn(let t) = items[1] else { Issue.record("not a turn"); return }
        #expect(t.number == 1 && t.calls.first?.result?.content == "Error")
        #expect(t.flags.contains("error") && t.flags.contains("bad arguments"))
        let stats = SessionStats(session)
        #expect(stats.turns == 2 && stats.toolCalls == 1 && stats.errors == 1 && stats.badArguments == 1)
        #expect(stats.promptTokens == 200 && stats.costByProvider["DeepInfra"] == 0.01)
        #expect(stats.cost.spent == 0.01 && !stats.cost.estimated)
    }
}

@Suite struct WireSettingTests {
    @Test func theRunSetupRecordsUnlessTurnedOff() throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-ws-\(UUID().uuidString.prefix(8))"))
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: "/tmp/p"), messages: [], model: "m")
        func run(_ settings: RunSettings) -> SessionRun {
            SessionRun(session: session, store: store, settings: settings, profile: ModelProfile(endpointID: UUID(), model: "m"),
                       endpointID: UUID(), mode: .ask, rules: [], tools: [], workspace: nil, shell: ShellState(cwd: URL(fileURLWithPath: "/tmp")),
                       contextLimit: nil, sandbox: nil, turn: TurnKey(UUID()),
                       checkpoints: CheckpointStore(directory: FileManager.default.temporaryDirectory.appending(path: "kk-ck")),
                       approve: { _ in .allow }, hooks: nil, subagentModel: nil)
        }
        let on = run(RunSettings())
        #expect(on.config.wireLog?.directory == store.wireDirectory(for: session.header))
        var off = RunSettings()
        off.recordWire = false
        #expect(run(off).config.wireLog == nil)
        let d = try #require(UserDefaults(suiteName: "kk-wire-\(UUID().uuidString.prefix(8))"))
        #expect(RunSettings(defaults: d).recordWire)
        d.set(false, forKey: RunSettings.Key.recordWire)
        #expect(!RunSettings(defaults: d).recordWire)
    }
}
