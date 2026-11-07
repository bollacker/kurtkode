import Foundation
import Testing
@testable import AgentCore

/// A listed OpenRouter price that jumps more than 3× is held until a later read confirms it (COST_AUDIT.md F5: a 10×
/// listing glitch for deepseek-v4-flash-0731 was recorded into 340 eval runs).
@Suite struct RemotePriceSanityTests {
    func price(_ input: Double, _ output: Double) -> PriceList.Price {
        PriceList.Price(standard: PriceList.Rates(input: input, output: output, cacheRead: input / 10, cacheWrite5m: input,
                                                  cacheWrite1h: input),
                        longAbove: nil, long: nil, perSearch: nil, perRequest: nil)
    }

    @Test func aJumpIsHeldUntilConfirmed() {
        var memory: [String: RemotePrices.Remembered] = [:]
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let normal = price(0.0444, 0.1333), glitch = price(0.444, 1.333)
        // First sight: adopted.
        var r = RemotePrices.steady(["ds": normal], remembered: &memory, server: "or", now: t0)
        #expect(r.prices["ds"] == normal && r.held.isEmpty)
        // 10× the next day: the old price is used, with a note.
        r = RemotePrices.steady(["ds": glitch, "other": price(1, 2)], remembered: &memory, server: "or", now: t0 + 86_400)
        #expect(r.prices["ds"]?.input == 0.0444 && r.held["ds"]?.contains("held") == true)
        #expect(r.prices["other"]?.input == 1 && r.held["other"] == nil)
        // Still 10× an hour later: still held.
        r = RemotePrices.steady(["ds": glitch], remembered: &memory, server: "or", now: t0 + 86_400 + 3600)
        #expect(r.prices["ds"]?.input == 0.0444)
        // Back to normal: adopted, and nothing is pending any more.
        r = RemotePrices.steady(["ds": normal], remembered: &memory, server: "or", now: t0 + 86_400 + 7200)
        #expect(r.prices["ds"] == normal && memory["or|ds"]?.pending == nil)
        // A real price change, seen again 6 hours later: adopted then.
        let raised = price(0.2, 0.8)
        r = RemotePrices.steady(["ds": raised], remembered: &memory, server: "or", now: t0 + 2 * 86_400)
        #expect(r.prices["ds"]?.input == 0.0444)
        r = RemotePrices.steady(["ds": raised], remembered: &memory, server: "or", now: t0 + 2 * 86_400 + 6 * 3600)
        #expect(r.prices["ds"] == raised && r.held.isEmpty)
        // Changes within 3× are adopted at once.
        r = RemotePrices.steady(["ds": price(0.5, 2)], remembered: &memory, server: "or", now: t0 + 3 * 86_400)
        #expect(r.prices["ds"]?.input == 0.5)
        // Servers are kept apart.
        r = RemotePrices.steady(["ds": glitch], remembered: &memory, server: "other-server", now: t0 + 3 * 86_400)
        #expect(r.prices["ds"] == glitch)
    }
}
