import Foundation
import Testing
@testable import AgentCore

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var events: [AgentEvent] { lock.withLock { items } }

    var assistants: [ChatMessage] { events.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
    var toolResults: [ChatMessage] { events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var stop: AgentStop? { events.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last }
}

private func runAgent(_ turns: [[Data]], maxSteps: Int = 30, workspace: Workspace? = nil,
                      history: [ChatMessage] = [.user("What is this project?")]) async throws -> (Recorder, String) {
    let ws = try workspace ?? makeProject()
    let (client, host) = MockServer.client(.init(turns: turns))
    let rec = Recorder()
    await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: history,
                        config: AgentConfig(tools: ReadTools.all, maxSteps: maxSteps), workspace: ws) { rec.add($0) }
    return (rec, host)
}

private func messages(inRequest body: Data) throws -> [[String: JSONValue]] {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body),
          case .array(let msgs) = o["messages"] else { return [] }
    return msgs.compactMap { if case .object(let m) = $0 { m } else { nil } }
}

@Suite struct AgentLoopTests {
    @Test func runsAToolAndFeedsBackTheResult() async throws {
        let (rec, host) = try await runAgent([
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("It is a demo project."),
        ])
        #expect(rec.stop == .completed)
        #expect(rec.assistants.count == 2)
        #expect(rec.assistants[0].toolCalls.map(\.name) == ["read_file"])
        #expect(rec.assistants[1].content == "It is a demo project.")
        let result = try #require(rec.toolResults.first)
        #expect(result.toolCallID == "call_1")
        #expect(result.content.contains("1\t# Demo"))
        #expect(result.toolResult?.isError == false)

        // Second request: system prompt, user, assistant with tool_calls, then the tool result.
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 2)
        let second = try messages(inRequest: bodies[1])
        #expect(second.map { $0["role"] } == ["system", "user", "assistant", "tool"])
        #expect(second[0]["content"] == "SYSTEM")
        #expect(second[3]["tool_call_id"] == "call_1")
        guard case .object(let first) = try JSONDecoder().decode(JSONValue.self, from: bodies[0]),
              case .array(let tools) = first["tools"] else { Issue.record("no tools sent"); return }
        #expect(tools.count == 4)          // ReadTools only
    }

    @Test func asksOnceAfterAnEmptyReply() async throws {
        let (rec, host) = try await runAgent([
            SSE.toolCall("call_1", "grep", #"{"pattern":"nothing_matches_this"}"#),
            SSE.content(""),
            SSE.content("It isn't defined anywhere."),
        ])
        #expect(rec.stop == .completed)
        #expect(rec.assistants.last?.content == "It isn't defined anywhere.")
        // The retry drops the empty turn and asks: ..., tool result, user nudge.
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)
        let third = try messages(inRequest: bodies[2])
        #expect(third.map { $0["role"] } == ["system", "user", "assistant", "tool", "user"])
        #expect(third.last?["content"] == .string(AgentLoop.emptyReplyNudge(reasoning: nil)))
    }

    @Test func asksAgainAfterAReplyOfOnlyAToolCallMarker() async throws {
        // Seen on Gemma 4 26B in the long-doc eval: the 12th reply was "<tool_call|>" (2 tokens, finish stop) and the
        // run ended with it as the answer.
        let (rec, host) = try await runAgent([
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("<tool_call|>"),
            SSE.content("It is a demo project."),
        ])
        #expect(rec.stop == .completed)
        #expect(rec.assistants.last?.content == "It is a demo project.")
        #expect(rec.assistants[1].meta?.notes?.first?.contains("only a tool-call marker") == true)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)
        let third = try messages(inRequest: bodies[2])
        #expect(third.map { $0["role"] } == ["system", "user", "assistant", "tool", "user"])
        #expect(third.last?["content"] == .string(AgentLoop.markerOnlyNudge))
    }

    /// Seen on Gemma 4 26B (long-doc, 9 of 14 files): "The next step is to continue…" with the todo list half done, and
    /// the run ended. Asked once; the reply stays.
    @Test func asksOnceWhenTheRunsTodoListIsUnfinished() async throws {
        let ws = try makeProject()
        let todos = #"{"todos":[{"content":"Read README.md","status":"completed"},{"content":"Read src/main.swift","status":"pending"}]}"#
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "todo_write", todos),
            SSE.content("The next step is to read src/main.swift."),
            SSE.content("Stopping here: main.swift isn't needed."),
        ]))
        let rec = Recorder()
        await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [.user("Go")],
                            config: AgentConfig(tools: ReadTools.all + [TodoWriteTool()], maxSteps: 30), workspace: ws) { rec.add($0) }
        #expect(rec.stop == .completed)
        #expect(rec.assistants.map(\.content).suffix(2) == ["The next step is to read src/main.swift.", "Stopping here: main.swift isn't needed."])
        #expect(rec.assistants[1].meta?.notes?.first?.contains("todo list still had open items") == true)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)                     // asked once, not again after the second answer
        let third = try messages(inRequest: bodies[2])
        guard case .string(let nudge)? = third.last?["content"] else { Issue.record("no nudge"); return }
        #expect(nudge.contains("1 open item") && nudge.contains("Read src/main.swift"))
        // A list from an earlier run doesn't count.
        #expect(AgentLoop.openTodosNudge([.user("unrelated question")]) == nil)
    }

    @Test func recognizesToolCallMarkers() {
        for s in ["<tool_call|>", " <|tool_call> ", "<tool_call></tool_call>", "<|tool_calls_section_begin|>", "\n</tool_call>\n"] {
            #expect(AgentLoop.onlyToolCallMarkers(s), "\(s)")
        }
        for s in ["", "Done.", "<tool_call|> Done.", "Use <tool_call> tags", "<b>"] {
            #expect(!AgentLoop.onlyToolCallMarkers(s), "\(s)")
        }
    }

    @Test func stopsAskingAfterThreeEmptyReplies() async throws {
        let (rec, host) = try await runAgent([SSE.content("")])
        #expect(rec.stop == .completed)
        #expect(MockServer.requestBodies(host).count == 4)
    }

    /// Hands out `message` on the `on`-th call to takeInput, nothing otherwise.
    private final class Inbox: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let on: Int, message: ChatMessage
        init(on: Int, _ text: String) { self.on = on; message = .user(text) }
        func take() -> [ChatMessage] { lock.withLock { calls += 1; return calls == on ? [message] : [] } }
    }

    private func runWithInbox(_ turns: [[Data]], _ inbox: Inbox) async throws -> (Recorder, String) {
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: turns))
        let rec = Recorder()
        var config = AgentConfig(tools: ReadTools.all)
        config.takeInput = { inbox.take() }
        await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [.user("Go")],
                            config: config, workspace: ws) { rec.add($0) }
        return (rec, host)
    }

    @Test func queuedInputSteersAtTheNextStep() async throws {
        let (rec, host) = try await runWithInbox([
            SSE.toolCall("call_1", "list_dir", "{}"),
            SSE.content("Done, and I looked at src too."),
        ], Inbox(on: 2, "Also look at src."))
        #expect(rec.stop == .completed)
        let injected = rec.events.compactMap { if case .injected(let m) = $0 { m } else { nil } }
        #expect(injected.map(\.content) == ["Also look at src."])
        let second = try messages(inRequest: MockServer.requestBodies(host)[1])
        #expect(second.map { $0["role"] } == ["system", "user", "assistant", "tool", "user"])
        #expect(second.last?["content"] == "Also look at src.")
    }

    @Test func inputThatArrivesDuringTheLastReplyContinuesTheRun() async throws {
        let (rec, host) = try await runWithInbox([
            SSE.content("First answer."),
            SSE.content("Second answer."),
        ], Inbox(on: 2, "One more thing."))
        #expect(rec.stop == .completed)
        #expect(rec.assistants.map(\.content) == ["First answer.", "Second answer."])
        let second = try messages(inRequest: MockServer.requestBodies(host)[1])
        #expect(second.map { $0["role"] } == ["system", "user", "assistant", "user"])
    }

    @Test func countsEmptyRepliesInARowNotPerRun() async throws {
        let (rec, _) = try await runAgent([
            SSE.content(""),
            SSE.toolCall("call_1", "list_dir", "{}"),
            SSE.content(""), SSE.content(""), SSE.content(""),
            SSE.content("Done."),
        ])
        #expect(rec.stop == .completed)
        #expect(rec.assistants.last?.content == "Done.")
    }

    @Test func saysWhenTheCallWentIntoTheReasoning() {
        #expect(AgentLoop.emptyReplyNudge(reasoning: #"Let's list inventory.{"path": "inventory"}"#).contains("end of your reasoning"))
        #expect(AgentLoop.emptyReplyNudge(reasoning: "Nothing matched.") == AgentLoop.emptyReplyNudge)
        #expect(AgentLoop.emptyReplyNudge(reasoning: nil) == AgentLoop.emptyReplyNudge)
        #expect(AgentLoop.emptyReplyNudge(reasoning: nil, generatedTokens: 48).contains("dropped it"))
        #expect(AgentLoop.emptyReplyNudge(reasoning: nil, generatedTokens: 400).contains("under about 800 characters"))
        #expect(AgentLoop.emptyReplyNudge(reasoning: String(repeating: "thinking ", count: 40), generatedTokens: 90) == AgentLoop.emptyReplyNudge)
    }

    @Test func runsParallelCallsInOrder() async throws {
        let (rec, _) = try await runAgent([
            SSE.toolCalls([("a", "list_dir", "{}"), ("b", "glob", #"{"pattern":"*.swift"}"#)]),
            SSE.content("done"),
        ])
        #expect(rec.toolResults.map(\.toolCallID) == ["a", "b"])
        #expect(rec.toolResults[1].content.contains("src/main.swift"))
    }

    @Test func nudgesInsteadOfRepeatingACall() async throws {
        let (rec, _) = try await runAgent([
            SSE.toolCall("1", "read_file", #"{"path":"README.md"}"#),
            SSE.toolCall("2", "read_file", #"{ "path" : "README.md" }"#),     // same call, different spacing
            SSE.content("ok"),
        ])
        #expect(rec.toolResults.count == 2)
        #expect(rec.toolResults[1].content.contains("You already called read_file"))
        #expect(rec.toolResults[1].toolResult?.isError == true)
        #expect(rec.stop == .completed)
    }

    @Test func reportsBadCallsToTheModelAndContinues() async throws {
        let (rec, _) = try await runAgent([
            SSE.toolCalls([("1", "delete_everything", "{}"), ("2", "read_file", "{oops")]),
            SSE.content("sorry"),
        ])
        #expect(rec.toolResults[0].content.contains("unknown tool \"delete_everything\""))
        #expect(rec.toolResults[1].content.contains("not valid JSON"))
        #expect(rec.stop == .completed)
    }

    @Test func stopsAtTheStepLimit() async throws {
        let (rec, host) = try await runAgent([SSE.toolCall("x", "list_dir", "{}")], maxSteps: 3)
        #expect(rec.stop == .stepLimit)
        #expect(MockServer.requestBodies(host).count == 3)
    }

    @Test func stopsWhenATurnFails() async throws {
        let (client, _) = MockServer.client(.init(status: 500, chunks: [Data(#"{"error":"boom"}"#.utf8)]))
        let rec = Recorder()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("hi")],
                            config: AgentConfig(tools: ReadTools.all), workspace: try makeProject()) { rec.add($0) }
        #expect(rec.stop == .turnStopped(.failed))
    }

    @Test func cleansHistoryBeforeSending() {
        let call = ToolCall(id: "c1", name: "list_dir", arguments: "{}")
        let history: [ChatMessage] = [
            .user("q"),
            ChatMessage(role: .assistant, content: ""),                              // failed turn: dropped
            ChatMessage(role: .tool, content: "orphan", toolCallID: "nobody"),       // no matching call: dropped
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),           // stopped before the tool ran
            .user("again"),
        ]
        let out = AgentLoop.sendable(history)
        #expect(out.map(\.role) == [.user, .assistant, .tool, .user])
        #expect(out[2].toolCallID == "c1")
        #expect(out[2].content.contains("no result was recorded"))
    }
}

/// Spending limits: a run pauses before its next request once it has spent its limit; a session limit counts what
/// came before.
@Suite struct CostLimitTests {
    /// A tool call that cost `dollars` (OpenRouter-style reported cost).
    static func costlyCall(_ id: String, _ dollars: Double) -> [Data] {
        let calls = SSE.toolCall(id, "read_file", #"{"path":"README.md"}"#)
        return calls.dropLast() + [SSE.line(#"{"model":"m","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"cost":\#(dollars)}}"#),
                                   calls.last!]
    }

    @Test func aRunPausesAtItsLimitAndASessionCountsWhatCameBefore() async throws {
        let (client, host) = MockServer.client(.init(turns: [Self.costlyCall("a", 0.6), Self.costlyCall("b", 0.6), SSE.content("Done.")]))
        var config = AgentConfig(tools: ReadTools.all)
        config.costMeter = CostMeter(runLimit: 1.0, sessionLimit: nil, sessionBefore: 0)
        final class Box: @unchecked Sendable { var stop: AgentStop? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: try makeProject()) { if case .finished(let s) = $0 { box.stop = s } }
        #expect(box.stop == .costLimit)
        #expect(MockServer.requestBodies(host).count == 2)          // paused before the third request
        #expect(config.costMeter?.run == 1.2)
        #expect(config.costMeter?.reached == "this run's limit of $1.00: it has spent $1.20")

        // A session already at its limit doesn't send anything.
        let (c2, h2) = MockServer.client(.init(turns: [SSE.content("Hi.")]))
        var config2 = AgentConfig(tools: ReadTools.all)
        config2.costMeter = CostMeter(runLimit: 0, sessionLimit: 5, sessionBefore: 5.2)
        await AgentLoop.run(client: c2, model: "m", systemPrompt: "S", history: [.user("go")], config: config2,
                            workspace: try makeProject()) { if case .finished(let s) = $0 { box.stop = s } }
        #expect(box.stop == .costLimit && MockServer.requestBodies(h2).isEmpty)
        #expect(CostMeter(runLimit: 0, sessionLimit: 0, sessionBefore: 9).reached == nil)   // 0: no limits
    }
}
