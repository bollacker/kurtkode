import AgentCore
import CryptoKit
import Foundation

/// A bank run as recorded once (EVAL_PLAN.md E1): what the subagent was asked and did, its report, the grounded checks,
/// the re-run check, gold, cost and time. Its fixture (the project as the run left it) is kept beside it, so it can be
/// judged again any number of times. A degraded copy is a run of its own, with its type and the run it came from.
public struct StoredRun: Codable, Sendable {
    public var id: String
    public var task: String
    public var kind: String
    public var agent: String
    public var card: TaskCard
    /// The subagent's model (`endpoint:model`).
    public var model: String
    public var trial: Int
    public var prompt: String
    public var report: String
    /// The checks at the run's end: what a parent sees with the report.
    public var checks: GroundedChecks
    /// The task's check run again after the run (as at the end of a parent's run): whether it ran, and its exit status.
    public var rechecked: Bool
    public var recheckExit: Int32?
    public var gold: CheckResult
    public var stop: String
    public var seconds: Double
    public var steps: Int
    public var toolCalls: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var listPrice: Double?
    public var unpricedRequests: Int
    /// Set when the run failed before doing any work, for a reason that isn't the model's (no provider, a model
    /// that won't load, an HTTP error), after one retry: left out of every rate.
    public var infra: String?
    /// A degraded copy: its type (`Degradation`) and the run it came from.
    public var degradation: String?
    public var parent: String?
    public var temperature: Double?
    public var contextLimit: Int?
    public var commit: String?
    public var recordedAt: Date
    public var runRecord: AgentRunRecord?
    public var transcript: [ChatMessage]
    /// The re-run check was stopped at its time limit: it didn't finish, which is neither a pass nor a failure
    /// (`recheckExit` is nil).
    public var recheckTimedOut: Bool? = nil
    /// The options that shape a run beyond its model and task (skills, prompt style, output limit, sandbox, context;
    /// `kurtkode-eval`'s `configFingerprint`), so resuming a set with other options is refused, not mixed in. Nil for
    /// runs recorded before 2026-11-03.
    public var config: String? = nil

    /// A grounded hard failure: at the run's end, or when its check ran again.
    public var groundedFailure: Bool { checks.isHardFailure || (rechecked && (recheckExit ?? 0) != 0) }
    /// Where a known failure comes from: the model itself, or a degradation type; nil for a run that passed gold.
    public var failureSource: String? { gold.passed ? nil : (degradation ?? "real") }
}

/// One judge's verdict on one stored run.
public struct StoredJudgment: Codable, Sendable {
    public var run: String
    public var outcome: JudgeOutcome
    public var at: Date
}

/// `eval-results/runs/<set>/`: one folder per run (`run.json`, `fixture.tgz`, `judgments.jsonl`).
public final class RunStore: @unchecked Sendable {
    public let root: URL
    private let lock = NSLock()

    public init(root: URL) { self.root = root }

    func folder(_ id: String) -> URL { root.appending(path: id) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// A run id from its parts, safe as a folder name.
    public static func id(task: String, model: String, trial: Int, degradation: String? = nil) -> String {
        let slug = model.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return "\(task)__\(String(slug))__t\(trial)" + (degradation.map { "__" + $0 } ?? "")
    }

    /// Saves a run and its fixture (the folder as it is, `.git` included, Python caches left out). The fixture goes
    /// to a temporary name and is renamed, and `run.json` is written last: a run is known only once both are whole.
    public func save(_ run: StoredRun, fixture: URL) throws {
        let dir = folder(run.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let partial = dir.appending(path: "fixture.tgz.partial"), whole = dir.appending(path: "fixture.tgz")
        let tar = shell("tar -czf \(q(partial.path)) --exclude __pycache__ -C \(q(fixture.path)) .")
        guard tar.status == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: tar.output])
        }
        guard rename(partial.path, whole.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        try Self.encoder.encode(run).write(to: dir.appending(path: "run.json"), options: .atomic)
    }

    /// Rewrites a run's record (its fixture stays as it is).
    public func update(_ run: StoredRun) throws {
        try Self.encoder.encode(run).write(to: folder(run.id).appending(path: "run.json"), options: .atomic)
    }

    public func runs() -> [StoredRun] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d in
            (try? Data(contentsOf: d.appending(path: "run.json"))).flatMap { try? Self.decoder.decode(StoredRun.self, from: $0) }
        }.sorted { $0.id < $1.id }
    }

    /// The run's fixture, unpacked into a new temporary folder (the caller removes it).
    public func restore(_ run: StoredRun) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-restore-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tar = shell("tar -xzf \(q(folder(run.id).appending(path: "fixture.tgz").path)) -C \(q(dir.path))")
        guard tar.status == 0 else { throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: tar.output]) }
        return dir
    }

    public func judgments(of id: String) -> [StoredJudgment] {
        lock.withLock {
            guard let text = try? String(contentsOf: folder(id).appending(path: "judgments.jsonl"), encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? Self.decoder.decode(StoredJudgment.self, from: Data($0.utf8)) }
        }
    }

    public func append(_ j: StoredJudgment) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        var line = try enc.encode(j)
        line.append(0x0A)
        try lock.withLock {
            let url = folder(j.run).appending(path: "judgments.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
        }
    }
}

/// A subagent's run of a bank task, before it's checked: what the eval needs to check, record and judge it.
struct SubagentTaskRun {
    var prompt: String
    var record: RunRecord
    var report: String
    var config: AgentConfig
    var workspace: Workspace
    var limits: TurnLimits
    var contextLimit: Int
    /// Why the fixture couldn't be made; the model wasn't called.
    var setupError: String? = nil
}

extension Runner {
    /// Runs `task` in `dir` (prepared here) the way a subagent would: its agent's tools, the subagent prompt with
    /// the default templates and no personal instructions, the task with its card's check.
    static func performSubagentTask(_ task: BankTask, on target: ModelTarget, dir: URL, limits: TurnLimits, sandbox: SandboxUse,
                                    makeClient: ClientFactory, log: @escaping @Sendable (String) -> Void) async -> SubagentTaskRun {
        var prompt = "", setupError: String?
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            prompt = try task.setUp(dir)
        } catch {
            log("  fixture setup failed: \(error)")
            setupError = "fixture setup failed: " + String(error.localizedDescription.prefix(300))
        }
        let workspace = Workspace(root: dir)
        let agent = AgentDefinition.builtIns.first { $0.name == task.agent } ?? .general
        let tools = agent.tools.map { names in AllTools.all.filter { names.contains($0.name) } } ?? AllTools.all
        let policy = PermissionPolicy(mode: .fullAuto)
        var limits = limits
        if target.endpoint.kind.api != .openai {
            limits.maxTokens = max(limits.maxTokens, 16_384)
            limits.wallClock = max(limits.wallClock, 900)
        }
        if let cap = target.profile.maxOutputTokens { limits.maxTokens = cap }
        let contextLimit = target.profile.contextLength ?? target.contextLength ?? 32_768
        var config = AgentConfig(tools: tools, maxSteps: task.maxSteps, limits: limits, policy: policy,
                                 approve: { _ in .allow }, shell: ShellState(cwd: dir),
                                 context: ContextBudget(limit: contextLimit, outputReserve: limits.maxTokens))
        config.maxToolOutputBytes = AgentConfig.toolOutputBytes(contextLimit: contextLimit)
        config.historyShape = target.profile.history
        config.temperature = target.profile.temperature
        config.endpointID = target.endpoint.id
        config.providers = target.profile.providers
        config.reasoning = target.reasoning
        config.sandbox = sandbox.policy(for: .fullAuto, SandboxPolicy())
        config.costScope = CostScope(run: UUID(), agent: agent.name, card: task.card)
        // A fixture that isn't there isn't the model's failure: it isn't called (BUG_HUNT_2026-11-02.md item 46).
        if let setupError {
            return SubagentTaskRun(prompt: prompt, record: RunRecord(), report: "", config: config, workspace: workspace, limits: limits,
                                   contextLimit: contextLimit, setupError: setupError)
        }
        // As a session's subagent gets them: an agent that lists its tools gets skills only if it lists "skill".
        if target.skills, agent.tools.map({ $0.contains("skill") }) ?? true {
            config.skills = Skills.load(root: dir, home: dir.appending(path: ".none"), builtin: Skills.builtinFolder)
        }
        let system = await SubagentSetup.defaultPrompt(workspace: workspace, agent: agent, tools: policy.offered(tools), mode: .fullAuto,
                                                       templates: PromptTemplates(overrides: target.promptDir.map { [$0] } ?? []),
                                                       skills: !config.skills.isEmpty,
                                                       globalInstructions: dir.appending(path: ".none"), userFiles: false)
        let recorder = Recorder()
        let start = Date()
        let client = makeClient(target)
        let request = SubagentSetup.taskText(prompt, card: task.card), runConfig = config
        let run = Task {
            await AgentLoop.run(client: client, model: target.model, systemPrompt: system, history: [.user(request)],
                                config: runConfig, workspace: workspace) { recorder.record($0, log: log) }
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(task.wallClock))
            if !Task.isCancelled { log("  wall-clock limit reached; stopping"); run.cancel() }
        }
        await run.value
        watchdog.cancel()
        // What the run started in the background (a server, a watcher) is stopped before gold runs, so it can't hold a
        // port or the fixture for the checks and the runs after it.
        runConfig.shell?.jobs.stopAll()
        var record = recorder.snapshot()
        record.duration = Date().timeIntervalSince(start)
        return SubagentTaskRun(prompt: prompt, record: record, report: record.finalText.trimmingCharacters(in: .whitespacesAndNewlines),
                               config: config, workspace: workspace, limits: limits, contextLimit: contextLimit)
    }

    /// The task's check run again in `dir`, as at the end of a parent's run, with the task's `checkTimeout`: nil
    /// without a check; else whether it ran, its exit status, and whether it was stopped at the time limit (then no
    /// status: a slow suite that didn't finish isn't a failure, BUG_HUNT_2026-11-02.md item 48).
    static func recheck(_ task: BankTask, config: AgentConfig, dir: URL) async -> (ran: Bool, exit: Int32?, timedOut: Bool)? {
        guard let command = task.card.verify else { return nil }
        var config = config
        config.shell = ShellState(cwd: dir)
        let c = await AgentLoop.runCheck(command, tools: Dictionary(AllTools.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a }),
                                         config: config, workspace: Workspace(root: dir), callID: "recheck", timeout: task.checkTimeout)
        guard let c, c.ran else { return (false, nil, false) }
        if c.output.exitCode == nil, c.output.text.contains("Timed out after") { return (true, nil, true) }
        return (true, AgentLoop.exitStatus(c.output), false)
    }

    /// One judge's verdict, by one path, on a run whose fixture is in `dir`: the parent's end-of-run rating (with the
    /// re-run check's result in its request) or the grader's.
    static func judge(prompt: String, report: String, checks: GroundedChecks, recheck: Int32??, task: BankTask, dir: URL,
                      judge: ModelTarget, path: String, limits: TurnLimits, sandbox: SandboxUse, makeClient: ClientFactory) async -> JudgeOutcome {
        let workspace = Workspace(root: dir)
        let agent = AgentDefinition.builtIns.first { $0.name == task.agent } ?? .general
        let judgeClient = makeClient(judge)
        final class Costs: @unchecked Sendable {
            let lock = NSLock()
            var entries: [CostEntry] = []
        }
        let costs = Costs()
        let sink = CostSink(scope: CostScope(run: nil, agent: "judge"), endpointID: judge.endpoint.id) { e in
            costs.lock.withLock { costs.entries.append(e) }
        }
        var limits = limits
        if judge.endpoint.kind.api != .openai {
            limits.maxTokens = max(limits.maxTokens, 16_384)
            limits.wallClock = max(limits.wallClock, 900)
        }
        let began = Date()
        let j: RunJudgment?
        if path == "parent" {
            var parentConfig = AgentConfig(tools: AllTools.all, limits: limits, policy: PermissionPolicy(mode: .fullAuto),
                                           approve: { _ in .allow }, shell: ShellState(cwd: dir))
            parentConfig.sandbox = sandbox.policy(for: .fullAuto, SandboxPolicy())
            parentConfig.historyShape = judge.profile.history
            parentConfig.temperature = judge.profile.temperature
            var builder = SystemPromptBuilder(workspace: workspace, tools: AllTools.all, mode: .fullAuto,
                                              globalInstructions: dir.appending(path: ".none"))
            builder.userFiles = false
            builder.style = judge.promptStyle ?? .automatic(for: judge.endpoint.kind.api)
            builder.templates = PromptTemplates(overrides: judge.promptDir.map { [$0] } ?? [])
            builder.subagents = true
            j = await JudgeCalibration.parentRating(
                client: judgeClient, model: judge.model, config: parentConfig, systemPrompt: await builder.build(),
                workspace: workspace, request: prompt, title: task.summary, agent: agent.name, card: task.card,
                parentView: JudgeCalibration.parentView(report: report, checks: checks, agent: agent.name),
                recheck: recheck, costs: sink)
        } else {
            let grader = SubagentModel(client: judgeClient, model: judge.model, historyShape: judge.profile.history,
                                       temperature: judge.profile.temperature, endpointID: judge.endpoint.id)
            j = await JudgeCalibration.grade(grader: grader, task: SubagentSetup.taskText(prompt, card: task.card),
                                             card: task.card, report: report, checks: checks, workspace: workspace,
                                             limits: limits, costs: sink)
        }
        let prices = costs.lock.withLock { costs.entries }.compactMap(\.listPrice?.total)
        return JudgeOutcome(judge: judge.label, path: path, verdict: j?.verdict, checked: j?.checked,
                            checkedConfirmed: j?.checkedConfirmed, issues: j?.issues ?? [], note: j?.note,
                            seconds: Date().timeIntervalSince(began), listPrice: prices.isEmpty ? nil : prices.reduce(0, +),
                            judgment: j)
    }

    /// Runs `task` on `target`, checks it, and records it in `store`; with `degrade`, also each degraded copy whose
    /// gold fails (EVAL_PLAN.md E2). Returns what it recorded.
    public static func recordBank(_ task: BankTask, on target: ModelTarget, trial: Int, store: RunStore, degrade: Bool = false,
                                  commit: String? = nil, config fingerprint: String? = nil,
                                  limits: TurnLimits = TurnLimits(maxTokens: 4096, wallClock: 300),
                                  sandbox: SandboxUse = .fullAuto, makeClient: ClientFactory = defaultClient,
                                  log: @escaping @Sendable (String) -> Void = { _ in }) async -> [StoredRun] {
        var dir = FileManager.default.temporaryDirectory.appending(path: "kk-bank-\(task.id)-\(UUID().uuidString.prefix(8))")
        var r = await performSubagentTask(task, on: target, dir: dir, limits: limits, sandbox: sandbox, makeClient: makeClient, log: log)
        // Failed before doing anything, for a reason outside the model: once more, after a pause (not for a fixture
        // that couldn't be made, which would fail the same way).
        if r.setupError == nil, infraReason(r.record) != nil {
            try? FileManager.default.removeItem(at: dir)
            try? await Task.sleep(for: .seconds(20))
            dir = FileManager.default.temporaryDirectory.appending(path: "kk-bank-\(task.id)-\(UUID().uuidString.prefix(8))")
            r = await performSubagentTask(task, on: target, dir: dir, limits: limits, sandbox: sandbox, makeClient: makeClient, log: log)
        }
        let finalDir = dir
        defer { try? FileManager.default.removeItem(at: finalDir) }
        let checks = GroundedChecks.evaluate(messages: r.record.messages, report: r.report, stop: r.record.stop,
                                             maxSteps: task.maxSteps, workspace: r.workspace, verify: task.card.verify)
        let gold = TaskBank.gold(task, dir: dir, report: r.report, record: r.record)
        let again = r.setupError == nil ? await recheck(task, config: r.config, dir: dir) : nil
        let usages = r.record.messages.compactMap { $0.meta?.usage }
        let priced = r.record.costs.compactMap(\.listPrice)
        let run = StoredRun(id: RunStore.id(task: task.id, model: target.label, trial: trial), task: task.id,
                            kind: task.card.kind?.rawValue ?? "", agent: task.agent, card: task.card, model: target.label,
                            trial: trial, prompt: r.prompt, report: r.report, checks: checks, rechecked: again?.ran ?? false,
                            recheckExit: again?.exit, gold: gold, stop: r.record.stop.map { "\($0)" } ?? "none",
                            seconds: r.record.duration, steps: r.record.assistantMessages.count, toolCalls: r.record.toolCalls.count,
                            promptTokens: usages.map(\.promptTokens).reduce(0, +),
                            completionTokens: usages.map(\.completionTokens).reduce(0, +),
                            listPrice: priced.isEmpty ? nil : priced.map(\.total).reduce(0, +),
                            unpricedRequests: r.record.costs.count - priced.count, infra: r.setupError ?? infraReason(r.record),
                            temperature: target.profile.temperature,
                            contextLimit: r.contextLimit, commit: commit, recordedAt: Date(), runRecord: r.record.runRecord,
                            transcript: r.record.messages, recheckTimedOut: again?.timedOut == true ? true : nil, config: fingerprint)
        var out: [StoredRun] = []
        do { try store.save(run, fixture: dir); out.append(run) } catch { log("  couldn't record \(run.id): \(error)") }
        guard degrade, gold.passed, run.infra == nil else { return out }
        return out + (await recordDegradations(of: run, task: task, dir: dir, record: r.record, config: r.config, store: store, log: log))
    }

    /// Why a run is an infrastructure failure, or nil: it stopped on a server error before any tool call (a model
    /// that won't load, no provider for the settings, a rate limit that outlasted the retries).
    public static func infraReason(_ record: RunRecord) -> String? {
        guard record.toolCalls.isEmpty, case .turnStopped(let stop)? = record.stop, stop == .failed,
              let error = record.assistantMessages.last?.meta?.error else { return nil }
        return String(error.prefix(200))
    }

    /// Records the degraded copies of a passing run whose project is in `dir` (left as it is): each kind that
    /// applies, kept only if gold then fails.
    static func recordDegradations(of run: StoredRun, task: BankTask, dir: URL, record: RunRecord, config: AgentConfig,
                                   store: RunStore, log: @escaping @Sendable (String) -> Void) async -> [StoredRun] {
        var out: [StoredRun] = []
        for kind in Degradation.allCases where Degradation.applies(kind, to: task) {
            let copy = FileManager.default.temporaryDirectory.appending(path: "kk-degrade-\(UUID().uuidString.prefix(8))")
            defer { try? FileManager.default.removeItem(at: copy) }
            guard shell("cp -R \(q(dir.path)) \(q(copy.path))").status == 0,
                  let bad = Degradation.apply(kind, report: run.report, dir: copy) else { continue }
            let badGold = TaskBank.gold(task, dir: copy, report: bad, record: record)
            guard !badGold.passed else { log("  \(kind.rawValue): gold still passes; not kept"); continue }
            var d = run
            d.id = RunStore.id(task: task.id, model: run.model, trial: run.trial, degradation: kind.rawValue)
            d.report = bad
            d.gold = badGold
            d.degradation = kind.rawValue
            d.parent = run.id
            d.checks = GroundedChecks.evaluate(messages: record.messages, report: bad, stop: record.stop,
                                               maxSteps: task.maxSteps, workspace: Workspace(root: copy), verify: task.card.verify)
            let badAgain = await recheck(task, config: config, dir: copy)
            d.rechecked = badAgain?.ran ?? false
            d.recheckExit = badAgain?.exit
            d.recheckTimedOut = badAgain?.timedOut == true ? true : nil
            do { try store.save(d, fixture: copy); out.append(d); log("  \(kind.rawValue): recorded (gold fails)") }
            catch { log("  couldn't record \(d.id): \(error)") }
        }
        return out
    }

    /// Scores every stored run again with the current gold, from its saved project (after a gold check is fixed, no
    /// model is run again). With `degrade`, trial 1's runs that now pass and have no degraded copies get them.
    /// Returns the runs whose gold changed.
    public static func regold(_ store: RunStore, degrade: Bool, sandbox: SandboxUse = .fullAuto,
                              log: @escaping @Sendable (String) -> Void = { _ in }) async -> [(id: String, was: Bool, now: Bool)] {
        var changed: [(id: String, was: Bool, now: Bool)] = []
        let all = store.runs()
        let parents = Set(all.compactMap(\.parent))
        for var run in all {
            guard let task = TaskBank.every.first(where: { $0.id == run.task }) else { continue }
            let dir: URL
            do { dir = try store.restore(run) } catch { log("  \(run.id): not restored, skipped (\(error.localizedDescription.prefix(120)))"); continue }
            defer { try? FileManager.default.removeItem(at: dir) }
            if let command = task.rebuild {
                let r = shell("cd \(q(dir.path)) && git clean -qfdX && \(command) 2>&1")
                // A tree that doesn't build fails its suite: gold records that.
                if r.status != 0 { log("  \(run.id): the rebuild failed; gold runs on what there is") }
            }
            var record = RunRecord()
            record.messages = run.transcript
            let gold = TaskBank.gold(task, dir: dir, report: run.report, record: record)
            if gold.passed != run.gold.passed || gold.notes != run.gold.notes {
                if gold.passed != run.gold.passed { changed.append((run.id, run.gold.passed, gold.passed)) }
                run.gold = gold
                try? store.update(run)
            }
            if degrade, run.degradation == nil, run.trial == 1, gold.passed, !parents.contains(run.id) {
                var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto), approve: { _ in .allow },
                                         shell: ShellState(cwd: dir))
                config.sandbox = sandbox.policy(for: .fullAuto, SandboxPolicy())
                let copies = await recordDegradations(of: run, task: task, dir: dir, record: record, config: config, store: store, log: log)
                log("  \(run.id): \(copies.count) degraded copies added")
            }
        }
        return changed
    }

    /// A fixed, balanced subset of `runs` of about `n`: every real failure, then degraded copies and passing runs half
    /// and half, each in an order set by a hash of its id, so every judge given the same `n` gets the same runs.
    public static func sample(_ runs: [StoredRun], _ n: Int) -> [StoredRun] {
        func key(_ r: StoredRun) -> String { SHA256.hash(data: Data(r.id.utf8)).map { String(format: "%02x", $0) }.joined() }
        let realFails = runs.filter { $0.degradation == nil && !$0.gold.passed }
        let copies = runs.filter { $0.degradation != nil }.sorted { key($0) < key($1) }
        let passes = runs.filter { $0.degradation == nil && $0.gold.passed }.sorted { key($0) < key($1) }
        let room = max(0, n - realFails.count)
        let fromCopies = min(copies.count, room / 2)
        let fromPasses = min(passes.count, room - fromCopies)
        return realFails + copies.prefix(fromCopies) + passes.prefix(fromPasses)
    }

    /// Judges a stored run with one judge by one path, from its restored fixture, and records the verdict.
    public static func judgeStored(_ run: StoredRun, store: RunStore, judge: ModelTarget, path: String,
                                   limits: TurnLimits = TurnLimits(maxTokens: 4096, wallClock: 300), sandbox: SandboxUse = .fullAuto,
                                   makeClient: ClientFactory = defaultClient) async -> JudgeOutcome? {
        guard let task = TaskBank.every.first(where: { $0.id == run.task }), let dir = try? store.restore(run) else { return nil }
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await Runner.judge(prompt: run.prompt, report: run.report, checks: run.checks,
                                         recheck: task.card.verify == nil ? nil : .some(run.rechecked ? run.recheckExit : nil),
                                         task: task, dir: dir, judge: judge, path: path, limits: limits, sandbox: sandbox,
                                         makeClient: makeClient)
        try? store.append(StoredJudgment(run: run.id, outcome: outcome, at: Date()))
        return outcome
    }
}
