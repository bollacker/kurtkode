import Foundation

/// A named model server. D13: several may be configured; each session remembers its endpoint.
public struct Endpoint: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// LM Studio: adds model metadata (`/api/v0`) and, when local, `lms` server management.
        case lmstudio
        /// Any OpenAI-compatible server: model ids only; context length is entered by hand.
        case openai
        /// Anthropic's Messages API (Claude), spoken natively so thinking blocks round-trip.
        case anthropic
        /// Google's Gemini API (`generateContent`), spoken natively so thought signatures round-trip.
        case gemini

        public var displayName: String {
            switch self {
            case .lmstudio: "LM Studio"
            case .openai: "OpenAI-compatible"
            case .anthropic: "Anthropic"
            case .gemini: "Google Gemini"
            }
        }

        /// The wire format its requests use.
        public var api: WireAPI {
            switch self {
            case .lmstudio, .openai: .openai
            case .anthropic: .anthropic
            case .gemini: .gemini
            }
        }

        /// The environment variables the provider's own tools read the key from, tried after kurtkode's own.
        public var standardKeyVariables: [String] {
            switch self {
            case .anthropic: ["ANTHROPIC_API_KEY"]
            case .gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
            case .lmstudio, .openai: []
            }
        }

        /// Whether the server lists each model's context length (so none is entered by hand).
        public var reportsContextLength: Bool { self != .openai }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// OpenAI base URL including `/v1`, e.g. `http://127.0.0.1:1234/v1`.
    public var baseURL: URL
    /// Whether an API key is stored in the Keychain for this endpoint.
    public var usesAPIKey: Bool
    /// For `.openai` endpoints, which don't report it. Ignored for LM Studio.
    public var manualContextLength: Int?

    // Saved as `kind: "openai"` plus `api` for the native kinds, so an older build reading the file sees an
    // OpenAI-compatible endpoint (its requests fail) instead of failing to read the whole list.
    private enum CodingKeys: String, CodingKey { case id, name, kind, api, baseURL, usesAPIKey, manualContextLength }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let api = try c.decodeIfPresent(String.self, forKey: .api).flatMap(Kind.init(rawValue:))
        let saved = try c.decodeIfPresent(Kind.self, forKey: .kind)
        kind = api ?? saved ?? .openai
        baseURL = try c.decode(URL.self, forKey: .baseURL)
        usesAPIKey = try c.decodeIfPresent(Bool.self, forKey: .usesAPIKey) ?? false
        manualContextLength = try c.decodeIfPresent(Int.self, forKey: .manualContextLength)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        switch kind {
        case .lmstudio, .openai: try c.encode(kind, forKey: .kind)
        case .anthropic, .gemini:
            try c.encode(Kind.openai, forKey: .kind)
            try c.encode(kind.rawValue, forKey: .api)
        }
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(usesAPIKey, forKey: .usesAPIKey)
        try c.encodeIfPresent(manualContextLength, forKey: .manualContextLength)
    }

    public init(id: UUID = UUID(), name: String, kind: Kind, baseURL: URL, usesAPIKey: Bool = false,
                manualContextLength: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.usesAPIKey = usesAPIKey
        self.manualContextLength = manualContextLength
    }

    /// A server given for one run (the command line's --endpoint, the app's KURTKODE_EXTRA_ENDPOINT), never saved.
    /// Its id comes from its name and URL, so the same server has the same id every run: sessions continued with it
    /// don't gain a model record each time, and the app's recent models don't fill with copies of it.
    /// Anthropic's and Google's own servers get their native kind; anything else is OpenAI-compatible.
    public static func launchOnly(name: String, url: URL, manualContextLength: Int? = nil) -> Endpoint {
        let kind = detectedKind(url)
        return Endpoint(id: stableID("launch-only|\(name)|\(url.absoluteString)"), name: name, kind: kind, baseURL: url,
                        usesAPIKey: !kind.standardKeyVariables.isEmpty, manualContextLength: manualContextLength)
    }

    /// The kind a URL implies: Anthropic's and Google's API hosts speak their native formats (Google's OpenAI-compatible
    /// path, `…/openai`, stays OpenAI-compatible).
    public static func detectedKind(_ url: URL) -> Kind {
        switch url.host()?.lowercased() {
        case "api.anthropic.com": .anthropic
        case "generativelanguage.googleapis.com" where !url.path().lowercased().contains("/openai"): .gemini
        default: .openai
        }
    }

    /// A UUID from a string: two FNV-1a hashes with different seeds.
    static func stableID(_ text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h = seed
            for b in text.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
            return h
        }
        let a = fnv(14_695_981_039_346_656_037), b = fnv(0x9E37_79B9_7F4A_7C15)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * i)); bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * i)) }
        bytes[6] = (bytes[6] & 0x0F) | 0x80      // version 8 (custom), RFC 9562 variant
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The most context a session on Anthropic's or Google's API uses unless the model's profile sets its own. They
    /// list up to 1M tokens, and a session grows to its limit before compacting: every request would resend that much.
    public static let nativeContextCap = 200_000

    /// LM Studio on this Mac. 127.0.0.1, not localhost: LM Studio binds IPv4 only.
    public static let localLMStudio = Endpoint(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!,
        name: "This Mac (LM Studio)", kind: .lmstudio,
        baseURL: URL(string: "http://127.0.0.1:1234/v1")!)

    /// True when the server runs on this Mac, so `lms` can manage it.
    public var isLocal: Bool {
        guard let host = baseURL.host() else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }

    /// A hosted model API run by a company (Anthropic, Google, OpenRouter, OpenAI, and other known services): what
    /// automatic routing needs before it sends a session's work to another such service (`SubagentRouting`). Stricter
    /// than `isThirdParty`, which takes any name it can't place as remote: a server on the LAN reached by a bare name
    /// ("studio"), `.lan`, `.home.arpa`, `.internal` or a Tailscale name is third party there, and must not make
    /// kurtkode send a local session's files to the cloud.
    public var isCloudAPI: Bool {
        if kind == .anthropic || kind == .gemini { return true }
        guard let host = baseURL.host()?.lowercased() else { return false }
        return Self.cloudHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Hosted OpenAI-compatible APIs kurtkode recognizes.
    public static let cloudHosts = ["openrouter.ai", "openai.com", "anthropic.com", "googleapis.com", "together.xyz", "together.ai",
                                    "fireworks.ai", "groq.com", "deepseek.com", "mistral.ai", "x.ai", "cerebras.ai", "deepinfra.com",
                                    "perplexity.ai", "cohere.com", "cohere.ai", "featherless.ai", "novita.ai", "hyperbolic.xyz",
                                    "sambanova.ai", "nebius.com", "moonshot.ai", "z.ai", "minimax.io", "inference.net"]

    /// A server outside this Mac and the local network: what the agent reads goes to a third party. Anthropic and Google
    /// always are; LM Studio on the LAN isn't.
    public var isThirdParty: Bool { kind == .anthropic || kind == .gemini || Self.isThirdParty(baseURL) }

    public static func isThirdParty(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        if ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return false }
        let p = host.split(separator: ".").compactMap { Int($0) }
        if p.count == 4 {
            if p[0] == 10 || p[0] == 127 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
                || (p[0] == 169 && p[1] == 254) || (p[0] == 100 && (64...127).contains(p[1])) { return false }   // private, link-local, CGNAT (Tailscale)
        }
        // IPv6 unique-local (fc00::/7) and link-local (fe80::/10) addresses; a name like fdai.example.com is not one.
        if host.contains(":"), host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8") || host.hasPrefix("fe9")
            || host.hasPrefix("fea") || host.hasPrefix("feb") { return false }
        return true
    }

    /// The OpenAI base URL from whatever the user pasted: API docs usually show the full request URL
    /// (`…/v1/chat/completions`), so trailing endpoint paths and slashes are removed.
    public static func normalizedBaseURL(_ url: URL) -> URL {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/chat/completions", "/completions", "/models", "/responses", "/embeddings", "/messages"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
            break
        }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s) ?? url
    }

    /// Server root for LM Studio's native API: the base URL without its trailing `/v1`.
    public var serverRoot: URL {
        baseURL.lastPathComponent == "v1" ? baseURL.deletingLastPathComponent() : baseURL
    }
}

/// Persists the endpoint list as JSON. The local LM Studio endpoint is always present.
public struct EndpointStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [Endpoint] { loadChecked().value }

    /// The saved endpoints and what's wrong with the file, if anything. Entries this build can't read are left out
    /// (and kept in the file by `save`); a file that isn't a JSON list gives only the local endpoint, is copied aside,
    /// and `save` refuses to write over it.
    public func loadChecked() -> ConfigLoad<[Endpoint]> {
        let file = ConfigListFile<Endpoint>(fileURL: fileURL)
        let c = file.read()
        var list = c.items
        if !list.contains(where: { $0.id == Endpoint.localLMStudio.id }) {
            list.insert(.localLMStudio, at: 0)
        }
        for i in list.indices { list[i].baseURL = Endpoint.normalizedBaseURL(list[i].baseURL) }
        return ConfigLoad(value: list, problem: file.problem(c, backup: c.unreadable ? file.backUp() : nil), unreadable: c.unreadable)
    }

    /// Saves the list, keeping the file's entries this build can't read. Throws `ConfigFileUnreadable` when the file
    /// isn't a JSON list, unless `replacingUnreadable` (the file is copied aside first).
    public func save(_ endpoints: [Endpoint], replacingUnreadable: Bool = false) throws {
        try ConfigListFile<Endpoint>(fileURL: fileURL).write(endpoints, replacingUnreadable: replacingUnreadable)
    }

    /// Combines a list edited here (`mine`, last read or saved as `base`) with the file as it is now (`theirs`, which
    /// another process such as `kurtkode endpoint add` may have changed meanwhile), by id: an endpoint added or removed
    /// on either side stays added or removed, and one changed on only one side keeps that change (ours wins when both
    /// changed it). Our order, then theirs for endpoints added elsewhere.
    public static func merge(base: [Endpoint], mine: [Endpoint], theirs: [Endpoint]) -> [Endpoint] {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let theirsByID = Dictionary(theirs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mineIDs = Set(mine.map(\.id))
        var out: [Endpoint] = []
        for e in mine {
            let old = baseByID[e.id]
            if let t = theirsByID[e.id] {
                out.append(old == e ? t : e)
            } else if old == nil || old != e {
                out.append(e)                       // added here, or changed here though removed elsewhere
            }
        }
        for t in theirs where !mineIDs.contains(t.id) && baseByID[t.id] == nil { out.append(t) }
        return out
    }
}

/// A starting point for a new endpoint: a known server's base URL and whether it needs a key.
public struct EndpointPreset: Sendable, Hashable, Identifiable {
    public var name: String
    public var kind: Endpoint.Kind
    public var baseURL: String
    public var needsKey: Bool
    /// Shown in the editor: what to fill in or change.
    public var note: String
    public var id: String { name }

    public static let remote: [EndpointPreset] = [
        EndpointPreset(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com/v1", needsKey: true,
                       note: "Claude models through Anthropic's Messages API; keys at console.anthropic.com."),
        EndpointPreset(name: "Google Gemini", kind: .gemini, baseURL: "https://generativelanguage.googleapis.com/v1beta",
                       needsKey: true, note: "Gemini models through Google's Gemini API; keys at aistudio.google.com. On the free "
                           + "tier Google may use prompts and replies to improve its products: use a paid key for code you keep private."),
        EndpointPreset(name: "OpenRouter", kind: .openai, baseURL: "https://openrouter.ai/api/v1", needsKey: true,
                       note: "Hundreds of models from many providers; prices at openrouter.ai/models."),
        EndpointPreset(name: "OpenAI", kind: .openai, baseURL: "https://api.openai.com/v1", needsKey: true, note: ""),
        EndpointPreset(name: "Together", kind: .openai, baseURL: "https://api.together.xyz/v1", needsKey: true, note: ""),
        EndpointPreset(name: "Groq", kind: .openai, baseURL: "https://api.groq.com/openai/v1", needsKey: true, note: ""),
        EndpointPreset(name: "Fireworks", kind: .openai, baseURL: "https://api.fireworks.ai/inference/v1", needsKey: true, note: ""),
    ]

    public static let local: [EndpointPreset] = [
        EndpointPreset(name: "Ollama", kind: .openai, baseURL: "http://127.0.0.1:11434/v1", needsKey: false,
                       note: "Ollama's OpenAI-compatible API. Set the context length: Ollama doesn't report it."),
        EndpointPreset(name: "llama.cpp server", kind: .openai, baseURL: "http://127.0.0.1:8080/v1", needsKey: false,
                       note: "llama-server; use the context length you started it with."),
        EndpointPreset(name: "vLLM", kind: .openai, baseURL: "http://127.0.0.1:8000/v1", needsKey: false, note: ""),
        EndpointPreset(name: "LM Studio on another Mac", kind: .lmstudio, baseURL: "http://192.168.1.10:1234/v1", needsKey: false,
                       note: "Replace the address with the other Mac's. It must serve on the local network (LM Studio's server settings)."),
    ]

    public func makeEndpoint() -> Endpoint {
        Endpoint(name: name, kind: kind, baseURL: URL(string: baseURL)!)
    }
}
