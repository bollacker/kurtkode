import Foundation

/// The wire format a server speaks.
public enum WireAPI: String, Codable, Sendable {
    /// OpenAI Chat Completions (LM Studio, OpenRouter, most servers).
    case openai
    /// Anthropic's Messages API.
    case anthropic
    /// Google's Gemini API (`generateContent`).
    case gemini
}

/// An assistant reply's content exactly as a native API returned it (Anthropic content blocks, Gemini parts), kept so
/// it can be sent back unchanged: thinking blocks and thought signatures are only valid verbatim.
public struct NativeContent: Codable, Sendable, Hashable {
    public var api: WireAPI
    /// The model that wrote it; another model can't read its thinking.
    public var model: String
    /// Anthropic: the `content` array. Gemini: the `parts` array.
    public var blocks: JSONValue

    public init(api: WireAPI, model: String, blocks: JSONValue) {
        self.api = api
        self.model = model
        self.blocks = blocks
    }
}

/// A model a server lists, with what it says about it.
public struct ListedModel: Sendable, Hashable {
    public var id: String
    public var displayName: String?
    public var contextLength: Int?
    /// What the server says about the model, where it says it (OpenRouter's `/models`, Ollama's `/api/show`); nil: it
    /// doesn't say.
    public var maxOutputTokens: Int?
    public var supportsTools: Bool?
    public var supportsReasoning: Bool?
    public var supportsImages: Bool?
    /// List price, from servers that publish it with the list (OpenRouter).
    public var price: PriceList.Price?

    public init(id: String, displayName: String? = nil, contextLength: Int? = nil, maxOutputTokens: Int? = nil,
                supportsTools: Bool? = nil, supportsReasoning: Bool? = nil, supportsImages: Bool? = nil,
                price: PriceList.Price? = nil) {
        self.id = id
        self.displayName = displayName
        self.contextLength = contextLength
        self.maxOutputTokens = maxOutputTokens
        self.supportsTools = supportsTools
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
        self.price = price
    }

    /// One entry of an OpenAI-compatible `/models` list. OpenRouter: `context_length`,
    /// `top_provider.max_completion_tokens`, `supported_parameters` (`tools`, `reasoning`),
    /// `architecture.input_modalities`, `pricing`; Together: `context_length`; vLLM: `max_model_len`. Fields a server
    /// leaves out stay nil.
    public static func openAI(_ m: [String: JSONValue]) -> ListedModel? {
        guard let id = NativeWire.string(m["id"]) else { return nil }
        var out = ListedModel(id: id, displayName: NativeWire.string(m["name"]))
        out.contextLength = positive(m["context_length"]) ?? positive(m["max_model_len"])
        if case .object(let top)? = m["top_provider"] {
            out.maxOutputTokens = positive(top["max_completion_tokens"])
            if out.contextLength == nil { out.contextLength = positive(top["context_length"]) }
        }
        if case .array(let params)? = m["supported_parameters"] {
            let names = Set(params.compactMap(NativeWire.string))
            out.supportsTools = names.contains("tools")
            out.supportsReasoning = names.contains("reasoning") || names.contains("include_reasoning")
        }
        if case .object(let arch)? = m["architecture"], case .array(let inputs)? = arch["input_modalities"] {
            out.supportsImages = inputs.compactMap(NativeWire.string).contains("image")
        }
        out.price = RemotePrices.price(m)
        return out
    }

    /// Ollama's `POST /api/show` answer: the context it serves with (`num_ctx` in `parameters`, as the Modelfile set it),
    /// and `capabilities` (`completion`, `tools`, `vision`, `thinking`). `model_info`'s `context_length` is what the
    /// model was trained for, not what the server gives a request (Ollama's own default is a few thousand tokens), so
    /// without `num_ctx` the context stays unknown.
    public mutating func absorbOllama(_ show: [String: JSONValue]) {
        if let params = NativeWire.string(show["parameters"]) {
            for line in params.split(separator: "\n") {
                let words = line.split(whereSeparator: \.isWhitespace)
                if words.count >= 2, words[0] == "num_ctx", let n = Int(words[1]), n > 0 { contextLength = n }
            }
        }
        if case .array(let caps)? = show["capabilities"] {
            let names = Set(caps.compactMap(NativeWire.string))
            supportsTools = names.contains("tools")
            supportsImages = names.contains("vision")
            supportsReasoning = names.contains("thinking")
        }
    }

    static func positive(_ v: JSONValue?) -> Int? {
        switch v {
        case .number(let n)? where n > 0 && n < 1e12: Int(n)
        case .string(let s)?: Int(s).flatMap { $0 > 0 ? $0 : nil }
        default: nil
        }
    }
}

public enum Role: String, Codable, Sendable {
    case system, user, assistant, tool
}

/// A tool call as the model produced it. `arguments` is the raw JSON text, kept verbatim so it can be
/// sent back to the server unchanged and shown to the user even when it doesn't parse.
public struct ToolCall: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct Usage: Codable, Sendable, Hashable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    /// What the request cost, in USD: as the server reports it (OpenRouter), or estimated at list price
    /// (`costIsEstimate`; Anthropic and Gemini, from `PriceList`).
    public var cost: Double?
    public var costIsEstimate: Bool?
    /// Prompt tokens served from the server's prompt cache (part of `promptTokens`); nil when the server doesn't say.
    public var cacheReadTokens: Int?
    /// Prompt tokens written to the cache by this request (part of `promptTokens`; Anthropic bills them at a premium).
    public var cacheWriteTokens: Int?
    /// Of the written ones, those kept for an hour (Anthropic's longer cache, billed higher than five minutes).
    public var cacheWriteHourTokens: Int?
    /// Web searches the server ran for the reply (billed per search).
    public var webSearches: Int?

    public init(promptTokens: Int, completionTokens: Int, reasoningTokens: Int = 0, cost: Double? = nil,
                costIsEstimate: Bool? = nil, cacheReadTokens: Int? = nil, cacheWriteTokens: Int? = nil, cacheWriteHourTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
        self.costIsEstimate = costIsEstimate
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheWriteHourTokens = cacheWriteHourTokens
    }

    public var totalTokens: Int { promptTokens + completionTokens }

    /// "$0.0123", or "≈$0.0123 (list price)" for an estimate; nil without a cost.
    public func costText(digits: Int = 4) -> String? {
        guard let cost else { return nil }
        let amount = String(format: "$%.\(digits)f", cost)
        return costIsEstimate == true ? "≈" + amount + " (list price)" : amount
    }

    /// The share of the prompt read from the cache, when the server says.
    /// Cache reads and writes in words ("2400 read from the cache · 120 written, for an hour"), or nil.
    public var cacheDetail: String? {
        guard cacheReadTokens != nil || cacheWriteTokens != nil else { return nil }
        var s = "\(cacheReadTokens ?? 0) read from the cache · \(cacheWriteTokens ?? 0) written"
        if let h = cacheWriteHourTokens, h > 0 { s += h == cacheWriteTokens ? ", for an hour" : " (\(h) for an hour)" }
        return s
    }

    public var cachedShare: Double? {
        guard let r = cacheReadTokens, promptTokens > 0 else { return nil }
        return Double(r) / Double(promptTokens)
    }

    /// "87% cached, 1200 written": the cache's part in the prompt, or nil when the server says nothing about it.
    public var cacheSummary: String? {
        guard cacheReadTokens != nil || cacheWriteTokens != nil else { return nil }
        var parts = ["\(Int(((cachedShare ?? 0) * 100).rounded()))% cached"]
        if let w = cacheWriteTokens, w > 0 { parts.append("\(w) written") }
        return parts.joined(separator: ", ")
    }
}

/// Why the server ended a completion.
public enum FinishReason: String, Codable, Sendable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case other

    init(wire: String) {
        self = FinishReason(rawValue: wire) ?? .other
    }
}

/// Why kurtkode ended a turn. Distinct from `FinishReason`: the server may never finish at all.
public enum StopReason: String, Codable, Sendable {
    case completed          // server sent a finish reason (see TurnMeta.finishReason)
    case cancelled          // user pressed Stop
    case timedOut           // exceeded the per-turn wall-clock limit
    case repetition         // repetition detector fired
    case failed             // transport or server error
}

/// Bookkeeping attached to an assistant message.
public struct TurnMeta: Codable, Sendable, Hashable {
    public var requestedModel: String
    public var reportedModel: String?       // what the server says answered; LM Studio can substitute
    /// The provider that served the reply, when the endpoint routes between several (OpenRouter).
    public var provider: String?
    /// What the agent loop did with or about this reply (recovered calls, a renamed tool, a nudge, a retry).
    public var notes: [String]?
    /// The reply's text as it arrived, when the loop changed it (tool calls recovered from it).
    public var rawContent: String?
    /// Requests made for this turn that produced no message (a retry the server refused): their wire records.
    public var retryRequests: [UUID]?
    /// Which endpoint served the turn; a session can use several.
    public var endpointID: UUID?
    public var usage: Usage?
    public var finishReason: FinishReason?
    public var stopReason: StopReason
    /// The server or the model declined (a Claude refusal, a Gemini safety stop or blocked prompt, OpenAI's
    /// `content_filter`). Such a reply isn't lost and isn't nudged: asking again gets the same answer.
    public var declined: Bool?
    /// The server paused the turn mid-step (Claude's `pause_turn`, a long web search); the loop sends it back.
    public var paused: Bool?
    /// The loop took this reply back and asked again instead of sending it on (an empty reply, a broken call, a reply
    /// stopped for repeating itself). It's stored and shown, but `sendable` leaves it out, as the run did.
    public var unsent: Bool?
    /// The server's ids for the request (`StreamEvent.requestID`).
    public var requestIDs: [String]?
    /// The usage as the server sent it, for checking the parsed `usage` and the cost made from it.
    public var usageRaw: JSONValue?
    public var error: String?
    public var timeToFirstToken: Double?    // seconds, first content or reasoning token
    public var duration: Double             // seconds

    public init(requestedModel: String, reportedModel: String? = nil, usage: Usage? = nil,
                finishReason: FinishReason? = nil, stopReason: StopReason, error: String? = nil,
                timeToFirstToken: Double? = nil, duration: Double) {
        self.requestedModel = requestedModel
        self.reportedModel = reportedModel
        self.usage = usage
        self.finishReason = finishReason
        self.stopReason = stopReason
        self.error = error
        self.timeToFirstToken = timeToFirstToken
        self.duration = duration
    }

    /// True when the server answered with a different model than requested.
    public var modelMismatch: Bool {
        guard let reportedModel else { return false }
        return reportedModel != requestedModel
    }
}

/// A command the user ran with `!`.
public struct UserCommandInfo: Codable, Sendable, Hashable {
    public var command: String
    public var output: String
    public var exitCode: Int32?

    public init(command: String, output: String, exitCode: Int32?) {
        self.command = command
        self.output = output
        self.exitCode = exitCode
    }
}

public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: Role
    public var content: String
    /// Reasoning ("thinking") text. Stored and shown; sent back only when the history shape says so (native APIs send
    /// their own blocks instead, see `native`).
    public var reasoning: String?
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public var createdAt: Date
    public var meta: TurnMeta?
    /// On tool-result messages: how the tool went, for the UI.
    public var toolResult: ToolResultInfo?
    /// On a user message from `!command`: what ran and its output, for the UI (the model gets `content`).
    public var userCommand: UserCommandInfo?
    /// Images attached to a user message.
    public var images: [ImageAttachment]?
    /// On a user message that delivers a background subagent's report (not the user's words): that run.
    public var subagentReport: UUID?
    /// On a user message kurtkode wrote: the environment now, for a resumed session (`FrozenSystemPrompt`).
    public var contextNote: Bool?
    /// On an assistant message from a native API (Anthropic, Gemini): its content as returned, sent back as it is
    /// while the message still matches it (`content`, `toolCalls`) and the same model is asked.
    public var native: NativeContent?

    public init(id: UUID = UUID(), role: Role, content: String, reasoning: String? = nil,
                toolCalls: [ToolCall] = [], toolCallID: String? = nil, createdAt: Date = Date(),
                meta: TurnMeta? = nil, toolResult: ToolResultInfo? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.createdAt = createdAt
        self.meta = meta
        self.toolResult = toolResult
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: text) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
}

/// A function tool offered to the model, in OpenAI's `tools` shape.
public struct ToolDefinition: Sendable, Hashable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ChatRequest: Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var tools: [ToolDefinition]
    /// Always set: local models can generate without end (spike: 78 minutes in one turn).
    public var maxTokens: Int
    public var temperature: Double?
    /// Send assistant turns' reasoning back (HistoryShape.sendReasoning). Off, reasoning never leaves the app.
    public var sendReasoning: Bool
    /// Send attached images. Off (a model without vision), each is replaced by a short note.
    public var sendImages: Bool
    /// Which providers may serve it (OpenRouter's `provider` object); nil sends none.
    public var provider: ProviderRouting?
    /// Offer the server's own web search (Claude's web search tool, Gemini's Google Search grounding). Other servers
    /// ignore it.
    public var webSearch = false
    /// Keep the prompt cache for an hour instead of five minutes (Anthropic's `cache_control.ttl`; writes cost 2×
    /// the input price instead of 1.25×). Other servers ignore it.
    public var cacheForAnHour = false
    /// OpenRouter's `reasoning` object as sent (`{"enabled": false}` turns thinking off); nil: not sent.
    public var reasoning: JSONValue?
    /// A tool the reply must call (A7: `task` at the delegation threshold); nil: the model's choice. Sent as OpenAI's named
    /// `tool_choice`, Gemini's `ANY` with that name allowed, Claude's `tool` choice (only without thinking, which Claude
    /// refuses to combine with it). Only where `ToolForcing.supported` says the server honors it.
    public var forcedTool: String?
    /// OpenAI's `reasoning_effort`; nil sends none (the model's default). "none" turns Gemma 4's thinking off on
    /// LM Studio (713 reasoning tokens, 15.5 s → 0, 1.0 s), but with tools offered it also loses the prompt cache.
    public var reasoningEffort: String?
    /// Names the conversation for the server's cache routing (OpenAI's `prompt_cache_key`, OpenRouter's `session_id`):
    /// requests that share it go where the earlier ones left their cache. Nil sends none.
    public var cacheKey: String?
    /// A request nothing will repeat (a title, a commit message, a grade): where writing the cache costs extra (Anthropic;
    /// OpenAI from GPT-5.6, `WireFormat.billsCacheWrites`) it asks for no cache.
    public var oneOff = false

    public init(model: String, messages: [ChatMessage], tools: [ToolDefinition] = [],
                maxTokens: Int, temperature: Double? = nil, sendReasoning: Bool = false, sendImages: Bool = false) {
        self.sendImages = sendImages
        self.model = model
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.sendReasoning = sendReasoning
    }
}

/// One decoded piece of a streamed completion.
public enum StreamEvent: Sendable, Equatable {
    case model(String)
    /// The provider serving the stream (OpenRouter).
    case provider(String)
    case content(String)
    case reasoning(String)
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    case finish(FinishReason)
    case usage(Usage)
    /// Something the server said about the reply that isn't its content (a refusal, a fallback model, dropped thinking).
    case note(String)
    /// Tool calls received so far are void (the model that wrote them declined and another took over).
    case discardToolCalls
    /// The reply was declined (refusal, safety stop, blocked prompt).
    case declined
    /// The server paused the turn (Claude's `pause_turn`): send the reply back to continue it.
    case paused
    /// The server's id for the request or reply (a header or a field), for finding it in the provider's records.
    case requestID(String)
    /// The usage as the server sent it (the latest replaces earlier ones).
    case usageRaw(JSONValue)
    /// The reply's native content, at the end of the stream.
    case native(NativeContent)
}

extension ChatMessage {
    /// Each tool result joined to the reply whose call it answers: reply id → call id → result. A result goes to the
    /// latest reply before it that made that call and has no answer to it yet, so ids that repeat across turns (Gemini
    /// 2.x sends none, and every reply's first call becomes `call_0`) keep each turn's own result.
    public static func resultsByReply(_ messages: [ChatMessage]) -> [UUID: [String: ChatMessage]] {
        var out: [UUID: [String: ChatMessage]] = [:]
        var open: [String: UUID] = [:]                  // call id → the reply waiting for its result
        for m in messages {
            if m.role == .assistant {
                for c in m.toolCalls { open[c.id] = m.id }
            } else if let id = m.toolCallID, let reply = open.removeValue(forKey: id) {
                out[reply, default: [:]][id] = m
            }
        }
        return out
    }
}
