import Foundation
import AgentCore

/// A4's offline measurement: which escalation triggers would have caught a cheap model's failures, from runs already
/// stored with their outcome (gold), checks, transcript, and (bank1) the judges' verdicts and (A6) reviews. No model
/// is called. Then a cascade replay: a run on the cheaper model is escalated, when a trigger fires, to the stored run of
/// the same task and trial on the next model up, and the pair is scored as the cascade would have ended.
public enum TriggerSim {
    /// What a trigger can see about one stored run.
    public struct Signals: Codable, Sendable {
        public var run: String
        public var task: String
        public var kind: String
        public var model: String
        public var trial: Int
        public var passed: Bool
        /// What it cost (the charge, else the list price; nil: unpriced) and how long it took.
        public var cost: Double?
        public var seconds: Double
        public var verifyFailed = false
        public var recheckFailed = false
        public var hard = false
        public var stopped = false
        public var lastCheckFailed = false
        public var unfinishedTodos = false
        public var unmentioned = false
        public var repeated = false
        /// Finished with no change on a request that asked for one (`Escalation.gaveUp`).
        public var gaveUp = false
        /// A judge's verdict (0–3) by "path judge" ("grader gemini-3.8-flash").
        public var judges: [String: Int] = [:]
        /// A reviewer's verdict by reviewer.
        public var reviews: [String: String] = [:]
        /// What each judgment and review cost (list price), by the same names.
        public var judgeCosts: [String: Double] = [:]
        public var reviewCosts: [String: Double] = [:]
    }

    public static func signals(_ run: StoredRun, store: RunStore, reviews: [ReviewSim.Row] = []) -> Signals {
        var s = Signals(run: run.id, task: run.task, kind: run.kind, model: run.model, trial: run.trial, passed: run.gold.passed,
                        cost: run.runRecord?.totals.charged ?? run.runRecord?.totals.spent ?? run.listPrice, seconds: run.seconds)
        s.verifyFailed = run.checks.verifyCommand != nil && (run.checks.verifyExitCode ?? 1) != 0
        s.recheckFailed = run.rechecked && (run.recheckExit ?? 0) != 0
        s.hard = run.checks.isHardFailure
        // As in sessions (`Escalation.reasons`): the step limit, a cut-off reply, a loop; not a cost limit, a stop, a
        // denial or a server error.
        s.stopped = run.stop == "stepLimit" || run.stop == "truncated" || (run.stop.hasPrefix("turnStopped") && run.stop.hasSuffix("repetition)"))
        let signals = RunSignals.evaluate(run.transcript, request: run.prompt, card: TaskCard(kind: TaskCard.Kind(rawValue: run.kind)))
        // As in sessions (`Escalation.reasons`): only after the run changed files.
        s.lastCheckFailed = signals.lastCheckFailed && !run.checks.filesChanged.isEmpty
        s.unfinishedTodos = !signals.unfinishedTodos.isEmpty
        s.unmentioned = !run.checks.unmentionedChanges.isEmpty
        s.repeated = run.checks.repeatedCalls > 0
        // The run's own record has its stop, denials and tools. A subagent run has no snapshots: its change is its
        // saved tree against the commit it started from (commands' edits included), worked out only for a run that
        // could fire.
        if var record = run.runRecord, signals.changeAsked == true, record.outcome.stop == "completed", record.snapshots == nil,
           let dir = try? store.restore(run) {
            defer { try? FileManager.default.removeItem(at: dir) }
            record.snapshots = RunSnapshotRefs(start: "", end: "", skipped: [], changed: ReviewSim.ownDiff(dir).map { !$0.isEmpty })
            s.gaveUp = Escalation.gaveUp(record, signals: signals)
        }
        for j in store.judgments(of: run.id) {
            guard let v = j.outcome.verdict else { continue }
            let name = j.outcome.judge.split(separator: ":").last.map { String($0.split(separator: "/").last ?? $0) } ?? j.outcome.judge
            s.judges["\(j.outcome.path) \(name)"] = v
            s.judgeCosts["\(j.outcome.path) \(name)"] = j.outcome.listPrice ?? 0
        }
        for r in reviews where r.run == run.id {
            if let v = r.verdict { s.reviews[r.reviewer] = v }
            s.reviewCosts[r.reviewer] = r.charged ?? r.listPrice ?? 0
        }
        return s
    }

    /// A trigger: its name and whether it fires on a run.
    public struct Trigger: Sendable {
        public var name: String
        public var fires: @Sendable (Signals) -> Bool
        /// What checking a run costs (a judge's or reviewer's request); grounded signals are free.
        public var cost: @Sendable (Signals) -> Double = { _ in 0 }

        public init(name: String, fires: @escaping @Sendable (Signals) -> Bool, cost: @escaping @Sendable (Signals) -> Double = { _ in 0 }) {
            self.name = name
            self.fires = fires
            self.cost = cost
        }
    }

    /// The grounded triggers, then one per judge (verdict 0 or 1) and one per reviewer (a problem found) seen in `rows`,
    /// then combinations.
    public static func triggers(for rows: [Signals]) -> [Trigger] {
        var t: [Trigger] = [
            Trigger(name: "the card's check failed") { $0.verifyFailed },
            Trigger(name: "the re-run check failed") { $0.recheckFailed },
            Trigger(name: "a hard failure") { $0.hard },
            Trigger(name: "stopped early") { $0.stopped },
            Trigger(name: "its last check failed") { $0.lastCheckFailed },
            Trigger(name: "unfinished todos") { $0.unfinishedTodos },
            Trigger(name: "changed files it didn't mention") { $0.unmentioned },
            Trigger(name: "repeated a call") { $0.repeated },
            Trigger(name: "changed nothing on a change request") { $0.gaveUp },
        ]
        let grounded: @Sendable (Signals) -> Bool = { s in s.verifyFailed || s.recheckFailed || s.hard || s.stopped || s.lastCheckFailed || s.unfinishedTodos || s.gaveUp }
        t.append(Trigger(name: "any grounded signal", fires: grounded))
        let judges = Set(rows.flatMap(\.judges.keys)).sorted()
        for j in judges {
            t.append(Trigger(name: "judge: \(j) ≤ 1", fires: { ($0.judges[j] ?? 3) <= 1 }, cost: { $0.judgeCosts[j] ?? 0 }))
        }
        let reviewers = Set(rows.flatMap(\.reviews.keys)).sorted()
        for r in reviewers {
            t.append(Trigger(name: "review: \(r) found a problem", fires: { ($0.reviews[r] ?? "looks_right") != "looks_right" },
                             cost: { $0.reviewCosts[r] ?? 0 }))
        }
        for j in judges {
            t.append(Trigger(name: "grounded or \(j) ≤ 1", fires: { grounded($0) || ($0.judges[j] ?? 3) <= 1 }, cost: { $0.judgeCosts[j] ?? 0 }))
        }
        for r in reviewers {
            t.append(Trigger(name: "grounded or review \(r)", fires: { grounded($0) || ($0.reviews[r] ?? "looks_right") != "looks_right" },
                             cost: { $0.reviewCosts[r] ?? 0 }))
        }
        return t
    }

    /// Precision (gold failures among the runs it fires on) and recall (of all gold failures) for each trigger, over the
    /// runs where the trigger's inputs exist (a judge's or reviewer's trigger only over the runs it judged).
    public static func table(_ rows: [Signals], title: String) -> String {
        var s = "### \(title)\n\n\(rows.count) runs, \(rows.filter { !$0.passed }.count) gold failures.\n\n"
        s += "| trigger | runs it applies to | fires | failures it catches | precision | recall |\n|---|---|---|---|---|---|\n"
        for t in triggers(for: rows) {
            let applies = rows.filter { r in
                if t.name.contains("judge") || (t.name.contains(" ≤ 1") && t.name.hasPrefix("grounded")) {
                    return r.judges.keys.contains { t.name.contains($0) }
                }
                if t.name.contains("review") { return r.reviews.keys.contains { t.name.contains($0) } }
                return true
            }
            guard !applies.isEmpty else { continue }
            let fired = applies.filter(t.fires)
            let caught = fired.filter { !$0.passed }.count
            let failures = applies.filter { !$0.passed }.count
            s += "| \(t.name) | \(applies.count) | \(fired.count) | \(caught) | \(pct(caught, fired.count)) | \(pct(caught, failures)) |\n"
        }
        return s
    }

    /// A replayed cascade's totals (`ladder`), and the first and top models' alone, over the same runs.
    public struct Cascade: Sendable {
        public var runs = 0, passed = 0, escalated = 0, needed = 0, escalatedNeeded = 0
        public var cost = 0.0, seconds = 0.0
        public var nextAlonePassed = 0
        public var nextAloneCost = 0.0, nextAloneSeconds = 0.0
        public var cheapAlonePassed = 0
        public var cheapAloneCost = 0.0
    }

    /// A ladder replayed: each run of the first level goes up one level at a time while `fires` says so, to the stored
    /// run of the same task and trial; only tasks and trials every level has count.
    public static func ladder(_ levels: [[Signals]], fires: @escaping @Sendable (Signals) -> Bool) -> Cascade {
        ladder(levels, Trigger(name: "", fires: fires))
    }

    /// The replay, with what checking each run along the way cost (a judge's request on every run it looked at).
    public static func ladder(_ levels: [[Signals]], _ trigger: Trigger) -> Cascade {
        let fires = trigger.fires
        guard let first = levels.first else { return Cascade() }
        let byKey = levels.map { Dictionary($0.map { ("\($0.task)|\($0.trial)", $0) }, uniquingKeysWith: { a, _ in a }) }
        var c = Cascade()
        for r in first {
            let key = "\(r.task)|\(r.trial)"
            let chain = byKey.compactMap { $0[key] }
            guard chain.count == levels.count, let top = chain.last else { continue }
            c.runs += 1
            c.cheapAlonePassed += r.passed ? 1 : 0
            c.cheapAloneCost += r.cost ?? 0
            c.nextAlonePassed += top.passed ? 1 : 0
            c.nextAloneCost += top.cost ?? 0
            c.nextAloneSeconds += top.seconds
            if !r.passed { c.needed += 1 }
            var i = 0
            c.cost += r.cost ?? 0
            c.seconds += r.seconds
            while i + 1 < chain.count {
                c.cost += trigger.cost(chain[i])
                guard fires(chain[i]) else { break }
                if i == 0 { c.escalated += 1; if !r.passed { c.escalatedNeeded += 1 } }
                i += 1
                c.cost += chain[i].cost ?? 0
                c.seconds += chain[i].seconds
            }
            c.passed += chain[i].passed ? 1 : 0
        }
        return c
    }

    /// The ladder table: every trigger (it decides each step), never, the oracle and always, and the top model alone.
    public static func ladderTable(_ levels: [[Signals]], title: String) -> String {
        var s = "### \(title)\n\n| trigger | escalated from the first | of them needed | needed, missed | passed | a run | a success | seconds a run |\n|---|---|---|---|---|---|---|---|\n"
        let base = ladder(levels) { _ in false }
        guard base.runs > 0 else { return s + "(no runs every level has)\n" }
        func row(_ name: String, _ c: Cascade) {
            s += "| \(name) | \(c.escalated) | \(c.escalatedNeeded) | \(c.needed - c.escalatedNeeded) | \(c.passed)/\(c.runs) (\(pct(c.passed, c.runs))) | "
                + money(c.cost / Double(c.runs)) + " | " + (c.passed == 0 ? "–" : money(c.cost / Double(c.passed)))
                + String(format: " | %.0f |\n", c.seconds / Double(c.runs))
        }
        row("never (the first model alone)", base)
        for t in triggers(for: levels.flatMap { $0 }) { row(t.name, ladder(levels, t)) }
        row("oracle (exactly the failures)", ladder(levels) { !$0.passed })
        row("always (up to the top)", ladder(levels) { _ in true })
        s += "| **the top model alone** | – | – | – | \(base.nextAlonePassed)/\(base.runs) (\(pct(base.nextAlonePassed, base.runs))) | "
            + money(base.nextAloneCost / Double(base.runs)) + " | " + (base.nextAlonePassed == 0 ? "–" : money(base.nextAloneCost / Double(base.nextAlonePassed)))
            + String(format: " | %.0f |\n", base.nextAloneSeconds / Double(base.runs))
        return s
    }

    static func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((Double(a) * 100 / Double(b)).rounded()))%" }
    static func money(_ v: Double) -> String { v == 0 ? "$0" : v >= 0.01 ? String(format: "$%.3f", v) : String(format: "$%.5f", v) }
}
