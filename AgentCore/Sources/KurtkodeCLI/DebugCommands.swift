import AgentCore
import Foundation

/// `kurtkode inspect | replay | export`: the Debug window's views of a recorded session, in a terminal.
public enum DebugCommands {
    public static let names: Set<String> = ["inspect", "replay", "export", "runs", "cost", "prompts", "judge", "judgments", "pool"]

    public static let usage = """
        kurtkode inspect [SESSION] [--run N] [--turn N] [--json]
            A session's turns: model, tokens, times, tool calls, problems. --turn N: one turn in full (its reply,
            reasoning, calls and results, notes, HTTP); --run N: the session's Nth subagent run instead.
        kurtkode replay [SESSION] --turn N [--run N] [-m ENDPOINT:MODEL] [--temperature T]
                        [--reasoning LEVEL[,LEVEL…]|default] [--system-file FILE] [--json]
            Sends turn N's recorded request again (on its own model unless -m says otherwise) and compares the
            reply with the original. Tools aren't run. The replay is saved with the session (the Debug window
            lists it).
        kurtkode export [SESSION] [--run N] [--format markdown|json] [-o FILE]
            The session as Markdown (default) or JSON, its subagent runs included.
        kurtkode runs [--since DATE|Nd] [--agent NAME] [--json|--csv] [-o FILE]
            Every recorded agent run (main runs and subagent runs, all projects): task, model setup, cost at list
            price by component, tokens, times, and how it ended. --json: one record per line, in full; --csv: one
            row per run, for analysis.

        kurtkode judge RUN --verdict 0-3 [--issues TAG,TAG] [--note TEXT]
            Your judgment of a run, a main run or a subagent run (RUN: its id or a prefix; see `kurtkode runs --json` or
            the app's Agents tab; in a session /good and /bad rate the last reply):
            3 done and right, 2 minor gaps, 1 partial, 0 failed or wrong. It's kept beside the agent's own rating and
            the automatic checks, and counts most.
        kurtkode judgments [--json] [-o FILE]
            Every subagent run with its judgments (automatic checks, the parent's rating, the grader's, yours). --json:
            one run per line with its task, card, report, model and every judgment in full, for analysis and tuning.

        kurtkode cost check --day YYYY-MM-DD [--tz UTC|local|ZONE] [--endpoint NAME] [--json]
            A day's recorded requests summed by endpoint and model (tokens by kind, list price, what was charged),
            to compare with the provider's console for the same key and day. --tz: the day's time zone (UTC by
            default; use the console's).
        kurtkode cost report [--by model|kind|project|day] [--since DATE|Nd] [--eval STORE]… [--no-sessions] [--hourly N] [--json]
            What runs cost, grouped: runs, spent (the charge where the server said, else list price), per run and per
            passing run, how many of the labeled runs passed (eval gold checks; your thumbs, retries and rewinds; the
            judges), the share of prompt tokens read from cache, tokens. Sessions' runs (main and subagent) by default;
            --eval adds an eval run store (eval-results/runs/NAME), --no-sessions leaves the sessions out. With a value
            for your time (Settings' hourly rate, $30 unless changed, or --hourly N; 0 hides it), also the mean wall
            time of a run and what waiting for the runs cost at that rate.
        kurtkode cost whatif -m ENDPOINT:MODEL [the report's options]
            The same runs' recorded tokens repriced at another model's list price, beside what they cost. A first
            approximation: another model would use more or fewer tokens, and pass more or less often.
        kurtkode cost cache [--since DATE|Nd] [--compact-at 150k,200k] [--json]
            How well the prompt cache served the sessions' requests: misses by cause (cache expired over a pause, the
            tool list, system prompt or an earlier message changed, a model, effort or provider switch, a compaction)
            and what each cost beyond a cache read; requests by the pause before them; the input side repriced with a
            5-minute and an hour's cache (servers that bill cache writes); and an estimate of compacting at each
            --compact-at size (sessions that grew past it).
        kurtkode cost reconcile [--since DATE|Nd]
            Looks up the provider's record of requests not checked yet (OpenRouter's generation records, which can
            lag the reply) and records what it says; says why when a record can't be had.
        kurtkode cost calibrate -m ENDPOINT:MODEL [--max-output N] [--yes]
            A fixed set of three requests (a short one, then a ~9k-token prompt twice, the second reading the cache)
            to check the price list against the provider's console the next day. Without --yes it only shows what it
            would send and its estimated list price; with --yes it sends them (this spends money) and records them
            in a session of their own.

        kurtkode pool [--json] | pool init
            The model pool: the configurations kurtkode picks on its own for subagents, retries, judging and summaries
            (tier, roles, retry rung), where each runs here, and its list price and the cost of a typical small task.
            `pool init` writes the shipped pool to pool.json in kurtkode's data folder, to edit by hand.

        kurtkode prompts [list]
            The system prompt's templates (SYSTEM_PROMPT.md) and where each one comes from: the project's
            .kurtkode/prompts/, your ~/.kurtkode/prompts/, or kurtkode's defaults.
        kurtkode prompts show NAME | reset NAME | reset --all
            Prints a template as used here; removes your override of one (or of all kurtkode's own) so the
            default is used again. A style of your own is removed by name.
        kurtkode prompts render [--style NAME] [--mode ask|acceptEdits|plan|fullAuto]
            The system prompt a session in this folder would start with (with every tool offered).

        SESSION is an id or id prefix (any project; see --list-sessions), or "last" (default): the latest
        session in the current folder (-C DIR for another).
        """

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Runs one command; returns the exit status. `out` gets the output.
    public static func run(_ args: [String], settings: AppSettings, cwd: URL,
                           out: @escaping @Sendable (String) -> Void) async -> Int32 {
        do {
            var rest = Array(args.dropFirst())
            let command = args.first ?? ""
            var o = Parsed()
            var positional: [String] = []
            while !rest.isEmpty {
                let a = rest.removeFirst()
                func value() throws -> String {
                    guard !rest.isEmpty else { throw Failure(description: "\(a) needs a value") }
                    return rest.removeFirst()
                }
                switch a {
                case "--turn": o.turn = Int(try value())
                case "--run": o.run = Int(try value())
                case "--json": o.json = true
                case "-m", "--model": o.model = try value()
                case "--temperature": o.temperature = Double(try value())
                case "--reasoning": o.reasoning = try value()
                case "--system-file": o.systemFile = try value()
                case "--format": o.format = try value()
                case "-o", "--out": o.outFile = try value()
                case "--csv": o.csv = true
                case "--since": o.since = try value()
                case "--agent": o.agent = try value()
                case "--day": o.day = try value()
                case "--tz": o.timeZone = try value()
                case "--endpoint": o.endpoint = try value()
                case "--yes": o.yes = true
                case "--style": o.style = try value()
                case "--mode": o.mode = try value()
                case "--all": o.all = true
                case "--verdict": o.verdict = Int(try value())
                case "--note": o.note = try value()
                case "--issues": o.issues = try value()
                case "--by": o.by = try value()
                case "--eval": o.evalStores.append(try value())
                case "--no-sessions": o.noSessions = true
                case "--hourly":
                    guard let v = Double(try value()), v >= 0 else { throw Failure(description: "--hourly takes dollars an hour (0 hides the time cost)") }
                    o.hourly = v
                case "--max-output": o.maxOutput = Int(try value())
                case "--compact-at":
                    o.compactAt = try value().split(separator: ",").map { part in
                        let t = part.trimmingCharacters(in: .whitespaces).lowercased()
                        guard let n = Double(t.hasSuffix("k") ? String(t.dropLast()) : t), n > 0 else {
                            throw Failure(description: "--compact-at takes sizes in tokens, such as 150k,200k")
                        }
                        return Int(t.hasSuffix("k") ? n * 1000 : n)
                    }
                case "-C", "--cwd": _ = try value()          // already applied by main
                case "-h", "--help": out(usage + "\n"); return 0
                default:
                    if a.hasPrefix("-") { throw Failure(description: "unknown option \(a)\n\n" + usage) }
                    positional.append(a)
                }
            }
            let store = settings.sessionStore
            if command == "runs" {
                try await runs(store: store, options: o, out: out)
                return 0
            }
            if command == "judge" {
                try await judge(positional.first, store: store, options: o, out: out)
                return 0
            }
            if command == "judgments" {
                try await judgments(store: store, options: o, out: out)
                return 0
            }
            if command == "pool" {
                try await pool(positional.first, settings: settings, options: o, out: out)
                return 0
            }
            if command == "prompts" {
                try await prompts(positional, cwd: cwd, settings: settings, options: o, out: out)
                return 0
            }
            if command == "cost" {
                switch positional.first {
                case "check": try await costCheck(store: store, settings: settings, options: o, out: out)
                case "calibrate": try await calibrate(store: store, settings: settings, options: o, out: out)
                case "cache": try await cacheReport(store: store, options: o, out: out)
                case "reconcile": try await reconcileCosts(store: store, settings: settings, options: o, out: out)
                case "report": try await costReport(store: store, settings: settings, options: o, cwd: cwd, whatIf: false, out: out)
                case "whatif", "what-if": try await costReport(store: store, settings: settings, options: o, cwd: cwd, whatIf: true, out: out)
                default: throw Failure(description: "kurtkode cost report | whatif | cache | check | reconcile | calibrate (kurtkode cost --help)")
                }
                return 0
            }
            var session = try await resolve(positional.first, store: store, cwd: cwd)
            let wire: URL
            if let n = o.run {
                let runs = await store.subagentRuns(of: session.header)
                guard n >= 1, n <= runs.count else { throw Failure(description: "this session has \(runs.count) subagent runs") }
                session = runs[n - 1]
            }
            wire = store.wireDirectory(for: session.header)
            switch command {
            case "inspect": try inspect(session, wire: wire, options: o, store: store, settings: settings, out: out)
            case "replay": try await replay(session, wire: wire, options: o, settings: settings, out: out)
            case "export": try await export(session, options: o, store: store, out: out)
            default: throw Failure(description: usage)
            }
            return 0
        } catch {
            Renderer.write(to: .standardError)("kurtkode: \(error)\n")      // checked: it can quote a server's error
            return 1
        }
    }

    struct Parsed {
        var turn: Int?
        var run: Int?
        var json = false
        var model: String?
        var temperature: Double?
        var reasoning: String?
        var systemFile: String?
        var format: String?
        var outFile: String?
        var csv = false
        var since: String?
        var agent: String?
        var day: String?
        var timeZone: String?
        var endpoint: String?
        var yes = false
        var maxOutput: Int?
        var style: String?
        var mode: String?
        var all = false
        var verdict: Int?
        var note: String?
        var issues: String?
        var by: String?
        var evalStores: [String] = []
        var hourly: Double?
        var noSessions = false
        var compactAt: [Int] = [150_000, 200_000]
    }

    /// `kurtkode judge`: the user's judgment of a subagent run, in its own session and its parent's.
    static func judge(_ spec: String?, store: SessionStore, options o: Parsed, out: @Sendable (String) -> Void) async throws {
        guard let spec, !spec.isEmpty else { throw Failure(description: "kurtkode judge RUN --verdict 0-3 [--note TEXT]") }
        guard let verdict = o.verdict, (0...3).contains(verdict) else { throw Failure(description: "--verdict takes 0, 1, 2 or 3") }
        let issues = (o.issues ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if let bad = issues.first(where: { !RunJudgment.issueTags.contains($0) }) {
            throw Failure(description: "\(bad) isn't an issue tag: " + RunJudgment.issueTags.joined(separator: ", "))
        }
        let prefix = spec.lowercased()
        let hits = try await store.judgedRuns().filter { $0.run.header.id.uuidString.lowercased().hasPrefix(prefix) }
        // A main run (A3): its judgment goes in its own session.
        let mains = try await store.runRecords().filter { $0.run.agent == "main" && $0.run.id.uuidString.lowercased().hasPrefix(prefix) }
        if hits.isEmpty, mains.count == 1, let (session, run, _) = mains.first {
            let j = RunJudgment(run: run.id, judge: .user, verdict: verdict, issues: issues, note: o.note)
            try await store.append(.judgment(j), to: session.id)
            out("Judged the main run \(String(run.id.uuidString.prefix(8))) (\(run.task.text.prefix(60))) \(verdict)/3 "
                + "(\(RunJudgment.verdictMeanings[verdict]!)).\n")
            return
        }
        guard hits.count + mains.count == 1, let (parent, run) = hits.first else {
            throw Failure(description: hits.count + mains.count == 0 ? "no run \(spec)" : "\(spec) matches \(hits.count + mains.count) runs")
        }
        let j = RunJudgment(run: run.header.id, taskCall: run.header.parentCallID, judge: .user, verdict: verdict,
                            checked: RunJudgment.Checked.readTheFiles.rawValue, issues: issues, note: o.note)
        try await store.append(.judgment(j), toRun: run.header.id, of: parent)
        try? await store.append(.judgment(j), to: parent.id)
        out("Judged \(run.displayTitle) \(verdict)/3 (\(RunJudgment.verdictMeanings[verdict]!)).\n")
    }

    /// `kurtkode cost report` and `cost whatif`.
    static func costReport(store: SessionStore, settings: AppSettings, options o: Parsed, cwd: URL, whatIf: Bool,
                           out: @escaping @Sendable (String) -> Void) async throws {
        guard let group = Spending.Group(rawValue: o.by ?? "model") else {
            throw Failure(description: "--by takes " + Spending.Group.allCases.map(\.rawValue).joined(separator: ", "))
        }
        var runs: [Spending.Run] = o.noSessions ? [] : try await Spending.sessionRuns(store)
        for path in o.evalStores {
            var url = URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL
            // A bare store name, as the help says: eval-results/runs/NAME.
            if !path.contains("/"), !FileManager.default.fileExists(atPath: url.path) {
                url = cwd.appending(path: "eval-results/runs/" + path).standardizedFileURL
            }
            let found = Spending.evalRuns(url)
            if found.isEmpty { throw Failure(description: "no eval runs in \(url.path)") }
            runs += found
        }
        if let since = o.since {
            let cutoff = try sinceDate(since)
            runs = runs.filter { $0.record.started >= cutoff }
        }
        let rows = Spending.rows(runs, by: group)
        let perHour = o.hourly ?? settings.run.hourlyRate
        var text = Spending.table(rows, by: group, perHour: perHour)
        if whatIf {
            guard let spec = o.model else { throw Failure(description: "cost whatif needs -m ENDPOINT:MODEL") }
            let (endpoint, model) = try CLIOptions.resolveModel(spec, settings: settings)
            guard case .known(let price, _, _) = await PriceLookup.lookup(client: ChatClient(endpoint: endpoint), model: model) else {
                throw Failure(description: "no list price known for \(model) on \(endpoint.name)")
            }
            // Runs only: another model's grading or a request outside any run wouldn't move with the main model.
            let priced = runs.filter { $0.outside == nil && $0.listSpent != nil }
            let actual = priced.compactMap(\.listSpent).reduce(0, +)
            let charged = priced.compactMap(\.spent).reduce(0, +)
            let would = Spending.whatIf(priced, at: price)
            text += String(format: "\nThe %d priced runs cost $%.4f at list price ($%.4f spent). Their tokens at %@'s list price: $%.4f (%@).\n",
                           priced.count, actual, charged, model, would,
                           actual > 0 ? String(format: "%.2f×", would / actual) : "–")
            text += "A first approximation: another model would use more or fewer tokens, and pass more or less often. "
                + "Unpriced (local) runs are left out.\n"
        }
        if o.json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let list: [JSONValue] = rows.map { r in
                var o: [String: JSONValue] = ["key": .string(r.key), "runs": .number(Double(r.runs)),
                                              "spent": r.pricedRuns > 0 || r.spent > 0 ? .number(r.spent) : .null, "total": .bool(r.isTotal),
                                              "pricedRuns": .number(Double(r.pricedRuns)), "labeled": .number(Double(r.labeled)),
                                              "passed": .number(Double(r.passed)), "promptTokens": .number(Double(r.promptTokens)),
                                              "cacheReadTokens": .number(Double(r.cacheReadTokens)),
                                              "completionTokens": .number(Double(r.completionTokens)),
                                              "seconds": .number(r.seconds)]
                if perHour > 0 { o["timeCost"] = .number(r.timeCost(perHour: perHour)) }
                o["perSuccess"] = r.perSuccess.map(JSONValue.number) ?? .null
                return .object(o)
            }
            text = String(decoding: try enc.encode(JSONValue.array(list)), as: UTF8.self) + "\n"
        }
        out(text)
    }

    /// `kurtkode cost cache`: the sessions' cache misses by cause, requests by the pause before them, and what a
    /// different cache lifetime or compaction size would have cost (CACHING_PLAN.md, Phase 0).
    static func cacheReport(store: SessionStore, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        var entries = try await store.costEntries()
        if let since = o.since {
            let cutoff = try sinceDate(since)
            entries = entries.filter { $0.entry.start >= cutoff }
        }
        let steps = CacheLedger.steps(entries)
        let causes = CacheLedger.causes(steps)
        let gaps = CacheLedger.gaps(steps)
        let short = CacheLedger.ttlWhatIf(steps, ttl: "5m"), hour = CacheLedger.ttlWhatIf(steps, ttl: "1h")
        let compactions = o.compactAt.map { ($0, CacheLedger.compactionWhatIf(steps, threshold: $0)) }
        if o.json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let v: JSONValue = [
                "requests": .number(Double(steps.count)),
                "misses": .array(causes.map { ["cause": .string($0.cause.rawValue), "count": .number(Double($0.count)),
                                               "lostTokens": .number(Double($0.lostTokens)), "lost": .number($0.lost)] }),
                "gaps": .array(gaps.map { ["gap": .string($0.label), "requests": .number(Double($0.count)),
                                           "promptTokens": .number(Double($0.promptTokens)), "cacheReadTokens": .number(Double($0.cacheReadTokens))] }),
                "ttl": ["requests": .number(Double(short.requests)), "actual": .number(short.actual),
                        "fiveMinutes": .number(short.whatIf), "oneHour": .number(hour.whatIf)],
                "compaction": .array(compactions.map { t, r in ["threshold": .number(Double(t)), "sessions": .number(Double(r.sessions)),
                                                               "actual": .number(r.actual), "estimate": .number(r.estimate)] }),
            ]
            out(String(decoding: try enc.encode(v), as: UTF8.self) + "\n")
            return
        }
        let prompt = steps.compactMap(\.entry.tokens).reduce(0) { $0 + $1.promptTokens }
        let read = steps.compactMap(\.entry.tokens).reduce(0) { $0 + ($1.cacheReadTokens ?? 0) }
        var text = "\(steps.count) reply requests, \(prompt.formatted()) prompt tokens, "
            + (prompt > 0 ? "\(Int((Double(read) / Double(prompt) * 100).rounded()))% read from the cache.\n" : "none read from the cache.\n")
        text += "\nMisses (a request that read at least a quarter less than the one before left in the cache):\n"
        if causes.isEmpty { text += "  none\n" }
        for c in causes {
            text += "  " + c.cause.label.padding(toLength: 28, withPad: " ", startingAt: 0)
                + String(format: "%5d  %12@ tokens  $%.4f beyond a cache read\n", c.count, c.lostTokens.formatted() as NSString, c.lost)
        }
        text += "\nRequests by the pause before them (same session and agent):\n"
        for g in gaps where g.count > 0 {
            let share = g.promptTokens > 0 ? Int((Double(g.cacheReadTokens) / Double(g.promptTokens) * 100).rounded()) : 0
            text += "  " + g.label.padding(toLength: 12, withPad: " ", startingAt: 0) + String(format: "%6d requests, %3d%% read from the cache\n", g.count, share)
        }
        if short.requests > 0 {
            text += String(format: "\nCache lifetime (%d requests on servers that bill cache writes; input side at list price):\n"
                           + "  as recorded $%.4f   all 5-minute $%.4f   all 1-hour $%.4f\n", short.requests, short.actual, short.whatIf, hour.whatIf)
        }
        for (t, r) in compactions {
            text += r.sessions == 0 ? "\nCompacting at \(t / 1000)k: no session grew past it.\n"
                : String(format: "\nCompacting at %dk (%d sessions grew past it; an estimate): input side $%.4f as recorded, about $%.4f.\n",
                         t / 1000, r.sessions, r.actual, r.estimate)
        }
        out(text)
    }

    /// `--since`: YYYY-MM-DD (local) or Nd (days back).
    static func sinceDate(_ since: String) throws -> Date {
        if since.hasSuffix("d"), let days = Double(since.dropLast()) { return Date().addingTimeInterval(-days * 86_400) }
        guard let d = DayFormat.formatter(zone: .current).date(from: since) else { throw Failure(description: "--since takes YYYY-MM-DD or Nd (days)") }
        return d
    }

    /// `kurtkode pool`: the pool's entries, where they run here, and what they cost.
    static func pool(_ sub: String?, settings: AppSettings, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        let url = settings.poolURL
        if sub == "init" {
            if FileManager.default.fileExists(atPath: url.path) { throw Failure(description: "\(url.path) already exists") }
            try ModelPool.shipped.save(url)
            out("Wrote the shipped pool to \(url.path).\n")
            return
        }
        if let sub { throw Failure(description: "kurtkode pool [--json] | pool init (not \(sub))") }
        let (pool, problem) = ModelPool.loadChecked(url)
        var rows: [JSONValue] = []
        var text = FileManager.default.fileExists(atPath: url.path) ? "Pool: \(url.path)\n" : "Pool: the shipped one (no \(url.path))\n"
        if let problem { text += "Problem: " + problem + "\n" }
        for e in pool.entries {
            let r = ModelPool.resolve(e, endpoints: settings.endpoints)
            var price: PriceList.Price?
            if let r {
                if r.endpoint.kind == .openai {
                    price = await RemotePrices.shared.price(client: ChatClient(endpoint: r.endpoint), model: r.model)?.0
                } else {
                    price = PriceList.price(api: r.endpoint.kind.api, model: r.model)
                }
            }
            let rung = e.ladder.map { "rung \($0 + 1)" } ?? ""
            let where_ = r.map { "\($0.endpoint.name):\($0.model)" } ?? "no endpoint here for \(e.endpoint)"
            let roles: String = e.roles.map(\.rawValue).sorted().joined(separator: ",")
            let head: [String] = [e.enabled ? "" : "(off)", e.label, e.tier.rawValue, roles, rung]
            var lines: [String] = [head.filter { !$0.isEmpty }.joined(separator: "  "), "    " + where_]
            if let price { lines.append("    " + TypicalTask.label(price)) }
            if let note = e.note { lines.append("    " + note) }
            text += "\n" + lines.joined(separator: "\n") + "\n"
            var row: [String: JSONValue] = ["entry": encode(e)]
            row["endpoint"] = r.map { JSONValue.string($0.endpoint.name) } ?? .null
            row["model"] = r.map { JSONValue.string($0.model) } ?? .null
            row["typicalTask"] = price.map { JSONValue.number(TypicalTask.cost($0)) } ?? .null
            rows.append(.object(row))
        }
        out(o.json ? pretty(.array(rows)) + "\n" : text)
    }

    /// `kurtkode judgments`: every subagent run and how it was judged.
    static func judgments(store: SessionStore, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        let rows = try await store.judgedRuns()
        var text = ""
        if o.json {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            func json<T: Encodable>(_ v: T) -> JSONValue { (try? enc.encode(v)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null }
            for (parent, run) in rows {
                let task = run.messages.first(where: { $0.role == .user })?.content ?? ""
                let obj: JSONValue = ["run": .string(run.header.id.uuidString), "parent": .string(parent.id.uuidString),
                                      "workspace": parent.workspace.map(JSONValue.string) ?? .null,
                                      "agent": .string(run.header.agent ?? ""), "model": .string(run.model), "task": .string(task),
                                      "card": run.subagentEnd?.card.map(json) ?? .null,
                                      "report": run.subagentEnd.map { .string($0.report) } ?? .null,
                                      "stop": run.subagentEnd.map { .string($0.stop) } ?? .null,
                                      "label": run.judgments.label.map(JSONValue.number) ?? .null,
                                      "record": run.runs.last.map(json) ?? .null,
                                      "judgments": .array(run.judgments.map(json))]
                text += String(decoding: try enc.encode(obj), as: UTF8.self) + "\n"
            }
        } else if rows.isEmpty {
            text = "No subagent runs recorded.\n"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            text = "started      run       agent     model                     label  judgments\n"
            for (_, run) in rows {
                let label = run.judgments.label.map { String(format: "%.2f", $0) } ?? "–"
                text += [f.string(from: run.header.createdAt), String(run.header.id.uuidString.prefix(8)).lowercased(),
                         (run.header.agent ?? "").padding(toLength: 9, withPad: " ", startingAt: 0),
                         String(run.model.suffix(25)).padding(toLength: 25, withPad: " ", startingAt: 0),
                         label.padding(toLength: 6, withPad: " ", startingAt: 0),
                         run.judgments.latestByJudge.map(\.summary).joined(separator: " · ")].joined(separator: " ") + "\n"
                text += "  " + run.displayTitle + "\n"
            }
        }
        if let file = o.outFile {
            try text.write(toFile: (file as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
            out("Wrote \(rows.count) runs to \(file).\n")
        } else {
            out(text)
        }
    }

    /// `kurtkode prompts`: the system prompt's templates, as Settings → Prompts shows them.
    static func prompts(_ args: [String], cwd: URL, settings: AppSettings, options o: Parsed,
                        out: @Sendable (String) -> Void) async throws {
        let root = Workspace(path: cwd.path).root
        let templates = PromptTemplates.standard(project: root)
        let names = PromptTemplates.shared + templates.styles.map { "style-" + $0 }
        switch args.first ?? "list" {
        case "list":
            for name in names {
                guard let s = templates.source(name) else { continue }
                let from = s.isDefault ? "default" : s.url.path.hasPrefix(PromptTemplates.userFolder.path) ? "yours" : "project"
                out(name.padding(toLength: 18, withPad: " ", startingAt: 0) + from.padding(toLength: 9, withPad: " ", startingAt: 0)
                    + (s.isDefault ? "" : s.url.path) + "\n")
            }
        case "show":
            guard let name = args.dropFirst().first else { throw Failure(description: "kurtkode prompts show NAME") }
            guard let s = templates.source(name) else { throw Failure(description: "no template named \(name)") }
            out(s.text.hasSuffix("\n") ? s.text : s.text + "\n")
        case "reset":
            let user = PromptTemplates.userFolder
            let targets = o.all ? PromptTemplates.shared + ["style-detailed", "style-lean"] : Array(args.dropFirst().prefix(1))
            guard !targets.isEmpty else { throw Failure(description: "kurtkode prompts reset NAME | --all") }
            for name in targets where FileManager.default.fileExists(atPath: user.appending(path: name + ".md").path) {
                try PromptTemplates.resetUserOverride(name)
                out("removed \(user.appending(path: name + ".md").path)\n")
            }
        case "render":
            let run = settings.run
            let mode = try o.mode.map { m in
                guard let mode = PermissionMode(rawValue: m) else { throw Failure(description: "--mode wants ask, acceptEdits, plan or fullAuto") }
                return mode
            } ?? .ask
            var builder = SystemPromptBuilder(workspace: Workspace(path: cwd.path), tools: AllTools.all, mode: mode,
                                              userPrompt: run.systemPrompt)
            builder.sandbox = run.sandbox(for: mode)
            builder.style = try o.style.map { name in
                guard let s = PromptStyle(rawValue: name), templates.has(style: s) else {
                    throw Failure(description: "no style named \(name) (kurtkode prompts list)")
                }
                return s
            } ?? run.promptStyle ?? .detailed
            out(await builder.build() + "\n")
        default:
            throw Failure(description: "kurtkode prompts list | show NAME | reset NAME|--all | render")
        }
    }

    /// An id or prefix (any project), or the latest session in `cwd`.
    static func resolve(_ spec: String?, store: SessionStore, cwd: URL) async throws -> Session {
        let all = try await store.list()
        let match: SessionSummary?
        if let spec, spec != "last" {
            let hits = all.filter { $0.id.uuidString.lowercased().hasPrefix(spec.lowercased()) }
            guard hits.count < 2 else {
                throw Failure(description: "\(spec) matches \(hits.count) sessions: "
                              + hits.prefix(5).map { $0.id.uuidString.prefix(8).lowercased() }.joined(separator: ", "))
            }
            match = hits.first
        } else {
            let root = Workspace(path: cwd.path).root
            match = all.first { CLISession.sameFolder($0.workspace, root) }      // as `-c` finds it
        }
        guard let id = match?.id, let s = try await store.load(id) else {
            throw Failure(description: spec.map { "no session \($0)" } ?? "no sessions in \(cwd.path)")
        }
        return s
    }

    static func turns(_ s: Session) -> [TurnEntry] {
        SessionTimeline.items(s).compactMap { if case .turn(let t) = $0, t.number > 0 { t } else { nil } }
    }

    static func turn(_ s: Session, _ n: Int?) throws -> TurnEntry {
        guard let n else { throw Failure(description: "say which turn: --turn N") }
        guard let t = turns(s).first(where: { $0.number == n }) else {
            throw Failure(description: "no turn \(n) (this session has \(turns(s).count))")
        }
        return t
    }

    // MARK: inspect

    static func inspect(_ s: Session, wire: URL, options o: Parsed, store: SessionStore, settings: AppSettings,
                        out: (String) -> Void) throws {
        if let n = o.turn {
            let t = try turn(s, n)
            let record = WireLog.read(wire, replyID: t.reply.id)
            if o.json {
                var obj: [String: JSONValue] = ["turn": .number(Double(t.number)), "flags": .array(t.flags.map(JSONValue.string)),
                                                "reply": encode(t.reply), "calls": .array(t.calls.map { c in
                                                    ["call": encode(c.call), "result": c.result.map(encode) ?? .null] })]
                if let record { obj["wire"] = encode(record) }
                out(pretty(.object(obj)) + "\n")
                return
            }
            out(turnText(t, record: record, settings: settings, replays: Replay.load(wire, sourceReply: t.reply.id).count,
                         cost: s.costs.last { $0.reply == t.reply.id }))
            return
        }
        let stats = SessionStats(s)
        if o.json {
            let list: [JSONValue] = turns(s).map { t in
                let m = t.reply.meta
                return ["number": .number(Double(t.number)), "model": .string(m?.reportedModel ?? m?.requestedModel ?? ""),
                        "promptTokens": m?.usage.map { .number(Double($0.promptTokens)) } ?? .null,
                        "completionTokens": m?.usage.map { .number(Double($0.completionTokens)) } ?? .null,
                        "cacheReadTokens": m?.usage?.cacheReadTokens.map { .number(Double($0)) } ?? .null,
                        "cacheWriteTokens": m?.usage?.cacheWriteTokens.map { .number(Double($0)) } ?? .null,
                        "cost": m?.usage?.cost.map(JSONValue.number) ?? .null,
                        "timeToFirstToken": m?.timeToFirstToken.map(JSONValue.number) ?? .null,
                        "duration": m.map { .number($0.duration) } ?? .null,
                        "flags": .array(t.flags.map(JSONValue.string)),
                        "calls": .array(t.calls.map { c in
                            ["name": .string(c.call.name), "arguments": .string(c.call.arguments),
                             "isError": .bool(c.result?.toolResult?.isError ?? false),
                             "notes": .array((c.result?.toolResult?.notes ?? []).map(JSONValue.string))]
                        })]
            }
            out(pretty(["id": .string(s.header.id.uuidString), "title": .string(s.displayTitle), "model": .string(s.model),
                        "turns": .array(list)]) + "\n")
            return
        }
        var lines = [header(s, settings: settings),
                     "\(stats.turns) turns · \(stats.toolCalls) tool calls · \(stats.errors) errors · \(stats.notRun) not run · "
                     + "\(stats.lostReplies) lost · \(stats.promptTokens) in · \(stats.completionTokens) out"]
        let cost = stats.cost
        let costs = Dictionary(s.costs.map { ($0.reply, $0) }, uniquingKeysWith: { _, b in b })
        if !cost.isEmpty {
            var line = "Cost: " + cost.spentText() + " over \(cost.requests) requests"
            let purposes: [(CostEntry.Purpose, String)] = [(.summary, "summaries"), (.summaryAttempt, "summary attempts"),
                                                           (.retryAttempt, "retried attempts"), (.nudgedReply, "empty replies"),
                                                           (.fallbackReply, "fallback model"), (.review, "reviews")]
            let extra = purposes.compactMap { p, name in cost.byPurpose[p].map { String(format: "%@ $%.4f", name, $0) } }
            if !extra.isEmpty { line += " (" + extra.joined(separator: ", ") + ")" }
            line += String(format: " · list price $%.4f", cost.listPrice.total)
            if cost.chargedRequests > 0 { line += String(format: " · charged $%.4f on %d", cost.charged, cost.chargedRequests) }
            if cost.unpricedRequests > 0 { line += " · \(cost.unpricedRequests) unpriced" }
            lines.append(line)
        }
        lines.append("")
        lines.append(pad("#", 4) + pad("model", 26) + pad("in", 8) + pad("out", 7) + pad("1st tok", 9) + pad("time", 8)
                     + (cost.isEmpty ? "" : pad("cost", 11)) + "calls")
        for t in turns(s) {
            let m = t.reply.meta
            let calls = t.calls.map { c -> String in
                var n = c.call.name
                if let info = c.result?.toolResult {
                    if info.notes?.contains(where: { $0.hasPrefix("Not run") }) == true { n += "[not run]" }
                    else if info.isError { n += "[error]" }
                    if info.subagentRun != nil { n += "[subagent]" }
                }
                return n
            }.joined(separator: " ")
            let flags = t.flags.filter { $0 != "error" }
            lines.append(pad("\(t.number)", 4) + pad(String((m?.reportedModel ?? m?.requestedModel ?? "?").split(separator: "/").last ?? ""), 26)
                         + pad(m?.usage.map { "\($0.promptTokens)" } ?? "—", 8) + pad(m?.usage.map { "\($0.completionTokens)" } ?? "—", 7)
                         + pad(m?.timeToFirstToken.map { String(format: "%.1f s", $0) } ?? "—", 9)
                         + pad(m.map { String(format: "%.1f s", $0.duration) } ?? "—", 8)
                         + (cost.isEmpty ? "" : pad(costs[t.reply.id]?.spent.map { String(format: "$%.5f", $0) } ?? "—", 11))
                         + (calls.isEmpty ? "answer" : calls) + (flags.isEmpty ? "" : "  (" + flags.joined(separator: ", ") + ")"))
        }
        if !s.compactions.isEmpty { lines.append("\n\(s.compactions.count) compaction(s).") }
        out(lines.joined(separator: "\n") + "\n")
    }

    static func header(_ s: Session, settings: AppSettings) -> String {
        var h = "\(s.displayTitle)  (\(s.header.id.uuidString.prefix(8).lowercased()), \(s.model)"
        if let e = settings.endpoint(s.endpointID) { h += " on \(e.name)" }
        if let a = s.header.agent { h += ", \(a) subagent run" }
        if let f = s.header.forkedFrom { h += ", forked from \(f.uuidString.prefix(8).lowercased())" }
        return h + ")"
    }

    /// One step on one line: "thinking: I'll read the file…", "call read_file {…}".
    static func stepLine(_ s: ReplyStep) -> String {
        func short(_ t: String) -> String {
            let one = t.split(whereSeparator: \.isNewline).joined(separator: " ")
            return one.count > 100 ? one.prefix(100) + "…" : one
        }
        switch s.kind {
        case .thinking(let t): return "thinking: " + short(t)
        case .hiddenThinking: return "thinking, not shown"
        case .text(let t): return "text: " + short(t)
        case .call(let c): return "call \(c.name) " + short(c.arguments)
        case .server(let t): return "server: " + t
        case .webSearch(let q): return "web search: " + short(q)
        case .webResults(let r): return "web results: \(r.count)" + (r.first.map { " (" + short($0) + "…)" } ?? "")
        }
    }

    static func turnText(_ t: TurnEntry, record: WireRecord?, settings: AppSettings, replays: Int, cost: CostEntry? = nil) -> String {
        let m = t.reply.meta
        var lines = ["Turn \(t.number) · \(m?.reportedModel ?? m?.requestedModel ?? "?")"
                     + (m?.endpointID.flatMap { settings.endpoint($0)?.name }.map { " on " + $0 } ?? "")]
        if let u = m?.usage {
            lines.append("Tokens: \(u.promptTokens) prompt · \(u.completionTokens) completion · \(u.reasoningTokens) reasoning")
            if let c = u.cacheDetail { lines.append("Cache: " + c) }
            if let r = ReasoningShown(t.reply).summary { lines.append("Reasoning: " + r) }
        }
        if let e = cost {
            if let c = e.spentText() { lines.append("Cost: " + c) } else if let why = e.unpricedReason { lines.append("Cost: none (\(why))") }
            if let b = e.listPrice, e.charged != nil { lines.append(String(format: "List price: $%.6f", b.total)) }
            if let b = e.listPrice {
                lines.append(String(format: "  input $%.6f · cache read $%.6f · cache write $%.6f · output $%.6f", b.uncachedInput, b.cacheRead,
                                    b.cacheWrite5m + b.cacheWrite1h, b.output) + (b.reasoning > 0 ? String(format: " (thinking $%.6f)", b.reasoning) : ""))
            }
            if let r = e.reconciled { lines.append("Provider's record: " + (r.charged.map { String(format: "charged $%.6f", $0) } ?? "no charge") + (r.provider.map { " · " + $0 } ?? "")) }
            if let ids = e.requestIDs { lines.append("Request ids: " + ids.joined(separator: ", ")) }
        }
        if let m { lines.append("Timing: first token " + (m.timeToFirstToken.map { String(format: "%.2f s", $0) } ?? "—")
                                + String(format: " · %.2f s in all", m.duration)) }
        if let m { lines.append("Ended: \(m.stopReason.rawValue)" + (m.finishReason.map { " (finish: \($0.rawValue))" } ?? "")
                                + (m.error.map { " · " + $0 } ?? "")) }
        if !t.flags.isEmpty { lines.append("Flags: " + t.flags.joined(separator: ", ")) }
        if let r = record {
            lines.append("HTTP: " + r.statuses.map(String.init).joined(separator: " → ") + " · \(r.messages.count) messages sent · \(r.url)")
        } else {
            lines.append("No wire record.")
        }
        if replays > 0 { lines.append("Replays: \(replays) (kurtkode replay … or the Debug window)") }
        for n in m?.notes ?? [] { lines.append("Loop: " + n) }
        let (steps, ordered) = ReplySteps.steps(of: t.reply)
        if steps.count > 1 {
            lines += ["", "Steps" + (ordered ? " (in the order the server sent them):" : " (as stored: reasoning, text, calls):")]
            for s in steps { lines.append("  \(s.id + 1). " + Self.stepLine(s)) }
        }
        if let r = t.reply.reasoning, !r.isEmpty { lines += ["", "Reasoning:", r.trimmingCharacters(in: .whitespacesAndNewlines)] }
        lines += ["", "Reply:", t.reply.content.isEmpty ? "(no text)" : t.reply.content]
        for c in t.calls {
            lines += ["", "→ \(c.call.name) \(c.call.arguments)"]
            if let info = c.result?.toolResult {
                if let a = info.approval { lines.append("  approval: " + a.summary) }
                for p in info.argumentProblems ?? [] { lines.append("  argument problem: " + p) }
                for n in info.notes ?? [] { lines.append("  note: " + n) }
            }
            if let r = c.result {
                let body = r.content.split(separator: "\n", omittingEmptySubsequences: false)
                lines += body.prefix(20).map { "  " + $0 }
                if body.count > 20 { lines.append("  … (\(body.count - 20) more lines)") }
            } else {
                lines.append("  (no result)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: replay

    /// The effort comparison as a table: one line per reply.
    static func effortTable(_ rows: [Replay.EffortRow]) -> String {
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count) }
        var lines = [pad("effort", 13) + pad("reasoning", 11) + pad("shown", 7) + pad("out", 7) + pad("time", 8) + pad("cost", 10) + "did"]
        for r in rows {
            let did = r.error.map { "failed: " + $0.prefix(60) } ?? ((r.sameCallsAsOriginal ? "= " : "≠ ") + r.actions)
            lines.append(pad(r.level, 13) + pad(r.reasoningTokens.map(String.init) ?? "—", 11)
                         + pad(r.shownShare.map { String(format: "%.0f%%", $0 * 100) } ?? "—", 7)
                         + pad(r.outputTokens.map(String.init) ?? "—", 7)
                         + pad(r.duration.map { String(format: "%.1f s", $0) } ?? "—", 8)
                         + pad(r.cost.map { (r.costIsEstimate ? "≈" : "") + String(format: "$%.4f", $0) } ?? "—", 10) + did)
        }
        lines.append("(= the same tool calls as the original, ≠ different ones)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func replay(_ s: Session, wire: URL, options o: Parsed, settings: AppSettings,
                       out: @escaping @Sendable (String) -> Void) async throws {
        let t = try turn(s, o.turn)
        guard let record = WireLog.read(wire, replyID: t.reply.id) else {
            throw Failure(description: "turn \(t.number) has no wire record (requests are recorded while the app's setting is on)")
        }
        let endpoint: Endpoint
        let model: String
        if let spec = o.model {
            (endpoint, model) = try CLIOptions.resolveModel(spec, settings: settings)
        } else {
            guard let e = (t.reply.meta?.endpointID).flatMap({ settings.endpoint($0) }) ?? settings.endpoint(s.endpointID) else {
                throw Failure(description: "the turn's endpoint isn't saved any more; say which with -m ENDPOINT:MODEL")
            }
            endpoint = e
            model = t.reply.meta?.requestedModel ?? s.model
        }
        var system: String?
        if let f = o.systemFile { system = try String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8) }
        // Several levels: replay once per level and compare them (--reasoning low,medium,high; "all" for the model's).
        if let r = o.reasoning, r.contains(",") || r == "all" {
            let levels = r == "all" ? Replay.effortLevels(api: endpoint.kind.api, model: model)
                : r.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !o.json { out("Replaying turn \(t.number) on \(model) (\(endpoint.name)) at \(levels.joined(separator: ", "))…\n") }
            let client = ChatClient(endpoint: endpoint, apiKey: settings.apiKey(for: endpoint))
            let rs = await Replay.sweep(record, client: client, endpointName: endpoint.name, endpointID: endpoint.id, model: model,
                                        levels: levels, keepProvider: endpoint.id == t.reply.meta?.endpointID, wire: wire)
            let rows = Replay.effortRows(original: t.reply, replays: rs)
            if o.json {
                out(pretty(.array(rows.map { r in
                    ["level": .string(r.level), "reasoningTokens": r.reasoningTokens.map { .number(Double($0)) } ?? .null,
                     "shownShare": r.shownShare.map(JSONValue.number) ?? .null,
                     "outputTokens": r.outputTokens.map { .number(Double($0)) } ?? .null, "actions": .string(r.actions),
                     "sameCallsAsOriginal": .bool(r.sameCallsAsOriginal), "duration": r.duration.map(JSONValue.number) ?? .null,
                     "cost": r.cost.map(JSONValue.number) ?? .null, "error": r.error.map(JSONValue.string) ?? .null]
                })) + "\n")
            } else {
                out(effortTable(rows))
            }
            return
        }
        let options = ReplayOptions(model: model, temperature: o.temperature,
                                    reasoningEffort: o.reasoning.map { $0 == "default" ? "" : $0 }, systemPrompt: system,
                                    keepProvider: endpoint.id == t.reply.meta?.endpointID)
        if !o.json { out("Replaying turn \(t.number) on \(model) (\(endpoint.name))…\n") }
        let client = ChatClient(endpoint: endpoint, apiKey: settings.apiKey(for: endpoint))
        let r = await Replay.run(record, client: client, endpointName: endpoint.name, endpointID: endpoint.id, options: options)
        try? Replay.save(r, wire: wire)
        let c = Replay.compare(original: t.reply, replay: r.reply)
        if o.json {
            out(pretty(["replay": encode(r.reply), "sameToolCalls": .bool(c.sameToolCalls), "sameText": .bool(c.sameText),
                        "toolCallDifferences": .array(c.toolCallDifferences.map(JSONValue.string)),
                        "warnings": .array(r.warnings.map(JSONValue.string)), "id": .string(r.id.uuidString)]) + "\n")
            return
        }
        var lines = r.warnings.map { "! " + $0 }
        if let e = r.reply.meta?.error { lines.append("! " + e) }
        lines.append(c.sameToolCalls ? "Same tool calls." : "Different tool calls:")
        lines += c.toolCallDifferences.map { "  " + $0 }
        if !c.sameText { lines.append("The text differs.") }
        func f(_ v: Double?, _ fmt: String) -> String { v.map { String(format: fmt, $0) } ?? "—" }
        func i(_ v: Int?) -> String { v.map(String.init) ?? "—" }
        lines += ["", pad("", 18) + pad("original", 12) + "replay",
                  pad("ended", 18) + pad(c.original.stop, 12) + c.replay.stop,
                  pad("prompt tokens", 18) + pad(i(c.original.promptTokens), 12) + i(c.replay.promptTokens),
                  pad("output tokens", 18) + pad(i(c.original.completionTokens), 12) + i(c.replay.completionTokens),
                  pad("first token", 18) + pad(f(c.original.timeToFirstToken, "%.2f s"), 12) + f(c.replay.timeToFirstToken, "%.2f s"),
                  pad("duration", 18) + pad(f(c.original.duration, "%.1f s"), 12) + f(c.replay.duration, "%.1f s"),
                  "", "Replay's reply:", r.reply.content.isEmpty ? "(no text)" : r.reply.content]
        lines += r.reply.toolCalls.map { "→ \($0.name) \($0.arguments)" }
        lines.append("\nSaved as replay \(r.id.uuidString.prefix(8).lowercased()) (the Debug window's Replays tab lists it).")
        out(lines.joined(separator: "\n") + "\n")
    }

    // MARK: export

    static func export(_ s: Session, options o: Parsed, store: SessionStore, out: (String) -> Void) async throws {
        let runs = s.header.isSubagent ? [] : await store.subagentRuns(of: s.header)
        let format = o.format ?? (o.outFile?.hasSuffix(".json") == true ? "json" : "markdown")
        let data: Data
        switch format {
        case "json": data = try SessionExport.json(s, runs: runs)
        case "markdown", "md": data = Data(SessionExport.markdown(s, runs: runs).utf8)
        default: throw Failure(description: "--format is markdown or json")
        }
        if let file = o.outFile {
            try data.write(to: URL(fileURLWithPath: (file as NSString).expandingTildeInPath))
            out("Wrote \(file) (\(data.count / 1024) KB).\n")
        } else {
            out(String(decoding: data, as: UTF8.self) + "\n")
        }
    }

    // MARK: -

    static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count) }

    static func encode<T: Encodable>(_ v: T) -> JSONValue {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(v)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
    }

    static func pretty(_ v: JSONValue) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    // MARK: runs

    static func runs(store: SessionStore, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        var rows = try await store.runRecords()
        if let since = o.since {
            let cutoff: Date
            if since.hasSuffix("d"), let days = Double(since.dropLast()) {
                cutoff = Date().addingTimeInterval(-days * 86_400)
            } else {
                guard let d = DayFormat.formatter(zone: .current).date(from: since) else { throw Failure(description: "--since takes YYYY-MM-DD or Nd (days)") }
                cutoff = d
            }
            rows = rows.filter { $0.run.started >= cutoff }
        }
        if let agent = o.agent { rows = rows.filter { $0.run.agent == agent } }
        var judgments = try await store.mainRunJudgments()
        for (_, run) in try await store.judgedRuns() where !run.judgments.isEmpty { judgments[run.header.id] = run.judgments }
        var text = ""
        if o.json {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.sortedKeys]
            for r in rows {
                var obj: [String: JSONValue] = ["session": .string(r.session.id.uuidString), "workspace": r.session.workspace.map(JSONValue.string) ?? .null]
                obj["record"] = (try? enc.encode(r.run)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
                if let js = judgments[r.run.id] {
                    obj["judgments"] = .array(js.map { (try? enc.encode($0)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null })
                }
                if let e = r.end { obj["delegation"] = ["taskBytes": e.taskBytes.map { .number(Double($0)) } ?? .null,
                                                        "reportBytes": e.reportBytes.map { .number(Double($0)) } ?? .null] }
                text += String(decoding: try enc.encode(JSONValue.object(obj)), as: UTF8.self) + "\n"
            }
        } else if o.csv {
            text = runsCSV(rows, judgments: judgments)
        } else {
            text = runsTable(rows)
        }
        if let file = o.outFile {
            try text.write(toFile: (file as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
            out("Wrote \(rows.count) runs to \(file).\n")
        } else {
            out(text)
        }
    }

    static let runColumns = [
        "run", "session", "workspace", "user_message", "parent_run", "task_call", "agent", "definition_hash", "system_prompt_hash",
        "api", "host", "model", "endpoint", "prompt_style", "temperature", "max_output_tokens", "started", "ended", "wall_s", "model_s",
        "requests", "unpriced_requests", "list_total", "list_uncached_input", "list_cache_read", "list_cache_write_5m",
        "list_cache_write_1h", "list_output", "list_reasoning", "list_searches", "charged", "prompt_tokens", "cache_read_tokens",
        "cache_write_tokens", "completion_tokens", "reasoning_tokens", "searches", "stop", "steps", "tool_calls", "tool_errors",
        "denied", "files_changed", "compactions", "final_reply_bytes", "task_hash", "task_bytes", "task_text",
        "delegated_task_bytes", "report_bytes", "children", "children_list_total", "build_version", "build_commit", "build_dirty",
        "executable_hash", "machine_chip", "machine_memory_gb", "quantization", "loaded_context", "judgment",
        "task_kind", "task_importance", "task_verify", "label", "parent_verdict", "grader_verdict", "user_verdict",
        "check_problems", "hard_failure", "recheck_exit",
        "implicit", "reasoning", "attempt_of", "last_check", "last_check_exit", "files_not_named", "unfinished_todos",
        "cache_share",
    ]

    static func runsCSV(_ rows: [(session: SessionHeader, run: AgentRunRecord, end: SubagentEnd?)],
                        judgments: [UUID: [RunJudgment]] = [:]) -> String {
        let iso = ISO8601DateFormatter()
        func field(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func num(_ d: Double?) -> String { d.map { String(format: "%.8f", $0) } ?? "" }
        var lines = [runColumns.joined(separator: ",")]
        for (session, r, end) in rows {
            let t = r.totals, p = t.listPrice
            let priced = t.requests > t.unpricedRequests
            var cells: [String] = [
                r.id.uuidString, session.id.uuidString, session.workspace ?? "", r.userMessage?.uuidString ?? "",
                r.parentRun?.uuidString ?? "", r.taskCall ?? "", r.agent, r.definitionHash, r.systemPromptHash,
                r.setup.api.rawValue, r.setup.host ?? "", r.setup.model, r.setup.endpointID?.uuidString ?? "",
                r.setup.promptStyle ?? "", r.setup.temperature.map { "\($0)" } ?? "", "\(r.setup.maxOutputTokens)",
                iso.string(from: r.started), iso.string(from: r.ended), String(format: "%.2f", t.wallSeconds), String(format: "%.2f", t.modelSeconds),
                "\(t.requests)", "\(t.unpricedRequests)", priced ? num(p.total) : "", priced ? num(p.uncachedInput) : "",
                priced ? num(p.cacheRead) : "", priced ? num(p.cacheWrite5m) : "", priced ? num(p.cacheWrite1h) : "",
                priced ? num(p.output) : "", priced ? num(p.reasoning) : "", priced ? num(p.searches) : "", num(t.charged),
                "\(t.promptTokens)", "\(t.cacheReadTokens)", "\(t.cacheWriteTokens)", "\(t.completionTokens)", "\(t.reasoningTokens)",
                "\(t.searches)", r.outcome.stop, "\(r.outcome.steps)", r.outcome.toolCalls.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "),
                "\(r.outcome.toolErrors)", "\(r.outcome.denied)", r.outcome.filesChanged.joined(separator: " "), "\(r.outcome.compactions)",
                "\(r.outcome.finalReplyBytes)", r.task.hash, "\(r.task.bytes)", String(r.task.text.prefix(300)),
                end?.taskBytes.map { "\($0)" } ?? "", end?.reportBytes.map { "\($0)" } ?? "", "\(r.children.count)",
                r.children.isEmpty ? "" : num(r.children.compactMap(\.listPrice).reduce(0, +)),
                r.build.version, r.build.gitCommit ?? "", r.build.gitDirty.map { $0 ? "yes" : "no" } ?? "", r.build.executableHash ?? "",
                r.machine?.chip ?? "", r.machine?.memoryGB.map { "\($0)" } ?? "", r.localModel?.quantization ?? "",
                r.localModel?.loadedContextLength.map { "\($0)" } ?? "", r.judgment.map { "\($0)" } ?? "",
            ]
            cells += judgmentCells(r, judgments[r.id] ?? [])
            cells += signalCells(r, judgments[r.id] ?? [])
            lines.append(cells.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A run's implicit judgment, setup extras, end-of-run signals and cache share, for the CSV.
    static func signalCells(_ r: AgentRunRecord, _ js: [RunJudgment]) -> [String] {
        let implicit: String = js.latestByJudge.first { $0.judge == .implicit }?.note ?? ""
        var exit = ""
        if let c = r.signals?.lastCheck { exit = c.timedOut == true ? "timeout" : c.exitCode.map { String($0) } ?? "" }
        let notNamed: String = r.signals?.filesNotNamed.joined(separator: " ") ?? ""
        let todos: String = r.signals.map { String($0.unfinishedTodos.count) } ?? ""
        let t = r.totals
        let share: String = t.promptTokens > 0 ? String(format: "%.3f", Double(t.cacheReadTokens) / Double(t.promptTokens)) : ""
        return [implicit, r.setup.reasoning ?? "", r.attemptOf?.uuidString ?? "", r.signals?.lastCheck?.command ?? "", exit,
                notNamed, todos, share]
    }

    /// A run's card and judgments, for the CSV.
    static func judgmentCells(_ r: AgentRunRecord, _ js: [RunJudgment]) -> [String] {
        let latest = js.latestByJudge
        func verdict(_ k: RunJudgment.Judge) -> String { latest.first { $0.judge == k }?.verdict.map { "\($0)" } ?? "" }
        let checks = latest.first { $0.judge == .checks }?.checks
        return [r.task.card?.kind?.rawValue ?? "", r.task.card?.importance?.rawValue ?? "", r.task.card?.verify ?? "",
                js.label.map { String(format: "%.3f", $0) } ?? "", verdict(.parent), verdict(.grader), verdict(.user),
                checks?.problems.joined(separator: "; ") ?? "", checks.map { $0.isHardFailure ? "yes" : "no" } ?? "",
                latest.first { $0.judge == .recheck }?.checks?.verifyExitCode.map { "\($0)" } ?? ""]
    }

    static func runsTable(_ rows: [(session: SessionHeader, run: AgentRunRecord, end: SubagentEnd?)]) -> String {
        guard !rows.isEmpty else { return "No recorded runs.\n" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        var lines = ["started      agent      model                        reqs  list price     tokens in/out     cache   time  stop        task"]
        for (_, r, _) in rows {
            let t = r.totals
            let price = t.requests == t.unpricedRequests ? "–" : String(format: "$%.4f", t.listPrice.total) + (t.unpricedRequests > 0 ? "+" : "")
            let agent = (r.parentRun == nil ? "" : " ") + r.agent
            lines.append([f.string(from: r.started), agent.padding(toLength: 10, withPad: " ", startingAt: 0),
                          String(r.setup.model.suffix(28)).padding(toLength: 28, withPad: " ", startingAt: 0),
                          String(format: "%4d", t.requests), price.padding(toLength: 13, withPad: " ", startingAt: 0),
                          "\(t.promptTokens)/\(t.completionTokens)".padding(toLength: 17, withPad: " ", startingAt: 0),
                          (t.promptTokens > 0 && t.cacheReadTokens > 0 ? String(format: "%4.0f%%", 100 * Double(t.cacheReadTokens) / Double(t.promptTokens)) : "   –"),
                          String(format: "%5.0fs", t.wallSeconds), r.outcome.stop.padding(toLength: 11, withPad: " ", startingAt: 0),
                          String(r.task.text.replacingOccurrences(of: "\n", with: " ").prefix(50))].joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: cost check, calibrate

    static func costCheck(store: SessionStore, settings: AppSettings, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        guard let dayText = o.day else { throw Failure(description: "cost check needs --day YYYY-MM-DD") }
        if let stale = PriceList.staleness() { out(stale) }
        let zone: TimeZone
        switch o.timeZone?.lowercased() {
        case nil, "utc": zone = TimeZone(identifier: "UTC")!
        case "local": zone = .current
        default:
            guard let z = TimeZone(identifier: o.timeZone!) else { throw Failure(description: "unknown time zone \(o.timeZone!)") }
            zone = z
        }
        guard let start = DayFormat.formatter(zone: zone).date(from: dayText) else { throw Failure(description: "--day takes YYYY-MM-DD") }
        let day = DayFormat.day(starting: start, zone: zone)          // 23 or 25 hours when the clocks change
        var entries = try await store.costEntries().map(\.entry).filter { day.contains($0.start) }
        func endpointName(_ e: CostEntry) -> String { e.endpointID.flatMap { settings.endpoint($0)?.name } ?? e.host ?? "?" }
        if let name = o.endpoint { entries = entries.filter { endpointName($0).lowercased() == name.lowercased() } }

        struct Sum: Encodable {
            var endpoint = "", model = ""
            var requests = 0, uncachedInput = 0, cacheRead = 0, cacheWrite = 0, output = 0, reasoning = 0, searches = 0
            var listPrice = 0.0, charged = 0.0, chargedRequests = 0, reconciled = 0, partial = 0, unpriced = 0
        }
        var sums: [String: Sum] = [:]
        for e in entries {
            let model = e.servedModel ?? e.requestedModel
            let key = endpointName(e) + "\u{0}" + model
            var s = sums[key] ?? Sum(endpoint: endpointName(e), model: model)
            s.requests += 1
            if let u = e.tokens {
                let read = u.cacheReadTokens ?? 0, write = u.cacheWriteTokens ?? 0
                s.uncachedInput += max(0, u.promptTokens - read - write)
                s.cacheRead += read
                s.cacheWrite += write
                s.output += u.completionTokens
                s.reasoning += u.reasoningTokens
                s.searches += u.webSearches ?? 0
            }
            if let b = e.listPrice { s.listPrice += b.total } else { s.unpriced += 1 }
            if let c = e.charged { s.charged += c; s.chargedRequests += 1 }
            if e.reconciled != nil { s.reconciled += 1 }
            if e.billing == .partial { s.partial += 1 }
            sums[key] = s
        }
        let rows = sums.values.sorted { ($0.endpoint, $0.model) < ($1.endpoint, $1.model) }
        if o.json {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            out(String(decoding: try enc.encode(rows), as: UTF8.self) + "\n")
            return
        }
        guard !rows.isEmpty else { out("No recorded requests on \(dayText) (\(zone.identifier)).\n"); return }
        var lines = ["Requests on \(dayText), \(zone.identifier):", "",
                     "endpoint              model                          reqs   uncached   cache rd   cache wr     output   thinking  srch   list price    charged"]
        for r in rows {
            lines.append([r.endpoint.padding(toLength: 21, withPad: " ", startingAt: 0),
                          String(r.model.suffix(30)).padding(toLength: 30, withPad: " ", startingAt: 0),
                          String(format: "%5d %10d %10d %10d %10d %10d %5d", r.requests, r.uncachedInput, r.cacheRead, r.cacheWrite,
                                 r.output, r.reasoning, r.searches),
                          r.unpriced == r.requests ? "           –" : String(format: "%12.6f", r.listPrice),
                          r.chargedRequests == 0 ? "         –" : String(format: "%10.6f", r.charged)].joined(separator: " "))
            var notes: [String] = []
            if r.unpriced > 0, r.unpriced < r.requests { notes.append("\(r.unpriced) unpriced") }
            if r.partial > 0 { notes.append("\(r.partial) ended early (billing uncertain)") }
            if r.reconciled > 0 { notes.append("\(r.reconciled) checked against the provider's record") }
            if !notes.isEmpty { lines.append(String(repeating: " ", count: 22) + notes.joined(separator: "; ")) }
        }
        lines += ["", "Compare with the provider's console for the same key and day: its input, cache and output token counts and its cost.",
                  "Check the console's time zone and pass it with --tz."]
        out(lines.joined(separator: "\n") + "\n")
    }

    /// The calibration prompt: about 9,000 tokens, the same every time, so its cost is predictable and cacheable.
    static let calibrationPrefix: String = {
        let words = ["amber", "basalt", "cobalt", "dune", "ember", "fjord", "garnet", "harbor", "indigo", "juniper"]
        var lines: [String] = []
        for i in 1...400 {
            var picked: [String] = []
            for k in 0..<8 { picked.append(words[(i * 7 + k * 3) % words.count]) }
            lines.append("Calibration line " + String(format: "%04d", i) + ": " + picked.joined(separator: " ") + ".")
        }
        return lines.joined(separator: "\n")
    }()

    static func calibrate(store: SessionStore, settings: AppSettings, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        guard let spec = o.model else { throw Failure(description: "cost calibrate needs -m ENDPOINT:MODEL") }
        let (endpoint, model) = try CLIOptions.resolveModel(spec, settings: settings)
        let maxOutput = o.maxOutput ?? 1024
        let short = [ChatMessage.system("You are a calibration probe. Follow the instruction exactly."), .user("Reply with exactly: OK")]
        let long = [ChatMessage.system("You are a calibration probe.\n\n" + calibrationPrefix),
                    .user("How many lines above start with \"Calibration line\"? Reply with the number only.")]
        let plan: [(String, [ChatMessage])] = [("short", short), ("long, writes the cache", long), ("long again, reads the cache", long)]
        let client = ChatClient(endpoint: endpoint, apiKey: o.yes ? settings.apiKey(for: endpoint) : nil)
        let price = await PriceLookup.lookup(client: client, model: model)
        let longTokens = TokenEstimator().tokens(long)
        var estimate = "no list price known for \(model)"
        if case .known(let p, _, _) = price {
            let write = endpoint.kind.api == .anthropic ? longTokens : 0
            func cost(_ out: Int) -> Double {
                let a = Usage(promptTokens: 30, completionTokens: out)
                let b = Usage(promptTokens: longTokens, completionTokens: out, cacheWriteTokens: write)
                let c = Usage(promptTokens: longTokens, completionTokens: out, cacheReadTokens: longTokens)
                var total = 0.0
                for u in [a, b, c] { total += CostBreakdown(u, price: p, source: "", priceList: "").total }
                return total
            }
            estimate = String(format: "about $%.4f at list price with 200 output tokens each, at most $%.4f with %d (~%d-token prompt)",
                              cost(200), cost(maxOutput), maxOutput, longTokens)
        }
        guard o.yes else {
            out("Would send 3 requests to \(model) on \(endpoint.name): " + plan.map(\.0).joined(separator: "; ") + ".\n"
                + "Cost: \(estimate).\nRun again with --yes to send them.\n")
            return
        }
        let header = SessionHeader(endpointID: endpoint.id, model: model, workspace: nil)
        try await store.create(header)
        try await store.append(.title("Cost calibration: \(model)"), to: header.id)
        let run = UUID()
        out("Sending 3 requests to \(model) on \(endpoint.name) (\(estimate)).\n")
        for (label, messages) in plan {
            let started = Date()
            let request = ChatRequest(model: model, messages: messages, maxTokens: maxOutput)
            let reply = await TurnRunner.run(client: client, request: request, limits: TurnLimits(maxTokens: maxOutput, wallClock: 300)) { _ in }
            try await store.append(.message(messages.last!), to: header.id)
            try await store.append(.message(reply), to: header.id)
            let p = await PriceLookup.lookup(client: client, model: CostEntry.pricedModel(reply))
            var e = CostEntry.make(reply: reply, purpose: .reply, run: run, agent: "calibration", client: client,
                                   endpointID: endpoint.id, start: started, price: p)
            if let checked = await CostEntry.reconcile([e], clients: [client]).first { e = checked }
            try await store.append(.cost(e), to: header.id)
            let u = e.tokens
            out(String(format: "  %@: in %d (cache read %d, write %d), out %d, list %@%@%@\n", label, u?.promptTokens ?? 0,
                       u?.cacheReadTokens ?? 0, u?.cacheWriteTokens ?? 0, u?.completionTokens ?? 0,
                       e.listPrice.map { String(format: "$%.6f", $0.total) } ?? "–",
                       e.charged.map { String(format: ", charged $%.6f", $0) } ?? "",
                       reply.meta?.stopReason == .completed ? "" : " (\(reply.meta?.error ?? "\(reply.meta?.stopReason ?? .failed)"))"))
        }
        let f = DayFormat.formatter()
        out("Recorded in session \(header.id.uuidString.prefix(8)). Tomorrow, compare `kurtkode cost check --day \(f.string(from: Date())) "
            + "--endpoint \"\(endpoint.name)\"` with the console.\n")
    }

    static func reconcileCosts(store: SessionStore, settings: AppSettings, options o: Parsed, out: @escaping @Sendable (String) -> Void) async throws {
        var since = Date().addingTimeInterval(-7 * 86_400)
        if let s = o.since, s.hasSuffix("d"), let days = Double(s.dropLast()) { since = Date().addingTimeInterval(-days * 86_400) }
        let (checked, pending) = await CostReconciler.run(store: store, since: since, minAge: 0, limit: 500, client: { id in
            settings.endpoint(id).map { ChatClient(endpoint: $0, apiKey: settings.apiKey(for: $0)) }
        }, report: { out($0 + "\n") })
        out(pending == 0 ? "Nothing to check.\n" : "Checked \(checked) of \(pending).\n")
    }
}
