import Foundation

/// Money a run spends (its replies, summaries, and its subagents', which share the meter), against the user's limits:
/// per run, and for the whole session. Each request counts what its cost record says (`CostEntry.spent`: the charge
/// where the server said it, else list price), the same figure every display shows. A local model's requests count
/// nothing. A remote model with no known price (missing from the price lists, api.openai.com, a server whose list lacks
/// it) counts at `unpricedRate`, deliberately high, so a limit still stops it (the cost audit's B5: such sessions
/// used to run past every limit); the stop note says when part of the figure is that estimate.
public final class CostMeter: @unchecked Sendable {
    /// Dollars a run may spend before it pauses; nil: no limit.
    public let runLimit: Double?
    /// Dollars the session may have spent in all; nil: no limit.
    public let sessionLimit: Double?
    /// What the session spent before this run.
    public let sessionBefore: Double
    /// Dollars all sessions may spend in a day (this Mac's day), and what they had spent today before this run; nil: no
    /// limit.
    public let dayLimit: Double?
    public let dayBefore: Double
    /// The same for this project's sessions alone.
    public let projectLimit: Double?
    public let projectBefore: Double
    private let lock = NSLock()
    private var spent = 0.0
    private var estimated = 0.0

    /// Dollars per million tokens for a remote request with no known price: Sonnet-class input, cache reads and
    /// output, above every cheap and standard model in the pool.
    public static let unpricedRate = PriceList.Rates(input: 3, output: 15, cacheRead: 0.30, cacheWrite5m: 3.75, cacheWrite1h: 6)

    /// What a request counts toward the limits: its spending, or for a remote one with no price, its tokens at
    /// `unpricedRate`; 0 for a local one.
    public static func counted(_ e: CostEntry) -> Double {
        if let s = e.spent { return s }
        return e.isUnpricedRemote ? estimate(e.tokens) : 0
    }

    static func estimate(_ u: Usage?) -> Double {
        guard let u else { return 0 }
        let r = unpricedRate, cached = u.cacheReadTokens ?? 0
        return (Double(max(0, u.promptTokens - cached)) * r.input + Double(cached) * r.cacheRead
                + Double(u.completionTokens) * r.output) / 1e6
    }

    public init(runLimit: Double?, sessionLimit: Double?, sessionBefore: Double, dayLimit: Double? = nil, dayBefore: Double = 0,
                projectLimit: Double? = nil, projectBefore: Double = 0) {
        self.runLimit = runLimit.flatMap { $0 > 0 ? $0 : nil }
        self.sessionLimit = sessionLimit.flatMap { $0 > 0 ? $0 : nil }
        self.sessionBefore = sessionBefore
        self.dayLimit = dayLimit.flatMap { $0 > 0 ? $0 : nil }
        self.dayBefore = dayBefore
        self.projectLimit = projectLimit.flatMap { $0 > 0 ? $0 : nil }
        self.projectBefore = projectBefore
    }

    /// This meter with the day's and the project's spending so far (`Spending.today`).
    public func with(dayLimit: Double?, dayBefore: Double, projectLimit: Double?, projectBefore: Double) -> CostMeter {
        CostMeter(runLimit: runLimit, sessionLimit: sessionLimit, sessionBefore: sessionBefore, dayLimit: dayLimit, dayBefore: dayBefore,
                  projectLimit: projectLimit, projectBefore: projectBefore)
    }

    public func add(_ entry: CostEntry) {
        let c = Self.counted(entry)
        guard c > 0 else { return }
        lock.withLock {
            spent += c
            if entry.spent == nil { estimated += c }
        }
    }

    /// The part of `run` estimated at `unpricedRate`.
    public var estimatedPart: Double { lock.withLock { estimated } }

    /// A request with no cost record: what the server said it cost, if anything.
    public func add(_ usage: Usage?) {
        guard let c = usage?.cost, c > 0 else { return }
        lock.withLock { spent += c }
    }

    public var run: Double { lock.withLock { spent } }
    public var session: Double { sessionBefore + run }

    /// What a stop at the limit says (the loop sends it as a status before it stops): which limit, and, for a daily one,
    /// that Continue won't get past it.
    public var stopNote: String? {
        guard let r = reached else { return nil }
        let daily = r.hasPrefix("the daily") || r.hasPrefix("this project's daily")
        let estimate = estimatedPart > 0
            ? String(format: " ($%.2f of it estimated: the model has no known price, so its tokens count at $%.0f/$%.0f per million)",
                     estimatedPart, Self.unpricedRate.input, Self.unpricedRate.output) : ""
        return CostMeter.stopPrefix + r + estimate
            + (daily ? ". Continue won't go past it until tomorrow: raise it in Settings → Generation → "
            + "Spending, or use a local model, which costs nothing." : ".")
    }

    public static let stopPrefix = "Stopped at "

    /// The limit reached, in words ("this run's limit of $2.00: it has spent $2.03"); nil while under both.
    public var reached: String? {
        let run = run
        if let l = runLimit, run >= l { return String(format: "this run's limit of $%.2f: it has spent $%.2f", l, run) }
        if let l = sessionLimit, sessionBefore + run >= l {
            return String(format: "this session's limit of $%.2f: it has spent $%.2f", l, sessionBefore + run)
        }
        if let l = projectLimit, projectBefore + run >= l {
            return String(format: "this project's daily limit of $%.2f: its sessions have spent $%.2f today", l, projectBefore + run)
        }
        if let l = dayLimit, dayBefore + run >= l {
            return String(format: "the daily limit of $%.2f: all sessions have spent $%.2f today", l, dayBefore + run)
        }
        return nil
    }

    /// What a session has spent: every billed request of it and of its subagent runs (`SessionStore.ownSubagentRuns`,
    /// not `subagentRuns`: a fork also holds copies of its original's), summaries and retried attempts included
    /// (`CostEntry.spent`).
    public static func spent(_ session: Session, runs: [Session] = []) -> Double {
        ([session] + runs).flatMap(\.costs).compactMap(\.spent).reduce(0, +)
    }

    /// What a session's requests count toward its limit (`counted`: unpriced remote ones at the default rate).
    public static func counted(_ session: Session, runs: [Session] = []) -> Double {
        ([session] + runs).flatMap(\.costs).map(counted).reduce(0, +)
    }
}
