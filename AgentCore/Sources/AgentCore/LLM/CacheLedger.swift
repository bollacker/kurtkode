import CryptoKit
import Foundation

/// What a request sent, in short hashes: enough for the next request to tell what changed between them, which is what
/// decides how much of its prompt the server can read from its cache (CACHING_PLAN.md, Phase 0).
public struct PromptPrint: Codable, Sendable, Hashable {
    /// The tool definitions, in order.
    public var tools: String
    /// The leading system messages as sent (the stable prompt, its changing section and any summary).
    public var system: String
    /// Messages after the system prompt.
    public var messages: Int
    /// Those messages, in order.
    public var history: String
    public var model: String
    public var effort: String?
    /// The cache lifetime the request asked for ("5m", "1h"), where the server takes one.
    public var ttl: String?

    /// The print of `request`, and whether its history starts with exactly the messages `previous` sent (nil without a
    /// previous print, or when this request has fewer messages).
    public static func of(_ request: ChatRequest, ttl: String? = nil, previous: PromptPrint? = nil) -> (print: PromptPrint, extends: Bool?) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var t = SHA256()
        for d in request.tools {
            t.update(string: d.name); t.update(string: d.description)
            t.update(data: (try? enc.encode(d.parameters)) ?? Data())
        }
        let system = request.messages.prefix { $0.role == .system }
        var s = SHA256()
        for m in system { s.update(string: m.content) }
        let rest = request.messages.dropFirst(system.count)
        var h = SHA256()
        var extends: Bool?
        for (i, m) in rest.enumerated() {
            if let p = previous, i == p.messages { extends = short(h) == p.history }
            h.update(string: m.role.rawValue); h.update(string: m.content); h.update(string: m.reasoning ?? "")
            for c in m.toolCalls { h.update(string: c.id); h.update(string: c.name); h.update(string: c.arguments) }
            h.update(string: m.toolCallID ?? "")
            for img in m.images ?? [] { h.update(string: img.id.uuidString) }
            if let n = m.native { h.update(data: (try? enc.encode(n)) ?? Data()) }
            h.update(string: "\u{1}")
        }
        let print = PromptPrint(tools: short(t), system: short(s), messages: rest.count, history: short(h), model: request.model,
                                effort: request.reasoningEffort, ttl: ttl)
        if let p = previous, rest.count == p.messages { extends = print.history == p.history }
        return (print, extends)
    }

    static func short(_ h: SHA256) -> String { h.finalize().prefix(8).map { String(format: "%02x", $0) }.joined() }
}

private extension SHA256 {
    mutating func update(string: String) { update(data: Data(string.utf8)); update(data: Data([0])) }
}

/// A request that read much less from the cache than the one before it could have left there, and why.
public struct CacheMiss: Codable, Sendable, Hashable {
    public enum Cause: String, Codable, Sendable, CaseIterable {
        /// Another model or endpoint (caches belong to one model).
        case model
        /// A compaction replaced the start of the conversation.
        case compaction
        /// Earlier tool outputs were trimmed to make room.
        case trim
        /// The tool definitions changed (invalidates everything after them).
        case tools
        /// The system prompt changed.
        case system
        /// The reasoning effort changed (invalidates the messages on most models).
        case effort
        /// An earlier message changed (the history wasn't only added to).
        case history
        /// OpenRouter sent it to another provider.
        case provider
        /// The gap since the last request was longer than the cache lasts.
        case ttl
        /// Nothing kurtkode sent explains it: the server dropped or didn't find the cache.
        case evicted

        public var label: String {
            switch self {
            case .model: "model switch"
            case .compaction: "compaction"
            case .trim: "trimmed tool outputs"
            case .tools: "tool list changed"
            case .system: "system prompt changed"
            case .effort: "reasoning effort changed"
            case .history: "earlier message changed"
            case .provider: "provider changed"
            case .ttl: "cache expired (pause)"
            case .evicted: "server-side (unexplained)"
            }
        }
    }

    public var cause: Cause
    /// Seconds from the end of the previous request to the start of this one.
    public var gap: Double
    /// Prompt tokens the previous request left in the cache that this one paid for in full.
    public var lostTokens: Int
    /// What that cost beyond reading them from the cache, at list price; nil when unpriced.
    public var lost: Double?
}

/// Classifies cache misses and answers what-if questions about the cache over recorded requests.
public enum CacheLedger {
    /// What changed between two consecutive requests of one agent, besides their tokens.
    public struct Changes: Sendable, Hashable {
        public var compacted = false
        public var trimmed = false
        /// The current request's history starts with exactly the previous one's (nil: not known).
        public var extends: Bool?
        public init(compacted: Bool = false, trimmed: Bool = false, extends: Bool? = nil) {
            self.compacted = compacted; self.trimmed = trimmed; self.extends = extends
        }
    }

    /// Below this many prompt tokens a miss isn't worth naming (and is under most models' cache minimum).
    static let minimumPrompt = 2048

    /// The miss `current` had after `previous`, or nil when it read about as much as it could. Without `prompt` prints
    /// (older entries) only the model, provider and gap can be told apart.
    public static func classify(previous p: CostEntry, current c: CostEntry, changes: Changes = Changes()) -> CacheMiss? {
        guard let pt = p.tokens, let ct = c.tokens, let read = ct.cacheReadTokens else { return nil }
        let expected = min(pt.promptTokens, ct.promptTokens)
        guard expected >= minimumPrompt else { return nil }
        let lostTokens = expected - read
        guard lostTokens >= max(1024, expected / 4) else { return nil }
        let gap = c.start.timeIntervalSince(p.end)
        let cause: CacheMiss.Cause
        let pp = p.prompt, cp = c.prompt
        if p.requestedModel != c.requestedModel || p.endpointID != c.endpointID { cause = .model }
        else if changes.compacted { cause = .compaction }
        else if changes.trimmed { cause = .trim }
        else if let pp, let cp, pp.tools != cp.tools { cause = .tools }
        else if let pp, let cp, pp.system != cp.system { cause = .system }
        else if let pp, let cp, pp.effort != cp.effort { cause = .effort }
        else if changes.extends == false { cause = .history }
        else if let a = p.provider, let b = c.provider, a != b { cause = .provider }
        else if gap > ttlSeconds(p) { cause = .ttl }
        else { cause = .evicted }
        return CacheMiss(cause: cause, gap: gap, lostTokens: lostTokens, lost: lostDollars(lostTokens, c))
    }

    /// How long the previous request's cache lasts: an hour when it asked for (or wrote) an hour's cache, else five
    /// minutes (Anthropic's default, and about what OpenAI's and Gemini's implicit caches keep).
    static func ttlSeconds(_ e: CostEntry) -> Double {
        e.prompt?.ttl == "1h" || (e.tokens?.cacheWriteHourTokens ?? 0) > 0 ? 3600 : 300
    }

    /// `tokens` paid at what this request paid for its uncached input, less what reading them would have cost.
    static func lostDollars(_ tokens: Int, _ e: CostEntry) -> Double? {
        guard let lp = e.listPrice, let u = e.tokens else { return nil }
        let paidTokens = u.promptTokens - (u.cacheReadTokens ?? 0)
        guard paidTokens > 0 else { return nil }
        let paidRate = (lp.uncachedInput + lp.cacheWrite5m + lp.cacheWrite1h) / Double(paidTokens)
        return max(0, Double(tokens) * (paidRate - lp.rates.cacheRead / 1_000_000))
    }

    // MARK: - A cold session

    /// What the next message to a session whose cache has expired will cost, in words, or nil when its cache should
    /// still be warm, the session is small (under `minimumTokens`), or its model is unpriced (local). `last` is the
    /// session's last reply request (`Session.lastReplyCost`). CACHING_PLAN.md 1.7: Claude Code nudges toward /clear
    /// for the same reason; this says what each choice costs.
    public static func coldResumeNote(last: CostEntry?, now: Date = Date(), minimumTokens: Int = 50_000) -> String? {
        guard let last, let u = last.tokens, let r = last.listPrice?.rates, u.promptTokens >= minimumTokens else { return nil }
        let idle = now.timeIntervalSince(last.end)
        let ttl = ttlSeconds(last)
        guard idle > ttl else { return nil }
        let prompt = Double(u.promptTokens)
        // The next request writes the whole prompt (Anthropic bills the write; elsewhere it's plain input).
        let hour = ttl > 300
        let write = r.cacheWrite5m > r.input ? (hour ? r.cacheWrite1h : r.cacheWrite5m) : r.input
        let kept = min(prompt, 40_000)
        let resume = prompt * write / 1_000_000
        let compact = (prompt * write + 4_000 * r.output + kept * write) / 1_000_000
        let saved = (prompt - kept) * r.cacheRead / 1_000_000
        let minutes = Int(idle / 60)
        let since = minutes >= 120 ? "\(minutes / 60) hours" : "\(minutes) minutes"
        return "This session's prompt cache has expired (idle \(since)): the next message re-reads all "
            + "\(u.promptTokens / 1000)k tokens at full price, about " + money(resume) + ". /compact first costs about "
            + money(compact) + " once, and each later request then reads about \(Int(kept) / 1000)k tokens instead of "
            + "\(u.promptTokens / 1000)k (" + money(saved) + " less each); a new session costs nothing to start."
    }

    static func money(_ v: Double) -> String { v < 0.01 ? String(format: "$%.4f", v) : String(format: "$%.2f", v) }

    // MARK: - Over recorded requests

    /// One reply request and the one before it from the same agent in the same session file.
    public struct Step: Sendable {
        public var group: String
        public var entry: CostEntry
        public var previous: CostEntry?
        /// The recorded miss, or one worked out from what older entries recorded.
        public var miss: CacheMiss? { entry.cacheMiss ?? previous.flatMap { CacheLedger.classify(previous: $0, current: entry) } }
    }

    /// The loop's own replies (not side calls), ordered within each session file and agent.
    public static func steps(_ entries: [(session: SessionHeader, entry: CostEntry)]) -> [Step] {
        let replies = entries.filter { [.reply, .nudgedReply].contains($0.entry.purpose) && $0.entry.tokens != nil }
        let groups = Dictionary(grouping: replies) { "\($0.session.id)|\($0.entry.agent)" }
        var out: [Step] = []
        for (key, list) in groups {
            let sorted = list.map(\.entry).sorted { $0.start < $1.start }
            for (i, e) in sorted.enumerated() { out.append(Step(group: key, entry: e, previous: i > 0 ? sorted[i - 1] : nil)) }
        }
        return out.sorted { $0.entry.start < $1.entry.start }
    }

    public struct CauseRow: Sendable, Hashable {
        public var cause: CacheMiss.Cause
        public var count = 0
        public var lostTokens = 0
        public var lost = 0.0
    }

    public struct GapRow: Sendable, Hashable {
        public var label: String
        public var count = 0
        public var promptTokens = 0
        public var cacheReadTokens = 0
    }

    public static func causes(_ steps: [Step]) -> [CauseRow] {
        var rows: [CacheMiss.Cause: CauseRow] = [:]
        for s in steps {
            guard let m = s.miss else { continue }
            var r = rows[m.cause] ?? CauseRow(cause: m.cause)
            r.count += 1; r.lostTokens += m.lostTokens; r.lost += m.lost ?? 0
            rows[m.cause] = r
        }
        return rows.values.sorted { ($0.lost, $0.lostTokens) > ($1.lost, $1.lostTokens) }
    }

    /// Requests by the pause before them: the user thinking, an approval, a background wait.
    public static func gaps(_ steps: [Step]) -> [GapRow] {
        let edges: [(String, Double)] = [("under 1 min", 60), ("1–5 min", 300), ("5–60 min", 3600), ("over 1 h", .infinity)]
        var rows = edges.map { GapRow(label: $0.0) }
        for s in steps {
            guard let p = s.previous, let u = s.entry.tokens else { continue }
            let gap = s.entry.start.timeIntervalSince(p.end)
            let i = edges.firstIndex { gap < $0.1 } ?? edges.count - 1
            rows[i].count += 1; rows[i].promptTokens += u.promptTokens; rows[i].cacheReadTokens += u.cacheReadTokens ?? 0
        }
        return rows
    }

    /// The input side of `steps` repriced with every cache write at `ttl` ("5m" or "1h"): with an hour's cache, what
    /// expired in a 5–60 minute pause is read instead of written again; with five minutes, what an hour's cache kept
    /// over such a pause is written again. Only for servers that bill cache writes (Anthropic, Claude through
    /// OpenRouter); returns (actual, what-if) at list price.
    public static func ttlWhatIf(_ steps: [Step], ttl: String) -> (actual: Double, whatIf: Double, requests: Int) {
        var actual = 0.0, would = 0.0, n = 0
        for s in steps {
            guard let u = s.entry.tokens, let r = s.entry.listPrice?.rates, r.cacheWrite5m > r.input else { continue }
            let lp = s.entry.listPrice!
            n += 1
            actual += lp.uncachedInput + lp.cacheRead + lp.cacheWrite5m + lp.cacheWrite1h
            var read = u.cacheReadTokens ?? 0
            var write = u.cacheWriteTokens ?? 0
            let fresh = max(0, u.promptTokens - read - write)
            let gap = s.previous.map { s.entry.start.timeIntervalSince($0.end) } ?? 0
            if ttl == "1h", let m = s.miss, m.cause == .ttl, gap <= 3600 {
                let back = min(m.lostTokens, write); read += back; write -= back
            } else if ttl == "5m", s.previous != nil, gap > 300, gap <= 3600 {
                write += read; read = 0
            }
            let writeRate = ttl == "1h" ? r.cacheWrite1h : r.cacheWrite5m
            would += (Double(fresh) * r.input + Double(read) * r.cacheRead + Double(write) * writeRate) / 1_000_000
        }
        return (actual, would, n)
    }

    /// An estimate of the input side of `steps` had each session compacted whenever its prompt passed `threshold`
    /// tokens: the prompt grows by what each request added, a compaction leaves the session's first prompt plus 24k
    /// tokens (the kept messages and the summary) and costs a cached read of everything, a write of what's left and a
    /// 4,000-token summary. Only sessions that pass `threshold` are counted; returns (actual, estimate, sessions).
    public static func compactionWhatIf(_ steps: [Step], threshold: Int) -> (actual: Double, estimate: Double, sessions: Int) {
        var actual = 0.0, estimate = 0.0, sessions = 0
        for (_, list) in Dictionary(grouping: steps, by: \.group) {
            let seq = list.sorted { $0.entry.start < $1.entry.start }
            guard seq.contains(where: { ($0.entry.tokens?.promptTokens ?? 0) > threshold }),
                  let first = seq.first?.entry.tokens?.promptTokens else { continue }
            sessions += 1
            let after = first + 24_000
            var context = first, last = first
            for s in seq {
                guard let u = s.entry.tokens, let lp = s.entry.listPrice else { continue }
                let r = lp.rates
                actual += lp.uncachedInput + lp.cacheRead + lp.cacheWrite5m + lp.cacheWrite1h
                let added = max(0, u.promptTokens - last)
                last = u.promptTokens
                let writeRate = (u.cacheWriteHourTokens ?? 0) > 0 ? r.cacheWrite1h : max(r.cacheWrite5m, r.input)
                if context + added > threshold {
                    estimate += (Double(context) * r.cacheRead + Double(after) * writeRate + 4000 * r.output) / 1_000_000
                    context = after
                }
                estimate += (Double(context) * r.cacheRead + Double(added) * writeRate) / 1_000_000
                context += added
            }
        }
        return (actual, estimate, sessions)
    }
}
