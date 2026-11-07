import Foundation

/// The cheap-first cascade's advisory step (GAP_ANALYSIS.md A4; decision 2: a one-click card, nothing automatic yet):
/// when a run on a model below the pool's frontier looks wrong, kurtkode offers to hand the request to the next tier's
/// main model (decision 3: one tier up, not straight to the top), with what it would cost. The run's work is kept: the new
/// model gets the conversation, the reasons and the run's diff. Offers and what the user did with them are recorded, to
/// measure the triggers' precision in real sessions before anything is automatic.
public struct EscalationOffer: Codable, Sendable, Hashable, Identifiable {
    /// `ignored`: the user moved on (a new message, another model, a newer offer) without answering. `reviewed`: the user
    /// had the change reviewed on the offer's model first (decision 4) and has not escalated (yet).
    public enum Decision: String, Codable, Sendable { case offered, accepted, declined, ignored, reviewed }

    public var id = UUID()
    /// The main run that looked wrong (nil for `/escalate` before any run).
    public var run: UUID?
    /// Why, in words ("it stopped at the step limit", "you marked the reply wrong").
    public var reasons: [String]
    /// "signals" (grounded, free), "review" (A6's reviewer), "user" (👎, /bad), "asked" (/escalate).
    public var source: String
    public var fromModel: String
    public var fromEndpointID: UUID?
    public var toModel: String
    public var toEndpointID: UUID
    public var toReasoning: String?
    /// The pool entry's provider pins (OpenRouter's `data_collection: deny`), applied to the session when it's taken.
    public var toProviders: ProviderRouting?
    /// "claude-haiku", "ling-3.0-flash".
    public var toLabel: String
    /// The switch (the conversation read once at the new model's input price) plus a typical task there; nil: unpriced.
    public var estimate: Double?
    /// Decision 4 (COST_AUDIT.md, P3): for a run that changed files, the card's first action is one read-only review of
    /// the change on the offer's model, a fraction of a re-run's cost; the re-run is the second. Nil (older records) or
    /// false: the re-run only.
    public var reviewable: Bool?
    /// That review's estimated cost on the offer's model (`Escalation.reviewEstimate`); nil: unpriced.
    public var reviewEstimate: Double?
    public var decision: Decision = .offered
    public var at = Date()

    /// "Escalate to claude-haiku for ≈$0.004".
    public var buttonTitle: String {
        "Escalate to \(toLabel)" + (estimate.map { " for ≈" + TypicalTask.money($0) } ?? "")
    }

    /// "Review on claude-sonnet for ≈$0.02".
    public var reviewTitle: String {
        "Review on \(toLabel)" + (reviewEstimate.map { " for ≈" + TypicalTask.money($0) } ?? "")
    }

    public var canReview: Bool { reviewable == true }

    public var reasonText: String { reasons.joined(separator: "; ") }
}

public enum Escalation {
    /// Grounded, free reasons from how a main run ended, the ones precise enough on the stored runs (A4 "measured"):
    /// it stopped early (step limit, a stopped turn, a cut-off reply), its last test/build check failed after it changed
    /// files (a run asked only to run the tests and report ends on a failing check and is fine), it left todos
    /// unfinished. A cost limit, a stop by the user or a denial isn't the model's failure. When kurtkode ran the
    /// project's own tests after the run (11b), their result replaces the model's last check: it is the stronger signal
    /// (P2b: right on 12 of 12, against 77% precision). A subagent task's check that fails when run again is a reason too.
    public static func reasons(_ run: AgentRunRecord) -> [String] {
        var r: [String] = []
        // A stopped turn counts only when the model looped; a server error or the wall clock isn't its failure.
        switch run.outcome.stop {
        case "stepLimit": r.append("it stopped at the step limit")
        case "truncated": r.append("its reply was cut off at the output limit")
        case let s where s.hasPrefix("turnStopped") && s.hasSuffix("repetition)"): r.append("it got stuck repeating itself")
        default: break
        }
        if let s = run.signals {
            if let suite = s.suite {
                if suite.failed {
                    r.append(suite.timedOut == true ? "the project's tests timed out after the run: \(suite.command)"
                             : "the project's tests fail after the run (exit \(suite.exitCode.map(String.init) ?? "?")): \(suite.command)")
                }
            } else if s.lastCheckFailed, let c = s.lastCheck, run.snapshots?.changed ?? !run.outcome.filesChanged.isEmpty {
                r.append(c.timedOut == true ? "its last check timed out: \(c.command)" : "its last check failed (exit \(c.exitCode.map(String.init) ?? "?")): \(c.command)")
            }
            for c in s.failedRechecks ?? [] { r.append("a delegated task's check fails after the run: \(c)") }
            if !s.unfinishedTodos.isEmpty { r.append("it left \(s.unfinishedTodos.count) todo\(s.unfinishedTodos.count == 1 ? "" : "s") unfinished") }
            if gaveUp(run, signals: s) { r.append("it changed no files, though the request asked for a change") }
        }
        return r
    }

    /// The tools that change files; a run offered none (Plan mode) isn't expected to.
    static let editTools: Set<String> = ["edit_file", "write_file", "apply_patch"]

    /// A run that finished on its own, could edit and wasn't denied, on a request that asked for a change, and left the
    /// files as they were (COST_AUDIT.md §10, point 6: at 32k context three of 11 cascade runs stopped like this, with
    /// notes and no edit, and earned no offer). A run that ended on a question to the user is waiting, not done. Only
    /// the snapshots can say nothing changed: `filesChanged` counts the edit tools, and good runs edit with commands
    /// (sed, a script) too; on the stored real-sized runs that fallback flagged 7 runs gold passed.
    public static func gaveUp(_ run: AgentRunRecord, signals s: RunSignals) -> Bool {
        s.changeAsked == true && run.outcome.stop == "completed" && run.outcome.denied == 0
            && run.snapshots?.changed == false && !editTools.isDisjoint(with: run.setup.tools)
    }

    /// Verbs that ask for a change when a sentence starts with one (after an opening like "please" or "can you") or one
    /// follows "and" or "then" ("find the bug and fix it").
    static let changeVerbs: Set<String> = [
        "add", "fix", "implement", "change", "update", "refactor", "rename", "remove", "delete", "create", "replace",
        "rewrite", "convert", "port", "migrate", "extend", "modify", "edit", "correct", "move", "split", "make", "wire",
        "introduce", "simplify", "clean", "bump", "patch", "support", "handle", "write",
    ]
    static let openings = ["please", "can you", "could you", "would you", "will you", "i want you to", "i'd like you to",
                           "go ahead and", "now", "ok", "okay", "so", "then", "next", "and", "also", "let's", "lets"]

    /// Whether a request asks for a change to the files. A task card's kind says so when there is one. Otherwise a
    /// sentence must ask for one (a question only when it's a polite request, "can you rename Foo?"): start with a verb
    /// of change ("fix the off-by-one in calc.py"), have one after "and" or "then" ("find the bug and fix it"), or ask
    /// about "what you changed" (a request that describes the behavior wanted and ends "report what you changed"). "Why
    /// does calc.py need a fix?" doesn't. It agrees with the card on every bank and real-sized prompt
    /// (`ChangeRequestTests`). A false yes is an offer for a run that was fine, so words that rarely mean an edit stay
    /// out ("write a summary", "make sure", "add up").
    public static func asksForChange(_ request: String, card: TaskCard? = nil) -> Bool {
        if let kind = card?.kind { return [.edit, .refactor, .fix, .writeTests].contains(kind) }
        // Sentences: a line break, or a space after ".", "!" or "?".
        var sentences: [String] = [], current = ""
        for c in request.lowercased() {
            if c.isNewline || (c.isWhitespace && current.last.map { ".!?".contains($0) } == true) {
                sentences.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        sentences.append(current)
        return sentences.map { $0.trimmingCharacters(in: .whitespaces) }.contains { s in
            // A question asks for an answer, unless it's a polite request ("can you rename Foo?").
            if s.hasSuffix("?") { return politeAsks.contains { s.hasPrefix($0 + " ") } && asks(s) }
            return s.contains(/\bwhat you changed?\b|\byour changes?\b/) || asks(s)
        }
    }

    static let politeAsks = ["can you", "could you", "would you", "will you", "please"]

    /// Whether a sentence asks for a change: a verb of change first (after an opening) or after "and" or "then".
    private static func asks(_ s: String) -> Bool {
        var rest = s
        var opened = true
        while opened {
            opened = false
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;!-").union(.whitespaces))
            for o in openings where rest.hasPrefix(o + " ") || rest.hasPrefix(o + ",") {
                rest = String(rest.dropFirst(o.count))
                opened = true
            }
        }
        let words = rest.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        if asksAt(words[...]) { return true }
        return words.indices.dropLast().contains { i in ["and", "then"].contains(words[i]) && asksAt(words[(i + 1)...]) }
    }

    /// Whether `words` start with a verb of change that asks for an edit.
    private static func asksAt(_ words: ArraySlice<String>) -> Bool {
        guard let verb = words.first, changeVerbs.contains(verb) else { return false }
        let next = words.dropFirst().first ?? ""
        if verb == "make", ["sure", "certain"].contains(next) { return false }
        if verb == "write", ["a", "an", "me", "up"].contains(next) { return false }
        if verb == "add", next == "up" { return false }
        return true
    }

    /// The tier a model is on: this Mac's or the local network's is `local`; a hosted one the pool knows has its entry's
    /// tier; others are unknown (nil), and get no offer on their own.
    public static func tier(endpoint: Endpoint, model: String, pool: ModelPool, endpoints: [Endpoint]) -> PoolEntry.Tier? {
        if endpoint.isCloudAPI { return pool.entry(endpointID: endpoint.id, model: model, endpoints: endpoints)?.entry.tier }
        // Neither a known hosted API nor surely this Mac or its network (Azure, a cloud VM): unknown, not "local".
        return endpoint.isThirdParty ? nil : .local
    }

    /// The main model one tier up (the lowest tier above `tier` with a main entry that runs here), never the same model.
    public static func target(above tier: PoolEntry.Tier, current: (endpointID: UUID?, model: String), pool: ModelPool,
                              endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        pool.available(.main, endpoints: endpoints)
            .filter { $0.entry.tier > tier && !($0.endpoint.id == current.endpointID && $0.model == current.model) }
            .min { ($0.entry.tier, $0.entry.ladder ?? .max) < ($1.entry.tier, $1.entry.ladder ?? .max) }
    }

    /// An offer for a run, or nil: no reason, an unknown or top tier, or nowhere to go.
    /// `unknownTier`: the tier to assume for a model the pool doesn't know (the user's own `/escalate`); nil: no offer.
    public static func offer(run: UUID?, reasons: [String], source: String, endpoint: Endpoint, model: String, pool: ModelPool,
                             endpoints: [Endpoint], contextTokens: Int?, changedFiles: Bool = false, unknownTier: PoolEntry.Tier? = nil,
                             price: (ResolvedPoolEntry) -> PriceList.Price?) -> EscalationOffer? {
        guard !reasons.isEmpty, let tier = tier(endpoint: endpoint, model: model, pool: pool, endpoints: endpoints) ?? unknownTier,
              let to = target(above: tier, current: (endpoint.id, model), pool: pool, endpoints: endpoints) else { return nil }
        return make(run: run, reasons: reasons, source: source, from: (endpoint.id, model), to: to, contextTokens: contextTokens,
                    changedFiles: changedFiles, price: price(to))
    }

    /// Tokens allowed for the hand-over's diff when the run changed files: about 10 KB (the diff is cut at 30 KB).
    public static let handOverDiffTokens = 3_000

    /// What taking a request over on a model at `price` is estimated to cost: a typical task, plus the conversation so
    /// far written to the new model's cache (its cache-write price: 1.25× input for Claude, input elsewhere), plus the
    /// hand-over's diff when the run changed files. Before the cost audit (B7) the history was priced at plain input and
    /// the diff left out.
    public static func estimate(_ p: PriceList.Price, contextTokens: Int?, changedFiles: Bool) -> Double {
        TypicalTask.cost(p) + Double(contextTokens ?? 0) * p.standard.cacheWrite5m / 1e6
            + (changedFiles ? Double(handOverDiffTokens) * p.standard.input / 1e6 : 0)
    }

    /// A review of a run's change, in tokens: the request, report and checks with the diff in, the verdict and findings
    /// out. P3 (2026-10-27): Sonnet 5.5's reviews of small-bank changes cost $0.006–0.011; real-sized diffs run larger.
    public static let reviewInputTokens = handOverDiffTokens + 1_000
    public static let reviewOutputTokens = 800

    /// What one read-only review of the run's change costs on a model at `p` (no cache: one request).
    public static func reviewEstimate(_ p: PriceList.Price) -> Double {
        Double(reviewInputTokens) * p.standard.input / 1e6 + Double(reviewOutputTokens) * p.standard.output / 1e6
    }

    static func make(run: UUID?, reasons: [String], source: String, from: (endpointID: UUID?, model: String), to: ResolvedPoolEntry,
                     contextTokens: Int?, changedFiles: Bool = false, price: PriceList.Price?) -> EscalationOffer {
        let estimate = price.map { Escalation.estimate($0, contextTokens: contextTokens, changedFiles: changedFiles) }
        var offer = EscalationOffer(run: run, reasons: reasons, source: source, fromModel: from.model, fromEndpointID: from.endpointID,
                                    toModel: to.model, toEndpointID: to.endpoint.id, toReasoning: to.entry.reasoning, toProviders: to.entry.providers,
                                    toLabel: to.entry.label, estimate: estimate)
        // A change to review, and not one a review already found wrong (A6's reviewer made this offer).
        if changedFiles, source != "review" {
            offer.reviewable = true
            offer.reviewEstimate = price.map(reviewEstimate)
        }
        return offer
    }

    /// How a hand-over starts (the skill router leaves it alone: it isn't a new request).
    public static let handOverPrefix = "[kurtkode: the user escalated"

    /// What the new model is sent: why it's taking over, and the run's change (cut at `maxDiffBytes`). The conversation
    /// before it goes along as in any model switch.
    public static func handOver(_ offer: EscalationOffer, request: String, diff: String?, maxDiffBytes: Int = 30_000) -> String {
        let line = request.split(separator: "\n").first.map { $0.count > 200 ? $0.prefix(200) + "…" : String($0) } ?? ""
        var s = handOverPrefix + " this request from \(offer.fromModel) to you, because \(offer.reasonText).] "
            + "Pick up where it left off on the request \"\(line)\": check its work against the request, fix or finish what's "
            + "needed, and say what you changed and how you checked it."
        if let diff, !diff.isEmpty {
            let cut = diff.utf8.count > maxDiffBytes
            let shown = cut ? String(decoding: Data(diff.utf8.prefix(maxDiffBytes)), as: UTF8.self) : diff
            s += "\n\nIts changes to the files so far:\n\n```diff\n" + shown + (cut ? "\n… (cut: \(diff.utf8.count / 1000) KB in all)" : "") + "\n```"
        } else if diff != nil {
            s += "\n\nIt changed no files."
        }
        return s
    }
}
