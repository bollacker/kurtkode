import AgentCore
import Foundation

/// One task shaped like a real delegation, run directly on a subagent (SUBAGENT_ROUTING_DESIGN.md "Seeding"): the
/// fixture, the task as a parent would write it, its card, and a gold check of the outcome that needs no model.
public struct BankTask: Sendable {
    public let id: String
    public let summary: String
    /// The built-in agent that runs it: explore (read-only) or general.
    public let agent: String
    public let card: TaskCard
    public var maxSteps = 30
    /// The run's wall-clock limit in seconds (the watchdog in `Runner.performSubagentTask`).
    public var wallClock: TimeInterval = 900
    /// The paths the task may change (a prefix each, "tests/" for a folder); empty: none. Gold fails a run that
    /// changes anything else (EVAL_PLAN.md E2), Python's __pycache__ aside.
    public var mayChange: [String] = []
    /// Run in a restored copy of a run's tree, after its ignored files are cleared, before gold is checked again: a
    /// build bound to the folder it was made in (SwiftPM's `.build`) is made again where the copy is. Nil: nothing.
    public var rebuild: String? = nil
    /// Builds the fixture in the directory and returns the task's prompt.
    public let prepare: @Sendable (URL) throws -> String
    /// Gold: did the run do the task? From the fixture and the report.
    public let check: @Sendable (URL, String, RunRecord) -> CheckResult
    /// Seconds the card's verify command may run when the eval runs it again after the run (the bash tool's limit,
    /// 600, caps it); nil: the bash tool's default.
    public var checkTimeout: Int? = nil

    /// Builds the fixture and marks its base commit (`Fixtures.markBase`); returns the task's prompt.
    public func setUp(_ dir: URL) throws -> String {
        let prompt = try prepare(dir)
        Fixtures.markBase(dir)
        return prompt
    }
}

public enum TaskBank {
    public static let all: [BankTask] = [
        findReserveDef, callersOfReserve, classInFile, fileForClass, insufficientStatus, discountFor, calcBugsExplain,
        logError, listClasses, fixCalc, renameTotal, addMedian, writePricingTests, reviewDiff, runScript, sumCSV,
    ] + more

    /// Gold for a run: the task's own check, and nothing changed outside what the task may change.
    public static func gold(_ task: BankTask, dir: URL, report: String, record: RunRecord) -> CheckResult {
        var r = task.check(dir, report, record)
        let (ok, stray) = untouched(dir, task.mayChange)
        r.notes.append((ok ? "✓ " : "✗ ") + (ok ? "nothing changed outside the task" : "changed outside the task: \(stray)"))
        if !ok { r.passed = false; r.score = max(0, r.score - 0.5) }
        return r
    }

    /// Whether every changed path (since the fixture's base, __pycache__ aside) starts with one of `allowed`; the
    /// others.
    static func untouched(_ dir: URL, _ allowed: [String]) -> (Bool, [String]) {
        let changed = changedPaths(dir)
        let stray = changed.filter { p in !allowed.contains { p.hasPrefix($0) } }
        return (stray.isEmpty, stray)
    }

    /// The paths the run changed: tracked files that differ from the fixture's base commit (`Fixtures.base`, so what
    /// the run committed counts), and new files git doesn't ignore. Python's caches aside.
    static func changedPaths(_ dir: URL) -> [String] {
        let git = "git -C \(q(dir.path)) -c core.quotePath=false"
        let tracked = shell("\(git) diff --name-only --no-renames \(Fixtures.base(dir)) --")
        let untracked = shell("\(git) ls-files --others --exclude-standard")
        var lines = Set<String>()
        for r in [tracked, untracked] where r.status == 0 {
            for line in r.output.split(separator: "\n") { lines.insert(String(line)) }
        }
        return lines.filter { !$0.isEmpty && !$0.contains("__pycache__") && !$0.hasSuffix(".pyc") }.sorted()
    }

    /// The ids in `ids` that name no task (a set name, `all`, `hard` and `real` are names too).
    public static func unknown(_ ids: [String]) -> [String] {
        let special = ["all", "hard", "real"]
        guard !(ids.count == 1 && (special.contains(ids[0]) || ids[0].hasPrefix("real:"))) else {
            return ids[0].hasPrefix("real:") && real(set: String(ids[0].dropFirst(5))).isEmpty ? ids : []
        }
        let known = Set(every.map(\.id))
        return ids.filter { !known.contains($0) }
    }

    public static func named(_ ids: [String]) -> [BankTask] {
        if ids == ["hard"] { return hard }
        if ids == ["real"] { return real }
        if ids.count == 1, ids[0].hasPrefix("real:") { return real(set: String(ids[0].dropFirst(5))) }
        return ids.isEmpty || ids == ["all"] ? all : every.filter { ids.contains($0.id) }
    }

    static func read(_ dir: URL, _ path: String) -> String { (try? String(contentsOf: dir.appending(path: path), encoding: .utf8)) ?? "" }
    /// Whether the report cites `line` of a file ending in `suffix`: path:N within `slack` lines, or a range path:A-B
    /// that holds it (cost-floor stage 2: "inventory/storage.py:31-34" for a raise at 34).
    static func cites(_ report: String, _ suffix: String, _ line: Int, slack: Int = 1) -> Bool {
        if GroundedChecks.citations(in: report).contains(where: { $0.path.hasSuffix(suffix) && abs($0.line - line) <= slack }) { return true }
        return report.matches(of: /([\w.\/-]+):(\d+)\s*[-–]\s*(\d+)/).contains { m in
            String(m.1).hasSuffix(suffix) && (Int(m.2) ?? 0) - slack <= line && line <= (Int(m.3) ?? 0) + slack
        }
    }

    static func lineOf(_ dir: URL, _ path: String, _ needle: String) -> Int {
        (read(dir, path).components(separatedBy: "\n").firstIndex { $0.contains(needle) } ?? -2) + 1
    }
    static func result(_ parts: [(String, Bool)]) -> CheckResult {
        let ok = parts.filter(\.1).count
        return CheckResult(passed: ok == parts.count, score: Double(ok) / Double(max(1, parts.count)),
                           notes: parts.map { ($0.1 ? "✓ " : "✗ ") + $0.0 })
    }
    static func onlyChanged(_ dir: URL, _ allowed: Set<String>) -> (Bool, [String]) {
        let changed = changedPaths(dir)
        return (changed.allSatisfy { allowed.contains($0) }, changed)
    }

    // MARK: search

    static let findReserveDef = BankTask(
        id: "find-reserve-def", summary: "Locate a method by path:line", agent: "explore",
        card: TaskCard(kind: .search, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Where is the method reserve_stock defined? Give its location as path:line."
        },
        check: { dir, report, _ in
            let line = lineOf(dir, "inventory/storage.py", "def reserve_stock")
            let hit = cites(report, "storage.py", line)
            return result([("cites storage.py:\(line)", hit)])
        })

    static let callersOfReserve = BankTask(
        id: "callers-reserve", summary: "Find every caller of a method", agent: "explore",
        card: TaskCard(kind: .search, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "List every place in the project that calls reserve_stock (calls, not its definition), with path:line for each."
        },
        check: { _, report, _ in
            let t = report.lowercased()
            return result([("api.py", t.contains("api.py")), ("cli.py", t.contains("cli.py")),
                           ("test_storage.py", t.contains("test_storage.py")),
                           ("no invented callers in models/pricing", !t.contains("models.py:") && !t.contains("pricing.py:"))])
        })

    static let classInFile = BankTask(
        id: "class-in-file", summary: "Name the class a file declares", agent: "explore",
        card: TaskCard(kind: .search, importance: .low),
        prepare: { dir in
            _ = try Fixtures.documentation(at: dir, count: 10, seed: 7)
            return "Which class does src/part04.py declare? Give its exact name."
        },
        check: { dir, report, _ in
            let name = read(dir, "src/part04.py").firstMatch(of: /class (\w+):/).map { String($0.1) } ?? "?"
            return result([("names \(name)", report.contains(name))])
        })

    static let fileForClass = BankTask(
        id: "file-for-class", summary: "Find which file declares a class", agent: "explore",
        card: TaskCard(kind: .search, importance: .low),
        prepare: { dir in
            let expected = try Fixtures.documentation(at: dir, count: 10, seed: 11)
            return "Which file declares the class \(expected["src/part07.py"]!)? Give its path."
        },
        check: { _, report, _ in result([("names src/part07.py", report.contains("part07.py"))]) })

    // MARK: explain

    static let insufficientStatus = BankTask(
        id: "insufficient-status", summary: "Explain an error path in an HTTP handler", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "What HTTP status and response body does the API return when a reservation asks for more units than "
                + "are in stock? Name the exception involved and where it's raised (path:line)."
        },
        check: { dir, report, _ in
            let raise = lineOf(dir, "inventory/storage.py", "raise InsufficientStock")
            let cited = cites(report, "storage.py", raise, slack: 2)
            return result([("409", report.contains("409")), ("InsufficientStock", report.contains("InsufficientStock")),
                           ("cites the raise, storage.py:\(raise)", cited)])
        })

    static let discountFor = BankTask(
        id: "discount-for", summary: "Work out a price from the pricing code", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Using the code in inventory/pricing.py: what volume discount applies to 60 units, and what does "
                + "price_with_tax return for 60 units at a unit price of 2.50? Show the numbers."
        },
        check: { _, report, _ in
            // 2.50 × 60 × (1 − 0.05) × 1.0825 = 154.26
            result([("total 154.26", report.contains("154.26")),
                     ("5% discount", report.contains("5%") || report.contains("0.05"))])
        })

    static let calcBugsExplain = BankTask(
        id: "calc-bugs-explain", summary: "Diagnose two bugs without changing anything", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.calc(at: dir)
            return "The tests in test_calc.py fail. Without changing any file, find which functions in calc.py are wrong "
                + "and give the corrected line for each."
        },
        check: { _, report, _ in
            let t = report.replacingOccurrences(of: " ", with: "")
            return result([("sub: a-b", t.contains("a-b")), ("mean: sum(values)/len(values)", t.contains("sum(values)/len(values)")),
                           ("names both", report.contains("sub") && report.contains("mean"))])
        })

    // MARK: summarize

    static let logError = BankTask(
        id: "log-error", summary: "Find the one error in a long log", agent: "explore",
        card: TaskCard(kind: .summarize, importance: .normal),
        prepare: { dir in
            try Fixtures.serverLog(at: dir)
            return "logs/app.log has exactly one ERROR in it. When did it happen, which component logged it, and what "
                + "was the cause? Quote the line."
        },
        check: { _, report, _ in
            result([("time 03:17:42", report.contains("03:17:42")), ("component ledger.flush", report.contains("ledger.flush")),
                    ("cause: disk quota", report.lowercased().contains("quota"))])
        })

    static let listClasses = BankTask(
        id: "list-classes", summary: "List every class in a package with its file", agent: "explore",
        card: TaskCard(kind: .summarize, importance: .normal),
        prepare: { dir in
            _ = try Fixtures.documentation(at: dir, count: 8, seed: 23)
            return "List every class declared under src/, each with the file that declares it."
        },
        check: { dir, report, _ in
            let expected = (1...8).map { i -> (String, String) in
                let path = String(format: "src/part%02d.py", i)
                return (path, read(dir, path).firstMatch(of: /class (\w+):/).map { String($0.1) } ?? "?")
            }
            let lines = report.components(separatedBy: "\n")
            let right = expected.filter { path, name in
                lines.contains { $0.contains(name) && $0.contains((path as NSString).lastPathComponent) }
            }
            return CheckResult(passed: right.count == expected.count, score: Double(right.count) / 8,
                               notes: ["\(right.count)/8 classes with their files"])
        })

    // MARK: changes

    static let fixCalc = BankTask(
        id: "fix-calc", summary: "Fix two bugs so the tests pass", agent: "general",
        card: TaskCard(kind: .fix, importance: .normal, verify: "python3 -m unittest"), mayChange: ["calc.py"],
        prepare: { dir in
            try Fixtures.calc(at: dir)
            return "The tests fail. Fix the bugs in calc.py so they pass, without changing the tests."
        },
        check: { dir, _, _ in
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            let (only, changed) = onlyChanged(dir, ["calc.py"])
            return result([("tests pass", pass), ("only calc.py changed \(changed)", only)])
        })

    static let renameTotal = BankTask(
        id: "rename-total", summary: "Rename a function across a package", agent: "general",
        // The check also fails while the old name is left anywhere (a reverted rename passes the tests).
        card: TaskCard(kind: .refactor, importance: .normal,
                       verify: "python3 -m unittest && ! grep -rn compute_total --include='*.py' ."),
        mayChange: ["shop/", "tests/"],
        prepare: { dir in
            try Fixtures.shop(at: dir)
            return "Rename the function compute_total to order_total everywhere in the project: its definition and every "
                + "use, keeping the behavior the same."
        },
        check: { dir, _, _ in
            let left = shell("grep -rn compute_total \(q(dir.path)) --include='*.py'").output
            let defined = read(dir, "shop/orders.py").contains("def order_total(")
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            return result([("no compute_total left", left.isEmpty), ("order_total defined", defined), ("tests pass", pass)])
        })

    static let addMedian = BankTask(
        id: "add-median", summary: "Add a function to a module", agent: "general",
        card: TaskCard(kind: .edit, importance: .normal,
                       verify: "python3 -c 'from stats import median; assert median([3, 1, 2]) == 2 and median([4, 1, 3, 2]) == 2.5'"),
        // Adding tests for the new function is fine (seen: gemini-3.6-flash did; the first version failed it).
        mayChange: ["stats.py", "test_stats.py"],
        prepare: { dir in
            try Fixtures.stats(at: dir)
            return "Add a function median(values) to stats.py that returns the median of a non-empty list of numbers "
                + "(for an even count, the mean of the two middle values). Don't change the existing functions."
        },
        check: { dir, _, _ in
            let ok = shell("cd \(q(dir.path)) && python3 -c 'from stats import median; assert median([3, 1, 2]) == 2 and "
                           + "median([4, 1, 3, 2]) == 2.5 and median([7]) == 7'").status == 0
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            return result([("median works", ok), ("existing tests pass", pass)])
        })

    static let writePricingTests = BankTask(
        id: "write-pricing-tests", summary: "Write passing tests for a module", agent: "general",
        // The check runs the new file's own tests, so it fails if the file is gone (the whole suite would still pass).
        card: TaskCard(kind: .writeTests, importance: .normal, verify: "python3 -m unittest discover -s tests -p test_pricing.py"),
        mayChange: ["tests/test_pricing.py"],
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Write unit tests for unit_discount and price_with_tax in inventory/pricing.py, in a new file "
                + "tests/test_pricing.py, covering both discount thresholds. Run the tests with "
                + "`python3 -m unittest discover -s tests` and make sure they pass. Don't change inventory/pricing.py."
        },
        check: { dir, _, _ in
            let tests = read(dir, "tests/test_pricing.py")
            let run = shell("cd \(q(dir.path)) && python3 -m unittest discover -s tests 2>&1")
            // Counted from "Ran N tests" on the file alone (verbose lines put a docstring between a test and its "ok").
            let own = shell("cd \(q(dir.path)) && python3 -m unittest discover -s tests -p test_pricing.py 2>&1")
            let count = own.status == 0 ? (own.output.firstMatch(of: /Ran (\d+) tests?/).flatMap { Int($0.1) } ?? 0) : 0
            let untouched = shell("git -C \(q(dir.path)) diff --quiet -- inventory/pricing.py").status == 0
            return result([("tests/test_pricing.py tests both functions", tests.contains("unit_discount") && tests.contains("price_with_tax")),
                           ("at least 3 passing pricing tests (\(count))", count >= 3), ("all tests pass", run.status == 0),
                           ("pricing.py unchanged", untouched)])
        })

    // MARK: review, run, research

    static let reviewDiff = BankTask(
        id: "review-diff", summary: "Find the bug a proposed change introduces", agent: "explore",
        card: TaskCard(kind: .review, importance: .high),
        prepare: { dir in
            try Fixtures.ratesReview(at: dir)
            return "changes.diff is a proposed change to rates.py. Review it: does it introduce a bug? If so, say which "
                + "line and what goes wrong."
        },
        check: { _, report, _ in
            let t = report.lowercased()
            let named = t.contains("range(1") || t.contains("off-by-one") || t.contains("off by one")
            let effect = t.contains("one year") || t.contains("first year") || t.contains("one fewer") || t.contains("year short")
                || t.contains("fewer year") || t.contains("skips") || t.contains("years - 1") || t.contains("n-1") || t.contains("n - 1")
            return result([("names the range change", named), ("says what goes wrong", effect)])
        })

    static let runScript = BankTask(
        id: "run-script", summary: "Run a script and report its output", agent: "general",
        card: TaskCard(kind: .run, importance: .low),
        prepare: { dir in
            try Fixtures.checksum(at: dir)
            return "Run tools/checksum.py with python3 and report the number it prints."
        },
        check: { dir, report, _ in
            let gold = shell("cd \(q(dir.path)) && python3 tools/checksum.py").output.trimmingCharacters(in: .whitespacesAndNewlines)
            return result([("reports \(gold)", !gold.isEmpty && report.contains(gold))])
        })

    static let sumCSV = BankTask(
        id: "sum-csv", summary: "Total a column across several CSV files", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal),
        prepare: { dir in
            try Fixtures.sales(at: dir)
            return "What is the total of the amount column across all the CSV files in data/? Give the number."
        },
        check: { _, report, _ in
            let gold = Fixtures.salesTotal
            let plain = report.replacingOccurrences(of: ",", with: "")
            return result([("total \(gold)", plain.contains(String(gold)))])
        })
}

// MARK: - Fixtures for the task bank

extension Fixtures {
    /// A 500-line service log with one ERROR, at line 372.
    public static func serverLog(at root: URL) throws {
        var rng = SplitMix(seed: 5)
        let parts = ["http.server", "auth.session", "ledger.flush", "cache.warm", "jobs.runner", "mail.queue"]
        var lines: [String] = []
        for i in 0..<500 {
            let t = 10_800 + i * 7
            let stamp = String(format: "2026-03-14 %02d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
            if i == 371 {
                lines.append("2026-03-14 03:17:42 ERROR ledger.flush: disk quota exceeded on /var/spool/ledger (wrote 0 of 4096 bytes)")
                continue
            }
            let part = parts[Int(rng.next() % UInt64(parts.count))]
            let level = rng.next() % 9 == 0 ? "WARN " : (rng.next() % 3 == 0 ? "DEBUG" : "INFO ")
            let msg = level == "WARN " ? "slow response (\(200 + rng.next() % 800) ms)" : "handled request \(rng.next() % 100_000)"
            lines.append("\(stamp) \(level) \(part): \(msg)")
        }
        try write(root, ["logs/app.log": lines.joined(separator: "\n") + "\n", "README.md": "# service\n"])
        try commitAll(root)
    }

    /// A small package where compute_total is defined once and used in three other files.
    public static func shop(at root: URL) throws {
        try write(root, [
            "shop/__init__.py": "",
            "shop/orders.py": """
                \"\"\"Orders and their totals.\"\"\"


                def compute_total(items):
                    \"\"\"Sum of price × quantity over (price, quantity) pairs.\"\"\"
                    return round(sum(p * q for p, q in items), 2)
                """,
            "shop/report.py": """
                from shop.orders import compute_total


                def summary(orders):
                    return {name: compute_total(items) for name, items in orders.items()}
                """,
            "shop/api.py": """
                from . import orders


                def total_handler(request):
                    return 200, {"total": orders.compute_total(request["items"])}
                """,
            "tests/__init__.py": "",
            "tests/test_orders.py": """
                import unittest

                from shop.orders import compute_total
                from shop.report import summary


                class OrderTests(unittest.TestCase):
                    def test_total(self):
                        self.assertEqual(compute_total([(2.5, 2), (1.0, 3)]), 8.0)

                    def test_summary(self):
                        self.assertEqual(summary({"a": [(1.0, 1)]}), {"a": 1.0})


                if __name__ == "__main__":
                    unittest.main()
                """,
        ])
        try commitAll(root)
    }

    /// A statistics module with tests, to extend.
    public static func stats(at root: URL) throws {
        try write(root, [
            "stats.py": """
                \"\"\"Small statistics helpers.\"\"\"


                def mean(values):
                    return sum(values) / len(values)


                def spread(values):
                    return max(values) - min(values)
                """,
            "test_stats.py": """
                import unittest

                from stats import mean, spread


                class StatsTests(unittest.TestCase):
                    def test_mean(self):
                        self.assertEqual(mean([1, 2, 3]), 2)

                    def test_spread(self):
                        self.assertEqual(spread([4, 9, 1]), 8)


                if __name__ == "__main__":
                    unittest.main()
                """,
        ])
        try commitAll(root)
    }

    /// A compound-interest module and a proposed diff that drops the first year (range(1, years)).
    public static func ratesReview(at root: URL) throws {
        try write(root, [
            "rates.py": """
                \"\"\"Savings projections.\"\"\"


                def grow(balance, rate, years):
                    \"\"\"Balance after compounding once a year for `years` years.\"\"\"
                    for _ in range(years):
                        balance *= 1 + rate
                    return round(balance, 2)
                """,
            "changes.diff": """
                --- a/rates.py
                +++ b/rates.py
                @@ -1,8 +1,10 @@
                 \"\"\"Savings projections.\"\"\"


                 def grow(balance, rate, years):
                     \"\"\"Balance after compounding once a year for `years` years.\"\"\"
                -    for _ in range(years):
                +    if years <= 0:
                +        return round(balance, 2)
                +    for _ in range(1, years):
                         balance *= 1 + rate
                     return round(balance, 2)
                """,
        ])
        try commitAll(root)
    }

    /// A script whose output can't be guessed without running it.
    public static func checksum(at root: URL) throws {
        try write(root, [
            "tools/checksum.py": """
                \"\"\"Prints a checksum of the numbers in data.txt.\"\"\"
                import pathlib

                values = [int(x) for x in (pathlib.Path(__file__).parent.parent / "data.txt").read_text().split()]
                total = 0
                for i, v in enumerate(values):
                    total = (total * 31 + v * (i + 7)) % 1_000_003
                print(total)
                """,
            "data.txt": (1...60).map { String(($0 * 7_919) % 1_009) }.joined(separator: " ") + "\n",
        ])
        try commitAll(root)
    }

    /// The total of the amount column across `sales`'s CSV files.
    public static let salesTotal = 4_317

    /// Three small CSV files whose amounts add up to `salesTotal`.
    public static func sales(at root: URL) throws {
        let files: [String: [(String, Int)]] = [
            "data/q1.csv": [("north", 412), ("south", 233), ("east", 518), ("west", 95)],
            "data/q2.csv": [("north", 377), ("south", 604), ("east", 141), ("west", 266)],
            "data/q3.csv": [("north", 529), ("south", 188), ("east", 450), ("west", 504)],
        ]
        var out: [String: String] = ["README.md": "# Sales\n\nQuarterly sales by region.\n"]
        for (path, rows) in files { out[path] = "region,amount\n" + rows.map { "\($0.0),\($0.1)" }.joined(separator: "\n") + "\n" }
        try write(root, out)
        try commitAll(root)
    }
}

extension Fixtures {
    /// The meeting notes of `meetingNotes`, and those in which something was postponed (each worded differently).
    public static let meetingFiles = (1...16).map { String(format: "2026-%02d-%02d.md", 1 + ($0 - 1) / 4, 3 + (($0 - 1) % 4) * 7) }
    public static let postponed = [meetingFiles[1], meetingFiles[5], meetingFiles[8], meetingFiles[11], meetingFiles[14]]

    /// Sixteen meeting notes, each padded with discussion. Five decide to postpone something, in five different
    /// phrasings; others decide other things, and two mention postponing only to reject it.
    public static func meetingNotes(at root: URL) throws {
        let delays = [
            "We agreed to push the billing migration back to the second half of the year.",
            "The vendor review won't happen before the audit is finished, so it moves to next month.",
            "Launch of the partner portal is deferred until Q3; marketing will be told.",
            "Given the outage, the team decided to hold off on the database upgrade until after the holidays.",
            "We'll revisit the hiring plan in June instead of now; the req stays frozen until then.",
        ]
        let others = [
            "Decision: approve the new on-call rotation starting Monday.",
            "Decision: cancel the weekly sync with design; async updates instead.",
            "Someone suggested postponing the API freeze, but we kept the date as planned.",
            "Decision: hire one more SRE this quarter.",
            "Decision: adopt the new incident template.",
            "The question of delaying the offsite came up; we decided to go ahead as scheduled.",
            "Decision: retire the old metrics dashboard.",
            "Decision: move standup to 9:45.",
            "Decision: buy the second build server.",
            "Decision: rotate the shared credentials this week.",
            "Decision: document the release checklist in the wiki.",
        ]
        let filler = [
            "Status went around the table; most streams are on track.", "The flaky test in checkout was discussed again.",
            "Support volume was normal for the week.", "Two customers asked about export formats.",
            "The infra budget review is still pending finance.", "Action items from last week were mostly closed.",
            "Someone raised documentation gaps in the onboarding guide.", "The team reviewed open incidents; none are severe.",
        ]
        var files: [String: String] = ["README.md": "# Team notes\n\nOne file per meeting.\n"]
        var d = 0, o = 0
        for (i, name) in meetingFiles.enumerated() {
            var lines = ["# Team meeting \(name.dropLast(3))", "", "Attendees: Ana, Bo, Chen, Dee, Eli", "", "## Discussion", ""]
            for k in 0..<36 { lines.append("- " + filler[(i * 5 + k) % filler.count] + " (item \(k + 1))") }
            lines += ["", "## Decisions", ""]
            if postponed.contains(name) { lines.append("- " + delays[d]); d += 1 } else { lines.append("- " + others[o % others.count]); o += 1 }
            lines.append("- Next meeting as usual.")
            files["notes/" + name] = lines.joined(separator: "\n") + "\n"
        }
        try write(root, files)
        try commitAll(root)
    }
}
