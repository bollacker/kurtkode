import Foundation

/// The model configurations kurtkode may choose among on its own (GAP_ANALYSIS.md A1): for subagents, retries, judging,
/// summaries and reviews. A configuration is an endpoint, a model, a reasoning setting and provider pins, so the same
/// model with reasoning off is a different entry. Saved as `pool.json` beside the profiles; until the user edits it,
/// the shipped pool holds the cost-floor study's finalists (COST_FLOOR_RESULTS.md).
public struct PoolEntry: Codable, Sendable, Hashable, Identifiable {
    /// How capable and how costly, as a routing prior. Ordered: a retry never goes to a lower tier.
    public enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
        case local, cheap, standard, frontier
        public static func < (a: Tier, b: Tier) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    }
    public enum Role: String, Codable, Sendable, CaseIterable { case main, subagent, judge, summarizer, reviewer }

    /// A saved endpoint's id, or a kind of endpoint for whichever one the user has: "openrouter", "anthropic",
    /// "gemini", or "claude" (Anthropic's API if there's one, else OpenRouter; the model is then an alias: haiku,
    /// sonnet, opus).
    public var endpoint: String
    public var model: String
    /// "none" or an effort level (`ReasoningSetting`); nil: the model's default.
    public var reasoning: String?
    public var providers: ProviderRouting?
    public var tier: Tier
    public var roles: Set<Role>
    public var enabled: Bool
    /// Its place on the retry ladder (lower first); nil: not on it.
    public var ladder: Int?
    /// Why it's here ("cost-floor finalist: 98%, $0.00025 a run").
    public var note: String?

    public var id: String { "\(endpoint)|\(model)|\(reasoning ?? "")" }

    /// Hand-written entries may leave out `enabled` (on), `roles` (subagent) and the optional fields; the tier also
    /// takes the task card's name for the top tier ("strong").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        model = try c.decode(String.self, forKey: .model)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
        providers = try c.decodeIfPresent(ProviderRouting.self, forKey: .providers)
        let t = try c.decode(String.self, forKey: .tier).lowercased()
        guard let tier = t == "strong" ? .frontier : Tier(rawValue: t) else {
            throw DecodingError.dataCorruptedError(forKey: .tier, in: c, debugDescription: "tier \"\(t)\": local, cheap, standard or frontier")
        }
        self.tier = tier
        roles = try c.decodeIfPresent(Set<Role>.self, forKey: .roles) ?? [.subagent]
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        ladder = try c.decodeIfPresent(Int.self, forKey: .ladder)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public init(endpoint: String, model: String, reasoning: String? = nil, providers: ProviderRouting? = nil, tier: Tier,
                roles: Set<Role>, enabled: Bool = true, ladder: Int? = nil, note: String? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.reasoning = reasoning
        self.providers = providers
        self.tier = tier
        self.roles = roles
        self.enabled = enabled
        self.ladder = ladder
        self.note = note
    }

    /// "ling-3.0-flash", "deepseek-v4-flash-0731 (reasoning off)".
    public var label: String {
        let name = endpoint.lowercased() == "claude" ? "claude-" + model : model.split(separator: "/").last.map(String.init) ?? model
        return reasoning.map { "\(name) (reasoning \(ReasoningSetting.label($0)))" } ?? name
    }
}

/// An entry made concrete: the endpoint it runs on here and the model id that endpoint takes.
public struct ResolvedPoolEntry: Sendable, Hashable {
    public var entry: PoolEntry
    public var endpoint: Endpoint
    public var model: String
}

public struct ModelPool: Codable, Sendable, Hashable {
    public var entries: [PoolEntry]

    public init(entries: [PoolEntry]) { self.entries = entries }

    /// The cost-floor finalists (COST_FLOOR_RESULTS.md, re-run after Phase 1): ling-3.0-flash first, then Claude Haiku
    /// 5.5, which also judges; deepseek-v4-flash-0731 with reasoning off reviews only (on real-sized edits it passed
    /// less often than Haiku at 2–4½× its cost per success; COST_AUDIT.md section 12); Sonnet 5.5 as the frontier
    /// (REAL_TASKS_PLAN.md: escalating Haiku's failed real-sized runs, Sonnet fixed 9 of 9 at $0.72 each, Opus 7 of 8 at
    /// $1.57).
    /// The OpenRouter entries keep to providers that don't keep prompts, as the study ran them (`--no-train`).
    public static let shipped = ModelPool(entries: [
        PoolEntry(endpoint: "openrouter", model: "inclusionai/ling-3.0-flash", providers: ProviderRouting(dataCollection: "deny"),
                  tier: .cheap, roles: [.subagent, .main], ladder: 0,
                  note: "cost-floor finalist: 98% (96–99%) of 479 runs, $0.00025 a run; real-sized edits: 28% of 123 runs in six repositories (cost audit section 12), so code-changing tasks go to the standard tier"),
        PoolEntry(endpoint: "openrouter", model: "deepseek/deepseek-v4-flash-0731", reasoning: "none",
                  providers: ProviderRouting(dataCollection: "deny"), tier: .cheap, roles: [.reviewer],
                  note: "reviewer: caught 51 of 55 bad changes, no false alarms in 24, $0.0001 a review; not a subagent: real-sized edits 63% of 120 runs, below Haiku at 2–4½× its cost per success (cost audit section 12); cost-floor finalist: 100% (99–100%) of 480 runs"),
        PoolEntry(endpoint: "claude", model: "haiku", tier: .standard, roles: [.subagent, .judge, .reviewer, .summarizer, .main], ladder: 1,
                  note: "cost-floor finalist: 99% (98–100%) of 480 runs, $0.0014 a run; real-sized edits: 85% of 125 runs in six repositories, $0.03–0.06 a success (cost audit section 12); judge kappa 0.67; reviewer: caught 56 of 56 bad changes, 2 cautions in 24 good ones"),
        PoolEntry(endpoint: "claude", model: "sonnet", tier: .frontier, roles: [.main, .reviewer],
                  note: "escalation target: fixed 14 of 16 of Haiku's failed real-sized runs, $0.72 each on the user's repositories (Opus: 7 of 8, $1.57)"),
    ])

    // MARK: Saving

    /// `pool.json`, or the shipped pool when there's none. A file that can't be read gives an empty pool, so nothing is
    /// routed automatically until it's fixed (the shipped pool would bring back entries the user removed); `problem`
    /// says why.
    public static func load(_ url: URL) -> ModelPool { loadChecked(url).pool }

    public static func loadChecked(_ url: URL) -> (pool: ModelPool, problem: String?) {
        guard let data = try? Data(contentsOf: url) else { return (.shipped, nil) }
        do { return (try JSONDecoder().decode(ModelPool.self, from: data), nil) }
        catch {
            let why: String
            switch error {
            case DecodingError.dataCorrupted(let c): why = c.debugDescription
            case DecodingError.keyNotFound(let k, let c): why = "missing \"\(k.stringValue)\"" + (c.codingPath.isEmpty ? "" : " in " + c.codingPath.map(\.stringValue).joined(separator: "."))
            case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
                why = "wrong value at " + c.codingPath.map(\.stringValue).joined(separator: ".")
            default: why = error.localizedDescription
            }
            return (ModelPool(entries: []), "\(url.lastPathComponent) can't be read (\(why)); no model is chosen automatically until it's fixed")
        }
    }

    public func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    // MARK: Choosing

    /// Where an entry runs here, or nil when no endpoint serves it.
    public static func resolve(_ e: PoolEntry, endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        func openRouter() -> Endpoint? { endpoints.first { $0.kind == .openai && ($0.baseURL.host()?.hasSuffix("openrouter.ai") ?? false) } }
        switch e.endpoint.lowercased() {
        case "openrouter": return openRouter().map { ResolvedPoolEntry(entry: e, endpoint: $0, model: e.model) }
        case "anthropic": return endpoints.first { $0.kind == .anthropic }.map { ResolvedPoolEntry(entry: e, endpoint: $0, model: e.model) }
        case "gemini": return endpoints.first { $0.kind == .gemini }.map { ResolvedPoolEntry(entry: e, endpoint: $0, model: e.model) }
        case "claude":
            guard let (endpoint, model) = ModelAlias.resolve(e.model, endpoints: endpoints) else { return nil }
            return ResolvedPoolEntry(entry: e, endpoint: endpoint, model: model)
        default:
            guard let id = UUID(uuidString: e.endpoint), let endpoint = endpoints.first(where: { $0.id == id }) else { return nil }
            return ResolvedPoolEntry(entry: e, endpoint: endpoint, model: e.model)
        }
    }

    /// Enabled entries with `role` that run here, in pool order.
    public func available(_ role: PoolEntry.Role, endpoints: [Endpoint]) -> [ResolvedPoolEntry] {
        entries.filter { $0.enabled && $0.roles.contains(role) }.compactMap { Self.resolve($0, endpoints: endpoints) }
    }

    /// The first available entry with `role` at `tier` or above (the lowest such tier first), or nil.
    public func pick(_ role: PoolEntry.Role, atLeast tier: PoolEntry.Tier, endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        available(role, endpoints: endpoints).filter { $0.entry.tier >= tier }
            .min { ($0.entry.tier, $0.entry.ladder ?? .max) < ($1.entry.tier, $1.entry.ladder ?? .max) }
    }

    /// The retry ladder's available subagent entries, lowest rung first.
    public func ladder(endpoints: [Endpoint]) -> [ResolvedPoolEntry] {
        available(.subagent, endpoints: endpoints).filter { $0.entry.ladder != nil }.sorted { $0.entry.ladder! < $1.entry.ladder! }
    }

    /// The next rung after a run on `model` at `endpointID` (with `reasoning`): the first ladder entry above it, never at
    /// a lower tier. A configuration that isn't a rung goes to the first rung of a higher tier than its own (`tier`, else
    /// the tier of a pool entry for the same model), never to the same model; with neither known, nowhere (a model the
    /// pool doesn't know could be stronger than every rung). Nil when there's nowhere higher to go.
    public func next(after endpointID: UUID?, model: String, reasoning: String?, tier: PoolEntry.Tier? = nil,
                     endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        let rungs = ladder(endpoints: endpoints)
        // A rung without a reasoning setting of its own matches the model whatever its profile set.
        if let i = rungs.firstIndex(where: { $0.endpoint.id == endpointID && $0.model == model
                                             && ($0.entry.reasoning == nil || $0.entry.reasoning == reasoning) }) {
            return rungs[(i + 1)...].first { $0.entry.tier >= rungs[i].entry.tier }
        }
        // Not a rung: only from a known tier, and only upward.
        guard let own = tier ?? entry(endpointID: endpointID, model: model, endpoints: endpoints)?.entry.tier else { return nil }
        return rungs.first { r in r.entry.tier > own && !(r.endpoint.id == endpointID && r.model == model) }
    }

    /// The pool entry for a configuration, if it's in the pool (for its tier).
    public func entry(endpointID: UUID?, model: String, endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        entries.compactMap { Self.resolve($0, endpoints: endpoints) }.first { $0.endpoint.id == endpointID && $0.model == model }
    }
}

/// The cost of a typical small task at a price: the cost-floor bank's average run after Phase 1 (1,439 runs of three
/// cheap models): about 20,000 prompt tokens, 13,000 of them read from the cache, 900 output tokens, and 8 requests
/// (for per-request fees). A first
/// approximation for comparing models in menus, not a forecast: harder tasks cost many times more, and models differ
/// in how many tokens they use.
public enum TypicalTask {
    public static let promptTokens = 20_000
    public static let cachedTokens = 13_000
    public static let outputTokens = 900
    public static let requests = 8

    public static func cost(_ price: PriceList.Price) -> Double {
        let r = price.standard
        return (Double(promptTokens - cachedTokens) * r.input + Double(cachedTokens) * r.cacheRead
                + Double(outputTokens) * r.output) / 1e6 + (price.perRequest ?? 0) * Double(requests)
    }

    /// "$0.07 / $0.28 per M tokens · ≈$0.0011 a task".
    public static func money(_ v: Double) -> String {
        v >= 1 ? String(format: "$%.2f", v) : v >= 0.01 ? String(format: "$%.3f", v) : String(format: "$%.4f", v)
    }

    public static func label(_ price: PriceList.Price) -> String {
        let r = price.standard
        func rate(_ v: Double) -> String { v == 0 ? "free" : v < 1 ? String(format: "$%.2f", v) : String(format: "$%.1f", v) }
        let task = cost(price)
        return "\(rate(r.input)) / \(rate(r.output)) per M tokens · " + (task == 0 ? "free" : "≈" + money(task) + " a task")
    }
}

/// How kurtkode picks subagent models from the pool on its own (GAP_ANALYSIS.md A2). Only for a session whose main
/// model is a hosted API (`Endpoint.isCloudAPI`): a local or LAN session's subagents stay where it is, so nothing leaves
/// it that didn't before.
public enum SubagentRouting {
    /// The tier a task asks for: its card's `tier` (cheap, standard, strong = frontier), else standard for an
    /// important task or one that changes code, else cheap. The cheap tier's bank results don't carry over to changing
    /// code in a real repository: on ten real-sized tasks ling-3.0-flash passed 10% and Haiku 5.5 83%, and Haiku was
    /// also the cheaper success ($0.057 against $0.128; COST_AUDIT.md section 5, P2 and P2b). It held over 47 tasks in
    /// six repositories and three languages (Haiku 85%, ling 28%; section 12). Lookups stay cheap.
    public static func tier(for card: TaskCard) -> PoolEntry.Tier {
        switch card.tier {
        case .cheap?: .cheap
        case .standard?: .standard
        case .strong?: .frontier
        case nil: card.importance == .high || card.kind.map(changesCode) == true ? .standard : .cheap
        }
    }

    /// Kinds of task whose work is a change to the code: edit, refactor, fix, write-tests.
    public static let codeChangingKinds: Set<TaskCard.Kind> = [.edit, .refactor, .fix, .writeTests]
    public static func changesCode(_ kind: TaskCard.Kind) -> Bool { codeChangingKinds.contains(kind) }

    /// The pool entry for a subagent nothing else chose a model for, or nil (the main model): a local main model, no
    /// entry at the tier asked for, or one that is the main model itself.
    public static func automatic(card: TaskCard, main: Endpoint, mainModel: String, pool: ModelPool,
                                 endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        guard main.isCloudAPI, let e = pool.pick(.subagent, atLeast: tier(for: card), endpoints: endpoints),
              !(e.endpoint.id == main.id && e.model == mainModel && e.entry.reasoning == nil) else { return nil }
        return e
    }

    /// Where a failed run goes next (D3), or nil: a run whose model wasn't the pool's choice (`routed`: no `model:` in
    /// its definition, and Settings' subagent model on automatic), a local main model, or nothing higher on the ladder.
    public static func retry(after endpointID: UUID?, model: String, reasoning: String?, routed: Bool, main: Endpoint,
                             pool: ModelPool, endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        guard routed, main.isCloudAPI else { return nil }
        return pool.next(after: endpointID, model: model, reasoning: reasoning, endpoints: endpoints)
    }

    /// Whether a subagent's model is the pool's to choose: its definition names none and Settings leave it automatic.
    public static func routed(_ agent: AgentDefinition, settings: RunSettings) -> Bool {
        agent.model == nil && settings.subagentModel == nil && settings.subagentAutomatic
    }

    /// The judge for an important task's run when none is chosen, for a hosted main model: the pool's first judge that
    /// isn't the run's own model, or none. A run on the only judge (Haiku, in the shipped pool: important and
    /// code-changing tasks run there) gets no grade rather than a silent fallback: the strongest reviewer (Opus) cost
    /// about 14× the run it graded, and the cheap reviewer's judging isn't measured (COST_AUDIT.md F3, decision 3).
    /// Such a run still gets the cross-vendor review of its change (A6). A grader named in Settings is used as named.
    public static func grader(main: Endpoint, runEndpointID: UUID?, runModel: String, pool: ModelPool,
                              endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        guard main.isCloudAPI else { return nil }
        return pool.available(.judge, endpoints: endpoints).first { !($0.endpoint.id == runEndpointID && $0.model == runModel) }
    }
}
