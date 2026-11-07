import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

// Round 6 of the functional tests (FUNCTIONAL_TESTS.md §20): probes for what three code reviews of Phase 2 found.
// Each test is named for its finding (R6-n in FUNCTIONAL_TEST_RESULTS.md "Round 6").

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var started: [SubagentInfo] { all.compactMap { if case .subagentStarted(let i) = $0 { i } else { nil } } }
    var injected: [ChatMessage] { all.compactMap { if case .injected(let m) = $0 { m } else { nil } } }
    var statuses: [String] { all.compactMap { if case .status(let s) = $0 { s } else { nil } } }
}

private let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
private let anthropic = Endpoint(name: "Anthropic", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!, usesAPIKey: true)

private func object(_ json: String) -> [String: JSONValue] {
    guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else { return [:] }
    return o
}

private let madeUp: [[Data]] = [
    SSE.toolCall("w1", "write_file", #"{"path":"NOTE.md","content":"draft\n"}"#),
    SSE.content("Done: see ghost.py:10 and phantom.swift:3 for where it's used.", model: "rung-1"),
]

@Suite struct R6PoolAndRetryTests {
    /// R6-1 (A): a LAN server reached by a name kurtkode can't place counted as remote, so a local session's subagent
    /// tasks went to OpenRouter by default.
    @Test func r6_1_onlyHostedAPIsRouteAutomatically() {
        for url in ["http://studio:1234/v1", "http://gpu.lan:8000/v1", "http://box.home.arpa/v1", "http://mac.tail1234.ts.net:1234/v1",
                    "http://ollama.internal:11434/v1", "http://10.0.0.5:1234/v1"] {
            let lan = Endpoint(name: "LAN", kind: .openai, baseURL: URL(string: url)!)
            #expect(!lan.isCloudAPI, "\(url)")
            #expect(SubagentRouting.automatic(card: TaskCard(), main: lan, mainModel: "m", pool: .shipped, endpoints: [lan, openRouter]) == nil)
            #expect(SubagentRouting.grader(main: lan, runEndpointID: nil, runModel: "x", pool: .shipped, endpoints: [lan, anthropic]) == nil)
        }
        #expect(openRouter.isCloudAPI && anthropic.isCloudAPI)
        #expect(Endpoint(name: "OpenAI", kind: .openai, baseURL: URL(string: "https://api.openai.com/v1")!).isCloudAPI)
        #expect(!Endpoint(name: "Evil", kind: .openai, baseURL: URL(string: "https://openrouter.ai.example.com/v1")!).isCloudAPI)
    }

    /// R6-2 (A): a failed run's edits were undone after it gave up its writer slot, so another writing run could have
    /// changed the same files in between, and the undo wiped them.
    @Test func r6_2_theUndoHappensWhileTheRunStillHoldsItsSlot() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Note it","prompt":"Write the note","agent":"general"}"#), SSE.content("Done."),
        ]))
        let (first, _) = MockServer.client(.init(turns: madeUp))
        let (second, _) = MockServer.client(.init(turns: [SSE.content("OK.")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root))
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: first, model: "a") })
        let limiter = config.subagents!.limiter
        final class Seen: @unchecked Sendable { var slotFree: Bool?; var fileThere: Bool? }
        let seen = Seen()
        config.subagents?.retryModel = { _, _, _, _ in
            // Asked while the failed run still holds the writers' slot (and before its edits are undone).
            let free = await limiter.tryAcquire("writers", limit: 1)
            if free { await limiter.release("writers") }
            seen.slotFree = free
            seen.fileThere = FileManager.default.fileExists(atPath: ws.root.appending(path: "NOTE.md").path)
            return SubagentModel(client: second, model: "b")
        }
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { _ in }
        #expect(seen.slotFree == false)
        #expect(seen.fileThere == true)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "NOTE.md").path))
    }

    /// R6-3 (B): retries went to the pool even when the user had chosen the subagent's model (or the agent file had), and a
    /// model the pool doesn't know went to the first rung, below it.
    @Test func r6_3_onlyThePoolsOwnChoicesAreRetriedAndNeverDown() throws {
        let eps = [openRouter, anthropic]
        #expect(SubagentRouting.retry(after: openRouter.id, model: "inclusionai/ling-3.0-flash", reasoning: nil, routed: false,
                                      main: anthropic, pool: .shipped, endpoints: eps) == nil)
        #expect(SubagentRouting.retry(after: openRouter.id, model: "inclusionai/ling-3.0-flash", reasoning: nil, routed: true,
                                      main: anthropic, pool: .shipped, endpoints: eps)?.model == "claude-haiku-5-5")
        // A model the pool doesn't know (sonnet): no tier to climb from, no retry.
        #expect(ModelPool.shipped.next(after: anthropic.id, model: "claude-sonnet-5-5", reasoning: nil, endpoints: eps) == nil)
        var settings = RunSettings()
        #expect(SubagentRouting.routed(AgentDefinition.builtIns.first { $0.name == "general" }!, settings: settings))
        var pinned = AgentDefinition.builtIns.first { $0.name == "general" }!
        pinned.model = "sonnet"
        #expect(!SubagentRouting.routed(pinned, settings: settings))
        settings.subagentAutomatic = false
        #expect(!SubagentRouting.routed(AgentDefinition.builtIns.first { $0.name == "general" }!, settings: settings))
    }

    /// R6-4 (B): a pool.json with one slip (an entry without "enabled") silently brought back the shipped pool, OpenRouter
    /// entries and all.
    @Test func r6_4_aHandWrittenPoolIsReadOrRefusedNeverReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kk-r6-pool-\(UUID().uuidString.prefix(6)).json")
        try Data(#"{"entries": [{"endpoint": "claude", "model": "haiku", "tier": "standard", "ladder": 0}]}"#.utf8).write(to: url)
        let (pool, problem) = ModelPool.loadChecked(url)
        #expect(problem == nil)
        #expect(pool.entries.count == 1 && pool.entries[0].enabled && pool.entries[0].roles == [.subagent])
        try Data(#"{"entries": [{"endpoint": "claude", "model": "opus", "tier": "strong"}]}"#.utf8).write(to: url)
        #expect(ModelPool.loadChecked(url).pool.entries.first?.tier == .frontier)      // the card's word for it
        try Data(#"{"entries": [{"endpoint": "claude", "tier": "standard"}]}"#.utf8).write(to: url)
        let broken = ModelPool.loadChecked(url)
        #expect(broken.pool.entries.isEmpty)
        #expect(broken.problem?.contains("missing \"model\"") == true)
        #expect(ModelPool.loadChecked(url.appendingPathExtension("none")).pool == .shipped)   // no file: the shipped pool
    }

    /// R6-5 (B): Ollama's trained context (model_info) was taken for what it serves, so nothing was compacted.
    @Test func r6_5_ollamaServesItsNumCtx() {
        var m = ListedModel(id: "qwen3:8b")
        m.absorbOllama(object(#"{"model_info": {"qwen3.context_length": 40960}, "capabilities": ["tools"]}"#))
        #expect(m.contextLength == nil && m.supportsTools == true)
        m.absorbOllama(object(#"{"parameters": "temperature 0.6\nnum_ctx 16384\nstop \"<|im_end|>\"", "capabilities": ["tools"]}"#))
        #expect(m.contextLength == 16_384)
    }

    /// R6-6 (B/C): a retried background run's report named the failed run.
    @Test func r6_6_aRetriedBackgroundReportNamesTheSecondRun() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-r6-6-\(UUID().uuidString.prefix(6))"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(header)
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Look","prompt":"Look around","agent":"explore","background":true}"#),
            SSE.content("Waiting."), SSE.content("Got it."),
        ]))
        let (first, _) = MockServer.client(.init(turns: [SSE.content("See ghost.py:10 and phantom.swift:3.")]))
        let (second, _) = MockServer.client(.init(turns: [SSE.content("Nothing found.")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root))
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: first, model: "a") },
                                         recorder: SubagentRecorder(store: store, parent: header))
        config.subagents?.retryModel = { _, _, _, _ in SubagentModel(client: second, model: "b") }
        let events = Events()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { events.add($0) }
        let report = try #require(events.injected.first { $0.subagentReport != nil })
        let runs = await store.subagentRuns(of: header)
        #expect(report.subagentReport == runs.first { $0.model == "b" }?.header.id)
    }

    /// R6-7 (C): a profile's reasoning setting on a rung's model hid the rung, and the retry skipped a step.
    @Test func r6_7_aRungMatchesWhateverItsProfileSet() {
        let next = ModelPool.threeRungs.next(after: openRouter.id, model: "inclusionai/ling-3.0-flash", reasoning: "low",
                                          endpoints: [openRouter, anthropic])
        #expect(next?.model == "deepseek/deepseek-v4-flash-0731")
    }

    /// R6-8 (C): a mistyped --reasoning went to the server; Gemini 2.5 Pro was offered "none", which it refuses.
    @Test func r6_8_reasoningLevelsAreChecked() throws {
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["--reasoning", "hgih"]) }
        #expect(try CLIOptions.parse(["--reasoning", "None"]).reasoning == "none")
        #expect(!Replay.effortLevels(api: .gemini, model: "gemini-2.5-pro").contains("none"))
        #expect(Replay.effortLevels(api: .gemini, model: "gemini-2.5-flash").contains("none"))
    }

    /// R6-9 (B): an important task without a tier runs on Haiku, the automatic grader too, so it was never graded.
    @Test func r6_9_theGraderIsNeverTheRunsOwnModel() {
        let eps = [openRouter, anthropic]
        #expect(SubagentRouting.grader(main: anthropic, runEndpointID: openRouter.id, runModel: "inclusionai/ling-3.0-flash",
                                       pool: .shipped, endpoints: eps)?.model == "claude-haiku-5-5")
        // A run on the only judge gets no grade, not Opus (cost audit, decision 3); the A6 review still runs.
        #expect(SubagentRouting.grader(main: anthropic, runEndpointID: anthropic.id, runModel: "claude-haiku-5-5",
                                       pool: .shipped, endpoints: eps) == nil)
    }

    /// R6-10 (A, from the retry simulation): "made-up citations" fired on right reports that named a file by its bare
    /// name in a subfolder, or a dotted name in the code; "no report" on runs cut off after doing the work.
    @Test func r6_10_citationsAndMissingReportsThatArentFailures() throws {
        let ws = try makeProject()
        let dir = ws.root.appending(path: "inventory")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data((1...20).map { "line \($0)" }.joined(separator: "\n").utf8).write(to: dir.appending(path: "pricing.py"))
        let ok = GroundedChecks.evaluate(messages: [], report: "The discount is applied at pricing.py:12 and pricing.py:4.",
                                         stop: .completed, maxSteps: 10, workspace: ws, verify: nil)
        #expect(ok.unresolvedCitations.isEmpty && !ok.isHardFailure)
        let names = GroundedChecks.evaluate(messages: [], report: "Hot paths: cache.warm:13, ledger.flush:8, mail.queue:7.",
                                            stop: .completed, maxSteps: 10, workspace: ws, verify: nil)
        #expect(!names.isHardFailure)
        let fake = GroundedChecks.evaluate(messages: [], report: "See ghost.py:10 and phantom.swift:3.", stop: .completed,
                                           maxSteps: 10, workspace: ws, verify: nil)
        #expect(fake.isHardFailure && fake.retryableFailures.count == 1)
        // No report after changing files: a failure for the parent to look at, not one to undo and retry.
        var cut = GroundedChecks.evaluate(messages: [], report: "", stop: .truncated, maxSteps: 10, workspace: ws, verify: nil)
        #expect(cut.retryableFailures == ["no report"])
        cut.filesChanged = ["inventory/pricing.py"]
        #expect(cut.isHardFailure && cut.retryableFailures.isEmpty)
    }
}

@Suite struct R6SignalsAndSpendingTests {
    /// R6-11 (A): an eval store's degraded copies (their original's record, a forced failure) and infrastructure failures
    /// counted as runs: spending nearly doubled, pass rates fell.
    @Test func r6_11_evalReportsLeaveOutCopiesAndInfraFailures() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-r6-11-\(UUID().uuidString.prefix(6))")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let record = try JSONDecoder().decode(JSONValue.self, from: enc.encode(AgentRunRecord.test(agent: "main", spent: 0.01)))
        let other = try JSONDecoder().decode(JSONValue.self, from: enc.encode(AgentRunRecord.test(agent: "main", spent: 0.01)))
        let runs: [(String, JSONValue)] = [
            ("t1", ["gold": ["passed": true], "runRecord": record]),
            ("t1-digits", ["gold": ["passed": false], "runRecord": record, "degradation": "digits"]),
            ("t2", ["gold": ["passed": false], "runRecord": other, "infra": "HTTP 404 from the provider"]),
        ]
        for (name, obj) in runs {
            try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: true)
            try enc.encode(obj).write(to: dir.appending(path: name).appending(path: "run.json"))
        }
        let read = Spending.evalRuns(dir)
        #expect(read.count == 1 && read[0].passed == true)
    }

    /// R6-12 (A): a run with a charged request and an uncharged one (its summary on another server) reported only the
    /// charge.
    @Test func r6_12_aRunsSpendingSumsEachRequest() async throws {
        let rates = PriceList.Rates(input: 1, output: 1, cacheRead: 1, cacheWrite5m: 1, cacheWrite1h: 1)
        let known = PriceLookup.known(PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil),
                                      source: "t", version: "t")
        func entry(cost: Double?, usage: Int) -> CostEntry {
            var m = ChatMessage(role: .assistant, content: "x")
            var meta = TurnMeta.test
            meta.usage = Usage(promptTokens: usage, completionTokens: 0, cost: cost)
            m.meta = meta
            return CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!),
                                  endpointID: nil, start: Date(), price: known)
        }
        let tracker = RunTracker()
        tracker.observe(.cost(entry(cost: 0.05, usage: 1000)))
        tracker.observe(.cost(entry(cost: nil, usage: 20_000)))           // list price $0.02
        let r = tracker.record(stop: .completed, scope: CostScope(run: UUID(), agent: "main"), config: AgentConfig(tools: []),
                               client: ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!), model: "m", systemPrompt: "",
                               history: [.user("x")], tools: [], localModel: nil)
        #expect(r.totals.charged == 0.05)
        #expect(abs((r.totals.spent ?? 0) - 0.07) < 1e-9)
        #expect(abs((Spending.Run(record: r, project: "p", passed: nil).spent ?? 0) - 0.07) < 1e-9)
    }

    /// R6-13 (B): after a retry or a Continue, a run's request was the note added after the user's message, so thumbs and
    /// the next retry's judgment landed on the earlier run.
    @Test func r6_13_aRetrysRunAnswersTheUsersMessage() {
        var s = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil), messages: [], model: "m")
        let ask = ChatMessage.user("Fix it")
        var note = ChatMessage.user("[skill: debugging]")
        note.contextNote = true
        var report = ChatMessage.user("[Report from a background subagent]")
        report.subagentReport = UUID()
        s.messages = [ask, note, report]
        #expect(s.lastRequest?.id == ask.id)                               // what a retry's run answers now
        // Runs keyed the old way (the note) still map their replies.
        var first = AgentRunRecord.test(agent: "main")
        first.userMessage = ask.id
        var retried = AgentRunRecord.test(agent: "main")
        retried.userMessage = note.id
        var reply = ChatMessage(role: .assistant, content: "done")
        reply.meta = .test
        s.messages.append(reply)
        s.runs = [first, retried]
        #expect(s.replyRuns[reply.id] == retried.id)
        #expect(s.mainRun(for: reply.id)?.id == retried.id)
        #expect(s.latestReplyRun?.id == retried.id)
        // A queued message during a run doesn't start one: the run's reply after it still gets the thumbs.
        var t = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil), messages: [], model: "m")
        let queued = ChatMessage.user("also do X")
        var final = ChatMessage(role: .assistant, content: "did both")
        final.meta = .test
        t.messages = [ask, queued, final]
        t.runs = [first]
        #expect(t.replyRuns[final.id] == first.id)
    }

    /// R6-14 (B): a daily limit stopped free local sessions too, and the stop said "Continue" would help.
    @Test func r6_14_dailyLimitsSayWhatStoppedAndSpareLocalSessions() async throws {
        let m = CostMeter(runLimit: 0, sessionLimit: 0, sessionBefore: 0, dayLimit: 1, dayBefore: 1.2)
        #expect(m.stopNote?.hasPrefix("Stopped at the daily limit of $1.00") == true)
        #expect(m.stopNote?.contains("Continue won't go past it") == true)
        #expect(CostMeter(runLimit: 1, sessionLimit: 0, sessionBefore: 0).stopNote == nil)
        let (client, host) = MockServer.client(.init(turns: [SSE.content("Hi.")]))
        var config = AgentConfig(tools: [])
        config.costMeter = m
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: nil, history: [.user("go")], config: config, workspace: nil) { events.add($0) }
        #expect(MockServer.requestBodies(host).isEmpty)
        #expect(events.statuses.contains { $0.hasPrefix(CostMeter.stopPrefix + "the daily limit") })

        // The limit isn't counted for a session on this Mac's model.
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-r6-14-\(UUID().uuidString.prefix(6))"))
        var settings = RunSettings()
        settings.dailyCostLimit = 0.01
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: "/p"), messages: [], model: "m")
        var run = SessionRun(session: session, store: store, settings: settings, profile: ModelProfile(endpointID: UUID(), model: "m"),
                             endpointID: UUID(), mode: .ask, rules: [], tools: [], workspace: nil, shell: ShellState(cwd: URL(fileURLWithPath: "/tmp")),
                             contextLimit: nil, sandbox: nil, turn: TurnKey(UUID()), checkpoints: CheckpointStore(directory: store.root),
                             approve: { _ in .allow }, hooks: nil, subagentModel: nil)
        await run.countDailySpending(settings: settings, store: store, workspace: "/p", main: .localLMStudio)
        #expect(run.config.costMeter?.dayLimit == nil)
        await run.countDailySpending(settings: settings, store: store, workspace: "/p", main: openRouter)
        #expect(run.config.costMeter?.dayLimit == 0.01)
    }

    /// R6-15 (C): report keys and figures: a reasoning object's key order split rows; a project named "all" took the total
    /// row's id; local runs' tokens dragged the cache share down.
    @Test func r6_15_reportKeysAndCacheShare() {
        var a = AgentRunRecord.test(agent: "main", model: "d", spent: 0.01)
        a.setup.reasoning = #"{"enabled":false}"#
        a.totals.promptTokens = 1000
        a.totals.cacheReadTokens = 800
        var local = AgentRunRecord.test(agent: "main", model: "g")
        local.totals.requests = 1
        local.totals.unpricedRequests = 1
        local.totals.promptTokens = 9000
        let rows = Spending.rows([Spending.Run(record: a, project: "all", passed: nil), Spending.Run(record: local, project: "all", passed: nil)],
                                 by: .project)
        #expect(rows.count == 2 && rows[0].key == "all" && !rows[0].isTotal && rows[1].isTotal)
        #expect(rows[0].cacheShare == 0.8)
        #expect(Spending.Run(record: a, project: "p", passed: nil).model == "d (reasoning off)")
        var on = a
        on.setup.reasoning = #"{"effort":"high","exclude":false}"#
        #expect(Spending.Run(record: on, project: "p", passed: nil).model.hasSuffix("(reasoning {\"effort\":\"high\",\"exclude\":false})"))
    }
}
