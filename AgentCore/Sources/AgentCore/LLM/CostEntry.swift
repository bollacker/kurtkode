import Foundation

/// A request's list price by component, from the tokens the server reported (COST_TRACKING_DESIGN.md). The list price,
/// not what the account was charged, is what models are compared on.
public struct CostBreakdown: Codable, Sendable, Hashable {
    public var uncachedInput: Double
    public var cacheRead: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    /// All output, thinking included (it's billed as output).
    public var output: Double
    /// The part of `output` that was thinking.
    public var reasoning: Double
    public var searches: Double
    public var requests: Double
    public var total: Double
    /// `standard`, or `long` when the prompt passed the model's long-prompt threshold.
    public var tier: String
    /// The rates applied, per million tokens.
    public var rates: PriceList.Rates
    public var perSearch: Double?
    public var perRequest: Double?
    /// Where the rates came from ("Anthropic list price", "OpenRouter /models").
    public var source: String
    /// `PriceList.version`, or the date OpenRouter's list was read.
    public var priceList: String
    /// Billed components without a known rate (Gemini's searches): the total leaves them out.
    public var unpriced: [String]?

    public init(_ u: Usage, price: PriceList.Price, source: String, priceList: String) {
        let (r, tier) = price.rates(forPrompt: u.promptTokens)
        let read = u.cacheReadTokens ?? 0
        let write = u.cacheWriteTokens ?? 0
        let hour = min(u.cacheWriteHourTokens ?? 0, write)
        let fresh = max(0, u.promptTokens - read - write)
        func d(_ tokens: Int, _ perMillion: Double) -> Double { Double(tokens) * perMillion / 1_000_000 }
        uncachedInput = d(fresh, r.input)
        cacheRead = d(read, r.cacheRead)
        cacheWrite5m = d(write - hour, r.cacheWrite5m)
        cacheWrite1h = d(hour, r.cacheWrite1h)
        output = d(u.completionTokens, r.output)
        reasoning = d(min(u.reasoningTokens, u.completionTokens), r.output)
        let n = u.webSearches ?? 0
        searches = n > 0 ? Double(n) * (price.perSearch ?? 0) : 0
        requests = price.perRequest ?? 0
        total = uncachedInput + cacheRead + cacheWrite5m + cacheWrite1h + output + searches + requests
        self.tier = tier
        rates = r
        perSearch = price.perSearch
        perRequest = price.perRequest
        self.source = source
        self.priceList = priceList
        unpriced = n > 0 && price.perSearch == nil ? ["searches"] : nil
    }
}

/// One billed (or possibly billed) request: who made it and why, what the server reported, and its list price.
/// Written to the session file of the agent run it belongs to (`SessionRecord.cost`).
public struct CostEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Purpose: String, Codable, Sendable {
        /// A model reply the run went on with.
        case reply
        /// A reply that was paid for and then retried elsewhere (a lost tool call), or a retry request that failed.
        case retryAttempt
        /// A reply from the fallback model.
        case fallbackReply
        /// An empty or marker-only reply that the loop asked again.
        case nudgedReply
        /// A compaction's summary, and the cached attempt that fell back to a plain one.
        case summary, summaryAttempt
        case replay
        /// The parent's rating of the subagent runs it used, asked at the end of its run; a grader model's judgment.
        case rating, grading
        /// The skill router's question: which skill fits the user's new request (`SkillRouter`).
        case routing
        /// A chat's title, written by its own model (`ChatTitle`).
        case title
        /// A commit's message, written from its diff (`CommitMessage`).
        case commitMessage
        /// A question on the side (`SideQuestion`).
        case side
        /// A cross-vendor review of a change (`CodeReview`).
        case review
    }

    /// Whether the usage is the server's final word on the request.
    public enum Billing: String, Codable, Sendable {
        /// The stream finished and reported its usage.
        case reported
        /// The stream ended early (cut, cancelled, timed out, failed after it started): the usage is what had arrived;
        /// the provider's own records settle what was billed.
        case partial
        /// No usage arrived (an HTTP error before the stream); most likely nothing was billed.
        case none
    }

    public var id: UUID
    public var start: Date
    public var end: Date
    /// The agent run: the main run's id (the user message it answers) or the subagent run's id; nil for requests
    /// outside any run (a /compact between runs, a replay).
    public var run: UUID?
    /// `main`, or the subagent's name (`explore`, `general`, a custom agent).
    public var agent: String
    public var purpose: Purpose
    public var endpointID: UUID?
    public var api: WireAPI
    /// Where the request went.
    public var host: String?
    /// OpenRouter's provider.
    public var provider: String?
    public var requestedModel: String
    /// The model that answered, when it says another (an alias resolved, Claude's server-side fallback).
    public var servedModel: String?
    /// The server's ids for the request (Anthropic `request-id` and message id, OpenRouter generation id, Gemini
    /// `responseId`), for finding it in the provider's records.
    public var requestIDs: [String]?
    /// The reply's id: its message, when it became one, and its wire-log record, when the wire was kept.
    public var reply: UUID
    /// How the request ended (`StopReason`), and the finish reason the server gave.
    public var ended: StopReason
    public var finish: FinishReason?
    public var billing: Billing
    /// The usage as parsed, and as the server sent it.
    public var tokens: Usage?
    public var usageRaw: JSONValue?
    /// The list price; nil when the model has no known price (`unpricedReason` says why).
    public var listPrice: CostBreakdown?
    public var unpricedReason: String?
    /// What the account was charged, when the server says (OpenRouter); not used to compare models.
    public var charged: Double?
    public var timeToFirstToken: Double?
    public var duration: Double
    /// Output tokens per second after the first token.
    public var outputTokensPerSecond: Double?
    /// The provider's own record of the request, fetched afterwards (OpenRouter's generation record).
    public var reconciled: Reconciliation?
    /// What the input consisted of, in tokens, estimated from sizes and scaled to the reported prompt (a loop's replies
    /// only): `system`, `summary` (an earlier compaction's, in the system prompt), `tools` (definitions),
    /// `earlierHistory` (before this run), `userText`, `assistantTurns`, `toolOutputs`, `subagentReports`.
    public var promptMix: [String: Int]?
    /// What a loop's reply request sent, in short hashes (`PromptPrint`), so a later request can tell what changed.
    public var prompt: PromptPrint?
    /// Why this request read much less from the cache than the one before it left there (`CacheLedger.classify`).
    public var cacheMiss: CacheMiss?
}

extension CostEntry {
    /// Why a request on this Mac or the local network has no price.
    public static let localReason = "a model on this Mac or the local network (timed, not priced)"

    /// A request to a remote model with no known price (not a local one), which limits count at a default rate.
    public var isUnpricedRemote: Bool { spent == nil && listPrice == nil && unpricedReason != Self.localReason && tokens != nil }

    /// The entry for a finished request. `price` is the model's list price (`PriceList`, or OpenRouter's list); nil for a
    /// model without one, `local` for a model on this Mac or the local network.
    public static func make(reply m: ChatMessage, purpose: Purpose, run: UUID?, agent: String, client: ChatClient,
                            endpointID: UUID?, start: Date, price: PriceLookup) -> CostEntry {
        let meta = m.meta
        let usage = meta?.usage
        let duration = meta?.duration ?? Date().timeIntervalSince(start)
        let stop = meta?.stopReason ?? .completed
        let billing: Billing = usage == nil ? .none : (stop == .completed ? .reported : .partial)
        var tps: Double?
        if let u = usage, u.completionTokens > 0 {
            let generating = duration - (meta?.timeToFirstToken ?? 0)
            if generating > 0.05 { tps = Double(u.completionTokens) / generating }
        }
        var listPrice: CostBreakdown?
        var unpricedReason: String?
        switch price {
        case .known(let p, let source, let version):
            listPrice = usage.map { CostBreakdown($0, price: p, source: source, priceList: version) }
            if usage == nil { unpricedReason = "no usage reported" }
        case .local:
            unpricedReason = CostEntry.localReason
        case .unknown(let why):
            unpricedReason = why
        }
        return CostEntry(id: UUID(), start: start, end: start.addingTimeInterval(duration), run: run, agent: agent,
                         purpose: purpose, endpointID: endpointID ?? meta?.endpointID, api: client.api,
                         host: client.baseURL.host(), provider: meta?.provider, requestedModel: meta?.requestedModel ?? "",
                         servedModel: meta?.reportedModel.flatMap { $0 == meta?.requestedModel ? nil : $0 },
                         requestIDs: meta?.requestIDs, reply: m.id, ended: stop, finish: meta?.finishReason, billing: billing,
                         tokens: usage, usageRaw: meta?.usageRaw, listPrice: listPrice, unpricedReason: unpricedReason,
                         charged: client.api == .openai && usage?.costIsEstimate != true ? usage?.cost : nil,
                         timeToFirstToken: meta?.timeToFirstToken, duration: duration, outputTokensPerSecond: tps)
    }

    /// `promptMix` for a request: each message's estimated size by what it is, scaled so the parts add up to the prompt
    /// tokens the server reported.
    static func promptMix(_ messages: [ChatMessage], baseSystem: String, tools: [ToolDefinition], earlier: Set<UUID>,
                          promptTokens: Int?) -> [String: Int] {
        var bytes: [String: Int] = [:]
        if !tools.isEmpty { bytes["tools"] = TokenEstimator.bytes([], tools: tools) }
        for m in messages {
            let n = TokenEstimator.bytes([m])
            let kind: String
            switch m.role {
            case .system:
                let base = min(n, baseSystem.utf8.count + 12)
                bytes["system", default: 0] += base
                if n > base { bytes["summary", default: 0] += n - base }
                continue
            case _ where earlier.contains(m.id): kind = "earlierHistory"
            case .user: kind = m.subagentReport != nil ? "subagentReports" : "userText"
            case .assistant: kind = "assistantTurns"
            case .tool: kind = m.toolResult?.subagentRun != nil || m.toolResult?.toolName == "task" ? "subagentReports" : "toolOutputs"
            }
            bytes[kind, default: 0] += n
        }
        let total = bytes.values.reduce(0, +)
        guard total > 0 else { return [:] }
        let scale = promptTokens.map { Double($0) / Double(total) } ?? (1 / 3.3)
        return bytes.mapValues { Int((Double($0) * scale).rounded()) }
    }

    /// The model a reply's list price is for: the one that answered when the server names it (Claude's server-side
    /// fallback), else the one asked for.
    public static func pricedModel(_ m: ChatMessage) -> String {
        m.native?.model ?? m.meta?.requestedModel ?? ""
    }
}

/// A model's list price for a cost entry.
public enum PriceLookup: Sendable {
    case known(PriceList.Price, source: String, version: String)
    /// On this Mac or the local network: no dollars.
    case local
    case unknown(String)

    /// The list price of `model` on `client`'s server: `PriceList` for Claude and Gemini, OpenRouter's `/models` list for
    /// other remote servers, none for local ones.
    public static func lookup(client: ChatClient, model: String, on day: Date = Date()) async -> PriceLookup {
        switch client.api {
        case .anthropic, .gemini:
            guard let p = PriceList.price(api: client.api, model: model, on: day) else {
                return .unknown("\(model) isn't in the price list (\(PriceList.version))")
            }
            return .known(p, source: client.api == .anthropic ? "Anthropic list price" : "Gemini list price", version: PriceList.version)
        case .openai:
            guard client.isThirdParty else { return .local }
            if let (p, read) = await RemotePrices.shared.price(client: client, model: model) {
                return .known(p, source: "\(client.baseURL.host() ?? "server") /models", version: "read \(read)")
            }
            return .unknown("the server lists no price for \(model)")
        }
    }
}

/// List prices from servers that publish them with their models (OpenRouter's `/models`: dollars per token, as text),
/// read once per server and kept for six hours.
///
/// A listed price that moved more than `jump`× from the one last adopted for that model is held (the old one is used)
/// until a read at least `confirmAfter` later lists the new one again. On 2026-10-26 OpenRouter listed
/// deepseek-v4-flash-0731 at 10× its price for a few hours; 340 eval runs were recorded at it (COST_AUDIT.md F5).
/// Adopted prices are remembered between launches in `memory` (a JSON file), for remote servers only.
public actor RemotePrices {
    public static let shared = RemotePrices(memory: defaultMemory)
    public static let jump = 3.0
    public static let confirmAfter: TimeInterval = 6 * 3600

    private var lists: [String: (read: Date, prices: [String: PriceList.Price], held: [String: String])] = [:]
    private let memoryURL: URL?
    private var remembered: [String: Remembered]?

    /// The last adopted price of a model on a server, and a different one waiting to be confirmed.
    struct Remembered: Codable, Sendable, Hashable {
        var rates: PriceList.Rates
        var perSearch: Double?
        var perRequest: Double?
        var adopted: Date
        var pending: PriceList.Rates?
        var pendingSince: Date?
    }

    /// `~/Library/Caches/kurtkode/remote-prices.json`.
    public static var defaultMemory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "kurtkode/remote-prices.json")
    }

    public init(memory: URL? = nil) { memoryURL = memory }

    /// The price and the time the list was read (with a note when the listed price is being held).
    public func price(client: ChatClient, model: String) async -> (PriceList.Price, String)? {
        let key = client.baseURL.absoluteString
        func answer(_ l: (read: Date, prices: [String: PriceList.Price], held: [String: String])) -> (PriceList.Price, String)? {
            l.prices[model].map { ($0, ISO8601DateFormatter().string(from: l.read) + (l.held[model].map { "; " + $0 } ?? "")) }
        }
        if let l = lists[key], Date().timeIntervalSince(l.read) < 6 * 3600 { return answer(l) }
        guard let data = await client.modelsList() else { return nil }
        let now = Date()
        var prices = Self.parse(data), held: [String: String] = [:]
        if client.isThirdParty {
            var memory = loadMemory()
            (prices, held) = Self.steady(prices, remembered: &memory, server: key, now: now)
            saveMemory(memory)
        }
        lists[key] = (now, prices, held)
        return answer(lists[key]!)
    }

    /// `fresh` with every price that jumped more than `jump`× from the remembered one replaced by the remembered one,
    /// unless the same new price was first seen at least `confirmAfter` ago; updates `remembered`. `held`: a note per
    /// model whose listed price was not used.
    static func steady(_ fresh: [String: PriceList.Price], remembered: inout [String: Remembered], server: String,
                       now: Date) -> (prices: [String: PriceList.Price], held: [String: String]) {
        func jumped(_ a: PriceList.Rates, _ b: PriceList.Rates) -> Bool {
            func far(_ x: Double, _ y: Double) -> Bool { x > 0 && y > 0 && (y / x > jump || x / y > jump) }
            return far(a.input, b.input) || far(a.output, b.output)
        }
        func same(_ a: PriceList.Rates, _ b: PriceList.Rates) -> Bool {
            func near(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= 0.01 * max(abs(x), abs(y)) }
            return near(a.input, b.input) && near(a.output, b.output)
        }
        var out = fresh, held: [String: String] = [:]
        for (model, p) in fresh {
            let key = server + "|" + model
            let adopt = Remembered(rates: p.standard, perSearch: p.perSearch, perRequest: p.perRequest, adopted: now)
            guard var r = remembered[key], jumped(r.rates, p.standard) else { remembered[key] = adopt; continue }
            if let pending = r.pending, same(pending, p.standard), let since = r.pendingSince, now.timeIntervalSince(since) >= confirmAfter {
                remembered[key] = adopt
                continue
            }
            if r.pending.map({ !same($0, p.standard) }) ?? true { r.pending = p.standard; r.pendingSince = now }
            remembered[key] = r
            out[model] = PriceList.Price(standard: r.rates, longAbove: nil, long: nil, perSearch: r.perSearch, perRequest: r.perRequest)
            held[model] = String(format: "held: listed at $%.4g/$%.4g per M, more than %.0f× the last price; used until a "
                                 + "read %.0f h after the first one confirms it", p.input, p.output, jump, confirmAfter / 3600)
        }
        return (out, held)
    }

    private func loadMemory() -> [String: Remembered] {
        if let remembered { return remembered }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let loaded = memoryURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? dec.decode([String: Remembered].self, from: $0) } ?? [:]
        remembered = loaded
        return loaded
    }

    private func saveMemory(_ memory: [String: Remembered]) {
        remembered = memory
        guard let url = memoryURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(memory).write(to: url, options: .atomic)
    }

    /// `{"data": [{"id": …, "pricing": {"prompt": "0.000003", "completion": …, "input_cache_read": …,
    /// "input_cache_write": …, "web_search": …, "request": …}}]}` → prices per million tokens.
    static func parse(_ data: Data) -> [String: PriceList.Price] {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let list)? = o["data"] else { return [:] }
        var out: [String: PriceList.Price] = [:]
        for case .object(let m) in list {
            guard let id = NativeWire.string(m["id"]), let p = price(m) else { continue }
            out[id] = p
        }
        return out
    }

    /// One model's `pricing` (dollars per token, as text) as prices per million tokens; nil when it has none.
    static func price(_ m: [String: JSONValue]) -> PriceList.Price? {
        func number(_ v: JSONValue?) -> Double? {
            switch v { case .string(let s)?: Double(s); case .number(let n)?: n; default: nil }
        }
        // Router models (openrouter/auto) list -1: no price of their own (the model that answers has one).
        guard case .object(let p)? = m["pricing"], let input = number(p["prompt"]), let output = number(p["completion"]),
              input >= 0, output >= 0 else { return nil }
        let read = number(p["input_cache_read"]).flatMap { $0 >= 0 ? $0 : nil } ?? input
        let write = number(p["input_cache_write"]).flatMap { $0 >= 0 ? $0 : nil } ?? input
        // The listing has one write price, the five-minute cache's; Claude's hour cache is written at 2× the input
        // price (Anthropic's rule, which OpenRouter passes on).
        let claude = (m["id"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "").contains("anthropic/")
        let rates = PriceList.Rates(input: input * 1e6, output: output * 1e6, cacheRead: read * 1e6,
                                    cacheWrite5m: write * 1e6, cacheWrite1h: (claude ? input * 2 : write) * 1e6)
        let search = number(p["web_search"]).flatMap { $0 > 0 ? $0 : nil }
        let request = number(p["request"]).flatMap { $0 > 0 ? $0 : nil }
        return PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: search, perRequest: request)
    }
}

/// Which agent run a loop's requests belong to (`AgentConfig.costScope`).
public struct CostScope: Sendable, Hashable {
    /// The run's id (a main run: one send; a subagent run: its child session's id); nil outside any run.
    public var run: UUID?
    /// `main`, or the subagent's name.
    public var agent: String
    /// The user message a main run answers.
    public var userMessage: UUID?
    /// A subagent run's parent run and `task` call.
    public var parentRun: UUID?
    public var taskCall: String?
    /// What the agent is (`AgentRunRecord.definitionHash`); nil: the main agent's, from its prompt style and tools.
    public var definitionHash: String?
    public var promptStyle: String?
    /// What the parent said about a subagent's task (its run record keeps it).
    public var card: TaskCard?
    /// A second attempt at a subagent task: the run that failed.
    public var attemptOf: UUID?

    public init(run: UUID?, agent: String, userMessage: UUID? = nil, parentRun: UUID? = nil, taskCall: String? = nil,
                definitionHash: String? = nil, promptStyle: String? = nil, card: TaskCard? = nil, attemptOf: UUID? = nil) {
        self.card = card
        self.attemptOf = attemptOf
        self.run = run
        self.agent = agent
        self.userMessage = userMessage
        self.parentRun = parentRun
        self.taskCall = taskCall
        self.definitionHash = definitionHash
        self.promptStyle = promptStyle
    }
}

/// Makes cost entries for requests made outside the loop's own turns (summaries), and hands them on.
public struct CostSink: Sendable {
    public var scope: CostScope
    public var endpointID: UUID?
    public var emit: @Sendable (CostEntry) async -> Void

    public init(scope: CostScope, endpointID: UUID?, emit: @escaping @Sendable (CostEntry) async -> Void) {
        self.scope = scope
        self.endpointID = endpointID
        self.emit = emit
    }

    @discardableResult
    public func record(_ reply: ChatMessage, purpose: CostEntry.Purpose, client: ChatClient, start: Date) async -> CostEntry {
        let price = await PriceLookup.lookup(client: client, model: CostEntry.pricedModel(reply))
        let entry = CostEntry.make(reply: reply, purpose: purpose, run: scope.run, agent: scope.agent, client: client,
                                   endpointID: endpointID, start: start, price: price)
        await emit(entry)
        return entry
    }
}

/// What a provider's own record says about a request, fetched after it (OpenRouter's `/generation`).
public struct Reconciliation: Codable, Sendable, Hashable {
    public var at: Date
    public var source: String
    /// What the account was charged (`total_cost`).
    public var charged: Double?
    /// Token counts by the model's own tokenizer, as the provider billed them.
    public var nativePromptTokens: Int?
    public var nativeCompletionTokens: Int?
    public var nativeReasoningTokens: Int?
    public var nativeCachedTokens: Int?
    public var provider: String?
    /// The list price of the native counts at the entry's rates (compare with `CostEntry.listPrice`, from the streamed counts).
    public var nativeListPrice: CostBreakdown?
    /// The record as sent.
    public var raw: JSONValue
}

extension CostEntry {
    /// An OpenRouter generation id (`gen-…`) to look up afterwards, when the entry hasn't been checked yet.
    public var generationID: String? {
        reconciled == nil ? requestIDs?.first(where: { $0.hasPrefix("gen-") }) : nil
    }

    /// The entry with the provider's record of it.
    public func reconciled(with d: [String: JSONValue], price: PriceLookup) -> CostEntry {
        func int(_ k: String) -> Int? { NativeWire.int(d[k]) }
        var r = Reconciliation(at: Date(), source: "\(host ?? "server") /generation", raw: .object(d))
        if case .number(let c)? = d["total_cost"] { r.charged = c }
        r.nativePromptTokens = int("native_tokens_prompt")
        r.nativeCompletionTokens = int("native_tokens_completion")
        r.nativeReasoningTokens = int("native_tokens_reasoning")
        r.nativeCachedTokens = int("native_tokens_cached")
        r.provider = NativeWire.string(d["provider_name"])
        if case .known(let p, let source, let version) = price, let prompt = r.nativePromptTokens, let completion = r.nativeCompletionTokens {
            let u = Usage(promptTokens: prompt, completionTokens: completion, reasoningTokens: r.nativeReasoningTokens ?? 0,
                          cacheReadTokens: r.nativeCachedTokens, cacheWriteTokens: tokens?.cacheWriteTokens)
            r.nativeListPrice = CostBreakdown(u, price: p, source: source, priceList: version)
        }
        var e = self
        e.reconciled = r
        if let c = r.charged { e.charged = c }
        return e
    }

    /// Looks up each entry's generation record on its server (the client for its host), waiting for records that lag;
    /// returns the entries that were found, updated. Gives up on an entry after about ten seconds.
    public static func reconcile(_ entries: [CostEntry], clients: [ChatClient], delays: [Double] = [1, 3, 6]) async -> [CostEntry] {
        await withTaskGroup(of: CostEntry?.self) { group in
            for e in entries {
                guard let id = e.generationID, let client = clients.first(where: { $0.baseURL.host() == e.host }) else { continue }
                group.addTask {
                    for wait in [0] + delays {
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                        if Task.isCancelled { return nil }
                        if let d = await client.generationStats(id: id) {
                            let price = await PriceLookup.lookup(client: client, model: e.requestedModel)
                            return e.reconciled(with: d, price: price)
                        }
                    }
                    return nil
                }
            }
            var out: [CostEntry] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
    }
}

/// Checks recorded entries against their providers' records after the fact (OpenRouter's generation records, which
/// lag the reply by minutes): `kurtkode cost reconcile`, and the app and CLI at launch.
public enum CostReconciler {
    /// Looks up entries recorded since `since` that are at least `minAge` old and not checked yet (at most `limit`), and
    /// records what their providers say. `client` gives the client (with its key) for an endpoint; nil skips its entries.
    /// `report` hears one line per entry. Returns how many were checked and how many were waiting.
    @discardableResult
    public static func run(store: SessionStore, since: Date, minAge: TimeInterval = 60, limit: Int = 50,
                           client: @Sendable (UUID) async -> ChatClient?,
                           report: (@Sendable (String) -> Void)? = nil) async -> (checked: Int, pending: Int) {
        let now = Date()
        guard let all = try? await store.costEntries() else { return (0, 0) }
        // Newest first, so entries that can never be settled (an endpoint since deleted, a record that never appears)
        // don't hold the newer ones back; only lookups count toward the limit.
        let pending = all.filter { $0.entry.start >= since && $0.entry.end <= now.addingTimeInterval(-minAge) && $0.entry.generationID != nil }
            .sorted { $0.entry.start > $1.entry.start }
        var clients: [UUID: ChatClient?] = [:]
        var checked = 0, looked = 0
        for (session, e) in pending {
            guard looked < limit else { break }
            guard let id = e.endpointID, let gen = e.generationID else { continue }
            if clients[id] == nil { clients[id] = .some(await client(id)) }
            guard let c = clients[id] ?? nil else { continue }
            looked += 1
            let (record, status, body) = await c.generationLookup(id: gen)
            guard let record else {
                report?("\(gen): not found (HTTP \(status.map(String.init) ?? "–")): \(body.replacingOccurrences(of: "\n", with: " "))")
                continue
            }
            let checkedEntry = e.reconciled(with: record, price: await PriceLookup.lookup(client: c, model: e.requestedModel))
            // A replay's cost goes back into its replay record; the session's own requests get a record in its file.
            if e.purpose == .replay {
                guard await store.updateReplayCost(checkedEntry, session: session) else { continue }
            } else {
                guard (try? await store.append(.cost(checkedEntry), to: session.id)) != nil else { continue }
            }
            checked += 1
            report?(String(format: "%@: charged $%.6f (list $%.6f)", gen, checkedEntry.charged ?? 0, checkedEntry.listPrice?.total ?? 0))
        }
        return (checked, pending.count)
    }
}

extension CostEntry {
    /// What the request cost, as best known: the provider's charge where it said (OpenRouter), else the list price; nil
    /// for an unpriced request. Spending shown and limits use this; comparing models uses `listPrice`.
    public var spent: Double? { charged ?? listPrice?.total }

    /// Who served the request: OpenRouter's provider, else the API's company, else the server's host.
    public var servedBy: String {
        if let p = reconciled?.provider ?? provider { return p }
        switch api {
        case .anthropic: return "Anthropic"
        case .gemini: return "Google"
        case .openai: return host ?? "?"
        }
    }

    /// "$0.00123 (charged)", "≈$0.00123 (list price)", or nil for an unpriced request.
    public func spentText(digits: Int = 5) -> String? {
        if let c = charged { return String(format: "$%.\(digits)f", c) + " (charged)" }
        return listPrice.map { String(format: "≈$%.\(digits)f", $0.total) + " (list price)" }
    }
}

/// Totals over cost entries, for the displays: what was spent (charge where known, else list price), list price by
/// component, and the split by purpose and provider.
public struct CostSummary: Sendable, Hashable {
    public var requests = 0
    public var spent = 0.0
    /// Whether any of `spent` is a list-price estimate (no charge reported).
    public var estimated = false
    public var listPrice = ComponentCosts()
    public var charged = 0.0
    public var chargedRequests = 0
    public var reconciledRequests = 0
    public var unpricedRequests = 0
    public var byPurpose: [CostEntry.Purpose: Double] = [:]
    /// By OpenRouter's provider, or the server's host.
    public var byProvider: [String: Double] = [:]

    public init(_ entries: [CostEntry] = []) {
        for e in entries { add(e) }
    }

    public mutating func add(_ e: CostEntry) {
        requests += 1
        if let b = e.listPrice { listPrice.add(b) }
        if let c = e.charged { charged += c; chargedRequests += 1 }
        if e.reconciled != nil { reconciledRequests += 1 }
        guard let s = e.spent else { unpricedRequests += 1; return }
        spent += s
        if e.charged == nil { estimated = true }
        byPurpose[e.purpose, default: 0] += s
        byProvider[e.servedBy, default: 0] += s
    }

    public static func + (a: CostSummary, b: CostSummary) -> CostSummary {
        var out = a
        out.requests += b.requests
        out.spent += b.spent
        out.estimated = a.estimated || b.estimated
        out.listPrice.uncachedInput += b.listPrice.uncachedInput
        out.listPrice.cacheRead += b.listPrice.cacheRead
        out.listPrice.cacheWrite5m += b.listPrice.cacheWrite5m
        out.listPrice.cacheWrite1h += b.listPrice.cacheWrite1h
        out.listPrice.output += b.listPrice.output
        out.listPrice.reasoning += b.listPrice.reasoning
        out.listPrice.searches += b.listPrice.searches
        out.listPrice.requests += b.listPrice.requests
        out.listPrice.total += b.listPrice.total
        out.charged += b.charged
        out.chargedRequests += b.chargedRequests
        out.reconciledRequests += b.reconciledRequests
        out.unpricedRequests += b.unpricedRequests
        for (k, v) in b.byPurpose { out.byPurpose[k, default: 0] += v }
        for (k, v) in b.byProvider { out.byProvider[k, default: 0] += v }
        return out
    }

    /// Nothing priced: local models only, or nothing yet.
    public var isEmpty: Bool { spent == 0 && requests == unpricedRequests }

    /// "≈$0.0283" (any estimate) or "$0.0283" (all charged).
    public func spentText(digits: Int = 4) -> String { (estimated ? "≈" : "") + String(format: "$%.\(digits)f", spent) }
}
