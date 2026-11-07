import AgentCore
import Foundation

/// The hard tier (COST_FLOOR_PLAN.md, stage 3): tasks that need several files read or changed together, traps where
/// the obvious answer is wrong, and checks that grade the work itself (hidden cases, mutation testing). Run with
/// `--bank hard`; not part of `all`, so the 34-task bank stays comparable.
extension TaskBank {
    public static let hard: [BankTask] = [
        hDiscountCode, hUnitBug, hRenameTrap, hPlugins, hEdgeTests, hMutableDefault, hLeapYear, hLogCorrelate,
        hConfigMigrate, hImportCycle, hAliasedCalls, hCrashDiagnose, hRetryExplain, hIncidents,
    ]

    /// Every task, for looking runs up by id (`all`, the hard tier and the real set).
    public static var every: [BankTask] { all + hard + real }

    /// Whether every paragraph that mentions `decoy` also rules it out ("not", "comment", a 500, ...): a good answer
    /// often names the decoys to say why they don't count (real reports from the first references did).
    static func onlyRuledOut(_ report: String, _ decoy: String, _ marks: [String]) -> Bool {
        report.lowercased().components(separatedBy: "\n\n").filter { $0.contains(decoy.lowercased()) }
            .allSatisfy { p in marks.contains { p.contains($0) } }
    }
    static let negations = ["not ", "n't", "no ", "exclud", "except", "only a comment", "comment", "isn't", "aren't", "never"]

    /// Whether the cycle the report claims holds only `cycle`. A claim is a closed chain (mod_c → mod_f → mod_h →
    /// mod_c) on a line that doesn't rule itself out ("... is not a cycle"); import listings ("mod_a → mod_b, mod_c")
    /// aren't closed. With no closed chain, the answer is the opening, up to the first line about other modules or
    /// ruling something out (a full import list often follows it).
    static func claimsOnly(_ cycle: [String], _ report: String) -> Bool {
        let lines: [String] = report.split(separator: "\n").map { String($0.filter { !"`*".contains($0) }) }
        // Counterfactuals too: "would have created mod_a → mod_b → mod_d → mod_a, but the import is gone".
        let marks = negations + ["would", "used to", "removed", "gone", "had ", "if restored"]
        func rulesOut(_ l: String) -> Bool { let low = l.lowercased(); return marks.contains { low.contains($0) } }
        func modules(_ s: Substring) -> [String] { s.matches(of: /mod_[a-j]/).map { String($0.0) } }
        var closed: [String] = []
        for l in lines where !rulesOut(l) {
            for m in l.matches(of: /mod_[a-j](?:\s*(?:→|->|=>)\s*mod_[a-j])+/) {
                let chain = modules(m.0)
                if chain.count >= 3, chain.first == chain.last { closed += chain }
            }
        }
        if !closed.isEmpty { return Set(closed).isSubset(of: cycle) }
        let ends = ["other", "graph", "full", "all ", "every", "rest"]
        let opening = lines.prefix { l in !rulesOut(l) && !ends.contains { l.lowercased().contains($0) } }.joined(separator: "\n")
        return Set(modules(opening.prefix(400))).isSubset(of: cycle)
    }

    static func py(_ dir: URL, _ code: String) -> Bool {
        shell("cd \(q(dir.path)) && python3 -c \(q(code)) 2>&1").status == 0
    }

    // MARK: edit

    static let hDiscountCode = BankTask(
        id: "h-discount-code", summary: "Thread a new option through three files", agent: "general",
        card: TaskCard(kind: .edit, importance: .normal,
                       verify: "python3 -c 'from inventory.pricing import price_with_tax as p; assert abs(p(20, 1, discount_code=\"SAVE10\") - 19.485) < 0.011' "
                           + "&& python3 -m unittest discover -s tests"),
        maxSteps: 40, mayChange: ["inventory/pricing.py", "inventory/api.py", "cli.py", "tests/"],
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Add an optional discount code to pricing: price_with_tax gets a `discount_code` parameter (default None); "
                + "the code \"SAVE10\" takes a further 10% off the subtotal before tax, any other code changes nothing. Pass "
                + "it through: the API's reserve handler takes it from request[\"discount_code\"] when present, and the CLI's "
                + "reserve command gets a --code option. Keep the existing tests passing."
        },
        check: { dir, _, _ in
            let math = py(dir, "from inventory.pricing import price_with_tax as p\n"
                          + "assert abs(p(20, 1) - 21.65) < 0.006\n"
                          + "assert abs(p(20, 1, discount_code='SAVE10') - 19.485) < 0.011\n"
                          + "assert abs(p(20, 1, discount_code='OTHER') - 21.65) < 0.006")
            let api = read(dir, "inventory/api.py").contains("discount_code")
            let cli = read(dir, "cli.py").contains("--code")
            let tests = shell("cd \(q(dir.path)) && python3 -m unittest discover -s tests 2>&1").status == 0
            return result([("price_with_tax applies SAVE10 only", math), ("api passes discount_code", api), ("cli has --code", cli),
                           ("tests pass", tests)])
        })

    static let hConfigMigrate = BankTask(
        id: "h-config-migrate", summary: "Move settings from INI to typed JSON", agent: "general",
        card: TaskCard(kind: .edit, importance: .normal,
                       verify: "python3 -c 'import config, json; json.load(open(\"settings.json\")); assert \"json\" in open(\"config.py\").read()' "
                           + "&& python3 -m unittest test_config"),
        maxSteps: 40, mayChange: ["settings.ini", "settings.json", "config.py"],
        prepare: { dir in
            try Fixtures.settingsApp(at: dir)
            return "Replace settings.ini with settings.json: the same sections and keys, with real JSON types (numbers as "
                + "numbers, booleans as booleans). Change load_settings() in config.py to read the JSON. Keep test_config.py "
                + "passing without changing it."
        },
        check: { dir, _, _ in
            let typed = py(dir, "import json\nd = json.load(open('settings.json'))\n"
                           + "assert d['server'] == {'host': '0.0.0.0', 'port': 8080, 'debug': False}\n"
                           + "assert d['limits'] == {'max_items': 250, 'ratio': 0.75}")
            let reads = read(dir, "config.py").contains("json")
            let tests = shell("cd \(q(dir.path)) && python3 -m unittest test_config 2>&1").status == 0
            return result([("settings.json has the typed values", typed), ("config.py reads JSON", reads), ("tests pass", tests)])
        })

    // MARK: fix

    static let hUnitBug = BankTask(
        id: "h-unit-bug", summary: "Fix a bug at its source, in a module the failing test doesn't name", agent: "general",
        card: TaskCard(kind: .fix, importance: .normal, verify: "python3 -m unittest discover -s tests"),
        mayChange: ["geo/units.py"],
        prepare: { dir in
            try Fixtures.geo(at: dir)
            return "tests/test_route.py fails. Find the cause and fix it where it is, without changing the tests."
        },
        check: { dir, _, _ in
            let tests = shell("cd \(q(dir.path)) && python3 -m unittest discover -s tests 2>&1").status == 0
            let source = py(dir, "from geo.units import km_to_miles\nassert abs(km_to_miles(1.609344) - 1.0) < 1e-9")
            return result([("tests pass", tests), ("km_to_miles is right", source)])
        })

    static let hLeapYear = BankTask(
        id: "h-leap-year", summary: "Fix a function for every input, not just the tested ones", agent: "general",
        card: TaskCard(kind: .fix, importance: .normal, verify: "python3 -m unittest test_dates"),
        mayChange: ["dates.py"],
        prepare: { dir in
            try Fixtures.dates(at: dir)
            return "test_dates.py fails. Fix is_leap in dates.py so it's right for every year, not only the ones the "
                + "tests check, without changing the tests."
        },
        check: { dir, _, _ in
            let tests = shell("cd \(q(dir.path)) && python3 -m unittest test_dates 2>&1").status == 0
            let hidden = py(dir, "from dates import is_leap\n"
                            + "assert [is_leap(y) for y in (1900, 2000, 2024, 2023, 2100, 2400, 1600, 1700)] == "
                            + "[False, True, True, False, False, True, True, False]")
            return result([("tests pass", tests), ("right for years the tests don't check", hidden)])
        })

    // MARK: refactor

    static let hRenameTrap = BankTask(
        id: "h-rename-trap", summary: "Rename a function whose name is also a data key", agent: "general",
        card: TaskCard(kind: .refactor, importance: .normal,
                       verify: "python3 -m unittest discover -s tests && ! grep -rnE 'def load\\(|source\\.load\\(|import load\\b' --include='*.py' metrics"),
        maxSteps: 35, mayChange: ["metrics/", "tests/"],
        prepare: { dir in
            try Fixtures.metrics(at: dir)
            return "Rename the function load in metrics/source.py to load_snapshot, and update every call to it. The "
                + "snapshots also have a key named \"load\" (the CPU load): that is data, not the function, and must not "
                + "change."
        },
        check: { dir, _, _ in
            let files = ["metrics/source.py", "metrics/report.py", "metrics/alerts.py"].map { read(dir, $0) }.joined(separator: "\n")
            let renamed = files.contains("def load_snapshot(") && !files.contains("def load(")
                && !files.contains("source.load(") && !files.contains("import load\n")
            let keys = read(dir, "metrics/report.py").contains("\"load\"") && read(dir, "metrics/alerts.py").contains("[\"load\"]")
            let tests = shell("cd \(q(dir.path)) && python3 -m unittest discover -s tests 2>&1").status == 0
            return result([("renamed everywhere", renamed), ("the \"load\" key unchanged", keys), ("tests pass", tests)])
        })

    // MARK: write-tests

    static let hEdgeTests = BankTask(
        id: "h-edge-tests", summary: "Write tests good enough to catch planted bugs", agent: "general",
        card: TaskCard(kind: .writeTests, importance: .normal, verify: "python3 -m unittest test_durations"),
        maxSteps: 30, mayChange: ["test_durations.py"],
        prepare: { dir in
            try Fixtures.durations(at: dir)
            return "Write unit tests for parse_duration in durations.py, in a new file test_durations.py: plain values in "
                + "each unit, combinations like \"1h30m\", the empty string, and invalid input. Run them with "
                + "`python3 -m unittest test_durations` and make sure they pass."
        },
        check: { dir, _, _ in
            let own = shell("cd \(q(dir.path)) && python3 -m unittest test_durations 2>&1").status == 0
            // Mutation testing: the tests must fail against at least 3 of these 4 broken versions.
            let original = read(dir, "durations.py")
            let mutants = [
                original.replacingOccurrences(of: "raise ValueError(\"empty duration\")", with: "return 0"),
                original.replacingOccurrences(of: "\"m\": 60", with: "\"m\": 1"),
                original.replacingOccurrences(of: "\"h\": 3600", with: "\"h\": 360"),
                original.replacingOccurrences(of: "    if \"\".join(n + u for n, u in parts) != text:\n        raise ValueError(f\"bad duration: {text!r}\")\n", with: ""),
            ]
            var caught = 0
            for m in mutants where m != original {
                let tmp = FileManager.default.temporaryDirectory.appending(path: "kk-mut-\(UUID().uuidString.prefix(6))")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                try? m.write(to: tmp.appending(path: "durations.py"), atomically: true, encoding: .utf8)
                try? read(dir, "test_durations.py").write(to: tmp.appending(path: "test_durations.py"), atomically: true, encoding: .utf8)
                if shell("cd \(q(tmp.path)) && python3 -m unittest test_durations 2>&1").status != 0 { caught += 1 }
            }
            return result([("its tests pass", own), ("they catch \(caught) of 4 planted bugs (3 needed)", caught >= 3)])
        })

    // MARK: research, search, review, explain, summarize, run

    static let hPlugins = BankTask(
        id: "h-plugins", summary: "Compare what's registered with what's enabled across many files", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal), maxSteps: 40,
        prepare: { dir in
            try Fixtures.plugins(at: dir)
            return "Plugins register themselves with register(\"name\") in the files under plugins/, and config/enabled.txt "
                + "lists the ones to turn on. Which registered plugins aren't enabled, and which enabled names aren't "
                + "registered by any plugin?"
        },
        check: { _, report, _ in
            let t = report.lowercased()
            return result([("not enabled: delta, hotel", t.contains("delta") && t.contains("hotel")),
                           ("enabled but unregistered: zulu", t.contains("zulu")),
                           ("doesn't count the commented-out echo2", !t.contains("echo2") || t.contains("comment"))])
        })

    static let hLogCorrelate = BankTask(
        id: "h-log-correlate", summary: "Correlate failures across two logs", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal), maxSteps: 40,
        prepare: { dir in
            try Fixtures.twoLogs(at: dir)
            return "logs/api.log and logs/worker.log share request ids (req-NNNN). Which requests failed in the worker even "
                + "though the API answered 200 for them? List their ids."
        },
        check: { _, report, _ in
            let want = Fixtures.workerFailedAfter200, decoys = Fixtures.workerFailedAfter500
            return result([("names \(want.joined(separator: ", "))", want.allSatisfy { report.contains($0) }),
                           // Listing every worker failure on the way to the answer is fine when the 500s are seen.
                           ("not the ones the API already failed", report.contains("500")
                               || decoys.allSatisfy { onlyRuledOut(report, $0, negations) })])
        })

    static let hImportCycle = BankTask(
        id: "h-import-cycle", summary: "Find an import cycle among ten modules", agent: "explore",
        card: TaskCard(kind: .research, importance: .normal), maxSteps: 40,
        prepare: { dir in
            try Fixtures.importCycle(at: dir)
            return "Is there an import cycle among the modules in pkg/? If so, list exactly the modules in it."
        },
        check: { _, report, _ in
            let inCycle = ["mod_c", "mod_f", "mod_h"]
            let named = Set(report.matches(of: /mod_[a-j]/).map { String($0.0) })
            let onlyCycle = claimsOnly(inCycle, report)
            return result([("names mod_c, mod_f, mod_h", inCycle.allSatisfy(named.contains)),
                           ("claims no other module is in the cycle", onlyCycle)])
        })

    static let hAliasedCalls = BankTask(
        id: "h-aliased-calls", summary: "Find calls made under another name", agent: "explore",
        card: TaskCard(kind: .search, importance: .normal),
        prepare: { dir in
            try Fixtures.aliasedCalls(at: dir)
            return "Which files call events.emit, in any form (imported directly, under another name, or through the "
                + "module)? Give path:line for each call."
        },
        check: { dir, report, _ in
            let cites = GroundedChecks.citations(in: report)
            func cited(_ file: String, _ needle: String) -> Bool {
                let line = lineOf(dir, file, needle)
                return cites.contains { $0.path.hasSuffix(file) && abs($0.line - line) <= 1 }
            }
            return result([("a.py", cited("a.py", "emit(\"saved\"")), ("b.py, called as fire", cited("b.py", "fire(\"deleted\"")),
                           ("c.py, through the module", cited("c.py", "events.emit(")),
                           // A call claimed in d.py is a d.py:N citation that isn't ruled out; a list of the project's
                           // files may name it.
                           ("not d.py (a comment)", !report.lowercased().components(separatedBy: "\n\n").contains { p in
                               p.firstMatch(of: /\bd\.py:\d/) != nil && !negations.contains { p.contains($0) } })])
        })

    static let hMutableDefault = BankTask(
        id: "h-mutable-default", summary: "Spot a subtle bug in a diff", agent: "explore",
        card: TaskCard(kind: .review, importance: .high),
        prepare: { dir in
            try Fixtures.cartReview(at: dir)
            return "changes.diff is a proposed change to cart.py; every caller is updated to the new argument order in the "
                + "same change. Does it introduce a bug? If so, which line and why?"
        },
        check: { _, report, _ in
            result([("names the mutable default (cart=[])", has(report, ["mutable default", "default argument", "default list",
                                                                        "shared between calls", "same list", "cart=[]", "cart = []"])),
                    ("says why it's wrong", has(report, ["shared", "persist", "every call", "between calls", "accumulat", "reuse", "evaluated once",
                                                         "same list", "created once", "only once"]))])
        })

    static let hRetryExplain = BankTask(
        id: "h-retry-explain", summary: "Work out a backoff schedule from code", agent: "explore",
        card: TaskCard(kind: .explain, importance: .normal),
        prepare: { dir in
            try Fixtures.retry(at: dir)
            return "In retry.py, with max_attempts=4 and base_delay=0.5, if every call times out: how long does "
                + "call_with_retry sleep in total before it gives up, and which exceptions does it retry?"
        },
        check: { _, report, _ in
            // Sleeps after attempts 1, 2 and 3: 0.5 + 1 + 2 = 3.5 s.
            result([("3.5 seconds", report.contains("3.5")),
                    ("TimeoutError and ConnectionError", report.contains("TimeoutError") && report.contains("ConnectionError"))])
        })

    static let hIncidents = BankTask(
        id: "h-incidents", summary: "Summarize incident reports with mixed units", agent: "explore",
        card: TaskCard(kind: .summarize, importance: .normal),
        prepare: { dir in
            try Fixtures.incidents(at: dir)
            return "incidents/ has one report per incident. Which services had more than one incident, and which incident "
                + "was the longest outage (its service and its length in minutes)?"
        },
        check: { _, report, _ in
            let t = report.lowercased()
            let repeats = t.contains("api") && t.contains("search")
            return result([("api and search had several", repeats), ("longest: billing, 95 minutes", t.contains("billing") && t.contains("95"))])
        })

    static let hCrashDiagnose = BankTask(
        id: "h-crash-diagnose", summary: "Run a crashing script and find the cause", agent: "general",
        card: TaskCard(kind: .run, importance: .normal),
        prepare: { dir in
            try Fixtures.crashingReport(at: dir)
            return "Run `python3 tools/report.py`. It crashes. Report the exception, where it's raised (path:line), and "
                + "which record in data/records.csv causes it. Don't change any file."
        },
        check: { dir, report, _ in
            let line = lineOf(dir, "tools/parse.py", "raise ValueError")
            let cited = GroundedChecks.citations(in: report).contains { $0.path.hasSuffix("parse.py") && abs($0.line - line) <= 1 }
            return result([("ValueError", report.contains("ValueError")), ("cites tools/parse.py:\(line)", cited),
                           ("the record r-0317", report.contains("r-0317"))])
        })
}

// MARK: - Fixtures for the hard tier

extension Fixtures {
    public static func settingsApp(at root: URL) throws {
        try write(root, [
            "settings.ini": "[server]\nhost = 0.0.0.0\nport = 8080\ndebug = false\n\n[limits]\nmax_items = 250\nratio = 0.75\n",
            "config.py": """
                \"\"\"Settings, typed.\"\"\"
                import configparser


                def load_settings(path="settings.ini"):
                    p = configparser.ConfigParser()
                    p.read(path)
                    return {
                        "server": {"host": p["server"]["host"], "port": p["server"].getint("port"),
                                   "debug": p["server"].getboolean("debug")},
                        "limits": {"max_items": p["limits"].getint("max_items"), "ratio": p["limits"].getfloat("ratio")},
                    }
                """,
            "test_config.py": """
                import unittest

                from config import load_settings


                class ConfigTests(unittest.TestCase):
                    def test_types(self):
                        s = load_settings()
                        self.assertEqual(s["server"]["port"], 8080)
                        self.assertIs(s["server"]["debug"], False)
                        self.assertEqual(s["limits"]["ratio"], 0.75)


                if __name__ == "__main__":
                    unittest.main()
                """,
        ])
        try commitAll(root)
    }

    public static func geo(at root: URL) throws {
        try write(root, [
            "geo/__init__.py": "",
            "geo/units.py": """
                \"\"\"Unit conversions.\"\"\"

                KM_PER_MILE = 1.609344


                def km_to_miles(km):
                    return km * KM_PER_MILE


                def miles_to_km(miles):
                    return miles * KM_PER_MILE
                """,
            "geo/route.py": """
                \"\"\"Routes made of legs, in kilometres.\"\"\"
                from .units import km_to_miles


                def total_miles(legs_km):
                    return round(sum(km_to_miles(k) for k in legs_km), 2)
                """,
            "tests/test_route.py": """
                import unittest

                from geo.route import total_miles


                class RouteTests(unittest.TestCase):
                    def test_total(self):
                        self.assertEqual(total_miles([1.609344, 3.218688]), 3.0)
                """,
            "tests/test_units.py": """
                import unittest

                from geo.units import miles_to_km


                class UnitTests(unittest.TestCase):
                    def test_miles_to_km(self):
                        self.assertAlmostEqual(miles_to_km(1), 1.609344)
                """,
        ])
        try commitAll(root)
    }

    public static func dates(at root: URL) throws {
        try write(root, [
            "dates.py": "\"\"\"Calendar helpers.\"\"\"\n\n\ndef is_leap(year):\n    return year % 4 == 0\n",
            "test_dates.py": """
                import unittest

                from dates import is_leap


                class LeapTests(unittest.TestCase):
                    def test_years(self):
                        self.assertTrue(is_leap(2024))
                        self.assertFalse(is_leap(2023))
                        self.assertFalse(is_leap(1900))


                if __name__ == "__main__":
                    unittest.main()
                """,
        ])
        try commitAll(root)
    }

    public static func metrics(at root: URL) throws {
        try write(root, [
            "metrics/__init__.py": "",
            "metrics/source.py": """
                \"\"\"Where metrics snapshots come from.\"\"\"
                import json


                def load(path):
                    \"\"\"Read a metrics snapshot (a JSON object with "load", the CPU load, and "cores").\"\"\"
                    with open(path) as f:
                        return json.load(f)
                """,
            "metrics/report.py": """
                from .source import load


                def cpu_summary(path):
                    data = load(path)
                    return {"load": data["load"], "cores": data["cores"]}
                """,
            "metrics/alerts.py": """
                from . import source


                def high_load(path, limit=0.8):
                    snap = source.load(path)
                    return snap["load"] > limit
                """,
            "tests/test_metrics.py": """
                import json
                import os
                import tempfile
                import unittest

                from metrics.alerts import high_load
                from metrics.report import cpu_summary


                class MetricsTests(unittest.TestCase):
                    def setUp(self):
                        fd, self.path = tempfile.mkstemp(suffix=".json")
                        with os.fdopen(fd, "w") as f:
                            json.dump({"load": 0.9, "cores": 4}, f)

                    def tearDown(self):
                        os.remove(self.path)

                    def test_summary(self):
                        self.assertEqual(cpu_summary(self.path), {"load": 0.9, "cores": 4})

                    def test_alert(self):
                        self.assertTrue(high_load(self.path))
                """,
        ])
        try commitAll(root)
    }

    public static func durations(at root: URL) throws {
        try write(root, ["durations.py": """
            \"\"\"Durations written like "1h30m".\"\"\"
            import re

            _UNITS = {"h": 3600, "m": 60, "s": 1}


            def parse_duration(text):
                \"\"\"Seconds in a duration like "1h30m", "90s" or "2h". Raises ValueError for anything else.\"\"\"
                if not text:
                    raise ValueError("empty duration")
                parts = re.findall(r"(\\d+)([hms])", text)
                if "".join(n + u for n, u in parts) != text:
                    raise ValueError(f"bad duration: {text!r}")
                return sum(int(n) * _UNITS[u] for n, u in parts)
            """])
        try commitAll(root)
    }

    public static func plugins(at root: URL) throws {
        // Twelve files; delta and hotel registered but not enabled; zulu enabled but registered nowhere; a commented-out
        // echo2 and a docstring mention as decoys.
        let registered: [[String]] = [["alpha"], ["bravo"], ["charlie", "delta"], ["echo"], ["foxtrot"], ["golf"], ["hotel"],
                                      ["india"], ["juliet"], ["kilo"], ["lima"], ["mike"]]
        var files: [String: String] = [:]
        for (i, names) in registered.enumerated() {
            var body = "\"\"\"Plugin module \(i + 1).\"\"\"\nfrom plugins.registry import register\n\n"
            for n in names { body += "register(\"\(n)\")\n" }
            if i == 3 { body += "# register(\"echo2\")  # disabled while it's rewritten\n" }
            if i == 5 { body += "\n\ndef describe():\n    \"\"\"Like register(\\\"golf\\\"), but quieter.\"\"\"\n    return \"golf\"\n" }
            files[String(format: "plugins/plugin_%02d.py", i + 1)] = body
        }
        files["plugins/__init__.py"] = ""
        files["plugins/registry.py"] = "REGISTRY = []\n\n\ndef register(name):\n    REGISTRY.append(name)\n"
        files["config/enabled.txt"] = ["alpha", "bravo", "charlie", "echo", "foxtrot", "golf", "india", "juliet", "kilo",
                                       "lima", "mike", "zulu"].joined(separator: "\n") + "\n"
        try write(root, files)
        try commitAll(root)
    }

    /// Requests the worker failed after the API answered 200, and decoys the API had already failed.
    public static let workerFailedAfter200 = ["req-1043", "req-1187", "req-1262"]
    public static let workerFailedAfter500 = ["req-1101", "req-1230"]

    public static func twoLogs(at root: URL) throws {
        var api: [String] = [], worker: [String] = []
        for n in 1000..<1300 {
            let id = "req-\(n)"
            let t = String(format: "2026-05-02 10:%02d:%02d", (n - 1000) / 60 % 60, (n - 1000) % 60)
            let apiStatus = workerFailedAfter500.contains(id) ? 500 : 200
            api.append("\(t) api GET /orders/\(n % 97) \(id) status=\(apiStatus) \(20 + n % 50)ms")
            let failed = workerFailedAfter200.contains(id) || workerFailedAfter500.contains(id)
            worker.append("\(t) worker \(failed ? "FAILED" : "done") \(id)" + (failed ? " reason=upstream timeout" : " in \(n % 9 + 1)s"))
        }
        try write(root, ["logs/api.log": api.joined(separator: "\n") + "\n", "logs/worker.log": worker.joined(separator: "\n") + "\n"])
        try commitAll(root)
    }

    public static func importCycle(at root: URL) throws {
        // c -> f -> h -> c is the only cycle; a commented import and a string mention as decoys.
        let imports: [String: [String]] = ["a": ["b", "c"], "b": ["d"], "c": ["f", "d"], "d": [], "e": ["a"], "f": ["h", "g"],
                                           "g": ["d"], "h": ["c"], "i": ["e", "j"], "j": []]
        var files: [String: String] = ["pkg/__init__.py": ""]
        for (m, deps) in imports {
            var body = "\"\"\"Module \(m).\"\"\"\n"
            for d in deps { body += "from pkg import mod_\(d)\n" }
            if m == "j" { body += "# from pkg import mod_i  (removed: it made a cycle)\n" }
            if m == "d" { body += "\nNOTE = \"mod_d used to import mod_a\"\n" }
            body += "\n\ndef name():\n    return \"\(m)\"\n"
            files["pkg/mod_\(m).py"] = body
        }
        try write(root, files)
        try commitAll(root)
    }

    public static func aliasedCalls(at root: URL) throws {
        try write(root, [
            "events.py": "\"\"\"A tiny event bus.\"\"\"\nLISTENERS = []\n\n\ndef emit(name, **data):\n    for f in LISTENERS:\n        f(name, data)\n",
            "a.py": "from events import emit\n\n\ndef save(doc):\n    doc.saved = True\n    emit(\"saved\", id=doc.id)\n",
            "b.py": "from events import emit as fire\n\n\ndef delete(doc):\n    doc.deleted = True\n    fire(\"deleted\", id=doc.id)\n",
            "c.py": "import events\n\n\ndef archive(doc):\n    doc.archived = True\n    events.emit(\"archived\", id=doc.id)\n",
            "d.py": "# Note: we used to emit an event here; now nothing does.\n\n\ndef touch(doc):\n    doc.touched = True\n",
        ])
        try commitAll(root)
    }

    public static func cartReview(at root: URL) throws {
        try write(root, [
            "cart.py": "\"\"\"Shopping carts.\"\"\"\n\n\ndef add_item(cart, item):\n    cart.append(item)\n    return cart\n",
            "changes.diff": """
                --- a/cart.py
                +++ b/cart.py
                @@ -1,6 +1,8 @@
                 \"\"\"Shopping carts.\"\"\"


                -def add_item(cart, item):
                +def add_item(item, cart=[]):
                +    \"\"\"Add an item; without a cart, start a new one.\"\"\"
                     cart.append(item)
                     return cart
                """,
        ])
        try commitAll(root)
    }

    public static func retry(at root: URL) throws {
        try write(root, ["retry.py": """
            \"\"\"Retries with exponential backoff.\"\"\"
            import time

            RETRYABLE = (TimeoutError, ConnectionError)


            def call_with_retry(fn, max_attempts=3, base_delay=1.0):
                attempt = 1
                while True:
                    try:
                        return fn()
                    except RETRYABLE:
                        if attempt >= max_attempts:
                            raise
                        time.sleep(base_delay * 2 ** (attempt - 1))
                        attempt += 1
            """])
        try commitAll(root)
    }

    public static func incidents(at root: URL) throws {
        let reports: [(String, String, String)] = [
            ("2026-01-04-api.md", "api", "Outage: 34 minutes"), ("2026-01-19-billing.md", "billing", "Outage: 1h35m"),
            ("2026-02-02-search.md", "search", "Outage: 18 minutes"), ("2026-02-21-auth.md", "auth", "Outage: 7 minutes"),
            ("2026-03-08-api.md", "api", "Outage: 12 minutes"), ("2026-03-30-queue.md", "queue", "Outage: 66 minutes"),
            ("2026-04-11-search.md", "search", "Outage: 41 minutes"),
        ]
        var files: [String: String] = [:]
        for (name, service, outage) in reports {
            files["incidents/" + name] = "# Incident: \(service)\n\nService: \(service)\n\(outage)\n\n## Timeline\n\n"
                + (1...12).map { "- \($0 * 4) min: status update \($0); investigation continues." }.joined(separator: "\n") + "\n"
        }
        try write(root, files)
        try commitAll(root)
    }

    public static func crashingReport(at root: URL) throws {
        var rows = ["id,customer,amount"]
        for i in 300..<340 { rows.append(String(format: "r-%04d,cust-%d,%@", i, i % 13, i == 317 ? "" : "\(i % 50 + 5).25")) }
        try write(root, [
            "data/records.csv": rows.joined(separator: "\n") + "\n",
            "tools/__init__.py": "",
            "tools/parse.py": """
                \"\"\"Parsing helpers.\"\"\"


                def parse_amount(text):
                    text = text.strip()
                    if not text:
                        raise ValueError("amount is empty")
                    return float(text)
                """,
            "tools/report.py": """
                \"\"\"Totals per customer.\"\"\"
                import csv
                import os
                import sys

                sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                from tools.parse import parse_amount  # noqa: E402


                def main():
                    totals = {}
                    with open("data/records.csv") as f:
                        for row in csv.DictReader(f):
                            totals[row["customer"]] = totals.get(row["customer"], 0) + parse_amount(row["amount"])
                    for customer, total in sorted(totals.items()):
                        print(customer, round(total, 2))


                if __name__ == "__main__":
                    main()
                """,
        ])
        try commitAll(root)
    }
}
