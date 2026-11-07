import Foundation
import Testing
@testable import AgentCore

/// Bug hunt 2026-11-02, area B: the agent loop, its hooks, compaction and the session's record of them.

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    private var approvalsMade = 0
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    func approved() { lock.withLock { approvalsMade += 1 } }
    var approvals: Int { lock.withLock { approvalsMade } }
    var all: [AgentEvent] { lock.withLock { items } }
    var assistants: [ChatMessage] { all.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var injected: [ChatMessage] { all.compactMap { if case .injected(let m) = $0 { m } else { nil } } }
    var compactions: [Compaction] { all.compactMap { if case .compacted(let c) = $0 { c } else { nil } } }
    var runs: [AgentRunRecord] { all.compactMap { if case .runEnded(let r) = $0 { r } else { nil } } }
    var stop: AgentStop? { all.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last }

    /// The session as the app or CLI would store it from these events, after `history`.
    func session(after history: [ChatMessage]) -> Session {
        var messages = history
        for e in all {
            switch e {
            case .assistant(let m), .toolFinished(let m), .injected(let m): messages.append(m)
            default: break
            }
        }
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: "/tmp")
        return Session(header: header, messages: messages, model: "m", compactions: compactions)
    }
}

private func requestMessages(_ body: Data) throws -> [(role: String, content: String)] {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body), case .array(let ms)? = o["messages"] else { return [] }
    return ms.compactMap { m in
        guard case .object(let d) = m, case .string(let role)? = d["role"] else { return nil }
        if case .string(let c)? = d["content"] { return (role, c) }
        return (role, "")
    }
}

// MARK: 24. Hooks that could block the loop

@Suite struct BugHuntHookTests {
    @Test func aHookThatIgnoresALargeStdinStillTimesOutPromptly() async throws {
        let ws = try makeProject()
        let payload = String(repeating: "x", count: 200_000)        // more than the pipe holds
        let started = Date()
        let r = await Hooks.execute("sleep 30", stdin: payload, cwd: ws.root, timeout: 0.5)
        #expect(r.timedOut)
        #expect(Date().timeIntervalSince(started) < 8, "took \(Date().timeIntervalSince(started))s")
    }

    @Test func aChildTheHookLeftBehindDoesNotHoldIt() async throws {
        let ws = try makeProject()
        let started = Date()
        let r = await Hooks.execute("echo ok; sleep 100 &", stdin: "{}", cwd: ws.root, timeout: 10)
        #expect(!r.timedOut)
        #expect(r.status == 0)
        #expect(r.stdout == "ok\n")
        #expect(Date().timeIntervalSince(started) < 8, "took \(Date().timeIntervalSince(started))s")
    }

    @Test func stopHooksDoNotRunInsideASubagent() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Find greet","prompt":"Where is greet()?","agent":"explore"}"#),
            SSE.content("greet() is at src/main.swift:12."),                   // the subagent's report
            SSE.content("It's at src/main.swift:12."),                         // the main agent
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto))
        config.subagents = SubagentSetup()
        config.sandbox = nil
        config.hooks = Hooks(matchers: [.stop: [HookMatcher(matcher: nil, hooks: [HookCommand(type: "command", command: "echo stop >> stops.txt", timeout: 10)])]],
                             sessionID: "s", cwd: ws.root)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is greet?")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        let stops = try String(contentsOf: ws.root.appending(path: "stops.txt"), encoding: .utf8)
        #expect(stops == "stop\n")                                              // once: the main agent's end, not the subagent's
    }
}

// MARK: 25. "Always allow" shared across the run; end-of-run checks under the run's current policy

@Suite struct BugHuntSharedRulesTests {
    @Test func alwaysAllowFromASubagentsCardHoldsForTheParent() async throws {
        let ws = try makeProject()
        let runner = AgentDefinition(name: "runner", description: "Runs commands.", instructions: "Run the command you're given.",
                                     tools: ["bash"])
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Run it","prompt":"Run echo hi","agent":"runner"}"#),   // main
            SSE.toolCall("call_s1", "bash", #"{"command":"echo hi"}"#),                                           // subagent
            SSE.content("It printed hi."),                                                                        // subagent
            SSE.toolCall("call_2", "bash", #"{"command":"echo hi"}"#),                                            // main, the same command
            SSE.content("Done."),
        ]))
        let events = Events()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .ask), approve: { r in
            events.approved()
            return r.suggestedRule.map { .allowAlways($0) } ?? .allow
        })
        config.subagents = SubagentSetup(agents: [runner])
        config.sandbox = nil
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Run echo hi")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        #expect(events.results.count == 2)
        #expect(events.results[1].toolResult?.isError == false, "\(events.results[1].content)")
        #expect(events.approvals == 1)        // the card in the subagent's run answered "always allow"; the parent isn't asked again
    }

    @Test func rulesReachSubagentsStartedLater() {
        let mode = RunMode(policy: PermissionPolicy(mode: .ask), sandbox: nil)
        mode.add(.command("swift test"))
        var parent = AgentConfig(tools: [], policy: PermissionPolicy(mode: .ask))
        parent.policy.rules = [.tool("edit_file")]
        let applied = mode.applied(to: parent)
        #expect(applied.policy.rules == [.tool("edit_file"), .command("swift test")])
        // A mode switch keeps the rules gathered so far.
        mode.set(policy: PermissionPolicy(mode: .fullAuto), sandbox: nil)
        var policy = PermissionPolicy(mode: .ask)
        mode.syncRules(into: &policy)
        #expect(policy.rules == [.command("swift test")])
    }

    @Test func theProjectsSuiteRunsUnderTheModeAnApprovedPlanLeft() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("p1", "present_plan", ##"{"plan":"# Rename\n1. Change A demo project. to A renamed project. in README.md"}"##),
            SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#),
            SSE.toolCall("e1", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"A renamed project."}"#),
            SSE.content("Done."),
        ]))
        let events = Events()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan), approve: { _ in .deny(feedback: nil) })
        config.outputDirectory = ws.root.appending(path: ".outputs")
        config.presentPlan = { _ in .approve(.fullAuto) }
        config.testSuite = "touch suite-ran.txt"          // not one of Plan mode's read-only commands
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("rename the greeting")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        let record = try #require(events.runs.first)
        // Plan mode would refuse the suite as "not read-only"; the run ended in Full Auto, so it runs and is recorded.
        #expect(record.signals?.suite?.exitCode == 0, "\(String(describing: record.signals?.suite))")
        #expect(FileManager.default.fileExists(atPath: ws.root.appending(path: "suite-ran.txt").path))
    }
}

// MARK: 16. Compaction keeps the results the model hasn't read yet whole

/// A project with four big files, each read capped at the default 16 KB (about 4k tokens).
private func bigProject() throws -> Workspace {
    let ws = try makeProject()
    for i in 1...4 {
        let big = (1...400).map { "let value\($0) = compute(\($0)) // file \(i), some explanatory text to take up room" }.joined(separator: "\n")
        try Data(big.utf8).write(to: ws.root.appending(path: "Big\(i).swift"))
    }
    return ws
}

private func readBig(_ i: Int) -> [Data] { SSE.toolCall("r\(i)", "read_file", #"{"path":"Big\#(i).swift"}"#) }

@Suite struct BugHuntCompactionTests {
    @Test func theNewestGroupIsSizedWholeWhenPlanningTheCut() {
        var est = TokenEstimator()
        est.bytesPerToken = 1
        func group(_ i: Int) -> [ChatMessage] {
            [ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "c\(i)", name: "read_file", arguments: "{}")]),
             ChatMessage(role: .tool, content: String(repeating: "b", count: 5000), toolCallID: "c\(i)")]
        }
        let history: [ChatMessage] = [.user("go")] + group(1) + group(2)
        // Room for an answered group trimmed to 4 KB plus the unread one whole (about 9.3k), but not for two trimmed
        // groups measured the old way (8.4k) if the newest were trimmed too.
        #expect(Compactor.cut(history, keepTokens: 9_600, estimator: est).index == 1)
        #expect(Compactor.cut(history, keepTokens: 9_000, estimator: est).index == 3)      // only the unread group fits whole
    }

    @Test func compactionSendsTheUnreadResultWholeAndTheStoreRebuildsTheSamePrompt() async throws {
        let ws = try bigProject()
        let user = ChatMessage.user("Describe the Big files.")
        let (client, host) = MockServer.client(.init(turns: [
            readBig(1), readBig(2), readBig(3), readBig(4),                 // the fourth read passes the threshold
            SSE.content("## Summary\nThe user asked about the Big files; Big1 and Big2 define 400 values each. Next: read on."),
            SSE.content("They each define 400 values."),
        ]))
        let events = Events()
        // Each read is about 4.8k tokens (3.3 bytes a token), 1.2k trimmed. The threshold (19.7k) passes after the fourth
        // read; the kept part (6.8k) holds the fourth whole and the third trimmed, not the second.
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 34_000))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "BASE PROMPT", history: [user], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        let c = try #require(events.compactions.first)
        let results = events.results
        #expect(results.count == 4)
        #expect(results[3].content.utf8.count > 12_000)
        #expect(c.lastSummarizedID == results[1].id)                    // summarized through the second read
        #expect(c.lastKeptID == results[2].id)                          // the third was kept and trimmed; the fourth kept whole
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 6)
        let after = try requestMessages(bodies[5])
        #expect(after.map(\.role) == ["system", "user", "assistant", "tool", "assistant", "tool"])
        #expect(after[3].content.utf8.count < 4300 && after[3].content.contains("Trimmed when the session was compacted"))
        #expect(after[5].content == results[3].content)                 // whole: the model hadn't read it yet
        // The next run rebuilds the prompt from the session: the same messages, trimmed the same way.
        // (The session also holds the answer to that request, so all but its last message are compared.)
        let rebuilt = AgentLoop.sendable(events.session(after: [user]).modelHistory.messages).dropLast()
        #expect(rebuilt.map { "\($0.role.rawValue): \($0.content)" } == after.dropFirst().map { "\($0.role): \($0.content)" })
    }

    @Test func resultsThatOverflowOnTheirOwnAreCutOnceNotReadAgainAndAgain() async throws {
        let ws = try bigProject()
        let overflow = Data(#"{"error":"This model's maximum context length is 2000 tokens; the prompt is too long."}"#.utf8)
        let (client, host) = MockServer.client(.init(turns: [
            readBig(1),
            [overflow],                                                      // the server rejects the prompt
            SSE.toolCall("r1b", "read_file", #"{"path":"Big1.swift"}"#),     // the model asks for the cut file again
            SSE.content("Big1 defines 400 values."),
        ], turnStatuses: [1: 400]))
        let events = Events()
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 1_000_000))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Describe Big1.swift")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        // One unread result is all there is: a summary can't make room, and nothing answered can be trimmed, so the
        // result is cut as a last resort, with the reason, and the same read again is refused instead of overflowing again.
        #expect(events.compactions.isEmpty)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 4)
        let retried = try requestMessages(bodies[2])
        #expect(retried.last?.content.utf8.count ?? 0 < 1600)
        #expect(retried.last?.content.contains(Compactor.oversizeHint) == true)
        #expect(events.results.count == 2)
        #expect(events.results[1].content.hasPrefix("You already called read_file"))
    }
}

// MARK: 23. Nudges are stored, taken-back replies aren't sent again, boundaries are stored messages

@Suite struct BugHuntNudgeStoreTests {
    @Test func aNudgedReplyIsStoredButNotSentAgainAndTheNudgeIsStored() async throws {
        let ws = try makeProject()
        let user = ChatMessage.user("What is this project?")
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("<tool_call|>"),                                     // a broken call: taken back, asked again
            SSE.content("It is a demo project."),
        ]))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "SYSTEM", history: [user],
                            config: AgentConfig(tools: ReadTools.all), workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        #expect(events.assistants.count == 3)
        #expect(events.assistants[1].meta?.unsent == true)                   // stored and shown, never sent again
        #expect(events.assistants[2].meta?.unsent == nil)
        let nudge = try #require(events.injected.first)
        #expect(nudge.contextNote == true && nudge.content == AgentLoop.markerOnlyNudge)
        // The next run rebuilds exactly what the last request sent: …, tool result, nudge; not two replies in a row.
        let sent = try requestMessages(MockServer.requestBodies(host)[2]).dropFirst()
        let rebuilt = AgentLoop.sendable(events.session(after: [user]).modelHistory.messages).dropLast()
        #expect(rebuilt.map { "\($0.role.rawValue): \($0.content)" } == sent.map { "\($0.role): \($0.content)" })
        #expect(rebuilt.map(\.role) == [.user, .assistant, .tool, .user])
    }

    @Test func aCompactionRightAfterANudgeHasABoundaryTheStoreKnows() async throws {
        let ws = try bigProject()
        let user = ChatMessage.user("Describe the Big files.")
        let (client, host) = MockServer.client(.init(turns: [
            readBig(1),
            SSE.content("<tool_call|>"),                                     // taken back; the nudge follows the read
            readBig(2),                                                      // over the threshold: compaction before the next turn
            SSE.content("## Summary\nThe user asked about the Big files; Big1 defines 400 values. Next: read on."),
            SSE.content("They each define 400 values."),
        ]))
        let events = Events()
        // Keeps less than one read (4k of 4.8k tokens): the cut lands right after the nudge, which used to be its boundary.
        let config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 20_000))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "BASE PROMPT", history: [user], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.stop == .completed)
        let c = try #require(events.compactions.first)
        let session = events.session(after: [user])
        #expect(session.messages.contains { $0.id == c.lastSummarizedID })  // a message the session stores: the nudge
        #expect(session.activeCompaction == c)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 5)
        let sent = try requestMessages(bodies[4]).dropFirst()
        #expect(sent.map(\.role) == ["user", "assistant", "tool"])          // continuation, the second read whole
        let rebuilt = AgentLoop.sendable(session.modelHistory.messages).dropLast()
        #expect(rebuilt.map { "\($0.role.rawValue): \($0.content)" } == sent.map { "\($0.role): \($0.content)" })
    }

    @Test func aReplyStoppedForRepeatingItselfIsNotSentAgain() {
        var reply = ChatMessage(role: .assistant, content: "the same thing over and over")
        reply.meta = TurnMeta(requestedModel: "m", stopReason: .repetition, duration: 1)
        reply.meta?.unsent = true
        let history: [ChatMessage] = [.user("go"), reply, FrozenSystemPrompt.noteMessage("Your last reply was stopped…"),
                                      ChatMessage(role: .assistant, content: "The next step.")]
        #expect(AgentLoop.sendable(history).map(\.content) == ["go", "Your last reply was stopped…", "The next step."])
    }
}
