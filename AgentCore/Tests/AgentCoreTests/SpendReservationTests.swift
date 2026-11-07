import Foundation
import Testing
@testable import EvalKit

/// The eval's spending cap counts the runs in flight (the cost audit's P2: a $4.50 cap ended at $7.80).
@Suite struct SpendReservationTests {
    @Test func runsInFlightCountTowardTheCap() {
        let r = SpendReservation(prior: 0)
        // Nothing known yet and no prior: only what was spent counts.
        #expect(!r.wouldExceed(4.5, spent: 0, starting: "sonnet"))
        r.started("sonnet"); r.started("sonnet"); r.started("sonnet")
        #expect(r.reserved == 0)
        r.finished("sonnet", listPrice: 1.9)
        // Two still running at $1.9 each, plus a new one: $1.9 spent + $3.8 + $1.9 > $4.50.
        #expect(abs(r.reserved - 3.8) < 1e-9)
        #expect(r.wouldExceed(4.5, spent: 1.9, starting: "sonnet"))
        // Another model's runs are estimated from its own.
        #expect(r.expected("haiku") == 0)
        r.finished("sonnet", listPrice: 0.5)
        r.finished("sonnet", listPrice: nil)
        #expect(r.reserved == 0 && abs(r.expected("sonnet") - 1.2) < 1e-9)
        #expect(!r.wouldExceed(10, spent: 2.4, starting: "sonnet"))
        #expect(r.wouldExceed(2, spent: 2.4, starting: "haiku"))         // already past
    }

    /// BUG_HUNT_2026-11-02.md item 45: before a model's first run finishes, each run in flight is reserved at the prior,
    /// and the check and the start are one step, so a wide start stops at the cap.
    @Test func aWideStartStopsAtTheCapBeforeAnyRunFinishes() async {
        let r = SpendReservation(prior: 0.5)
        #expect(r.expected("sonnet") == 0.5)
        // 40 runs try to start at once under a $5 cap: ten fit at $0.50 each.
        let started = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<40 { group.addTask { r.tryStart("sonnet", cap: 5, spent: 0) } }
            var n = 0
            for await ok in group where ok { n += 1 }
            return n
        }
        #expect(started == 10)
        #expect(abs(r.reserved - 5) < 1e-9)
        // A run finishing at $1.90 sets the estimate: the nine still running reserve $17.10, so nothing more starts.
        r.finished("sonnet", listPrice: 1.9)
        #expect(!r.tryStart("sonnet", cap: 5, spent: 1.9))
        #expect(!r.tryStart("haiku", cap: 5, spent: 1.9))
    }
}
