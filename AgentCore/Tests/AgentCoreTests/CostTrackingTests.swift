import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var costs: [CostEntry] { all.compactMap { if case .cost(let e) = $0 { e } else { nil } } }
    var assistants: [ChatMessage] { all.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
}

private func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-12 } ?? false }

/// Cost entries (COST_TRACKING_DESIGN.md, phase 1): the list price by component, and an entry for every request.
@Suite struct CostTrackingTests {
    // MARK: Pricing

    @Test func anthropicBreakdownByComponent() throws {
        // Opus 5.5: $4 in, $20 out, $0.20 cache read per million; writes 1.25× and 2× input; $10 per 1,000 searches.
        var u = Usage(promptTokens: 1_000_000 + 200_000 + 100_000 + 50_000, completionTokens: 30_000, reasoningTokens: 10_000,
                      cacheReadTokens: 200_000, cacheWriteTokens: 150_000, cacheWriteHourTokens: 50_000)
        u.webSearches = 3
        let b = try #require(PriceList.breakdown(u, api: .anthropic, model: "claude-opus-5-5"))
        #expect(near(b.uncachedInput, 4.0))
        #expect(near(b.cacheRead, 0.04))
        #expect(near(b.cacheWrite5m, 0.5))         // 100k × $5
        #expect(near(b.cacheWrite1h, 0.4))         // 50k × $8
        #expect(near(b.output, 0.6))
        #expect(near(b.reasoning, 0.2))            // part of output
        #expect(near(b.searches, 0.03))
        #expect(near(b.total, 4.0 + 0.04 + 0.5 + 0.4 + 0.6 + 0.03))
        #expect(b.tier == "standard" && b.unpriced == nil && b.priceList == PriceList.version)
        #expect(near(PriceList.cost(u, api: .anthropic, model: "claude-opus-5-5"), b.total))
    }

    @Test func longPromptTierAndGeminiSearchesUnpriced() throws {
        // Haiku 5.5 above 100k tokens: $0.50 in, $2.50 out.
        let long = Usage(promptTokens: 200_000, completionTokens: 1000)
        let h = try #require(PriceList.breakdown(long, api: .anthropic, model: "claude-haiku-5-5"))
        #expect(h.tier == "long" && near(h.uncachedInput, 0.1) && near(h.output, 0.0025))
        // Gemini search grounding has no price here: left out of the total, and said so.
        var g = Usage(promptTokens: 10_000, completionTokens: 1000, cacheReadTokens: 4000)
        g.webSearches = 2
        let b = try #require(PriceList.breakdown(g, api: .gemini, model: "gemini-3-flash"))
        #expect(b.unpriced == ["searches"] && b.searches == 0)
        #expect(near(b.total, 6000 * 0.5e-6 + 4000 * 0.05e-6 + 1000 * 3e-6))
    }

    @Test func openRouterListPricesFromItsModelList() throws {
        let list = #"{"data":[{"id":"vendor/model","pricing":{"prompt":"0.000003","completion":"0.000015","input_cache_read":"0.0000003","web_search":"0.004","request":"0"}},{"id":"free/model","pricing":{"prompt":"0","completion":"0"}}]}"#
        let prices = RemotePrices.parse(Data(list.utf8))
        let p = try #require(prices["vendor/model"])
        #expect(p.input == 3 && p.output == 15 && p.cacheRead == 0.3 && p.perSearch == 0.004 && p.perRequest == nil)
        #expect(prices["free/model"]?.input == 0)
        let b = CostBreakdown(Usage(promptTokens: 2000, completionTokens: 100, cacheReadTokens: 1000), price: p,
                              source: "openrouter.ai /models", priceList: "read today")
        #expect(near(b.total, 1000 * 3e-6 + 1000 * 0.3e-6 + 100 * 15e-6))
    }

    // MARK: Entries

    @Test func aRunsRepliesAreEntriesWithIDsAndRawUsage() async throws {
        let ws = try makeProject()
        func turn(_ id: String, _ data: [Data]) -> [Data] {      // OpenRouter-style chunks carry the generation id
            data.map { d in Data(String(decoding: d, as: UTF8.self).replacingOccurrences(of: #"{"model""#, with: #"{"id":"\#(id)","model""#).utf8) }
        }
        let (client, _) = MockServer.client(.init(turns: [
            turn("gen-1", SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#)),
            turn("gen-2", SSE.content("A demo.")),
        ]))
        var config = AgentConfig(tools: ReadTools.all)
        let run = UUID()
        config.costScope = CostScope(run: run, agent: "main")
        config.generationLookupDelays = [0.01]
        let events = Events()
        await AgentLoop.run(client: client, model: "test-model", systemPrompt: "S", history: [.user("What is it?")], config: config,
                            workspace: ws) { events.add($0) }
        let costs = events.costs
        #expect(costs.count == 2)
        #expect(costs.map(\.reply) == events.assistants.map(\.id))
        #expect(costs.map(\.requestIDs) == [["gen-1"], ["gen-2"]])
        #expect(costs.allSatisfy { $0.run == run && $0.purpose == .reply && $0.billing == .reported && $0.ended == .completed })
        #expect(costs[0].usageRaw == ["prompt_tokens": 100, "completion_tokens": 20])
        #expect(costs[0].tokens?.completionTokens == 20)
        // The mock server isn't this Mac and lists no prices: unpriced, with the reason.
        #expect(costs[0].listPrice == nil && costs[0].unpricedReason?.contains("no price") == true)
    }

    /// CACHING_PLAN.md Phase 0: each reply request records what it sent, and the next one is checked against it.
    @Test func replyEntriesCarryPromptPrints() async throws {
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#), SSE.content("A demo.")]))
        let events = Events()
        await AgentLoop.run(client: client, model: "test-model", systemPrompt: "S", history: [.user("What is it?")],
                            config: AgentConfig(tools: ReadTools.all), workspace: try makeProject()) { events.add($0) }
        let prints = events.costs.compactMap(\.prompt)
        #expect(prints.count == 2)
        #expect(prints[0].tools == prints[1].tools && prints[0].system == prints[1].system)
        #expect(prints[1].messages == prints[0].messages + 2)       // the reply's call and its result
        #expect(prints.allSatisfy { $0.model == "test-model" })
        #expect(events.costs.allSatisfy { $0.cacheMiss == nil })     // the mock reports no cache use
    }

    @Test func anEmptyReplyAskedAgainIsANudgedReply() async throws {
        let (client, _) = MockServer.client(.init(turns: [SSE.content(""), SSE.content("Here it is.")]))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: AgentConfig(tools: ReadTools.all),
                            workspace: try makeProject()) { events.add($0) }
        #expect(events.costs.map(\.purpose) == [.nudgedReply, .reply])
    }

    @Test func claudeEntryPricedFromItsReportedTokens() async throws {
        let lines = [
            #"{"type":"message_start","message":{"id":"msg_01","model":"claude-opus-5-5","usage":{"input_tokens":1000,"cache_read_input_tokens":4000,"cache_creation_input_tokens":2000,"output_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Hi."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":500}}"#,
            #"{"type":"message_stop"}"#,
        ]
        let (client, _) = MockServer.client(.init(turns: [lines.map { Data("data: \($0)\n\n".utf8) }]), api: .anthropic)
        let events = Events()
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "S", history: [.user("hi")],
                            config: AgentConfig(tools: ReadTools.all), workspace: try makeProject()) { events.add($0) }
        let e = try #require(events.costs.first)
        #expect(e.requestIDs == ["msg_01"])
        #expect(e.tokens?.promptTokens == 7000 && e.tokens?.cacheReadTokens == 4000 && e.tokens?.cacheWriteTokens == 2000)
        let b = try #require(e.listPrice)
        #expect(near(b.uncachedInput, 1000 * 4e-6) && near(b.cacheRead, 4000 * 0.2e-6) && near(b.cacheWrite5m, 2000 * 5e-6))
        #expect(near(b.output, 500 * 20e-6))
        #expect(e.charged == nil)                                  // Anthropic doesn't say what it charged
        guard case .object(let raw)? = e.usageRaw else { Issue.record("no raw usage"); return }
        #expect(raw["message_start"] != nil && raw["message_delta"] != nil)
    }

    @Test func aCutStreamIsAPartialEntry() async throws {
        let lines = [#"{"type":"message_start","message":{"id":"msg_02","model":"claude-opus-5-5","usage":{"input_tokens":3000,"output_tokens":1}}}"#,
                     #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Half"}}"#]
        let (client, _) = MockServer.client(.init(turns: [lines.map { Data("data: \($0)\n\n".utf8) }]), api: .anthropic)
        let events = Events()
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "S", history: [.user("hi")],
                            config: AgentConfig(tools: ReadTools.all), workspace: try makeProject()) { events.add($0) }
        let e = try #require(events.costs.first)
        #expect(e.ended == .failed && e.billing == .partial)
        #expect(near(e.listPrice?.uncachedInput, 3000 * 4e-6))
    }

    @Test func subagentEntriesGoToTheChildSession() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-cost-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let task = #"{"description":"Find greet","prompt":"Where is greet() defined?","agent":"explore"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", task),
            SSE.toolCall("call_s1", "grep", #"{"pattern":"greet"}"#),
            SSE.content("At src/main.swift:12."),
            SSE.content("It's at src/main.swift:12."),
            SSE.content("(no rating)"),                     // the end-of-run rating request
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let mainRun = UUID()
        config.costScope = CostScope(run: mainRun, agent: "main")
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Where is greet?")], config: config,
                            workspace: ws) { events.add($0) }
        #expect(events.costs.count == 3 && events.costs.allSatisfy { $0.run == mainRun && $0.agent == "main" })
        #expect(events.costs.map(\.purpose) == [.reply, .reply, .rating])       // the rating request is the parent's
        let child = try #require(await store.subagentRuns(of: parent).first)
        #expect(child.costs.count == 2)
        #expect(child.costs.allSatisfy { $0.run == child.header.id && $0.agent == "explore" })
        // A later process (`kurtkode cost reconcile`) finds the child's file in its parent's `.subagents` folder.
        let later = SessionStore(root: await store.root)
        var updated = try #require(child.costs.first)
        updated.charged = 0.25
        try await later.append(.cost(updated), to: child.header.id)
        let reread = try #require(await later.subagentRuns(of: parent).first)
        #expect(reread.costs.count == 2 && reread.costs.first?.charged == 0.25)
    }

    @Test func entriesRoundTripThroughTheSessionFile() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-cost-\(UUID().uuidString.prefix(6))"))
        let h = SessionHeader(endpointID: UUID(), model: "m", workspace: nil)
        try await store.create(h)
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "claude-opus-5-5", usage: Usage(promptTokens: 10, completionTokens: 2), stopReason: .completed, duration: 1)
        let client = ChatClient(endpoint: Endpoint(name: "A", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!))
        let e = CostEntry.make(reply: m, purpose: .summary, run: nil, agent: "main", client: client, endpointID: nil, start: Date(),
                               price: await PriceLookup.lookup(client: client, model: "claude-opus-5-5"))
        try await store.append(.cost(e), to: h.id)
        let loaded = try #require(try await store.load(h.id))
        #expect(loaded.costs.map(\.id) == [e.id] && loaded.costs.first?.purpose == .summary)
        #expect(near(loaded.costs.first?.listPrice?.total, 10 * 4e-6 + 2 * 20e-6))
    }
}

/// Run records (COST_TRACKING_DESIGN.md, phase 2): one per agent run, with its totals, setup, task, and outcome.
@Suite struct RunRecordTests {
    @Test func aMainRunWithASubagentHasRecordsLinkedByRun() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-runs-\(UUID().uuidString.prefix(6))"))
        let parent = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(parent)
        let task = #"{"description":"Find greet","prompt":"Where is greet() defined?","agent":"explore"}"#
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", task),
            SSE.toolCall("call_s1", "grep", #"{"pattern":"greet"}"#),
            SSE.content("At src/main.swift:12."),
            SSE.content("It's at src/main.swift:12."),
            SSE.content("(no rating)"),                     // the end-of-run rating request
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(recorder: SubagentRecorder(store: store, parent: parent))
        let user = ChatMessage.user("Where is greet?")
        let runID = UUID()
        config.costScope = CostScope(run: runID, agent: "main", userMessage: user.id, promptStyle: "detailed")
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [user], config: config, workspace: ws) { events.add($0) }

        let records = events.all.compactMap { if case .runEnded(let r) = $0 { r } else { nil } }
        let main = try #require(records.first)
        #expect(records.count == 1)                               // the child's record goes to its own session
        #expect(main.id == runID && main.userMessage == user.id && main.agent == "main" && main.parentRun == nil)
        // Two replies and the rating request at the end.
        #expect(main.totals.requests == 3 && main.totals.promptTokens == 300 && main.totals.unpricedRequests == 3)
        #expect(main.outcome.steps == 2 && main.outcome.toolCalls == ["task": 1] && main.outcome.stop == "completed")
        #expect(main.task.text == "Where is greet?" && main.setup.model == "m" && main.setup.tools.contains("task"))
        #expect(main.build.version == BuildInfo.version)
        // The record comes right before the end.
        let kinds = events.all.suffix(2).map { e -> String in if case .runEnded = e { "run" } else if case .finished = e { "finished" } else { "?" } }
        #expect(kinds == ["run", "finished"])

        let child = try #require(await store.subagentRuns(of: parent).first)
        let sub = try #require(child.runs.first)
        #expect(sub.id == child.header.id && sub.agent == "explore" && sub.parentRun == runID && sub.taskCall == "call_1")
        #expect(sub.totals.requests == 2 && sub.task.text == "Where is greet() defined?")
        #expect(main.children.map(\.run) == [child.header.id] && main.children.first?.requests == 2)
        let end = try #require(child.subagentEnd)
        #expect(end.agent == "explore" && end.requests == 2)
        #expect(end.taskBytes == "Find greet".utf8.count + "Where is greet() defined?".utf8.count)
        #expect((end.reportBytes ?? 0) > "At src/main.swift:12.".utf8.count)      // the report as returned, note included
        // The definition hash follows the agent's definition, not the run.
        #expect(sub.definitionHash != main.definitionHash)
    }

    @Test func promptMixAddsUpToTheReportedPrompt() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("A demo."),
        ]))
        let events = Events()
        let earlier = [ChatMessage.user("Earlier question"), ChatMessage(role: .assistant, content: "Earlier answer")]
        await AgentLoop.run(client: client, model: "m", systemPrompt: "SYSTEM PROMPT", history: earlier + [.user("What is it?")],
                            config: AgentConfig(tools: ReadTools.all), workspace: ws) { events.add($0) }
        let mix = try #require(events.costs.last?.promptMix)
        #expect(Set(mix.keys) == ["system", "tools", "earlierHistory", "userText", "assistantTurns", "toolOutputs"])
        #expect(abs(mix.values.reduce(0, +) - 100) <= 3)          // scaled to the reported 100 prompt tokens
        #expect(events.costs.first?.promptMix?["toolOutputs"] == nil)
    }

    @Test func runsExportFlattensRecords() async throws {
        let ws = try makeProject()
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-runs-\(UUID().uuidString.prefix(6))"))
        let h = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(h)
        let (client, _) = MockServer.client(.init(turns: [SSE.content("Hi, \"there\".")]))
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Say hi, please")],
                            config: AgentConfig(tools: ReadTools.all), workspace: ws) { events.add($0) }
        for case .runEnded(let r) in events.all { try await store.append(.run(r), to: h.id) }
        let rows = try await store.runRecords()
        #expect(rows.count == 1)
        let csv = DebugCommands.runsCSV(rows).split(separator: "\n")
        #expect(csv.count == 2)
        #expect(csv[0].split(separator: ",").count == DebugCommands.runColumns.count)
        #expect(csv[1].contains("Say hi, please") && csv[1].contains(",main,"))
    }
}

/// Checking entries against the provider's own records (COST_TRACKING_DESIGN.md, phase 3).
@Suite struct ReconciliationTests {
    @Test func openRouterRepliesAreCheckedAgainstTheirGenerationRecords() async throws {
        func turn(_ id: String, _ data: [Data]) -> [Data] {
            data.map { d in Data(String(decoding: d, as: UTF8.self).replacingOccurrences(of: #"{"model""#, with: #"{"id":"\#(id)","model""#).utf8) }
        }
        let generation = #"{"data":{"id":"gen-7","total_cost":0.00042,"native_tokens_prompt":104,"native_tokens_completion":12,"native_tokens_reasoning":0,"native_tokens_cached":64,"provider_name":"Solid","model":"vendor/model"}}"#
        let models = #"{"data":[{"id":"vendor/model","pricing":{"prompt":"0.000003","completion":"0.000015","input_cache_read":"0.0000003"}}]}"#
        var route = MockServer.Route(turns: [turn("gen-7", SSE.content("A demo."))])
        route.gets = ["generation": Data(generation.utf8), "models": Data(models.utf8)]
        let (client, host) = MockServer.client(route)
        var config = AgentConfig(tools: ReadTools.all)
        config.generationLookupDelays = [0.01]
        let events = Events()
        await AgentLoop.run(client: client, model: "vendor/model", systemPrompt: "S", history: [.user("What is it?")], config: config,
                            workspace: try makeProject()) { events.add($0) }
        // The entry, then the same entry with the provider's record, before the run's record.
        let costs = events.costs
        #expect(costs.count == 2 && costs[0].id == costs[1].id)
        #expect(costs[0].reconciled == nil && costs[0].charged == nil)
        let r = try #require(costs[1].reconciled)
        #expect(r.charged == 0.00042 && costs[1].charged == 0.00042 && r.provider == "Solid")
        #expect(r.nativePromptTokens == 104 && r.nativeCachedTokens == 64)
        // List price from the streamed counts (100 in, 10 out) and from the native ones (104 in, 64 of them cached, 12 out).
        let streamed: Double = 100 * 3e-6 + 10 * 15e-6
        let native: Double = 40 * 3e-6 + 64 * 0.3e-6 + 12 * 15e-6
        #expect(near(costs[1].listPrice?.total, streamed))
        #expect(near(r.nativeListPrice?.total, native))
        #expect(MockServer.getRequests(host).contains { $0.query()?.contains("id=gen-7") == true })
        let record = try #require(events.all.compactMap { e -> AgentRunRecord? in if case .runEnded(let x) = e { x } else { nil } }.first)
        #expect(record.totals.reconciledRequests == 1 && record.totals.charged == 0.00042)
    }

    @Test func aLaterRecordOfAnEntryReplacesItInTheSession() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-rec-\(UUID().uuidString.prefix(6))"))
        let h = SessionHeader(endpointID: UUID(), model: "m", workspace: nil)
        try await store.create(h)
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: "m", usage: Usage(promptTokens: 10, completionTokens: 2), stopReason: .completed, duration: 1)
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        let e = CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: nil, start: Date(), price: .unknown("x"))
        var later = e
        later.charged = 0.5
        try await store.append(.cost(e), to: h.id)
        try await store.append(.cost(later), to: h.id)
        let loaded = try #require(try await store.load(h.id))
        #expect(loaded.costs.count == 1 && loaded.costs.first?.charged == 0.5)
    }
}

/// `kurtkode cost check` and `cost calibrate` (phase 3).
@Suite struct CostCommandTests {
    final class Out: @unchecked Sendable {
        let lock = NSLock()
        var text = ""
        func add(_ s: String) { lock.withLock { text += s } }
    }

    func settings() -> AppSettings {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-costcmd-\(UUID().uuidString.prefix(6))")
        var s = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-costcmd-\(UUID().uuidString)")!, environment: [:])
        s.endpoints.append(Endpoint(name: "Claude", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!))
        return s
    }

    func entry(_ day: String, hour: Int, model: String, endpoint: Endpoint, prompt: Int, read: Int = 0, output: Int) -> CostEntry {
        let f = ISO8601DateFormatter()
        let at = f.date(from: "\(day)T\(String(format: "%02d", hour)):00:00Z")!
        var m = ChatMessage(role: .assistant, content: "x")
        m.meta = TurnMeta(requestedModel: model, usage: Usage(promptTokens: prompt, completionTokens: output, cacheReadTokens: read),
                          stopReason: .completed, duration: 1)
        let client = ChatClient(endpoint: endpoint)
        let p = PriceList.price(api: .anthropic, model: model).map { PriceLookup.known($0, source: "test", version: "t") } ?? .unknown("x")
        return CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: endpoint.id, start: at, price: p)
    }

    @Test func checkSumsADayByEndpointAndModel() async throws {
        let settings = settings()
        let claude = try #require(settings.endpoint(named: "Claude"))
        let store = settings.sessionStore
        let h = SessionHeader(endpointID: claude.id, model: "claude-opus-5-5", workspace: nil)
        try await store.create(h)
        for e in [entry("2026-10-20", hour: 1, model: "claude-opus-5-5", endpoint: claude, prompt: 1000, read: 600, output: 100),
                  entry("2026-10-20", hour: 23, model: "claude-opus-5-5", endpoint: claude, prompt: 2000, output: 50),
                  entry("2026-10-20", hour: 5, model: "claude-haiku-5-5", endpoint: claude, prompt: 500, output: 10),
                  entry("2026-10-21", hour: 1, model: "claude-opus-5-5", endpoint: claude, prompt: 9999, output: 9)] {
            try await store.append(.cost(e), to: h.id)
        }
        let out = Out()
        let status = await DebugCommands.run(["cost", "check", "--day", "2026-10-20", "--json"], settings: settings,
                                             cwd: FileManager.default.temporaryDirectory) { out.add($0) }
        #expect(status == 0)
        guard case .array(let rows)? = try? JSONDecoder().decode(JSONValue.self, from: Data(out.text.utf8)) else { Issue.record(Comment(rawValue: out.text)); return }
        #expect(rows.count == 2)
        guard case .object(let opus)? = rows.first(where: { if case .object(let o) = $0 { o["model"] == "claude-opus-5-5" } else { false } }) else {
            Issue.record("no opus row"); return
        }
        #expect(opus["requests"] == 2 && opus["uncachedInput"] == 2400 && opus["cacheRead"] == 600 && opus["output"] == 150)
        let expected = 2400 * 4e-6 + 600 * 0.2e-6 + 150 * 20e-6
        if case .number(let p)? = opus["listPrice"] { #expect(abs(p - expected) < 1e-12) } else { Issue.record("no list price") }
        #expect(opus["endpoint"] == "Claude")
        // In another time zone the late request falls on the next day.
        let shifted = Out()
        _ = await DebugCommands.run(["cost", "check", "--day", "2026-10-20", "--tz", "Asia/Tokyo", "--json"], settings: settings,
                                    cwd: FileManager.default.temporaryDirectory) { shifted.add($0) }
        guard case .array(let later)? = try? JSONDecoder().decode(JSONValue.self, from: Data(shifted.text.utf8)) else { Issue.record("no JSON"); return }
        let opusLater = later.first { if case .object(let o) = $0 { o["model"] == "claude-opus-5-5" } else { false } }
        if case .object(let o)? = opusLater { #expect(o["requests"] == 1) } else { Issue.record("no opus row") }
    }

    @Test func calibrateWithoutYesOnlyShowsThePlan() async throws {
        let settings = settings()
        let out = Out()
        let status = await DebugCommands.run(["cost", "calibrate", "-m", "Claude:claude-opus-5-5"], settings: settings,
                                             cwd: FileManager.default.temporaryDirectory) { out.add($0) }
        #expect(status == 0)
        #expect(out.text.contains("Would send 3 requests to claude-opus-5-5 on Claude"))
        #expect(out.text.contains("at list price") && out.text.contains("--yes"))
        #expect(try await settings.sessionStore.list().isEmpty)              // nothing sent, nothing recorded
        #expect(DebugCommands.calibrationPrefix.utf8.count > 18_000)       // about 9k tokens
    }
}

/// The follow-ups to the calibration: OpenRouter records checked later, and Claude's cache on OpenRouter.
@Suite struct CalibrationFollowUpTests {
    @Test func pendingOpenRouterRecordsAreCheckedLater() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-recon-\(UUID().uuidString.prefix(6))"))
        let h = SessionHeader(endpointID: UUID(), model: "vendor/model", workspace: nil)
        try await store.create(h)
        let endpointID = UUID()
        func entry(_ gen: String, ageSeconds: Double) -> CostEntry {
            var m = ChatMessage(role: .assistant, content: "x")
            m.meta = TurnMeta(requestedModel: "vendor/model", usage: Usage(promptTokens: 100, completionTokens: 10), stopReason: .completed, duration: 1)
            m.meta?.requestIDs = [gen]
            let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
            return CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: endpointID,
                                  start: Date().addingTimeInterval(-ageSeconds - 1), price: .unknown("x"))
        }
        try await store.append(.cost(entry("gen-old", ageSeconds: 600)), to: h.id)
        try await store.append(.cost(entry("gen-new", ageSeconds: 0)), to: h.id)        // too recent: left for later
        var route = MockServer.Route()
        route.gets = ["generation": Data(#"{"data":{"id":"gen-old","total_cost":0.0007,"native_tokens_prompt":100,"native_tokens_completion":10}}"#.utf8)]
        let (mock, _) = MockServer.client(route)
        let (checked, pending) = await CostReconciler.run(store: store, since: Date().addingTimeInterval(-86_400), minAge: 60,
                                                          client: { $0 == endpointID ? mock : nil })
        #expect(checked == 1 && pending == 1)
        let s = try #require(try await store.load(h.id))
        #expect(s.costs.count == 2)
        #expect(s.costs.first { $0.requestIDs == ["gen-old"] }?.charged == 0.0007)
        #expect(s.costs.first { $0.requestIDs == ["gen-new"] }?.reconciled == nil)
        // Checked entries aren't looked up again.
        let again = await CostReconciler.run(store: store, since: Date().addingTimeInterval(-86_400), minAge: 60, client: { _ in mock })
        #expect(again.pending == 0)
    }

    @Test func claudeOnOpenRouterMarksCacheBreakpoints() throws {
        var call = ChatMessage(role: .assistant, content: "")
        call.toolCalls = [ToolCall(id: "c1", name: "read_file", arguments: "{}")]
        let messages: [ChatMessage] = [.system("SYSTEM"), .user("Read it."), call, ChatMessage(role: .tool, content: "file text", toolCallID: "c1")]
        func body(_ base: String, _ model: String, hour: Bool = false) throws -> [JSONValue] {
            var r = ChatRequest(model: model, messages: messages, maxTokens: 100)
            r.cacheForAnHour = hour
            let data = try ChatClient(baseURL: URL(string: base)!, api: .openai).encode(r)
            guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let ms)? = o["messages"] else { return [] }
            return ms
        }
        let marked = try body("https://openrouter.ai/api/v1", "anthropic/claude-haiku-4.5")
        let ephemeral: JSONValue = ["type": "ephemeral"]
        #expect(marked[0] == ["role": "system", "content": [["type": "text", "text": "SYSTEM", "cache_control": ephemeral]]])
        #expect(marked[3] == ["role": "tool", "tool_call_id": "c1", "content": [["type": "text", "text": "file text", "cache_control": ephemeral]]])
        #expect(marked[1] == ["role": "user", "content": "Read it."])          // only the last user or tool message
        let hour = try body("https://openrouter.ai/api/v1", "anthropic/claude-haiku-4.5", hour: true)
        #expect(String(describing: hour[0]).contains("1h"))
        // Other models on OpenRouter, and other servers, send plain text as before.
        #expect(try body("https://openrouter.ai/api/v1", "google/gemini-3-flash")[0] == ["role": "system", "content": "SYSTEM"])
        #expect(try body("http://127.0.0.1:1234/v1", "anthropic/claude-haiku-4.5")[0] == ["role": "system", "content": "SYSTEM"])
    }
}

/// The displays read the cost records (summaries and retried attempts included), not the replies' usage.
@Suite struct CostDisplayTests {
    func entry(_ purpose: CostEntry.Purpose, list: Double?, charged: Double? = nil, run: UUID? = nil, reply: UUID = UUID()) -> CostEntry {
        var m = ChatMessage(role: .assistant, content: "x")
        m.id = reply
        m.meta = TurnMeta(requestedModel: "claude-opus-5-5", usage: Usage(promptTokens: 1, completionTokens: 1), stopReason: .completed, duration: 1)
        let client = ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, api: .anthropic)
        var e = CostEntry.make(reply: m, purpose: purpose, run: run, agent: "main", client: client, endpointID: nil, start: Date(),
                               price: .unknown("x"))
        if let list { e.listPrice = CostBreakdown(Usage(promptTokens: 0, completionTokens: 0), price: PriceList.price(api: .anthropic, model: "claude-opus-5-5")!,
                                                  source: "t", priceList: "t"); e.listPrice?.total = list }
        e.charged = charged
        return e
    }

    @Test func summaryCountsChargesFirstAndSummaries() {
        let s = CostSummary([entry(.reply, list: 0.10), entry(.summary, list: 0.02), entry(.retryAttempt, list: 0.01, charged: 0.012),
                             entry(.reply, list: nil)])
        #expect(abs(s.spent - 0.132) < 1e-12 && s.estimated && s.unpricedRequests == 1 && s.requests == 4)
        #expect(s.byPurpose[.summary] == 0.02 && s.chargedRequests == 1)
        #expect(s.spentText() == "≈$0.1320")
        #expect(CostSummary([entry(.reply, list: 0.1, charged: 0.1)]).spentText() == "$0.1000")
    }

    @Test func meterJournalAndRendererUseTheRecords() async throws {
        var session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil), messages: [], model: "m")
        let run = UUID()
        session.costs = [entry(.reply, list: 0.05, run: run), entry(.summary, list: 0.01, run: run)]
        #expect(abs(CostMeter.spent(session) - 0.06) < 1e-12)                     // summaries count toward limits
        #expect(abs(SessionJournal(session: session, contexts: []).summaryCost - 0.01) < 1e-12)

        final class Out: @unchecked Sendable { var text = ""; let lock = NSLock() }
        let out = Out()
        let r = Renderer(style: .interactive, out: { s in out.lock.withLock { out.text += s } }, err: { _ in })
        for e in session.costs { r.handle(.cost(e)) }
        var record = try #require(await runRecord(run))
        record.id = run
        r.handle(.runEnded(record))
        #expect(out.text.contains("≈$0.0600 this run · 2 requests, summaries $0.0100"))
    }

    /// A run record for a run with no requests of its own (the renderer only needs its id and children).
    func runRecord(_ id: UUID) async -> AgentRunRecord? {
        let (client, _) = MockServer.client(.init(turns: [SSE.content("ok")]))
        final class Box: @unchecked Sendable { var r: AgentRunRecord? }
        let box = Box()
        var config = AgentConfig(tools: [])
        config.costScope = CostScope(run: id, agent: "main")
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("x")], config: config, workspace: nil) { e in
            if case .runEnded(let r) = e { box.r = r }
        }
        return box.r
    }
}
