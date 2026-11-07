import AgentCore
import Foundation

/// The bank's second half (EVAL_PLAN.md E3): three or four tasks per kind in all, one review with no bug.
extension TaskBank {
    static let more: [BankTask] = [
        findTaxRate, findTooManyTest, importersOfStorage, warnCount, warnTopComponent, explainReserveSuccess,
        explainChecksum, growValue, januaryDecisions, fixRates, fixShopTotal, renameDiscountTable, addCountItems,
        writeReportTests, reviewShopDiff, reviewClean, countTests, regionMax,
    ]

    static func has(_ report: String, _ any: [String]) -> Bool {
        let t = report.lowercased()
        return any.contains { t.contains($0.lowercased()) }
    }

    /// WARN lines in the server log, by component.
    static func warns(_ dir: URL) -> [String: Int] {
        var out: [String: Int] = [:]
        for line in read(dir, "logs/app.log").components(separatedBy: "\n") where line.contains(" WARN ") {
            if let m = line.firstMatch(of: /WARN\s+([\w.]+):/) { out[String(m.1), default: 0] += 1 }
        }
        return out
    }

    // MARK: search

    static let findTaxRate = BankTask(
        id: "find-tax-rate", summary: "Find a constant's value and where it's defined", agent: "explore",
        card: TaskCard(kind: .search, importance: .low),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "What tax rate does the pricing code use, and where is it defined? Give the value and path:line."
        },
        check: { dir, report, _ in
            let line = lineOf(dir, "inventory/pricing.py", "TAX_RATE =")
            let cited = GroundedChecks.citations(in: report).contains { $0.path.hasSuffix("pricing.py") && abs($0.line - line) <= 1 }
            return result([("0.0825 (8.25%)", has(report, ["0.0825", "8.25%", "8.25 %"])), ("cites pricing.py:\(line)", cited)])
        })

    static let findTooManyTest = BankTask(
        id: "find-too-many-test", summary: "Find the test that covers a case", agent: "explore",
        card: TaskCard(kind: .search, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Which test checks that reserving more units than are in stock raises an error? Give its name and path:line."
        },
        check: { dir, report, _ in
            let line = lineOf(dir, "tests/test_storage.py", "def test_reserve_too_many")
            let cited = GroundedChecks.citations(in: report).contains { $0.path.hasSuffix("test_storage.py") && abs($0.line - line) <= 1 }
            return result([("names test_reserve_too_many", report.contains("test_reserve_too_many")),
                           ("cites test_storage.py:\(line)", cited)])
        })

    static let importersOfStorage = BankTask(
        id: "importers-of-storage", summary: "List the files that import a module", agent: "explore",
        card: TaskCard(kind: .search, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Which files import from inventory/storage.py (with absolute or relative imports)? List their paths."
        },
        check: { _, report, _ in
            let t = report.lowercased()
            return result([("api.py", t.contains("api.py")), ("cli.py", t.contains("cli.py")),
                           ("test_storage.py", t.contains("test_storage.py")),
                           ("not pricing.py or models.py", !t.contains("pricing.py") && !t.contains("models.py"))])
        })

    // MARK: summarize, research

    static let warnCount = BankTask(
        id: "warn-count", summary: "Count lines of one kind in a long log", agent: "explore",
        card: TaskCard(kind: .summarize, importance: .normal),
        prepare: { dir in
            try Fixtures.serverLog(at: dir)
            return "How many WARN lines are there in logs/app.log? Give the exact number."
        },
        check: { dir, report, _ in
            let n = warns(dir).values.reduce(0, +)
            let numbers = report.matches(of: /\b(\d+)\b/).compactMap { Int($0.1) }
            return result([("says \(n)", numbers.contains(n))])
        })

    static let warnTopComponent = BankTask(
        id: "warn-top-component", summary: "Find which component warns most in a log", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal),
        prepare: { dir in
            try Fixtures.serverLog(at: dir)
            return "In logs/app.log, which component logged the most WARN lines, and how many?"
        },
        check: { dir, report, _ in
            let w = warns(dir)
            let top = w.values.max() ?? 0
            let leaders = w.filter { $0.value == top }.keys
            return result([("names \(leaders.sorted().joined(separator: " or "))", leaders.contains { report.contains($0) }),
                           ("says \(top)", report.matches(of: /\b(\d+)\b/).compactMap { Int($0.1) }.contains(top))])
        })

    static let januaryDecisions = BankTask(
        id: "january-decisions", summary: "Summarize a decision from each of several notes", agent: "explore",
        card: TaskCard(kind: .summarize, importance: .normal),
        prepare: { dir in
            try Fixtures.meetingNotes(at: dir)
            return "For each January meeting in notes/ (the 2026-01-*.md files), say in one line what was decided."
        },
        check: { _, report, _ in
            let wanted = [("01-03", "on-call"), ("01-10", "billing"), ("01-17", "design"), ("01-24", "freeze")]
            let lines = report.lowercased().components(separatedBy: "\n")
            return result(wanted.map { date, word in ("\(date): \(word)", lines.contains { $0.contains(date) && $0.contains(word) }) })
        })

    static let regionMax = BankTask(
        id: "region-max", summary: "Aggregate CSV files by a column", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal),
        prepare: { dir in
            try Fixtures.sales(at: dir)
            return "Across all the CSV files in data/, which region has the highest total amount, and what is that total?"
        },
        check: { _, report, _ in
            // north 412 + 377 + 529 = 1318
            result([("north", has(report, ["north"])), ("1318", report.replacingOccurrences(of: ",", with: "").contains("1318"))])
        })

    // MARK: explain

    static let explainReserveSuccess = BankTask(
        id: "explain-reserve-success", summary: "Explain a handler's success path", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "What status code and body does the API's reserve handler return when a reservation succeeds, and "
                + "which function computes the total in it?"
        },
        check: { _, report, _ in result([("201", report.contains("201")), ("price_with_tax", report.contains("price_with_tax"))]) })

    static let explainChecksum = BankTask(
        id: "explain-checksum", summary: "Explain what a script computes", agent: "explore",
        card: TaskCard(kind: .explain, importance: .low),
        prepare: { dir in
            try Fixtures.checksum(at: dir)
            return "Without running it, explain what tools/checksum.py computes. Which multiplier and which modulus does it use?"
        },
        check: { _, report, _ in
            result([("multiplier 31", report.contains("31")),
                    ("modulus 1000003", report.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: ",", with: "").contains("1000003"))])
        })

    static let growValue = BankTask(
        id: "grow-value", summary: "Work out a function's result from its code", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.ratesReview(at: dir)
            return "Using rates.py as it is now (ignore changes.diff), what does grow(100, 0.1, 2) return? Explain briefly."
        },
        check: { _, report, _ in
            // 100 × 1.1 × 1.1 = 121.0. (Working that shows "100 × 1.1 = 110.0" on the way is fine; a first version
            // failed every model for it.)
            result([("121", report.contains("121"))])
        })

    // MARK: changes

    static let fixRates = BankTask(
        id: "fix-rates", summary: "Fix an off-by-one so the tests pass", agent: "general",
        card: TaskCard(kind: .fix, importance: .normal, verify: "python3 -m unittest"), mayChange: ["rates.py"],
        prepare: { dir in
            try Fixtures.ratesBroken(at: dir)
            return "The tests in test_rates.py fail. Fix rates.py so they pass, without changing the tests."
        },
        check: { dir, _, _ in
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            return result([("tests pass", pass)])
        })

    static let fixShopTotal = BankTask(
        id: "fix-shop-total", summary: "Fix a wrong operator so the tests pass", agent: "general",
        card: TaskCard(kind: .fix, importance: .normal, verify: "python3 -m unittest"), mayChange: ["shop/orders.py"],
        prepare: { dir in
            try Fixtures.shopBroken(at: dir)
            return "The shop tests fail. Find the bug in the shop package and fix it, without changing the tests."
        },
        check: { dir, _, _ in
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            return result([("tests pass", pass)])
        })

    static let renameDiscountTable = BankTask(
        id: "rename-discount-table", summary: "Rename a module constant", agent: "general",
        card: TaskCard(kind: .refactor, importance: .normal,
                       verify: "python3 -c 'from inventory.pricing import VOLUME_DISCOUNTS, unit_discount; assert unit_discount(20) == 0.05' "
                           + "&& ! grep -rn DISCOUNT_TABLE --include='*.py' ."),
        mayChange: ["inventory/pricing.py", "tests/"],
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Rename DISCOUNT_TABLE to VOLUME_DISCOUNTS everywhere in the project, keeping the behavior the same."
        },
        check: { dir, _, _ in
            let left = shell("grep -rn DISCOUNT_TABLE \(q(dir.path)) --include='*.py'").output
            let works = shell("cd \(q(dir.path)) && python3 -c 'from inventory.pricing import VOLUME_DISCOUNTS, unit_discount; "
                              + "assert unit_discount(20) == 0.05 and unit_discount(150) == 0.10'").status == 0
            return result([("no DISCOUNT_TABLE left", left.isEmpty), ("VOLUME_DISCOUNTS works", works)])
        })

    static let addCountItems = BankTask(
        id: "add-count-items", summary: "Add a small function", agent: "general",
        card: TaskCard(kind: .edit, importance: .normal,
                       verify: "python3 -c 'from shop.orders import count_items; assert count_items([(2.5, 2), (1.0, 3)]) == 5'"),
        mayChange: ["shop/orders.py", "tests/"],
        prepare: { dir in
            try Fixtures.shop(at: dir)
            return "Add a function count_items(items) to shop/orders.py that returns the total quantity over a list of "
                + "(price, quantity) pairs. Don't change the other functions."
        },
        check: { dir, _, _ in
            let ok = shell("cd \(q(dir.path)) && python3 -c 'from shop.orders import count_items; "
                           + "assert count_items([(2.5, 2), (1.0, 3)]) == 5 and count_items([]) == 0'").status == 0
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            return result([("count_items works", ok), ("existing tests pass", pass)])
        })

    static let writeReportTests = BankTask(
        id: "write-report-tests", summary: "Write tests for a function", agent: "general",
        card: TaskCard(kind: .writeTests, importance: .normal, verify: "python3 -m unittest tests.test_report"),
        mayChange: ["tests/test_report.py"],
        prepare: { dir in
            try Fixtures.shop(at: dir)
            return "Write unit tests for summary() in shop/report.py, in a new file tests/test_report.py, with at least two "
                + "cases. Run them with `python3 -m unittest tests.test_report` and make sure they pass."
        },
        check: { dir, _, _ in
            let own = shell("cd \(q(dir.path)) && python3 -m unittest tests.test_report 2>&1")
            let count = own.status == 0 ? (own.output.firstMatch(of: /Ran (\d+) tests?/).flatMap { Int($0.1) } ?? 0) : 0
            let uses = read(dir, "tests/test_report.py").contains("summary")
            return result([("tests/test_report.py tests summary", uses), ("at least 2 passing tests (\(count))", count >= 2)])
        })

    // MARK: review, run

    static let reviewShopDiff = BankTask(
        id: "review-shop-diff", summary: "Find the bug in a proposed change", agent: "explore",
        card: TaskCard(kind: .review, importance: .high),
        prepare: { dir in
            try Fixtures.shopReview(at: dir)
            return "changes.diff is a proposed change to shop/orders.py. Does it introduce a bug? If so, which line and why?"
        },
        check: { _, report, _ in
            let t = report.replacingOccurrences(of: " ", with: "").lowercased()
            return result([("names p + q", t.contains("p+q")), ("says it should multiply", has(report, ["multipl", "p * q", "p*q", "product", "×", "times"]))])
        })

    static let reviewClean = BankTask(
        id: "review-clean", summary: "Review a correct change (no bug to find)", agent: "explore",
        card: TaskCard(kind: .review, importance: .normal),
        prepare: { dir in
            try Fixtures.statsReview(at: dir)
            return "changes.diff is a proposed change to stats.py. Does it introduce a bug? If so, which line and why; "
                + "if not, say so."
        },
        check: { _, report, _ in
            let clean = has(report.filter { !"*_`".contains($0) }, ["no bug", "doesn't introduce", "does not introduce", "no issue",
                                     "not introduce", "is correct", "equivalent", "behaves the same", "same behavior", "same result",
                                     "looks correct", "not a bug", "not a correctness bug", "no correctness", "performance change"])
            // An alarm is a claim of a bug, not a word in the analysis (a first version counted "breaks" in "nothing
            // breaks"): an answer that opens with yes, or "introduces a bug" not negated.
            let opening = report.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "*#_> "))
            // Markdown aside ("does **not** introduce"), a claim is "introduces a bug" with no negation or question
            // just before it ("whether this introduces a bug", "none of which introduce a bug").
            let plain = report.lowercased().filter { !"*_`".contains($0) }
            let claimed = plain.matches(of: /introduces? an? (functional )?bug/).contains { m in
                let start = plain.index(m.range.lowerBound, offsetBy: -40, limitedBy: plain.startIndex) ?? plain.startIndex
                let before = plain[start..<m.range.lowerBound]
                // A question ("does it introduce a bug?") isn't a claim either.
                let after = plain[m.range.upperBound...].prefix { $0 != "\n" && $0 != "." }
                return !["not", "n't", "whether", "if ", "none", "no ", "never", "does "].contains { before.contains($0) }
                    && !after.contains("?")
            }
            let alarm = opening.hasPrefix("yes") || claimed
            return result([("says there's no bug", clean), ("raises no false bug", !alarm)])
        })

    static let countTests = BankTask(
        id: "count-tests", summary: "Run a test suite and report the result", agent: "general",
        card: TaskCard(kind: .run, importance: .low),
        prepare: { dir in
            try Fixtures.shop(at: dir)
            return "Run the project's tests with `python3 -m unittest` and report how many tests ran and whether they all passed."
        },
        check: { _, report, _ in
            result([("2 tests", report.matches(of: /\b(\d+)\b/).compactMap { Int($0.1) }.contains(2)),
                    // A claim of failure, not the word: "no failures or errors" is a pass (cost-floor stage 2).
                    ("all passed", has(report, ["pass", "ok"])
                        && report.lowercased().firstMatch(of: /failed \(|failures=[1-9]|errors=[1-9]|\b[1-9]\d* (tests? )?(failed|failures?)\b|(some|one|a) tests? failed/) == nil)])
        })
}

// MARK: - Fixtures for the second half

extension Fixtures {
    /// The ERROR kinds in `manyLogs`, and how many of each there are in all.
    public static let errorCounts: [(String, Int)] = [("timeout", 7), ("disk quota", 4), ("connection refused", 5)]

    /// Five logs of 300 lines each, with the errors of `errorCounts` scattered among them.
    public static func manyLogs(at root: URL) throws {
        var rng = SplitMix(seed: 17)
        var slots: [String] = []
        for (kind, n) in errorCounts { slots += Array(repeating: kind, count: n) }
        var files: [String: String] = [:]
        var placed = 0
        for f in 1...5 {
            var lines: [String] = []
            for i in 0..<300 {
                let t = 3600 * f + i * 11
                let stamp = String(format: "2026-04-0%d %02d:%02d:%02d", f, (t / 3600) % 24, (t / 60) % 60, t % 60)
                if placed < slots.count, (i * 7 + f * 13) % 89 == 0 {
                    let kind = slots[placed]; placed += 1
                    let detail = kind == "timeout" ? "request timeout after 30 s" : kind == "disk quota" ? "disk quota exceeded on /data"
                        : "connection refused by db-\(rng.next() % 4)"
                    lines.append("\(stamp) ERROR worker.\(f): \(detail)")
                } else {
                    lines.append("\(stamp) INFO  worker.\(f): processed batch \(rng.next() % 100_000)")
                }
            }
            files[String(format: "logs/service-%d.log", f)] = lines.joined(separator: "\n") + "\n"
        }
        precondition(placed == slots.count, "manyLogs placed \(placed) of \(slots.count) errors")
        try write(root, files)
        try commitAll(root)
    }

    /// rates.py with the off-by-one already in it, and a test that catches it.
    public static func ratesBroken(at root: URL) throws {
        try write(root, [
            "rates.py": """
                \"\"\"Savings projections.\"\"\"


                def grow(balance, rate, years):
                    \"\"\"Balance after compounding once a year for `years` years.\"\"\"
                    for _ in range(1, years):
                        balance *= 1 + rate
                    return round(balance, 2)
                """,
            "test_rates.py": """
                import unittest

                from rates import grow


                class RatesTests(unittest.TestCase):
                    def test_two_years(self):
                        self.assertEqual(grow(100, 0.1, 2), 121.0)

                    def test_zero_years(self):
                        self.assertEqual(grow(100, 0.1, 0), 100)


                if __name__ == "__main__":
                    unittest.main()
                """,
        ])
        try commitAll(root)
    }

    /// The shop package with p + q where it should multiply.
    public static func shopBroken(at root: URL) throws {
        try shop(at: root)
        let url = root.appending(path: "shop/orders.py")
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "p * q", with: "p + q")
        try Data(text.utf8).write(to: url)
        try git(root, ["commit", "-qam", "broken"])
    }

    /// The shop package and a proposed diff that adds instead of multiplying.
    public static func shopReview(at root: URL) throws {
        try shop(at: root)
        try write(root, ["changes.diff": """
            --- a/shop/orders.py
            +++ b/shop/orders.py
            @@ -3,5 +3,6 @@


             def compute_total(items):
                 \"\"\"Sum of price × quantity over (price, quantity) pairs.\"\"\"
            -    return round(sum(p * q for p, q in items), 2)
            +    total = sum(p + q for p, q in items)
            +    return round(total, 2)
            """])
        try git(root, ["add", "-A"])
        try git(root, ["commit", "-qm", "diff"])
    }

    /// The stats module and a proposed diff that's correct (a refactor with the same behavior).
    public static func statsReview(at root: URL) throws {
        try stats(at: root)
        try write(root, ["changes.diff": """
            --- a/stats.py
            +++ b/stats.py
            @@ -6,4 +6,5 @@


             def spread(values):
            -    return max(values) - min(values)
            +    ordered = sorted(values)
            +    return ordered[-1] - ordered[0]
            """])
        try git(root, ["add", "-A"])
        try git(root, ["commit", "-qm", "diff"])
    }
}
