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
    var judgments: [RunJudgment] { all.compactMap { if case .judged(let j) = $0 { j } else { nil } } }
    var costs: [CostEntry] { all.compactMap { if case .cost(let e) = $0 { e } else { nil } } }
}

private func call(_ name: String, _ args: [String: String]) -> ToolCall {
    ToolCall(id: "c\(UUID().uuidString.prefix(4))", name: name,
             arguments: String(decoding: try! JSONEncoder().encode(args), as: UTF8.self))
}

private func result(_ c: ToolCall, _ text: String, error: Bool = false, exit: Int32? = nil) -> ChatMessage {
    var info = ToolResultInfo(toolName: c.name, isError: error, truncated: false, duration: 0)
    info.exitCode = exit
    return ChatMessage(role: .tool, content: text, toolCallID: c.id, toolResult: info)
}

@Suite struct JudgingTests {
    @Test func citationsAreFoundAndURLsAndTimesAreNot() {
        let text = """
            See `src/main.swift:12`, Sources/A/B.swift:3:7, ./docs/guide.md:1-4 and README.md:2.
            Not http://localhost:8080/x, not 10:30, not main:12, not v1.2:3? (that one has a dot: counted).
            """
        let cs = GroundedChecks.citations(in: text).map { "\($0.path):\($0.line)" }
        #expect(cs.contains("src/main.swift:12") && cs.contains("Sources/A/B.swift:3") && cs.contains("./docs/guide.md:1")
                && cs.contains("README.md:2"))
        #expect(!cs.contains { $0.hasPrefix("localhost") || $0.hasPrefix("10") || $0.hasPrefix("main:") })

        // Seen from qwen3.5-9b: a table, and "at line N" prose.
        let table = """
            | Function | File Path | Line Number |
            |----------|-----------|-------------|
            | `read_all` | `src/io/files.py` | 3 |
            | `zephyr_quotient` | `src/math/ratio.py` | 17 |
            - **`read_all`**: Defined in `src/io/files.py` at **line 3**
            It's in Package.swift, line 12, near the top. Version 2.0 shipped 3 builds.
            """
        let found = GroundedChecks.citations(in: table).map { "\($0.path):\($0.line)" }
        #expect(found == ["src/io/files.py:3", "src/math/ratio.py:17", "Package.swift:12"])
    }

    @Test func checksResolveCitationsAndFindMadeUpOnes() throws {
        let ws = try makeProject()
        let good = GroundedChecks.evaluate(messages: [], report: "greet is at src/main.swift:12 (and README.md:1).",
                                           stop: .completed, maxSteps: 50, workspace: ws, verify: nil)
        #expect(good.citations == 2 && good.unresolvedCitations.isEmpty && !good.isHardFailure && good.problems.isEmpty)

        let bad = GroundedChecks.evaluate(messages: [], report: "See src/main.swift:99, src/greeter.swift:4, src/main.swift:12.",
                                          stop: .completed, maxSteps: 50, workspace: ws, verify: nil)
        #expect(bad.unresolvedCitations == ["src/main.swift:99 (the file has 30 lines)", "src/greeter.swift:4 (no such file)"])
        #expect(bad.isHardFailure && bad.hardFailures.first?.hasPrefix("made-up citations: 2 of 3") == true)

        // One stray citation among many is a problem to mention, not a failure.
        let one = GroundedChecks.evaluate(messages: [], report: "src/main.swift:12, README.md:1, docs/guide.md:1, src/nope.swift:2",
                                          stop: .completed, maxSteps: 50, workspace: ws, verify: nil)
        #expect(!one.isHardFailure && one.problems.first?.hasPrefix("1 of 4 citations don't resolve") == true)

        let empty = GroundedChecks.evaluate(messages: [], report: "", stop: .turnStopped(.failed), maxSteps: 50, workspace: ws, verify: nil)
        #expect(empty.hardFailures.contains("no report") && empty.hardFailures.contains { $0.hasPrefix("stopped early") })
    }

    @Test func checksSeeChangesAndTheVerifyCommand() throws {
        let ws = try makeProject()
        let edit = call("write_file", ["path": "src/new.swift", "content": "x"])
        let test1 = call("bash", ["command": "cd . && swift test 2>&1 | tail"])
        let again = call("bash", ["command": "cd . && swift test 2>&1 | tail"])
        let messages: [ChatMessage] = [
            ChatMessage(role: .assistant, content: "", toolCalls: [edit]), result(edit, "wrote"),
            ChatMessage(role: .assistant, content: "", toolCalls: [test1]), result(test1, "1 failed", error: true, exit: 1),
            ChatMessage(role: .assistant, content: "", toolCalls: [again]), result(again, "ok", exit: 0),
        ]
        let passed = GroundedChecks.evaluate(messages: messages, report: "Done: tests pass.", stop: .completed, maxSteps: 50,
                                             workspace: ws, verify: "swift test")
        #expect(passed.verifyExitCode == 0 && passed.repeatedCalls == 1 && passed.toolErrors == 1)
        #expect(passed.filesChanged == ["src/new.swift"] && passed.unmentionedChanges == ["src/new.swift"])
        #expect(!passed.isHardFailure)

        let failed = GroundedChecks.evaluate(messages: Array(messages.prefix(4)), report: "Wrote src/new.swift.", stop: .completed,
                                             maxSteps: 50, workspace: ws, verify: "swift test")
        #expect(failed.verifyExitCode == 1 && failed.isHardFailure && failed.unmentionedChanges.isEmpty)

        let notRun = GroundedChecks.evaluate(messages: Array(messages.prefix(2)), report: "Wrote new.swift.", stop: .completed,
                                             maxSteps: 50, workspace: ws, verify: "swift test")
        #expect(notRun.verifyExitCode == nil && notRun.problems.contains("didn't run the check (swift test)"))
    }

    @Test func theCardIsLenient() throws {
        let args = try ToolArguments(json: #"{"kind":"Search","importance":"urgent","verify":"none","tier":"cheap"}"#)
        let card = TaskCard(args)
        #expect(card.kind == .search && card.importance == nil && card.verify == nil && card.tier == .cheap)
        #expect(TaskCard(try ToolArguments(json: #"{"kind":"write-tests","verify":" make test "}"#)) == TaskCard(kind: .writeTests, verify: "make test"))
    }

    @Test func theUsersJudgmentCountsMostAndHardFailuresBeatOpinions() {
        let run = UUID()
        var checks = GroundedChecks.evaluate(messages: [], report: "fine", stop: .completed, maxSteps: 50, workspace: nil, verify: nil)
        let t0 = Date()
        let parent = RunJudgment(run: run, judge: .parent, verdict: 3, at: t0)
        let ok = RunJudgment(run: run, judge: .checks, checks: checks, at: t0)
        #expect([parent, ok].label == 1)
        checks.hardFailures = ["no report"]
        let failing = RunJudgment(run: run, judge: .checks, checks: checks, at: t0)
        #expect([parent, failing].label == 0)
        let user = RunJudgment(run: run, judge: .user, verdict: 2, at: t0.addingTimeInterval(1))
        #expect([parent, failing, user].label == 2.0 / 3)
        // Every judgment is kept; the latest per judge counts.
        let later = RunJudgment(run: run, judge: .parent, verdict: 1, at: t0.addingTimeInterval(2))
        #expect([parent, later].latestByJudge.map(\.verdict) == [1])
    }

    /// A whole run: the card goes to the run record, the checks are recorded, and at the end the parent is asked once,
    /// aside from the conversation, to rate the run; the rating lands in the run's session and is announced for the
    /// parent's.
    @Test func theParentIsAskedToRateAtTheEnd() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-judge-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let task = #"{"description":"Find greet","prompt":"Where is greet() defined?","agent":"explore","kind":"search","importance":"normal"}"#
        let rate = #"{"task":"Find greet","verdict":3,"checked":"read-the-files","note":"Right file and line."}"#
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", task),                                    // main agent
            SSE.content("greet() is defined at src/main.swift:12."),                 // subagent's report
            SSE.content("It's at src/main.swift:12."),                               // main agent's answer
            SSE.toolCall("call_r", "rate_task", rate),                               // the rating request
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }

        // The conversation is unchanged: the rating request isn't part of it.
        #expect(events.assistants.map(\.content) == ["", "It's at src/main.swift:12."])
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 4)
        let last = String(decoding: bodies[3], as: UTF8.self)
        #expect(last.contains("Before you finish: rate the subagent run") && last.contains("\\\"Find greet\\\" (explore)"))
        #expect(String(decoding: bodies[0], as: UTF8.self).contains("\"rate_task\""))

        let runID = try #require(events.results.first?.toolResult?.subagentRun)
        #expect(events.judgments.map(\.judge) == [.checks, .parent])
        #expect(events.judgments.allSatisfy { $0.run == runID })
        let rating = try #require(events.judgments.last)
        #expect(rating.verdict == 3 && rating.checked == "read-the-files" && rating.taskCall == "call_1" && rating.judgeModel == "m")
        #expect(rating.prompt?.hasPrefix("Before you finish") == true && rating.response?.contains("rate_task") == true)
        // It says it read the files, but made no call after the report.
        #expect(rating.checkedConfirmed == false && rating.summary.contains("unconfirmed"))
        #expect(events.costs.contains { $0.purpose == .rating })

        let run = try #require(await store.subagentRun(runID, of: parent))
        #expect(run.judgments.map(\.judge) == [.checks, .parent])
        #expect(run.judgments.label == 1)
        #expect(run.subagentEnd?.card == TaskCard(kind: .search, importance: .normal))
        #expect(run.runs.last?.task.card?.kind == .search)
        #expect(events.results.first?.content.contains("[Automatic checks") == false)       // nothing wrong to report
    }

    /// Problems the checks find go to the parent with the report.
    @Test func theParentSeesWhatTheChecksFound() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Find greet","prompt":"Where?","agent":"explore"}"#),
            SSE.content("It's in src/greeter.swift:4 and src/hello.swift:9."),
            SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }
        let text = try #require(events.results.first?.content)
        #expect(text.contains("[Automatic checks: made-up citations: 2 of 2 don't resolve"))
        #expect(events.judgments.isEmpty)               // not recorded: nothing to attach a judgment to, and no rating asked
    }

    /// An important task gets a grader's opinion, on a model other than the run's.
    @Test func importantTasksAreGraded() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-grade-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Find greet","prompt":"Where?","agent":"explore","importance":"high"}"#),
            SSE.content("greet() is at src/main.swift:12."),
            SSE.content("Done."),
            SSE.content("No rating."),
        ]))
        let (graderClient, graderHost) = MockServer.client(.init(turns: [
            SSE.toolCall("g1", "rate_task", #"{"task":"Find greet","verdict":2,"checked":"read-the-files","issues":["incomplete"]}"#),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        config.subagents?.grader = { _, _ in SubagentModel(client: graderClient, model: "judge") }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }
        let graded = try #require(events.judgments.first { $0.judge == .grader })
        #expect(graded.verdict == 2 && graded.issues == ["incomplete"] && graded.judgeModel == "judge")
        let asked = String(decoding: try #require(MockServer.requestBodies(graderHost).first), as: UTF8.self)
        #expect(asked.contains("## Cited lines") && asked.contains("func greet()"))
        #expect(events.costs.contains { $0.purpose == .grading })
        let run = try #require(await store.subagentRun(graded.run, of: parent))
        #expect(run.judgments.contains { $0.judge == .grader && $0.prompt != nil && $0.response != nil })
    }
}

extension JudgingTests {
    /// A parent that read a file after the report and then rated it: the claim is backed by the call.
    @Test func aCheckThatHappenedIsConfirmed() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-judge-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Find greet","prompt":"Where?","agent":"explore"}"#),
            SSE.content("greet() is at src/main.swift:12."),
            SSE.toolCall("call_2", "read_file", #"{"path":"src/main.swift","offset":10,"limit":5}"#),
            SSE.toolCall("call_3", "rate_task", #"{"task":"1","verdict":3,"checked":"read-the-files"}"#),
            SSE.content("It's at src/main.swift:12."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }
        let rating = try #require(events.judgments.first { $0.judge == .parent })
        #expect(rating.checkedConfirmed == true && rating.evidence?.first?.hasPrefix("read_file") == true)
        #expect(rating.prompt == nil)                                   // rated in the conversation, not when asked
        #expect(MockServer.requestBodies(host).count == 5)              // rated already: no request at the end
        #expect(events.results.last?.content.hasPrefix("Recorded:") == true)
    }
}

extension JudgingTests {
    /// Asked to rate, the parent may look first (seen: qwen3.5-9b read the files): the read runs aside from the
    /// conversation, and backs the claimed check.
    @Test func theParentMayReadBeforeItRates() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-judge-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Find greet","prompt":"Where?","agent":"explore"}"#),
            SSE.content("greet() is at src/main.swift:12."),
            SSE.content("It's at src/main.swift:12."),
            SSE.toolCall("call_r1", "read_file", #"{"path":"src/main.swift","offset":12,"limit":1}"#),   // the rating request
            SSE.toolCall("call_r2", "rate_task", #"{"task":"Find greet","verdict":3,"checked":"read-the-files"}"#),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Where is greet?")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(events.assistants.map(\.content) == ["", "It's at src/main.swift:12."])     // the conversation is unchanged
        let rating = try #require(events.judgments.first { $0.judge == .parent })
        #expect(rating.verdict == 3 && rating.checkedConfirmed == true && rating.evidence?.first?.hasPrefix("read_file") == true)
        let bodies = MockServer.requestBodies(host).map { String(decoding: $0, as: UTF8.self) }
        #expect(bodies.count == 5 && bodies[4].contains("func greet()"))                     // it saw what it read
        #expect(events.costs.filter { $0.purpose == .rating }.count == 2)
    }
}

extension JudgingTests {
    /// Six reads in a row that fill a fifth of the context: the last one carries the advice to delegate, once.
    @Test func broadReadingGetsTheAdviceToDelegate() async throws {
        let ws = try makeProject()
        let big = (1...400).map { "line \($0) of filler text for the context" }.joined(separator: "\n")
        for i in 1...8 { try big.write(to: ws.root.appending(path: "f\(i).txt"), atomically: true, encoding: .utf8) }
        let reads = (1...8).map { i in SSE.toolCall("r\(i)", "read_file", #"{"path":"f\#(i).txt"}"#) }
        let (client, _) = MockServer.client(.init(turns: reads + [SSE.content("Done.")]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup()
        config.context = ContextBudget(limit: 60_000, outputReserve: 2_000)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Read everything.")],
                            config: config, workspace: ws) { events.add($0) }
        let advised = events.results.filter { $0.content.contains("the explore subagent can do the searching") }
        #expect(advised.count == 1)
        #expect(advised.first?.toolResult?.notes?.contains { $0.hasPrefix("Suggested the explore subagent") } == true)
        let index = try #require(events.results.firstIndex { $0.content.contains("explore subagent can do") })
        #expect(index >= 5)

        // Off in Settings: no advice.
        let (quiet, _) = MockServer.client(.init(turns: reads + [SSE.content("Done.")]))
        config.delegationAdvice = false
        let none = Events()
        await AgentLoop.run(client: quiet, model: "m", systemPrompt: "MAIN", history: [.user("Read everything.")],
                            config: config, workspace: ws) { none.add($0) }
        #expect(!none.results.contains { $0.content.contains("explore subagent can do") })
    }
}

extension JudgingTests {
    private func ratingRun(mode: PermissionMode, sideCalls: [[Data]], verify: String = "grep -q Demo README.md",
                           approve: (@Sendable (ApprovalRequest) async -> ApprovalDecision)? = nil)
        async throws -> (Events, [String]) {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-judge-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let task = #"{"description":"Check the readme","prompt":"Is it there?","agent":"explore","verify":"\#(verify)"}"#
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", task),
            SSE.content("README.md:1 says # Demo."),
            SSE.content("Yes."),
        ] + sideCalls))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: mode))
        if let approve { config.approve = approve }
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "MAIN", history: [.user("Is the readme there?")],
                            config: config, workspace: ws) { events.add($0) }
        return (events, MockServer.requestBodies(host).map { String(decoding: $0, as: UTF8.self) })
    }

    /// Asked to rate, the parent may run the task's own check (exactly as written), and that backs "ran-tests".
    @Test func theParentMayRunTheTasksCheckBeforeItRates() async throws {
        let (events, bodies) = try await ratingRun(mode: .fullAuto, sideCalls: [
            SSE.toolCall("v1", "bash", #"{"command":"grep -q Demo README.md"}"#),
            SSE.toolCall("r1", "rate_task", #"{"task":"1","verdict":3,"checked":"ran-tests"}"#),
        ])
        let rating = try #require(events.judgments.first { $0.judge == .parent })
        #expect(rating.checkedConfirmed == true && rating.evidence?.first?.hasPrefix("bash") == true)
        #expect(bodies.count == 5 && bodies[3].contains("its check: `grep -q Demo README.md`"))
        #expect(bodies[4].contains("exit code 0") || bodies[4].contains("(no output)") || bodies[4].contains("exit 0"))
        #expect(events.assistants.map(\.content) == ["", "Yes."])                    // none of it in the conversation
    }

    /// With no subagent run there's nothing to rate, and the error says to stop: qwen3-coder kept inventing task names.
    @Test func ratingWithNoSubagentRunSaysThereIsNothingToRate() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = AgentConfig(tools: [])
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.subagents = SubagentSetup()
        let (client, host) = MockServer.client(.init(chunks: [], turns: [
            SSE.toolCall("r", "rate_task", #"{"task":"my own work","verdict":3,"checked":"read-the-files"}"#), SSE.content("Done.")]))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: Workspace(root: dir)) { _ in }
        let sent = String(decoding: MockServer.requestBodies(host).last ?? Data(), as: UTF8.self)
        #expect(sent.contains("nothing to rate") && !sent.contains("give the task's title"))
    }

    /// Any other command is refused, and a refused call isn't a check.
    @Test func otherCommandsAreRefusedAndDontCount() async throws {
        let (events, bodies) = try await ratingRun(mode: .fullAuto, sideCalls: [
            SSE.toolCall("v1", "bash", #"{"command":"touch made-by-the-rater"}"#),
            SSE.toolCall("r1", "rate_task", #"{"task":"1","verdict":3,"checked":"ran-tests"}"#),
        ])
        let rating = try #require(events.judgments.first { $0.judge == .parent })
        #expect(rating.checkedConfirmed == false && rating.evidence == nil)
        #expect(bodies[4].contains("only a task's check command, exactly as given, can run now: grep -q Demo README.md."))
    }

    /// In Ask mode the check is asked about like any command; denied, it doesn't run or count.
    @Test func theCheckIsAuthorizedLikeAnyCommand() async throws {
        final class Asked: @unchecked Sendable { let lock = NSLock(); var summaries: [String] = [] }
        let asked = Asked()
        let (events, _) = try await ratingRun(mode: .ask, sideCalls: [
            SSE.toolCall("v1", "bash", #"{"command":"grep -q Demo README.md"}"#),
            SSE.toolCall("r1", "rate_task", #"{"task":"1","verdict":2,"checked":"ran-tests"}"#),
        ], approve: { r in asked.lock.withLock { asked.summaries.append(r.summary) }; return .deny(feedback: nil) })
        #expect(asked.lock.withLock { asked.summaries }.contains { $0.contains("grep -q Demo README.md") })
        let rating = try #require(events.judgments.first { $0.judge == .parent })
        #expect(rating.checkedConfirmed == false)
    }
}


extension JudgingTests {
    /// At the end of the parent's run, each task's check runs again; a failure is a grounded hard failure that
    /// outweighs any rating, and the parent is told of it when asked to rate.
    @Test func aFailingCheckRunAgainIsAHardFailure() async throws {
        let (events, bodies) = try await ratingRun(mode: .fullAuto, sideCalls: [
            SSE.toolCall("r1", "rate_task", #"{"task":"1","verdict":3,"checked":"read-the-files"}"#),
        ], verify: "grep -q Nowhere README.md")
        let recheck = try #require(events.judgments.first { $0.judge == .recheck })
        #expect(recheck.checks?.verifyExitCode == 1 && recheck.checks?.isHardFailure == true)
        #expect(bodies[3].contains("(run again just now: it FAILED, exit 1)") && bodies[3].contains(AgentLoop.rubric))
        #expect(events.judgments.first { $0.judge == .parent }?.verdict == 3)
        #expect(events.judgments.label == 0)                         // the grounded failure wins over the 3/3
        // The parent's own run records it, as a reason to offer escalation (11b).
        let main = try #require(events.all.compactMap { e -> AgentRunRecord? in
            if case .runEnded(let r) = e, r.agent == "main" { r } else { nil } }.last)
        #expect(main.signals?.failedRechecks == ["grep -q Nowhere README.md"])
        #expect(Escalation.reasons(main) == ["a delegated task's check fails after the run: grep -q Nowhere README.md"])
    }

    @Test func aPassingCheckRunAgainLeavesTheRatingToCount() async throws {
        let (events, bodies) = try await ratingRun(mode: .fullAuto, sideCalls: [
            SSE.toolCall("r1", "rate_task", #"{"task":"1","verdict":2,"checked":"read-the-files"}"#),
        ])
        #expect(events.judgments.first { $0.judge == .recheck }?.checks?.verifyExitCode == 0)
        #expect(bodies[3].contains("(run again just now: it passed)"))
        #expect(events.judgments.label == 2.0 / 3)
    }
}

extension JudgingTests {
    /// Gemma 4 wrote its rate_task call as text, in its own format (seen in calibration).
    @Test func gemmaTextCallsAreRecovered() throws {
        let text = #"rate_task{checked:<|"|>read-the-files<|"|>, issues:[<|"|>wrong-facts<|"|>], note:<|"|>The subagent "made up" the error.<|"|>, task:<|"|>Find the one error<|"|>, verdict:0}<tool_call|>"#
        let found = try #require(TextToolCalls.extract(from: "Checked it.\n<|tool_call>call:" + text, knownTools: ["rate_task", "read_file"]))
        #expect(found.calls.map(\.name) == ["rate_task"] && found.remaining == "Checked it.")
        let args = try ToolArguments(json: found.calls[0].arguments)
        #expect(args.int("verdict") == 0 && args.string("note") == #"The subagent "made up" the error."# && args.string("checked") == "read-the-files")
        #expect(args.values["issues"] == .array([.string("wrong-facts")]))
        #expect(TextToolCalls.extract(from: "No call here, just <|\"|>quotes<|\"|>.", knownTools: ["rate_task"]) == nil)
    }
}
