import AgentCore
import Foundation
import KurtkodeCLI

/// One task through the live cascade (REAL_TASKS_PLAN.md, Measurement "Cascade, live"): a main run on the cheap model,
/// gold, and, when the run earned an escalation offer, the stronger model's hand-over run and gold again.
public struct CascadeRun: Codable, Sendable {
    public var task: String
    public var kind: String
    public var trial: Int
    public var cheap: String
    public var strong: String
    public var commit: String
    /// The cheap model's main run: gold on the tree it left, how it ended, what it cost.
    public var cheapGold: CheckResult
    public var cheapStop: String
    public var cheapSteps: Int
    public var cheapSeconds: Double
    public var cheapListPrice: Double?
    public var cheapCharged: Double?
    public var cheapReport: String
    /// The offer's reasons (empty: no offer) and the model it went to.
    public var reasons: [String]
    public var offeredTo: String?
    /// After the hand-over (nil: no offer).
    public var strongGold: CheckResult?
    public var strongStop: String?
    public var strongSteps: Int?
    public var strongSeconds: Double?
    public var strongListPrice: Double?
    public var strongCharged: Double?
    public var strongReport: String?
    /// The change after each stage (`git diff --binary` from the fixture's base commit, so a stage's own commits count;
    /// cut at 200 KB).
    public var cheapDiff: String
    public var strongDiff: String?
    /// The session could not run (setup, a thrown error); the run is not a model failure.
    public var infra: String?
    public var transcript: [ChatMessage]
    public var recordedAt = Date()

    /// Gold at the end of the cascade: the hand-over's when there was one.
    public var finalPassed: Bool { strongGold?.passed ?? cheapGold.passed }
    public var listPrice: Double { (cheapListPrice ?? 0) + (strongListPrice ?? 0) }
}

public enum Cascade {
    /// Gold again for a recorded run, from its saved change: a fresh fixture with the last stage's diff applied and that
    /// stage's report. Nil when the fixture can't be made or the diff doesn't apply.
    public static func regold(_ run: CascadeRun, task: BankTask) -> CheckResult? {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-cascade-regold-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
              (try? task.setUp(dir)) != nil else { return nil }
        let diff = run.strongDiff ?? run.cheapDiff
        if !diff.isEmpty {
            let patch = dir.appending(path: ".git/cascade.patch")
            guard (try? Data(diff.utf8).write(to: patch)) != nil,
                  shell("cd \(q(dir.path)) && git apply --whitespace=nowarn \(q(patch.path))").status == 0 else { return nil }
        }
        var record = RunRecord()
        record.messages = run.transcript
        return TaskBank.gold(task, dir: dir, report: run.strongReport ?? run.cheapReport, record: record)
    }

    /// A data folder for the cascade's CLI sessions: the user's endpoints, a pool of just `cheap` (standard tier) and
    /// `strong` (frontier), so the product's own `Escalation.target` picks `strong`, and nothing else of the user's
    /// (no profiles, MCP servers or approvals). Sessions and snapshots land here, not in the app's folder.
    public static func makeSupport(at dir: URL, userSupport: URL, cheap: ModelTarget, strong: ModelTarget) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let endpoints = userSupport.appending(path: "endpoints.json")
        try FileManager.default.copyItem(at: endpoints, to: dir.appending(path: "endpoints.json"))
        let pool = ModelPool(entries: [
            PoolEntry(endpoint: "openrouter", model: cheap.model, providers: cheap.profile.providers, tier: .standard, roles: [.main]),
            PoolEntry(endpoint: "openrouter", model: strong.model, providers: strong.profile.providers, tier: .frontier, roles: [.main]),
        ])
        try pool.save(dir.appending(path: "pool.json"))
    }

    /// Runs `task` through the cascade in a CLI session on `support`'s data folder, as a user who takes every offer.
    public static func run(_ task: BankTask, cheap: ModelTarget, strong: ModelTarget, trial: Int, support: URL, commit: String,
                           contextLength: Int, maxTokens: Int, log: @escaping @Sendable (String) -> Void = { _ in }) async -> CascadeRun {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-cascade-\(task.id)-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        var out = CascadeRun(task: task.id, kind: task.card.kind?.rawValue ?? "", trial: trial, cheap: cheap.label, strong: strong.label,
                             commit: commit, cheapGold: CheckResult(passed: false, score: 0, notes: []), cheapStop: "none", cheapSteps: 0,
                             cheapSeconds: 0, cheapReport: "", reasons: [], cheapDiff: "", transcript: [])
        let prompt: String
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            prompt = try task.setUp(dir)
            // 11b: the project names its tests, so the session runs them after a main run that changed files. Kept out
            // of git's view, so gold doesn't count the file as a change.
            if let verify = task.card.verify {
                let folder = dir.appending(path: ".kurtkode")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: [TestSuite.key: verify]).write(to: folder.appending(path: "settings.json"))
                let exclude = dir.appending(path: ".git/info/exclude")
                let own = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
                try Data((own + "\n.kurtkode/\n").utf8).write(to: exclude)
            }
        } catch {
            out.infra = "fixture setup failed: \(error)"
            return out
        }

        let suite = "kurtkode-eval-cascade-\(UUID().uuidString.prefix(8))"
        guard let defaults = UserDefaults(suiteName: suite) else { out.infra = "no defaults"; return out }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(maxTokens, forKey: RunSettings.Key.maxTokens)
        defaults.set(task.maxSteps, forKey: RunSettings.Key.maxSteps)
        defaults.set(contextLength, forKey: RunSettings.Key.defaultContextLength)
        defaults.set(true, forKey: RunSettings.Key.escalationOffers)
        defaults.set(false, forKey: RunSettings.Key.escalationReview)
        defaults.set(cheap.skills, forKey: RunSettings.Key.builtinSkills)
        // No Keychain reads: both models get the eval's key, read once per process.
        var settings = AppSettings(support: support, defaults: defaults, environment: ["KURTKODE_NO_KEYCHAIN": "1"])
        for t in [cheap, strong] {
            var p = ModelProfile.defaults(endpointID: t.endpoint.id, model: t.model)
            p.contextLength = contextLength
            p.maxOutputTokens = maxTokens
            p.providers = t.profile.providers
            settings.profiles[p.key] = p
        }
        var options = CLIOptions()
        options.model = cheap.endpoint.name + ":" + cheap.model
        options.mode = .fullAuto
        options.maxSteps = task.maxSteps
        options.mcp = false
        options.subagents = false
        options.builtinSkills = cheap.skills
        let key = cheap.apiKey
        let recorder = Recorder()
        let cli: CLISession
        do {
            cli = try await CLISession(settings: settings, workspace: dir, options: options,
                                       makeClient: { e, _ in ChatClient(endpoint: e, apiKey: key) })
        } catch {
            out.infra = "session setup failed: \(error)"
            return out
        }
        cli.approve = { _ in .allow }
        cli.interactive = false                     // nobody pauses an eval run: the five-minute cache
        cli.onEvent = { recorder.record($0, log: log) }

        /// Sends `text` with the task's wall clock; the session's latest main run, or why there is none.
        func turn(_ text: String) async -> (run: AgentRunRecord?, seconds: Double, error: String?) {
            let start = Date()
            let work = Task { try await cli.send(text) }
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(task.wallClock))
                if !Task.isCancelled { log("  wall-clock limit reached; stopping"); work.cancel() }
            }
            var failure: String?
            do { _ = try await work.value } catch { failure = "\(error)" }
            watchdog.cancel()
            return (cli.session.runs.last { $0.agent == "main" }, Date().timeIntervalSince(start), failure)
        }
        func diff() -> String {
            let d = shell("git -C \(q(dir.path)) add -A -N . 2>/dev/null; git -C \(q(dir.path)) diff --binary \(Fixtures.base(dir))").output
            return d.utf8.count > 200_000 ? String(decoding: Data(d.utf8.prefix(200_000)), as: UTF8.self) + "\n… (cut)" : d
        }

        let first = await turn(SubagentSetup.taskText(prompt, card: task.card))
        out.cheapSeconds = first.seconds
        if let r = first.run {
            out.cheapStop = r.outcome.stop
            out.cheapSteps = r.outcome.steps
            out.cheapListPrice = r.totals.listPrice.total
            out.cheapCharged = r.totals.charged
        } else {
            out.infra = "the cheap run recorded nothing" + (first.error.map { ": " + $0 } ?? "")
        }
        let afterCheap = recorder.snapshot()
        out.cheapReport = afterCheap.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        out.cheapGold = TaskBank.gold(task, dir: dir, report: out.cheapReport, record: afterCheap)
        out.cheapDiff = diff()
        log("  \(task.id) #\(trial) cheap: \(out.cheapGold.passed ? "PASS" : "FAIL") \(out.cheapStop) \(out.cheapSteps) steps")

        if out.infra == nil, let offer = await cli.escalationOffer() {
            out.reasons = offer.reasons
            out.offeredTo = offer.toModel
            log("  \(task.id) #\(trial) offer to \(offer.toLabel): \(offer.reasonText)")
            if let handOver = await cli.decide(offer, accept: true) {
                let second = await turn(handOver)
                out.strongSeconds = second.seconds
                if let r = second.run, r.id != first.run?.id {
                    out.strongStop = r.outcome.stop
                    out.strongSteps = r.outcome.steps
                    out.strongListPrice = r.totals.listPrice.total
                    out.strongCharged = r.totals.charged
                } else {
                    out.infra = "the hand-over run recorded nothing" + (second.error.map { ": " + $0 } ?? "")
                }
                let afterStrong = recorder.snapshot()
                let report = afterStrong.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                out.strongReport = report
                out.strongGold = TaskBank.gold(task, dir: dir, report: report, record: afterStrong)
                out.strongDiff = diff()
            } else {
                out.infra = "the offer could not be taken (no endpoint for \(offer.toModel))"
            }
        }
        out.transcript = recorder.snapshot().messages
        return out
    }
}
