import AgentCore
import Foundation

/// Rates with intervals, and agreement beyond chance (EVAL_PLAN.md E3).
public enum Stats {
    /// The 95% Wilson interval for k of n (nil when n is 0).
    public static func wilson(_ k: Int, _ n: Int, z: Double = 1.96) -> (p: Double, lo: Double, hi: Double)? {
        guard n > 0 else { return nil }
        let nn = Double(n), p = Double(k) / nn, z2 = z * z
        let center = (p + z2 / (2 * nn)) / (1 + z2 / nn)
        let half = z * (p * (1 - p) / nn + z2 / (4 * nn * nn)).squareRoot() / (1 + z2 / nn)
        return (p, max(0, center - half), min(1, center + half))
    }

    /// Cohen's kappa for two yes/no raters (nil when undefined).
    public static func kappa(_ pairs: [(Bool, Bool)]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        let n = Double(pairs.count)
        let agree = Double(pairs.filter { $0.0 == $0.1 }.count) / n
        let a1 = Double(pairs.filter(\.0).count) / n, b1 = Double(pairs.filter(\.1).count) / n
        let chance = a1 * b1 + (1 - a1) * (1 - b1)
        return chance >= 1 ? nil : (agree - chance) / (1 - chance)
    }

    /// "62% (48–75%) 21/34", or "–".
    public static func rate(_ k: Int, _ n: Int) -> String {
        guard let w = wilson(k, n) else { return "–" }
        return String(format: "%.0f%% (%.0f–%.0f%%) %d/%d", w.p * 100, w.lo * 100, w.hi * 100, k, n)
    }
}

/// The tables of EVAL_RESULTS.md, from a run store: models, judges, failure kinds, grounded checks.
public enum EvalReport {
    /// A judge's verdict counts as "fail" at 0 or 1, "pass" at 2 or 3.
    static func fails(_ o: JudgeOutcome) -> Bool? { o.verdict.map { $0 <= 1 } }

    /// A stray edit on a read-only task can't happen (explore agents have no tools that write), so those copies are
    /// left out of the tables; a first report counted them, and they hid how well judges catch everything else.
    public static func realistic(_ r: StoredRun) -> Bool { !(r.degradation == Degradation.strayEdit.rawValue && r.agent == "explore") }

    /// One configuration's place on the cost–quality plane, from its real runs (infrastructure failures left out).
    public struct FrontierRow: Sendable {
        public var model: String
        public var runs: Int
        public var passes: Int
        public var lower: Double
        public var listPerRun: Double?
        public var perSuccess: Double?
        public var seconds: Double
    }

    /// The mean list price of `rs`'s priced runs, or nil when none is priced.
    static func perRun(_ rs: [StoredRun]) -> Double? {
        let priced = rs.compactMap(\.listPrice)
        return priced.isEmpty ? nil : priced.reduce(0, +) / Double(priced.count)
    }

    /// What a pass costs: the mean priced run times the runs, over the passes (an unpriced run counts at the mean, not
    /// at $0). The one formula for the frontier and the models table (BUG_HUNT_2026-11-02.md item 49).
    static func perSuccess(_ rs: [StoredRun]) -> Double? {
        let passes = rs.filter(\.gold.passed).count
        return perRun(rs).flatMap { passes == 0 ? nil : $0 * Double(rs.count) / Double(passes) }
    }

    public static func frontier(_ real: [StoredRun]) -> [FrontierRow] {
        Dictionary(grouping: real, by: \.model).map { m, rs in
            let passes = rs.filter(\.gold.passed).count
            return FrontierRow(model: m, runs: rs.count, passes: passes, lower: Stats.wilson(passes, rs.count)?.lo ?? 0,
                               listPerRun: perRun(rs), perSuccess: perSuccess(rs),
                               seconds: rs.map(\.seconds).reduce(0, +) / Double(max(1, rs.count)))
        }.sorted { $0.model < $1.model }
    }

    /// The frontier as CSV, for plotting: one row per configuration.
    public static func frontierCSV(_ store: RunStore) -> String {
        let real = store.runs().filter { $0.infra == nil && $0.degradation == nil }
        var lines = ["model,runs,passes,pass_rate,lower_95,list_per_run,per_success,mean_seconds"]
        for r in frontier(real) {
            lines.append([r.model, "\(r.runs)", "\(r.passes)", String(format: "%.4f", Double(r.passes) / Double(max(1, r.runs))),
                          String(format: "%.4f", r.lower), r.listPerRun.map { String(format: "%.6f", $0) } ?? "",
                          r.perSuccess.map { String(format: "%.6f", $0) } ?? "", String(format: "%.1f", r.seconds)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func markdown(_ store: RunStore) -> String {
        let all = store.runs()
        let stored = all.filter { $0.infra == nil }
        let runs = stored.filter(realistic)
        let judgments = Dictionary(grouping: runs.flatMap { store.judgments(of: $0.id) }, by: \.run)
        var md: [String] = []
        func table(_ header: [String], _ rows: [[String]]) {
            md.append("| " + header.joined(separator: " | ") + " |")
            md.append("|" + header.map { _ in "---" }.joined(separator: "|") + "|")
            for r in rows { md.append("| " + r.joined(separator: " | ") + " |") }
            md.append("")
        }
        let real = runs.filter { $0.degradation == nil }
        let degraded = runs.filter { $0.degradation != nil }
        md.append("Runs: \(real.count) recorded, \(degraded.count) degraded copies; \(judgments.values.map(\.count).reduce(0, +)) judgments."
                  + (stored.count > runs.count ? " (\(stored.count - runs.count) stray-edit copies of read-only tasks left out: explore agents can't edit.)" : ""))
        let infra = all.filter { $0.infra != nil }
        if !infra.isEmpty {
            let byModel = Dictionary(grouping: infra, by: \.model)
            md.append("Left out as infrastructure failures (no provider, a model that won't load, server errors before any work, "
                      + "after a retry): \(infra.count) runs of \(byModel.count) configurations"
                      + (byModel.count <= 12 ? ": " + byModel.keys.sorted().joined(separator: ", ") : "") + ".")
        }
        md.append("")

        // The cheapest configuration whose success rate's lower bound clears each floor (COST_FLOOR_PLAN.md).
        let plane = frontier(real)
        if plane.contains(where: { $0.listPerRun != nil }) {
            md.append("### Cheapest above the floor")
            md.append("")
            md.append("Configurations whose 95% Wilson lower bound on success clears the floor, cheapest per run first (list "
                      + "price; local models are timed, not priced, and are listed after).")
            md.append("")
            for floor in [0.80, 0.90, 0.95] {
                let ok = plane.filter { $0.lower >= floor }
                let priced = ok.filter { $0.listPerRun != nil }.sorted { $0.listPerRun! < $1.listPerRun! }
                let local = ok.filter { $0.listPerRun == nil }
                md.append("**\(Int(floor * 100))%**: " + (priced.isEmpty ? "none priced" : priced.prefix(6).map {
                    String(format: "%@ $%.4f/run, $%.4f/success (%d/%d, lower %.0f%%)", $0.model, $0.listPerRun!, $0.perSuccess ?? 0,
                           $0.passes, $0.runs, $0.lower * 100)
                }.joined(separator: "; ")) + (local.isEmpty ? "" : "; local: " + local.map(\.model).joined(separator: ", ")))
                md.append("")
            }
        }

        // Subagent models, from real runs.
        md.append("### Subagent models (real runs, all trials)")
        md.append("")
        let models = Array(Set(real.map(\.model))).sorted()
        table(["model", "pass rate (95% CI)", "mean s", "mean steps", "mean tokens in/out", "list $ per run", "$ per success"], models.map { m in
            let rs = real.filter { $0.model == m }
            let priced = rs.compactMap(\.listPrice)
            let passes = rs.filter(\.gold.passed).count
            let perSuccess = Self.perSuccess(rs).map { String(format: "%.4f", $0) } ?? "–"
            return [m, Stats.rate(passes, rs.count),
                    String(format: "%.0f", rs.map(\.seconds).reduce(0, +) / Double(max(1, rs.count))),
                    String(format: "%.1f", Double(rs.map(\.steps).reduce(0, +)) / Double(max(1, rs.count))),
                    "\(rs.map(\.promptTokens).reduce(0, +) / max(1, rs.count))/\(rs.map(\.completionTokens).reduce(0, +) / max(1, rs.count))",
                    priced.isEmpty ? "–" : String(format: "%.4f", priced.reduce(0, +) / Double(priced.count)), perSuccess]
        })
        let kinds = Array(Set(real.map(\.kind))).sorted()
        md.append("Passes by kind:")
        md.append("")
        table(["model"] + kinds, models.map { m in
            [m] + kinds.map { k in
                let rs = real.filter { $0.model == m && $0.kind == k }
                return rs.isEmpty ? "–" : "\(rs.filter(\.gold.passed).count)/\(rs.count)"
            }
        })

        // Judges against gold, on every judged run.
        let judged = runs.filter { judgments[$0.id] != nil }
        let judges = Array(Set(judgments.values.flatMap { $0.map { "\($0.outcome.judge) (\($0.outcome.path))" } })).sorted()
        func outcomes(_ key: String) -> [(StoredRun, JudgeOutcome)] {
            judged.compactMap { r in
                judgments[r.id]?.last(where: { "\($0.outcome.judge) (\($0.outcome.path))" == key }).map { (r, $0.outcome) }
            }
        }
        md.append("### Judges against gold")
        md.append("")
        md.append("A verdict of 0–1 is \"fail\", 2–3 \"pass\". Failures are real failed runs and degraded copies.")
        md.append("")
        // The runs every judge rated: the fair comparison when judges were given different subsets.
        let common = Set(judged.filter { r in judges.allSatisfy { key in judgments[r.id]?.contains { "\($0.outcome.judge) (\($0.outcome.path))" == key } == true } }.map(\.id))
        func judgeRows(_ only: Set<String>?) -> [[String]] { judges.map { key in
            let pairs = outcomes(key).filter { only == nil || only!.contains($0.0.id) }
            let rated = pairs.compactMap { r, o in fails(o).map { (r, $0, o) } }
            let fl = rated.filter { !$0.0.gold.passed }, ps = rated.filter(\.0.gold.passed)
            let kap = Stats.kappa(rated.map { ($0.1, !$0.0.gold.passed) })
            let prices = pairs.compactMap(\.1.listPrice)
            return [key, "\(pairs.count)", "\(pairs.count - rated.count)",
                    rated.isEmpty ? "–" : String(format: "%.0f%%", Double(rated.filter { $0.1 == !$0.0.gold.passed }.count) * 100 / Double(rated.count)),
                    kap.map { String(format: "%.2f", $0) } ?? "–",
                    Stats.rate(fl.filter(\.1).count, fl.count), Stats.rate(ps.filter(\.1).count, ps.count),
                    "\(pairs.filter { $0.1.checkedConfirmed == false }.count)",
                    prices.isEmpty ? "–" : String(format: "%.3f", prices.reduce(0, +))]
        } }
        let header = ["judge (path)", "runs", "no verdict", "agreement", "kappa", "failures caught (95% CI)", "passes failed (95% CI)",
                      "claimed unchecked", "list $"]
        md.append("All runs each judge rated:")
        md.append("")
        table(header, judgeRows(nil))
        if !common.isEmpty, common.count < judged.count {
            let f = judged.filter { common.contains($0.id) && !$0.gold.passed }.count
            md.append("Only the \(common.count) runs every judge rated (\(f) failures):")
            md.append("")
            table(header, judgeRows(common))
        }

        // The grounded checks, and each judge combined with them (a grounded hard failure is a fail).
        md.append("### Grounded checks, and judges combined with them")
        md.append("")
        let fl = judged.filter { !$0.gold.passed }, ps = judged.filter(\.gold.passed)
        var rows: [[String]] = [
            ["checks at the run's end", Stats.rate(fl.filter(\.checks.isHardFailure).count, fl.count),
             Stats.rate(ps.filter(\.checks.isHardFailure).count, ps.count)],
            ["checks and the re-run check", Stats.rate(fl.filter(\.groundedFailure).count, fl.count),
             Stats.rate(ps.filter(\.groundedFailure).count, ps.count)],
        ]
        for key in judges {
            let pairs = outcomes(key)
            func combined(_ r: StoredRun, _ o: JudgeOutcome) -> Bool { r.groundedFailure || (fails(o) ?? false) }
            let f = pairs.filter { !$0.0.gold.passed }, p = pairs.filter(\.0.gold.passed)
            rows.append(["grounded + \(key)", Stats.rate(f.filter { combined($0.0, $0.1) }.count, f.count),
                         Stats.rate(p.filter { combined($0.0, $0.1) }.count, p.count)])
        }
        table(["", "failures caught (95% CI)", "passes failed (95% CI)"], rows)

        // Failures caught, by where the failure comes from.
        md.append("### Failures caught, by kind of failure")
        md.append("")
        let sources = Array(Set(judged.compactMap(\.failureSource))).sorted()
        table(["failure"] + ["grounded"] + judges, sources.map { s in
            let rs = judged.filter { $0.failureSource == s }
            return [s, "\(rs.filter(\.groundedFailure).count)/\(rs.count)"] + judges.map { key in
                let pairs = outcomes(key).filter { $0.0.failureSource == s }
                let rated = pairs.compactMap { fails($0.1) }
                return rated.isEmpty ? "–" : "\(rated.filter { $0 }.count)/\(rated.count)"
            }
        })

        // Self against cross: a judge on its own model's runs, and on others'.
        md.append("### Judging its own model's runs, and others'")
        md.append("")
        table(["judge (path)", "own runs: agreement", "own runs: failures caught", "others' runs: agreement", "others' runs: failures caught"],
              judges.map { key in
            let judgeModel = String(key.prefix { $0 != " " })
            let pairs = outcomes(key).compactMap { r, o in fails(o).map { (r, $0) } }
            func cells(_ ps: [(StoredRun, Bool)]) -> [String] {
                let f = ps.filter { !$0.0.gold.passed }
                let agree = ps.filter { $0.1 == !$0.0.gold.passed }.count
                return [ps.isEmpty ? "–" : "\(agree)/\(ps.count)", Stats.rate(f.filter(\.1).count, f.count)]
            }
            return [key] + cells(pairs.filter { $0.0.model == judgeModel }) + cells(pairs.filter { $0.0.model != judgeModel })
        })
        return md.joined(separator: "\n")
    }
}
