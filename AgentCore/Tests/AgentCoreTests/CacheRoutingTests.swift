import Foundation
import Testing
@testable import AgentCore

/// CACHING_PLAN.md 1.3 and 1.5: cache keys and provider stickiness, and no cache writes for one-off requests.
struct CacheRoutingTests {
    static func body(_ base: String, api: WireAPI = .openai, model: String, key: String? = nil, oneOff: Bool = false,
                     system: String = "SYSTEM") throws -> [String: JSONValue] {
        var r = ChatRequest(model: model, messages: [.system(system), .user("hi")], maxTokens: 100)
        r.cacheKey = key
        r.oneOff = oneOff
        let data = try ChatClient(baseURL: URL(string: base)!, api: api).encode(r)
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return o
    }

    @Test func theCacheKeyGoesWhereEachServerTakesIt() throws {
        let openAI = try Self.body("https://api.openai.com/v1", model: "gpt-6.1-sol", key: "s1")
        #expect(openAI["prompt_cache_key"] == "s1" && openAI["session_id"] == nil)
        let router = try Self.body("https://openrouter.ai/api/v1", model: "deepseek/deepseek-v4-flash", key: "s1")
        #expect(router["session_id"] == "s1" && router["prompt_cache_key"] == nil)
        // Other servers (LM Studio, a LAN server) get neither, nor does a request without a key.
        let local = try Self.body("http://127.0.0.1:1234/v1", model: "qwen3", key: "s1")
        #expect(local["prompt_cache_key"] == nil && local["session_id"] == nil)
        #expect(try Self.body("https://api.openai.com/v1", model: "gpt-6.1-sol")["prompt_cache_key"] == nil)
    }

    @Test func gptModelsFromFiveSixBillCacheWrites() {
        #expect(WireFormat.billsCacheWrites("gpt-5.6-sol") && WireFormat.billsCacheWrites("gpt-6.1-terra"))
        #expect(WireFormat.billsCacheWrites("gpt-6-luna") && WireFormat.billsCacheWrites("openai/gpt-6.1-sol"))
        #expect(!WireFormat.billsCacheWrites("gpt-5.5") && !WireFormat.billsCacheWrites("gpt-5") && !WireFormat.billsCacheWrites("gpt-4.1"))
        #expect(!WireFormat.billsCacheWrites("o3") && !WireFormat.billsCacheWrites("anthropic/claude-haiku-4.5"))
    }

    @Test func aOneOffRequestWritesNoCache() throws {
        let explicit: JSONValue = ["mode": "explicit"]
        #expect(try Self.body("https://api.openai.com/v1", model: "gpt-6.1-sol", oneOff: true)["prompt_cache_options"] == explicit)
        #expect(try Self.body("https://openrouter.ai/api/v1", model: "openai/gpt-6.1-sol", oneOff: true)["prompt_cache_options"] == explicit)
        // Free writes before GPT-5.6: nothing to turn off. And an ordinary request leaves caching on.
        #expect(try Self.body("https://api.openai.com/v1", model: "gpt-5.5", oneOff: true)["prompt_cache_options"] == nil)
        #expect(try Self.body("https://api.openai.com/v1", model: "gpt-6.1-sol")["prompt_cache_options"] == nil)

        // Claude through OpenRouter: no breakpoints.
        let routed = try Self.body("https://openrouter.ai/api/v1", model: "anthropic/claude-haiku-4.5", oneOff: true)
        #expect(!String(describing: routed["messages"]).contains("cache_control"))

        // Claude: no automatic breakpoint; a short system prompt goes as plain text, a long fixed one stays cached.
        let claude = try Self.body("https://api.anthropic.com/v1", api: .anthropic, model: "claude-haiku-5-5", oneOff: true)
        #expect(claude["cache_control"] == nil && claude["system"] == "SYSTEM")
        let long = String(repeating: "Grade the run by its evidence. ", count: 300)
        let grader = try Self.body("https://api.anthropic.com/v1", api: .anthropic, model: "claude-haiku-5-5", oneOff: true, system: long)
        #expect(grader["cache_control"] == nil)
        #expect(String(describing: grader["system"]).contains("ephemeral"))
        let ordinary = try Self.body("https://api.anthropic.com/v1", api: .anthropic, model: "claude-haiku-5-5")
        #expect(ordinary["cache_control"] == ["type": "ephemeral"])
    }
}

/// CACHING_PLAN.md 1.1: an hour's cache where someone may pause, five minutes for the rest.
struct PromptCacheTTLTests {
    @Test func autoGivesAnHourToInteractiveMainRunsOnly() {
        var s = RunSettings()
        #expect(s.promptCacheTTL == .auto)
        #expect(s.cacheHour(interactive: true) == (main: true, subagents: false))
        #expect(s.cacheHour(interactive: false) == (main: false, subagents: false))
        s.promptCacheTTL = .hour
        #expect(s.cacheHour(interactive: false) == (main: true, subagents: true))
        s.promptCacheTTL = .fiveMinutes
        #expect(s.cacheHour(interactive: true) == (main: false, subagents: false))
    }

    @Test func theOldHourSwitchReadsAsAnHourForAll() throws {
        let d = try #require(UserDefaults(suiteName: "kk-ttl-\(UUID().uuidString)"))
        #expect(RunSettings(defaults: d).promptCacheTTL == .auto)
        d.set(true, forKey: RunSettings.Key.promptCacheHour)
        #expect(RunSettings(defaults: d).promptCacheTTL == .hour)
        d.set("5m", forKey: RunSettings.Key.promptCacheTTL)
        #expect(RunSettings(defaults: d).promptCacheTTL == .fiveMinutes)
    }

    @Test func aRunRecordsTheLifetimeItAskedFor() async throws {
        for hour in [true, false] {
            let (client, _) = MockServer.client(.init(turns: [SSE.content("Done.")]))
            var config = AgentConfig(tools: ReadTools.all)
            config.promptCacheHour = hour
            final class Box: @unchecked Sendable { var prints: [PromptPrint] = []; let lock = NSLock() }
            let box = Box()
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                                workspace: try makeProject()) { e in
                if case .cost(let c) = e, let p = c.prompt { box.lock.withLock { box.prints.append(p) } }
            }
            #expect(box.prints.map(\.ttl) == [hour ? "1h" : nil])
        }
    }
}

/// CACHING_PLAN.md 1.4: a fan-out's siblings start once the first of their kind has begun replying. Checked by the
/// order of events, not by wall-clock bounds: under the full suite's load the cooperative pool runs late.
struct CacheWarmupTests {
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    @Test func theFirstGoesAtOnceAndTheRestWaitForIt() async {
        let w = CacheWarmup()
        // With a minute's limit, a leader or another kind that waited would make this test take a minute.
        let clock = ContinuousClock(), t = clock.now
        await w.admit("explore|m", limit: .seconds(60))
        await w.admit("general|m", limit: .seconds(60))
        #expect(clock.now - t < .seconds(30))
        let warmed = Flag()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            warmed.set()
            await w.warmed("explore|m")
        }
        await w.admit("explore|m", limit: .seconds(60))
        #expect(warmed.isSet)                     // it waited for the first run's reply
        let u = clock.now
        await w.admit("explore|m", limit: .seconds(60))   // once warm, at once
        #expect(clock.now - u < .seconds(30))
    }

    @Test func aSiblingStopsWaitingAtTheLimit() async {
        let w = CacheWarmup()
        await w.admit("k")
        let clock = ContinuousClock(), t = clock.now
        await w.admit("k", limit: .milliseconds(300))      // nobody calls warmed: it returns at the limit
        #expect(clock.now - t >= .milliseconds(250))
    }
}

/// Found in the live check: OpenRouter reports Claude's cache writes without their lifetime and lists one write price.
struct HourCachePricingTests {
    @Test func anHourCacheRequestIsKnownByWhereItGoes() {
        var r = ChatRequest(model: "anthropic/claude-haiku-5.5", messages: [.user("hi")], maxTokens: 10)
        r.cacheForAnHour = true
        #expect(ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!).sendsHourCache(r))
        #expect(ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, api: .anthropic).sendsHourCache(r))
        var gpt = r
        gpt.model = "openai/gpt-6-luna"                       // OpenRouter drops a TTL for OpenAI models
        #expect(!ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!).sendsHourCache(gpt))
        r.oneOff = true
        #expect(!ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!).sendsHourCache(r))
    }

    @Test func openRoutersClaudeListingGetsTheHourWriteRate() throws {
        func listing(_ id: String) -> [String: JSONValue] {
            ["id": .string(id), "pricing": ["prompt": "0.0000001", "completion": "0.0000005",
                                             "input_cache_read": "0.00000001", "input_cache_write": "0.000000125"]]
        }
        let claude = try #require(RemotePrices.price(listing("anthropic/claude-haiku-5.5")))
        #expect(abs(claude.standard.cacheWrite5m - 0.125) < 1e-9 && abs(claude.standard.cacheWrite1h - 0.2) < 1e-9)
        let gpt = try #require(RemotePrices.price(listing("openai/gpt-6-luna")))
        #expect(abs(gpt.standard.cacheWrite1h - 0.125) < 1e-9)
    }
}
