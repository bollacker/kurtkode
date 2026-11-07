import Foundation
import Testing
@testable import AgentCore

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var assistants: [ChatMessage] { all.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
}

private func requestJSON(_ body: Data) throws -> [String: JSONValue] {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body) else { return [:] }
    return o
}

private func toolNames(_ request: [String: JSONValue]) -> [String] {
    guard case .array(let tools)? = request["tools"] else { return [] }
    return tools.compactMap { t in
        guard case .object(let o) = t, case .object(let f)? = o["function"], case .string(let n)? = f["name"] else { return nil }
        return n
    }
}

private func messages(_ request: [String: JSONValue]) -> [[String: JSONValue]] {
    guard case .array(let ms)? = request["messages"] else { return [] }
    return ms.compactMap { if case .object(let m) = $0 { m } else { nil } }
}

private let taskCall = #"{"description":"Find greet","prompt":"Where is greet() defined? Cite file and line.","agent":"explore"}"#

@Suite struct SubagentTests {
    @Test func delegatesAndGetsOnlyTheReport() async throws {
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", taskCall),                                   // main agent
            SSE.toolCall("call_s1", "grep", #"{"pattern":"greet"}"#),                   // subagent
            SSE.content("greet() is defined at src/main.swift:12."),                    // subagent's report
            SSE.content("It's at src/main.swift:12."),                                  // main agent
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }

        #expect(events.assistants.map(\.content) == ["", "It's at src/main.swift:12."])   // the subagent's turns aren't the main agent's
        let result = try #require(events.results.first)
        #expect(result.content.hasPrefix("greet() is defined at src/main.swift:12.\n\n[This is the explore subagent's final report."))
        let display = try #require(result.toolResult?.display)
        #expect(display.hasPrefix("explore subagent on m · 1 tool calls\n→ "))

        let bodies = MockServer.requestBodies(host).map { try? requestJSON($0) }
        #expect(toolNames(bodies[0]!).contains("task"))
        let sub = try #require(bodies[1])
        #expect(toolNames(sub).sorted() == ["glob", "grep", "list_dir", "read_file"])        // explore: read-only, no task
        let subMessages = messages(sub)
        guard case .string(let system)? = subMessages.first?["content"] else { Issue.record("no system prompt"); return }
        #expect(system.contains(SubagentSetup.preamble) && system.contains("Your role (explore)"))
        #expect(subMessages[1]["content"] == "Where is greet() defined? Cite file and line.")
        #expect(subMessages.count == 2)                                                    // not the main conversation
    }

    @Test func recordsTheRunAsAChildSession() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-sub-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", taskCall),
            SSE.toolCall("call_s1", "grep", #"{"pattern":"greet"}"#),
            SSE.content("greet() is defined at src/main.swift:12."),
            SSE.content("It's at src/main.swift:12."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        let parentWire = store.wireDirectory(for: parent)
        config.wireLog = WireLog(directory: parentWire)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }

        // The task result links the run; the run is a session in the parent's .subagents folder.
        let runID = try #require(events.results.first?.toolResult?.subagentRun)
        let runs = await store.subagentRuns(of: parent)
        #expect(runs.map(\.header.id) == [runID])
        let run = try #require(runs.first)
        #expect(run.header.parent == parent.id && run.header.parentCallID == "call_1" && run.header.agent == "explore")
        #expect(run.title == "Find greet")
        #expect(run.permissionMode == .fullAuto)
        #expect(run.systemPrompt.map { $0.contains(SubagentSetup.preamble) && $0.contains("Your role (explore)") } == true)
        #expect(run.messages.map(\.role) == [.user, .assistant, .tool, .assistant])
        #expect(run.messages.first?.content == "Where is greet() defined? Cite file and line.")
        let end = try #require(run.subagentEnd)
        #expect(end.stop == "completed" && end.steps == 2 && end.toolCalls == 1)
        #expect(end.report == "greet() is defined at src/main.swift:12.")
        #expect(FileManager.default.fileExists(atPath: store.subagentDirectory(for: parent).appending(path: "\(runID.uuidString).jsonl").path))

        // Its requests are in its own wire log and context index, none in the parent's.
        let runWire = store.wireDirectory(for: run.header)
        let runReplies = run.messages.filter { $0.role == .assistant }.map(\.id)
        #expect(runReplies.allSatisfy { WireLog.read(runWire, replyID: $0) != nil })
        #expect(runReplies.allSatisfy { WireLog.read(parentWire, replyID: $0) == nil })
        #expect(Set(WireLog.contexts(runWire).map(\.replyID)) == Set(runReplies))
        let parentReplies = Set(events.assistants.map(\.id))
        #expect(Set(WireLog.contexts(parentWire).map(\.replyID)) == parentReplies)

        // A run is never listed as a session of its own, and loads by its parent.
        #expect(try await store.list().map(\.id) == [parent.id])
        #expect(await store.subagentRun(runID, of: parent)?.subagentEnd?.steps == 2)
    }

    @Test func aRunWithoutARecorderWritesNoWire() async throws {
        let ws = try makeProject()
        let wire = FileManager.default.temporaryDirectory.appending(path: "kk-wire-\(UUID().uuidString.prefix(6))")
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", taskCall), SSE.content("Found it."), SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.wireLog = WireLog(directory: wire)
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(events.results.first?.toolResult?.subagentRun == nil)
        #expect(WireLog.contexts(wire).count == 2)                 // the main agent's two requests only
    }

    @Test func stopsOneSubagentWhileItWaitsForApproval() async throws {
        let ws = try makeProject()
        let generalTask = #"{"description":"Write notes","prompt":"Write NOTES.md saying hi.","agent":"general"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", generalTask),                                   // main agent
            SSE.toolCall("call_s1", "write_file", #"{"path":"NOTES.md","content":"hi\n"}"#), // subagent: needs approval
            SSE.content("Carried on without it."),                                          // main agent again
        ]))
        let control = SubagentControl()
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .ask))
        var setup = SubagentSetup()
        setup.control = control
        config.subagents = setup
        // Like the app: an approval waits until answered, and a stop answers it "deny".
        config.approve = { _ in
            await withTaskCancellationHandler {
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
                return .deny(feedback: nil)
            } onCancel: {}
        }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Have a subagent write notes.")],
                            config: config, workspace: ws) { e in
            events.add(e)
            if case .subagentProgress(let p) = e, p.waitingForApproval { control.stop(p.id) }   // the user's Stop
        }
        let all = events.all
        let started = all.compactMap { if case .subagentStarted(let i) = $0 { i } else { nil } }
        #expect(started.map(\.agent) == ["general"] && started.first?.callID == "call_1")
        #expect(all.contains { if case .subagentProgress(let p) = $0 { p.waitingForApproval } else { false } })
        let ended = all.compactMap { if case .subagentFinished(_, let end) = $0 { end } else { nil } }
        #expect(ended.map(\.stop) == ["cancelled"])                  // stopped, not "denied"
        let result = try #require(events.results.first)
        #expect(result.content.hasPrefix("[The user stopped this subagent before it finished."))
        #expect(events.assistants.last?.content == "Carried on without it.")   // the main agent went on
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "NOTES.md").path))
        #expect(control.running.isEmpty)
    }

    @Test func runsOnItsOwnModel() async throws {
        let ws = try makeProject()
        let (mainClient, mainHost) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", taskCall), SSE.content("Done."),
        ]))
        let (subClient, subHost) = MockServer.client(.init(turns: [SSE.content("Found it.", model: "small-model")]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: subClient, model: "small-model") })
        let events = Events()
        await AgentLoop.run(client: mainClient, model: "big-model", systemPrompt: nil, history: [.user("Go")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(MockServer.requestBodies(mainHost).count == 2)
        let sub = try requestJSON(try #require(MockServer.requestBodies(subHost).first))
        #expect(sub["model"] == "small-model")
        #expect(events.results.first?.content.hasPrefix("Found it.") == true)
    }

    @Test func planModeKeepsSubagentsReadOnly() async throws {
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Refactor","prompt":"Rename greet","agent":"general"}"#),
            SSE.content("I can't edit in this mode."),
            SSE.content("OK."),
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan))
        config.subagents = SubagentSetup()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Go")],
                            config: config, workspace: ws) { _ in }
        let sub = try requestJSON(MockServer.requestBodies(host)[1])
        // What Plan mode offers: the readers, and bash (read-only commands only) with its background tools.
        #expect(Set(toolNames(sub)) == ["read_file", "list_dir", "glob", "grep", "todo_write", "bash", "bash_output", "kill_shell"])
    }

    @Test func loadsCustomAgents() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-agents-\(UUID().uuidString.prefix(8))")
        let project = root.appending(path: "p"), home = root.appending(path: "h")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write(project.appending(path: ".claude/agents/reviewer.md"),
                  "---\nname: reviewer\ndescription: Reviews diffs for bugs\ntools: read_file, grep, mcp\nmodel: Openrouter|qwen/qwen3-coder\n---\nReview carefully.\n")
        try write(home.appending(path: ".kurtkode/agents/explore.md"), "Can't replace the built-in.\n")
        try write(home.appending(path: ".kurtkode/agents/tester.md"), "---\nmodel: inherit\n---\nRun the tests.\n")
        let agents = AgentDefinitions.load(workspace: project, home: home)
        #expect(agents.map(\.name) == ["explore", "general", "reviewer", "tester"])
        let reviewer = agents[2]
        #expect(reviewer.tools == ["read_file", "grep", "mcp"])
        #expect(reviewer.model == "Openrouter|qwen/qwen3-coder")
        #expect(reviewer.instructions == "Review carefully.")
        #expect(agents[3].model == nil)
        #expect(agents[0].instructions == AgentDefinition.explore.instructions)
    }
}

@Suite struct SubagentSummaryTests {
    private func run(ended: Bool) -> Session {
        var header = SessionHeader(endpointID: UUID(), model: "small", workspace: "/p")
        header.parent = UUID()
        header.parentCallID = "call_9"
        header.agent = "explore"
        header.createdAt = Date(timeIntervalSinceNow: -20)
        let call = ToolCall(id: "c1", name: "grep", arguments: #"{"pattern":"x"}"#)
        var reply = ChatMessage(role: .assistant, content: "", toolCalls: [call])
        reply.meta = TurnMeta(requestedModel: "small", stopReason: .completed, duration: 1)
        reply.meta?.usage = Usage(promptTokens: 300, completionTokens: 20)
        var result = ChatMessage(role: .tool, content: "Error: bad pattern", toolCallID: "c1")
        result.toolResult = ToolResultInfo(toolName: "grep", isError: true, truncated: false, duration: 0.1)
        var final = ChatMessage(role: .assistant, content: "Nothing found.")
        final.meta = TurnMeta(requestedModel: "small", stopReason: .completed, duration: 1)
        final.meta?.usage = Usage(promptTokens: 350, completionTokens: 10)
        var s = Session(header: header, messages: [.user("find x"), reply, result, final], title: "Find x", model: "small")
        if ended {
            s.subagentEnd = SubagentEnd(stop: "completed", steps: 2, toolCalls: 1, promptTokens: 650, completionTokens: 30,
                                        seconds: 12, report: "Nothing found.")
        }
        return s
    }

    @Test func summarizesARunningAndAFinishedRun() {
        let live = SubagentRunSummary(run(ended: false))
        #expect(live.isRunning && live.state == "running")
        #expect(live.steps == 2 && live.toolCalls == 1 && live.promptTokens == 650 && live.completionTokens == 30)
        #expect(live.seconds >= 19 && live.report == nil)
        #expect(live.flags["error"] == 1)
        #expect(live.agent == "explore" && live.title == "Find x" && live.callID == "call_9")

        let done = SubagentRunSummary(run(ended: true))
        #expect(!done.isRunning && done.state == "completed" && done.seconds == 12 && done.report == "Nothing found.")

        var stats = SessionStats(Session(header: SessionHeader(endpointID: UUID(), model: "m"), messages: [], model: "m"))
        stats.add(subagents: [run(ended: true), run(ended: false)])
        #expect(stats.subagents == 2 && stats.subagentToolCalls == 2 && stats.subagentPromptTokens == 1300)
        #expect(stats.toolCalls == 0)                                     // the main agent's own counts stay apart
    }
}

@Suite struct ParallelSubagentTests {
    final class Log: @unchecked Sendable {
        let lock = NSLock()
        var items: [(String, Date)] = []          // "start:<agent>", "end:<agent>", "wait:<id>"
        var events: [AgentEvent] = []
        var agents: [UUID: String] = [:]
        func time(_ s: String) -> Date? { lock.withLock { items.first { $0.0 == s }?.1 } }
        var names: [String] { lock.withLock { items.map(\.0) } }
    }

    /// Events from two subagents arrive at once: keep the bookkeeping under one lock.
    private func record(_ log: Log, _ e: AgentEvent) {
        log.lock.withLock {
            log.events.append(e)
            let now = Date()
            switch e {
            case .subagentStarted(let i): log.agents[i.id] = i.agent; log.items.append(("start:" + i.agent, now))
            case .subagentProgress(let p) where p.waitingForSlot: log.items.append(("wait:" + (log.agents[p.id] ?? "?"), now))
            case .subagentFinished(let id, _): log.items.append(("end:" + (log.agents[id] ?? "?"), now))
            default: break
            }
        }
    }

    private func call(_ id: String, _ agent: String, _ what: String) -> (String, String, String) {
        (id, "task", #"{"description":"\#(what)","prompt":"\#(what)","agent":"\#(agent)"}"#)
    }

    @Test func readOnlyRunsOverlapAndResultsKeepCallOrder() async throws {
        let ws = try makeProject()
        let (main, mainHost) = MockServer.client(.init(turns: [
            SSE.toolCalls([call("call_A", "explore", "Find A"), call("call_B", "finder", "Find B")]),
            SSE.content("Both done."),
        ]))
        let slow = { (text: String) in MockServer.Route(chunks: SSE.content(text), delay: 0.15) }
        let (a, _) = MockServer.client(slow("Report A is long enough to take a while."))
        let (b, _) = MockServer.client(slow("Report B."))
        var config = AgentConfig(tools: AllTools.all)
        var setup = SubagentSetup(agents: [.explore, AgentDefinition(name: "finder", description: "finds", instructions: "find",
                                                                     tools: ["grep"])],
                                  resolveModel: { agent, _ in agent.name == "explore" ? SubagentModel(client: a, model: "a") : SubagentModel(client: b, model: "b") })
        setup.slots = { (_: UUID?, _: String) in 4 }
        config.subagents = setup
        let log = Log()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Find A and B")],
                            config: config, workspace: ws) { e in self.record(log, e) }
        // B started before A finished: they ran at the same time.
        let startB = try #require(log.time("start:finder")), endA = try #require(log.time("end:explore"))
        #expect(startB < endA)
        let results = log.lock.withLock { log.events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
        #expect(results.map(\.toolCallID) == ["call_A", "call_B"])
        #expect(results[0].content.hasPrefix("Report A") && results[1].content.hasPrefix("Report B"))
        #expect(results.allSatisfy { $0.toolResult?.notes?.contains { $0.hasPrefix("Ran in parallel") } == true })
        let second = String(decoding: MockServer.requestBodies(mainHost)[1], as: UTF8.self)
        let iA = try #require(second.range(of: "Report A")), iB = try #require(second.range(of: "Report B"))
        #expect(iA.lowerBound < iB.lowerBound)                               // in call order for the model too
    }

    @Test func runsThatWriteGoOneAtATime() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCalls([call("call_A", "general", "Do A"), call("call_B", "general", "Do B")]),
            SSE.content("A done."), SSE.content("B done."),             // one at a time: whichever goes first gets "A done."
            SSE.content("Both done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        let log = Log()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Do A and B")],
                            config: config, workspace: ws) { e in self.record(log, e) }
        #expect(log.names.filter { $0.hasPrefix("wait:") }.count == 1)
        let results = log.lock.withLock { log.events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
        #expect(Set(results.map { String($0.content.prefix(6)) }) == ["A done", "B done"])   // either may go first
        #expect(results.map(\.toolCallID) == ["call_A", "call_B"])
    }

    @Test func aModelWithOneSlotTakesOneRunAtATime() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCalls([call("call_A", "explore", "Find A"), call("call_B", "explore", "Find B")]),
            SSE.content("Found A."), SSE.content("Found B."), SSE.content("Both done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        var setup = SubagentSetup()
        setup.slots = { (_: UUID?, model: String) in model == "m" ? 1 : 4 }
        config.subagents = setup
        let log = Log()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("Find A and B")],
                            config: config, workspace: ws) { e in self.record(log, e) }
        #expect(log.names.filter { $0.hasPrefix("wait:") }.count == 1)
        let results = log.lock.withLock { log.events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
        #expect(Set(results.map(\.content).map { String($0.prefix(8)) }) == ["Found A.", "Found B."])
        #expect(results.map(\.toolCallID) == ["call_A", "call_B"])
    }
}

@Suite struct BackgroundSubagentTests {
    private let bgTask = #"{"description":"Find greet","prompt":"Where is greet() defined?","agent":"explore","background":true}"#

    @Test func aReportArrivesAsAMessageAndTheLoopWaitsForIt() async throws {
        let ws = try makeProject()
        let (main, mainHost) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", bgTask),
            SSE.content("Meanwhile I looked at the README."),        // would end the run, but the report is still coming
            SSE.content("The report says src/main.swift:12."),
        ]))
        let (sub, _) = MockServer.client(MockServer.Route(chunks: SSE.content("greet() is at src/main.swift:12."), delay: 0.1))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: sub, model: "small") })
        let events = Events()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }
        let all = events.all
        #expect(events.results.first?.content.hasPrefix("Started the explore subagent in the background") == true)
        let injected = all.compactMap { if case .injected(let m) = $0 { m } else { nil } }
        let report = try #require(injected.first)
        #expect(report.subagentReport != nil && report.role == .user)
        #expect(report.content.contains("not a message from the user") && report.content.contains("src/main.swift:12"))
        #expect(all.contains { if case .status(let s) = $0 { s.hasPrefix("Waiting for 1 background subagent") } else { false } })
        #expect(events.assistants.map(\.content) == ["", "Meanwhile I looked at the README.", "The report says src/main.swift:12."])
        if case .finished(let s)? = all.last { #expect(s == .completed) } else { Issue.record("no finish") }
        // The model saw the report in its next request, after its own last reply.
        let last = String(decoding: MockServer.requestBodies(mainHost)[2], as: UTF8.self)
        let iReply = try #require(last.range(of: "Meanwhile I looked")), iReport = try #require(last.range(of: "greet() is at"))
        #expect(iReply.lowerBound < iReport.lowerBound)
    }

    @Test func agentsThatWriteCantRunInTheBackground() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Edit","prompt":"Edit a file.","agent":"general","background":true}"#),
            SSE.content("OK, I'll do it myself."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Edit it")], config: config,
                            workspace: ws) { events.add($0) }
        let r = try #require(events.results.first)
        #expect(r.toolResult?.isError == true && r.content.contains("background runs are for agents that only read"))
        #expect(!events.all.contains { if case .subagentStarted = $0 { true } else { false } })
    }

    @Test func stoppingTheMainAgentStopsABackgroundRun() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [SSE.toolCall("call_1", "task", bgTask), SSE.content("Waiting.")]))
        let (sub, _) = MockServer.client(MockServer.Route(chunks: SSE.content("never"), delay: 5, repeatForever: true))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: sub, model: "small") })
        let events = Events()
        let run = Task {
            await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config,
                                workspace: ws) { events.add($0) }
        }
        // Stop once the loop is waiting for the report.
        while !events.all.contains(where: { if case .status = $0 { true } else { false } }) { try await Task.sleep(for: .milliseconds(20)) }
        run.cancel()
        await run.value
        if case .finished(let s)? = events.all.last(where: { if case .finished = $0 { true } else { false } }) { #expect(s == .cancelled) }
        // The background run ends too (stopped), shortly after.
        for _ in 0..<100 where !events.all.contains(where: { if case .subagentFinished = $0 { true } else { false } }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let ends = events.all.compactMap { if case .subagentFinished(_, let e) = $0 { e.stop } else { nil } }
        #expect(ends == ["cancelled"])
    }
}
