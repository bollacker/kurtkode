import Foundation

/// List prices for the native APIs, which don't say what a request cost: a turn's cost is estimated from its usage.
/// Dollars per million tokens, standard (paid) tier, as published when this table was written (`asOf`): Anthropic's
/// model table, and ai.google.dev/gemini-api/docs/pricing. Prices change; a model missing here gets no estimate.
public enum PriceList {
    public static let asOf = "2026-10-14"
    /// Changes with every edit of the tables below, and is kept with each cost entry (`CostBreakdown.priceList`).
    public static let version = "2026-10-15.1"

    /// Dollars per million tokens, for each kind of token billed.
    public struct Rates: Codable, Sendable, Hashable {
        public var input: Double
        public var output: Double          // thinking is billed as output (Claude, Gemini, OpenAI)
        public var cacheRead: Double
        public var cacheWrite5m: Double
        public var cacheWrite1h: Double
    }

    public struct Price: Sendable, Hashable {
        public var standard: Rates
        /// Prompts longer than this many tokens are billed at `long` instead (Gemini Pro, Claude Haiku 5.5).
        public var longAbove: Int?
        public var long: Rates?
        /// Dollars per server-side web search; nil when the provider bills searches but the price isn't known here.
        public var perSearch: Double?
        /// Dollars per request (some OpenRouter models).
        public var perRequest: Double?

        public var input: Double { standard.input }
        public var output: Double { standard.output }
        public var cacheRead: Double { standard.cacheRead }

        func rates(forPrompt tokens: Int) -> (Rates, tier: String) {
            if let longAbove, tokens > longAbove, let long { return (long, "long") }
            return (standard, "standard")
        }
    }

    struct Entry {
        var model: String
        var price: Price
        /// The last day the price holds (some are introductory), in UTC.
        var until: String? = nil
    }

    /// Anthropic: cache writes at 1.25× input (five-minute cache) or 2× (an hour); web search $10 per 1,000.
    static func a(_ input: Double, _ output: Double, _ cacheRead: Double, longAbove: Int? = nil, long: [Double]? = nil) -> Price {
        func rates(_ i: Double, _ o: Double, _ r: Double) -> Rates {
            Rates(input: i, output: o, cacheRead: r, cacheWrite5m: i * 1.25, cacheWrite1h: i * 2)
        }
        return Price(standard: rates(input, output, cacheRead), longAbove: longAbove,
                     long: long.map { rates($0[0], $0[1], $0[2]) }, perSearch: 0.01)
    }

    /// Gemini: implicit caching has no write charge (writes, if ever reported, at the input price). Search grounding
    /// is billed per query, at a price not in this table: searches are left unpriced (`CostBreakdown.unpriced`).
    static func g(_ input: Double, _ output: Double, _ cacheRead: Double, longAbove: Int? = nil, long: [Double]? = nil) -> Price {
        func rates(_ i: Double, _ o: Double, _ r: Double) -> Rates {
            Rates(input: i, output: o, cacheRead: r, cacheWrite5m: i, cacheWrite1h: i)
        }
        return Price(standard: rates(input, output, cacheRead), longAbove: longAbove,
                     long: long.map { rates($0[0], $0[1], $0[2]) }, perSearch: nil)
    }

    static let anthropic: [Entry] = [
        Entry(model: "claude-fable-5-1", price: a(10, 50, 0.25)),
        Entry(model: "claude-fable-5", price: a(10, 50, 1.00)),
        Entry(model: "claude-opus-5-5", price: a(4, 20, 0.20)),
        Entry(model: "claude-opus-5", price: a(5, 25, 0.50)),
        Entry(model: "claude-opus-4-8", price: a(5, 25, 0.50)),
        Entry(model: "claude-opus-4-7", price: a(5, 25, 0.50)),
        Entry(model: "claude-opus-4-6", price: a(5, 25, 0.50)),
        Entry(model: "claude-sonnet-5-5", price: a(2, 10, 0.20)),
        Entry(model: "claude-sonnet-5", price: a(2, 10, 0.20)),
        Entry(model: "claude-sonnet-4-6", price: a(3, 15, 0.30)),
        Entry(model: "claude-haiku-5-5", price: a(0.10, 0.50, 0.01, longAbove: 100_000, long: [0.50, 2.50, 0.05])),
        Entry(model: "claude-haiku-4-5", price: a(1, 5, 0.10)),
    ]

    /// Gemini's implicit cache has no storage fee; cached tokens are billed at the context-caching price.
    static let gemini: [Entry] = [
        Entry(model: "gemini-4-argon", price: g(2, 10, 0.10), until: "2026-11-30"),
        Entry(model: "gemini-4-argon", price: g(4, 20, 0.20)),
        Entry(model: "gemini-3.8-flash", price: g(0.75, 3.75, 0.075), until: "2026-12-31"),
        Entry(model: "gemini-3.8-flash", price: g(1.50, 7.50, 0.15)),
        Entry(model: "gemini-3.6-flash", price: g(0.75, 3.75, 0.075), until: "2026-12-31"),
        Entry(model: "gemini-3.6-flash", price: g(1.50, 7.50, 0.15)),
        Entry(model: "gemini-3.1-pro", price: g(2, 12, 0.20, longAbove: 200_000, long: [4, 18, 0.40])),
        Entry(model: "gemini-3-flash", price: g(0.50, 3.00, 0.05)),
        Entry(model: "gemini-2.5-flash", price: g(0.30, 2.50, 0.03)),
    ]

    /// Days after `asOf` when the table counts as old: providers change prices a few times a year.
    public static let staleAfterDays = 60

    /// A warning when the table is older than `staleAfterDays` on `day`, or nil. Claude and Gemini costs are estimated
    /// from it (OpenRouter's come from its live `/models`), so an old table means estimates that may be off.
    public static func staleness(on day: Date = Date()) -> String? {
        guard let written = DayFormat.formatter().date(from: asOf) else { return nil }
        let days = Int(day.timeIntervalSince(written) / 86_400)
        guard days > staleAfterDays else { return nil }
        return "kurtkode's price table for Claude and Gemini is from \(asOf) (\(days) days old): their cost estimates "
            + "may be off. A newer kurtkode has a newer table."
    }

    /// The price of `model` on `day` (a later price takes over once an introductory one ends).
    public static func price(api: WireAPI, model: String, on day: Date = Date()) -> Price? {
        let list: [Entry]
        switch api {
        case .anthropic: list = anthropic
        case .gemini: list = gemini
        case .openai: return nil
        }
        let today = DayFormat.formatter().string(from: day)
        let m = model.lowercased()
        // The longest matching name wins ("claude-opus-5-5" before "claude-opus-5"); for one name, the introductory
        // price (with an end date) before the regular one, explicitly: `sorted` doesn't promise to keep the order.
        for e in list.sorted(by: { ($0.model.count, $0.until != nil ? 1 : 0) > ($1.model.count, $1.until != nil ? 1 : 0) })
        where names(m, e.model) {
            if let until = e.until, today > until { continue }
            return e.price
        }
        return nil
    }

    /// Whether `model` is `name` or a dated or preview id of it (not another model that shares the start:
    /// "gemini-2.5-flash-lite" isn't "gemini-2.5-flash", "claude-opus-5-5" isn't "claude-opus-5").
    static func names(_ model: String, _ name: String) -> Bool {
        if model == name { return true }
        guard model.hasPrefix(name + "-") || model.hasPrefix(name + "@") else { return false }
        let rest = model.dropFirst(name.count + 1)
        let pieces = rest.split(whereSeparator: { $0 == "-" || $0 == "@" })
        // A short number first is a version of an unlisted model ("claude-sonnet-5-6-20270101" isn't "claude-sonnet-5");
        // a date has eight digits.
        if let first = pieces.first, first.allSatisfy(\.isNumber), first.count < 8 { return false }
        // A product variant has its own price ("gemini-2.5-flash-image" isn't "gemini-2.5-flash").
        let variants: Set<Substring> = ["lite", "image", "live", "tts", "audio", "embedding", "robotics"]
        return !pieces.contains { variants.contains($0) }
    }

    /// What the first request on another model costs for a prompt of `promptTokens`: none of it is in that model's cache
    /// (caches belong to one model), and Anthropic bills it as a cache write. Nil for a model not in the table.
    public static func switchCost(promptTokens: Int, api: WireAPI, model: String, cacheHour: Bool = false) -> Double? {
        let write = api == .anthropic ? promptTokens : 0
        let u = Usage(promptTokens: promptTokens, completionTokens: 0, cacheReadTokens: 0, cacheWriteTokens: write,
                      cacheWriteHourTokens: cacheHour ? write : nil)
        return cost(u, api: api, model: model)
    }

    /// What switching a session of `promptTokens` to `model` means, in words, or nil when it's small. `fromThinking`: the
    /// last reply carried Claude thinking (it stays with the model that wrote it).
    public static func switchNote(promptTokens: Int, api: WireAPI, model: String, fromThinking: Bool, cacheHour: Bool = false) -> String? {
        guard promptTokens >= 8000 else { return nil }
        var s = "Its first request resends this session's \(promptTokens / 1000)k tokens without a cache (caches belong to one model)"
        if let c = switchCost(promptTokens: promptTokens, api: api, model: model, cacheHour: cacheHour) {
            s += String(format: ": about $%.2f at list price", c)
        } else if api == .openai {
            s += ": on a local model, a wait while it reads them; on a paid one, the full input price"
        }
        s += "; switching back costs as much again."
        if fromThinking { s += " Claude's earlier thinking stays with the model that wrote it." }
        return s
    }

    /// What a request cost at list price; nil for a model not in the table.
    public static func cost(_ u: Usage, api: WireAPI, model: String, on day: Date = Date()) -> Double? {
        breakdown(u, api: api, model: model, on: day)?.total
    }

    /// A request's list price, by component; nil for a model not in the table.
    public static func breakdown(_ u: Usage, api: WireAPI, model: String, on day: Date = Date()) -> CostBreakdown? {
        guard let price = price(api: api, model: model, on: day) else { return nil }
        return CostBreakdown(u, price: price, source: api == .anthropic ? "Anthropic list price" : "Gemini list price",
                             priceList: version)
    }
}
