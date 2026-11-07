import Foundation
import Testing
@testable import AgentCore

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var compactions: [Compaction] { lock.withLock { items.compactMap { if case .compacted(let c) = $0 { c } else { nil } } } }
    var assistants: [ChatMessage] { lock.withLock { items.compactMap { if case .assistant(let m) = $0 { m } else { nil } } } }
    var toolResults: [ChatMessage] { lock.withLock { items.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } } }
    var stop: AgentStop? { lock.withLock { items.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last } }
    var costs: [CostEntry] { lock.withLock { items.compactMap { if case .cost(let e) = $0 { e } else { nil } } } }
}

private func body(_ data: Data) throws -> (messages: [[String: JSONValue]], tools: Int) {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data),
          case .array(let msgs) = o["messages"] else { return ([], 0) }
    var tools = 0
    if case .array(let t)? = o["tools"] { tools = t.count }
    return (msgs.compactMap { if case .object(let m) = $0 { m } else { nil } }, tools)
}

private func text(_ v: JSONValue?) -> String { if case .string(let s)? = v { s } else { "" } }

/// A project with big files (Big.swift, Big2.swift), so reading them pushes the context over a small budget.
private func bigProject() throws -> Workspace {
    let ws = try makeProject()
    let big = (1...400).map { "let value\($0) = compute(\($0)) // some explanatory text to take up room" }.joined(separator: "\n")
    try Data(big.utf8).write(to: ws.root.appending(path: "Big.swift"))
    try Data(big.utf8).write(to: ws.root.appending(path: "Big2.swift"))
    return ws
}

/// Reading Big.swift and then Big2.swift passes this budget's threshold; compacting then summarizes the first read
/// and keeps the second (with all tools offered, the tool schemas alone are about 1.4k tokens).
private let twoReadBudget = ContextBudget(limit: 12_000, outputReserve: 500)
private let readBig = SSE.toolCall("r1", "read_file", #"{"path":"Big.swift"}"#)
private let readBig2 = SSE.toolCall("r2", "read_file", #"{"path":"Big2.swift"}"#)

@Suite struct ContextTests {
    @Test func compactsWithAPrefixSharingSummaryRequest() async throws {
        let ws = try bigProject()
        let user = ChatMessage.user("Describe Big.swift.")
        let turns = [
            readBig,                                                       // 1: read a big file
            readBig2,                                                      // 2: and another
            SSE.content("## Summary\nThe user asked about Big.swift; it defines 400 computed values. Next: answer."),  // 3: summary
            SSE.content("Big.swift defines 400 values."),                  // 4: answer after compaction
        ]
        let (client, host) = MockServer.client(.init(turns: turns))
        let events = Events()
        let config = AgentConfig(tools: AllTools.all, context: twoReadBudget)
        await AgentLoop.run(client: client, model: "m", systemPrompt: "BASE PROMPT", history: [user], config: config,
                            workspace: ws) { events.add($0) }

        #expect(events.stop == .completed)
        let c = try #require(events.compactions.first)
        #expect(c.lastSummarizedID == events.toolResults.first?.id)   // summarized through the first read…
        #expect(c.continuation != nil)                         // …so the kept part needs a user turn first
        #expect(c.tokensAfter < c.tokensBefore - Compactor.minimumSaving(twoReadBudget))

        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 4)
        // The summary request is the previous prompt plus one instruction, with the same tools (cache reuse).
        let first = try body(bodies[1]), summaryReq = try body(bodies[2])
        #expect(summaryReq.tools == first.tools)
        #expect(summaryReq.messages.count == first.messages.count + 3)     // + assistant call, tool result, instruction
        let instruction = text(summaryReq.messages.last?["content"])
        #expect(instruction.hasPrefix("Summarize this session"))
        // The summary request keeps the model's default (thinking), like the agent's turns: same prompt, same cache.
        let raw = bodies.map { String(decoding: $0, as: UTF8.self) }
        #expect(!raw.contains { $0.contains("reasoning_effort") })
        // After compacting: the summary is in the system prompt and the big tool output is gone or trimmed.
        let after = try body(bodies[3])
        let system = text(after.messages.first?["content"])
        #expect(system.hasPrefix("BASE PROMPT"))
        #expect(system.contains("# Summary of the earlier conversation"))
        #expect(system.contains("400 computed values"))
        #expect(bodies[3].count < bodies[2].count * 2 / 3)   // the first read is gone
        // The second read goes on whole: the model hadn't read it yet (bug hunt 2026-11-02, item 16).
        #expect(text(after.messages.last?["content"]) == events.toolResults[1].content)
        let hasContinuation = after.messages.contains { m in
            m["role"] == .string("user") && text(m["content"]) == Compactor.continuationText
        }
        #expect(hasContinuation)

        // The next run rebuilds the same prompt from the session: same trimmed tool output, same continuation.
        let stored: [ChatMessage] = [user] + events.assistants.prefix(1)
            + [ChatMessage(role: .tool, content: String(repeating: "x", count: 30_000), toolCallID: "r1")]
        var tail = stored
        tail[2].id = UUID()
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "m"), messages: tail, model: "m",
                              compactions: [Compaction(summary: c.summary, lastSummarizedID: user.id,
                                                       continuation: c.continuation, lastKeptID: tail[2].id,
                                                       tokensBefore: 1, tokensAfter: 1)])
        let rebuilt = session.modelHistory.messages
        #expect(rebuilt.first?.content == Compactor.continuationText)
        #expect(rebuilt.last.map { $0.content.utf8.count < 4200 } == true)
        #expect(c.lastKeptID == nil)                            // nothing kept was trimmed: only the unread second read was kept
    }

    @Test func overflowErrorTriggersCompactionAndRetry() async throws {
        let ws = try bigProject()
        let overflow = Data(#"{"error":"The number of tokens to keep from the initial prompt is greater than the context length. Try to load the model with a larger context length, or provide a shorter input"}"#.utf8)
        let turns = [
            readBig,                                               // 1: read a big file
            readBig2,                                              // 2: and another
            [overflow],                                            // 3: server rejects the prompt
            SSE.content("## Summary\nThe user asked about Big.swift, which was read; it defines 400 computed values."),   // 4: summary
            SSE.content("It has 400 values."),                     // 5: retried turn
        ]
        let (client, host) = MockServer.client(.init(turns: turns, turnStatuses: [2: 400]))
        let events = Events()
        // A generous budget, so only the error can trigger compaction.
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 1_000_000))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.compactions.count == 1)
        #expect(events.stop == .completed)
        #expect(events.assistants.last?.content == "It has 400 values.")
        #expect(!events.assistants.contains { $0.meta?.stopReason == .failed })   // the failed attempt isn't recorded
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 5)
        // The first read is summarized away; the second, which the model hadn't read yet, goes on whole.
        let retried = try body(bodies[4])
        #expect(text(retried.messages.last?["content"]) == events.toolResults[1].content)
    }

    @Test func noCompactionWithoutABudget() async throws {
        let ws = try bigProject()
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("r1", "read_file", #"{"path":"Big.swift"}"#),
                                                             SSE.content("ok")]))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")],
                            config: AgentConfig(tools: AllTools.all), workspace: ws) { events.add($0) }
        #expect(events.compactions.isEmpty)
        #expect(MockServer.requestBodies(host).count == 2)
    }

    @Test func cutKeepsWholeGroupsAndPrefersUserBoundaries() {
        var est = TokenEstimator()
        est.bytesPerToken = 1
        let call = ToolCall(id: "c", name: "read_file", arguments: "{}")
        let history: [ChatMessage] = [
            .user(String(repeating: "a", count: 100)),                                     // 0
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),                 // 1
            ChatMessage(role: .tool, content: String(repeating: "b", count: 500), toolCallID: "c"),  // 2
            .user("short follow-up"),                                                      // 3
            ChatMessage(role: .assistant, content: "answer"),                              // 4
        ]
        let (i, cont) = Compactor.cut(history, keepTokens: 100, estimator: est)
        #expect(i == 3)          // stops at the user turn; doesn't reach into the big tool result
        #expect(!cont)
        let (j, cont2) = Compactor.cut(history, keepTokens: 30, estimator: est)
        #expect(j == 4)
        #expect(cont2)
        // Never starts on a tool result, even when forced to summarize something.
        let tiny: [ChatMessage] = [ChatMessage(role: .assistant, content: "", toolCalls: [call]),
                                   ChatMessage(role: .tool, content: "x", toolCallID: "c"), .user("hi")]
        #expect(Compactor.cut(tiny, keepTokens: 10_000, estimator: est).index == 2)
    }

    @Test func planDoesNotGrowTheContextWhenTheSystemPromptDominates() {
        // The session-4 case: a 9k context, a system prompt and tools taking most of it, and a short body
        // (a list, a todo, one 3.6 KB read, a write). The old cut kept the whole body and summarized only the
        // user's message, so the prompt grew (4.4k -> 5.1k tokens).
        var est = TokenEstimator()
        est.bytesPerToken = 3.3
        let budget = ContextBudget(limit: 9000)
        let call = { (id: String, name: String) in ToolCall(id: id, name: name, arguments: #"{"path":"lib/part1.py"}"#) }
        let body: [ChatMessage] = [
            .user(String(repeating: "u", count: 173)),
            ChatMessage(role: .assistant, content: "", toolCalls: [call("a", "list_dir")]),
            ChatMessage(role: .tool, content: String(repeating: "l", count: 151), toolCallID: "a"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call("b", "todo_write")]),
            ChatMessage(role: .tool, content: "ok", toolCallID: "b"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call("c", "read_file")]),
            ChatMessage(role: .tool, content: String(repeating: "r", count: 3612), toolCallID: "c"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call("d", "write_file")]),
            ChatMessage(role: .tool, content: "Appended.", toolCallID: "d"),
        ]
        let system = String(repeating: "s", count: 9500)          // system prompt + tool schemas, about 2.9k tokens
        let before = est.tokens([.system(system)] + body)
        #expect(before > budget.compactThreshold)
        let plan = Compactor.plan(body: body, baseSystem: system, facts: nil, previousSummaryBytes: 0, tools: [],
                                  budget: budget, estimator: est)
        #expect(plan.index > 1)                                    // summarizes more than the opening message…
        #expect(plan.predictedTokens > before - Compactor.minimumSaving(budget))   // …but still can't save enough

        // With a smaller fixed part the same body is worth compacting, down to the newest step.
        let small = Compactor.plan(body: body, baseSystem: "S", facts: nil, previousSummaryBytes: 0, tools: [],
                                   budget: ContextBudget(limit: 3000, outputReserve: 300), estimator: est)
        #expect(small.index == 7)
        #expect(small.predictedTokens < est.tokens([.system("S")] + body))
    }

    @Test func skipsACompactionThatCannotShrinkThePrompt() async throws {
        let ws = try bigProject()
        let mid = (1...50).map { "let item\($0) = make(\($0)) // a line of text to fill this file up to about 3.5 KB" }
        try Data(mid.joined(separator: "\n").utf8).write(to: ws.root.appending(path: "Mid.swift"))
        // A system prompt that takes most of the budget. After the read, and again after the listing, a summary
        // wouldn't save a tenth of the limit: no summary request; the answered read is trimmed instead (the new
        // one reaches the model whole), and the reply says why, once.
        let turns = [SSE.toolCall("r1", "read_file", #"{"path":"Mid.swift"}"#),
                     SSE.toolCall("r2", "list_dir", "{}"),
                     SSE.content("Done.")]
        let (client, host) = MockServer.client(.init(turns: turns))
        let events = Events()
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 6000, outputReserve: 300))
        await AgentLoop.run(client: client, model: "m", systemPrompt: String(repeating: "s", count: 6600),
                            history: [.user("go")], config: config, workspace: ws) { events.add($0) }
        #expect(events.compactions.isEmpty)
        #expect(events.stop == .completed)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)                                       // no summary request
        let second = try body(bodies[1]), third = try body(bodies[2])
        #expect(text(second.messages.last?["content"]).utf8.count > 3000)   // the new read, sent whole
        #expect(text(third.messages[3]["content"]).utf8.count < 1400)       // then trimmed once answered
        let notes = events.assistants.compactMap(\.meta?.notes).flatMap { $0 }
        #expect(notes.filter { $0.hasPrefix("Didn't compact") }.count == 1)   // noted once, not every turn
    }

    @Test func trimmingLeavesRoomSoTheHistoryStaysPutForTurns() {
        // A session near its limit: each turn reads another ~800-token file.
        let output = (1...60).map { "line \($0): some explanatory text to take up room" }.joined(separator: "\n")
        func pair(_ i: Int) -> [ChatMessage] {
            [ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "c\(i)", name: "read_file", arguments: "{}")]),
             ChatMessage(role: .tool, content: output, toolCallID: "c\(i)")]
        }
        let budget = ContextBudget(limit: 12_000, outputReserve: 500)
        let estimator = TokenEstimator()
        /// Turns whose request changed something an earlier request had sent, trimming with `trim` when over the threshold.
        func historyChanges(gated: Bool, _ trim: ([ChatMessage]) -> [ChatMessage]) -> Int {
            var messages: [ChatMessage] = [.system("sys"), .user("read them all")]
            var sent: [ChatMessage] = []
            var changes = 0
            var gate = Compactor.TrimGate()
            for i in 0..<24 {
                messages += pair(i)
                if estimator.tokens(messages) > budget.compactThreshold, !gated || gate.allows(messages, tools: [], estimator, budget) {
                    let trimmed = trim(messages)
                    if trimmed != messages { messages = trimmed; gate.trimmed(messages, tools: [], estimator, budget) }
                }
                if !sent.isEmpty, Array(messages.prefix(sent.count)) != sent { changes += 1 }
                sent = messages
            }
            return changes
        }
        let everyTime = historyChanges(gated: false) { Compactor.trimAnswered($0, maxToolBytes: 1200) }
        let withRoom = historyChanges(gated: true) { Compactor.trimForHeadroom($0, budget: budget, estimator: estimator, tools: []) }
        #expect(everyTime >= 10)          // the old way: once over the threshold, every turn
        #expect(withRoom >= 1 && withRoom <= 4)   // a few steps, with turns in between that leave the history alone

        // Room left after a trim, newest answered outputs whole; and the same old outputs trimmed the same way later.
        var h: [ChatMessage] = [.system("sys"), .user("go")]
        for i in 0..<14 { h += pair(i) }
        let t = Compactor.trimForHeadroom(h, budget: budget, estimator: estimator, tools: [])
        #expect(estimator.tokens(t) <= Compactor.trimTarget(budget))
        #expect(t.last?.content == output && t[3].content.utf8.count < 1400)   // the unanswered output is whole
        #expect(Compactor.trimForHeadroom(t, budget: budget, estimator: estimator, tools: []) == t)   // nothing more to do
    }

    @Test func trimmingTwiceChangesNothing() {
        let m = [ChatMessage(role: .tool, content: (1...800).map { "line \($0)" }.joined(separator: "\n"), toolCallID: "c")]
        let once = Compactor.trimKept(m, maxToolBytes: 1200)
        #expect(once[0].content.utf8.count < 1400)
        #expect(Compactor.trimKept(once, maxToolBytes: 1200) == once)
    }

    @Test func rejectsARunawayReplyAsASummary() async throws {
        #expect(Compactor.looksLikeSummary("## Summary\n- Read Big.swift (400 values).\n- FILES.md has 4 of 25 lines. Next: read Endpoint.swift."))
        #expect(!Compactor.looksLikeSummary("I've documented the first four files. Let me continue.\n\nLet me check what's in the Endpoints directory:"))
        // In a run: a non-summary reply falls back to the transcript summary (a second, tool-less request).
        let ws = try bigProject()
        let turns = [
            readBig, readBig2,
            SSE.content("I've read it. Let me check the next file:"),                       // not a summary
            SSE.content("## Summary\nThe user asked what Big.swift contains. It was read in full: it defines 400 computed values. Next: answer."),  // fallback
            SSE.content("Done."),
        ]
        let (client, host) = MockServer.client(.init(turns: turns))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Describe Big.swift.")],
                            config: AgentConfig(tools: AllTools.all, context: twoReadBudget),
                            workspace: ws) { events.add($0) }
        #expect(events.compactions.first?.summary.hasPrefix("## Summary") == true)
        let fallback = try body(MockServer.requestBodies(host)[3])
        #expect(fallback.tools == 0)
        // The fallback has no cache to lose: it asks for no thinking, so thinking can't use up its output room.
        #expect(String(decoding: MockServer.requestBodies(host)[3], as: UTF8.self).contains(#""reasoning_effort":"none""#))
        #expect(!String(decoding: MockServer.requestBodies(host)[2], as: UTF8.self).contains("reasoning_effort"))
    }

    @Test func trackedProgressSurvivesCompaction() async throws {
        let ws = try bigProject()
        let turns = [
            SSE.toolCall("t1", "todo_write", #"{"todos":[{"content":"Read Big.swift","status":"in_progress"},{"content":"Write notes","status":"pending"}]}"#),
            SSE.toolCall("w1", "write_file", #"{"path":"notes.md","content":"Big has 400 values\n"}"#),
            readBig, readBig2,                                             // push the context over budget
            SSE.content("## Summary\nWorking through the files listed by the user; details are in the progress section below."),
            SSE.content("Done."),
        ]
        let (client, host) = MockServer.client(.init(turns: turns))
        let events = Events()
        var prior = SessionFacts()
        prior.filesRead = ["README.md"]                  // read in an earlier run
        let config = AgentConfig(tools: AllTools.all, context: twoReadBudget, facts: prior)
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: ws) { events.add($0) }
        let c = try #require(events.compactions.first)
        let f = try #require(c.facts)
        #expect(f.filesRead == ["README.md", "Big.swift", "Big2.swift"])
        #expect(f.filesChanged == ["notes.md": 1])
        #expect(f.todos.map(\.status) == ["in_progress", "pending"])
        // The model sees it, after its own summary.
        let bodies = MockServer.requestBodies(host)
        let system = text(try body(bodies[bodies.count - 1]).messages.first?["content"])
        #expect(system.contains("Files you have already read (3): README.md, Big.swift, Big2.swift"))
        #expect(system.contains("notes.md (1 edit)"))
        #expect(system.contains("- [~] Read Big.swift"))
        #expect(c.modelText.hasPrefix("## Summary"))
    }

    @Test func aTurnCannotReturnMoreThanTheContextHolds() async throws {
        let ws = try bigProject()
        for i in [1, 3] { try FileManager.default.copyItem(at: ws.root.appending(path: "Big.swift"), to: ws.root.appending(path: "Big\(i).swift")) }
        let many = SSE.toolCalls((1...3).map { ("r\($0)", "read_file", #"{"path":"Big\#($0).swift"}"#) })
        let (client, _) = MockServer.client(.init(turns: [many, SSE.content("## Summary\nThe user asked for the Big files; one was read, the others were refused for size."), SSE.content("ok")]))
        final class Box: @unchecked Sendable { let l = NSLock(); var r: [ChatMessage] = []; func add(_ m: ChatMessage) { l.withLock { r.append(m) } } }
        let box = Box()
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 8000, outputReserve: 1000))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("read them")], config: config,
                            workspace: ws) { if case .toolFinished(let m) = $0 { box.add(m) } }
        #expect(box.r.count == 3)
        #expect(!box.r[0].content.hasPrefix("Error"))                     // the first read runs (shortened to fit)
        #expect(box.r[0].content.utf8.count < 8000 * 35 / 100 * 4)
        #expect(box.r.dropFirst().allSatisfy { $0.content.contains("Work in smaller steps") })
    }

    @Test func doesNotRecompactWhenItCannotHelp() {
        // Right after a compaction the body is the continuation and the newest step, and the old summary is in the
        // system prompt: summarizing again would only swap one summary for another, so the planner says no.
        var est = TokenEstimator()
        est.bytesPerToken = 3.3
        let budget = ContextBudget(limit: 3000, outputReserve: 300)
        let oldSummary = "## Summary\n" + String(repeating: "w", count: 2000)
        let body: [ChatMessage] = [
            .user(Compactor.continuationText),
            ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "c", name: "read_file", arguments: "{}")]),
            ChatMessage(role: .tool, content: String(repeating: "r", count: 4000), toolCallID: "c"),
        ]
        let before = est.tokens([.system("S\n\n" + Compaction.systemSection(oldSummary))] + body)
        #expect(before > budget.compactThreshold)
        let plan = Compactor.plan(body: body, baseSystem: "S", facts: nil, previousSummaryBytes: oldSummary.utf8.count,
                                  tools: [], budget: budget, estimator: est)
        #expect(plan.predictedTokens > before - Compactor.minimumSaving(budget))
    }

    @Test func aSeparateSummarizerWritesTheSummary() async throws {
        let ws = try bigProject()
        let (agent, agentHost) = MockServer.client(.init(turns: [readBig, readBig2, SSE.content("Answer from the agent.")]))
        let (sum, sumHost) = MockServer.client(.init(turns: [SSE.content("## Summary\nThe user asked about Big.swift; the summarizer model wrote this summary.")]))
        let events = Events()
        var config = AgentConfig(tools: AllTools.all, context: twoReadBudget)
        config.summarizer = Summarizer(client: sum, model: "fast-local")
        config.summaryThinking = false                                  // Settings: summaries without thinking
        await AgentLoop.run(client: agent, model: "slow-remote", systemPrompt: "S", history: [.user("Describe Big.swift.")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(events.compactions.first?.summary.contains("summarizer model") == true)
        #expect(MockServer.requestBodies(sumHost).count == 1)
        #expect(String(decoding: MockServer.requestBodies(sumHost)[0], as: UTF8.self).contains("\"model\":\"fast-local\""))
        #expect(String(decoding: MockServer.requestBodies(sumHost)[0], as: UTF8.self).contains(#""reasoning_effort":"none""#))
        #expect(MockServer.requestBodies(agentHost).count == 3)          // the agent never saw the summary request
        #expect(events.stop == .completed)
    }

    @Test func compactNowSizesTheSummaryFromTheContext() async throws {
        let long = String(repeating: "The project has many small modules, each with a class. ", count: 200)   // ~11 KB
        let history: [ChatMessage] = [.user("Describe the project."), ChatMessage(role: .assistant, content: long)]
        let summary = SSE.content("## Summary\nThe user asked for a description of the project; it is small. Nothing else happened.")
        for (limit, expected) in [(nil, 1500), (Optional(12_000), 4000), (Optional(1_000), 1500)] as [(Int?, Int)] {
            let (client, host) = MockServer.client(.init(turns: [summary]))
            let outcome = await Compactor.compactAll(client: client, model: "m", systemPrompt: "S", history: history, tools: [],
                                                     limits: TurnLimits(maxTokens: 1500), contextLimit: limit)
            #expect(outcome.compaction != nil)
            #expect(String(decoding: MockServer.requestBodies(host)[0], as: UTF8.self).contains("\"max_tokens\":\(expected)"))
        }
    }

    @Test func compactNowSkipsWhenASummaryCantShrinkThePrompt() async throws {
        // Seen: /compact on a two-message chat went from about 1k to 2k tokens.
        let history: [ChatMessage] = [.user("Say hi."), ChatMessage(role: .assistant, content: "Hi!")]
        let (client, host) = MockServer.client(.init(turns: [SSE.content("## Summary\nThe user said hi.")]))
        let outcome = await Compactor.compactAll(client: client, model: "m", systemPrompt: "S", history: history, tools: [],
                                                 limits: TurnLimits(maxTokens: 1500))
        guard case .noSaving(let before, let after, measured: false) = outcome else { Issue.record("\(outcome)"); return }
        #expect(after >= before)
        #expect(MockServer.requestBodies(host).isEmpty)          // predicted: no summary request
        #expect(outcome.explanation?.contains("Nothing to gain yet") == true)
    }

    @Test func compactNowDropsASummaryLongerThanWhatItReplaces() async throws {
        let history: [ChatMessage] = [.user("Describe it."), ChatMessage(role: .assistant, content: String(repeating: "word ", count: 1600))]
        // Long and varied (a repeated sentence would trip the turn's repetition check): ~25 KB.
        let rambling = "## Summary\n" + (0..<500).map { "Item \($0): part\($0).py declares C\($0 * 7919 % 1000) and helper_\($0)." }
            .joined(separator: "\n")
        let (client, host) = MockServer.client(.init(turns: [SSE.content(rambling)]))
        let outcome = await Compactor.compactAll(client: client, model: "m", systemPrompt: "S", history: history, tools: [],
                                                 limits: TurnLimits(maxTokens: 1500))
        guard case .noSaving(let before, let after, measured: true) = outcome else { Issue.record("\(outcome)"); return }
        #expect(after > before)
        #expect(MockServer.requestBodies(host).count == 1)
        #expect(outcome.compaction == nil)
    }

    @Test func compactNowCountsTheNewSummaryInPlaceOfTheOldOne() async throws {
        // The new summary replaces the earlier one in the system prompt; it used to be counted on top of it.
        let base = "SYSTEM PROMPT"
        let old = String(repeating: "Earlier summary text. ", count: 400)                  // ~9 KB
        let history: [ChatMessage] = [.user("Next step?"), ChatMessage(role: .assistant, content: String(repeating: "detail ", count: 900))]
        let (client, _) = MockServer.client(.init(turns: [SSE.content("## Summary\nThe user asked what to do next; the earlier work is done and the next step is to run the tests.")]))
        let outcome = await Compactor.compactAll(client: client, model: "m", systemPrompt: SessionRun.withSummary(base, old),
                                                 baseSystemPrompt: base, history: history, tools: [], limits: TurnLimits(maxTokens: 1500))
        let c = try #require(outcome.compaction)
        #expect(c.tokensAfter == TokenEstimator().tokens([.system(base + "\n\n" + Compaction.systemSection(c.modelText))], tools: []))
        #expect(c.tokensAfter < c.tokensBefore / 4)
    }

    @Test func estimatorCalibrates() {
        var e = TokenEstimator()
        let msgs = [ChatMessage.user(String(repeating: "word ", count: 2000))]
        let bytes = TokenEstimator.bytes(msgs)
        e.calibrate(bytes: bytes, promptTokens: bytes / 5)
        #expect(abs(e.bytesPerToken - 5) < 0.1)
        #expect(abs(e.tokens(msgs) - bytes / 5) < 5)
        e.calibrate(bytes: 10, promptTokens: 5)       // too small to trust
        #expect(abs(e.bytesPerToken - 5) < 0.1)
    }

    @Test func sessionHistoryStartsAfterTheActiveCompaction() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-compact-\(UUID().uuidString.prefix(6))")
        let store = SessionStore(root: dir)
        let header = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(header)
        let u1 = ChatMessage.user("first task"), a1 = ChatMessage(role: .assistant, content: "did it")
        let u2 = ChatMessage.user("second task")
        for m in [u1, a1, u2] { try await store.append(.message(m), to: header.id) }
        try await store.append(.compaction(Compaction(summary: "S1", lastSummarizedID: a1.id, continuation: nil,
                                                      tokensBefore: 900, tokensAfter: 100)), to: header.id)
        var s = try #require(try await store.load(header.id))
        #expect(s.modelHistory.summary == "S1")
        #expect(s.modelHistory.messages.map(\.content) == ["second task"])

        // A compaction whose boundary was rewound away no longer applies.
        try await store.append(.retract(a1.id), to: header.id)
        s = try #require(try await store.load(header.id))
        #expect(s.activeCompaction == nil)
        #expect(s.modelHistory.messages.count == 2)
    }

    @Test func compactNowNeedsSomethingNewToSummarize() {
        let u = ChatMessage.user("Read the files."), a = ChatMessage(role: .assistant, content: "Done.")
        var session = Session(header: SessionHeader(endpointID: UUID(), model: "m"), messages: [u, a], model: "m")
        #expect(SessionRun.hasNewMessagesToCompact(session))
        // Right after /compact everything is summarized; the continuation line it leaves doesn't count.
        session.compactions.append(Compaction(summary: "## Summary\nRead the files.", lastSummarizedID: a.id,
                                              continuation: Compactor.continuationText, tokensBefore: 100, tokensAfter: 20))
        #expect(!SessionRun.hasNewMessagesToCompact(session))
        session.messages.append(.user("And one more."))
        #expect(SessionRun.hasNewMessagesToCompact(session))
    }
}

@Suite struct TodoTests {
    @Test func parsesLenientTodoLists() throws {
        let args = try ToolArguments(json: #"{"todos":[{"content":"Read code","status":"done"},{"content":"Fix bug","status":"in progress"},{"content":"Run tests"}]}"#)
        let items = try TodoWriteTool.items(from: args)
        #expect(items.map(\.status) == [.completed, .inProgress, .pending])
        #expect(TodoWriteTool().summary(args) == "Todo 1/3: Fix bug")
        let stringified = try ToolArguments(json: #"{"todos":"[{\"content\":\"A\",\"status\":\"pending\"}]"}"#)
        #expect(try TodoWriteTool.items(from: stringified).count == 1)
        #expect(throws: ToolFailure.self) { try TodoWriteTool.items(from: ToolArguments(json: #"{"todos":[{"status":"pending"}]}"#)) }
    }

    @Test func bashSavesFullOutputOnlyWhenTruncated() async throws {
        let ws = try makeProject()
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-out-\(UUID().uuidString.prefix(6))")
        var ctx = ToolContext(workspace: ws, maxOutputBytes: 2000)
        ctx.fullOutputURL = dir.appending(path: "big.txt")
        let big = try await BashTool().run(ToolArguments(["command": "seq 1 5000"]), context: ctx)
        let path = try #require(big.fullOutputPath)
        #expect(String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self).contains("\n4999\n"))
        ctx.fullOutputURL = dir.appending(path: "small.txt")
        let small = try await BashTool().run(ToolArguments(["command": "echo hi"]), context: ctx)
        #expect(small.fullOutputPath == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "small.txt").path))
    }
}

/// Summaries are billed requests too: each gets a cost entry (COST_TRACKING_DESIGN.md).
@Suite struct SummaryCostTests {
    @Test func aCompactionsRequestsAreCostEntries() async throws {
        let ws = try bigProject()
        let turns = [
            readBig, readBig2,
            SSE.content("I've read it. Let me check the next file:"),                       // not a summary: an attempt
            SSE.content("## Summary\nThe user asked what Big.swift contains. It was read in full: it defines 400 computed values. Next: answer."),
            SSE.content("Done."),
        ]
        let (client, _) = MockServer.client(.init(turns: turns))
        let events = Events()
        var config = AgentConfig(tools: AllTools.all, context: twoReadBudget)
        let run = UUID()
        config.costScope = CostScope(run: run, agent: "main")
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Describe Big.swift.")],
                            config: config, workspace: ws) { events.add($0) }
        let costs = events.costs
        #expect(costs.map(\.purpose) == [.reply, .reply, .summaryAttempt, .summary, .reply])
        #expect(costs.allSatisfy { $0.run == run && $0.agent == "main" && $0.tokens?.promptTokens == 100 })
    }
}
