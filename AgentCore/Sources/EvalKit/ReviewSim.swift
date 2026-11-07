import CryptoKit
import Foundation
import AgentCore

/// A6's measurement: cross-vendor review (`CodeReview`) run on stored bank runs whose outcome is known. Each run's change
/// is rebuilt as a diff of its saved fixture against a fresh copy of its task's fixture; the reviewer sees the task, the
/// run's report, its checks and that diff, as a session's reviewer would. Catch rate: reviews that find a problem
/// ("has problems" or "wrong") in runs gold failed (real failures, and copies degraded to make or claim changes they
/// shouldn't); false alarms: the same on runs gold passed.
public enum ReviewSim {
    public struct Row: Codable, Sendable {
        public var run: String
        public var task: String
        public var kind: String
        public var model: String
        /// "real-fail", "pass", or the degradation ("stray-edit", "undo-all", …).
        public var group: String
        public var goldPassed: Bool
        public var reviewer: String
        public var verdict: String?
        public var findings: Int
        public var problem: String?
        public var diffBytes: Int
        public var seconds: Double
        public var listPrice: Double?
        public var charged: Double?
        public var promptTokens: Int
        public var completionTokens: Int
        public var summary: String?
    }

    static let codeKinds: Set<String> = ["edit", "fix", "refactor", "write-tests"]
    public static let degradations = ["stray-edit", "undo-all", "undo-half", "vanish"]

    public static func group(_ r: StoredRun) -> String { r.degradation ?? (r.gold.passed ? "pass" : "real-fail") }

    /// Every real failure that changed or should have changed code, and up to `perGroup` of each degradation that touches
    /// files and of passing code runs, chosen by a hash of the run id (the same runs for every reviewer).
    public static func sample(_ runs: [StoredRun], perGroup: Int) -> [StoredRun] {
        func key(_ r: StoredRun) -> String { SHA256.hash(data: Data(r.id.utf8)).map { String(format: "%02x", $0) }.joined() }
        let usable = runs.filter { $0.infra == nil }.sorted { key($0) < key($1) }
        let real = usable.filter { $0.degradation == nil && !$0.gold.passed && (codeKinds.contains($0.kind) || !$0.checks.filesChanged.isEmpty) }
        var out = real
        for d in degradations { out += usable.filter { $0.degradation == d }.prefix(perGroup) }
        out += usable.filter { $0.degradation == nil && $0.gold.passed && codeKinds.contains($0.kind) }.prefix(perGroup * 2)
        return out
    }

    /// The run's change: its saved fixture against the commit it started from (the fixture's last commit), as
    /// `git diff` shows it, ignored files (caches, a kurtkode fixture's `.build`) left out. A fixture changed after the
    /// run was recorded (P2b's `conftest.py` in real1) doesn't show as the run's change. A saved fixture without git
    /// falls back to a fresh copy of the task's fixture.
    public static func diff(_ run: StoredRun, store: RunStore) throws -> String {
        let dir = try store.restore(run)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try ownDiff(dir) ?? freshDiff(run, store: store)
    }

    /// A tree's change since the fixture's last commit (new files included, ignored ones not); nil without git history.
    /// The fixture's base ref (`Fixtures.baseRef`) marks it; for a run recorded before the ref, the fixture's commits
    /// are the eval's (`Fixtures.git`'s identity): a task can have several ("fixture", then "broken" adding the bug),
    /// and a run's own commits come after them. Without one of the eval's, the first commit.
    static func ownDiff(_ dir: URL) -> String? {
        let git = "git -C \(q(dir.path)) -c core.quotePath=false"
        let marked = shell("\(git) rev-parse -q --verify \(Fixtures.baseRef) 2>/dev/null").output
        let fixture = shell("\(git) log -1 --format=%H --author=eval@example.com 2>/dev/null").output
        let first = shell("\(git) rev-list --max-parents=0 HEAD 2>/dev/null | tail -1").output
        let root = [marked, fixture, first].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        guard !root.isEmpty else { return nil }
        _ = shell("\(git) add -A -N . 2>/dev/null")
        let d = shell("\(git) diff --no-color --no-ext-diff -M \(root) 2>/dev/null")
        return d.status == 0 ? d.output : nil
    }

    /// The run's change against a fresh copy of its task's fixture (caches and `.git` left out).
    static func freshDiff(_ run: StoredRun, store: RunStore) throws -> String {
        guard let task = TaskBank.every.first(where: { $0.id == run.task }) else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        let top = fm.temporaryDirectory.appending(path: "kk-revsim-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: top) }
        let before = top.appending(path: "before"), after = top.appending(path: "after")
        try fm.createDirectory(at: before, withIntermediateDirectories: true)
        _ = try task.setUp(before)
        try fm.moveItem(at: try store.restore(run), to: after)
        for dir in [before, after] { prune(dir) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-c", "core.quotePath=false", "diff", "--no-index", "--no-color", "--no-ext-diff", "-M", "before", "after"]
        p.currentDirectoryURL = top
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            // A new file is "a/after/x b/after/x", a deleted one "a/before/x b/before/x".
            for (from, to) in [("a/before/", "a/"), ("b/after/", "b/"), ("a/after/", "a/"), ("b/before/", "b/"), (" before/", " "), (" after/", " ")]
            where l.hasPrefix("diff --git") || l.hasPrefix("--- ") || l.hasPrefix("+++ ") || l.hasPrefix("rename ") {
                l = l.replacingOccurrences(of: from, with: to)
            }
            return l
        }.joined(separator: "\n")
    }

    static func prune(_ dir: URL) {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return }
        var gone: [URL] = []
        for case let url as URL in e where [".git", "__pycache__", ".pytest_cache", ".DS_Store"].contains(url.lastPathComponent) {
            gone.append(url)
            e.skipDescendants()
        }
        for u in gone { try? fm.removeItem(at: u) }
    }

    /// One review of one stored run.
    public static func review(_ run: StoredRun, diff: String, reviewer: ModelTarget,
                              makeClient: Runner.ClientFactory = Runner.defaultClient) async -> Row {
        var ran = run.checks.problems
        if let v = run.checks.verifyCommand { ran.insert("\(v) → exit \(run.checks.verifyExitCode.map(String.init) ?? "?")", at: 0) }
        let prompt = CodeReview.prompt(request: run.prompt, report: run.report, checks: ran, diff: diff)
        final class Costs: @unchecked Sendable { let lock = NSLock(); var entries: [CostEntry] = [] }
        let costs = Costs()
        let sink = CostSink(scope: CostScope(run: nil, agent: "reviewer"), endpointID: reviewer.endpoint.id) { e in
            costs.lock.withLock { costs.entries.append(e) }
        }
        let model = SubagentModel(client: makeClient(reviewer), model: reviewer.model, historyShape: reviewer.profile.history,
                                  temperature: reviewer.profile.temperature, endpointID: reviewer.endpoint.id,
                                  // "#off" targets carry OpenRouter's {"enabled": false}: the profile setting "none" sends that.
                                  reasoning: reviewer.reasoning != nil ? "none" : reviewer.profile.reasoning,
                                  providers: reviewer.profile.providers)
        var limits = TurnLimits(maxTokens: 8192, wallClock: 600)
        if reviewer.endpoint.kind.api != .openai { limits.maxTokens = 16_384; limits.wallClock = 900 }
        let began = Date()
        let r = await CodeReview.run(model, prompt: prompt, costs: sink, meter: nil, limits: limits)
        let entries = costs.lock.withLock { costs.entries }
        let priced = entries.compactMap(\.listPrice), charged = entries.compactMap(\.charged)
        return Row(run: run.id, task: run.task, kind: run.kind, model: run.model, group: group(run), goldPassed: run.gold.passed,
                   reviewer: reviewer.label, verdict: r.verdict?.rawValue, findings: r.findings.count, problem: r.problem,
                   diffBytes: diff.utf8.count, seconds: Date().timeIntervalSince(began),
                   listPrice: priced.isEmpty ? nil : priced.map(\.total).reduce(0, +),
                   charged: charged.isEmpty ? nil : charged.reduce(0, +),
                   promptTokens: entries.compactMap { $0.tokens?.promptTokens }.reduce(0, +),
                   completionTokens: entries.compactMap { $0.tokens?.completionTokens }.reduce(0, +), summary: r.summary)
    }

    /// The table: for each reviewer, the share of each group's runs in which it found a problem.
    public static func report(_ rows: [Row]) -> String {
        var s = "| reviewer | group | runs | found a problem | of them \"wrong\" | no verdict | a review |\n|---|---|---|---|---|---|---|\n"
        let groups = ["real-fail"] + degradations + ["pass"]
        for reviewer in Array(Set(rows.map(\.reviewer))).sorted() {
            let mine = rows.filter { $0.reviewer == reviewer }
            func line(_ name: String, _ g: [Row]) {
                guard !g.isEmpty else { return }
                let judged = g.filter { $0.verdict != nil }
                let flagged = judged.filter { $0.verdict != CodeReview.Verdict.looksRight.rawValue }
                let wrong = judged.filter { $0.verdict == CodeReview.Verdict.wrong.rawValue }
                let cost = g.compactMap { $0.charged ?? $0.listPrice }
                s += "| \(reviewer) | \(name) | \(g.count) | \(flagged.count)/\(judged.count) (\(pct(flagged.count, judged.count))) | \(wrong.count) | \(g.count - judged.count) | "
                    + (cost.isEmpty ? "free" : String(format: "$%.4f", cost.reduce(0, +) / Double(cost.count))) + String(format: ", %.0f s", g.map(\.seconds).reduce(0, +) / Double(g.count)) + " |\n"
            }
            for g in groups { line(g, mine.filter { $0.group == g }) }
            line("all failures", mine.filter { !$0.goldPassed })
        }
        return s
    }

    static func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((Double(a) * 100 / Double(b)).rounded()))%" }
}
