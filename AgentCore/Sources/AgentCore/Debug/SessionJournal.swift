import Foundation

/// A session's whole life in one stream, for seeing how earlier things in the context affect later ones: the system
/// prompt, what the user sent, each reply's reasoning and text, tool uses (call with result), what the loop did,
/// compactions, and changes of model, mode, and folders. With the context index (`WireLog.contexts`) it can say,
/// for any turn, which of these were in that turn's request, trimmed, or not sent, and why.
public struct SessionJournal: Sendable {
    public struct Entry: Identifiable, Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            /// The system prompt as sent from this turn on (`bytes`); `summary`: it carried a compaction summary.
            case system(summary: Bool)
            case user(ChatMessage)
            case command(ChatMessage)
            /// Files the user attached with @ (sent as tool calls and results).
            case attachment(call: ToolCall, result: ChatMessage?)
            case reasoning(ChatMessage)
            case output(ChatMessage)
            case toolUse(call: ToolCall, reply: ChatMessage, result: ChatMessage?)
            /// Something the loop did about a reply (a nudge, a retry, recovered calls).
            case loop(String, reply: ChatMessage)
            case compaction(Compaction)
            case event(SessionEvent)
        }
        public var id: String
        public var kind: Kind
        public var date: Date
        /// The model turn it belongs to (for a reply's parts), or the turn after which it happened.
        public var turn: Int?
        /// Size as text (the model's tokens are about a quarter of this).
        public var bytes: Int

        /// Searchable text: what the entry says.
        public var text: String {
            switch kind {
            case .system: return ""
            case .user(let m), .command(let m), .output(let m): return m.content
            case .reasoning(let m): return m.reasoning ?? ""
            case .attachment(let c, let r), .toolUse(let c, _, let r): return c.name + " " + c.arguments + "\n" + (r?.content ?? "")
            case .loop(let s, _): return s
            case .compaction(let c): return c.modelText
            case .event(let e): return e.text
            }
        }
    }

    public var entries: [Entry]
    /// Model turns in order: reply id → turn number (from 1).
    public let turnOfReply: [UUID: Int]
    /// Each turn's request context, by turn number.
    public let contexts: [Int: ContextSnapshot]
    let session: Session
    let messageIndex: [UUID: Int]
    /// Thinking the server dropped from a request although it was sent: request (reply id) → message id → why.
    let droppedThinking: [UUID: [UUID: String]]

    /// `droppedThinking`: from `SessionJournal.droppedThinking(session:wire:)`, when the wire log is at hand.
    public init(session: Session, contexts snapshots: [ContextSnapshot], droppedThinking: [UUID: [UUID: String]] = [:]) {
        self.session = session
        self.droppedThinking = droppedThinking
        var index: [UUID: Int] = [:]
        for (i, m) in session.messages.enumerated() { index[m.id] = i }
        messageIndex = index
        let results = ChatMessage.resultsByReply(session.messages)
        let boundaries = Dictionary(session.compactions.map { ($0.lastSummarizedID, $0) }, uniquingKeysWith: { _, b in b })
        let byReply = Dictionary(snapshots.map { ($0.replyID, $0) }, uniquingKeysWith: { _, b in b })

        var turns: [UUID: Int] = [:]
        var ctx: [Int: ContextSnapshot] = [:]
        var out: [Entry] = []
        var turn = 0
        var lastSystem: ContextRef?
        for m in session.messages {
            switch m.role {
            case .user:
                out.append(Entry(id: m.id.uuidString, kind: m.userCommand == nil ? .user(m) : .command(m), date: m.createdAt,
                                 turn: turn, bytes: m.content.utf8.count))
            case .assistant where m.meta == nil:
                // An @ mention: the user's attachment, sent as calls and results.
                for c in m.toolCalls {
                    let r = results[m.id]?[c.id]
                    out.append(Entry(id: "attach-\(m.id.uuidString)-" + c.id, kind: .attachment(call: c, result: r), date: m.createdAt, turn: turn,
                                     bytes: (r?.content.utf8.count ?? 0)))
                }
            case .assistant:
                turn += 1
                turns[m.id] = turn
                let snapshot = byReply[m.id]
                if let snapshot {
                    ctx[turn] = snapshot
                    // The system prompt: shown where it starts and wherever it changes.
                    if let sys = snapshot.refs.first(where: { $0.role == "system" }), sys != lastSystem {
                        let e = Entry(id: "system-\(turn)", kind: .system(summary: sys.kind == "system+summary"),
                                      date: snapshot.startedAt, turn: turn, bytes: sys.bytes)
                        // The first one opens the journal: it starts every request.
                        if lastSystem == nil { out.insert(e, at: 0) } else { out.append(e) }
                        lastSystem = sys
                    }
                }
                if let r = m.reasoning, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(Entry(id: "reasoning-" + m.id.uuidString, kind: .reasoning(m), date: m.createdAt, turn: turn, bytes: r.utf8.count))
                }
                if !m.content.isEmpty || m.toolCalls.isEmpty {
                    out.append(Entry(id: "output-" + m.id.uuidString, kind: .output(m), date: m.createdAt, turn: turn, bytes: m.content.utf8.count))
                }
                for c in m.toolCalls {
                    let r = results[m.id]?[c.id]
                    out.append(Entry(id: "tool-\(m.id.uuidString)-" + c.id, kind: .toolUse(call: c, reply: m, result: r), date: r?.createdAt ?? m.createdAt,
                                     turn: turn, bytes: c.arguments.utf8.count + (r?.content.utf8.count ?? 0)))
                }
                for (i, note) in (m.meta?.notes ?? []).enumerated() {
                    out.append(Entry(id: "loop-\(i)-" + m.id.uuidString, kind: .loop(note, reply: m), date: m.createdAt, turn: turn,
                                     bytes: 0))
                }
            case .tool, .system:
                break
            }
            if let c = boundaries[m.id] {
                out.append(Entry(id: "compaction-" + c.lastSummarizedID.uuidString, kind: .compaction(c), date: out.last?.date ?? m.createdAt,
                                 turn: turn, bytes: c.modelText.utf8.count))
            }
        }
        // Events (model, mode, folders) go in by time.
        for e in session.events.sorted(by: { $0.at < $1.at }) {
            let i = out.firstIndex { $0.date > e.at } ?? out.count
            let turnBefore = i > 0 ? out[i - 1].turn : 0
            out.insert(Entry(id: "event-\(e.kind.rawValue)-\(e.at.timeIntervalSince1970)", kind: .event(e), date: e.at,
                             turn: turnBefore, bytes: 0), at: i)
        }
        entries = out
        turnOfReply = turns
        contexts = ctx
    }

    public var turnCount: Int { turnOfReply.count }

    // MARK: The context lens

    public enum Status: Sendable, Hashable {
        /// In the turn's request as it is.
        case inContext
        /// In the request, but shortened (an old tool result after a compaction).
        case trimmed
        /// Not in the request, and why.
        case notSent(String)
        /// Part of the turn's own reply.
        case thisTurn
        /// After the turn's request.
        case later
        /// Not something a context holds (an event).
        case none
    }

    /// Every entry's status in turn `n`'s request, by entry id (the lookup built once).
    public func statuses(inTurn n: Int) -> [String: Status] {
        guard let snapshot = contexts[n] else { return [:] }
        let refs = Self.refs(snapshot)
        return Dictionary(entries.map { ($0.id, status($0, inTurn: n, snapshot: snapshot, refs: refs)) }, uniquingKeysWith: { a, _ in a })
    }

    static func refs(_ s: ContextSnapshot) -> [UUID: ContextRef] {
        Dictionary(s.refs.compactMap { r in r.id.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Where `entry` stood in turn `n`'s request.
    public func status(_ entry: Entry, inTurn n: Int) -> Status {
        guard let snapshot = contexts[n] else { return .none }
        return status(entry, inTurn: n, snapshot: snapshot, refs: Self.refs(snapshot))
    }

    func status(_ entry: Entry, inTurn n: Int, snapshot: ContextSnapshot, refs: [UUID: ContextRef]) -> Status {
        // A reply's parts belong to their turn; anything else happened after the reply numbered `turn`, so turn n can
        // hold it only if it came before n's request (turn < n). The system prompt is placed at the turn it starts.
        switch entry.kind {
        case .event: return .none
        case .system: break
        case .reasoning, .output, .toolUse, .loop:
            let t = entry.turn ?? 0
            if t == n { return .thisTurn }
            if t > n { return .later }
        default:
            if (entry.turn ?? 0) >= n { return .later }
        }
        func presence(_ id: UUID, fullBytes: Int) -> Status? {
            guard let r = refs[id] else { return nil }
            return r.bytes < fullBytes ? .trimmed : .inContext
        }
        switch entry.kind {
        case .event:
            return .none
        case .system:
            // The version in force for turn n is the latest one at or before it.
            if (entry.turn ?? 0) > n { return .later }
            let latest = entries.last { if case .system = $0.kind, ($0.turn ?? 0) <= n { true } else { false } }
            return latest?.id == entry.id ? .inContext : .notSent("replaced by a later system prompt")
        case .compaction:
            // Its summary rides in the system prompt; a later compaction replaces it.
            guard snapshot.refs.first(where: { $0.role == "system" })?.kind == "system+summary" else {
                return .notSent("the system prompt carried no summary")
            }
            let latest = entries.last { if case .compaction = $0.kind, ($0.turn ?? 0) < n { true } else { false } }
            return latest?.id == entry.id ? .inContext : .notSent("replaced by a later compaction")
        case .user(let m), .command(let m):
            return presence(m.id, fullBytes: m.content.utf8.count) ?? .notSent(absence(m.id, snapshot))
        case .attachment(_, let r):
            guard let r else { return .notSent("no result") }
            return presence(r.id, fullBytes: r.content.utf8.count) ?? .notSent(absence(r.id, snapshot))
        case .output(let m):
            if m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, m.toolCalls.isEmpty {
                return .notSent("an empty reply isn't sent back")
            }
            return presence(m.id, fullBytes: 0).map { _ in .inContext } ?? .notSent(absence(m.id, snapshot))
        case .reasoning(let m):
            guard let r = refs[m.id] else { return .notSent(absence(m.id, snapshot)) }
            if r.reasoning == true {
                if let why = droppedThinking[snapshot.replyID]?[m.id] { return .notSent("sent, but the server dropped it: " + why) }
                return .inContext
            }
            return .notSent(reasoningAbsence(m, snapshot))
        case .toolUse(_, let reply, let result):
            guard refs[reply.id] != nil else { return .notSent(absence(reply.id, snapshot)) }
            guard let result else { return .notSent("no result recorded for the call") }
            return presence(result.id, fullBytes: result.content.utf8.count) ?? .notSent(absence(result.id, snapshot))
        case .loop(let note, let reply):
            // A nudge goes only into the request right after its reply.
            guard note.hasPrefix("The reply was empty") else { return .notSent("the loop's own record") }
            return turnOfReply[reply.id].map { $0 + 1 } == n && snapshot.refs.contains { $0.kind == "nudge" }
                ? .inContext : .notSent("a nudge is sent once, in the next request")
        }
    }

    private func firstMessageIndex(_ s: ContextSnapshot) -> Int? {
        s.refs.compactMap { $0.id.flatMap { messageIndex[$0] } }.min()
    }

    /// Why a reply's reasoning didn't go back with a request that held the reply.
    private func reasoningAbsence(_ m: ChatMessage, _ s: ContextSnapshot) -> String {
        guard let native = m.native else { return "reasoning isn't sent back to this model" }
        let model = messageIndex[s.replyID].flatMap { session.messages[$0].meta?.requestedModel }
        if let model, model != native.model {
            return "\(native.model) wrote it; thinking goes back only to the model that wrote it (this turn: \(model))"
        }
        if native.api == .anthropic, !(native.blocks.arrayValue ?? []).contains(where: {
            let t = AnthropicWire.type($0)
            return t == "thinking" || t == "redacted_thinking"
        }) { return "the server returned no thinking blocks to send back" }
        return "the reply was changed after it arrived (a tool call renamed or recovered), so its thinking can't go back"
    }

    /// Thinking the server dropped from requests although kurtkode sent it (Anthropic's `input_transformations`, kept in
    /// each turn's recorded response), by request and message. Reads only the wire records of turns noted as having
    /// had some dropped. A block is matched to its message by its signature (paths in the request shift with merging).
    public static func droppedThinking(session: Session, wire: URL) -> [UUID: [UUID: String]] {
        var bySignature: [String: UUID] = [:]
        for m in session.messages where m.native?.api == .anthropic {
            for case .object(let b) in m.native?.blocks.arrayValue ?? [] {
                if let s = NativeWire.string(b["signature"]) ?? NativeWire.string(b["data"]), !s.isEmpty { bySignature[s] = m.id }
            }
        }
        guard !bySignature.isEmpty else { return [:] }
        var out: [UUID: [UUID: String]] = [:]
        for reply in session.messages where reply.meta?.notes?.contains(where: { $0.contains("earlier thinking block") }) == true {
            guard let record = WireLog.read(wire, replyID: reply.id), case .object(let request) = record.request,
                  case .array(let sent)? = request["messages"] else { continue }
            for case .object(let event) in record.payloads where NativeWire.string(event["type"]) == "message_start" {
                guard case .object(let message)? = event["message"], case .array(let changes)? = message["input_transformations"] else { continue }
                for case .object(let c) in changes where NativeWire.string(c["type"]) == "thinking_dropped" {
                    // "messages.7.content.0"
                    let parts = (NativeWire.string(c["path"]) ?? "").split(separator: ".")
                    guard parts.count == 4, let i = Int(parts[1]), let j = Int(parts[3]), i < sent.count,
                          case .object(let m) = sent[i], case .array(let content)? = m["content"], j < content.count,
                          case .object(let block) = content[j],
                          let sig = NativeWire.string(block["signature"]) ?? NativeWire.string(block["data"]),
                          let owner = bySignature[sig] else { continue }
                    out[reply.id, default: [:]][owner] = switch NativeWire.string(c["reason"]) {
                    case "prefix_binding_mismatch": "the history before it changed (a compaction or trimmed output)"
                    case "model_binding_mismatch": "another model wrote it"
                    case let r?: r
                    case nil: "no reason given"
                    }
                }
            }
        }
        return out
    }

    /// Why a session message isn't in a request.
    private func absence(_ id: UUID, _ s: ContextSnapshot) -> String {
        guard let i = messageIndex[id] else { return "not a session message" }
        if session.compactions.contains(where: { (messageIndex[$0.lastSummarizedID] ?? -1) >= i }), let first = firstMessageIndex(s), i < first {
            return "replaced by a compaction summary"
        }
        if AgentLoop.droppedCall(session.messages[i]) { return "a lost reply isn't sent back" }
        return "not in this request"
    }

    // MARK: Lifetimes

    /// The turns whose requests held the entry, with whether it was trimmed there.
    public func lifetime(_ entry: Entry) -> [(turn: Int, trimmed: Bool)] {
        (1...max(1, turnCount)).compactMap { n in
            switch status(entry, inTurn: n) {
            case .inContext: (n, false)
            case .trimmed: (n, true)
            default: nil
            }
        }
    }

    /// The lifetime in words: "in context for turns 3–12 (trimmed from 9)".
    public func lifetimeSummary(_ entry: Entry) -> String {
        let life = lifetime(entry)
        guard let first = life.first, let last = life.last else {
            if case .notSent(let why) = (1...max(1, turnCount)).map({ status(entry, inTurn: $0) }).first(where: { if case .notSent = $0 { true } else { false } }) ?? .none {
                return "never in a request: \(why)"
            }
            return "never in a request"
        }
        var ranges: [String] = []
        var start = first.turn, prev = first.turn
        for p in life.dropFirst() {
            if p.turn != prev + 1 { ranges.append(start == prev ? "\(start)" : "\(start)–\(prev)"); start = p.turn }
            prev = p.turn
        }
        ranges.append(start == prev ? "\(start)" : "\(start)–\(prev)")
        var s = "in context for turn\(life.count == 1 ? "" : "s") " + ranges.joined(separator: ", ")
        if let t = life.first(where: \.trimmed) { s += " (trimmed from turn \(t.turn))" }
        if last.turn < turnCount, case .notSent(let why) = status(entry, inTurn: last.turn + 1) { s += "; then \(why)" }
        return s
    }

    // MARK: Budget

    public struct Budget: Sendable, Hashable {
        public var turn: Int
        /// Prompt tokens the server reported (estimated from bytes when it didn't).
        public var promptTokens: Int
        /// Estimated tokens by part: system, summary, user, assistant, tool.
        public var parts: [String: Int]
        /// Prompt tokens the server read from its cache, when it said.
        public var cachedTokens: Int?
        /// What the request cost (reported, or at list price).
        public var cost: Double?
        public var costIsEstimate = false
    }

    /// What the session's summaries cost (they have no turn of their own in the budget).
    public var summaryCost: Double {
        session.costs.filter { $0.purpose == .summary || $0.purpose == .summaryAttempt }.compactMap(\.spent).reduce(0, +)
    }

    /// Whether turn `n`'s server reported its prompt size (else `budget` estimates it).
    public func reportedPrompt(turn n: Int) -> Bool {
        guard let id = contexts[n]?.replyID, let i = messageIndex[id] else { return false }
        return session.messages[i].meta?.usage != nil
    }

    /// Each turn's prompt, split by what filled it.
    public var budget: [Budget] {
        let replies = Dictionary(session.messages.filter { $0.role == .assistant }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = Dictionary(session.costs.map { ($0.reply, $0) }, uniquingKeysWith: { _, b in b })
        return contexts.keys.sorted().compactMap { n in
            guard let s = contexts[n] else { return nil }
            var bytes: [String: Int] = [:]
            for r in s.refs {
                switch (r.role, r.kind) {
                case ("system", "system+summary"):
                    let summary = session.compactions.last.map { $0.modelText.utf8.count } ?? 0
                    bytes["summary", default: 0] += min(summary, r.bytes)
                    bytes["system", default: 0] += max(0, r.bytes - summary)
                case ("system", _): bytes["system", default: 0] += r.bytes
                case (let role, _): bytes[role, default: 0] += r.bytes
                }
            }
            let total = max(1, bytes.values.reduce(0, +))
            let usage = replies[s.replyID]?.meta?.usage
            let tokens = usage?.promptTokens ?? total / 4
            let scale = Double(tokens) / Double(total)
            let entry = entries[s.replyID]
            return Budget(turn: n, promptTokens: tokens, parts: bytes.mapValues { Int(Double($0) * scale) },
                          cachedTokens: usage?.cacheReadTokens, cost: entry?.spent, costIsEstimate: entry?.charged == nil)
        }
    }

    // MARK: Where did this come from?

    /// The values a tool call passed that may have come from earlier in the session (strings of 3+ characters).
    public static func values(_ call: ToolCall) -> [String] {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8)) else { return [] }
        var out: [String] = []
        func walk(_ v: JSONValue) {
            switch v {
            case .string(let s):
                let line = s.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                if line.count >= 3, !out.contains(line) { out.append(String(line.prefix(120))) }
            case .array(let a): a.forEach(walk)
            case .object(let o): o.keys.sorted().forEach { walk(o[$0]!) }
            default: break
            }
        }
        walk(v)
        return Array(out.prefix(8))
    }

    /// The first entry before `entryID` whose text contains `value` (ignoring the entry's own turn's call).
    public func origin(of value: String, before entryID: String) -> Entry? {
        guard let end = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        return entries[..<end].first { e in
            if case .event = e.kind { return false }
            return e.text.contains(value)
        }
    }
}

// MARK: - Search and filters

extension SessionJournal.Entry {
    /// What the journal's kind filters toggle.
    public enum Group: String, CaseIterable, Sendable, Hashable {
        /// The user's prompts (and commands, attachments) and the model's replies.
        case turns = "Prompts and replies"
        case reasoning = "Reasoning"
        case tools = "Tool uses"
        case loop = "The loop"
        case context = "System and compactions"
        case events = "Changes"
    }

    public var group: Group {
        switch kind {
        case .user, .command, .attachment, .output: .turns
        case .reasoning: .reasoning
        case .toolUse: .tools
        case .loop: .loop
        case .system, .compaction: .context
        case .event: .events
        }
    }

    /// The tool, for a tool use.
    public var toolName: String? {
        if case .toolUse(let c, _, _) = kind { return c.name }
        return nil
    }
}

extension SessionJournal {
    public struct Filter: Sendable, Hashable {
        public enum Lens: String, CaseIterable, Sendable { case all = "Everything", inRequest = "In the request", leftOut = "Left out" }
        public var query = ""
        public var onlyMatches = false
        public var groups = Set(Entry.Group.allCases)
        public var tool: String?
        public var lens = Lens.all
        /// Model turns to show (entries before the first turn count as turn 0, shown with turn 1).
        public var turns: ClosedRange<Int>?

        public init() {}

        public var isEmpty: Bool { self == Filter() }
    }

    /// Whether `text` contains the query, ignoring case and diacritics.
    public static func matches(_ text: String, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public func isMatch(_ e: Entry, _ query: String) -> Bool {
        Self.matches(e.text, query) || e.toolName.map { Self.matches($0, query) } == true
    }

    /// The entries the filter shows, in order. `statuses` is the lens turn's (needed by the lens filter).
    public func visible(_ f: Filter, statuses: [String: Status]) -> [Entry] {
        entries.filter { e in
            guard f.groups.contains(e.group) else { return false }
            if let tool = f.tool, let name = e.toolName, name != tool { return false }
            if let range = f.turns {
                let t = max(1, e.turn ?? 0)
                guard range.contains(t) else { return false }
            }
            switch f.lens {
            case .all: break
            case .inRequest:
                guard let s = statuses[e.id], s == .inContext || s == .trimmed || s == .thisTurn else { return false }
            case .leftOut:
                guard case .notSent? = statuses[e.id] else { return false }
            }
            if f.onlyMatches, !f.query.trimmingCharacters(in: .whitespaces).isEmpty, !isMatch(e, f.query) { return false }
            return true
        }
    }

    /// Entries among `shown` that match the query, in order.
    public func hits(_ query: String, in shown: [Entry]) -> [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return shown.filter { isMatch($0, query) }.map(\.id)
    }
}
