import Foundation

/// Sees one request on the wire: the exact body sent, every HTTP status (retries included), the raw stream lines,
/// and an error body. `ChatClient.stream` fills it; the agent loop saves it as a `WireRecord`.
public final class WireTap: @unchecked Sendable {
    private let lock = NSLock()
    private var _url: String?
    private var _body: Data?
    private var _statuses: [Int] = []
    private var _lines: [String] = []
    private var _lineBytes = 0
    private var _errorBody: String?
    private var _truncated = false
    /// The raw stream is kept up to this many bytes (a runaway reply can be very long).
    static let maxLineBytes = 4_000_000

    public init() {}

    func request(url: URL, body: Data) { lock.withLock { _url = url.absoluteString; _body = body } }
    func status(_ code: Int) { lock.withLock { _statuses.append(code) } }
    func line(_ s: String) {
        lock.withLock {
            guard _lineBytes < Self.maxLineBytes else { _truncated = true; return }
            _lines.append(s)
            _lineBytes += s.utf8.count
        }
    }
    func errorBody(_ s: String) { lock.withLock { _errorBody = s } }

    /// What was seen, as a record for the reply `replyID`.
    public func record(replyID: UUID, startedAt: Date, duration: Double) -> WireRecord {
        lock.withLock {
            WireRecord(replyID: replyID, startedAt: startedAt, duration: duration, url: _url ?? "",
                       request: _body.map(WireRecord.compactRequest) ?? .null, statuses: _statuses,
                       lines: _lines, linesTruncated: _truncated ? true : nil, errorBody: _errorBody)
        }
    }
}

/// One model request and its raw response, saved next to the session (`<id>.wire/<reply id>.json`).
public struct WireRecord: Codable, Sendable, Hashable {
    /// The assistant message this request produced (its id in the session).
    public var replyID: UUID
    public var startedAt: Date
    public var duration: Double
    /// The endpoint's URL. Headers aren't kept: the API key is in one.
    public var url: String
    /// The request body as sent, except image data (replaced by a note of its size).
    public var request: JSONValue
    /// Every HTTP status received, in order (a 429 before a 200 was retried).
    public var statuses: [Int]
    /// The stream's lines as received (`data: {…}`), blank lines excepted.
    public var lines: [String]
    public var linesTruncated: Bool?
    public var errorBody: String?

    /// The request with images' data URLs replaced, so a session with screenshots doesn't store each one per turn.
    static func compactRequest(_ body: Data) -> JSONValue {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            return .string(String(decoding: body.prefix(200_000), as: UTF8.self))
        }
        func strip(_ v: JSONValue) -> JSONValue {
            switch v {
            case .string(let s) where s.hasPrefix("data:image/"):
                return .string("[image, \(s.utf8.count / 1024) KB as a data URL]")
            case .array(let a): return .array(a.map(strip))
            case .object(var o):
                // Anthropic's `source` ({media_type, data}) and Gemini's `inlineData` ({mimeType, data}).
                if case .string(let data)? = o["data"], case .string(let type)? = o["media_type"] ?? o["mimeType"],
                   type.hasPrefix("image/") {
                    o["data"] = .string("[image, \(data.utf8.count / 1024) KB as base64]")
                    return .object(o)
                }
                return .object(o.mapValues(strip))
            default: return v
            }
        }
        return strip(v)
    }

    /// The wire format the request went out in, from its URL.
    public var api: WireAPI {
        let path = URL(string: url)?.path() ?? url
        if path.contains(":streamGenerateContent") || path.contains(":generateContent") { return .gemini }
        if path.hasSuffix("/messages") { return .anthropic }
        return .openai
    }

    /// The request's messages (role and content), for showing and comparing; the native APIs' system prompt (a field
    /// of its own there) comes first as a `system` message, as in OpenAI's format.
    public var messages: [JSONValue] {
        guard case .object(let o) = request else { return [] }
        switch api {
        case .openai:
            if case .array(let m)? = o["messages"] { return m }
        case .anthropic:
            let system: [JSONValue] = o["system"].map { [["role": "system", "content": $0]] } ?? []
            if case .array(let m)? = o["messages"] { return system + m }
            return system
        case .gemini:
            var system: [JSONValue] = []
            if case .object(let s)? = o["systemInstruction"], case .array(let parts)? = s["parts"] {
                let text = parts.compactMap { p -> String? in
                    if case .object(let po) = p, case .string(let t)? = po["text"] { return t }
                    return nil
                }.joined(separator: "\n\n")
                system = [["role": "system", "content": .string(text)]]
            }
            if case .array(let c)? = o["contents"] { return system + c }
            return system
        }
        return []
    }

    /// The `data:` payloads of the stream, decoded where they parse.
    public var payloads: [JSONValue] {
        lines.compactMap { line in
            guard case .data(let p) = SSELineParser.parse(line[...]) else { return nil }
            return (try? JSONDecoder().decode(JSONValue.self, from: Data(p.utf8))) ?? .string(p)
        }
    }
}

/// One message in a request's context: which session message it was (nil for the system prompt), its role, its size
/// as sent, and whether its reasoning went with it. `kind` marks what isn't a session message.
public struct ContextRef: Codable, Sendable, Hashable {
    public var id: UUID?
    public var role: String
    /// "system", "system+summary" (the prompt carried a compaction summary), "nudge", "continuation"; nil for a message.
    public var kind: String?
    public var bytes: Int
    public var reasoning: Bool?

    public init(id: UUID?, role: String, kind: String? = nil, bytes: Int, reasoning: Bool? = nil) {
        self.id = id
        self.role = role
        self.kind = kind
        self.bytes = bytes
        self.reasoning = reasoning
    }
}

/// What one request carried, in order. Kept in `index.jsonl` beside the wire records: small, so a journal can read
/// every turn's context without reading every request.
public struct ContextSnapshot: Codable, Sendable, Hashable {
    public var replyID: UUID
    public var startedAt: Date
    public var refs: [ContextRef]

    public init(replyID: UUID, startedAt: Date, refs: [ContextRef]) {
        self.replyID = replyID
        self.startedAt = startedAt
        self.refs = refs
    }
}

/// A session's wire records, in a folder next to its file, up to a size cap (past it, new records are dropped).
public actor WireLog {
    public nonisolated let directory: URL
    public nonisolated let maxBytes: Int
    private var used: Int?

    public init(directory: URL, maxBytes: Int = 100_000_000) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public func write(_ record: WireRecord) {
        let fm = FileManager.default
        if used == nil {
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            used = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(record), (used ?? 0) + data.count <= maxBytes else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if (try? data.write(to: Self.url(directory, record.replyID), options: .atomic)) != nil { used = (used ?? 0) + data.count }
    }

    static func url(_ directory: URL, _ replyID: UUID) -> URL { directory.appending(path: "\(replyID.uuidString).json") }

    /// Appends a request's context to the index (kept even past the size cap: it's a few hundred bytes).
    public func writeContext(_ snapshot: ContextSnapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard var line = try? enc.encode(snapshot) else { return }
        line.append(0x0A)
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = directory.appending(path: "index.jsonl")
        if !fm.fileExists(atPath: index.path) { fm.createFile(atPath: index.path, contents: nil) }
        _ = try? JSONLines.append(line, to: index)
    }

    /// Every request's context, in the order sent.
    public nonisolated static func contexts(_ directory: URL) -> [ContextSnapshot] {
        guard let data = try? Data(contentsOf: directory.appending(path: "index.jsonl")) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? dec.decode(ContextSnapshot.self, from: Data($0)) }
    }

    /// The record for a reply, if one was saved.
    public nonisolated static func read(_ directory: URL, replyID: UUID) -> WireRecord? {
        guard let data = try? Data(contentsOf: url(directory, replyID)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WireRecord.self, from: data)
    }
}

/// How a tool call came to run (or not): who decided, and how long it waited for the user.
public struct ApprovalRecord: Codable, Sendable, Hashable {
    public enum Decider: String, Codable, Sendable {
        /// Allowed without asking: a read, or the permission mode.
        case mode
        /// An "always allow" rule.
        case rule
        /// A PreToolUse hook (allow, deny, or ask).
        case hook
        /// The user, on an approval card (or at the CLI prompt).
        case user
        /// Refused before asking: plan mode, no one to ask, or the preview showed it would fail.
        case refused
    }
    public var decider: Decider
    public var allowed: Bool
    /// Seconds the call waited for the user's answer.
    public var waited: Double?
    /// The rule that allowed it, or the user's feedback with a denial, or why it was refused.
    public var detail: String?

    public init(decider: Decider, allowed: Bool, waited: Double? = nil, detail: String? = nil) {
        self.decider = decider
        self.allowed = allowed
        self.waited = waited
        self.detail = detail
    }

    public var summary: String {
        let verb = allowed ? "allowed" : "denied"
        switch decider {
        case .mode: return "allowed without asking (read, or the permission mode)"
        case .rule: return "allowed by a rule" + (detail.map { ": \($0)" } ?? "")
        case .hook: return "\(verb) by a PreToolUse hook" + (detail.map { ": \($0)" } ?? "")
        case .user: return "\(verb) by the user" + (waited.map { String(format: " after %.1f s", $0) } ?? "")
            + (detail.map { " (\($0))" } ?? "")
        case .refused: return "refused before asking" + (detail.map { ": \($0)" } ?? "")
        }
    }
}

/// Checks a tool call's arguments against the tool's JSON schema: what a model got wrong, not just what failed.
/// Covers what tool schemas here use: an object with properties, required, and simple types.
public enum ArgumentCheck {
    public static func problems(_ arguments: String, schema: JSONValue) -> [String] {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data((trimmed.isEmpty ? "{}" : trimmed).utf8)) else {
            return ["the arguments aren't valid JSON: \(arguments.prefix(120))"]
        }
        guard case .object(let args) = value else { return ["the arguments are \(kind(value)), not an object"] }
        guard case .object(let s) = schema else { return [] }
        var out: [String] = []
        let properties: [String: JSONValue] = { if case .object(let p)? = s["properties"] { return p } else { return [:] } }()
        if case .array(let required)? = s["required"] {
            for case .string(let name) in required where args[name] == nil || args[name] == .null {
                out.append("missing required \"\(name)\"")
            }
        }
        if args.isEmpty, !properties.isEmpty, !out.isEmpty { out.append("no arguments at all (a provider may have dropped them)") }
        for (name, v) in args.sorted(by: { $0.key < $1.key }) {
            guard case .object(let p)? = properties[name] else {
                if !properties.isEmpty { out.append("unknown argument \"\(name)\"") }
                continue
            }
            if case .string(let type)? = p["type"], !matches(v, type) {
                out.append("\"\(name)\" should be \(type), got \(kind(v))")
            }
        }
        return out
    }

    static func matches(_ v: JSONValue, _ type: String) -> Bool {
        switch (type, v) {
        case ("string", .string), ("boolean", .bool), ("array", .array), ("object", .object), ("null", .null): return true
        case ("number", .number): return true
        case ("integer", .number(let d)): return d.rounded() == d
        default: return false
        }
    }

    static func kind(_ v: JSONValue) -> String {
        switch v {
        case .string: "a string"
        case .number: "a number"
        case .bool: "a boolean"
        case .array: "an array"
        case .object: "an object"
        case .null: "null"
        }
    }
}
