import Foundation
import Testing
@testable import AgentCore

/// A turn that reasons, then answers or calls a tool.
private func reasoned(_ reasoning: String, then turn: [Data]) -> [Data] {
    let r = String(decoding: try! JSONEncoder().encode(reasoning), as: UTF8.self)
    return [SSE.line(#"{"model":"test-model","choices":[{"index":0,"delta":{"reasoning_content":\#(r)},"finish_reason":null}]}"#)] + turn
}

private final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ChatMessage] = []
    func add(_ e: AgentEvent) {
        switch e {
        case .assistant(let m), .toolFinished(let m), .injected(let m): lock.withLock { items.append(m) }
        default: break
        }
    }
    var all: [ChatMessage] { lock.withLock { items } }
}

/// Runs the loop as the app does (wire log on) and returns the session it made and its context index.
private func journal(_ turns: [[Data]], shape: HistoryShape = HistoryShape()) async throws -> SessionJournal {
    let (client, _) = MockServer.client(.init(turns: turns))
    let wire = FileManager.default.temporaryDirectory.appending(path: "kk-journal-\(UUID().uuidString.prefix(8))")
    var config = AgentConfig(tools: ReadTools.all)
    config.wireLog = WireLog(directory: wire)
    config.historyShape = shape
    let first = ChatMessage.user("Read README.md and summarize it.")
    let got = Messages()
    await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [first], config: config,
                        workspace: try makeProject()) { got.add($0) }
    let session = Session(header: SessionHeader(endpointID: UUID(), model: "test-model", workspace: nil),
                          messages: [first] + got.all, model: "test-model")
    return SessionJournal(session: session, contexts: WireLog.contexts(wire))
}

private func entry(_ j: SessionJournal, _ match: (SessionJournal.Entry.Kind) -> Bool) -> SessionJournal.Entry? {
    j.entries.first { match($0.kind) }
}

@Suite struct JournalTests {
    @Test func blendsTheSessionAndKnowsWhatEachTurnSaw() async throws {
        let j = try await journal([
            reasoned("The user wants README.md; read it.", then: SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#)),
            reasoned("It's a demo.", then: SSE.content("A demo project.")),
        ])
        #expect(j.turnCount == 2 && j.contexts.count == 2)
        // In order: system prompt, the user, turn 1 (reasoning, tool use), turn 2 (reasoning, answer).
        let kinds = j.entries.map { e -> String in
            switch e.kind {
            case .system: "system"
            case .user: "user"
            case .reasoning: "reasoning"
            case .toolUse: "tool"
            case .output: "output"
            default: "other"
            }
        }
        #expect(kinds == ["system", "user", "reasoning", "tool", "reasoning", "output"])
        let user = try #require(entry(j) { if case .user = $0 { true } else { false } })
        let tool = try #require(entry(j) { if case .toolUse = $0 { true } else { false } })
        let reasoning1 = try #require(j.entries.first { if case .reasoning = $0.kind { $0.turn == 1 } else { false } })
        let answer = try #require(entry(j) { if case .output = $0 { true } else { false } })
        // Turn 1's request: the system prompt and the user. Its own reasoning and call are this turn's.
        #expect(j.status(user, inTurn: 1) == .inContext)
        #expect(j.status(tool, inTurn: 1) == .thisTurn && j.status(answer, inTurn: 1) == .later)
        // Turn 2 saw the tool use, but not turn 1's reasoning (this model doesn't get it back).
        #expect(j.status(tool, inTurn: 2) == .inContext)
        #expect(j.status(reasoning1, inTurn: 2) == .notSent("reasoning isn't sent back to this model"))
        #expect(j.lifetimeSummary(user) == "in context for turns 1–2")
        #expect(j.lifetimeSummary(reasoning1).hasPrefix("never in a request: reasoning isn't sent back"))
        // Where did the call's path come from? The user's message.
        #expect(SessionJournal.values(Self.call(tool)) == ["README.md"])
        #expect(j.origin(of: "README.md", before: tool.id)?.id == user.id)
    }

    static func call(_ e: SessionJournal.Entry) -> ToolCall {
        if case .toolUse(let c, _, _) = e.kind { return c }
        return ToolCall(id: "", name: "", arguments: "")
    }

    @Test func reasoningSentBackShowsInContext() async throws {
        let j = try await journal([
            reasoned("Read it first.", then: SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#)),
            SSE.content("Done."),
        ], shape: HistoryShape(sendReasoning: true))
        let reasoning = try #require(entry(j) { if case .reasoning = $0 { true } else { false } })
        #expect(j.status(reasoning, inTurn: 2) == .inContext)
    }

    @Test func aNudgeIsInTheNextRequestOnly() async throws {
        let j = try await journal([SSE.content(""), SSE.content("Answer."), SSE.content("Unused.")])
        let nudge = try #require(entry(j) { if case .loop(let s, _) = $0 { s.hasPrefix("The reply was empty") } else { false } })
        let empty = try #require(j.entries.first { if case .output = $0.kind { $0.turn == 1 } else { false } })
        #expect(j.status(nudge, inTurn: 2) == .inContext)
        #expect(j.status(empty, inTurn: 2) == .notSent("an empty reply isn't sent back"))
        #expect(j.contexts[2]?.refs.contains { $0.kind == "nudge" } == true)
    }

    @Test func compactionsAndTrimmingAreExplained() throws {
        // Built by hand: u1, a1 (calls c1), r1 (a long result), u2, a2; compacted after r1; turn 3 sees a trimmed r1.
        let u1 = ChatMessage.user("First question")
        let call = ToolCall(id: "c1", name: "read_file", arguments: #"{"path":"big.txt"}"#)
        let meta = TurnMeta(requestedModel: "m", usage: Usage(promptTokens: 1000, completionTokens: 10), stopReason: .completed, duration: 1)
        let a1 = ChatMessage(role: .assistant, content: "", toolCalls: [call], meta: meta)
        let r1 = ChatMessage(role: .tool, content: String(repeating: "x", count: 5000), toolCallID: "c1",
                             toolResult: ToolResultInfo(toolName: "read_file", isError: false, truncated: false, duration: 0))
        let a2 = ChatMessage(role: .assistant, content: "Answer one.", meta: meta)
        let u2 = ChatMessage.user("Second question")
        let a3 = ChatMessage(role: .assistant, content: "Answer two.", meta: meta)
        var session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil),
                              messages: [u1, a1, r1, a2, u2, a3], model: "m")
        session.compactions = [Compaction(summary: "Earlier: read big.txt.", lastSummarizedID: a2.id, continuation: nil,
                                          tokensBefore: 2000, tokensAfter: 300)]
        let t0 = Date()
        func ref(_ m: ChatMessage, _ bytes: Int? = nil) -> ContextRef {
            ContextRef(id: m.id, role: m.role.rawValue, bytes: bytes ?? m.content.utf8.count + m.toolCalls.reduce(0) { $0 + $1.arguments.utf8.count })
        }
        let contexts = [
            ContextSnapshot(replyID: a1.id, startedAt: t0, refs: [ContextRef(id: nil, role: "system", kind: "system", bytes: 400), ref(u1)]),
            ContextSnapshot(replyID: a2.id, startedAt: t0, refs: [ContextRef(id: nil, role: "system", kind: "system", bytes: 400),
                                                                  ref(u1), ref(a1), ref(r1)]),
            // After the compaction: the summary in the system prompt, r1 kept but trimmed, then the new question.
            ContextSnapshot(replyID: a3.id, startedAt: t0, refs: [ContextRef(id: nil, role: "system", kind: "system+summary", bytes: 450),
                                                                  ref(a1), ref(r1, 1200), ref(u2)]),
        ]
        let j = SessionJournal(session: session, contexts: contexts)
        let first = try #require(j.entries.first { if case .user(let m) = $0.kind { m.id == u1.id } else { false } })
        let tool = try #require(entry(j) { if case .toolUse = $0 { true } else { false } })
        let compaction = try #require(entry(j) { if case .compaction = $0 { true } else { false } })
        #expect(j.status(first, inTurn: 3) == .notSent("replaced by a compaction summary"))
        #expect(j.status(tool, inTurn: 2) == .inContext && j.status(tool, inTurn: 3) == .trimmed)
        #expect(j.status(compaction, inTurn: 2) == .later && j.status(compaction, inTurn: 3) == .inContext)
        #expect(j.lifetimeSummary(tool) == "in context for turns 2–3 (trimmed from turn 3)")
        #expect(j.lifetimeSummary(first) == "in context for turns 1–2; then replaced by a compaction summary")
        // Two system prompt entries: the original and the one with the summary.
        #expect(j.entries.filter { if case .system = $0.kind { true } else { false } }.count == 2)
        // The budget splits turn 3's prompt into its parts, scaled to the reported 1000 tokens.
        let b3 = try #require(j.budget.first { $0.turn == 3 })
        #expect(b3.promptTokens == 1000 && (b3.parts["summary"] ?? 0) > 0 && (b3.parts["tool"] ?? 0) > (b3.parts["user"] ?? 0))
        #expect(abs(b3.parts.values.reduce(0, +) - 1000) <= 5)
    }

    @Test func eventsAreRecordedWithTimes() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-ev-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: nil)
        try await store.create(header)
        try await store.append(.message(.user("hi")), to: header.id)
        try await store.append(.permissionMode(.plan), to: header.id)
        try await store.append(.model("other-model", endpoint: nil), to: header.id)
        let s = try #require(try await store.load(header.id))
        #expect(s.events.map(\.kind) == [.mode, .model] && s.events.map(\.text) == ["Plan (read-only)", "other-model"])
        let j = SessionJournal(session: s, contexts: [])
        #expect(j.entries.count == 3)
        guard case .event = j.entries[2].kind else { Issue.record("events go after the message"); return }
    }
}

@Suite struct JournalFilterTests {
    @Test func filtersCombineAndSearchFindsReasoningToo() async throws {
        // Reuses the real-run journal: system, user, reasoning, read_file, reasoning, answer.
        let (client, _) = MockServer.client(.init(turns: [
            [SSE.line(#"{"model":"test-model","choices":[{"index":0,"delta":{"reasoning_content":"Look at the Walrus file."},"finish_reason":null}]}"#)]
                + SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("It mentions a demo."),
        ]))
        let wire = FileManager.default.temporaryDirectory.appending(path: "kk-jf-\(UUID().uuidString.prefix(8))")
        var config = AgentConfig(tools: ReadTools.all)
        config.wireLog = WireLog(directory: wire)
        let first = ChatMessage.user("What does README.md say?")
        final class Box: @unchecked Sendable { var m: [ChatMessage] = []; let l = NSLock() }
        let box = Box()
        await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [first], config: config,
                            workspace: try makeProject()) { e in
            switch e {
            case .assistant(let m), .toolFinished(let m): box.l.withLock { box.m.append(m) }
            default: break
            }
        }
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "test-model", workspace: nil),
                              messages: [first] + box.m, model: "test-model")
        let j = SessionJournal(session: session, contexts: WireLog.contexts(wire))
        let all = j.visible(.init(), statuses: [:])
        #expect(all.count == j.entries.count)
        // Search: case-insensitive, finds the reasoning, and the tool by name.
        #expect(j.hits("walrus", in: all).count == 1)
        #expect(j.hits("READ_FILE", in: all).count == 1)
        var f = SessionJournal.Filter()
        f.query = "demo"
        f.onlyMatches = true
        #expect(j.visible(f, statuses: [:]).count == j.hits("demo", in: all).count)
        // Kinds: reasoning and tool uses only.
        f = .init()
        f.groups = [.reasoning, .tools]
        #expect(j.visible(f, statuses: [:]).map(\.group) == [.reasoning, .tools])
        // Turn range: turn 2 only (its reasoning and answer).
        f = .init()
        f.turns = 2...2
        #expect(j.visible(f, statuses: [:]).allSatisfy { $0.turn == 2 } && j.visible(f, statuses: [:]).count == 1)
        // The lens: what turn 2's request held, and what it left out (turn 1's reasoning).
        let s2 = j.statuses(inTurn: 2)
        f = .init()
        f.lens = .inRequest
        let held = j.visible(f, statuses: s2)
        #expect(held.contains { $0.group == .tools } && !held.contains { $0.group == .reasoning && $0.turn == 1 })
        f.lens = .leftOut
        #expect(j.visible(f, statuses: s2).map(\.group) == [.reasoning])
        // A tool filter hides other tools' uses, not other kinds.
        f = .init()
        f.tool = "grep"
        #expect(!j.visible(f, statuses: [:]).contains { $0.group == .tools } && j.visible(f, statuses: [:]).count == all.count - 1)
    }
}

/// Claude's thinking in the Journal: sent back with later requests, dropped by the server, or not sent and why.
@Suite struct NativeThinkingJournalTests {
    static func sse(_ events: [String]) -> [Data] { events.map { Data("data: \($0)\n\n".utf8) } }

    @Test func showsThinkingTheServerDropped() async throws {
        let start = #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":50}}}"#
        let turn1 = Self.sse([start,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Read the readme first."}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sigA"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"README.md\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}"#])
        let turn2 = Self.sse([
            #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":90},"input_transformations":[{"type":"thinking_dropped","path":"messages.1.content.0","reason":"prefix_binding_mismatch"}]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"A demo project."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#])
        let (client, _) = MockServer.client(.init(turns: [turn1, turn2]), api: .anthropic)
        let wire = FileManager.default.temporaryDirectory.appending(path: "kk-journal-\(UUID().uuidString.prefix(8))")
        var config = AgentConfig(tools: ReadTools.all)
        config.wireLog = WireLog(directory: wire)
        let first = ChatMessage.user("Read README.md and summarize it.")
        let got = Messages()
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "SYSTEM", history: [first], config: config,
                            workspace: try makeProject()) { got.add($0) }
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "claude-opus-5-5", workspace: nil),
                              messages: [first] + got.all, model: "claude-opus-5-5")
        let reply1 = try #require(session.messages.first { $0.role == .assistant })
        #expect(reply1.native?.blocks.arrayValue?.count == 2)

        let dropped = SessionJournal.droppedThinking(session: session, wire: wire)
        let j = SessionJournal(session: session, contexts: WireLog.contexts(wire), droppedThinking: dropped)
        let thinking = try #require(entry(j) { if case .reasoning = $0 { true } else { false } })
        #expect(j.status(thinking, inTurn: 1) == .thisTurn)
        #expect(j.status(thinking, inTurn: 2)
                == .notSent("sent, but the server dropped it: the history before it changed (a compaction or trimmed output)"))
        // Without the wire log's word on it, it counts as sent.
        #expect(SessionJournal(session: session, contexts: WireLog.contexts(wire)).status(thinking, inTurn: 2) == .inContext)

        // Turn 2 asked for another model: the thinking stays behind, and the Journal says why.
        var other = session
        if let i = other.messages.lastIndex(where: { $0.role == .assistant }) { other.messages[i].meta?.requestedModel = "claude-sonnet-5-5" }
        var refs = WireLog.contexts(wire)
        refs[1].refs = refs[1].refs.map { r in var r = r; r.reasoning = nil; return r }
        let k = SessionJournal(session: other, contexts: refs)
        #expect(k.status(thinking, inTurn: 2) == .notSent(
            "claude-opus-5-5 wrote it; thinking goes back only to the model that wrote it (this turn: claude-sonnet-5-5)"))
    }
}
