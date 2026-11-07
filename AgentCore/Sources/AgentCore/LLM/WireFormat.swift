import Foundation

// OpenAI Chat Completions wire format: request encoding and streamed-chunk decoding.

enum WireFormat {
    /// Where a request's `cacheKey` and `oneOff` go: OpenAI's own API, OpenRouter, or nowhere (other servers).
    enum CacheRouting { case none, openAI, openRouter }

    /// OpenAI models that bill cache writes (1.25× input from GPT-5.6; earlier models write for free), by name, with or
    /// without OpenRouter's "openai/".
    static func billsCacheWrites(_ model: String) -> Bool {
        let m = model.lowercased()
        let name = m.hasPrefix("openai/") ? String(m.dropFirst(7)) : m
        guard name.hasPrefix("gpt-") else { return false }
        let version = name.dropFirst(4).prefix { $0.isNumber || $0 == "." }.split(separator: ".").compactMap { Int($0) }
        guard let major = version.first else { return false }
        return major > 5 || (major == 5 && (version.dropFirst().first ?? 0) >= 6)
    }

    /// - Parameter completionTokens: name the output cap `max_completion_tokens` (OpenAI's own API, whose reasoning
    ///   models, GPT-5 and the o-series, refuse `max_tokens`); other servers get `max_tokens`, which all of them take.
    /// - Parameter routing: where the request's `cacheKey` and `oneOff` go.
    static func encodeRequest(_ request: ChatRequest, cacheBreakpoints: Bool = false, completionTokens: Bool = false,
                              routing: CacheRouting = .none) throws -> Data {
        var messages = request.messages.map { encodeMessage($0, reasoning: request.sendReasoning, images: request.sendImages) }
        if cacheBreakpoints { messages = withCacheBreakpoints(messages, hour: request.cacheForAnHour) }
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "stream": true,
            "stream_options": ["include_usage": true],
            (completionTokens ? "max_completion_tokens" : "max_tokens"): .number(Double(request.maxTokens)),
            "messages": .array(messages),
        ]
        if let t = request.temperature { body["temperature"] = .number(t) }
        switch routing {
        case .openAI:
            if let k = request.cacheKey { body["prompt_cache_key"] = .string(k) }
        case .openRouter:
            // Keeps the session on the provider that holds its cache (60 minutes without a request).
            if let k = request.cacheKey { body["session_id"] = .string(String(k.prefix(256))) }
        case .none: break
        }
        // Explicit caching with no breakpoints: nothing written, so no write premium for a prompt nobody reads again.
        if routing != .none, request.oneOff, billsCacheWrites(request.model) { body["prompt_cache_options"] = ["mode": "explicit"] }
        if let e = request.reasoningEffort { body["reasoning_effort"] = .string(e) }
        if let r = request.reasoning { body["reasoning"] = r }
        if let p = request.provider, !p.isEmpty {
            var o: [String: JSONValue] = [:]
            if !p.order.isEmpty { o["order"] = .array(p.order.map(JSONValue.string)) }
            if !p.ignore.isEmpty { o["ignore"] = .array(p.ignore.map(JSONValue.string)) }
            if !p.allowFallbacks { o["allow_fallbacks"] = false }
            if let d = p.dataCollection { o["data_collection"] = .string(d) }
            if p.requireParameters == true { o["require_parameters"] = true }
            body["provider"] = .object(o)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                ["type": "function",
                 "function": ["name": .string(tool.name), "description": .string(tool.description),
                              "parameters": tool.parameters]]
            })
            if let t = request.forcedTool, request.tools.contains(where: { $0.name == t }) {
                body["tool_choice"] = ["type": "function", "function": ["name": .string(t)]]
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(body))
    }

    /// Marks the system prompt and the last user or tool message as cache breakpoints (Claude through OpenRouter): the
    /// prefix up to each is cached, so the next request reads the whole history from the cache. The text moves into a
    /// content part, which is where OpenRouter takes `cache_control`.
    static func withCacheBreakpoints(_ messages: [JSONValue], hour: Bool) -> [JSONValue] {
        let control: JSONValue = hour ? ["type": "ephemeral", "ttl": "1h"] : ["type": "ephemeral"]
        func marked(_ m: JSONValue) -> JSONValue {
            guard case .object(var o) = m else { return m }
            switch o["content"] {
            case .string(let text)? where !text.isEmpty:
                o["content"] = [["type": "text", "text": .string(text), "cache_control": control]]
            case .array(var parts)?:
                guard let i = parts.lastIndex(where: { if case .object(let p) = $0 { p["type"] == "text" } else { false } }),
                      case .object(var p) = parts[i] else { return m }
                p["cache_control"] = control
                parts[i] = .object(p)
                o["content"] = .array(parts)
            default:
                return m
            }
            return .object(o)
        }
        // The system prompt's breakpoint goes before its changing last section, when it has one, so other runs
        // can read the stable part (`SystemPromptBuilder.splitVolatile`).
        func markedSystem(_ m: JSONValue) -> JSONValue {
            guard case .object(var o) = m, case .string(let text)? = o["content"] else { return marked(m) }
            let (stable, volatile) = SystemPromptBuilder.splitVolatile(text)
            guard !volatile.isEmpty else { return marked(m) }
            o["content"] = [["type": "text", "text": .string(stable), "cache_control": control],
                            ["type": "text", "text": .string(String(volatile.drop { $0 == "\n" }))]]
            return .object(o)
        }
        var out = messages
        if let i = out.firstIndex(where: { if case .object(let o) = $0 { o["role"] == "system" } else { false } }) { out[i] = markedSystem(out[i]) }
        if let i = out.lastIndex(where: { if case .object(let o) = $0 { o["role"] == "user" || o["role"] == "tool" } else { false } }) {
            out[i] = marked(out[i])
        }
        return out
    }

    static func encodeMessage(_ m: ChatMessage, reasoning: Bool = false, images: Bool = false) -> JSONValue {
        var o: [String: JSONValue] = ["role": .string(m.role.rawValue)]
        // An assistant message that only calls tools sends null content, as OpenAI does.
        o["content"] = (m.role == .assistant && m.content.isEmpty && !m.toolCalls.isEmpty) ? .null : .string(m.content)
        if m.role == .user, let attached = m.images, !attached.isEmpty {
            if images {
                // OpenAI content parts: the text, then each image as a data URL.
                var parts: [JSONValue] = m.content.isEmpty ? [] : [["type": "text", "text": .string(m.content)]]
                for image in attached {
                    guard let url = image.dataURL else {
                        parts.append(["type": "text", "text": "[an attached image is no longer available]"])
                        continue
                    }
                    parts.append(["type": "image_url", "image_url": ["url": .string(url)]])
                }
                o["content"] = .array(parts)
            } else {
                let note = "[\(attached.count) image\(attached.count == 1 ? " was" : "s were") attached here; this model can't see images]"
                o["content"] = .string(m.content.isEmpty ? note : m.content + "\n\n" + note)
            }
        }
        if !m.toolCalls.isEmpty {
            o["tool_calls"] = .array(m.toolCalls.map { c in
                ["id": .string(c.id), "type": "function",
                 "function": ["name": .string(c.name), "arguments": .string(NativeWire.sendableArguments(c.arguments))]]
            })
        }
        if let id = m.toolCallID { o["tool_call_id"] = .string(id) }
        if reasoning, m.role == .assistant, let r = m.reasoning, !r.isEmpty { o["reasoning"] = .string(r) }
        return .object(o)
    }

    // MARK: - Streamed chunks

    struct Chunk: Decodable {
        let id: String?
        let model: String?
        let provider: String?    // OpenRouter
        let choices: [Choice]?
        let usage: WireUsage?
    }

    struct Choice: Decodable {
        let delta: Delta?
        let finish_reason: String?
    }

    struct Delta: Decodable {
        let content: String?
        let reasoning_content: String?   // LM Studio
        let reasoning: String?           // some other servers (e.g. OpenRouter)
        let tool_calls: [ToolCallDelta]?
    }

    struct ToolCallDelta: Decodable {
        let index: Int?
        let id: String?
        let function: FunctionDelta?
    }

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    struct WireUsage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let completion_tokens_details: Details?
        let prompt_tokens_details: PromptDetails?
        let cost: Double?   // OpenRouter
        struct Details: Decodable { let reasoning_tokens: Int? }
        /// OpenAI and OpenRouter: `cached_tokens` read from the cache; OpenRouter also `cache_write_tokens`.
        struct PromptDetails: Decodable { let cached_tokens: Int?; let cache_write_tokens: Int? }
    }

    /// Decodes one `data:` payload into zero or more events, in delta order.
    static func events(fromChunk data: Data) throws -> [StreamEvent] {
        let chunk = try JSONDecoder().decode(Chunk.self, from: data)
        var out: [StreamEvent] = []
        if let id = chunk.id, !id.isEmpty { out.append(.requestID(id)) }      // OpenRouter's generation id
        if let model = chunk.model { out.append(.model(model)) }
        if let provider = chunk.provider, !provider.isEmpty { out.append(.provider(provider)) }
        for choice in chunk.choices ?? [] {
            if let d = choice.delta {
                if let r = d.reasoning_content ?? d.reasoning, !r.isEmpty { out.append(.reasoning(r)) }
                if let c = d.content, !c.isEmpty { out.append(.content(c)) }
                for (i, tc) in (d.tool_calls ?? []).enumerated() {
                    out.append(.toolCallDelta(index: tc.index ?? i, id: tc.id,
                                              name: tc.function?.name, arguments: tc.function?.arguments))
                }
            }
            if let f = choice.finish_reason {
                if f == "content_filter" { out.append(.note("The server's content filter stopped the reply.")); out.append(.declined) }
                out.append(.finish(FinishReason(wire: f)))
            }
        }
        if let u = chunk.usage {
            if case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data), let raw = o["usage"] { out.append(.usageRaw(raw)) }
            out.append(.usage(Usage(promptTokens: u.prompt_tokens ?? 0,
                                    completionTokens: u.completion_tokens ?? 0,
                                    reasoningTokens: u.completion_tokens_details?.reasoning_tokens ?? 0,
                                    cost: u.cost,
                                    cacheReadTokens: u.prompt_tokens_details?.cached_tokens,
                                    cacheWriteTokens: u.prompt_tokens_details?.cache_write_tokens)))
        }
        return out
    }

    /// Extracts a human-readable message from an error body. LM Studio sends `{"error": "text"}`;
    /// OpenAI-style servers send `{"error": {"message": "text", ...}}`.
    static func errorMessage(fromBody data: Data) -> String? {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let o) = v else {
            let text = String(decoding: data.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        switch o["error"] {
        case .string(let s): return s
        case .object(let e):
            if case .string(let s) = e["message"] { return s }
        default: break
        }
        if case .string(let s) = o["message"] { return s }
        return nil
    }
}

/// The lines of a byte stream, split on `\n` only (a trailing `\r` is dropped) and decoded as UTF-8; blank lines are
/// kept. `AsyncLineSequence` is not used because it also splits on U+0085, U+2028 and U+2029, which JSON may carry raw
/// inside a string (LM Studio and llama.cpp don't escape them), and that cut a `data:` line in two.
struct ByteLines<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String
    let base: Base

    struct AsyncIterator: AsyncIteratorProtocol {
        var bytes: Base.AsyncIterator
        var line: [UInt8] = []
        var ended = false

        mutating func next() async throws -> String? {
            guard !ended else { return nil }
            while let b = try await bytes.next() {
                if b == 0x0A { return take() }
                line.append(b)
            }
            ended = true
            return line.isEmpty ? nil : take()
        }

        private mutating func take() -> String {
            if line.last == 0x0D { line.removeLast() }
            defer { line.removeAll(keepingCapacity: true) }
            return String(decoding: line, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(bytes: base.makeAsyncIterator()) }
}

/// Splits a server-sent-events stream into `data:` payloads.
///
/// `ChatClient` treats each `data:` line that holds complete JSON as a whole event (many servers, and the tests, put no
/// blank line between events) and joins one that doesn't with the `data:` lines after it, as SSE allows.
struct SSELineParser {
    enum Line: Equatable {
        case data(String)
        case done
        case ignore
        /// Not an SSE line at all: part of a body that is not a stream (a proxy's JSON error).
        case other
    }

    static func parse(_ line: Substring) -> Line {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else {
            // Comments, event:, id:, retry:
            let isField = trimmed.isEmpty || trimmed.hasPrefix(":") || ["event:", "id:", "retry:"].contains { trimmed.hasPrefix($0) }
            return isField ? .ignore : .other
        }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        return payload.isEmpty ? .ignore : .data(payload)
    }
}

// MARK: - Per-API stream decoding

/// Turns one API's streamed `data:` payloads into events. Stateful: Anthropic's events refer to earlier blocks, and the
/// native content is assembled across the whole stream.
protocol StreamDecoder {
    /// Events for one payload.
    mutating func decode(_ payload: Data) throws -> [StreamEvent]
    /// Events once the stream has ended normally (the native content).
    mutating func end() -> [StreamEvent]
    /// True once the server said why the reply finished: a stream that ends before that was cut.
    var finished: Bool { get }
}

struct OpenAIStreamDecoder: StreamDecoder {
    var finished = false

    mutating func decode(_ payload: Data) throws -> [StreamEvent] {
        // An error inside the stream (OpenRouter: an `error` object with finish_reason "error"; LM Studio: `{"error": "…"}`)
        // fails the turn with the server's words, as Anthropic's `error` event does; it isn't a finished reply.
        if payload.range(of: Data(#""error""#.utf8)) != nil,
           case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: payload) {
            var message: String?
            switch o["error"] {
            case .string(let s)?: message = s
            case .object(let e)?: message = e["message"]?.stringValue ?? "the server reported an error"
            default: break
            }
            if message == nil, case .array(let choices)? = o["choices"],
               choices.contains(where: { if case .object(let c) = $0 { c["finish_reason"] == .string("error") } else { false } }) {
                message = "the server ended the reply with an error"
            }
            if let message { throw ChatError.server(message) }
        }
        let events = try WireFormat.events(fromChunk: payload)
        if events.contains(where: { if case .finish = $0 { true } else { false } }) { finished = true }
        return events
    }

    mutating func end() -> [StreamEvent] { [] }
}

/// Helpers the native formats share.
enum NativeWire {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// A tool call's argument text as a JSON object for APIs that take objects. Text that isn't an object is kept
    /// under a key, so the model still sees what it wrote.
    static func argumentsObject(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .object([:]) }
        if let v = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)), case .object = v { return v }
        return ["invalid_arguments": .string(text)]
    }

    /// A tool call's argument text for APIs that take it as a string. Valid arguments go unchanged. Text cut off by a
    /// cancelled or length-limited turn would make some servers (LM Studio) fail the whole request with a 500 while
    /// parsing the history, so it is sent as `argumentsObject` does, keeping what the model wrote.
    static func sendableArguments(_ text: String) -> String {
        if let v = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object = v { return text }
        return Self.text(argumentsObject(text))
    }

    /// A JSON value as compact text with sorted keys (a tool call's `arguments`).
    static func text(_ v: JSONValue) -> String {
        (try? encoder().encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// The same arguments, however they were spelled.
    static func sameArguments(_ a: String, _ b: JSONValue) -> Bool {
        argumentsObject(a) == b
    }

    /// An attached image's media type and base64 data; nil when its file is gone.
    static func imageData(_ image: ImageAttachment) -> (mediaType: String, base64: String)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: image.path)) else { return nil }
        return (image.mediaType, data.base64EncodedString())
    }

    static func imageNote(_ count: Int) -> String {
        "[\(count) image\(count == 1 ? " was" : "s were") attached here; this model can't see images]"
    }

    static let missingImage = "[an attached image is no longer available]"

    /// Whether a native API request for `model` carries this reply's thinking (its blocks go back as they were).
    static func carriesReasoning(_ m: ChatMessage, api: WireAPI, model: String) -> Bool {
        guard m.native?.api == api else { return false }
        switch api {
        case .openai:
            return false
        case .anthropic:
            return AnthropicWire.assistantBlocks(m, model: model).contains {
                let t = AnthropicWire.type($0)
                return t == "thinking" || t == "redacted_thinking"
            }
        case .gemini:
            return GeminiWire.modelParts(m, model: model).contains {
                if case .object(let p) = $0 { return p["thought"] == .bool(true) }
                return false
            }
        }
    }

    static func int(_ v: JSONValue?) -> Int? {
        if case .number(let n)? = v { return Int(json: n) }
        return nil
    }

    static func string(_ v: JSONValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }
}
