import Foundation

/// Everything kurtkode treats differently per model, as data. No model-specific code paths: a new model
/// gets defaults (from what its server reports, plus the family table below) and the user can override
/// any field.
public struct ModelProfile: Codable, Sendable, Hashable {
    public var endpointID: UUID
    public var model: String

    /// Context to load with and to budget against. Nil: what the server reports, else 32k.
    public var contextLength: Int?
    /// Per-reply output cap. Nil: the app setting.
    public var maxOutputTokens: Int?
    /// Nil: the server's default.
    public var temperature: Double?
    /// Nil: detect (LM Studio reports it; other servers are assumed to support tools).
    public var supportsTools: Bool?
    /// Nil: detect (LM Studio reports vision; other servers are assumed to take images).
    public var supportsImages: Bool?
    /// Text appended to the system prompt for this model only.
    public var promptAddendum: String

    /// How history is reshaped for this model's chat template.
    public var history: HistoryShape
    /// Which providers may serve this model, on endpoints that route between several (OpenRouter).
    public var providers: ProviderRouting?
    /// Peak memory the model was seen to use while generating (MLX takes memory at inference, not load).
    public var measuredPeakMemoryBytes: Int64?
    /// Offer `apply_patch` beside edit_file. Nil: the family table's choice (GPT, Codex and gpt-oss models are trained
    /// on that patch format).
    public var patchTool: Bool?
    /// How much the model reasons: "none" (off) or an effort level its API takes (`Replay.effortLevels`: low, medium,
    /// high, …). Nil: the model's default. Sent each turn in its API's form (`ReasoningSetting`).
    public var reasoning: String?

    /// Whether runs on this model get `apply_patch`.
    public var offersPatchTool: Bool { patchTool ?? ModelFamily.patchToolByDefault(model) }

    public init(endpointID: UUID, model: String, contextLength: Int? = nil, maxOutputTokens: Int? = nil,
                temperature: Double? = nil, supportsTools: Bool? = nil, promptAddendum: String = "",
                history: HistoryShape = HistoryShape(), measuredPeakMemoryBytes: Int64? = nil) {
        self.endpointID = endpointID
        self.model = model
        self.contextLength = contextLength
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.supportsTools = supportsTools
        self.promptAddendum = promptAddendum
        self.history = history
        self.measuredPeakMemoryBytes = measuredPeakMemoryBytes
    }

    public var key: String { Self.key(endpointID, model) }
    public static func key(_ endpointID: UUID, _ model: String) -> String { "\(endpointID.uuidString)|\(model)" }

    /// Starting profile for a model nobody has configured: the family table applied to its id.
    public static func defaults(endpointID: UUID, model: String) -> ModelProfile {
        var p = ModelProfile(endpointID: endpointID, model: model)
        let id = model.lowercased()
        for family in ModelFamily.known where family.matches.contains(where: { id.contains($0) }) {
            p.history = family.history
            if let t = family.temperature { p.temperature = t }
        }
        return p
    }
}

/// OpenRouter's provider preferences for a request: providers to try first, providers never to use, and whether
/// it may go beyond the ordered ones. Provider names as OpenRouter lists them ("DeepInfra", "Novita").
public struct ProviderRouting: Codable, Sendable, Hashable {
    public var order: [String]
    public var ignore: [String]
    public var allowFallbacks: Bool
    /// "deny": only providers that don't keep or train on prompts (OpenRouter's `data_collection`); nil: any.
    public var dataCollection: String?
    /// Only providers that support every parameter sent (tools among them), OpenRouter's `require_parameters`.
    public var requireParameters: Bool?

    public init(order: [String] = [], ignore: [String] = [], allowFallbacks: Bool = true, dataCollection: String? = nil,
                requireParameters: Bool? = nil) {
        self.order = order
        self.ignore = ignore
        self.allowFallbacks = allowFallbacks
        self.dataCollection = dataCollection
        self.requireParameters = requireParameters
    }

    public var isEmpty: Bool { order.isEmpty && ignore.isEmpty && allowFallbacks && dataCollection == nil && requireParameters != true }

    /// These preferences, also avoiding `providers` (ones that just failed). Ordered providers that are now
    /// ignored are dropped from the order, and fallbacks are allowed again so the request can go anywhere else.
    public func avoiding(_ providers: Set<String>) -> ProviderRouting {
        guard !providers.isEmpty else { return self }
        let lowered = Set(providers.map { $0.lowercased() })
        let ignore = self.ignore + providers.sorted().filter { p in !self.ignore.contains { $0.lowercased() == p.lowercased() } }
        let order = self.order.filter { !lowered.contains($0.lowercased()) }
        return ProviderRouting(order: order, ignore: ignore, allowFallbacks: allowFallbacks || order.isEmpty,
                               dataCollection: dataCollection, requireParameters: requireParameters)
    }
}

/// How messages are adjusted so a model's chat template accepts them.
public struct HistoryShape: Codable, Sendable, Hashable {
    public enum ToolCallIDs: String, Codable, Sendable, CaseIterable {
        /// Send ids as recorded.
        case asIs
        /// Exactly 9 characters of [A-Za-z0-9]; Mistral-family templates reject anything else.
        case alphanumeric9
    }

    public var toolCallIDs: ToolCallIDs
    /// Strict user/assistant alternation (Gemma's and Mistral's templates reject anything else): merge
    /// consecutive same-role messages, and bridge a tool result followed by a user message.
    public var mergeConsecutive: Bool
    /// Recover tool calls the model wrote as text instead of structured calls (`[TOOL_CALLS]name {json}`,
    /// `<tool_call>{json}</tool_call>`). Seen with Devstral on LM Studio.
    public var parseTextToolCalls: Bool
    /// Send each assistant turn's reasoning back with it (as `reasoning`). Models trained to see their own
    /// chain of thought across tool calls (gpt-oss) otherwise lose the thread; others don't need it.
    public var sendReasoning: Bool

    public init(toolCallIDs: ToolCallIDs = .asIs, mergeConsecutive: Bool = false, parseTextToolCalls: Bool = false,
                sendReasoning: Bool = false) {
        self.toolCallIDs = toolCallIDs
        self.mergeConsecutive = mergeConsecutive
        self.parseTextToolCalls = parseTextToolCalls
        self.sendReasoning = sendReasoning
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolCallIDs = try c.decodeIfPresent(ToolCallIDs.self, forKey: .toolCallIDs) ?? .asIs
        mergeConsecutive = try c.decodeIfPresent(Bool.self, forKey: .mergeConsecutive) ?? false
        parseTextToolCalls = try c.decodeIfPresent(Bool.self, forKey: .parseTextToolCalls) ?? false
        sendReasoning = try c.decodeIfPresent(Bool.self, forKey: .sendReasoning) ?? false
    }
}

/// Known quirks by model family, matched on the model id. Data, not code paths: add a row for a new family.
public struct ModelFamily: Sendable {
    public var name: String
    public var matches: [String]
    public var history: HistoryShape
    public var temperature: Double?
    /// Trained on Codex's patch format: offered `apply_patch`.
    public var patchTool = false

    public static func patchToolByDefault(_ model: String) -> Bool {
        let id = model.lowercased()
        return known.contains { f in f.patchTool && f.matches.contains { id.contains($0) } }
    }

    public static let known: [ModelFamily] = [
        ModelFamily(name: "Mistral", matches: ["mistral", "devstral", "magistral", "codestral", "ministral"],
                    history: HistoryShape(toolCallIDs: .alphanumeric9, mergeConsecutive: true, parseTextToolCalls: true),
                    temperature: nil),
        ModelFamily(name: "Gemma", matches: ["gemma"], history: HistoryShape(mergeConsecutive: true), temperature: nil),
        // Qwen3-Coder's XML tool calls sometimes arrive as text (seen from an OpenRouter provider).
        ModelFamily(name: "Qwen", matches: ["qwen"], history: HistoryShape(parseTextToolCalls: true), temperature: nil),
        // Before gpt-oss, whose row (it matches "gpt-" too) must win: later rows override earlier ones.
        ModelFamily(name: "GPT", matches: ["gpt-", "codex", "openai/o"], history: HistoryShape(), temperature: nil, patchTool: true),
        // Harmony-format models: without their earlier reasoning they wrote a call into the reasoning and
        // returned nothing (OpenRouter).
        ModelFamily(name: "gpt-oss", matches: ["gpt-oss"], history: HistoryShape(sendReasoning: true), temperature: nil,
                    patchTool: true),
    ]
}

/// Profiles saved as JSON, one file for all models.
public struct ProfileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> [String: ModelProfile] { loadChecked().value }

    /// The saved profiles and what's wrong with the file, if anything (as `EndpointStore.loadChecked`).
    public func loadChecked() -> ConfigLoad<[String: ModelProfile]> {
        let file = ConfigListFile<ModelProfile>(fileURL: fileURL)
        let c = file.read()
        return ConfigLoad(value: Dictionary(c.items.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b }),
                          problem: file.problem(c, backup: c.unreadable ? file.backUp() : nil), unreadable: c.unreadable)
    }

    public func save(_ profiles: [String: ModelProfile], replacingUnreadable: Bool = false) throws {
        try ConfigListFile<ModelProfile>(fileURL: fileURL).write(profiles.values.sorted { $0.key < $1.key },
                                                                 replacingUnreadable: replacingUnreadable)
    }

    /// Saves one profile into the file as it is now, so profiles another process saved meanwhile aren't lost; returns
    /// what the file then holds.
    @discardableResult
    public func save(_ profile: ModelProfile) throws -> [String: ModelProfile] {
        var all = load()
        all[profile.key] = profile
        try save(all)
        return all
    }
}

/// Reshapes history for a model's template. Deterministic, so the same history always produces the same
/// prompt (the server's prompt cache depends on it).
public enum HistoryShaper {
    public static func shape(_ messages: [ChatMessage], for shape: HistoryShape) -> [ChatMessage] {
        var out = messages
        if shape.toolCallIDs == .alphanumeric9 {
            out = out.map { m in
                var m = m
                m.toolCalls = m.toolCalls.map { ToolCall(id: alphanumeric9($0.id), name: $0.name, arguments: $0.arguments) }
                m.toolCallID = m.toolCallID.map(alphanumeric9)
                return m
            }
        }
        if shape.mergeConsecutive { out = merge(out) }
        return out
    }

    static func bridgeID(after id: UUID) -> UUID {
        var bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        bytes[15] ^= 0xB5
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
                           bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// A stable 9-character [A-Za-z0-9] id for any id (FNV-1a, base 62). Ids already in that form are kept.
    public static func alphanumeric9(_ id: String) -> String {
        if id.count == 9, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return id }
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var s = ""
        for _ in 0..<9 { s.append(alphabet[Int(h % 62)]); h /= 62; if h == 0 { h = 0x9E37_79B9_7F4A_7C15 } }
        return s
    }

    /// The assistant turn inserted between a tool result and a user message for strict templates.
    public static let bridge = "(Noted.)"

    /// Consecutive user messages become one; so do consecutive plain assistant messages. A user message
    /// right after tool results gets a short assistant turn before it. Deterministic, and only ever adds
    /// after what's there, so a prompt that grows by appending keeps its cached prefix.
    static func merge(_ messages: [ChatMessage]) -> [ChatMessage] {
        var out: [ChatMessage] = []
        for m in messages {
            if m.role == .user, out.last?.role == .tool {
                let tool = out.last!
                out.append(ChatMessage(id: bridgeID(after: tool.id), role: .assistant, content: bridge, createdAt: tool.createdAt))
            }
            if var last = out.last, last.role == m.role,
               (m.role == .user || (m.role == .assistant && last.toolCalls.isEmpty && m.toolCalls.isEmpty)) {
                last.content = [last.content, m.content].filter { !$0.isEmpty }.joined(separator: "\n\n")
                if let images = m.images, !images.isEmpty { last.images = (last.images ?? []) + images }
                out[out.count - 1] = last
            } else if m.role == .system, let first = out.first, first.role == .system {
                out[0].content += "\n\n" + m.content
            } else {
                out.append(m)
            }
        }
        return out
    }
}

/// A reasoning setting ("none" for off, or an effort level) in the form each API takes it: OpenRouter's `reasoning`
/// object (`enabled: false`, or `effort`), `reasoning_effort` on other OpenAI-compatible servers ("none" turns
/// thinking off on LM Studio's Gemma and OpenAI's newer models), and Claude's and Gemini's thinking settings, which
/// their wires derive from `reasoningEffort`.
public enum ReasoningSetting {
    public static func apply(_ setting: String?, to request: inout ChatRequest, client: ChatClient) {
        guard let level = setting?.trimmingCharacters(in: .whitespaces).lowercased(), !level.isEmpty else { return }
        let off = ["none", "off"].contains(level)
        if client.api == .openai, client.baseURL.host()?.hasSuffix("openrouter.ai") == true {
            request.reasoning = off ? ["enabled": false] : ["effort": .string(level)]
        } else {
            request.reasoningEffort = off ? "none" : level
        }
    }

    /// The setting's name in menus and listings.
    public static func label(_ setting: String?) -> String {
        switch setting?.lowercased() {
        case nil, "": "default"
        case "none", "off": "off"
        case let level?: level
        }
    }
}
