import Foundation

// Anthropic's Messages API (`POST /v1/messages`): request encoding and streamed-event decoding.
//
// Spoken natively rather than through Anthropic's OpenAI-compatible endpoint so the reasoning comes back (summarized
// thinking) and thinking blocks round-trip: each reply's content blocks are kept on the message (`NativeContent`) and
// sent back unchanged while the message still matches them and the same model is asked.

enum AnthropicWire {
    static let version = "2023-06-01"
    /// Lets a request say what happens to a thinking block whose history changed since it was written. kurtkode
    /// rewrites history (compaction, trimmed tool outputs), so blocks it invalidates are dropped instead of failing
    /// the request with a 400.
    static let bindingBeta = "thinking-binding-controls-2026-08-01"
    /// Server-side fallback: when a model declines, the API re-runs the request on another model in the same call.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// How a model takes its thinking settings, by family.
    enum Generation: Equatable {
        /// Claude 3.x, 4.0, 4.1, 4.5: thinking only with a token budget; sampling settings allowed.
        case budget
        /// Claude 4.6: adaptive thinking (which may be turned off); sampling settings allowed.
        case adaptive46
        /// Claude 4.7 and later: adaptive thinking, effort levels, no sampling settings, thinking blocks bound to
        /// their conversation.
        case current
    }

    static func generation(_ model: String) -> Generation {
        let m = model.lowercased()
        if m.contains("claude-3") || m.contains("-4-5") || m.contains("-4-1") || m.contains("-4-0")
            || m.range(of: #"claude-(opus|sonnet)-4-\d{8}"#, options: .regularExpression) != nil { return .budget }
        if m.contains("-4-6") { return .adaptive46 }
        return .current
    }

    /// The web search tool's version: the newer one (with dynamic filtering) on the models that take it.
    static func webSearchTool(_ model: String) -> String {
        let m = model.lowercased()
        let newer = ["opus-5", "opus-4-8", "opus-4-7", "opus-4-6", "sonnet-5", "sonnet-4-6"].contains { m.contains($0) }
        return newer ? "web_search_20260209" : "web_search_20250305"
    }

    /// Models that take `fallbacks: "default"` (a declined request continues on another model).
    static func takesFallbacks(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("fable-5-1") || m.contains("opus-5") || m.contains("sonnet-5-5")
    }

    // MARK: - Requests

    /// The system prompt as sent: one string, or, when it ends in the section that changes between runs
    /// (`SystemPromptBuilder.volatileHeading`), two blocks with a cache breakpoint after the first, so the next run's
    /// first request reads the tools and the stable prompt from the cache (only positions an earlier request marked
    /// can be read; the automatic breakpoint alone sits after the run's own first message).
    static func systemBlocks(_ text: String, control: JSONValue) -> JSONValue {
        let (stable, volatile) = SystemPromptBuilder.splitVolatile(text)
        guard !volatile.isEmpty else { return .string(text) }
        return .array([["type": "text", "text": .string(stable), "cache_control": control],
                       ["type": "text", "text": .string(String(volatile.drop { $0 == "\n" }))]])
    }

    /// A one-off request's system prompt is cached when it is at least this long (about 1,500 tokens, above every
    /// current model's minimum but Haiku 4.5's and Opus 4.5–4.6's 4,096).
    static let oneOffSystemCacheBytes = 6_000

    static func encodeRequest(_ r: ChatRequest) throws -> Data {
        var system: [String] = []
        var rest = r.messages[...]
        while let first = rest.first, first.role == .system {
            if !first.content.isEmpty { system.append(first.content) }
            rest = rest.dropFirst()
        }
        let control: JSONValue = r.cacheForAnHour ? ["type": "ephemeral", "ttl": "1h"] : ["type": "ephemeral"]
        var body: [String: JSONValue] = [
            "model": .string(r.model),
            "stream": true,
            "max_tokens": .number(Double(r.maxTokens)),
            "messages": .array(encodeMessages(Array(rest), model: r.model, images: r.sendImages)),
        ]
        // Caches the longest prefix the request shares with the last one: the system prompt, tools, and history. A
        // one-off request doesn't write its own tail (a write costs 1.25× or 2× the input price; nothing reads it
        // again); a long fixed system prompt (a grader's, a reviewer's) is still cached for the next such request.
        if !r.oneOff { body["cache_control"] = control }
        if !system.isEmpty {
            let text = system.joined(separator: "\n\n")
            if !r.oneOff { body["system"] = systemBlocks(text, control: control) }
            else if text.utf8.count >= oneOffSystemCacheBytes { body["system"] = .array([["type": "text", "text": .string(text), "cache_control": control]]) }
            else { body["system"] = .string(text) }
        }
        var tools: [JSONValue] = r.tools.map { t in
            ["name": .string(t.name), "description": .string(t.description), "input_schema": t.parameters]
        }
        // The server's own web search: it runs the searches and returns them with the reply (billed per search).
        if r.webSearch { tools.append(["type": .string(webSearchTool(r.model)), "name": "web_search", "max_uses": 5]) }
        if !tools.isEmpty { body["tools"] = .array(tools) }
        let effort = r.reasoningEffort?.lowercased()
        switch generation(r.model) {
        case .budget:
            let budgets = ["minimal": 1024, "low": 2048, "medium": 8192, "high": 16000, "xhigh": 24000, "max": 32000]
            if let e = effort, let wanted = budgets[e], case let b = min(wanted, r.maxTokens - 1024), b >= 1024 {
                body["thinking"] = ["type": "enabled", "budget_tokens": .number(Double(b))]
            } else if let t = r.temperature {
                body["temperature"] = .number(t)
            }
        case .adaptive46:
            if effort == "none" {
                body["thinking"] = ["type": "disabled"]
                if let t = r.temperature { body["temperature"] = .number(t) }
            } else {
                body["thinking"] = ["type": "adaptive"]
                let levels = ["minimal": "low", "low": "low", "medium": "medium", "high": "high", "xhigh": "high", "max": "max"]
                if let e = effort, let level = levels[e] { body["output_config"] = ["effort": .string(level)] }
            }
        case .current:
            // Thinking can't be turned off on the newest models; "none" asks for as little as there is.
            body["thinking"] = ["type": "adaptive", "display": "summarized",
                                "block_binding": ["prefix_mismatch_behavior": "drop_block"]]
            let levels = ["none": "low", "minimal": "low", "low": "low", "medium": "medium", "high": "high",
                          "xhigh": "xhigh", "max": "max"]
            if let e = effort, let level = levels[e] { body["output_config"] = ["effort": .string(level)] }
            if takesFallbacks(r.model) { body["fallbacks"] = "default" }
        }
        if let t = r.forcedTool, r.tools.contains(where: { $0.name == t }), canForceTool(model: r.model, effort: r.reasoningEffort) {
            body["tool_choice"] = ["type": "tool", "name": .string(t)]
        }
        return try NativeWire.encoder().encode(JSONValue.object(body))
    }

    /// Whether a request may force a tool: only without thinking (Claude refuses a forced choice with it on), which the
    /// newest models can't turn off.
    static func canForceTool(model: String, effort: String?) -> Bool {
        let e = effort?.lowercased()
        switch generation(model) {
        case .budget: return e.map { !["minimal", "low", "medium", "high", "xhigh", "max"].contains($0) } ?? true
        case .adaptive46: return e == "none"
        case .current: return false
        }
    }

    /// The `anthropic-beta` header a request body needs (nil for none).
    static func betas(forBody body: Data) -> String? {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: body) else { return nil }
        var betas: [String] = []
        if case .object(let t)? = o["thinking"], t["block_binding"] != nil { betas.append(bindingBeta) }
        if o["fallbacks"] != nil { betas.append(fallbackBeta) }
        return betas.isEmpty ? nil : betas.joined(separator: ",")
    }

    /// Messages as content blocks: tool results become `tool_result` blocks in a user message, consecutive messages of
    /// one role merge (all of a reply's results must arrive in one message), and the list starts and ends with a user
    /// message (the newest models take no prefilled reply).
    static func encodeMessages(_ messages: [ChatMessage], model: String, images: Bool) -> [JSONValue] {
        var turns: [(role: String, blocks: [JSONValue])] = []
        func add(_ role: String, _ blocks: [JSONValue]) {
            guard !blocks.isEmpty else { return }
            if turns.last?.role == role { turns[turns.count - 1].blocks += blocks } else { turns.append((role, blocks)) }
        }
        for m in messages {
            switch m.role {
            case .system:
                add("user", [text("[System] " + m.content)])
            case .user:
                var blocks: [JSONValue] = []
                var note = ""
                if let attached = m.images, !attached.isEmpty {
                    if images {
                        for image in attached {
                            if let (type, data) = NativeWire.imageData(image) {
                                blocks.append(["type": "image",
                                               "source": ["type": "base64", "media_type": .string(type), "data": .string(data)]])
                            } else {
                                blocks.append(text(NativeWire.missingImage))
                            }
                        }
                    } else {
                        note = NativeWire.imageNote(attached.count)
                    }
                }
                let words = [m.content, note].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
                if !words.isEmpty { blocks.append(text(words)) }
                add("user", blocks)
            case .tool:
                add("user", [["type": "tool_result", "tool_use_id": .string(toolID(m.toolCallID ?? "")),
                              "content": .string(m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no output)" : m.content)]])
            case .assistant:
                add("assistant", assistantBlocks(m, model: model))
            }
        }
        if turns.first?.role == "assistant" { turns.insert(("user", [text("(The conversation continues.)")]), at: 0) }
        // A paused reply (pause_turn) goes back as the last message, so the server continues it.
        if turns.last?.role == "assistant", messages.last?.meta?.paused != true { turns.append(("user", [text("Continue.")])) }
        return turns.map { ["role": .string($0.role), "content": .array($0.blocks)] }
    }

    /// A reply's blocks: as returned, while they still match the message (the loop can rename or recover tool calls),
    /// with their thinking only for the model that wrote it; otherwise rebuilt from the text and tool calls.
    static func assistantBlocks(_ m: ChatMessage, model: String) -> [JSONValue] {
        if let n = m.native, n.api == .anthropic, case .array(let blocks) = n.blocks, matches(blocks, m) {
            let sameModel = n.model == model
            return blocks.filter { b in
                let t = type(b)
                return t != "fallback" && (sameModel || (t != "thinking" && t != "redacted_thinking"))
            }
        }
        var out: [JSONValue] = []
        // Claude rejects a text block that is only whitespace (a local model's "\n" before its calls).
        if !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(text(m.content)) }
        for c in m.toolCalls {
            out.append(["type": "tool_use", "id": .string(toolID(c.id)), "name": .string(c.name),
                        "input": NativeWire.argumentsObject(c.arguments)])
        }
        return out
    }

    static func matches(_ blocks: [JSONValue], _ m: ChatMessage) -> Bool {
        var text = ""
        var uses: [[String: JSONValue]] = []
        for case .object(let b) in blocks {
            switch NativeWire.string(b["type"]) {
            case "text": text += NativeWire.string(b["text"]) ?? ""
            case "tool_use": uses.append(b)
            default: break
            }
        }
        guard text == m.content, uses.count == m.toolCalls.count else { return false }
        return zip(uses, m.toolCalls).allSatisfy { u, c in
            NativeWire.string(u["id"]) == c.id && NativeWire.string(u["name"]) == c.name
                && NativeWire.sameArguments(c.arguments, u["input"] ?? .object([:]))
        }
    }

    /// Tool-use ids must be letters, digits, `_` and `-`; ids from other servers are mapped the same way every time.
    static func toolID(_ id: String) -> String {
        let mapped = String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
        return mapped.isEmpty ? "call" : mapped
    }

    static func text(_ s: String) -> JSONValue { ["type": "text", "text": .string(s)] }

    static func type(_ block: JSONValue) -> String? {
        if case .object(let o) = block { return NativeWire.string(o["type"]) }
        return nil
    }
}

/// Folds Anthropic's stream (`message_start`, `content_block_*`, `message_delta`, `message_stop`) into events, and
/// assembles the reply's content blocks.
struct AnthropicStreamDecoder: StreamDecoder {
    let requestedModel: String
    var finished = false
    /// Who wrote the thinking: the model asked for, or the one a server-side fallback handed the reply to.
    private var author: String?
    private var blocks: [Int: [String: JSONValue]] = [:]
    private var order: [Int] = []
    private var partialJSON: [Int: String] = [:]
    /// Blocks of the server's own tools (web search): their input streams too, but they aren't calls for kurtkode to run.
    private var serverTools = Set<Int>()
    private var webSearches = 0
    private var thoughtBlocks = 0            // thinking blocks that had text, to separate them in the reasoning
    private var promptTokens = 0
    private var outputTokens = 0
    private var thinkingTokens = 0
    private var cacheRead = 0
    private var cacheWrite = 0
    private var cacheWriteHour = 0

    /// Reads usage figures (`message_start` has them all; `message_delta` repeats some, cumulative).
    private mutating func readUsage(_ u: [String: JSONValue]) {
        if let n = NativeWire.int(u["output_tokens"]) { outputTokens = n }
        if case .object(let s)? = u["server_tool_use"], let n = NativeWire.int(s["web_search_requests"]) { webSearches = n }
        if case .object(let d)? = u["output_tokens_details"], let n = NativeWire.int(d["thinking_tokens"]) { thinkingTokens = n }
        if let n = NativeWire.int(u["cache_read_input_tokens"]) { cacheRead = n }
        if let n = NativeWire.int(u["cache_creation_input_tokens"]) { cacheWrite = n }
        if case .object(let c)? = u["cache_creation"], let n = NativeWire.int(c["ephemeral_1h_input_tokens"]) { cacheWriteHour = n }
        let prompt = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].compactMap { NativeWire.int(u[$0]) }
        if !prompt.isEmpty { promptTokens = max(promptTokens, prompt.reduce(0, +)) }
    }

    /// The usage objects as sent, by the event they came in.
    private var rawUsage: [String: JSONValue] = [:]

    init(requestedModel: String) { self.requestedModel = requestedModel }

    /// The usage so far, priced.
    private func currentUsage() -> Usage {
        var usage = Usage(promptTokens: promptTokens, completionTokens: outputTokens, reasoningTokens: thinkingTokens,
                          cacheReadTokens: cacheRead,
                          cacheWriteTokens: cacheWrite, cacheWriteHourTokens: cacheWriteHour > 0 ? cacheWriteHour : nil)
        if webSearches > 0 { usage.webSearches = webSearches }
        if let c = PriceList.cost(usage, api: .anthropic, model: author ?? requestedModel) {
            usage.cost = c
            usage.costIsEstimate = true
        }
        return usage
    }

    mutating func decode(_ payload: Data) throws -> [StreamEvent] {
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: payload) else { return [] }
        var out: [StreamEvent] = []
        switch NativeWire.string(o["type"]) {
        case "message_start":
            guard case .object(let msg)? = o["message"] else { break }
            if let m = NativeWire.string(msg["model"]) { out.append(.model(m)) }
            if let id = NativeWire.string(msg["id"]) { out.append(.requestID(id)) }
            if case .object(let u)? = msg["usage"] {
                readUsage(u)
                rawUsage["message_start"] = .object(u)
                out.append(.usageRaw(.object(rawUsage)))
                // The input is billed even if the reply is cut off: count it now (the final usage replaces this).
                out.append(.usage(currentUsage()))
            }
            if case .array(let changes)? = msg["input_transformations"] {
                var reasons: [String: Int] = [:]
                for case .object(let c) in changes where NativeWire.string(c["type"]) == "thinking_dropped" {
                    reasons[NativeWire.string(c["reason"]) ?? "unknown", default: 0] += 1
                }
                for (reason, n) in reasons.sorted(by: { $0.key < $1.key }) {
                    out.append(.note("The server dropped \(n) earlier thinking block\(n == 1 ? "" : "s") (\(reason)): "
                                     + (reason == "model_binding_mismatch" ? "another model wrote them."
                                        : "the history before \(n == 1 ? "it" : "them") changed (a compaction or a trimmed output).")))
                }
            }
        case "content_block_start":
            guard let i = NativeWire.int(o["index"]), case .object(var block)? = o["content_block"] else { break }
            switch NativeWire.string(block["type"]) {
            case "tool_use":
                partialJSON[i] = ""
                out.append(.toolCallDelta(index: i, id: NativeWire.string(block["id"]), name: NativeWire.string(block["name"]),
                                          arguments: nil))
            case "server_tool_use":
                partialJSON[i] = ""
                serverTools.insert(i)
            case "text":
                if let t = NativeWire.string(block["text"]), !t.isEmpty { out.append(.content(t)) }
            case "thinking":
                if let t = NativeWire.string(block["thinking"]), !t.isEmpty { out += reasoning(t, startsBlock: true) }
            case "fallback":
                // The model before this block declined; what it wrote besides text isn't part of the reply.
                func name(_ v: JSONValue?) -> String {
                    if case .object(let m)? = v, let s = NativeWire.string(m["model"]) { return s }
                    return "a model"
                }
                out.append(.note("\(name(block["from"])) declined; \(name(block["to"])) continued (server-side fallback)."))
                out.append(.discardToolCalls)
                for k in order {
                    let t = blocks[k].flatMap { NativeWire.string($0["type"]) }
                    if t == "thinking" || t == "redacted_thinking" || t == "tool_use" { blocks[k] = nil }
                }
                order.removeAll { blocks[$0] == nil }
                partialJSON = [:]
                if case .object(let to)? = block["to"], let m = NativeWire.string(to["model"]) { author = m }
            default:
                break
            }
            if ["tool_use", "server_tool_use"].contains(NativeWire.string(block["type"])) { block["input"] = .object([:]) }
            blocks[i] = block
            if !order.contains(i) { order.append(i) }
        case "content_block_delta":
            guard let i = NativeWire.int(o["index"]), case .object(let d)? = o["delta"], blocks[i] != nil else { break }
            switch NativeWire.string(d["type"]) {
            case "text_delta":
                let t = NativeWire.string(d["text"]) ?? ""
                let before = NativeWire.string(blocks[i]?["text"]) ?? ""
                blocks[i]?["text"] = .string(before + t)
                if !t.isEmpty { out.append(.content(t)) }
            case "thinking_delta":
                let t = NativeWire.string(d["thinking"]) ?? ""
                let before = NativeWire.string(blocks[i]?["thinking"]) ?? ""
                blocks[i]?["thinking"] = .string(before + t)
                if !t.isEmpty { out += reasoning(t, startsBlock: before.isEmpty) }
            case "signature_delta":
                let s = NativeWire.string(d["signature"]) ?? ""
                let before = NativeWire.string(blocks[i]?["signature"]) ?? ""
                blocks[i]?["signature"] = .string(before + s)
            case "input_json_delta":
                let p = NativeWire.string(d["partial_json"]) ?? ""
                partialJSON[i, default: ""] += p
                if !p.isEmpty, !serverTools.contains(i) { out.append(.toolCallDelta(index: i, id: nil, name: nil, arguments: p)) }
            case "citations_delta":
                // Kept with the text they support (sent back as returned; the Steps tab lists the sources).
                if let c = d["citation"] {
                    var list = blocks[i]?["citations"]?.arrayValue ?? []
                    list.append(c)
                    blocks[i]?["citations"] = .array(list)
                }
            default:
                break
            }
        case "content_block_stop":
            guard let i = NativeWire.int(o["index"]), let json = partialJSON[i] else { break }
            blocks[i]?["input"] = NativeWire.argumentsObject(json)
        case "message_delta":
            if case .object(let u)? = o["usage"] {
                readUsage(u)
                rawUsage["message_delta"] = .object(u)
                out.append(.usageRaw(.object(rawUsage)))
            }
            guard case .object(let d)? = o["delta"], let reason = NativeWire.string(d["stop_reason"]) else { break }
            finished = true
            switch reason {
            case "end_turn", "stop_sequence": out.append(.finish(.stop))
            case "tool_use": out.append(.finish(.toolCalls))
            case "max_tokens": out.append(.finish(.length))
            case "pause_turn":
                // A long server-side step (web search) paused the turn; the loop sends it back to continue.
                out.append(.paused)
                out.append(.finish(.other))
            case "model_context_window_exceeded":
                out.append(.note("The reply stopped at the model's context window."))
                out.append(.finish(.length))
            case "refusal":
                var why = "The model declined to answer"
                if case .object(let s)? = d["stop_details"] {
                    if let c = NativeWire.string(s["category"]) { why += " (\(c))" }
                    if let e = NativeWire.string(s["explanation"]), !e.isEmpty { why += ": \(e)" }
                }
                out.append(.note(why.hasSuffix(".") ? why : why + "."))
                out.append(.declined)
                out.append(.finish(.other))
            default:
                out.append(.note("The server stopped the reply: \(reason)."))
                out.append(.finish(.other))
            }
            out.append(.usage(currentUsage()))
        case "error":
            var message = "The server reported an error mid-reply."
            if case .object(let e)? = o["error"] {
                message = [NativeWire.string(e["type"]), NativeWire.string(e["message"])].compactMap { $0 }.joined(separator: ": ")
            }
            throw ChatError.server(message)
        default:
            break   // ping, message_stop, and types added later
        }
        return out
    }

    private mutating func reasoning(_ t: String, startsBlock: Bool) -> [StreamEvent] {
        guard startsBlock else { return [.reasoning(t)] }
        thoughtBlocks += 1
        return [.reasoning(thoughtBlocks > 1 ? "\n\n" + t : t)]
    }

    mutating func end() -> [StreamEvent] {
        let list = order.compactMap { blocks[$0].map(JSONValue.object) }
        guard !list.isEmpty else { return [] }
        return [.native(NativeContent(api: .anthropic, model: author ?? requestedModel, blocks: .array(list)))]
    }
}
