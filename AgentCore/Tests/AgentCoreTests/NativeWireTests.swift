import Foundation
import Testing
@testable import AgentCore

/// Anthropic's and Google's native APIs: what goes out, what comes back, and what goes back again.
@Suite struct NativeWireTests {
    static let readTool = ToolDefinition(name: "read_file", description: "Read a file.",
                                         parameters: ["type": "object", "properties": ["path": ["type": "string"]],
                                                      "additionalProperties": false])

    func json(_ data: Data) throws -> [String: JSONValue] {
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data) else { throw ToolFailure("not an object") }
        return o
    }

    func run(_ fixture: String, api: WireAPI, model: String) async throws -> (ChatMessage, String) {
        let (client, host) = MockServer.client(try MockServer.sse(fixture: fixture), api: api)
        let reply = await TurnRunner.run(client: client,
                                         request: ChatRequest(model: model, messages: [.system("sys"), .user("read the config")],
                                                              tools: [Self.readTool], maxTokens: 4096),
                                         limits: TurnLimits(maxTokens: 4096, wallClock: 30)) { _ in }
        return (reply, host)
    }

    // MARK: - Anthropic

    @Test func anthropicRequestShape() throws {
        let call = ToolCall(id: "call:1/x", name: "read_file", arguments: #"{"path":"a.txt"}"#)
        let req = ChatRequest(model: "claude-opus-5-5",
                              messages: [.system("You are kurtkode."), .user("hi"),
                                         ChatMessage(role: .assistant, content: "Reading.", toolCalls: [call]),
                                         ChatMessage(role: .tool, content: "file text", toolCallID: "call:1/x"),
                                         .user("and then?")],
                              tools: [Self.readTool], maxTokens: 8192, temperature: 0.2)
        var r = req
        r.reasoningEffort = "high"
        let o = try json(AnthropicWire.encodeRequest(r))
        #expect(o["system"] == "You are kurtkode.")
        #expect(o["max_tokens"] == 8192)
        #expect(o["cache_control"] == ["type": "ephemeral"])
        #expect(o["temperature"] == nil)       // the newest models reject sampling settings
        #expect(o["thinking"] == ["type": "adaptive", "display": "summarized",
                                  "block_binding": ["prefix_mismatch_behavior": "drop_block"]])
        #expect(o["output_config"] == ["effort": "high"])
        #expect(o["fallbacks"] == "default")
        guard case .array(let tools)? = o["tools"], case .object(let tool) = tools[0] else { Issue.record("tools"); return }
        #expect(tool["input_schema"] == Self.readTool.parameters)
        guard case .array(let msgs)? = o["messages"] else { Issue.record("messages"); return }
        #expect(msgs.count == 3)   // user, assistant, user (the tool result and the next words in one message)
        #expect(msgs[1] == ["role": "assistant", "content": [["type": "text", "text": "Reading."],
                                                            ["type": "tool_use", "id": "call_1_x", "name": "read_file",
                                                             "input": ["path": "a.txt"]]]])
        #expect(msgs[2] == ["role": "user", "content": [["type": "tool_result", "tool_use_id": "call_1_x", "content": "file text"],
                                                       ["type": "text", "text": "and then?"]]])
    }

    @Test func anthropicHourLongCacheAndSummariesKeepTheCache() async throws {
        var r = ChatRequest(model: "claude-opus-5-5", messages: [.user("hi")], maxTokens: 100)
        r.cacheForAnHour = true
        #expect(try json(AnthropicWire.encodeRequest(r))["cache_control"] == ["type": "ephemeral", "ttl": "1h"])

        // A summary without thinking keeps Claude's effort (the cached history stays valid) and the cache's length.
        let reply = #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10}}}"#
        let text = ###"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"## Summary\nThe user asked for a config change; config.toml was read and edited, and the tests pass now."}}"###
        let stop = #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":30}}"#
        let (client, host) = MockServer.client(MockServer.Route(chunks: [reply, text, stop].map { Data("data: \($0)\n".utf8) }), api: .anthropic)
        let summary = await Compactor.summarize(client: client, model: "claude-opus-5-5", messages: [.system("sys"), .user("go")],
                                                tools: [], limits: TurnLimits(), thinking: false, cacheForAnHour: true)
        #expect(summary?.hasPrefix("## Summary") == true)
        let sent = try json(try #require(MockServer.requestBody(host)))
        #expect(sent["output_config"] == nil)
        #expect(sent["cache_control"] == ["type": "ephemeral", "ttl": "1h"])
        #expect(sent["max_tokens"] == 16000)          // room for Claude's thinking beyond the summary

        // Replies from the native APIs get their own limits; a profile's output limit still wins.
        let settings = RunSettings()
        #expect(settings.limits(for: ModelProfile(endpointID: UUID(), model: "m"), api: .anthropic) == TurnLimits(maxTokens: 32768, wallClock: 1800))
        #expect(settings.limits(for: ModelProfile(endpointID: UUID(), model: "m"), api: .openai) == TurnLimits(maxTokens: 8192, wallClock: 600))
        var p = ModelProfile(endpointID: UUID(), model: "m")
        p.maxOutputTokens = 64000
        #expect(settings.limits(for: p, api: .gemini).maxTokens == 64000)
    }

    @Test func anthropicOlderModelsTakeBudgetsAndSampling() throws {
        var r = ChatRequest(model: "claude-haiku-4-5", messages: [.user("hi")], maxTokens: 8192, temperature: 0.3)
        var o = try json(AnthropicWire.encodeRequest(r))
        #expect(o["thinking"] == nil)
        #expect(o["temperature"] == 0.3)
        #expect(o["fallbacks"] == nil)
        r.reasoningEffort = "medium"
        o = try json(AnthropicWire.encodeRequest(r))
        #expect(o["thinking"] == ["type": "enabled", "budget_tokens": 7168])   // leaves 1024 for the answer
        #expect(o["temperature"] == nil)
        r.model = "claude-sonnet-4-6"
        r.reasoningEffort = "none"
        o = try json(AnthropicWire.encodeRequest(r))
        #expect(o["thinking"] == ["type": "disabled"])
        #expect(AnthropicWire.generation("claude-sonnet-4-20250514") == .budget)
        #expect(AnthropicWire.generation("claude-fable-5-1") == .current)
    }

    @Test func anthropicHeaders() throws {
        let client = ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, apiKey: "k", api: .anthropic)
        let body = try client.encode(ChatRequest(model: "claude-opus-5-5", messages: [.user("hi")], maxTokens: 100))
        let r = client.streamRequest(body: body, model: "claude-opus-5-5")
        #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "thinking-binding-controls-2026-08-01,server-side-fallback-2026-07-01")
        let pasted = ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, apiKey: " k\n", api: .anthropic)
        #expect(pasted.streamRequest(body: body, model: "claude-opus-5-5").value(forHTTPHeaderField: "x-api-key") == "k")
        let old = try client.encode(ChatRequest(model: "claude-haiku-4-5", messages: [.user("hi")], maxTokens: 100))
        #expect(client.streamRequest(body: old, model: "claude-haiku-4-5").value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func anthropicStreamRoundTripsThinking() async throws {
        let (reply, _) = try await run("sse_anthropic_thinking_tool", api: .anthropic, model: "claude-opus-5-5")
        #expect(reply.meta?.error == nil)
        #expect(reply.reasoning == "The user wants the config. I should read it first.")
        #expect(reply.content == "Reading the config.")
        #expect(reply.toolCalls == [ToolCall(id: "toolu_01AbC", name: "read_file", arguments: #"{"path": "config.toml"}"#)])
        #expect(reply.meta?.finishReason == .toolCalls)
        // At Opus 5.5's list price: 120 fresh × $4 + 2400 read × $0.20 + 87 out × $20, per million.
        var usage = try #require(reply.meta?.usage)
        #expect(abs((usage.cost ?? 0) - 0.0027) < 1e-12 && usage.costIsEstimate == true)
        usage.cost = nil
        usage.costIsEstimate = nil
        #expect(usage == Usage(promptTokens: 2520, completionTokens: 87, reasoningTokens: 40, cacheReadTokens: 2400, cacheWriteTokens: 0))
        #expect(reply.meta?.usage?.cacheSummary == "95% cached")
        #expect(reply.meta?.notes?.first?.contains("dropped 1 earlier thinking block (prefix_binding_mismatch)") == true)
        let native = try #require(reply.native)
        #expect(native.api == .anthropic && native.model == "claude-opus-5-5")
        guard case .array(let blocks) = native.blocks else { Issue.record("blocks"); return }
        #expect(blocks[0] == ["type": "thinking", "thinking": "The user wants the config. I should read it first.",
                              "signature": "EqQBCkYIARgCSkAsig=="])
        #expect(blocks[2] == ["type": "tool_use", "id": "toolu_01AbC", "name": "read_file", "input": ["path": "config.toml"]])

        // Sent back unchanged to the same model; without its thinking to another; rebuilt once the loop changes it.
        let result = ChatMessage(role: .tool, content: "x = 1", toolCallID: "toolu_01AbC")
        func assistant(_ model: String, _ m: ChatMessage) throws -> JSONValue {
            let o = try json(AnthropicWire.encodeRequest(ChatRequest(model: model, messages: [.user("read the config"), m, result],
                                                                     maxTokens: 100)))
            guard case .array(let msgs)? = o["messages"], case .object(let a) = msgs[1] else { throw ToolFailure("shape") }
            return a["content"] ?? .null
        }
        #expect(try assistant("claude-opus-5-5", reply) == native.blocks)
        #expect(NativeWire.carriesReasoning(reply, api: .anthropic, model: "claude-opus-5-5"))
        #expect(!NativeWire.carriesReasoning(reply, api: .anthropic, model: "claude-sonnet-5-5"))
        #expect(try assistant("claude-sonnet-5-5", reply) == .array(Array(blocks.dropFirst())))
        var renamed = reply
        renamed.toolCalls[0].name = "read"
        #expect(try assistant("claude-opus-5-5", renamed) == [["type": "text", "text": "Reading the config."],
                                                              ["type": "tool_use", "id": "toolu_01AbC", "name": "read",
                                                               "input": ["path": "config.toml"]]])
    }

    @Test func anthropicFallbackVoidsEarlierCallsAndRefusalIsNoted() async throws {
        let lines = [
            #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_a","name":"bash","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-5"}}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":"I can't help with that."}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber","explanation":"Looks like malware."}},"usage":{"output_tokens":9}}"#,
        ]
        let route = MockServer.Route(chunks: lines.map { Data("data: \($0)\n\n".utf8) })
        let (client, _) = MockServer.client(route, api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "claude-opus-5-5", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.toolCalls.isEmpty)
        #expect(reply.content == "I can't help with that.")
        #expect(reply.meta?.finishReason == .other)
        #expect(reply.meta?.notes == ["claude-opus-5-5 declined; claude-opus-5 continued (server-side fallback).",
                                      "The model declined to answer (cyber): Looks like malware."])
        #expect(reply.native?.model == "claude-opus-5")
        // The reply was written, and priced, by the fallback model: the cost record says so.
        #expect(reply.meta?.reportedModel == "claude-opus-5")
    }

    @Test func anthropicStreamWithoutStopReasonIsCut() async throws {
        let lines = [#"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":1}}}"#,
                     #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Half"}}"#]
        let (client, _) = MockServer.client(MockServer.Route(chunks: lines.map { Data("data: \($0)\n".utf8) }), api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "claude-opus-5-5", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.stopReason == .failed)
        #expect(reply.content == "Half")
        #expect(reply.native == nil)
    }

    @Test func anthropicErrorEventFailsTheTurn() async throws {
        let lines = [#"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10}}}"#,
                     #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#]
        let (client, _) = MockServer.client(MockServer.Route(chunks: lines.map { Data("data: \($0)\n".utf8) }), api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "claude-opus-5-5", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.stopReason == .failed)
        #expect(reply.meta?.error?.contains("overloaded_error: Overloaded") == true)
    }

    @Test func anthropicImagesAndHistoryEnds() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.png")
        try Data([1, 2, 3]).write(to: file)
        var user = ChatMessage.user("what's this?")
        user.images = [ImageAttachment(mediaType: "image/png", path: file.path, width: 1, height: 1)]
        let msgs = AnthropicWire.encodeMessages([ChatMessage(role: .assistant, content: "earlier"), user,
                                                 ChatMessage(role: .assistant, content: "a picture")],
                                                model: "claude-opus-5-5", images: true)
        #expect(msgs.count == 5)
        #expect(msgs[0] == ["role": "user", "content": [["type": "text", "text": "(The conversation continues.)"]]])
        #expect(msgs[2] == ["role": "user", "content": [
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "AQID"]],
            ["type": "text", "text": "what's this?"]]])
        #expect(msgs[4] == ["role": "user", "content": [["type": "text", "text": "Continue."]]])
        // The wire log keeps a note in place of the data.
        let body = try AnthropicWire.encodeRequest(ChatRequest(model: "claude-opus-5-5", messages: [user], maxTokens: 10, sendImages: true))
        #expect(!String(decoding: try JSONEncoder().encode(WireRecord.compactRequest(body)), as: UTF8.self).contains("AQID"))
    }

    @Test func listPrices() throws {
        func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
        let u = Usage(promptTokens: 1_000_000, completionTokens: 0, cacheReadTokens: 600_000, cacheWriteTokens: 300_000,
                      cacheWriteHourTokens: 100_000)
        // 100k fresh × 4 + 600k × 0.20 + 200k × 5 (1.25×) + 100k × 8 (2×), per million.
        #expect(abs(PriceList.cost(u, api: .anthropic, model: "claude-opus-5-5")! - (0.4 + 0.12 + 1.0 + 0.8)) < 1e-9)
        #expect(PriceList.price(api: .anthropic, model: "claude-opus-5")?.input == 5)
        #expect(PriceList.price(api: .anthropic, model: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(PriceList.price(api: .anthropic, model: "claude-opus-4-1") == nil)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash-lite") == nil)
        #expect(PriceList.price(api: .gemini, model: "gemini-3-flash-preview")?.input == 0.5)
        #expect(PriceList.price(api: .gemini, model: "gemini-3.8-flash", on: day("2026-12-31"))?.input == 0.75)
        #expect(PriceList.price(api: .gemini, model: "gemini-3.8-flash", on: day("2027-01-01"))?.input == 1.5)
        // Long prompts on Gemini Pro: 300k at $4 instead of $2.
        let long = Usage(promptTokens: 300_000, completionTokens: 0, cacheReadTokens: 0)
        #expect(abs(PriceList.cost(long, api: .gemini, model: "gemini-3.1-pro-preview")! - 1.2) < 1e-9)
        #expect(Usage(promptTokens: 1, completionTokens: 1, cost: 0.01234, costIsEstimate: true).costText() == "≈$0.0123 (list price)")
    }

    // MARK: - Gemini

    @Test func geminiRequestShape() throws {
        let calls = [ToolCall(id: "call_0", name: "read_file", arguments: #"{"path":"a"}"#),
                     ToolCall(id: "call_1", name: "read_file", arguments: #"{"path":"b"}"#)]
        var r = ChatRequest(model: "gemini-3-flash-preview",
                            messages: [.system("sys"), .user("hi"),
                                       ChatMessage(role: .assistant, content: "", toolCalls: calls),
                                       ChatMessage(role: .tool, content: "A", toolCallID: "call_0"),
                                       ChatMessage(role: .tool, content: "B", toolCallID: "call_1")],
                            tools: [Self.readTool], maxTokens: 2048)
        r.reasoningEffort = "none"
        let o = try json(GeminiWire.encodeRequest(r))
        #expect(o["model"] == nil)
        #expect(o["systemInstruction"] == ["parts": [["text": "sys"]]])
        #expect(o["generationConfig"] == ["maxOutputTokens": 2048,
                                          "thinkingConfig": ["includeThoughts": true, "thinkingLevel": "minimal"]])
        #expect(o["tools"] == [["functionDeclarations": [["name": "read_file", "description": "Read a file.",
                                                          "parametersJsonSchema": Self.readTool.parameters]]]])
        guard case .array(let contents)? = o["contents"] else { Issue.record("contents"); return }
        #expect(contents.count == 3)
        // Rebuilt calls carry the stand-in signature on the step's first call; both results go back together.
        #expect(contents[1] == ["role": "model", "parts": [
            ["functionCall": ["name": "read_file", "args": ["path": "a"]], "thoughtSignature": "skip_thought_signature_validator"],
            ["functionCall": ["name": "read_file", "args": ["path": "b"]]]]])
        #expect(contents[2] == ["role": "user", "parts": [
            ["functionResponse": ["name": "read_file", "response": ["output": "A"]]],
            ["functionResponse": ["name": "read_file", "response": ["output": "B"]]]]])

        r.model = "gemini-2.5-flash"
        r.reasoningEffort = "low"
        let old = try json(GeminiWire.encodeRequest(r))
        #expect(old["generationConfig"] == ["maxOutputTokens": 2048, "thinkingConfig": ["includeThoughts": true, "thinkingBudget": 1024]])
        guard case .array(let oldContents)? = old["contents"], case .object(let m) = oldContents[1],
              case .array(let parts)? = m["parts"], case .object(let first) = parts[0] else { Issue.record("old"); return }
        #expect(first["thoughtSignature"] == nil)
    }

    @Test func geminiURLAndKey() {
        let client = ChatClient(baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!, apiKey: "g", api: .gemini)
        let r = client.streamRequest(body: Data("{}".utf8), model: "gemini-3-flash-preview")
        #expect(r.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent?alt=sse")
        #expect(r.value(forHTTPHeaderField: "x-goog-api-key") == "g")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func geminiStreamRoundTripsSignatures() async throws {
        let (reply, _) = try await run("sse_gemini_thought_call", api: .gemini, model: "gemini-3-flash-preview")
        #expect(reply.meta?.error == nil)
        #expect(reply.reasoning == "**Finding the config**\n\nI'll look for the file.")
        #expect(reply.content == "Let me read it.")
        #expect(reply.toolCalls.map(\.name) == ["read_file", "list_dir"])
        #expect(reply.toolCalls.map(\.arguments) == [#"{"path":"config.toml"}"#, #"{"path":"."}"#])
        #expect(reply.meta?.finishReason == .toolCalls)
        #expect(reply.meta?.usage?.cacheReadTokens == 0)
        #expect(reply.meta?.usage?.reasoningTokens == 120 && reply.meta?.usage?.completionTokens == 160)
        let native = try #require(reply.native)
        guard case .array(let parts) = native.blocks else { Issue.record("parts"); return }
        #expect(parts.count == 4)     // thought, the text merged, two calls
        #expect(parts[1] == ["text": "Let me read it."])
        #expect(parts[2] == ["functionCall": ["name": "read_file", "args": ["path": "config.toml"]], "thoughtSignature": "CiQBjz1rX0sig"])

        let results = reply.toolCalls.map { ChatMessage(role: .tool, content: "ok", toolCallID: $0.id) }
        func modelParts(_ model: String, _ m: ChatMessage) throws -> JSONValue {
            let o = try json(GeminiWire.encodeRequest(ChatRequest(model: model, messages: [.user("go"), m] + results, maxTokens: 100)))
            guard case .array(let c)? = o["contents"], case .object(let turn) = c[1] else { throw ToolFailure("shape") }
            return turn["parts"] ?? .null
        }
        #expect(try modelParts("gemini-3-flash-preview", reply) == native.blocks)
        #expect(NativeWire.carriesReasoning(reply, api: .gemini, model: "gemini-3-flash-preview"))
        let other = try modelParts("gemini-3-pro-preview", reply)
        #expect(other != native.blocks)
        guard case .array(let rebuilt) = other, case .object(let call) = rebuilt[1] else { Issue.record("rebuilt"); return }
        #expect(call["thoughtSignature"] == "skip_thought_signature_validator")
    }

    @Test func geminiBlockedPromptAndCutStream() async throws {
        let blocked = [#"{"promptFeedback":{"blockReason":"SAFETY"},"usageMetadata":{"promptTokenCount":5}}"#]
        var (client, _) = MockServer.client(MockServer.Route(chunks: blocked.map { Data("data: \($0)\n".utf8) }), api: .gemini)
        var reply = await TurnRunner.run(client: client, request: ChatRequest(model: "gemini-3-flash-preview", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.finishReason == .other)
        #expect(reply.meta?.notes == ["Gemini blocked the prompt (SAFETY)."])

        let cut = [#"{"candidates":[{"content":{"parts":[{"text":"Half"}],"role":"model"}}]}"#]
        (client, _) = MockServer.client(MockServer.Route(chunks: cut.map { Data("data: \($0)\n".utf8) }), api: .gemini)
        reply = await TurnRunner.run(client: client, request: ChatRequest(model: "gemini-3-flash-preview", messages: [.user("x")], maxTokens: 100),
                                     limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.stopReason == .failed)
    }

    // MARK: - Steps and shown reasoning

    @Test func stepsKeepTheServersOrder() async throws {
        let (claude, _) = try await run("sse_anthropic_thinking_tool", api: .anthropic, model: "claude-opus-5-5")
        let (steps, ordered) = ReplySteps.steps(of: claude)
        #expect(ordered)
        #expect(steps.map(\.kind) == [.thinking("The user wants the config. I should read it first."), .text("Reading the config."),
                                      .call(claude.toolCalls[0])])
        // 40 thinking tokens billed; the summary is 50 bytes, about 13 tokens.
        let shown = ReasoningShown(claude)
        #expect(shown.billedTokens == 40 && shown.shownTokens == 13 && shown.isSummary)
        #expect(shown.summary == "Thought for 40 tokens; shown: a summary of about 13 (33%)")

        let (gemini, _) = try await run("sse_gemini_thought_call", api: .gemini, model: "gemini-3-flash-preview")
        #expect(ReplySteps.steps(of: gemini).steps.map(\.kind) == [.thinking("**Finding the config**\n\nI'll look for the file."),
                                                                   .text("Let me read it."), .call(gemini.toolCalls[0]),
                                                                   .call(gemini.toolCalls[1])])

        // Thinking that left only its signature, a fallback, and a local model's reasoning (order unknown).
        var hidden = ChatMessage(role: .assistant, content: "")
        hidden.native = NativeContent(api: .anthropic, model: "claude-opus-5-5", blocks: [
            ["type": "thinking", "thinking": "", "signature": .string(String(repeating: "s", count: 2048))],
            ["type": "fallback", "from": ["model": "claude-opus-5-5"], "to": ["model": "claude-opus-5"]],
            ["type": "text", "text": "Done."]])
        #expect(ReplySteps.steps(of: hidden).steps.map(\.kind) == [.hiddenThinking(bytes: 2048),
                                                                   .server("claude-opus-5-5 declined; claude-opus-5 continued"), .text("Done.")])
        var local = ChatMessage(role: .assistant, content: "Answer", reasoning: "Hmm, let me think.",
                                toolCalls: [ToolCall(id: "1", name: "grep", arguments: "{}")])
        local.meta = TurnMeta(requestedModel: "gemma", usage: Usage(promptTokens: 10, completionTokens: 9, reasoningTokens: 5),
                              stopReason: .completed, duration: 1)
        let (localSteps, localOrdered) = ReplySteps.steps(of: local)
        #expect(!localOrdered && localSteps.count == 3)
        #expect(ReasoningShown(local).summary == "Thought for 5 tokens; all of it shown" && ReasoningShown(local).shownShare == 1)
    }

    // MARK: - Endpoints, wire records, replay

    @Test func endpointsSaveNativeKindsReadablyByOlderBuilds() throws {
        let e = Endpoint(name: "Claude", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!, usesAPIKey: true)
        let data = try JSONEncoder().encode(e)
        let o = try json(data)
        #expect(o["kind"] == "openai")
        #expect(o["api"] == "anthropic")
        #expect(try JSONDecoder().decode(Endpoint.self, from: data) == e)
        let old = Data(#"{"id":"A7E319B8-27CB-41B5-9BD5-97D2C716405C","name":"Openrouter","kind":"openai","baseURL":"https://openrouter.ai/api/v1","usesAPIKey":true}"#.utf8)
        #expect(try JSONDecoder().decode(Endpoint.self, from: old).kind == .openai)
        #expect(Endpoint.detectedKind(URL(string: "https://api.anthropic.com/v1")!) == .anthropic)
        #expect(Endpoint.detectedKind(URL(string: "https://generativelanguage.googleapis.com/v1beta")!) == .gemini)
        #expect(Endpoint.detectedKind(URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!) == .openai)
        #expect(Endpoint.normalizedBaseURL(URL(string: "https://api.anthropic.com/v1/messages")!).absoluteString == "https://api.anthropic.com/v1")
    }

    @Test func wireRecordsAndReplaysOfNativeRequests() throws {
        let anthropicBody = try AnthropicWire.encodeRequest(ChatRequest(model: "claude-opus-5-5", messages: [.system("sys"), .user("hi")],
                                                                        maxTokens: 500))
        let a = WireRecord(replyID: UUID(), startedAt: Date(), duration: 1, url: "https://api.anthropic.com/v1/messages",
                           request: WireRecord.compactRequest(anthropicBody), statuses: [200], lines: [])
        #expect(a.api == .anthropic)
        #expect(a.messages.first == ["role": "system", "content": "sys"])
        #expect(a.messages.count == 2)
        var (body, _) = try Replay.body(from: a, options: ReplayOptions(model: "claude-sonnet-5-5", reasoningEffort: "max", systemPrompt: "new"))
        var o = try json(body)
        #expect(o["model"] == "claude-sonnet-5-5")
        #expect(o["system"] == "new")
        #expect(o["output_config"] == ["effort": "max"])
        #expect(throws: ToolFailure.self) { try Replay.body(from: a, options: ReplayOptions(model: "x"), api: .openai) }
        let curl = Replay.curl(a)
        #expect(curl.contains("x-api-key: $KURTKODE_API_KEY") && curl.contains("anthropic-version: 2023-06-01")
                && curl.contains("anthropic-beta: thinking-binding-controls-2026-08-01"))

        let geminiBody = try GeminiWire.encodeRequest(ChatRequest(model: "gemini-3-flash-preview", messages: [.system("sys"), .user("hi")],
                                                                  maxTokens: 500))
        let g = WireRecord(replyID: UUID(), startedAt: Date(), duration: 1,
                           url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent?alt=sse",
                           request: WireRecord.compactRequest(geminiBody), statuses: [200], lines: [])
        #expect(g.api == .gemini)
        #expect(Replay.model(of: g) == "gemini-3-flash-preview")
        #expect(g.messages == [["role": "system", "content": "sys"], ["role": "user", "parts": [["text": "hi"]]]])
        (body, _) = try Replay.body(from: g, options: ReplayOptions(model: "gemini-3-pro-preview", temperature: 0.5, reasoningEffort: "high"))
        o = try json(body)
        #expect(o["model"] == nil)
        #expect(o["generationConfig"] == ["maxOutputTokens": 500, "temperature": 0.5,
                                          "thinkingConfig": ["includeThoughts": true, "thinkingLevel": "high"]])
        #expect(Replay.curl(g).contains("x-goog-api-key: $KURTKODE_API_KEY"))
    }
}

/// Refusals and summarized thinking aren't lost replies.
@Suite struct DeclinedReplyTests {
    static func sse(_ events: [String]) -> [Data] { events.map { Data("data: \($0)\n\n".utf8) } }

    @Test func aRefusalIsNeitherRetriedNorNudged() async throws {
        let refusal = Self.sse([
            #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":50}}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}},"usage":{"output_tokens":40}}"#])
        let (client, host) = MockServer.client(.init(turns: [refusal]), api: .anthropic)
        let (fallbackClient, fallbackHost) = MockServer.client(.init(turns: [SSE.content("Sure, here it is.")]))
        var config = AgentConfig(tools: ReadTools.all)
        config.fallback = FallbackModel(client: fallbackClient, model: "local")
        final class Box: @unchecked Sendable { var replies: [ChatMessage] = []; var stop: AgentStop? }
        let box = Box()
        await AgentLoop.run(client: client, model: "claude-opus-5-5", systemPrompt: "SYSTEM", history: [.user("x")], config: config,
                            workspace: try makeProject()) { e in
            if case .assistant(let m) = e { box.replies.append(m) }
            if case .finished(let s) = e { box.stop = s }
        }
        #expect(MockServer.requestBodies(host).count == 1)
        #expect(MockServer.requestBodies(fallbackHost).isEmpty)
        let reply = try #require(box.replies.first)
        #expect(box.replies.count == 1 && reply.meta?.declined == true && !AgentLoop.droppedCall(reply))
        #expect(reply.meta?.notes == ["The model declined to answer (cyber)."])
        #expect(box.stop == .completed)
    }

    @Test func summarizedThinkingIsntALostReply() {
        var m = ChatMessage(role: .assistant, content: "", reasoning: "Checked the file; nothing to change.")
        m.meta = TurnMeta(requestedModel: "claude-opus-5-5",
                          usage: Usage(promptTokens: 100, completionTokens: 2000, reasoningTokens: 1995),
                          finishReason: .stop, stopReason: .completed, duration: 1)
        #expect(!AgentLoop.droppedCall(m))
        m.meta?.usage?.reasoningTokens = 0            // the same output with nothing said about thinking: lost
        #expect(AgentLoop.droppedCall(m))
        // Gemini's safety stop and OpenAI's content filter are declines too.
        #expect(GeminiStreamDecoder.declinedReasons.contains("SAFETY"))
        let filtered = try? WireFormat.events(fromChunk: Data(#"{"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#.utf8))
        #expect(filtered?.contains(.declined) == true)
    }
}

/// What switching models costs, and what stays on this Mac with a remote model.
@Suite struct SwitchAndPrivacyTests {
    @Test func switchingCostsAWholeUncachedPrompt() throws {
        // 100k tokens written to Opus 5.5's cache at 1.25 × $4 per million; Gemini 3 Flash reads them at $0.50.
        #expect(abs(PriceList.switchCost(promptTokens: 100_000, api: .anthropic, model: "claude-opus-5-5")! - 0.5) < 1e-9)
        #expect(abs(PriceList.switchCost(promptTokens: 100_000, api: .gemini, model: "gemini-3-flash-preview")! - 0.05) < 1e-9)
        #expect(PriceList.switchCost(promptTokens: 100_000, api: .openai, model: "qwen") == nil)
        #expect(PriceList.switchNote(promptTokens: 5000, api: .anthropic, model: "claude-opus-5-5", fromThinking: false) == nil)
        let note = try #require(PriceList.switchNote(promptTokens: 120_000, api: .anthropic, model: "claude-opus-5-5", fromThinking: true))
        #expect(note.contains("120k tokens") && note.contains("$0.60") && note.contains("Claude's earlier thinking"))
        #expect(PriceList.switchNote(promptTokens: 120_000, api: .openai, model: "gemma", fromThinking: false)?.contains("local") == true)
    }

    @Test func thirdPartyServersAndWithheldFiles() {
        func url(_ s: String) -> URL { URL(string: s)! }
        #expect(Endpoint.isThirdParty(url("https://openrouter.ai/api/v1")))
        #expect(!Endpoint.isThirdParty(url("http://127.0.0.1:1234/v1")))
        #expect(!Endpoint.isThirdParty(url("http://192.168.1.20:1234/v1")))
        #expect(!Endpoint.isThirdParty(url("http://studio.local:1234/v1")))
        #expect(!Endpoint.isThirdParty(url("http://100.101.1.2:1234/v1")))     // Tailscale
        #expect(Endpoint(name: "C", kind: .anthropic, baseURL: url("https://api.anthropic.com/v1")).isThirdParty)
        let w = WithheldFiles(patterns: WithheldFiles.defaults + ["config/prod/*"], host: "h")
        #expect(w.matches(url("file:///p/.env")) && w.matches(url("file:///p/.env.local")) && w.matches(url("file:///p/certs/server.pem")))
        #expect(w.matches(url("file:///p/.ssh/id_ed25519")) && w.matches(url("file:///p/config/prod/db.yml")))
        #expect(!w.matches(url("file:///p/.env.example")) && !w.matches(url("file:///p/README.md")) && !w.matches(url("file:///p/keys.swift")))
    }

    @Test func aRemoteModelCantReadOrSearchSecrets() async throws {
        let ws = try makeProject()
        try Data("API_TOKEN=sk-live-123\n".utf8).write(to: ws.root.appending(path: ".env"))
        try Data("API_TOKEN=\n".utf8).write(to: ws.root.appending(path: ".env.example"))
        let turns = [SSE.toolCalls([("a", "read_file", #"{"path":".env"}"#), ("b", "grep", #"{"pattern":"API_TOKEN"}"#),
                                    ("c", "read_file", #"{"path":".env.example"}"#)]),
                     SSE.content("Done.")]
        let (client, host) = MockServer.client(.init(turns: turns))     // a host that isn't this Mac or the LAN
        var config = AgentConfig(tools: ReadTools.all)
        config.withheldFromRemote = WithheldFiles.defaults
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: ws) { _ in }
        let sent = String(decoding: try #require(MockServer.requestBodies(host).last), as: UTF8.self)
        #expect(!sent.contains("sk-live-123"))
        #expect(sent.contains("withheld from remote models"))
        #expect(sent.contains(".env.example:1: API_TOKEN="))           // the template is searched and read
    }
}

/// The servers' own web search.
@Suite struct WebSearchTests {
    @Test func claudeSearchesAreTheServersNotCallsToRun() async throws {
        var r = ChatRequest(model: "claude-opus-5-5", messages: [.user("x")], tools: [NativeWireTests.readTool], maxTokens: 100)
        r.webSearch = true
        guard case .array(let tools)? = try JSONDecoder().decode([String: JSONValue].self, from: AnthropicWire.encodeRequest(r))["tools"]
        else { Issue.record("tools"); return }
        #expect(tools.last == ["type": "web_search_20260209", "name": "web_search", "max_uses": 5])
        #expect(AnthropicWire.webSearchTool("claude-haiku-4-5") == "web_search_20250305")

        let events = [
            #"{"type":"message_start","message":{"model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"swift 6.2 release\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"Swift 6.2 Released","url":"https://swift.org/blog/swift-6.2","encrypted_content":"abc"}]}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Swift 6.2 is out."}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://swift.org/blog/swift-6.2","title":"Swift 6.2 Released","encrypted_index":"x","cited_text":"Swift 6.2"}}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":50,"server_tool_use":{"web_search_requests":1}}}"#]
        let (client, _) = MockServer.client(.init(chunks: events.map { Data("data: \($0)\n\n".utf8) }), api: .anthropic)
        let reply = await TurnRunner.run(client: client, request: r, limits: TurnLimits(maxTokens: 100, wallClock: 10)) { _ in }
        #expect(reply.toolCalls.isEmpty && reply.content == "Swift 6.2 is out.")
        #expect(reply.meta?.usage?.webSearches == 1)
        // 100 input × $4 + 50 output × $20 per million, plus $0.01 for the search.
        let cost: Double = reply.meta?.usage?.cost ?? 0
        let expected: Double = 0.0114
        #expect(abs(cost - expected) < 1e-9)
        let kinds: [ReplyStep.Kind] = ReplySteps.steps(of: reply).steps.map(\.kind)
        let want: [ReplyStep.Kind] = [.webSearch("swift 6.2 release"),
                                      .webResults(["Swift 6.2 Released — https://swift.org/blog/swift-6.2"]),
                                      .text("Swift 6.2 is out.")]
        #expect(kinds == want)
        guard case .array(let blocks)? = reply.native?.blocks, case .object(let text) = blocks[2] else { Issue.record("blocks"); return }
        #expect(text["citations"]?.arrayValue?.count == 1)
        // Sent back as they came (the search's encrypted results with it).
        let again = AnthropicWire.assistantBlocks(reply, model: "claude-opus-5-5")
        #expect(again.count == 3 && AnthropicWire.type(again[1]) == "web_search_tool_result")
    }

    @Test func geminiGroundsWithGoogleSearch() async throws {
        var r = ChatRequest(model: "gemini-3-flash-preview", messages: [.user("x")], tools: [NativeWireTests.readTool], maxTokens: 100)
        r.webSearch = true
        let body = try JSONDecoder().decode([String: JSONValue].self, from: GeminiWire.encodeRequest(r))
        #expect(body["tools"]?.arrayValue?.last == ["googleSearch": .object([:])])
        #expect(body["toolConfig"] == ["includeServerSideToolInvocations": true])
        let chunk = #"{"candidates":[{"content":{"parts":[{"text":"Swift 6.2 is out."}],"role":"model"},"finishReason":"STOP","groundingMetadata":{"webSearchQueries":["swift 6.2 release"]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}"#
        let (client, _) = MockServer.client(.init(chunks: [Data("data: \(chunk)\n\n".utf8)]), api: .gemini)
        let reply = await TurnRunner.run(client: client, request: r, limits: TurnLimits(maxTokens: 100, wallClock: 10)) { _ in }
        #expect(reply.meta?.notes == ["Searched the web: swift 6.2 release"])
        // The server-side call as Gemini returns it with function calling (a toolCall part) shows as a search step.
        var m = ChatMessage(role: .assistant, content: "Done.")
        m.native = NativeContent(api: .gemini, model: "gemini-3-flash-preview", blocks: [
            ["toolCall": ["args": ["queries": ["swift 6.2 release"]], "id": "call_1", "toolType": "GOOGLE_SEARCH_WEB"]],
            ["toolResponse": ["id": "call_1", "response": ["search_suggestions": "<style>…"]]],
            ["text": "Done."]])
        let kinds: [ReplyStep.Kind] = ReplySteps.steps(of: m).steps.map(\.kind)
        #expect(kinds == [.webSearch("swift 6.2 release"), .text("Done.")])
    }
}
