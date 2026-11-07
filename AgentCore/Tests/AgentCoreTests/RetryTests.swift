import Foundation
import Testing
@testable import AgentCore

/// Turns as OpenRouter streams them: each chunk names the provider serving it.
private enum Routed {
    static func line(_ json: String) -> Data { Data("data: \(json)\n".utf8) }

    /// What a provider sends when it couldn't parse the model's tool call: nothing, but the tokens are billed.
    static func lost(provider: String?, tokens: Int = 60) -> [Data] {
        let p = provider.map { #","provider":"\#($0)""# } ?? ""
        return [
            line(#"{"model":"test-model"\#(p),"choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#),
            line(#"{"model":"test-model"\#(p),"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#),
            line(#"{"model":"test-model"\#(p),"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":\#(tokens)}}"#),
            Data("data: [DONE]\n".utf8),
        ]
    }

    static func content(_ text: String, provider: String) -> [Data] {
        [
            line(#"{"model":"test-model","provider":"\#(provider)","choices":[{"index":0,"delta":{"role":"assistant","content":"\#(text)"},"finish_reason":null}]}"#),
            line(#"{"model":"test-model","provider":"\#(provider)","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#),
            line(#"{"model":"test-model","provider":"\#(provider)","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":10}}"#),
            Data("data: [DONE]\n".utf8),
        ]
    }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var assistants: [ChatMessage] { all.compactMap { if case .assistant(let m) = $0 { m } else { nil } } }
    var retries: [String] { all.compactMap { if case .retrying(let s) = $0 { s } else { nil } } }
    var stop: AgentStop? { all.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last }
}

private func run(_ client: ChatClient, config: AgentConfig = AgentConfig(tools: ReadTools.all)) async throws -> Events {
    let events = Events()
    await AgentLoop.run(client: client, model: "test-model", systemPrompt: "SYSTEM", history: [.user("What is this project?")],
                        config: config, workspace: try makeProject()) { events.add($0) }
    return events
}

/// The request's `provider` object, if it has one.
private func routing(_ body: Data) throws -> [String: JSONValue]? {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body), case .object(let p)? = o["provider"] else { return nil }
    return p
}

private func lastUserText(_ body: Data) throws -> String? {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body), case .array(let msgs)? = o["messages"],
          case .object(let last)? = msgs.last, case .string(let text)? = last["content"] else { return nil }
    return text
}

@Suite struct RetryElsewhereTests {
    @Test func decodesAndEncodesProviders() throws {
        let events = try WireFormat.events(fromChunk: Data(#"{"model":"m","provider":"Novita","choices":[]}"#.utf8))
        #expect(events == [.model("m"), .provider("Novita")])
        var request = ChatRequest(model: "m", messages: [.user("hi")], maxTokens: 10)
        #expect(try routing(WireFormat.encodeRequest(request)) == nil)
        request.provider = ProviderRouting(order: ["DeepInfra"], ignore: ["Novita"], allowFallbacks: false)
        let p = try #require(try routing(WireFormat.encodeRequest(request)))
        #expect(p["order"] == ["DeepInfra"] && p["ignore"] == ["Novita"] && p["allow_fallbacks"] == false)
    }

    @Test func avoidingProvidersKeepsTheUsersPreferences() {
        let mine = ProviderRouting(order: ["A", "B"], ignore: ["C"], allowFallbacks: false)
        let r = mine.avoiding(["a"])
        #expect(r.order == ["B"] && r.ignore == ["C", "a"] && !r.allowFallbacks)
        // With nothing left in the order, the request must be allowed to go anywhere else.
        #expect(mine.avoiding(["A", "B"]).allowFallbacks)
        #expect(ProviderRouting().avoiding([]).isEmpty)
    }

    @Test func recognizesALostReply() {
        func reply(_ content: String = "", tokens: Int = 60, reasoning: String? = nil) -> ChatMessage {
            ChatMessage(role: .assistant, content: content, reasoning: reasoning,
                        meta: TurnMeta(requestedModel: "m", usage: Usage(promptTokens: 1, completionTokens: tokens),
                                       finishReason: .stop, stopReason: .completed, duration: 1))
        }
        #expect(AgentLoop.droppedCall(reply()))
        #expect(!AgentLoop.droppedCall(reply("An answer.")))
        #expect(!AgentLoop.droppedCall(reply(tokens: 5)))                                       // nothing much was generated
        #expect(!AgentLoop.droppedCall(reply(tokens: 60, reasoning: String(repeating: "x", count: 240))))   // all reasoning
        #expect(!AgentLoop.droppedCall(reply(reasoning: #"List it. {"path": "."}"#)))           // a call in the reasoning
    }

    @Test func sendsALostReplyToAnotherProvider() async throws {
        let (client, host) = MockServer.client(.init(turns: [
            Routed.lost(provider: "Flaky"),
            Routed.content("It is a demo project.", provider: "Solid"),
            Routed.content("Again.", provider: "Solid"),
        ]))
        let events = try await run(client)
        #expect(events.stop == .completed)
        // The lost reply is kept (it was paid for, and says who lost it), then the answer from another provider.
        #expect(events.assistants.map(\.meta?.provider) == ["Flaky", "Solid"])
        #expect(events.assistants.last?.content == "It is a demo project.")
        #expect(events.retries.count == 1 && events.retries[0].hasPrefix("Flaky lost the reply"))
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 2)
        #expect(try routing(bodies[0]) == nil)
        #expect(try routing(bodies[1])?["ignore"] == ["Flaky"])
        // The same request again: no nudge was added.
        #expect(try lastUserText(bodies[1]) == "What is this project?")
    }

    @Test func providersThatLostACallStayAvoidedForTheRun() async throws {
        let (client, host) = MockServer.client(.init(turns: [
            Routed.lost(provider: "Flaky"),
            Routed.lost(provider: "Worse"),
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            Routed.content("Done.", provider: "Solid"),
        ]))
        var config = AgentConfig(tools: ReadTools.all)
        config.providers = ProviderRouting(ignore: ["Banned"])
        let events = try await run(client, config: config)
        #expect(events.stop == .completed && events.retries.count == 2)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 4)
        #expect(try routing(bodies[0])?["ignore"] == ["Banned"])
        #expect(try routing(bodies[1])?["ignore"] == ["Banned", "Flaky"])
        #expect(try routing(bodies[2])?["ignore"] == ["Banned", "Flaky", "Worse"])
        #expect(try routing(bodies[3])?["ignore"] == ["Banned", "Flaky", "Worse"])     // the next turn too
    }

    @Test func goesToTheFallbackModelWhenNoProviderIsLeft() async throws {
        let (client, host) = MockServer.client(.init(turns: [Routed.lost(provider: "Flaky"), []], turnStatuses: [1: 404]))
        let (backup, backupHost) = MockServer.client(.init(turns: [SSE.content("From the fallback.", model: "backup")]))
        var config = AgentConfig(tools: ReadTools.all)
        let backupID = UUID()
        config.fallback = FallbackModel(client: backup, model: "backup", endpointID: backupID)
        let events = try await run(client, config: config)
        #expect(events.stop == .completed)
        #expect(events.assistants.count == 2)
        #expect(events.assistants.last?.content == "From the fallback.")
        #expect(events.assistants.last?.meta?.endpointID == backupID)
        #expect(events.retries.count == 3)       // to another provider; none took it; to the fallback
        #expect(events.retries[1].hasPrefix("No other provider took it"))
        #expect(MockServer.requestBodies(host).count == 2)
        let fallbackRequest = try #require(MockServer.requestBodies(backupHost).first)
        #expect(try routing(fallbackRequest) == nil)          // provider preferences are the main model's
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: fallbackRequest) else { return }
        #expect(o["model"] == "backup")
    }

    @Test func nudgesWhenThereIsNowhereElseToGo() async throws {
        // Not OpenRouter (no provider named) and no fallback: the old behavior, a nudge.
        let (client, host) = MockServer.client(.init(turns: [Routed.lost(provider: nil), SSE.content("Answer.")]))
        let events = try await run(client)
        #expect(events.stop == .completed && events.retries.isEmpty)
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 2)
        #expect(try lastUserText(bodies[1])?.contains("could not read your tool call") == true)
    }
}

/// Rate limits read from responses, Google's suggested waits, and retired models.
@Suite struct RateLimitTests {
    @Test func waitsForAUsedUpWindowOnly() async {
        let book = RateLimits()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(20))
        await book.record(host: "h", headers: ["anthropic-ratelimit-requests-remaining": "40", "anthropic-ratelimit-requests-reset": reset,
                                               "anthropic-ratelimit-input-tokens-remaining": "250000",
                                               "anthropic-ratelimit-input-tokens-reset": reset], now: now)
        #expect(await book.pause(host: "h", now: now) == 0)
        await book.record(host: "h", headers: ["Anthropic-Ratelimit-Input-Tokens-Remaining": "0",
                                               "anthropic-ratelimit-input-tokens-reset": reset], now: now)
        #expect(await book.pause(host: "h", now: now) == 20)
        #expect(await book.pause(host: "h", now: now.addingTimeInterval(30)) == 0)   // after the reset
        #expect(await book.pause(host: "other", now: now) == 0)
    }

    @Test func windowsAreKeptPerModelClassAndKey() async {
        let book = RateLimits()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(20))
        let host = "api.anthropic.com"
        let haiku = RateLimits.scope(host: host, apiKey: "k1", model: "claude-haiku-5-5-20260101")
        let sonnet = RateLimits.scope(host: host, apiKey: "k1", model: "claude-sonnet-5")
        let otherKey = RateLimits.scope(host: host, apiKey: "k2", model: "claude-haiku-5-5")
        #expect(haiku == RateLimits.scope(host: host, apiKey: "k1", model: "claude-haiku-5-5"))
        #expect(!haiku.contains("k1"))
        await book.record(host: haiku, headers: ["anthropic-ratelimit-requests-remaining": "0",
                                                 "anthropic-ratelimit-requests-reset": reset], now: now)
        #expect(await book.pause(host: haiku, now: now) == 20)
        #expect(await book.pause(host: sonnet, now: now) == 0)
        #expect(await book.pause(host: otherKey, now: now) == 0)
        #expect(RateLimits.scope(host: "g", apiKey: nil, model: "gemini-2.5-pro")
                != RateLimits.scope(host: "g", apiKey: nil, model: "gemini-2.5-flash"))
    }

    @Test func readsGooglesRetryDelay() {
        let body = #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"23s"}]}}"#
        #expect(RateLimits.retryDelay(fromBody: Data(body.utf8)) == 23)
        #expect(RateLimits.retryDelay(fromBody: Data(#"{"error":{"code":429}}"#.utf8)) == nil)
    }

    @Test func aMissingModelSaysWhatToDo() async throws {
        let body = Data(#"{"type":"error","error":{"type":"not_found_error","message":"model: claude-old-preview"}}"#.utf8)
        let (client, _) = MockServer.client(.init(status: 404, chunks: [body]), api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "claude-old-preview", messages: [.user("x")], maxTokens: 10),
                                         limits: TurnLimits(maxTokens: 10, wallClock: 10)) { _ in }
        #expect(reply.meta?.error?.contains("model: claude-old-preview") == true)
        #expect(reply.meta?.error?.contains("doesn't offer claude-old-preview") == true)
    }
}

/// Every request is a cost entry; a lost reply that was retried elsewhere is marked as an attempt.
@Suite struct RetryCostTests {
    @Test func aLostReplyIsARetryAttempt() async throws {
        let (client, _) = MockServer.client(.init(turns: [
            Routed.lost(provider: "Flaky"),
            Routed.content("It is a demo project.", provider: "Solid"),
        ]))
        let events = try await run(client)
        let costs = events.all.compactMap { if case .cost(let e) = $0 { e } else { nil } }
        #expect(costs.map(\.purpose) == [.retryAttempt, .reply])
        #expect(costs.map(\.provider) == ["Flaky", "Solid"])
        #expect(costs.map(\.reply) == events.assistants.map(\.id))
    }
}
