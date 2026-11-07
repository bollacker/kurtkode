import Foundation
import Testing
@testable import AgentCore

// The later hook events, MCP resources and cancellation, and side questions.

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var injected: [ChatMessage] { lock.withLock { items.compactMap { if case .injected(let m) = $0 { m } else { nil } } } }
    var notices: [String] { lock.withLock { items.compactMap { if case .hookNotice(let s) = $0 { s } else { nil } } } }
}

private func folder() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "kk-he-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func hooks(_ event: HookEvent, _ command: String, cwd: URL) -> Hooks {
    Hooks(matchers: [event: [HookMatcher(matcher: nil, hooks: [HookCommand(type: "command", command: command, timeout: 10)])]],
          sessionID: "s", cwd: cwd)
}

private func run(_ turns: [[Data]], _ h: Hooks, in d: URL, history: [ChatMessage] = [.user("Go")], subagents: Bool = true,
                 mode: PermissionMode = .fullAuto, approve: @escaping @Sendable (ApprovalRequest) async -> ApprovalDecision = { _ in .allow }) async -> (Log, [Data]) {
    let (client, host) = MockServer.client(.init(chunks: [], turns: turns))
    let log = Log()
    var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: mode), approve: approve)
    config.hooks = h
    if subagents { config.subagents = SubagentSetup() }
    await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: history, config: config, workspace: Workspace(root: d)) { log.add($0) }
    return (log, MockServer.requestBodies(host))
}

private func text(_ d: URL, _ name: String) -> String { (try? String(contentsOf: d.appending(path: name), encoding: .utf8)) ?? "" }

@Suite struct HookEventTests {
    @Test func sessionStartGivesTheModelContextOnANewSession() async throws {
        let d = try folder()
        let (log, bodies) = await run([SSE.content("ok")], hooks(.sessionStart, "echo the branch is main", cwd: d), in: d)
        #expect(log.injected.first?.content.contains("the branch is main") == true)
        #expect(log.injected.first?.contextNote == true)
        #expect(String(decoding: bodies[0], as: UTF8.self).contains("the branch is main"))
    }

    @Test func aContinuedSessionDoesntStartAgain() async throws {
        let d = try folder()
        let (log, _) = await run([SSE.content("ok")], hooks(.sessionStart, "echo again", cwd: d), in: d,
                                 history: [.user("one"), ChatMessage(role: .assistant, content: "done"), .user("two")])
        #expect(log.injected.isEmpty)
    }

    @Test func subagentStopHearsTheReport() async throws {
        let d = try folder()
        let call = #"{"description":"Look","prompt":"Look around.","agent":"explore"}"#
        _ = await run([SSE.toolCall("c", "task", call), SSE.content("Found it."), SSE.content("Done.")],
                      hooks(.subagentStop, "cat > stop.json", cwd: d), in: d)
        let got = text(d, "stop.json")
        #expect(got.contains("SubagentStop") && got.contains("explore") && got.contains("Found it."), "\(got)")
    }

    @Test func notificationFiresWhenTheAgentWaits() async throws {
        let d = try folder()
        _ = await run([SSE.toolCall("c", "bash", #"{"command":"echo hi"}"#), SSE.content("Done.")],
                      hooks(.notification, "cat > note.json", cwd: d), in: d, mode: .ask)
        for _ in 0..<50 where text(d, "note.json").isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(text(d, "note.json").contains("needs your approval"))
    }

    @Test func preCompactRunsBeforeAManualSummary() async throws {
        let d = try folder()
        let h = hooks(.preCompact, "cat > compact.json", cwd: d)
        let out = await h.preCompact(trigger: "manual", instructions: "keep the tests")
        #expect(out.errors.isEmpty)
        #expect(text(d, "compact.json").contains("keep the tests") && text(d, "compact.json").contains("manual"))
    }
}

private func mock() async throws -> MCPClient {
    let path = try #require(Bundle.module.url(forResource: "mock_mcp_server", withExtension: "py", subdirectory: "Fixtures")).path
    let client = MCPClient(transport: StdioTransport(command: "/usr/bin/python3", arguments: [path]))
    try await client.connect(timeout: 20)
    return client
}

@Suite struct MCPDepthTests {
    @Test func aToolsReadOnlyHintIsReadButNeverSkipsAsking() async throws {
        let client = try await mock()
        defer { Task { await client.close() } }
        let list = try await client.listTools()
        #expect(list.first { $0.name == "echo" }?.readOnly == true)
        #expect(list.first { $0.name == "add" }?.readOnly == false)
        let echo = MCPTool(server: "m", info: list.first { $0.name == "echo" }!, client: client)
        let add = MCPTool(server: "m", info: list.first { $0.name == "add" }!, client: client)
        let plan = PermissionPolicy(mode: .plan)
        #expect(plan.offered([echo, add]).map(\.name) == [echo.name])
        // The server's word only: the mode still asks.
        #expect(echo.risk == .execute)
        #expect(!plan.isAllowedWithoutAsking(echo, ToolArguments()))
        #expect(!PermissionPolicy(mode: .ask).isAllowedWithoutAsking(echo, ToolArguments()))
    }

    @Test func resourcesListAndRead() async throws {
        let client = try await mock()
        defer { Task { await client.close() } }
        #expect(await client.server?.hasResources == true)
        #expect(await client.server?.instructions == "Prefer echo for simple checks.")
        let ctx = ToolContext(workspace: Workspace(root: FileManager.default.temporaryDirectory))
        let list = try await MCPResourceList(servers: ["mock": client]).run(ToolArguments(), context: ctx)
        #expect(list.text.contains("mock://notes") && list.text.contains("Team notes"))
        let read = MCPResourceRead(servers: ["mock": client])
        #expect(try await read.run(ToolArguments(["server": "mock", "uri": "mock://notes"]), context: ctx).text == "the notes say hello")
        await #expect(throws: ToolFailure.self) { _ = try await read.run(ToolArguments(["server": "other", "uri": "x"]), context: ctx) }
    }

    @Test func stoppingEndsACallAtOnce() async throws {
        let client = try await mock()
        defer { Task { await client.close() } }
        let started = Date()
        let call = Task { try await client.callTool("slow", arguments: [:], timeout: 60) }
        try await Task.sleep(for: .milliseconds(300))
        call.cancel()
        await #expect(throws: (any Error).self) { _ = try await call.value }
        #expect(Date().timeIntervalSince(started) < 2)                      // the tool takes 5
        #expect(try await client.callTool("echo", arguments: ["text": "still here"]).text == "still here")
    }

    @Test func instructionsGoOnceAndMarkedAsTheServers() {
        #expect(MCPHub.noteHeader("notes").contains("What the notes MCP server says"))
    }
}

@Suite struct SideQuestionTests {
    @Test func theTranscriptIsTheLatestOfTheConversation() {
        var note = ChatMessage.user("secret note")
        note.contextNote = true
        let messages = [ChatMessage.user("first question"), ChatMessage(role: .assistant, content: "an answer", toolCalls: [ToolCall(id: "c", name: "grep", arguments: "{}")]),
                        ChatMessage(role: .tool, content: "output", toolCallID: "c"), note, .user("second question")]
        let t = SideQuestion.transcript(messages)
        #expect(t.contains("User: first question") && t.contains("[called grep]") && t.contains("Tool result: output"))
        #expect(!t.contains("secret note"))
        let short = SideQuestion.transcript(messages, limit: 30)
        #expect(short.contains("second question") && !short.contains("first question"))
    }

    @Test func itAsksWithoutToolsAndRecordsItsCost() async throws {
        let (client, host) = MockServer.client(.init(chunks: SSE.content("It's in main.swift.")))
        final class Box: @unchecked Sendable { let lock = NSLock(); var entries: [CostEntry] = [] }
        let box = Box()
        let sink = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: nil) { e in box.lock.withLock { box.entries.append(e) } }
        let answer = await SideQuestion.ask("Where is it?", messages: [.user("Find the parser")], client: client, model: "m", limits: TurnLimits(), costs: sink)
        #expect(answer == "It's in main.swift." && box.lock.withLock { box.entries.map(\.purpose) } == [.side])
        let body = String(decoding: try #require(MockServer.requestBody(host)), as: UTF8.self)
        #expect(body.contains("Where is it?") && body.contains("Find the parser") && !body.contains("\"tools\":[{"))
    }
}
