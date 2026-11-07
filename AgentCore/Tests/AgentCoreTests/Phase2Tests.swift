import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit
@testable import KurtkodeCLI

// Phase 2 of GAP_ANALYSIS.md (cost in sessions): A1 pool and capabilities, A2 defaults and retry, A3 main-run signals,
// A5 spending.

extension ModelPool {
    /// The shipped pool as it was before 2026-11-04, with deepseek-v4-flash-0731 (reasoning off) a subagent on the
    /// ladder's middle rung: three rungs and a reasoning-pinned one, for the ladder's own tests.
    static var threeRungs: ModelPool {
        var pool = ModelPool.shipped
        let i = pool.entries.firstIndex { $0.model == "deepseek/deepseek-v4-flash-0731" }!
        pool.entries[i].roles.insert(.subagent)
        pool.entries[i].ladder = 1
        pool.entries[pool.entries.firstIndex { $0.model == "haiku" }!].ladder = 2
        return pool
    }
}

private func object(_ json: String) -> [String: JSONValue] {
    guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else { return [:] }
    return o
}

@Suite struct ListedCapabilitiesTests {
    @Test func readsOpenRoutersModelEntry() throws {
        let m = try #require(ListedModel.openAI(object(#"""
            {"id": "inclusionai/ling-3.0-flash", "name": "inclusionAI: Ling 3.0 Flash", "context_length": 131072,
             "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
             "top_provider": {"context_length": 131072, "max_completion_tokens": 32768},
             "supported_parameters": ["max_tokens", "temperature", "tools", "tool_choice", "reasoning"],
             "pricing": {"prompt": "0.00000007", "completion": "0.00000028", "input_cache_read": "0.000000014"}}
            """#)))
        #expect(m.contextLength == 131_072)
        #expect(m.maxOutputTokens == 32_768)
        #expect(m.supportsTools == true)
        #expect(m.supportsReasoning == true)
        #expect(m.supportsImages == false)
        #expect(abs((m.price?.standard.input ?? 0) - 0.07) < 1e-9)
        #expect(abs((m.price?.standard.cacheRead ?? 0) - 0.014) < 1e-9)
    }

    @Test func modelsWithoutToolsOrWithImagesSaySo() throws {
        let m = try #require(ListedModel.openAI(object(#"""
            {"id": "x/vision-chat", "context_length": 64000, "architecture": {"input_modalities": ["text", "image"]},
             "supported_parameters": ["max_tokens"], "pricing": {"prompt": "-1", "completion": "-1"}}
            """#)))
        #expect(m.supportsTools == false)
        #expect(m.supportsReasoning == false)
        #expect(m.supportsImages == true)
        #expect(m.price == nil)                       // a router's -1: no price of its own
    }

    @Test func plainServersLeaveCapabilitiesUnknown() throws {
        let lmstudio = try #require(ListedModel.openAI(object(#"{"id": "google/gemma-4-26b", "object": "model", "owned_by": "organization_owner"}"#)))
        #expect(lmstudio.contextLength == nil && lmstudio.supportsTools == nil && lmstudio.supportsImages == nil && lmstudio.price == nil)
        let vllm = try #require(ListedModel.openAI(object(#"{"id": "Qwen/Qwen3-32B", "owned_by": "vllm", "max_model_len": 40960}"#)))
        #expect(vllm.contextLength == 40_960)
        #expect(vllm.supportsTools == nil)
    }

    @Test func readsOllamasShow() {
        var m = ListedModel(id: "qwen3:8b")
        m.absorbOllama(object(#"""
            {"model_info": {"general.architecture": "qwen3", "qwen3.context_length": 131072, "qwen3.embedding_length": 4096},
             "parameters": "num_ctx 40960", "capabilities": ["completion", "tools", "thinking"]}
            """#))
        #expect(m.contextLength == 40_960)
        #expect(m.supportsTools == true)
        #expect(m.supportsReasoning == true)
        #expect(m.supportsImages == false)
    }

    @Test func pricesStillParseFromTheWholeList() {
        let data = Data(#"{"data": [{"id": "a/b", "pricing": {"prompt": "0.000001", "completion": "0.000002"}}, {"id": "c/d"}]}"#.utf8)
        let prices = RemotePrices.parse(data)
        #expect(prices.count == 1)
        #expect(prices["a/b"]?.standard.output == 2)
    }
}

@Suite struct ReasoningSettingTests {
    private func body(_ setting: String?, base: String) throws -> [String: JSONValue] {
        var request = ChatRequest(model: "m", messages: [.user("hi")], tools: [], maxTokens: 100)
        ReasoningSetting.apply(setting, to: &request, client: ChatClient(baseURL: URL(string: base)!))
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: WireFormat.encodeRequest(request)) else { return [:] }
        return o
    }

    @Test func openRouterGetsItsReasoningObject() throws {
        let off = try body("none", base: "https://openrouter.ai/api/v1")
        #expect(off["reasoning"] == ["enabled": false])
        #expect(off["reasoning_effort"] == nil)
        #expect(try body("high", base: "https://openrouter.ai/api/v1")["reasoning"] == ["effort": "high"])
    }

    @Test func otherServersGetReasoningEffort() throws {
        #expect(try body("off", base: "http://127.0.0.1:1234/v1")["reasoning_effort"] == "none")
        #expect(try body("Low", base: "http://127.0.0.1:1234/v1")["reasoning_effort"] == "low")
        let unset = try body(nil, base: "http://127.0.0.1:1234/v1")
        #expect(unset["reasoning_effort"] == nil && unset["reasoning"] == nil)
        #expect(ReasoningSetting.label("none") == "off" && ReasoningSetting.label(nil) == "default")
    }

    @Test func theLoopSendsAndRecordsTheProfilesSetting() async throws {
        let (client, host) = MockServer.client(.init(turns: [SSE.content("Hi.")]))
        var config = AgentConfig(tools: [])
        config.reasoningEffort = "none"
        config.costScope = CostScope(run: UUID(), agent: "main")
        final class Box: @unchecked Sendable { var run: AgentRunRecord? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: nil) { if case .runEnded(let r) = $0 { box.run = r } }
        let sent = try #require(MockServer.requestBody(host))
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: sent) else { Issue.record("shape"); return }
        #expect(o["reasoning_effort"] == "none")
        #expect(box.run?.setup.reasoning == "none")

        // The eval's own object wins, and is what's recorded.
        let (c2, h2) = MockServer.client(.init(turns: [SSE.content("Hi.")]))
        config.reasoning = ["enabled": false]
        await AgentLoop.run(client: c2, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: nil) { if case .runEnded(let r) = $0 { box.run = r } }
        guard case .object(let o2) = try JSONDecoder().decode(JSONValue.self, from: try #require(MockServer.requestBody(h2))) else { return }
        #expect(o2["reasoning"] == ["enabled": false] && o2["reasoning_effort"] == nil)
        #expect(box.run?.setup.reasoning == #"{"enabled":false}"#)
    }

    @Test func oldProfilesDecodeWithoutTheField() throws {
        let p = ModelProfile(endpointID: UUID(), model: "m")
        var json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        json = json.replacingOccurrences(of: #","reasoning":null"#, with: "")
        #expect(try JSONDecoder().decode(ModelProfile.self, from: Data(json.utf8)).reasoning == nil)
    }
}

@Suite struct ModelPoolTests {
    let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
    let anthropic = Endpoint(name: "Anthropic", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!, usesAPIKey: true)
    let local = Endpoint.localLMStudio

    @Test func shippedEntriesResolveToWhatTheUserHas() {
        let pool = ModelPool.shipped
        #expect(pool.available(.subagent, endpoints: [local]).isEmpty)
        let both = pool.available(.subagent, endpoints: [local, openRouter, anthropic]).map(\.model)
        #expect(both == ["inclusionai/ling-3.0-flash", "claude-haiku-5-5"])     // deepseek-off reviews only
        // Without Anthropic's API, the Claude entries go through OpenRouter.
        #expect(pool.available(.judge, endpoints: [openRouter]).map(\.model) == ["anthropic/claude-haiku-5.5"])
        #expect(pool.available(.judge, endpoints: [openRouter, anthropic]).first?.endpoint.id == anthropic.id)
        // The OpenRouter entries keep to providers that don't keep prompts, as the study ran.
        #expect(pool.entries[0].providers?.dataCollection == "deny")
    }

    @Test func picksTheLowestTierThatsHighEnough() {
        let pool = ModelPool.shipped, eps = [openRouter, anthropic]
        #expect(pool.pick(.subagent, atLeast: .cheap, endpoints: eps)?.model == "inclusionai/ling-3.0-flash")
        #expect(pool.pick(.subagent, atLeast: .standard, endpoints: eps)?.model == "claude-haiku-5-5")
        #expect(pool.pick(.subagent, atLeast: .frontier, endpoints: eps) == nil)      // sonnet isn't a subagent entry
        #expect(pool.pick(.main, atLeast: .frontier, endpoints: eps)?.model == "claude-sonnet-5-5")
        var off = pool
        off.entries[0].enabled = false
        #expect(off.pick(.subagent, atLeast: .cheap, endpoints: eps)?.model == "claude-haiku-5-5")
    }

    @Test func theLadderGoesUpNeverSideways() {
        let eps = [openRouter, anthropic]
        #expect(ModelPool.shipped.next(after: openRouter.id, model: "inclusionai/ling-3.0-flash", reasoning: nil, endpoints: eps)?.model
                == "claude-haiku-5-5")
        let pool = ModelPool.threeRungs
        let first = pool.next(after: openRouter.id, model: "inclusionai/ling-3.0-flash", reasoning: nil, endpoints: eps)
        #expect(first?.model == "deepseek/deepseek-v4-flash-0731" && first?.entry.reasoning == "none")
        #expect(pool.next(after: openRouter.id, model: "deepseek/deepseek-v4-flash-0731", reasoning: "none", endpoints: eps)?.model
                == "claude-haiku-5-5")
        #expect(pool.next(after: anthropic.id, model: "claude-haiku-5-5", reasoning: nil, endpoints: eps) == nil)
        // deepseek with reasoning on isn't a rung: it goes above its entry's tier (cheap), not sideways to ling.
        #expect(pool.next(after: openRouter.id, model: "deepseek/deepseek-v4-flash-0731", reasoning: nil, endpoints: eps)?.model
                == "claude-haiku-5-5")
        #expect(pool.next(after: local.id, model: "gemma", reasoning: nil, tier: .local, endpoints: eps)?.model == "inclusionai/ling-3.0-flash")
        #expect(pool.next(after: local.id, model: "gemma", reasoning: nil, tier: .standard, endpoints: eps) == nil)
        #expect(pool.next(after: local.id, model: "gemma", reasoning: nil, endpoints: eps) == nil)   // tier unknown: nowhere
    }

    @Test func savesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kk-pool-\(UUID().uuidString.prefix(8)).json")
        #expect(ModelPool.load(url) == .shipped)                // nothing saved: the shipped pool
        var pool = ModelPool.shipped
        pool.entries.append(PoolEntry(endpoint: local.id.uuidString, model: "google/gemma-4-26b", tier: .local, roles: [.subagent]))
        try pool.save(url)
        #expect(ModelPool.load(url) == pool)
        #expect(ModelPool.resolve(pool.entries.last!, endpoints: [local])?.endpoint.id == local.id)
        try Data("not json".utf8).write(to: url)
        #expect(ModelPool.load(url).entries.isEmpty)            // unreadable: nothing routed until it's fixed (R6-4)
    }

    @Test func typicalTaskCost() {
        // ling-3.0-flash's listing: $0.021 / $0.063, cache reads $0.0042 a million tokens.
        let rates = PriceList.Rates(input: 0.021, output: 0.063, cacheRead: 0.0042, cacheWrite5m: 0.021, cacheWrite1h: 0.021)
        let p = PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil)
        let expected = (7_000 * 0.021 + 13_000 * 0.0042 + 900 * 0.063) / 1e6
        #expect(abs(TypicalTask.cost(p) - expected) < 1e-12)
        #expect(TypicalTask.label(p) == "$0.02 / $0.06 per M tokens · ≈$0.0003 a task")
    }
}

// MARK: A2 defaults and retry

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
    var started: [SubagentInfo] { all.compactMap { if case .subagentStarted(let i) = $0 { i } else { nil } } }
    var ends: [(UUID, SubagentEnd)] { all.compactMap { if case .subagentFinished(let id, let e) = $0 { (id, e) } else { nil } } }
    var runs: [AgentRunRecord] { all.compactMap { if case .runEnded(let r) = $0 { r } else { nil } } }
}

@Suite struct SubagentRoutingTests {
    let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
    let anthropic = Endpoint(name: "Anthropic", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!, usesAPIKey: true)
    let local = Endpoint.localLMStudio

    @Test func theCardPicksTheTier() {
        #expect(SubagentRouting.tier(for: TaskCard()) == .cheap)
        #expect(SubagentRouting.tier(for: TaskCard(importance: .high)) == .standard)
        #expect(SubagentRouting.tier(for: TaskCard(importance: .high, tier: .cheap)) == .cheap)   // an explicit tier wins
        #expect(SubagentRouting.tier(for: TaskCard(tier: .strong)) == .frontier)
    }

    @Test func theRetryLadderIsOffUnlessTurnedOn() {
        #expect(!RunSettings().subagentRetry)
        let d = UserDefaults(suiteName: "kk-retry-\(UUID().uuidString)")!
        #expect(!RunSettings(defaults: d).subagentRetry)
        d.set(true, forKey: RunSettings.Key.subagentRetry)
        #expect(RunSettings(defaults: d).subagentRetry)
    }

    @Test func codeChangingTasksDefaultToTheStandardTier() {
        for kind in [TaskCard.Kind.edit, .refactor, .fix, .writeTests] {
            #expect(SubagentRouting.tier(for: TaskCard(kind: kind)) == .standard)
            #expect(SubagentRouting.tier(for: TaskCard(kind: kind, tier: .cheap)) == .cheap)   // an explicit tier still wins
        }
        for kind in [TaskCard.Kind.search, .explain, .summarize, .review, .research, .run] {
            #expect(SubagentRouting.tier(for: TaskCard(kind: kind)) == .cheap)
        }
        let eps = [openRouter, anthropic]
        #expect(SubagentRouting.automatic(card: TaskCard(kind: .edit), main: anthropic, mainModel: "claude-opus-5-5",
                                          pool: .shipped, endpoints: eps)?.model == "claude-haiku-5-5")
        #expect(SubagentRouting.automatic(card: TaskCard(kind: .search), main: anthropic, mainModel: "claude-opus-5-5",
                                          pool: .shipped, endpoints: eps)?.model == "inclusionai/ling-3.0-flash")
    }

    @Test func remoteSessionsGetThePoolLocalOnesDont() {
        let eps = [local, openRouter, anthropic], pool = ModelPool.shipped
        #expect(SubagentRouting.automatic(card: TaskCard(), main: anthropic, mainModel: "claude-opus-5-5", pool: pool,
                                          endpoints: eps)?.model == "inclusionai/ling-3.0-flash")
        #expect(SubagentRouting.automatic(card: TaskCard(importance: .high), main: anthropic, mainModel: "claude-opus-5-5",
                                          pool: pool, endpoints: eps)?.model == "claude-haiku-5-5")
        // A task that wants the strongest model stays on the main model (no frontier subagent entry).
        #expect(SubagentRouting.automatic(card: TaskCard(tier: .strong), main: anthropic, mainModel: "claude-opus-5-5",
                                          pool: pool, endpoints: eps) == nil)
        // A local session: nothing leaves the Mac.
        #expect(SubagentRouting.automatic(card: TaskCard(), main: local, mainModel: "gemma", pool: pool, endpoints: eps) == nil)
        #expect(SubagentRouting.retry(after: local.id, model: "gemma", reasoning: nil, routed: true, main: local, pool: pool, endpoints: eps) == nil)
        #expect(SubagentRouting.grader(main: local, runEndpointID: nil, runModel: "x", pool: pool, endpoints: eps) == nil)
        #expect(SubagentRouting.grader(main: openRouter, runEndpointID: nil, runModel: "x", pool: pool, endpoints: eps)?.model == "claude-haiku-5-5")
        // The main model itself isn't handed back as a subagent model.
        #expect(SubagentRouting.automatic(card: TaskCard(), main: openRouter, mainModel: "inclusionai/ling-3.0-flash", pool: pool,
                                          endpoints: eps) == nil)
    }

    @Test func settingsSayAutomaticUntilAModelOrTheSessionsOwnIsChosen() throws {
        let d = try #require(UserDefaults(suiteName: "kk-test-\(UUID().uuidString)"))
        #expect(RunSettings(defaults: d).subagentAutomatic && RunSettings(defaults: d).graderAutomatic)
        d.set("", forKey: RunSettings.Key.subagentModel)
        d.set("", forKey: RunSettings.Key.graderModel)
        #expect(!RunSettings(defaults: d).subagentAutomatic && !RunSettings(defaults: d).graderAutomatic)
        d.set("auto", forKey: RunSettings.Key.subagentModel)
        #expect(RunSettings(defaults: d).subagentAutomatic)
        d.set(ModelRef(endpointID: UUID(), model: "m").key, forKey: RunSettings.Key.subagentModel)
        #expect(!RunSettings(defaults: d).subagentAutomatic && RunSettings(defaults: d).subagentModel != nil)
    }

    @Test func theResolverGetsTheCard() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Check","prompt":"Look","agent":"explore","importance":"high","tier":"standard"}"#),
            SSE.content("Done."),
        ]))
        let (sub, _) = MockServer.client(.init(turns: [SSE.content("Looked.")]))
        final class Box: @unchecked Sendable { var card: TaskCard? }
        let box = Box()
        var config = AgentConfig(tools: AllTools.all)
        config.subagents = SubagentSetup(resolveModel: { _, card in box.card = card; return SubagentModel(client: sub, model: "s") })
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { _ in }
        #expect(box.card == TaskCard(importance: .high, tier: .standard))
    }
}

@Suite struct SubagentRetryTests {
    /// The main agent calls `task` once; the first model's run writes a file and then reports made-up citations (a hard
    /// failure); the second model's run reports cleanly.
    private func run(retry: Bool, firstTurns: [[Data]], verify: String? = nil, limit: Double? = nil, important: Bool = false,
                     configure: (inout AgentConfig) -> Void = { _ in }) async throws -> (Events, Workspace, [String]) {
        let ws = try makeProject()
        let card = (verify.map { #","verify":"\#($0)""# } ?? "") + (important ? #","importance":"high""# : "")
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Note it","prompt":"Write the note","agent":"general"\#(card)}"#),
            SSE.content("Done."),
        ]))
        let (first, _) = MockServer.client(.init(turns: firstTurns))
        let (second, secondHost) = MockServer.client(.init(turns: [SSE.content("Wrote nothing; all is well.", model: "rung-2")]))
        var config = AgentConfig(tools: AllTools.all, approve: { _ in .allow }, shell: ShellState(cwd: ws.root))
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: first, model: "rung-1", reasoning: "none") })
        final class Asked: @unchecked Sendable { var args: [String] = [] }
        let asked = Asked()
        if retry {
            config.subagents?.retryModel = { _, _, model, reasoning in
                asked.args.append("\(model)|\(reasoning ?? "")")
                return SubagentModel(client: second, model: "rung-2")
            }
        }
        if let limit { config.costMeter = CostMeter(runLimit: limit, sessionLimit: nil, sessionBefore: 0) }
        configure(&config)
        let events = Events()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { events.add($0) }
        _ = secondHost
        return (events, ws, asked.args)
    }

    private let madeUp: [[Data]] = [
        SSE.toolCall("w1", "write_file", #"{"path":"NOTE.md","content":"draft\n"}"#),
        SSE.content("Done: see ghost.py:10 and phantom.swift:3 for where it's used.", model: "rung-1"),
    ]

    @Test func aHardFailureIsTriedOnceMoreOnTheNextRungWithItsEditsUndone() async throws {
        let (events, ws, asked) = try await run(retry: true, firstTurns: madeUp)
        #expect(asked == ["rung-1|none"])                                  // asked with the failed model's settings
        #expect(events.started.map(\.model) == ["rung-1", "rung-2"])
        #expect(Set(events.started.map(\.callID)) == ["call_1"])
        let ends = events.ends
        #expect(ends.count == 2)
        #expect(ends[1].1.attemptOf == ends[0].0)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "NOTE.md").path))   // undone
        let result = try #require(events.results.first?.content)
        #expect(result.hasPrefix("[The first attempt, on rung-1, failed (made-up citations"))
        #expect(result.contains("its edits were undone") && result.contains("second attempt, on rung-2"))
        #expect(result.contains("Wrote nothing; all is well."))
        #expect(events.all.contains { if case .status(let s) = $0 { s.contains("trying again on rung-2") } else { false } })
    }

    @Test func bothAttemptsAreRecordedAndLinked() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-retry-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: nil)
        try await store.create(header)
        let (events, _, _) = try await run(retry: true, firstTurns: madeUp) { config in
            config.subagents?.recorder = SubagentRecorder(store: store, parent: header)
        }
        let runs = await store.subagentRuns(of: header)
        #expect(runs.count == 2)
        let failed = try #require(runs.first { $0.model == "rung-1" }), retried = try #require(runs.first { $0.model == "rung-2" })
        #expect(retried.subagentEnd?.attemptOf == failed.header.id)
        #expect(retried.runs.first?.attemptOf == failed.header.id)
        #expect(failed.judgments.first?.checks?.isHardFailure == true)          // the failed attempt is labeled 0
        #expect(failed.judgments.first?.label == 0)
        #expect(events.ends.count == 2)
    }

    /// B8 of the cost audit: the failed attempt isn't graded when it will be tried again; its retry is.
    @Test func aRunAboutToBeRetriedIsNotGraded() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-retry-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: nil)
        try await store.create(header)
        final class Graded: @unchecked Sendable { var models: [String] = [] }
        let graded = Graded()
        let (events, _, _) = try await run(retry: true, firstTurns: madeUp, important: true) { config in
            config.subagents?.recorder = SubagentRecorder(store: store, parent: header)
            config.subagents?.grader = { _, model in graded.models.append(model); return nil }
        }
        #expect(events.ends.count == 2)
        #expect(graded.models == ["rung-2"])
    }

    @Test func theSecondAttemptIsToldWhatFailed() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Note it","prompt":"Write the note","agent":"general"}"#), SSE.content("Done."),
        ]))
        let (first, _) = MockServer.client(.init(turns: madeUp))
        let (second, secondHost) = MockServer.client(.init(turns: [SSE.content("OK.")]))
        var config = AgentConfig(tools: AllTools.all, approve: { _ in .allow }, shell: ShellState(cwd: ws.root))
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: first, model: "a") })
        config.subagents?.retryModel = { _, _, _, _ in SubagentModel(client: second, model: "b") }
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { _ in }
        let body = String(decoding: try #require(MockServer.requestBodies(secondHost).first), as: UTF8.self)
        #expect(body.contains("Write the note"))
        #expect(body.contains("an earlier attempt at this task, on another model, failed: made-up citations"))
        #expect(body.contains("Its edits were undone: NOTE.md"))
    }

    @Test func noRetryWithoutALadderAFailedCheckOrAtTheLimit() async throws {
        // No ladder: the failure goes back to the parent as it was.
        let (e1, ws1, _) = try await run(retry: false, firstTurns: madeUp)
        #expect(e1.started.count == 1)
        #expect(FileManager.default.fileExists(atPath: ws1.root.appending(path: "NOTE.md").path))
        // A failed check is the parent's call, not a retry.
        let failing: [[Data]] = [SSE.toolCall("b1", "bash", #"{"command":"exit 3"}"#), SSE.content("Ran it; it failed.")]
        let (e2, _, asked2) = try await run(retry: true, firstTurns: failing, verify: "exit 3")
        #expect(e2.started.count == 1 && asked2.isEmpty)
        // Spending at its limit (reached as the subagent starts): no second attempt.
        let (e3, _, asked3) = try await run(retry: true, firstTurns: madeUp, limit: 0.5) { config in
            let meter = config.costMeter, first = config.subagents?.resolveModel
            config.subagents?.resolveModel = { a, c in meter?.add(Usage(promptTokens: 1, completionTokens: 1, cost: 0.6)); return await first?(a, c) }
        }
        #expect(e3.started.count == 1 && asked3.isEmpty)
    }

    @Test func aRetryIsNeverRetriedAgain() async throws {
        let ws = try makeProject()
        let (main, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Note it","prompt":"Write the note","agent":"general"}"#), SSE.content("Done."),
        ]))
        let (first, _) = MockServer.client(.init(turns: madeUp))
        let (second, _) = MockServer.client(.init(turns: [SSE.content("See ghost.py:1 and phantom.swift:2.")]))
        var config = AgentConfig(tools: AllTools.all, approve: { _ in .allow }, shell: ShellState(cwd: ws.root))
        config.policy = PermissionPolicy(mode: .fullAuto)
        config.subagents = SubagentSetup(resolveModel: { _, _ in SubagentModel(client: first, model: "a") })
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        config.subagents?.retryModel = { _, _, _, _ in count.n += 1; return SubagentModel(client: second, model: "b") }
        let events = Events()
        await AgentLoop.run(client: main, model: "m", systemPrompt: nil, history: [.user("Go")], config: config, workspace: ws) { events.add($0) }
        #expect(count.n == 1 && events.started.count == 2)
        #expect(events.results.first?.content.contains("[Automatic checks: made-up citations") == true)
    }
}

@Suite struct CLISubagentRoutingTests {
    @Test func aRemoteSessionsSubagentsRunOnThePool() throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-cli-pool-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
        let anthropic = Endpoint(name: "Anthropic", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!, usesAPIKey: true)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([.localLMStudio, openRouter, anthropic])
        let d = try #require(UserDefaults(suiteName: "kk-cli-pool-\(UUID().uuidString)"))
        // Keys from the environment, so the test never reads the Keychain.
        let settings = AppSettings(support: support, defaults: d,
                                   environment: ["KURTKODE_API_KEY_OPENROUTER": "k1", "KURTKODE_API_KEY_ANTHROPIC": "k2"])
        let make: CLISession.ClientFactory = { e, key in ChatClient(endpoint: e, apiKey: key) }
        let general = AgentDefinition.builtIns.first { $0.name == "general" }!

        let cheap = try #require(CLISession.subagentModel(general, card: TaskCard(), main: anthropic, mainModel: "claude-opus-5-5",
                                                          settings: settings, makeClient: make))
        #expect(cheap.model == "inclusionai/ling-3.0-flash" && cheap.endpointID == openRouter.id)
        #expect(cheap.providers?.dataCollection == "deny")
        let important = try #require(CLISession.subagentModel(general, card: TaskCard(importance: .high), main: anthropic,
                                                              mainModel: "claude-opus-5-5", settings: settings, makeClient: make))
        #expect(important.model == "claude-haiku-5-5" && important.endpointID == anthropic.id)
        #expect(CLISession.subagentModel(general, card: TaskCard(), main: .localLMStudio, mainModel: "gemma",
                                         settings: settings, makeClient: make) == nil)
        // The session's own model chosen in Settings: no pool.
        d.set("", forKey: RunSettings.Key.subagentModel)
        #expect(CLISession.subagentModel(general, card: TaskCard(), main: anthropic, mainModel: "claude-opus-5-5",
                                         settings: settings, makeClient: make) == nil)
        // A pool.json the user edited (ling off): the next subagent entry, a tier up.
        d.removeObject(forKey: RunSettings.Key.subagentModel)
        var pool = ModelPool.shipped
        pool.entries[0].enabled = false
        try pool.save(settings.poolURL)
        let next = try #require(CLISession.subagentModel(general, card: TaskCard(), main: anthropic, mainModel: "claude-opus-5-5",
                                                         settings: settings, makeClient: make))
        #expect(next.model == "claude-haiku-5-5" && next.endpointID == anthropic.id)
    }
}

// MARK: A3 main-run quality signals

@Suite struct MainRunSignalTests {
    private func turn(_ id: String, _ name: String, _ args: String, result: String, exit: Int32? = nil) -> [ChatMessage] {
        var info = ToolResultInfo(toolName: name, isError: false, truncated: false, duration: 0)
        info.exitCode = exit
        return [ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: id, name: name, arguments: args)]),
                ChatMessage(role: .tool, content: result, toolCallID: id, toolResult: info)]
    }

    @Test func signalsFromARunsMessages() {
        var m: [ChatMessage] = []
        m += turn("1", "write_file", #"{"path":"src/calc.py","content":"x"}"#, result: "Wrote")
        m += turn("2", "edit_file", #"{"path":"setup.cfg","old_string":"a","new_string":"b"}"#, result: "Edited")
        m += turn("3", "todo_write", #"{"todos":[{"content":"Fix add","status":"completed"},{"content":"Add a test","status":"pending"}]}"#, result: "ok")
        m += turn("4", "bash", #"{"command":"python3 -m pytest -q"}"#, result: "1 failed\n\n[Exit code 1.]", exit: 1)
        let s = RunSignals.evaluate(m, request: "Fix the bug in calc.py")
        #expect(s.lastCheck?.command == "python3 -m pytest -q" && s.lastCheck?.exitCode == 1)
        #expect(s.lastCheckFailed)
        #expect(s.filesNotNamed == ["setup.cfg"])
        #expect(s.unfinishedTodos == ["Add a test"])
        #expect(s.problems == ["the last check failed (exit 1): python3 -m pytest -q", "1 todo left unfinished",
                               "changed 1 file the request doesn't name"])
        #expect(RunSignals.evaluate([], request: "hi").problems.isEmpty)
    }

    @Test func theLoopRecordsThemOnTheRun() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "bash", #"{"command":"python3 -c 'import sys; sys.exit(2)'"}"#),
            SSE.content("It fails."),
        ]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                 shell: ShellState(cwd: ws.root))
        config.costScope = CostScope(run: UUID(), agent: "main")
        final class Box: @unchecked Sendable { var run: AgentRunRecord? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Run the check")], config: config,
                            workspace: ws) { if case .runEnded(let r) = $0 { box.run = r } }
        // `python3 -c` isn't a test runner: no check. The request text is the user's, not a context note; it asks for
        // no change.
        var none = RunSignals()
        none.changeAsked = false
        #expect(box.run?.signals == none)
        #expect(box.run?.task.text == "Run the check")
    }

    @Test func theLabelTakesThumbsThenRetriesAndRewinds() {
        let run = UUID()
        var js = [RunJudgment(run: run, judge: .parent, verdict: 3)]
        #expect(js.label == 1)
        js.append(MainRunJudgments.implicit(run: run, why: "retried"))
        #expect(js.label == 0)                                   // a retry outranks the agent's own view
        js.append(MainRunJudgments.thumbs(run: run, up: true))
        #expect(js.label == 1)                                   // the user's thumbs outrank both
        var withdrawn = MainRunJudgments.thumbs(run: run, up: true)
        withdrawn.verdict = nil
        js.append(withdrawn)
        #expect(js.label == 0)                                   // taken back: the retry speaks again
        #expect(MainRunJudgments.thumbs(run: run, up: false, note: "").note == nil)
    }

    @Test func repliesMapToTheirRuns() {
        var s = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: nil), messages: [], model: "m")
        let ask1 = ChatMessage.user("one"), ask2 = ChatMessage.user("two")
        var step = ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "a", name: "read_file", arguments: "{}")])
        step.meta = .test
        var reply1 = ChatMessage(role: .assistant, content: "first")
        reply1.meta = .test
        var note = ChatMessage.user("[skill note]")
        note.contextNote = true
        var reply2 = ChatMessage(role: .assistant, content: "second")
        reply2.meta = .test
        var early = ChatMessage(role: .assistant, content: "first, before a todo update")
        early.meta = .test
        s.messages = [ask1, early, step, reply1, ask2, note, reply2]
        func run(_ asked: ChatMessage) -> AgentRunRecord {
            var r = AgentRunRecord.test(agent: "main")
            r.userMessage = asked.id
            return r
        }
        let r1 = run(ask1), r2 = run(ask2)
        s.runs = [r1, r2]
        #expect(s.replyRuns == [reply1.id: r1.id, reply2.id: r2.id])
        #expect(s.mainRun(for: reply2.id)?.id == r2.id)               // past the context note
        #expect(s.latestMainRun?.id == r2.id)
        #expect(s.thumbs(r1.id) == nil)
        s.judgments = [MainRunJudgments.thumbs(run: r1.id, up: false)]
        #expect(s.thumbs(r1.id) == false)
    }
}

extension TurnMeta {
    static let test = TurnMeta(requestedModel: "m", stopReason: .completed, duration: 1)
}

extension AgentRunRecord {
    /// A minimal record for tests.
    static func test(agent: String, model: String = "m", started: Date = Date(), spent: Double? = nil) -> AgentRunRecord {
        let setup = RunSetup(endpointID: nil, api: .openai, host: nil, model: model, temperature: nil, maxOutputTokens: 1000,
                             wallClock: 60, maxSteps: 10, promptStyle: nil, webSearch: false, promptCacheHour: false, tools: [],
                             summarizerModel: nil, fallbackModel: nil)
        var totals = RunTotals()
        totals.charged = spent
        return AgentRunRecord(id: UUID(), userMessage: nil, parentRun: nil, taskCall: nil, agent: agent, definitionHash: "",
                              systemPromptHash: "", setup: setup, build: .current, machine: nil, localModel: nil,
                              task: RunTask(text: "t", bytes: 1, estimatedTokens: 1, hash: "h", card: nil), started: started,
                              ended: started.addingTimeInterval(1), totals: totals,
                              outcome: RunOutcome(stop: "completed", steps: 1, toolCalls: [:], toolErrors: 0, denied: 0, filesChanged: [],
                                                  compactions: 0, finalReplyBytes: 1, finalReplyEstimatedTokens: 1),
                              children: [], judgment: nil)
    }
}

@Suite struct MainRunJudgeCommandTests {
    @Test func judgeAndRunsCoverMainRuns() async throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-a3-\(UUID().uuidString.prefix(6))")
        let settings = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-a3-\(UUID().uuidString)")!, environment: [:])
        let store = settings.sessionStore
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
        try await store.create(header)
        var run = AgentRunRecord.test(agent: "main")
        run.signals = RunSignals(lastCheck: SessionFacts.Check(command: "swift test", exitCode: 1), filesNotNamed: ["a.swift"])
        run.totals.promptTokens = 1000
        run.totals.cacheReadTokens = 750
        try await store.append(.run(run), to: header.id)
        try await store.append(.judgment(MainRunJudgments.implicit(run: run.id, why: "retried")), to: header.id)

        final class Out: @unchecked Sendable { var text = "" }
        let out = Out()
        let code = await DebugCommands.run(["judge", String(run.id.uuidString.prefix(8)), "--verdict", "2", "--note", "fine"],
                                           settings: settings, cwd: URL(fileURLWithPath: "/tmp")) { out.text += $0 }
        #expect(code == 0)
        #expect(out.text.hasPrefix("Judged the main run"))
        let saved = try #require(try await store.load(header.id))
        #expect(saved.judgments.last?.judge == .user && saved.judgments.last?.verdict == 2)

        out.text = ""
        _ = await DebugCommands.run(["runs", "--csv"], settings: settings, cwd: URL(fileURLWithPath: "/tmp")) { out.text += $0 }
        let lines = out.text.split(separator: "\n").map(String.init)
        let header_ = lines[0].split(separator: ",").map(String.init)
        let row = try #require(lines.dropFirst().first)
        func cell(_ name: String) -> String? {
            // The task text and others have no commas here, so a plain split works.
            let cells = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return header_.firstIndex(of: name).map { cells[$0] }
        }
        #expect(cell("user_verdict") == "2")
        #expect(cell("implicit") == "retried")
        #expect(cell("label") == "0.667")                          // the user's 2/3 outranks the retry
        #expect(cell("last_check_exit") == "1" && cell("files_not_named") == "a.swift")
        #expect(cell("cache_share") == "0.750")
    }

    @Test func goodAndBadRateTheLastReply() async throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-a3g-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://mock.invalid/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock])
        let settings = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-a3g-\(UUID().uuidString)")!, environment: [:])
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.content("Hello.")]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        #expect(await session.rateLatestRun(up: true, note: "") == "There's no reply to rate yet.")
        _ = try await session.send("Say hello.")
        #expect(await session.rateLatestRun(up: false, note: "wrong greeting") == "Marked the last reply as wrong.")
        let saved = try #require(try await settings.sessionStore.load(session.session.header.id))
        let run = try #require(saved.latestMainRun)
        #expect(saved.judgments.last?.run == run.id && saved.judgments.last?.verdict == 0)
        #expect(saved.judgments.last?.note == "wrong greeting")
        #expect(saved.thumbs(run.id) == false)
    }
}

@Suite struct CLIPoolEndToEndTests {
    /// A CLI session on a remote-looking main endpoint, with a pool of two remote-looking subagent endpoints: the subagent
    /// runs on the pool's first rung, fails outright, and is retried on the second, all through `CLISession`.
    @Test func routesAndRetriesThroughTheCLI() async throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-a2e2e-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let main = Endpoint(name: "Main", kind: .openai, baseURL: URL(string: "https://api.openai.com/v1")!)
        let cheap = Endpoint(name: "Cheap", kind: .openai, baseURL: URL(string: "https://cheap.example/v1")!)
        let next = Endpoint(name: "Next", kind: .openai, baseURL: URL(string: "https://next.example/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([main, cheap, next])
        let defaults = UserDefaults(suiteName: "kk-a2e2e-\(UUID().uuidString)")!
        defaults.set(true, forKey: RunSettings.Key.subagentRetry)      // off by default since the cost audit
        let settings = AppSettings(support: support, defaults: defaults, environment: [:])
        try ModelPool(entries: [
            PoolEntry(endpoint: cheap.id.uuidString, model: "c-model", tier: .cheap, roles: [.subagent], ladder: 0),
            PoolEntry(endpoint: next.id.uuidString, model: "n-model", reasoning: "low", tier: .cheap, roles: [.subagent], ladder: 1),
        ]).save(settings.poolURL)

        let (mainClient, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "task", #"{"description":"Note it","prompt":"Write the note","agent":"general"}"#),
            SSE.content("Done."),
        ]))
        let (cheapClient, cheapHost) = MockServer.client(.init(turns: [
            SSE.toolCall("w1", "write_file", #"{"path":"NOTE.md","content":"draft\n"}"#),
            SSE.content("See ghost.py:10 and phantom.swift:3."),
        ]))
        let (nextClient, nextHost) = MockServer.client(.init(turns: [SSE.content("Nothing to write after all.")]))
        let clients = [main.id: mainClient, cheap.id: cheapClient, next.id: nextClient]
        let ws = try makeProject()
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        options.mode = .fullAuto
        options.model = "Main:big"
        options.skillRouting = .off
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { e, _ in clients[e.id]! }
        let stop = try await session.send("Write the note.")
        #expect(stop == .completed)
        #expect(MockServer.requestBodies(cheapHost).count == 2)
        let retried = try #require(MockServer.requestBodies(nextHost).first)
        guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: retried) else { return }
        #expect(body["model"] == "n-model" && body["reasoning_effort"] == "low")    // the pool entry's reasoning
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "NOTE.md").path))
        let runs = await settings.sessionStore.subagentRuns(of: session.session.header)
        #expect(Set(runs.map(\.model)) == ["c-model", "n-model"])
        let second = try #require(runs.first { $0.model == "n-model" })
        #expect(second.subagentEnd?.attemptOf == runs.first { $0.model == "c-model" }?.header.id)
    }
}

// MARK: A5 spending

@Suite struct SpendingTests {
    private func run(_ model: String, agent: String = "main", spent: Double?, passed: Bool?, project: String = "p",
                     prompt: Int = 1000, cached: Int = 500, out: Int = 100, day: String = "2026-10-20", card: TaskCard? = nil,
                     reasoning: String? = nil) -> Spending.Run {
        var r = AgentRunRecord.test(agent: agent, model: model, started: DayFormat.formatter(zone: .current).date(from: day)!)
        if let spent {
            r.totals.requests = 2
            r.totals.listPrice.total = spent * 2           // the charge wins over list price
            r.totals.charged = spent
        } else {
            r.totals.requests = 2
            r.totals.unpricedRequests = 2
            r.totals.charged = nil
        }
        r.totals.promptTokens = prompt
        r.totals.cacheReadTokens = cached
        r.totals.completionTokens = out
        r.task.card = card
        r.setup.reasoning = reasoning
        if agent != "main" { r.parentRun = UUID() }
        return Spending.Run(record: r, project: project, passed: passed)
    }

    @Test func groupsAndTotals() {
        let runs = [run("a", spent: 0.10, passed: true), run("a", spent: 0.20, passed: false), run("a", spent: 0.30, passed: nil),
                    run("b", spent: nil, passed: true, cached: 0), run("c", agent: "explore", spent: 0.01, passed: true, card: TaskCard(kind: .search))]
        let rows = Spending.rows(runs, by: .model)
        #expect(rows.map(\.key) == ["a", "c", "b", "all"])
        let a = rows[0]
        #expect(a.runs == 3 && abs(a.spent - 0.6) < 1e-9 && a.labeled == 2 && a.passed == 1)
        #expect(abs((a.perRun ?? 0) - 0.2) < 1e-9)
        #expect(abs((a.perSuccess ?? 0) - 0.3) < 1e-9)           // labeled spending (0.30) over passes (1)
        #expect(a.cacheShare == 0.5)
        #expect(rows[2].pricedRuns == 0 && rows[2].perRun == nil)  // local: no dollars
        let all = rows.last!
        #expect(all.runs == 5 && all.labeled == 4 && all.passed == 3)
        // A success is over the priced passes: b's free local pass doesn't lower it (0.31 over 2, not 3).
        #expect(abs((all.perSuccess ?? 0) - 0.155) < 1e-9)
        #expect(SubagentSetup.judgeScope(CostScope(run: nil, agent: "main"), as: "grader").agent == "grader")
        #expect(SubagentSetup.judgeScope(nil, as: "reviewer").agent == "reviewer")
        #expect(Spending.rows(runs, by: .kind).map(\.key).contains("subagent: search"))
        let days = Spending.rows([run("a", spent: 1, passed: nil, day: "2026-10-21"), run("a", spent: 1, passed: nil, day: "2026-10-19")], by: .day)
        #expect(days.map(\.key) == ["2026-10-19", "2026-10-21", "all"])
        #expect(Spending.rows([run("d", spent: 1, passed: nil, reasoning: "none")], by: .model).first?.key == "d (reasoning off)")
        #expect(Spending.table(rows, by: .model).contains("all"))
        #expect(Spending.table(Spending.rows([], by: .model), by: .model) == "No recorded runs.\n")
        // The user's time (the cost audit's θ): shown only with an hourly rate.
        #expect(!Spending.table(rows, by: .model).contains("time cost"))
        #expect(Spending.table(rows, by: .model, perHour: 30).contains("time cost"))
        var timed = Spending.Row(key: "x")
        timed.runs = 2
        timed.seconds = 7200
        #expect(timed.secondsPerRun == 3600 && timed.timeCost(perHour: 30) == 60)
        #expect(RunSettings().hourlyRate == 30)
        let d = UserDefaults(suiteName: "kk-hourly-\(UUID().uuidString)")!
        d.set(0.0, forKey: RunSettings.Key.hourlyRate)
        #expect(RunSettings(defaults: d).hourlyRate == 0)
    }

    /// Improvement 9 of the cost audit: runs don't wait for OpenRouter's records; a charge recorded later
    /// (`CostReconciler`) is what the reports show for the run.
    @Test func reportsReadChargesSettledAfterTheRun() {
        let rates = PriceList.Rates(input: 1, output: 1, cacheRead: 0.1, cacheWrite5m: 1, cacheWrite1h: 1)
        let price = PriceLookup.known(PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil),
                                      source: "t", version: "t")
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        var m = ChatMessage(role: .assistant, content: "x")
        var meta = TurnMeta.test
        meta.usage = Usage(promptTokens: 1_000_000, completionTokens: 0)
        m.meta = meta
        var record = AgentRunRecord.test(agent: "main", model: "m", started: Date())
        record.totals.spent = 1.0
        var settled = CostEntry.make(reply: m, purpose: .reply, run: record.id, agent: "main", client: client, endpointID: nil,
                                     start: Date(), price: price)
        settled.charged = 0.25
        let now = Spending.withCurrentCosts(record, entries: [settled])
        #expect(now.totals.spent == 0.25 && now.totals.charged == 0.25)
        #expect(Spending.withCurrentCosts(record, entries: nil).totals.spent == 1.0)
    }

    /// B2 and B3 of the cost audit: another model's grading in a run is filed under that model, and requests outside
    /// any run get rows of their own; neither counts as a run.
    @Test func otherModelsWorkAndRequestsOutsideRunsHaveTheirOwnRows() {
        let rates = PriceList.Rates(input: 1, output: 1, cacheRead: 0.1, cacheWrite5m: 1, cacheWrite1h: 1)
        let price = PriceLookup.known(PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil),
                                      source: "t", version: "t")
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
        func entry(_ purpose: CostEntry.Purpose, model: String, run: UUID?, tokens: Int) -> CostEntry {
            var m = ChatMessage(role: .assistant, content: "x")
            var meta = TurnMeta.test
            meta.usage = Usage(promptTokens: tokens, completionTokens: 0)
            meta.requestedModel = model
            m.meta = meta
            return CostEntry.make(reply: m, purpose: purpose, run: run, agent: "main", client: client, endpointID: nil,
                                  start: Date(), price: price)
        }
        let run = AgentRunRecord.test(agent: "main", model: "haiku")
        let reply = entry(.reply, model: "haiku", run: run.id, tokens: 1_000_000)
        let grade = entry(.grading, model: "opus", run: run.id, tokens: 2_000_000)
        let rating = entry(.rating, model: "haiku", run: run.id, tokens: 500_000)
        #expect(!Spending.isOtherModelsWork(reply, in: run) && Spending.isOtherModelsWork(grade, in: run))
        #expect(!Spending.isOtherModelsWork(rating, in: run))            // the parent's own model rating its subagents
        let own = Spending.withCurrentCosts(run, entries: [reply, rating])
        #expect(own.totals.spent == 1.5 && own.totals.promptTokens == 1_500_000 && own.totals.requests == 2)
        let routing = entry(.routing, model: "haiku", run: nil, tokens: 100_000)
        let runs = [Spending.Run(record: own, project: "p", passed: true),
                    Spending.Run(record: Spending.requestRecord(grade, like: run), project: "p", passed: nil, outside: "grading (in runs)"),
                    Spending.Run(record: Spending.requestRecord(routing, like: nil), project: "p", passed: nil, outside: "outside runs: routing")]
        let byModel = Spending.rows(runs, by: .model)
        #expect(byModel.first { $0.key == "opus" }?.spent == 2 && byModel.first { $0.key == "opus" }?.runs == 0)
        #expect(abs((byModel.first { $0.key == "haiku" }?.spent ?? 0) - 1.6) < 1e-9)
        let total = byModel.last!
        #expect(total.runs == 1 && abs(total.spent - 3.6) < 1e-9 && total.passed == 1)
        #expect(Set(Spending.rows(runs, by: .kind).map(\.key)) == ["main", "grading (in runs)", "outside runs: routing", "all"])
    }

    @Test func whatIfRepricesTheTokens() {
        let rates = PriceList.Rates(input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2, cacheWrite1h: 2)
        let price = PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: 0.001)
        let r = run("a", spent: 0.1, passed: nil, prompt: 10_000, cached: 6_000, out: 1_000)
        // 4,000 uncached × $2 + 6,000 cached × $0.20 + 1,000 out × $10, per million, plus 2 requests × $0.001.
        let expected: Double = (4_000.0 * 2 + 6_000.0 * 0.2 + 1_000.0 * 10) / 1e6 + 0.002
        let got: Double = Spending.whatIf([r], at: price)
        #expect(abs(got - expected) < 1e-12)
    }

    @Test func readsAnEvalStore() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-evalstore-\(UUID().uuidString.prefix(6))")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        for (i, passed) in [true, false].enumerated() {
            let run = dir.appending(path: "t\(i)")
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let record = try JSONDecoder().decode(JSONValue.self, from: enc.encode(AgentRunRecord.test(agent: "main", spent: 0.01)))
            let obj: JSONValue = ["task": "x", "gold": ["passed": .bool(passed)], "runRecord": record]
            try enc.encode(obj).write(to: run.appending(path: "run.json"))
        }
        try FileManager.default.createDirectory(at: dir.appending(path: "empty"), withIntermediateDirectories: true)
        let runs = Spending.evalRuns(dir)
        #expect(runs.count == 2)
        #expect(runs.map(\.passed) == [true, false])
        #expect(runs.first?.project == dir.lastPathComponent)
    }

    @Test func cacheWatchNoticesALostPrefix() {
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        let rates = PriceList.Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite5m: 3, cacheWrite1h: 3)
        let price = PriceLookup.known(PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil),
                                      source: "t", version: "t")
        func entry(prompt: Int, cached: Int) -> CostEntry {
            var m = ChatMessage(role: .assistant, content: "x")
            var meta = TurnMeta.test
            meta.usage = Usage(promptTokens: prompt, completionTokens: 10, cacheReadTokens: cached)
            m.meta = meta
            return CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: nil, start: Date(), price: price)
        }
        let warm = entry(prompt: 20_000, cached: 18_000), cold = entry(prompt: 21_000, cached: 0)
        let note = try? #require(CacheWatch.check(previous: warm, current: cold))
        #expect(note?.hasPrefix("The prompt cache missed: 21,000 tokens were read at full price") == true)
        #expect(CacheWatch.check(previous: warm, current: entry(prompt: 21_000, cached: 19_000)) == nil)
        #expect(CacheWatch.check(previous: entry(prompt: 2_000, cached: 1_800), current: entry(prompt: 2_100, cached: 0)) == nil)  // small
        #expect(CacheWatch.check(previous: nil, current: cold) == nil)
    }

    /// B5 of the cost audit: a remote model with no known price used to count $0 toward every limit.
    @Test func unpricedRemoteRequestsCountTowardLimitsAtADefaultRate() {
        func entry(_ price: PriceLookup) -> CostEntry {
            var m = ChatMessage(role: .assistant, content: "x")
            var meta = TurnMeta.test
            meta.usage = Usage(promptTokens: 100_000, completionTokens: 10_000)
            m.meta = meta
            return CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main",
                                  client: ChatClient(baseURL: URL(string: "https://api.openai.com/v1")!), endpointID: nil,
                                  start: Date(), price: price)
        }
        let remote = entry(.unknown("the server lists no price for gpt-x")), local = entry(.local)
        #expect(remote.isUnpricedRemote && !local.isUnpricedRemote)
        #expect(abs(CostMeter.counted(remote) - 0.45) < 1e-9)       // 100k in at $3 + 10k out at $15 per million
        #expect(CostMeter.counted(local) == 0)
        let m = CostMeter(runLimit: 0.40, sessionLimit: nil, sessionBefore: 0)
        m.add(local)
        #expect(m.reached == nil)
        m.add(remote)
        #expect(m.reached?.hasPrefix("this run's limit of $0.40") == true)
        #expect(m.stopNote?.contains("$0.45 of it estimated") == true)
    }

    @Test func dailyAndProjectLimits() async throws {
        let m = CostMeter(runLimit: 0, sessionLimit: 0, sessionBefore: 0, dayLimit: 1.0, dayBefore: 0.95, projectLimit: 0.5, projectBefore: 0.2)
        #expect(m.reached == nil)
        m.add(Usage(promptTokens: 1, completionTokens: 1, cost: 0.06))
        #expect(m.reached == "the daily limit of $1.00: all sessions have spent $1.01 today")
        let p = CostMeter(runLimit: 0, sessionLimit: 0, sessionBefore: 0, projectLimit: 0.5, projectBefore: 0.45)
        p.add(Usage(promptTokens: 1, completionTokens: 1, cost: 0.06))
        #expect(p.reached == "this project's daily limit of $0.50: its sessions have spent $0.51 today")

        // Today's spending, read from the store: this project's and everyone's, not yesterday's.
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-today-\(UUID().uuidString.prefix(6))"))
        let client = ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        func session(_ workspace: String, cost: Double, start: Date) async throws {
            let h = SessionHeader(endpointID: UUID(), model: "m", workspace: workspace)
            try await store.create(h)
            var m = ChatMessage(role: .assistant, content: "x")
            var meta = TurnMeta.test
            meta.usage = Usage(promptTokens: 1, completionTokens: 1, cost: cost)
            m.meta = meta
            let e = CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main", client: client, endpointID: nil, start: start,
                                   price: .unknown("x"))
            try await store.append(.cost(e), to: h.id)
        }
        try await session("/p/one", cost: 0.25, start: Date())
        try await session("/p/two", cost: 0.50, start: Date())
        try await session("/p/one", cost: 9.00, start: Date().addingTimeInterval(-3 * 86_400))
        let (all, one) = await Spending.today(store, workspace: "/p/one")
        #expect(abs(all - 0.75) < 1e-9 && abs(one - 0.25) < 1e-9)
    }
}

@Suite struct EvalPoolOptionTests {
    @Test func aPoolTargetIsLabeledAndBuildsTheEntrysModel() throws {
        let openRouter = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
        var t = ModelTarget(endpoint: openRouter, model: "anthropic/claude-haiku-5.5")
        t.subagents = true
        let box = SubagentPoolBox(pool: .threeRungs, endpoints: [openRouter], key: { _ in "k" })
        t.subagentPool = box
        #expect(t.label == "openrouter:anthropic/claude-haiku-5.5 +subagents >pool")
        let r = try #require(ModelPool.threeRungs.ladder(endpoints: [openRouter]).dropFirst().first)
        let m = box.model(r, { ChatClient(endpoint: $0.endpoint, apiKey: $0.apiKey) })
        #expect(m.model == "deepseek/deepseek-v4-flash-0731" && m.reasoning == "none" && m.providers?.dataCollection == "deny")
    }
}
