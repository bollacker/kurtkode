import Foundation

/// What runs still going are expected to cost, for a spending cap that is checked before each run starts
/// (`kurtkode-eval --max-cost`). Without it the cap counted only finished runs: in the cost audit's P2, a $4.50 cap
/// on Sonnet ended at $7.80, with two $1.9 runs in flight when it tripped. A run's expected cost is the mean list price
/// of its model's runs finished so far in this process, or `prior` before one has finished (BUG_HUNT_2026-11-02.md
/// item 45: with nothing reserved then, a wide start could launch dozens of runs past the cap). The check and the
/// start are one step under the lock (`tryStart`), so runs starting at once can't each see room for one.
public final class SpendReservation: @unchecked Sendable {
    private let lock = NSLock()
    private var running: [String: Int] = [:]
    private var finished: [String: (sum: Double, n: Int)] = [:]
    /// What a run of a model with no finished run is expected to cost.
    public let prior: Double

    public init(prior: Double = 0.5) { self.prior = prior }

    /// The mean list price of a finished run of `model`, or `prior` when none has finished.
    public func expected(_ model: String) -> Double { lock.withLock { expectedLocked(model) } }

    private func expectedLocked(_ model: String) -> Double {
        guard let f = finished[model], f.n > 0 else { return prior }
        return f.sum / Double(f.n)
    }

    /// The expected cost of every run in flight.
    public var reserved: Double { lock.withLock { reservedLocked() } }

    private func reservedLocked() -> Double {
        running.reduce(0) { total, kv in total + expectedLocked(kv.key) * Double(kv.value) }
    }

    /// Whether a new run of `model` would take spending past `cap`: what was `spent`, the runs in flight, and the new
    /// run's own expected cost.
    public func wouldExceed(_ cap: Double, spent: Double, starting model: String) -> Bool {
        lock.withLock { exceedsLocked(cap, spent: spent, model) }
    }

    private func exceedsLocked(_ cap: Double, spent: Double, _ model: String) -> Bool {
        spent >= cap || spent + reservedLocked() + expectedLocked(model) > cap
    }

    /// Starts a run of `model` unless it would take spending past `cap` (`wouldExceed`), in one step: true when it
    /// started (call `finished` when it ends).
    public func tryStart(_ model: String, cap: Double, spent: Double) -> Bool {
        lock.withLock {
            guard !exceedsLocked(cap, spent: spent, model) else { return false }
            running[model, default: 0] += 1
            return true
        }
    }

    public func started(_ model: String) { lock.withLock { running[model, default: 0] += 1 } }

    public func finished(_ model: String, listPrice: Double?) {
        lock.withLock {
            running[model] = max(0, (running[model] ?? 0) - 1)
            if let p = listPrice {
                var f = finished[model] ?? (0, 0)
                f.sum += p
                f.n += 1
                finished[model] = f
            }
        }
    }
}
