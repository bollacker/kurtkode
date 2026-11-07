import Foundation

/// What runs cost, grouped (GAP_ANALYSIS.md A5): by model, kind of run, project or day, with how often the labeled runs
/// passed, the share of prompt tokens read from cache, and a what-if repricing. Read from session run records and
/// from eval run stores.
public enum Spending {
    public enum Group: String, Sendable, CaseIterable { case model, kind, project, day }

    /// One run as the report counts it.
    public struct Run: Sendable {
        public var record: AgentRunRecord
        /// Its project folder's name (a session's workspace, or an eval store's name).
        public var project: String
        /// Whether it passed: an eval run's gold check, else its judgments' label (≥ 2/3 passes); nil: unlabeled.
        public var passed: Bool?
        /// Set for requests that aren't a run of their own, by what they were: one made outside any run (skill
        /// routing, a review after the run, /compact, a replay), or another model's grading, review or summary within
        /// a run. They count in the money and token columns, not as runs, and `whatIf` leaves them out (the cost
        /// audit's B2 and B3: they were missing from reports, or filed under the run's own model).
        public var outside: String?

        public init(record: AgentRunRecord, project: String, passed: Bool?, outside: String? = nil) {
            self.record = record
            self.project = project
            self.passed = passed
            self.outside = outside
        }

        /// What it spent: each request's charge where the server said, else its list price; nil: unpriced (local). Older
        /// records without the per-request sum: their charge, else their list price.
        public var spent: Double? {
            let t = record.totals
            if let s = t.spent { return s }
            if let c = t.charged { return c }
            return t.requests > t.unpricedRequests ? t.listPrice.total : nil
        }

        /// Its priced requests at list price; nil: unpriced (local). What `whatIf` is compared with: a list price
        /// against a list price (a charge differs from the list by provider routing, so comparing a charge said a
        /// model was 1.36× itself; the cost audit's B4).
        public var listSpent: Double? {
            let t = record.totals
            return t.requests > t.unpricedRequests ? t.listPrice.total : nil
        }

        /// "main", or a subagent run's card kind or agent ("subagent: fix").
        public var kind: String {
            if let outside { return outside }
            guard record.parentRun != nil || record.agent != "main" else { return "main" }
            return "subagent: " + (record.task.card?.kind?.rawValue ?? record.agent)
        }

        /// The model with its reasoning setting when it had one ("deepseek-v4-flash-0731 (reasoning none)").
        public var model: String {
            let name = record.setup.model
            guard let r = record.setup.reasoning else { return name }
            let off = r == "none" || r == "off" || r.replacingOccurrences(of: " ", with: "").contains(#""enabled":false"#)
            return name + (off ? " (reasoning off)" : " (reasoning \(r))")
        }

        func key(_ g: Group, zone: TimeZone) -> String {
            switch g {
            case .model: model
            case .kind: kind
            case .project: project
            case .day: DayFormat.formatter(zone: zone).string(from: record.started)
            }
        }
    }

    public struct Row: Sendable, Hashable {
        public var key: String
        /// The total row (its key is "all", which a project could be called too).
        public var isTotal = false
        public var runs = 0
        public var pricedRuns = 0
        public var spent = 0.0
        public var promptTokens = 0
        public var cacheReadTokens = 0
        /// Prompt tokens of the priced runs, which the cache share is over (local servers don't report cache reads).
        public var pricedPromptTokens = 0
        public var completionTokens = 0
        public var labeled = 0
        public var passed = 0
        public var seconds = 0.0

        /// What the runs themselves spent (`spent` also has requests outside them).
        public var runSpent = 0.0

        public var cacheShare: Double? { pricedPromptTokens > 0 ? Double(cacheReadTokens) / Double(pricedPromptTokens) : nil }
        public var passRate: Double? { labeled > 0 ? Double(passed) / Double(labeled) : nil }
        public var perRun: Double? { pricedRuns > 0 ? runSpent / Double(pricedRuns) : nil }
        /// Dollars per passing run, among the labeled priced runs (the cost-floor study's measure): their spending over
        /// their passes.
        public var perSuccess: Double?

        /// Mean wall time of a run, in seconds.
        public var secondsPerRun: Double? { runs > 0 ? seconds / Double(runs) : nil }
        /// The runs' wall time at `perHour` dollars an hour (`RunSettings.hourlyRate`): what waiting for them cost.
        public func timeCost(perHour: Double) -> Double { seconds / 3600 * perHour }
    }

    /// Runs grouped by `group`, most spent first (by date for days), with a total row last.
    public static func rows(_ runs: [Run], by group: Group, zone: TimeZone = .current) -> [Row] {
        var rows: [String: Row] = [:]
        var labeledSpent: [String: Double] = [:]
        var pricedPasses: [String: Int] = [:]
        func add(_ r: Run, to key: String) {
            var row = rows[key] ?? Row(key: key)
            let t = r.record.totals
            if r.outside == nil { row.runs += 1 }
            row.promptTokens += t.promptTokens
            if let s = r.spent {
                if r.outside == nil {
                    row.pricedRuns += 1
                    row.runSpent += s
                }
                row.spent += s
                row.pricedPromptTokens += t.promptTokens
                row.cacheReadTokens += t.cacheReadTokens
            }
            row.completionTokens += t.completionTokens
            row.seconds += t.wallSeconds
            if let p = r.passed {
                row.labeled += 1
                if p { row.passed += 1 }
                if let s = r.spent {
                    labeledSpent[key, default: 0] += s
                    if p { pricedPasses[key, default: 0] += 1 }
                }
            }
            rows[key] = row
        }
        for r in runs {
            add(r, to: r.key(group, zone: zone))
            add(r, to: "\u{0}total")
        }
        var out = rows.values.map { row -> Row in
            var row = row
            // Over the passes that were priced: a free local pass doesn't make paid runs cheaper (B4 of the audit).
            if let n = pricedPasses[row.key], n > 0, let s = labeledSpent[row.key] { row.perSuccess = s / Double(n) }
            return row
        }
        let total = out.first { $0.key == "\u{0}total" }
        out.removeAll { $0.key == "\u{0}total" }
        out.sort { group == .day ? $0.key < $1.key : ($0.spent, $0.runs) > ($1.spent, $1.runs) }
        if var total { total.key = "all"; total.isTotal = true; out.append(total) }
        return out
    }

    /// What the runs' recorded tokens would have cost at `price` (cache reads at its cache rate, the rest at input, plus
    /// output and per-request fees). A first approximation: another model would use a different number of tokens.
    public static func whatIf(_ runs: [Run], at price: PriceList.Price) -> Double {
        let r = price.standard
        var sum = 0.0
        for run in runs {
            let t = run.record.totals
            let uncached = Double(max(0, t.promptTokens - t.cacheReadTokens))
            let tokens: Double = uncached * r.input + Double(t.cacheReadTokens) * r.cacheRead + Double(t.completionTokens) * r.output
            sum += tokens / 1e6 + (price.perRequest ?? 0) * Double(t.requests)
        }
        return sum
    }

    /// The report as a table; with `perHour` above 0, also each group's mean wall time a run and its time cost.
    public static func table(_ rows: [Row], by group: Group, perHour: Double = 0) -> String {
        guard rows.count > 1 else { return "No recorded runs.\n" }
        func money(_ v: Double?) -> String {
            guard let v else { return "–" }
            return v == 0 ? "$0" : v < 0.01 ? String(format: "$%.5f", v) : v < 10 ? String(format: "$%.3f", v) : String(format: "$%.0f", v)
        }
        func pct(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }
        let width = min(44, max(10, rows.map(\.key.count).max() ?? 10))
        func pad(_ s: String, _ n: Int, left: Bool = false) -> String {
            let s = s.count > n ? String(s.prefix(n - 1)) + "…" : s
            let fill = String(repeating: " ", count: max(0, n - s.count))
            return left ? fill + s : s + fill
        }
        let time = perHour > 0
        var lines = [pad(group.rawValue, width) + "   runs        spent      a run  a success  passed   cache"
                     + (time ? "  wait a run   time cost" : "") + "   tokens in/out"]
        for r in rows {
            if r.isTotal { lines.append(String(repeating: "-", count: width + 82 + (time ? 24 : 0))) }
            let passed = r.labeled > 0 ? "\(r.passed)/\(r.labeled)" : "–"
            var cells = [pad(r.key, width), pad("\(r.runs)", 6, left: true), pad(money(r.pricedRuns > 0 || r.spent > 0 ? r.spent : nil), 12, left: true),
                         pad(money(r.perRun), 10, left: true), pad(money(r.perSuccess), 10, left: true),
                         pad(passed, 9, left: true), pad(pct(r.cacheShare), 7, left: true)]
            if time {
                cells.append(pad(r.secondsPerRun.map { String(format: "%.0f s", $0) } ?? "–", 11, left: true))
                cells.append(pad(money(r.timeCost(perHour: perHour)), 11, left: true))
            }
            cells.append("  \(r.promptTokens)/\(r.completionTokens)")
            lines.append(cells.joined(separator: " "))
        }
        var text = lines.joined(separator: "\n") + "\n"
        if time {
            text += String(format: "Time cost: the runs' wall time at $%.0f an hour of your waiting (Settings, or --hourly N; 0 hides it).\n", perHour)
        }
        return text
    }

    // MARK: Reading runs

    /// What every session, and the sessions of the project at `workspace`, spent today (this Mac's day): their cost
    /// entries' `spent`, subagent runs and replays included.
    public static func today(_ store: SessionStore, workspace: String?, now: Date = Date()) async -> (all: Double, project: Double) {
        let start = Calendar.current.startOfDay(for: now)
        var all = 0.0, project = 0.0
        for (header, e) in (try? await store.costEntries()) ?? [] where e.start >= start {
            // As the limits count it: a remote model with no known price at the meter's default rate.
            let s = CostMeter.counted(e)
            guard s > 0 else { continue }
            all += s
            if let workspace, header.workspace == workspace { project += s }
        }
        return (all, project)
    }

    /// Session runs (main and subagent) with their labels: the judgments' label, ≥ 2/3 passing.
    public static func sessionRuns(_ store: SessionStore) async throws -> [Run] {
        let records = try await store.runRecords()
        let entries = (try? await store.costEntries()) ?? []
        let ids = Set(records.map(\.run.id))
        var byRun: [UUID: [CostEntry]] = [:]
        for (_, e) in entries { if let run = e.run, ids.contains(run) { byRun[run, default: []].append(e) } }
        var judgments = try await store.mainRunJudgments()
        for (_, run) in try await store.judgedRuns() where !run.judgments.isEmpty { judgments[run.header.id] = run.judgments }
        func projectName(_ session: SessionHeader) -> String {
            session.workspace.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "(chats)"
        }
        var out: [Run] = []
        for (session, run, _) in records {
            // A subagent run's record sits in its child session, whose header names the run's workspace too.
            // The folder's path (with ~ for home): two projects with the same name stay apart.
            let project = projectName(session)
            let own = byRun[run.id] ?? []
            let others = own.filter { isOtherModelsWork($0, in: run) }
            out.append(Run(record: withCurrentCosts(run, entries: own.filter { !isOtherModelsWork($0, in: run) }), project: project,
                           passed: (judgments[run.id] ?? judgments[session.id])?.label.map { $0 >= 2.0 / 3 - 1e-9 }))
            out += others.map { Run(record: requestRecord($0, like: run), project: project, passed: nil, outside: "\($0.purpose.rawValue) (in runs)") }
        }
        for (session, e) in entries where e.run.map({ !ids.contains($0) }) ?? true {
            // No run at all (routing, a review after the run, /compact, a replay), or a run that left no record (one
            // stopped by quitting, or from before run records).
            out.append(Run(record: requestRecord(e, like: nil), project: projectName(session), passed: nil,
                           outside: (e.run == nil ? "outside runs: " : "runs without a record: ") + e.purpose.rawValue))
        }
        return out
    }

    /// A request in a run made for it by another model, and not the run's own work: a grader's or reviewer's
    /// judgment, a summary, a fallback reply.
    static func isOtherModelsWork(_ e: CostEntry, in run: AgentRunRecord) -> Bool {
        [.grading, .review, .summary, .summaryAttempt, .fallbackReply].contains(e.purpose)
            && (e.servedModel ?? e.requestedModel) != run.setup.model && e.requestedModel != run.setup.model
    }

    /// A record holding one request, so the report can count it under its own model, kind and day.
    static func requestRecord(_ e: CostEntry, like run: AgentRunRecord?) -> AgentRunRecord {
        let setup = RunSetup(endpointID: e.endpointID, api: e.api, host: e.host, model: e.requestedModel, temperature: nil,
                             maxOutputTokens: 0, wallClock: 0, maxSteps: 0, promptStyle: nil, webSearch: false,
                             promptCacheHour: false, tools: [], summarizerModel: nil, fallbackModel: nil)
        var totals = totalsFrom([e])
        totals.wallSeconds = e.duration
        return AgentRunRecord(id: e.id, userMessage: nil, parentRun: run?.id, taskCall: nil, agent: e.agent, definitionHash: "",
                              systemPromptHash: "", setup: setup, build: run?.build ?? .current, machine: nil, localModel: nil,
                              task: RunTask(text: "", bytes: 0, estimatedTokens: 0, hash: "", card: nil), started: e.start,
                              ended: e.end, totals: totals,
                              outcome: RunOutcome(stop: "\(e.ended)", steps: 0, toolCalls: [:], toolErrors: 0, denied: 0,
                                                  filesChanged: [], compactions: 0, finalReplyBytes: 0, finalReplyEstimatedTokens: 0),
                              children: [], judgment: nil)
    }

    /// What `entries` add up to, as a run record counts it (`RunTracker`).
    static func totalsFrom(_ entries: [CostEntry]) -> RunTotals {
        var t = RunTotals()
        var spent: Double?, charged: Double?
        for e in entries {
            t.requests += 1
            if let b = e.listPrice { t.listPrice.add(b) } else { t.unpricedRequests += 1 }
            if let s = e.spent { spent = (spent ?? 0) + s }
            if let c = e.charged { charged = (charged ?? 0) + c }
            if e.reconciled != nil { t.reconciledRequests += 1 }
            if let u = e.tokens {
                t.promptTokens += u.promptTokens
                t.cacheReadTokens += u.cacheReadTokens ?? 0
                t.cacheWriteTokens += u.cacheWriteTokens ?? 0
                t.completionTokens += u.completionTokens
                t.reasoningTokens += u.reasoningTokens
                t.searches += u.webSearches ?? 0
            }
            t.modelSeconds += e.duration
        }
        t.spent = spent
        t.charged = charged
        return t
    }

    /// A run's record with its spending as its cost entries say now: OpenRouter's charges arrive minutes after a run
    /// ends and are recorded later (`CostReconciler`), while the record keeps what was known when it ended.
    static func withCurrentCosts(_ record: AgentRunRecord, entries: [CostEntry]?) -> AgentRunRecord {
        guard let entries, !entries.isEmpty else { return record }
        var r = record
        let wall = r.totals.wallSeconds
        r.totals = totalsFrom(entries)
        r.totals.wallSeconds = wall
        return r
    }

    /// An eval store's runs (`<store>/<run>/run.json`: its `runRecord` and gold check), project = the store's name.
    public static func evalRuns(_ store: URL) -> [Run] {
        struct Stored: Decodable {
            struct Gold: Decodable { let passed: Bool? }
            let runRecord: AgentRunRecord?
            let gold: Gold?
            /// Degraded copies (made wrong on purpose, sharing their original's record) and runs that failed for a
            /// reason that isn't the model's are left out, as the eval's own rates leave them out.
            let degradation: String?
            let infra: String?
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)) ?? []
        var seen = Set<UUID>()
        return dirs.sorted { $0.path < $1.path }.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appending(path: "run.json")),
                  let s = try? dec.decode(Stored.self, from: data), let record = s.runRecord,
                  s.degradation == nil, s.infra == nil, seen.insert(record.id).inserted else { return nil }
            return Run(record: record, project: store.lastPathComponent, passed: s.gold?.passed)
        }
    }
}

/// Notices when a request read much less of its prompt from the cache than the one before it in the same run, on a paid
/// model with a large prompt: the cached prefix was lost (a changed system prompt or tool list, a different provider,
/// an expired cache), and the whole history was billed at the full input price (GAP_ANALYSIS.md A5, C7).
public enum CacheWatch {
    /// The notice for `current`, or nil.
    public static func check(previous: CostEntry?, current: CostEntry) -> String? {
        guard let p = previous?.tokens, let c = current.tokens, let price = current.listPrice, price.total > 0,
              p.promptTokens >= 8_000, c.promptTokens >= 8_000 else { return nil }
        let before = Double(p.cacheReadTokens ?? 0) / Double(p.promptTokens)
        let now = Double(c.cacheReadTokens ?? 0) / Double(c.promptTokens)
        guard before >= 0.5, now < 0.1 else { return nil }
        let missed = c.promptTokens - (c.cacheReadTokens ?? 0)
        return "The prompt cache missed: \(missed.formatted()) tokens were read at full price "
            + String(format: "($%.4f for this request's input)", price.uncachedInput + price.cacheWrite5m + price.cacheWrite1h)
            + "; the request before read \(Int(before * 100))% from the cache."
            + (current.cacheMiss.map { " Likely cause: \($0.cause.label)." } ?? "")
    }
}
