import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

/// The hard tier's gold, tested like the bank's: a right outcome passes; an idle run, a plausible wrong outcome (the
/// trap each task sets) and a right outcome with a stray edit all fail.
@Suite struct TaskBankHardTests {
    static func oracle(_ id: String, _ dir: URL) throws -> String {
        func read(_ p: String) -> String { TaskBank.read(dir, p) }
        func write(_ p: String, _ s: String) throws { try s.write(to: dir.appending(path: p), atomically: true, encoding: .utf8) }
        func edit(_ p: String, _ pairs: [(String, String)]) throws {
            var s = read(p)
            for (a, b) in pairs { #expect(s.contains(a), "\(p) lacks \(a)"); s = s.replacingOccurrences(of: a, with: b) }
            try write(p, s)
        }
        switch id {
        case "h-discount-code":
            try edit("inventory/pricing.py", [
                ("def price_with_tax(unit_price: float, units: int) -> float:\n    subtotal = unit_price * units * (1 - unit_discount(units))\n",
                 "def price_with_tax(unit_price: float, units: int, discount_code=None) -> float:\n    subtotal = unit_price * units * (1 - unit_discount(units))\n"
                    + "    if discount_code == \"SAVE10\":\n        subtotal *= 0.9\n")])
            try edit("inventory/api.py", [("price_with_tax(request[\"unit_price\"], r.units)",
                                           "price_with_tax(request[\"unit_price\"], r.units, discount_code=request.get(\"discount_code\"))")])
            try edit("cli.py", [("res.add_argument(\"units\", type=int)", "res.add_argument(\"units\", type=int); res.add_argument(\"--code\")")])
            return "Added discount_code to pricing, the API and the CLI (--code); the tests pass."
        case "h-config-migrate":
            try write("settings.json", "{\"server\": {\"host\": \"0.0.0.0\", \"port\": 8080, \"debug\": false},\n"
                      + " \"limits\": {\"max_items\": 250, \"ratio\": 0.75}}\n")
            try FileManager.default.removeItem(at: dir.appending(path: "settings.ini"))
            try write("config.py", "import json\n\n\ndef load_settings(path=\"settings.json\"):\n    with open(path) as f:\n        return json.load(f)\n")
            return "Moved to settings.json; tests pass."
        case "h-unit-bug":
            try edit("geo/units.py", [("    return km * KM_PER_MILE", "    return km / KM_PER_MILE")])
            return "km_to_miles multiplied instead of dividing; fixed in geo/units.py."
        case "h-leap-year":
            try edit("dates.py", [("    return year % 4 == 0", "    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)")])
            return "Fixed the century rule."
        case "h-rename-trap":
            try edit("metrics/source.py", [("def load(path):", "def load_snapshot(path):")])
            try edit("metrics/report.py", [("import load\n", "import load_snapshot\n"), ("data = load(path)", "data = load_snapshot(path)")])
            try edit("metrics/alerts.py", [("source.load(path)", "source.load_snapshot(path)")])
            return "Renamed load to load_snapshot in three files; the \"load\" keys are unchanged."
        case "h-edge-tests":
            try write("test_durations.py", """
                import unittest

                from durations import parse_duration


                class DurationTests(unittest.TestCase):
                    def test_units(self):
                        self.assertEqual(parse_duration("90s"), 90)
                        self.assertEqual(parse_duration("2m"), 120)
                        self.assertEqual(parse_duration("2h"), 7200)

                    def test_combined(self):
                        self.assertEqual(parse_duration("1h30m"), 5400)

                    def test_empty(self):
                        with self.assertRaises(ValueError):
                            parse_duration("")

                    def test_invalid(self):
                        with self.assertRaises(ValueError):
                            parse_duration("abc")

                """)
            return "Wrote test_durations.py; 4 tests pass."
        case "h-plugins": return "Registered but not enabled: delta, hotel. Enabled but not registered: zulu. (echo2 is only in a comment.)"
        case "h-log-correlate": return Fixtures.workerFailedAfter200.joined(separator: ", ")
        case "h-import-cycle": return "Yes: mod_c → mod_f → mod_h → mod_c."
        case "h-aliased-calls":
            return ["a.py": "emit(\"saved\"", "b.py": "fire(\"deleted\"", "c.py": "events.emit("].sorted { $0.key < $1.key }
                .map { "\($0.key):\(TaskBank.lineOf(dir, $0.key, $0.value))" }.joined(separator: ", ")
        case "h-mutable-default":
            return "Yes: cart=[] is a mutable default argument, so the same list is shared between calls and items accumulate."
        case "h-retry-explain": return "0.5 + 1 + 2 = 3.5 seconds; it retries TimeoutError and ConnectionError."
        case "h-incidents": return "api and search had two each; the longest was billing, 1h35m = 95 minutes."
        case "h-crash-diagnose":
            let out = shell("cd \(q(dir.path)) && python3 tools/report.py 2>&1").output
            #expect(out.contains("ValueError: amount is empty"), "\(out)")
            return "ValueError: amount is empty, raised at tools/parse.py:\(TaskBank.lineOf(dir, "tools/parse.py", "raise ValueError")); record r-0317."
        default: throw CocoaError(.featureUnsupported)
        }
    }

    /// The trap each task sets, sprung.
    static func wrong(_ id: String, _ dir: URL) throws -> String {
        func read(_ p: String) -> String { TaskBank.read(dir, p) }
        func write(_ p: String, _ s: String) throws { try s.write(to: dir.appending(path: p), atomically: true, encoding: .utf8) }
        switch id {
        case "h-discount-code":
            // Only the pricing function, not threaded through.
            try write("inventory/pricing.py", read("inventory/pricing.py")
                .replacingOccurrences(of: "units: int) -> float:\n    subtotal", with: "units: int, discount_code=None) -> float:\n    subtotal")
                .replacingOccurrences(of: "    return round(subtotal", with: "    if discount_code == \"SAVE10\":\n        subtotal *= 0.9\n    return round(subtotal"))
            return "Added the discount code."
        case "h-config-migrate":
            try write("settings.json", "{\"server\": {\"host\": \"0.0.0.0\", \"port\": \"8080\", \"debug\": \"false\"},\n"
                      + " \"limits\": {\"max_items\": \"250\", \"ratio\": \"0.75\"}}\n")
            try write("config.py", "import json\n\n\ndef load_settings(path=\"settings.json\"):\n    with open(path) as f:\n        return json.load(f)\n")
            return "Converted."
        case "h-unit-bug":
            try write("geo/route.py", read("geo/route.py").replacingOccurrences(of: "km_to_miles(k)", with: "k / 1.609344"))
            return "Fixed total_miles; the tests pass."
        case "h-leap-year":
            try write("dates.py", read("dates.py").replacingOccurrences(of: "year % 4 == 0", with: "year % 4 == 0 and year != 1900"))
            return "Fixed; the tests pass."
        case "h-rename-trap":
            for p in ["metrics/source.py", "metrics/report.py", "metrics/alerts.py"] {
                try write(p, read(p).replacingOccurrences(of: "load(", with: "load_snapshot(")
                    .replacingOccurrences(of: "json.load_snapshot(", with: "json.load(")
                    .replacingOccurrences(of: "import load\n", with: "import load_snapshot\n")
                    .replacingOccurrences(of: "\"load\"", with: "\"load_snapshot\""))
            }
            return "Renamed every load."
        case "h-edge-tests":
            try write("test_durations.py", "import unittest\nfrom durations import parse_duration\n\n\n"
                      + "class T(unittest.TestCase):\n    def test_seconds(self):\n        self.assertEqual(parse_duration(\"90s\"), 90)\n")
            return "Wrote tests; they pass."
        case "h-plugins": return "Not enabled: delta, hotel, echo2. Unregistered: zulu."
        case "h-log-correlate": return (Fixtures.workerFailedAfter200 + Fixtures.workerFailedAfter500).joined(separator: ", ")
        case "h-import-cycle": return "Yes: mod_a → mod_c → mod_f → mod_h → mod_d."
        case "h-aliased-calls":
            return "a.py:\(TaskBank.lineOf(dir, "a.py", "emit(\"saved\"")), c.py:\(TaskBank.lineOf(dir, "c.py", "events.emit("))"
        case "h-mutable-default": return "No bug: it only adds a docstring and a default."
        case "h-retry-explain": return "0.5 + 1 + 2 + 4 = 7.5 seconds; it retries TimeoutError and ConnectionError."
        case "h-incidents": return "api and search; the longest was queue, 66 minutes."
        case "h-crash-diagnose":
            return "ValueError at tools/report.py:\(TaskBank.lineOf(dir, "tools/report.py", "parse_amount(row")); record r-0317."
        default: throw CocoaError(.featureUnsupported)
        }
    }

    @Test(arguments: TaskBank.hard.map(\.id))
    func goldAcceptsTheRightOutcomeAndRejectsTheTrap(_ id: String) throws {
        let task = try #require(TaskBank.hard.first { $0.id == id })
        let fm = FileManager.default
        func fresh(_ tag: String) throws -> URL {
            let d = fm.temporaryDirectory.appending(path: "kk-hard-\(tag)-\(UUID().uuidString.prefix(6))")
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        let right = try fresh("ok"), idle = try fresh("no"), wrongDir = try fresh("wrong")
        defer { for d in [right, idle, wrongDir] { try? fm.removeItem(at: d) } }
        #expect(!(try task.prepare(right)).isEmpty)
        let report = try Self.oracle(id, right)
        let good = TaskBank.gold(task, dir: right, report: report, record: RunRecord())
        #expect(good.passed, "\(id): \(good.notes)")
        _ = try task.prepare(idle)
        let bad = TaskBank.gold(task, dir: idle, report: "", record: RunRecord())
        #expect(!bad.passed, "\(id) passed with nothing done: \(bad.notes)")
        _ = try task.prepare(wrongDir)
        let caught = TaskBank.gold(task, dir: wrongDir, report: try Self.wrong(id, wrongDir), record: RunRecord())
        #expect(!caught.passed, "\(id) passed the trap: \(caught.notes)")
        try "stray\n".write(to: right.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(!TaskBank.gold(task, dir: right, report: report, record: RunRecord()).passed, "\(id) allowed a stray edit")
    }

    @Test func verifyCommandsPassOnTheRightOutcomeAndFailIdle() throws {
        let fm = FileManager.default
        for task in TaskBank.hard {
            guard let verify = task.card.verify else { continue }
            let right = fm.temporaryDirectory.appending(path: "kk-hv-\(UUID().uuidString.prefix(6))")
            let idle = fm.temporaryDirectory.appending(path: "kk-hvi-\(UUID().uuidString.prefix(6))")
            defer { try? fm.removeItem(at: right); try? fm.removeItem(at: idle) }
            for d in [right, idle] { try fm.createDirectory(at: d, withIntermediateDirectories: true); _ = try task.prepare(d) }
            _ = try Self.oracle(task.id, right)
            #expect(shell("cd \(q(right.path)) && \(verify) 2>&1").status == 0, "\(task.id): verify fails on the right outcome")
            #expect(shell("cd \(q(idle.path)) && \(verify) 2>&1").status != 0, "\(task.id): verify passes with nothing done")
        }
    }

    /// Right answers from the first reference runs that gold first failed: they name the decoys only to rule them out.
    @Test(arguments: ["h-aliased-calls", "h-import-cycle", "h-log-correlate", "h-mutable-default",
                      "h-import-cycle#gemini-4-argon", "h-import-cycle#claude-opus-5.5", "h-import-cycle#mimo-v2.6-flash",
                      "h-log-correlate#claude-haiku-5.5-off"])
    func realReportsThatGoldFirstFailedPass(_ key: String) throws {
        let id = String(key.split(separator: "#")[0])
        let url = try #require(Bundle.module.url(forResource: "hard-real-reports", withExtension: "json", subdirectory: "Fixtures"))
        let reports = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let task = try #require(TaskBank.hard.first { $0.id == id })
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-hard-real-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try task.prepare(dir)
        let r = TaskBank.gold(task, dir: dir, report: try #require(reports[key]), record: RunRecord())
        #expect(r.passed, "\(key): \(r.notes)")
    }

    @Test func hardTierCoversEveryKindAndIsSeparateFromTheBank() {
        #expect(Set(TaskBank.hard.map(\.card.kind)) == Set(TaskBank.all.map(\.card.kind)))
        #expect(Set(TaskBank.hard.map(\.id)).isDisjoint(with: TaskBank.all.map(\.id)))
        #expect(TaskBank.named(["hard"]).count == 14)
        #expect(TaskBank.named(["h-leap-year", "fix-calc"]).count == 2)
    }
}
