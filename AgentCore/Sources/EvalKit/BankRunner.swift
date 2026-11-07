import AgentCore
import Foundation

/// A judge's verdict on one bank run, beside the gold check (for calibrating judges).
public struct JudgeOutcome: Codable, Sendable {
    /// The judge's model (`endpoint:model`), and how it judged: `parent` (the end-of-run rating, as in a real run) or
    /// `grader` (the prompt for important tasks).
    public var judge: String
    public var path: String
    /// Nil when no verdict came back.
    public var verdict: Int?
    public var checked: String?
    public var checkedConfirmed: Bool?
    public var issues: [String]
    public var note: String?
    public var seconds: Double
    public var listPrice: Double?
    /// The whole judgment as recorded (prompt and reply included), for tuning judges later.
    public var judgment: RunJudgment?
}

/// One bank task run on one model: the gold outcome, the automatic checks, and each judge's verdict.
public struct BankResult: Codable, Sendable {
    public var task: String
    public var kind: String
    public var agent: String
    public var card: TaskCard
    public var model: String
    public var trial: Int
    public var gold: CheckResult
    public var checks: GroundedChecks
    public var judges: [JudgeOutcome]
    public var stop: String
    public var seconds: Double
    public var steps: Int
    public var toolCalls: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var listPrice: Double?
    public var unpricedRequests: Int
    public var report: String
    /// With degradation: the run made wrong on purpose (digits in the report changed, a change task's files reset),
    /// its gold check (it must fail to count), and the judges' verdicts on it. Known failures to calibrate against.
    public var degradedReport: String?
    public var degradedGold: CheckResult?
    public var degradedJudges: [JudgeOutcome]?
    public var degradedChecks: GroundedChecks?
    public var runRecord: AgentRunRecord?
    public var transcript: [ChatMessage]?
}

/// How well one judge's verdicts matched gold over a set of bank runs.
public struct JudgeCalibrationRow: Codable, Sendable {
    public var judge: String
    public var path: String
    public var runs: Int
    /// Runs that got a verdict.
    public var verdicts: Int
    /// Verdict ≥ 2 agrees with a gold pass, ≤ 1 with a gold fail.
    public var agreement: Double?
    /// Of the gold failures, the share the judge caught (verdict ≤ 1); of the gold passes, the share it failed.
    public var failureRecall: Double?
    public var falseAlarms: Double?
    /// Ratings that claimed a check but made none.
    public var unconfirmedClaims: Int
    public var listPrice: Double?

    public static func rows(_ results: [BankResult]) -> [JudgeCalibrationRow] {
        let keys = Set(results.flatMap { r in r.judges.map { "\($0.judge)\u{0}\($0.path)" } }).sorted()
        var rows = keys.map { key -> JudgeCalibrationRow in
            let parts = key.split(separator: "\u{0}").map(String.init)
            func mine(_ js: [JudgeOutcome]?) -> JudgeOutcome? { js?.first { "\($0.judge)\u{0}\($0.path)" == key } }
            // Each run, and each degraded copy whose gold check failed (a known failure).
            let pairs = results.compactMap { r in mine(r.judges).map { (r.gold.passed, $0) } }
                + results.compactMap { r in r.degradedGold?.passed == false ? mine(r.degradedJudges).map { (false, $0) } : nil }
            let judged = pairs.filter { $0.1.verdict != nil }
            func share(_ n: Int, _ d: Int) -> Double? { d == 0 ? nil : Double(n) / Double(d) }
            let fails = judged.filter { !$0.0 }, passes = judged.filter(\.0)
            let prices = pairs.compactMap(\.1.listPrice)
            return JudgeCalibrationRow(
                judge: parts[0], path: parts[1], runs: pairs.count, verdicts: judged.count,
                agreement: share(judged.filter { ($0.1.verdict! >= 2) == $0.0 }.count, judged.count),
                failureRecall: share(fails.filter { $0.1.verdict! <= 1 }.count, fails.count),
                falseAlarms: share(passes.filter { $0.1.verdict! <= 1 }.count, passes.count),
                unconfirmedClaims: pairs.filter { $0.1.checkedConfirmed == false }.count,
                listPrice: prices.isEmpty ? nil : prices.reduce(0, +))
        }
        // The automatic checks are a judge too: a hard failure is their "fail".
        if !results.isEmpty {
            // Each run, and each degraded copy whose gold failed.
            let all = results.map { ($0.gold.passed, $0.checks) }
                + results.compactMap { r in r.degradedGold?.passed == false ? r.degradedChecks.map { (false, $0) } : nil }
            let fails = all.filter { !$0.0 }, passes = all.filter(\.0)
            func share(_ n: Int, _ d: Int) -> Double? { d == 0 ? nil : Double(n) / Double(d) }
            rows.insert(JudgeCalibrationRow(
                judge: "checks", path: "hard failure", runs: all.count, verdicts: all.count,
                agreement: share(all.filter { $0.1.isHardFailure != $0.0 }.count, all.count),
                failureRecall: share(fails.filter(\.1.isHardFailure).count, fails.count),
                falseAlarms: share(passes.filter(\.1.isHardFailure).count, passes.count),
                unconfirmedClaims: 0, listPrice: nil), at: 0)
        }
        return rows
    }
}

extension Runner {
    /// Runs one bank task on `target` as a subagent would (its agent's tools, the subagent prompt, the task with its
    /// card's check), checks it against gold, then asks each judge in `judges` for a verdict by each of `paths`.
    public static func runBank(_ task: BankTask, on target: ModelTarget, trial: Int, judges: [ModelTarget] = [],
                               paths: Set<String> = ["parent", "grader"], degrade: Bool = false,
                               limits: TurnLimits = TurnLimits(maxTokens: 4096, wallClock: 300), sandbox: SandboxUse = .fullAuto,
                               makeClient: ClientFactory = defaultClient,
                               log: @escaping @Sendable (String) -> Void = { _ in }) async -> BankResult {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-bank-\(task.id)-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await performSubagentTask(task, on: target, dir: dir, limits: limits, sandbox: sandbox, makeClient: makeClient, log: log)
        let (prompt, record, report, config, workspace) = (r.prompt, r.record, r.report, r.config, r.workspace)
        let agent = AgentDefinition.builtIns.first { $0.name == task.agent } ?? .general
        // What the judges see is the checks at the run's end; the re-run comes later (as in a real run, where the
        // parent hears of it in the rating request). The stored checks include it.
        let checks = GroundedChecks.evaluate(messages: record.messages, report: report, stop: record.stop,
                                             maxSteps: task.maxSteps, workspace: workspace, verify: task.card.verify)
        var storedChecks = checks
        let gold = TaskBank.gold(task, dir: dir, report: report, record: record)
        func recheckHere() async -> Int32?? {
            guard let again = await recheck(task, config: config, dir: dir) else { return nil }
            return .some(again.ran ? again.exit : nil)
        }
        let rerun = await recheckHere()
        if let command = task.card.verify, let exit = rerun { storedChecks = checks.addingRecheck(.recheck(command: command, exitCode: exit)) }

        // Judges see the fixture as the run left it.
        func judgeAll(report: String, checks: GroundedChecks, rerun: Int32??) async -> [JudgeOutcome] {
            var outcomes: [JudgeOutcome] = []
            for judge in judges {
                for path in ["parent", "grader"] where paths.contains(path) {
                    let o = await Runner.judge(prompt: prompt, report: report, checks: checks, recheck: rerun, task: task, dir: dir,
                                               judge: judge, path: path, limits: r.limits, sandbox: sandbox, makeClient: makeClient)
                    outcomes.append(o)
                    log("  judge \(judge.label) (\(path)): " + (o.verdict.map { "\($0)/3" } ?? "no verdict")
                        + (o.checkedConfirmed == false ? " (claimed a check it didn't make)" : ""))
                }
            }
            return outcomes
        }
        let outcomes = await judgeAll(report: report, checks: checks, rerun: rerun)
        // A known failure from the same run: the report's digits changed (lines, numbers, names with numbers) and a
        // change task's work undone. Counted only if gold now fails.
        var degraded: (report: String, gold: CheckResult, judges: [JudgeOutcome], checks: GroundedChecks)?
        if degrade, !judges.isEmpty, gold.passed {
            let bad = Self.degrade(report)
            if task.agent != "explore" { _ = shell("cd \(q(dir.path)) && git checkout -q -- . && git clean -qfd") }
            let badGold = TaskBank.gold(task, dir: dir, report: bad, record: record)
            if !badGold.passed {
                log("  degraded copy (gold fails): judging it")
                let badChecks = GroundedChecks.evaluate(messages: record.messages, report: bad, stop: record.stop,
                                                        maxSteps: task.maxSteps, workspace: workspace, verify: task.card.verify)
                let badRerun = await recheckHere()
                var badStored = badChecks
                if let command = task.card.verify, let exit = badRerun { badStored = badChecks.addingRecheck(.recheck(command: command, exitCode: exit)) }
                degraded = (bad, badGold, await judgeAll(report: bad, checks: badChecks, rerun: badRerun), badStored)
            } else {
                log("  degraded copy still passes gold: not used")
            }
        }

        let usages = record.messages.compactMap { $0.meta?.usage }
        let priced = record.costs.compactMap(\.listPrice)
        return BankResult(task: task.id, kind: task.card.kind?.rawValue ?? "", agent: agent.name, card: task.card,
                          model: target.label, trial: trial, gold: gold, checks: storedChecks, judges: outcomes,
                          stop: record.stop.map { "\($0)" } ?? "none", seconds: record.duration,
                          steps: record.assistantMessages.count, toolCalls: record.toolCalls.count,
                          promptTokens: usages.map(\.promptTokens).reduce(0, +),
                          completionTokens: usages.map(\.completionTokens).reduce(0, +),
                          listPrice: priced.isEmpty ? nil : priced.map(\.total).reduce(0, +),
                          unpricedRequests: record.costs.count - priced.count, report: report,
                          degradedReport: degraded?.report, degradedGold: degraded?.gold, degradedJudges: degraded?.judges, degradedChecks: degraded?.checks,
                          runRecord: record.runRecord, transcript: record.messages)
    }

    /// The report made wrong: every run of two or more digits has each digit moved by 3 (line numbers, amounts,
    /// times, class names like Heron42), so what it claims no longer matches the project.
    public static func degrade(_ report: String) -> String {
        var out = ""
        var digits = ""
        func flush() {
            out += digits.count >= 2 ? String(digits.map { Character(String(($0.wholeNumberValue! + 3) % 10)) }) : digits
            digits = ""
        }
        for c in report {
            if c.isASCII, c.isNumber { digits.append(c) } else { flush(); out.append(c) }
        }
        flush()
        return out
    }
}
