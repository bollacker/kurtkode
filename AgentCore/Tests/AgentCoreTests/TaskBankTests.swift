import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

/// Each bank task's gold check, against a known-right outcome (it must pass) and a run that did nothing (it must
/// fail): the fixtures and checks are right before any model is judged by them.
@Suite struct TaskBankTests {
    /// Makes the right outcome in `dir` and returns the right report.
    static func oracle(_ id: String, _ dir: URL) throws -> String {
        func read(_ p: String) -> String { TaskBank.read(dir, p) }
        func write(_ p: String, _ s: String) throws { try s.write(to: dir.appending(path: p), atomically: true, encoding: .utf8) }
        func cls(_ p: String) -> String { read(p).firstMatch(of: /class (\w+):/).map { String($0.1) } ?? "?" }
        switch id {
        case "find-reserve-def":
            return "It's at inventory/storage.py:\(TaskBank.lineOf(dir, "inventory/storage.py", "def reserve_stock"))."
        case "callers-reserve":
            return "inventory/api.py:\(TaskBank.lineOf(dir, "inventory/api.py", "reserve_stock(")), "
                + "cli.py:\(TaskBank.lineOf(dir, "cli.py", "reserve_stock(")), tests/test_storage.py:12"
        case "class-in-file": return "It declares \(cls("src/part04.py"))."
        case "file-for-class": return "src/part07.py"
        case "insufficient-status":
            return "409 with {\"error\": ...}; InsufficientStock is raised at inventory/storage.py:"
                + "\(TaskBank.lineOf(dir, "inventory/storage.py", "raise InsufficientStock"))."
        case "discount-for": return "60 units get the 5% discount; the total is 154.26."
        case "calc-bugs-explain": return "sub should be `return a - b`; mean should be `return sum(values) / len(values)`."
        case "log-error": return "2026-03-14 03:17:42 ERROR ledger.flush: disk quota exceeded on /var/spool/ledger"
        case "list-classes":
            return (1...8).map { i in let p = String(format: "src/part%02d.py", i); return "- \(p): \(cls(p))" }.joined(separator: "\n")
        case "fix-calc":
            try write("calc.py", read("calc.py").replacingOccurrences(of: "def sub(a, b):\n    return a + b", with: "def sub(a, b):\n    return a - b")
                .replacingOccurrences(of: "(len(values) - 1)", with: "len(values)"))
            return "Fixed sub and mean; the tests pass."
        case "rename-total":
            for p in ["shop/orders.py", "shop/report.py", "shop/api.py", "tests/test_orders.py"] {
                try write(p, read(p).replacingOccurrences(of: "compute_total", with: "order_total"))
            }
            return "Renamed in four files."
        case "add-median":
            try write("stats.py", read("stats.py") + """


                def median(values):
                    s = sorted(values)
                    n = len(s)
                    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

                """)
            return "Added median."
        case "write-pricing-tests":
            try write("tests/test_pricing.py", """
                import unittest

                from inventory.pricing import price_with_tax, unit_discount


                class PricingTests(unittest.TestCase):
                    def test_no_discount(self):
                        self.assertEqual(unit_discount(5), 0.0)

                    def test_thresholds(self):
                        self.assertEqual(unit_discount(20), 0.05)
                        self.assertEqual(unit_discount(100), 0.10)

                    def test_price(self):
                        \"\"\"A docstring, which verbose output prints between the test's name and its result.\"\"\"
                        self.assertEqual(price_with_tax(2.5, 60), 154.26)

                """)
            return "Wrote tests/test_pricing.py; they pass."
        case "review-diff": return "Yes: range(1, years) skips the first year, an off-by-one."
        case "run-script": return "It prints " + shell("cd \(q(dir.path)) && python3 tools/checksum.py").output
        case "sum-csv": return "The total is 4,317."
        case "find-tax-rate": return "TAX_RATE = 0.0825, at inventory/pricing.py:\(TaskBank.lineOf(dir, "inventory/pricing.py", "TAX_RATE ="))."
        case "find-too-many-test":
            return "test_reserve_too_many, at tests/test_storage.py:\(TaskBank.lineOf(dir, "tests/test_storage.py", "def test_reserve_too_many"))."
        case "importers-of-storage": return "inventory/api.py, cli.py and tests/test_storage.py"
        case "warn-count": return "There are \(TaskBank.warns(dir).values.reduce(0, +)) WARN lines."
        case "warn-top-component":
            let w = TaskBank.warns(dir), top = w.values.max()!
            return "\(w.first { $0.value == top }!.key), with \(top) WARN lines."
        case "january-decisions":
            return "- 2026-01-03: approve the new on-call rotation\n- 2026-01-10: push the billing migration back\n"
                + "- 2026-01-17: cancel the weekly sync with design\n- 2026-01-24: keep the API freeze date"
        case "region-max": return "north, with 1,318."
        case "explain-reserve-success": return "201 with the reservation id and the total, which price_with_tax computes."
        case "explain-checksum": return "It folds the numbers with multiplier 31, modulo 1_000_003."
        case "grow-value": return "It returns 121.0 (100 × 1.1 × 1.1)."
        case "fix-rates":
            try write("rates.py", read("rates.py").replacingOccurrences(of: "range(1, years)", with: "range(years)"))
            return "Fixed the loop range."
        case "fix-shop-total":
            try write("shop/orders.py", read("shop/orders.py").replacingOccurrences(of: "p + q", with: "p * q"))
            return "It added instead of multiplying; fixed."
        case "rename-discount-table":
            try write("inventory/pricing.py", read("inventory/pricing.py").replacingOccurrences(of: "DISCOUNT_TABLE", with: "VOLUME_DISCOUNTS"))
            return "Renamed in inventory/pricing.py."
        case "add-count-items":
            try write("shop/orders.py", read("shop/orders.py") + "\n\ndef count_items(items):\n    return sum(q for _, q in items)\n")
            return "Added count_items."
        case "write-report-tests":
            try write("tests/test_report.py", """
                import unittest

                from shop.report import summary


                class ReportTests(unittest.TestCase):
                    def test_one(self):
                        self.assertEqual(summary({"a": [(1.0, 2)]}), {"a": 2.0})

                    def test_empty(self):
                        self.assertEqual(summary({}), {})

                """)
            return "Wrote two tests; they pass."
        case "review-shop-diff": return "Yes: the new line sums p + q; it should multiply, p * q."
        case "review-clean": return "No bug: ordered[-1] - ordered[0] is equivalent to max - min."
        case "count-tests": return "Ran 2 tests, all passed (OK)."
        default: throw CocoaError(.featureUnsupported)
        }
    }

    /// Makes a plausible wrong outcome in `dir` (prepared, untouched) and returns its report: gold must fail it.
    static func wrong(_ id: String, _ dir: URL) throws -> String {
        func read(_ p: String) -> String { TaskBank.read(dir, p) }
        func write(_ p: String, _ s: String) throws { try s.write(to: dir.appending(path: p), atomically: true, encoding: .utf8) }
        func cls(_ p: String) -> String { read(p).firstMatch(of: /class (\w+):/).map { String($0.1) } ?? "?" }
        switch id {
        case "find-reserve-def": return "inventory/storage.py:\(TaskBank.lineOf(dir, "inventory/storage.py", "def reserve_stock") + 10)"
        case "callers-reserve": return "inventory/api.py:20 and cli.py:30"
        case "class-in-file": return "It declares \(cls("src/part05.py"))."
        case "file-for-class": return "src/part08.py"
        case "insufficient-status":
            return "400 with an error; InsufficientStock is raised at inventory/storage.py:\(TaskBank.lineOf(dir, "inventory/storage.py", "raise InsufficientStock"))."
        case "discount-for": return "10% discount; the total is 146.14."
        case "calc-bugs-explain": return "sub should be `return a - b`."
        case "log-error": return "2026-03-14 03:16:42 ERROR ledger.flush: disk quota exceeded"
        case "list-classes":
            return (1...7).map { i in let p = String(format: "src/part%02d.py", i); return "- \(p): \(cls(p))" }.joined(separator: "\n")
        case "fix-calc":
            try write("calc.py", read("calc.py").replacingOccurrences(of: "def sub(a, b):\n    return a + b", with: "def sub(a, b):\n    return a - b"))
            return "Fixed both bugs."
        case "rename-total":
            try write("shop/orders.py", read("shop/orders.py").replacingOccurrences(of: "compute_total", with: "order_total"))
            return "Renamed everywhere."
        case "add-median":
            try write("stats.py", read("stats.py") + "\n\ndef median(values):\n    s = sorted(values)\n    return s[len(s) // 2]\n")
            return "Added median."
        case "write-pricing-tests":
            try write("tests/test_pricing.py", "import unittest\nfrom inventory.pricing import price_with_tax, unit_discount\n\n"
                      + "class T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(unit_discount(5), 0.0)\n")
            return "Wrote tests for both functions; they pass."
        case "review-diff": return "The diff only adds a guard for years <= 0; no bug."
        case "run-script":
            let n = Int(shell("cd \(q(dir.path)) && python3 tools/checksum.py").output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return "It prints \(n + 1)."
        case "sum-csv": return "The total is 4,217."
        case "find-tax-rate": return "0.08, at inventory/pricing.py:\(TaskBank.lineOf(dir, "inventory/pricing.py", "TAX_RATE ="))"
        case "find-too-many-test":
            return "test_reserve_reduces_stock, at tests/test_storage.py:\(TaskBank.lineOf(dir, "tests/test_storage.py", "def test_reserve_reduces_stock"))"
        case "importers-of-storage": return "inventory/api.py, inventory/pricing.py, cli.py and tests/test_storage.py"
        case "warn-count": return "There are \(TaskBank.warns(dir).values.reduce(0, +) + 1) WARN lines."
        case "warn-top-component":
            let w = TaskBank.warns(dir), top = w.values.max()!
            return "\(w.first { $0.value < top }!.key), with \(top) WARN lines."
        case "january-decisions":
            return "- 2026-01-03: approve the new on-call rotation\n- 2026-01-10: push the billing migration back\n"
                + "- 2026-01-17: cancel the weekly sync with design"
        case "region-max": return "south, with 1,025."
        case "explain-reserve-success": return "200 with the total, which unit_discount computes."
        case "explain-checksum": return "It folds the numbers with multiplier 37, modulo 1_000_007."
        case "grow-value": return "It returns 110.0."
        case "fix-rates":
            try write("test_rates.py", read("test_rates.py").replacingOccurrences(of: "121.0", with: "110.0"))
            return "The tests pass now."
        case "fix-shop-total":
            try write("shop/orders.py", read("shop/orders.py").replacingOccurrences(of: "p + q", with: "p - q"))
            return "Fixed."
        case "rename-discount-table":
            try write("inventory/pricing.py", read("inventory/pricing.py").replacingOccurrences(of: "DISCOUNT_TABLE = ", with: "VOLUME_DISCOUNTS = "))
            return "Renamed."
        case "add-count-items":
            try write("shop/orders.py", read("shop/orders.py") + "\n\ndef count_items(items):\n    return len(items)\n")
            return "Added count_items."
        case "write-report-tests":
            try write("tests/test_report.py", "import unittest\nfrom shop.report import summary\n\n"
                      + "class T(unittest.TestCase):\n    def test_one(self):\n        self.assertEqual(summary({}), {})\n")
            return "Wrote the tests; they pass."
        case "review-shop-diff": return "No bug: it only splits the sum into a variable."
        case "review-clean": return "Yes, this introduces a bug: ordered[-1] is off by one."
        case "count-tests": return "Ran 3 tests, all passed."
        default: throw CocoaError(.featureUnsupported)
        }
    }

    @Test(arguments: TaskBank.all.map(\.id))
    func goldChecksAcceptTheRightOutcomeAndRejectNothing(_ id: String) throws {
        let task = try #require(TaskBank.all.first { $0.id == id })
        let fm = FileManager.default
        let right = fm.temporaryDirectory.appending(path: "kk-bank-ok-\(UUID().uuidString.prefix(6))")
        let idle = fm.temporaryDirectory.appending(path: "kk-bank-no-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: right); try? fm.removeItem(at: idle) }
        try fm.createDirectory(at: right, withIntermediateDirectories: true)
        try fm.createDirectory(at: idle, withIntermediateDirectories: true)
        let prompt = try task.prepare(right)
        #expect(!prompt.isEmpty)
        let report = try Self.oracle(id, right)
        let good = TaskBank.gold(task, dir: right, report: report, record: RunRecord())
        #expect(good.passed, "\(id): \(good.notes)")
        _ = try task.prepare(idle)
        let bad = TaskBank.gold(task, dir: idle, report: "", record: RunRecord())
        #expect(!bad.passed, "\(id) passed with nothing done: \(bad.notes)")
        // A plausible wrong outcome fails too (the docstring bug would have shown here).
        let wrongDir = fm.temporaryDirectory.appending(path: "kk-bank-wrong-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: wrongDir) }
        try fm.createDirectory(at: wrongDir, withIntermediateDirectories: true)
        _ = try task.prepare(wrongDir)
        let wrongReport = try Self.wrong(id, wrongDir)
        let caught = TaskBank.gold(task, dir: wrongDir, report: wrongReport, record: RunRecord())
        #expect(!caught.passed, "\(id) passed a wrong outcome: \(caught.notes)")
        // And a right outcome with an edit outside the task fails.
        try "stray\n".write(to: right.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(!TaskBank.gold(task, dir: right, report: report, record: RunRecord()).passed, "\(id) allowed a stray edit")
    }

    @Test func degradingChangesEveryMultiDigitNumber() {
        #expect(Runner.degrade("src/main.swift:12, total 154.26 at 03:17:42 in Heron42; range(1, years)")
                == "src/main.swift:45, total 487.59 at 36:40:75 in Heron75; range(1, years)")
    }

    @Test func bankCoversEveryKind() {
        #expect(Set(TaskBank.all.compactMap(\.card.kind)) == Set(TaskCard.Kind.allCases))
        #expect(TaskBank.all.count == 34)
        #expect(Set(TaskBank.all.map(\.id)).count == TaskBank.all.count)
    }

    @Test func calibrationRowsCompareJudgesWithGold() {
        func r(_ pass: Bool, _ verdict: Int?, confirmed: Bool? = nil, hard: Bool = false) -> BankResult {
            var checks = GroundedChecks.evaluate(messages: [], report: "x", stop: .completed, maxSteps: 30, workspace: nil, verify: nil)
            if hard { checks.hardFailures = ["no report"] }
            return BankResult(task: "t", kind: "search", agent: "explore", card: TaskCard(), model: "m", trial: 1,
                              gold: CheckResult(passed: pass, score: pass ? 1 : 0), checks: checks,
                              judges: [JudgeOutcome(judge: "j", path: "parent", verdict: verdict, checkedConfirmed: confirmed,
                                                    issues: [], seconds: 1)],
                              stop: "completed", seconds: 1, steps: 1, toolCalls: 0, promptTokens: 0, completionTokens: 0,
                              unpricedRequests: 0, report: "x")
        }
        let rows = JudgeCalibrationRow.rows([r(true, 3), r(true, 1), r(false, 3, confirmed: false), r(false, 0, hard: true), r(false, nil)])
        let j = rows.first { $0.judge == "j" }!
        #expect(j.runs == 5 && j.verdicts == 4 && j.agreement == 0.5 && j.failureRecall == 0.5 && j.falseAlarms == 0.5)
        #expect(j.unconfirmedClaims == 1)
        // A degraded copy whose gold failed counts as one more known failure; one that still passed doesn't count.
        var withCopy = r(true, 3)
        withCopy.degradedGold = CheckResult(passed: false, score: 0)
        withCopy.degradedJudges = [JudgeOutcome(judge: "j", path: "parent", verdict: 0, issues: [], seconds: 1)]
        var ignored = r(true, 3)
        ignored.degradedGold = CheckResult(passed: true, score: 1)
        ignored.degradedJudges = [JudgeOutcome(judge: "j", path: "parent", verdict: 3, issues: [], seconds: 1)]
        let k = JudgeCalibrationRow.rows([withCopy, ignored]).first { $0.judge == "j" }!
        #expect(k.runs == 3 && k.failureRecall == 1 && k.falseAlarms == 0)
        let checks = rows.first { $0.judge == "checks" }!
        #expect(checks.failureRecall == 1.0 / 3 && checks.falseAlarms == 0)
    }
}

extension TaskBankTests {
    @Test func surveyNeedsEveryPostponementAndNoDistractor() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-survey-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try Scenarios.survey.prepare(dir)
        let notes = try FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "notes").path)
        #expect(notes.count == 16)
        // Each postponement is worded differently: no one word finds them all.
        let texts = Fixtures.postponed.map { TaskBank.read(dir, "notes/" + $0).lowercased() }
        for word in ["postpon", "defer", "delay", "push", "later"] { #expect(!texts.allSatisfy { $0.contains(word) }) }
        func run(_ answer: String) -> RunRecord {
            var r = RunRecord()
            r.messages = [ChatMessage(role: .assistant, content: answer)]
            return r
        }
        #expect(Scenarios.survey.check(dir, run(Fixtures.postponed.joined(separator: "\n"))).passed)
        #expect(!Scenarios.survey.check(dir, run(Fixtures.postponed.dropLast().joined(separator: "\n"))).passed)
        let distractor = Fixtures.meetingFiles.first { !Fixtures.postponed.contains($0) && TaskBank.read(dir, "notes/" + $0).contains("postponing the API freeze") }!
        #expect(!Scenarios.survey.check(dir, run((Fixtures.postponed + [distractor]).joined(separator: "\n"))).passed)
    }
}

extension TaskBankTests {
    /// The delegation scenarios' checks: a right answer passes, a wrong one fails.
    @Test func delegationScenariosCheckTheirAnswers() throws {
        func run(_ answer: String) -> RunRecord {
            var r = RunRecord()
            r.messages = [ChatMessage(role: .assistant, content: answer)]
            return r
        }
        func dir(_ s: Scenario) throws -> URL {
            let d = FileManager.default.temporaryDirectory.appending(path: "kk-dlg-\(UUID().uuidString.prefix(6))")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            _ = try s.prepare(d)
            return d
        }
        #expect(Scenarios.delegation.map(\.id) == ["survey", "log-sweep", "two-questions", "tiny-lookup", "small-fix"])
        #expect(Scenarios.delegation.map(\.expectDelegation) == [true, true, true, false, false])

        let logs = try dir(Scenarios.logSweep)
        let counted = (try FileManager.default.contentsOfDirectory(atPath: logs.appending(path: "logs").path))
            .map { TaskBank.read(logs, "logs/" + $0) }.joined().components(separatedBy: "\n").filter { $0.contains(" ERROR ") }
        #expect(counted.count == 16)
        #expect(Scenarios.logSweep.check(logs, run("- timeout: 7\n- disk quota: 4\n- connection refused: 5")).passed)
        #expect(!Scenarios.logSweep.check(logs, run("- timeout: 6\n- disk quota: 4\n- connection refused: 5")).passed)

        let two = try dir(Scenarios.twoQuestions)
        let name = TaskBank.read(two, "parts/src/part04.py").firstMatch(of: /class (\w+):/).map { String($0.1) }!
        let line = TaskBank.lineOf(two, "inventory/storage.py", "def reserve_stock")
        #expect(Scenarios.twoQuestions.check(two, run("(1) inventory/storage.py:\(line) (2) \(name)")).passed)
        #expect(!Scenarios.twoQuestions.check(two, run("(1) inventory/storage.py:\(line) (2) Nothing")).passed)

        let tiny = try dir(Scenarios.tinyLookup)
        #expect(Scenarios.tinyLookup.check(tiny, run("TAX_RATE = 0.0825")).passed)
        #expect(!Scenarios.tinyLookup.check(tiny, run("TAX_RATE = 0.08")).passed)

        let fix = try dir(Scenarios.smallFix)
        #expect(!Scenarios.smallFix.check(fix, run("Fixed.")).passed)
        try TaskBank.read(fix, "calc.py").replacingOccurrences(of: "def sub(a, b):\n    return a + b", with: "def sub(a, b):\n    return a - b")
            .write(to: fix.appending(path: "calc.py"), atomically: true, encoding: .utf8)
        #expect(Scenarios.smallFix.check(fix, run("Fixed.")).passed)
    }
}

extension TaskBankTests {
    /// Real reports that a first version of gold failed (EVAL_PLAN.md: gold tested against both sides).
    @Test func realReportsThatGoldFirstFailedPass() throws {
        func check(_ id: String, _ report: String, edit: ((URL) throws -> Void)? = nil) throws -> CheckResult {
            let task = try #require(TaskBank.all.first { $0.id == id })
            let dir = FileManager.default.temporaryDirectory.appending(path: "kk-real-\(UUID().uuidString.prefix(6))")
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            _ = try task.prepare(dir)
            try edit?(dir)
            return TaskBank.gold(task, dir: dir, report: report, record: RunRecord())
        }
        // gemini: the working shows 110.0 on the way to 121.0.
        #expect(try check("grow-value", "returns `121.0`.\n2. Year 1: `100 * 1.1 = 110.0`\n3. Year 2: `110.0 * 1.1 = 121.0`").passed)
        // gemini: "no bug", with an analysis that says what would break if…
        #expect(try check("review-clean", "**No, the proposed change does not introduce a functional bug.** Nothing breaks: "
                          + "`ordered[-1] - ordered[0]` equals max - min.").passed)
        #expect(!(try check("review-clean", "**Yes**, it introduces a bug at line 9.").passed))
        // Cost-floor stage 2: Markdown in the negation, a question, a list of minor notes.
        #expect(try check("review-clean", "The proposed change does **not** introduce a bug.\n\n**Explanation:** same result.").passed)
        #expect(try check("review-clean", "I've reviewed both files. Let me analyze whether the proposed change introduces a bug. "
                          + "The change is correct.").passed)
        #expect(try check("review-clean", "The diff is not a bug: the result is identical. Minor notes, none of which introduce a bug: "
                          + "it's slower. No bug.").passed)
        #expect(!(try check("review-clean", "The diff looks correct, but on reflection it introduces a bug for empty input.").passed))
        #expect(try check("count-tests", "Tests run: 2. Result: OK (exit code 0). Failures or errors: none.").passed)
        #expect(try check("review-clean", "## Report: does changes.diff introduce a bug in stats.py?\n\n**No bug**: same result.").passed)
        #expect(try check("review-clean", "It's O(n log n) instead of O(n). That is a performance cost, not a correctness bug.").passed)
        #expect(try check("review-shop-diff", "Line 9, `p + q`: it should be price × quantity, not price + quantity.").passed)
        #expect(try check("insufficient-status", "HTTP 409 with {\"error\": ...}. InsufficientStock is raised in reserve_stock at "
                          + "`inventory/storage.py:31-34`.").passed)
        #expect(try check("count-tests", "2 tests ran, all passed, with no failures.").passed)
        #expect(!(try check("count-tests", "Ran 2 tests: FAILED (failures=1).").passed))
        #expect(!(try check("count-tests", "2 tests ran; 1 failed.").passed))
        // gemini: median added, with tests for it in test_stats.py.
        #expect(try check("add-median", "Added median and tests.") { dir in
            try (TaskBank.read(dir, "stats.py") + "\n\ndef median(values):\n    s = sorted(values)\n    n = len(s)\n"
                 + "    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2\n").write(to: dir.appending(path: "stats.py"), atomically: true, encoding: .utf8)
            try (TaskBank.read(dir, "test_stats.py") + "\n# more tests\n").write(to: dir.appending(path: "test_stats.py"), atomically: true, encoding: .utf8)
        }.passed)
    }
}
