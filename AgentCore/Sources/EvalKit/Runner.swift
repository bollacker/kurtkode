import AgentCore
import Foundation

/// A model to evaluate: where it is served and what to call it.
public struct ModelTarget: Sendable, Hashable {
    public var endpoint: Endpoint
    public var model: String
    public var apiKey: String?
    /// Subagents on (the task tool, on the same model, recorded in a throwaway store), for delegation scenarios.
    public var subagents = false
    /// OpenRouter's `reasoning` object for every turn (`{"enabled": false}`: the "reasoning off" configuration).
    public var reasoning: JSONValue?
    /// The model subagents run on, when it isn't this one (cost-floor stage 4: a strong parent, cheap subagents).
    public var subagentTarget: SubagentTargetBox?
    /// The parent is told to delegate the broad parts (cost-floor stage 4).
    public var forceDelegation = false
    /// A7: kurtkode itself makes the next step a `task` call at the delegation threshold (forced where the server can be,
    /// else written by kurtkode). Off by default, so earlier measurements stay comparable.
    public var kurtkodeDelegation = false
    /// Improvement 7's absolute trigger for the note, in tokens of reads in a row (`AgentConfig.delegationTokens`); nil:
    /// the default.
    public var delegationTokens: Int?
    /// Subagents on the model pool, as sessions with a hosted main model run them (GAP_ANALYSIS.md A2): the pool's entry
    /// for each task card's tier, and the retry ladder after a hard failure.
    public var subagentPool: SubagentPoolBox?
    /// The model's context length, when known (LM Studio reports it).
    public var contextLength: Int?
    /// History shaping and sampling. `ModelProfile.defaults` unless the run says otherwise.
    public var profile: ModelProfile
    /// The model that takes a turn whose tool call the server lost (`--fallback`).
    public var fallback: Fallback?
    /// The system prompt's style (`--prompt-style`); nil: automatic for the endpoint.
    public var promptStyle: PromptStyle?
    /// A folder of prompt templates that override the defaults (`--prompt-dir`); nil: the defaults alone.
    public var promptDir: URL?
    /// Bank runs give agents that may load skills (general) kurtkode's built-in skills, as sessions do (`--skills builtin`).
    public var skills = false

    public struct Fallback: Sendable, Hashable {
        public var endpoint: Endpoint
        public var model: String
        public var apiKey: String?
        public init(endpoint: Endpoint, model: String, apiKey: String? = nil) {
            self.endpoint = endpoint
            self.model = model
            self.apiKey = apiKey
        }
    }

    public init(endpoint: Endpoint, model: String, apiKey: String? = nil, contextLength: Int? = nil, profile: ModelProfile? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.contextLength = contextLength
        self.profile = profile ?? ModelProfile.defaults(endpointID: endpoint.id, model: model)
    }

    public var label: String {
        let ep = endpoint.id == Endpoint.localLMStudio.id ? "lmstudio" : endpoint.name.lowercased().replacingOccurrences(of: " ", with: "-")
        return "\(ep):\(model)" + (reasoning == nil ? "" : "#off") + (subagents ? " +subagents" : "")
            + (subagentTarget.map { " >" + $0.target.label } ?? "") + (subagentPool == nil ? "" : " >pool")
            + (forceDelegation ? " forced" : "") + (kurtkodeDelegation ? " kk-delegates" : "")
            + (delegationTokens.map { " note@\($0)" } ?? "")
    }
}

/// One scenario run on one model.
public struct TrialResult: Codable, Sendable {
    public var scenario: String
    public var model: String
    public var trial: Int
    public var check: CheckResult
    public var stop: String
    public var seconds: Double
    public var steps: Int
    public var toolCalls: Int
    public var toolErrors: Int
    public var compactions: Int
    /// Each compaction: sizes, how long its summary took, and the summary (to compare runs).
    public var summaries: [SummaryRecord]?
    /// Compactions the loop declined, or whose summary didn't come back (its "Didn't compact" notes).
    public var compactionsSkipped: Int?
    public var peakPromptTokens: Int
    public var approvalsAsked: Int
    public var minFreeMemoryPercent: Int
    /// Token totals over the agent's turns (compaction summaries not included).
    public var promptTokens: Int?
    public var completionTokens: Int?
    /// USD, summed over turns whose server reported a cost; nil when none did.
    public var reportedCost: Double?
    /// List price of every billed request (summaries and subagents included), the number of requests without a price,
    /// and the entries themselves (`CostEntry`; subagents' are in their run records).
    public var listPrice: Double?
    /// The part of `listPrice` that subagents spent.
    public var subagentListPrice: Double?
    public var unpricedRequests: Int?
    public var costEntries: [CostEntry]?
    public var runRecord: AgentRunRecord?
    /// Replies the server lost (empty, with output tokens), and how many replies each provider served.
    public var lostReplies: Int?
    public var providers: [String: Int]?
    public var finalExcerpt: String
    /// Subagent runs started and their judgments (with subagents on).
    public var subagentRuns: Int?
    public var judgments: [RunJudgment]?
    /// The whole conversation; written out only with --transcripts.
    public var transcript: [ChatMessage]?
}

public struct SummaryRecord: Codable, Sendable {
    public var tokensBefore: Int
    public var tokensAfter: Int
    public var seconds: Double?
    public var summary: String
}

public enum Runner {
    public typealias ClientFactory = @Sendable (ModelTarget) -> ChatClient
    /// Added to a scenario's request when the parent must delegate (cost-floor stage 4): no model delegated on its own.
    public static let delegationOrder = "\n\nWork through subagents: hand the broad reading and each independent part to the "
        + "task tool (the explore agent for reading, several at once when they're independent), then answer from their "
        + "reports. Check what matters before you rely on it."

    public static let defaultClient: ClientFactory = { ChatClient(endpoint: $0.endpoint, apiKey: $0.apiKey) }

    /// Runs one trial in a fresh temporary project, and checks the result.
    public static func run(_ scenario: Scenario, on target: ModelTarget, trial: Int, limits: TurnLimits = TurnLimits(maxTokens: 4096, wallClock: 300),
                           sandbox: SandboxUse = .fullAuto, makeClient: ClientFactory = defaultClient,
                           log: @escaping @Sendable (String) -> Void = { _ in }) async -> TrialResult {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "kk-eval-\(scenario.id)-\(UUID().uuidString.prefix(8))")
        let request: String
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            request = try scenario.prepare(dir) + (target.forceDelegation ? Runner.delegationOrder : "")
        } catch {
            return failed(scenario, target, trial, "fixture setup failed: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = Recorder()
        let start = Date()
        await phase(scenario, target, dir: dir, history: [.user(request)], maxSteps: scenario.maxSteps,
                    limits: limits, sandbox: sandbox, recorder: recorder, makeClient: makeClient, log: log)
        return result(scenario, label: target.label, trial: trial, dir: dir, recorder: recorder, start: start)
    }

    /// Starts on `first`, which stops after `switchAfter` steps; then `second` continues the same
    /// conversation (with its own history shaping and context budget). `between` runs in the gap, e.g.
    /// to swap which local model is loaded.
    public static func runSwitch(_ scenario: Scenario, first: ModelTarget, second: ModelTarget, switchAfter: Int, trial: Int,
                                 limits: TurnLimits = TurnLimits(maxTokens: 4096, wallClock: 300), sandbox: SandboxUse = .fullAuto,
                                 between: @Sendable (ModelTarget) async -> ModelTarget? = { $0 },
                                 makeClient: ClientFactory = defaultClient,
                                 log: @escaping @Sendable (String) -> Void = { _ in }) async -> TrialResult {
        let label = "\(first.label) → \(second.label)"
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "kk-eval-\(scenario.id)-switch-\(UUID().uuidString.prefix(8))")
        let request: String
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            request = try scenario.prepare(dir)
        } catch {
            return failed(scenario, first, trial, "fixture setup failed: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = Recorder()
        let start = Date()
        log("  phase 1: \(first.label), \(switchAfter) steps")
        await phase(scenario, first, dir: dir, history: [.user(request)], maxSteps: switchAfter, limits: limits,
                    sandbox: sandbox, recorder: recorder, makeClient: makeClient, log: log)
        guard let second = await between(second) else {
            var r = result(scenario, label: label, trial: trial, dir: dir, recorder: recorder, start: start)
            r.check = CheckResult(passed: false, score: 0, notes: ["couldn't prepare \(second.label)"])
            return r
        }
        log("  phase 2: \(second.label)")
        let history = [.user(request)] + recorder.snapshot().messages
        await phase(scenario, second, dir: dir, history: history, maxSteps: scenario.maxSteps, limits: limits,
                    sandbox: sandbox, recorder: recorder, makeClient: makeClient, log: log)
        return result(scenario, label: label, trial: trial, dir: dir, recorder: recorder, start: start)
    }

    static func phase(_ scenario: Scenario, _ target: ModelTarget, dir: URL, history: [ChatMessage], maxSteps: Int,
                      limits: TurnLimits, sandbox: SandboxUse, recorder: Recorder, makeClient: ClientFactory,
                      log: @escaping @Sendable (String) -> Void) async {
        let workspace = Workspace(root: dir)
        let policy = PermissionPolicy(mode: scenario.mode)
        let tools = policy.offered(AllTools.all)
        let limit = min(target.profile.contextLength ?? target.contextLength ?? 32_768, scenario.contextCap ?? .max)
        let approve: @Sendable (ApprovalRequest) async -> ApprovalDecision = { request in
            let n = recorder.countApproval()
            return scenario.approve(request, n)
        }
        var limits = limits
        // Claude's and Gemini's thinking counts against the output limit, and their turns can run longer.
        if target.endpoint.kind.api != .openai {
            limits.maxTokens = max(limits.maxTokens, 16_384)
            limits.wallClock = max(limits.wallClock, 900)
        }
        if let cap = target.profile.maxOutputTokens { limits.maxTokens = cap }
        var config = AgentConfig(tools: AllTools.all, maxSteps: maxSteps, limits: limits, policy: policy,
                                 approve: approve, shell: ShellState(cwd: workspace.root),
                                 context: ContextBudget(limit: limit, outputReserve: limits.maxTokens))
        config.maxToolOutputBytes = AgentConfig.toolOutputBytes(contextLimit: limit)
        config.historyShape = target.profile.history
        config.temperature = target.profile.temperature
        if target.profile.offersPatchTool { config.tools.append(ApplyPatchTool()) }
        // Summaries let the model think, as in the app by default; KURTKODE_SUMMARY_THINKING=0 asks for none.
        config.summaryThinking = ProcessInfo.processInfo.environment["KURTKODE_SUMMARY_THINKING"] != "0"
        config.endpointID = target.endpoint.id
        config.sandbox = sandbox.policy(for: scenario.mode, SandboxPolicy())
        config.providers = target.profile.providers
        config.reasoning = target.reasoning
        config.reasoningEffort = target.profile.reasoning           // a profile's setting, as the app and CLI send it
        if let f = target.fallback {
            let p = ModelProfile.defaults(endpointID: f.endpoint.id, model: f.model)
            config.fallback = FallbackModel(client: makeClient(ModelTarget(endpoint: f.endpoint, model: f.model, apiKey: f.apiKey)),
                                            model: f.model, historyShape: p.history, temperature: p.temperature,
                                            endpointID: f.endpoint.id)
        }
        // No personal ~/.kurtkode/AGENTS.md: runs must be comparable across machines.
        var builder = SystemPromptBuilder(workspace: workspace, tools: tools, mode: scenario.mode,
                                          globalInstructions: dir.appending(path: ".none"))
        builder.userFiles = false
        builder.sandbox = config.sandbox
        builder.style = target.promptStyle ?? .automatic(for: target.endpoint.kind.api)
        // No personal or project templates either: the defaults, or the run's own folder of them.
        builder.templates = PromptTemplates(overrides: target.promptDir.map { [$0] } ?? [])
        // Subagents run on the same model and are recorded outside the project, so the agent can't see them.
        var store: URL?
        if target.subagents {
            let root = FileManager.default.temporaryDirectory.appending(path: "kk-eval-runs-\(UUID().uuidString.prefix(8))")
            let sessions = SessionStore(root: root)
            let parent = SessionHeader(endpointID: target.endpoint.id, model: target.model, workspace: dir.path)
            try? await sessions.create(parent)
            config.subagents = SubagentSetup(recorder: SubagentRecorder(store: sessions, parent: parent))
            config.delegationForce = target.kurtkodeDelegation
            if let n = target.delegationTokens { config.delegationTokens = n }
            // Subagents on another model (a strong parent with cheap subagents), with that model's settings.
            if let sub = target.subagentTarget?.target {
                let client = makeClient(sub)
                let model = SubagentModel(client: client, model: sub.model, historyShape: sub.profile.history,
                                          contextLimit: sub.profile.contextLength ?? sub.contextLength ?? 32_768,
                                          temperature: sub.profile.temperature, endpointID: sub.endpoint.id,
                                          // As before the pool: a subagent inherits the parent's "reasoning off" and gets no
                                          // provider preferences, so earlier stores compare with new runs.
                                          reasoning: sub.reasoning != nil || target.reasoning != nil ? "none" : sub.profile.reasoning)
                config.subagents?.resolveModel = { _, _ in model }
            }
            if let box = target.subagentPool {
                let main = target.endpoint, mainModel = target.model
                // Each entry's model made once here (the factory can't outlive this call).
                var models: [String: SubagentModel] = [:]
                for e in box.pool.entries { if let r = ModelPool.resolve(e, endpoints: box.endpoints) { models[e.id] = box.model(r, makeClient) } }
                let ready = models
                config.subagents?.resolveModel = { _, card in
                    SubagentRouting.automatic(card: card, main: main, mainModel: mainModel, pool: box.pool, endpoints: box.endpoints)
                        .flatMap { ready[$0.entry.id] }
                }
                config.subagents?.retryModel = { _, endpointID, model, reasoning in
                    SubagentRouting.retry(after: endpointID, model: model, reasoning: reasoning, routed: true, main: main, pool: box.pool,
                                          endpoints: box.endpoints).flatMap { ready[$0.entry.id] }
                }
            }
            builder.subagents = true
            store = root
        }
        defer { if let store { try? FileManager.default.removeItem(at: store) } }
        var system = await builder.build()
        if !target.profile.promptAddendum.isEmpty { system += "\n\n" + target.profile.promptAddendum }
        let client = makeClient(target)
        let sampler = Task {
            while !Task.isCancelled {
                recorder.sampleMemory(MemoryStatus.current().freePercent)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        let agent = Task {
            await AgentLoop.run(client: client, model: target.model, systemPrompt: system, history: history,
                                config: config, workspace: workspace) { event in recorder.record(event, log: log) }
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(scenario.wallClock))
            if !Task.isCancelled { log("wall-clock limit reached; stopping"); agent.cancel() }
        }
        await agent.value
        watchdog.cancel()
        sampler.cancel()
        // Background commands the run started are stopped before the scenario is checked (as for bank runs).
        config.shell?.jobs.stopAll()
    }

    static func result(_ scenario: Scenario, label: String, trial: Int, dir: URL, recorder: Recorder, start: Date) -> TrialResult {
        var run = recorder.snapshot()
        run.duration = Date().timeIntervalSince(start)
        let minFree = recorder.minFree
        let check = scenario.check(dir, run)
        let usages = run.messages.compactMap { $0.meta?.usage }
        let costs = usages.compactMap(\.cost)
        let served = run.messages.compactMap { $0.meta?.provider }
        var result = TrialResult(scenario: scenario.id, model: label, trial: trial, check: check,
                           stop: run.stop.map { "\($0)" } ?? "none", seconds: run.duration,
                           steps: run.assistantMessages.count, toolCalls: run.toolCalls.count, toolErrors: run.toolErrors,
                           compactions: run.compactions.count, peakPromptTokens: run.peakPromptTokens,
                           approvalsAsked: run.approvalsAsked, minFreeMemoryPercent: minFree,
                           promptTokens: usages.map(\.promptTokens).reduce(0, +),
                           completionTokens: usages.map(\.completionTokens).reduce(0, +),
                           reportedCost: costs.isEmpty ? nil : costs.reduce(0, +),
                           finalExcerpt: String(run.finalText.prefix(400)), transcript: run.messages)
        result.lostReplies = run.messages.filter(AgentLoop.droppedCall).count
        let priced = run.costs.compactMap(\.listPrice)
        // Subagents' requests are in their child sessions; their list price comes with the run record.
        let children = (run.runRecord?.children ?? []).compactMap(\.listPrice)
        result.listPrice = priced.isEmpty && children.isEmpty ? nil : priced.map(\.total).reduce(0, +) + children.reduce(0, +)
        result.subagentListPrice = children.isEmpty ? nil : children.reduce(0, +)
        result.unpricedRequests = run.costs.count - priced.count
        result.costEntries = run.costs.isEmpty ? nil : run.costs
        result.runRecord = run.runRecord
        result.summaries = run.compactions.enumerated().map { i, c in
            SummaryRecord(tokensBefore: c.tokensBefore, tokensAfter: c.tokensAfter,
                          seconds: i < run.summarySeconds.count ? run.summarySeconds[i] : nil, summary: c.summary)
        }
        result.compactionsSkipped = run.messages.flatMap { $0.meta?.notes ?? [] }.filter { $0.hasPrefix("Didn't compact") }.count
        result.providers = served.isEmpty ? nil : Dictionary(served.map { ($0, 1) }, uniquingKeysWith: +)
        result.subagentRuns = run.subagentRuns
        result.judgments = run.judgments.isEmpty ? nil : run.judgments
        return result
    }

    static func failed(_ s: Scenario, _ t: ModelTarget, _ trial: Int, _ why: String) -> TrialResult {
        TrialResult(scenario: s.id, model: t.label, trial: trial, check: CheckResult(passed: false, score: 0, notes: [why]),
                    stop: "setup", seconds: 0, steps: 0, toolCalls: 0, toolErrors: 0, compactions: 0, peakPromptTokens: 0,
                    approvalsAsked: 0, minFreeMemoryPercent: MemoryStatus.current().freePercent, finalExcerpt: "")
    }
}

/// Collects agent events from any thread.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var run = RunRecord()
    private(set) var minFree = 100
    private var compactingSince: Date?

    func record(_ event: AgentEvent, log: @Sendable (String) -> Void) {
        lock.withLock {
            switch event {
            case .assistant(let m):
                run.messages.append(m)
                for c in m.toolCalls { log("  → \(c.name) \(c.arguments.prefix(90))") }
                if m.toolCalls.isEmpty, let stop = m.meta?.stopReason, stop != .completed { log("  turn stopped: \(stop)") }
            case .toolFinished(let m): run.messages.append(m)
            // Messages the loop adds to the conversation (subfolder rules, queued input, background reports).
            case .injected(let m): run.messages.append(m)
            case .promptSize(let t): run.peakPromptTokens = max(run.peakPromptTokens, t)
            case .cost(let e):
                if let i = run.costs.firstIndex(where: { $0.id == e.id }) { run.costs[i] = e } else { run.costs.append(e) }
            case .runEnded(let r): run.runRecord = r
            case .subagentStarted(let i):
                run.subagentRuns += 1
                log("  ⤷ \(i.agent) subagent: \(i.title)")
            case .judged(let j):
                run.judgments.append(j)
                if j.judge != .checks { log("  ✎ \(j.summary)") }
            case .compacting: compactingSince = Date()
            case .compacted(let c):
                run.compactions.append(c)
                let seconds = compactingSince.map { Date().timeIntervalSince($0) }
                run.summarySeconds.append(seconds ?? 0)
                compactingSince = nil
                log("  ⊜ compacted \(c.tokensBefore) → \(c.tokensAfter) tokens"
                    + (seconds.map { String(format: " (summary %.0f s, %d bytes)", $0, c.summary.utf8.count) } ?? ""))
            case .finished(let s): run.stop = s
            case .retrying(let why): log("  retrying: \(why)")
            default: break
            }
        }
    }

    func countApproval() -> Int { lock.withLock { defer { run.approvalsAsked += 1 }; return run.approvalsAsked } }
    func sampleMemory(_ free: Int) { lock.withLock { minFree = min(minFree, free) } }
    func snapshot() -> RunRecord { lock.withLock { run } }
}

/// A model target held by reference, so a target can name another (its subagents' model) without a recursive struct.
public final class SubagentTargetBox: @unchecked Sendable, Hashable {
    public let target: ModelTarget
    public init(_ target: ModelTarget) { self.target = target }
    public static func == (a: SubagentTargetBox, b: SubagentTargetBox) -> Bool { a.target == b.target }
    public func hash(into h: inout Hasher) { h.combine(target) }
}

/// A model pool for an eval's subagents, with the endpoints it resolves against and their keys.
public final class SubagentPoolBox: @unchecked Sendable, Hashable {
    public let pool: ModelPool
    public let endpoints: [Endpoint]
    let key: @Sendable (Endpoint) -> String?

    public init(pool: ModelPool, endpoints: [Endpoint], key: @escaping @Sendable (Endpoint) -> String?) {
        self.pool = pool
        self.endpoints = endpoints
        self.key = key
    }

    /// An entry as the subagent model the eval runs: 32k context, the entry's reasoning and provider pins.
    func model(_ r: ResolvedPoolEntry, _ makeClient: Runner.ClientFactory) -> SubagentModel {
        var t = ModelTarget(endpoint: r.endpoint, model: r.model, apiKey: key(r.endpoint))
        t.profile.providers = r.entry.providers
        return SubagentModel(client: makeClient(t), model: r.model, historyShape: t.profile.history, contextLimit: 32_768,
                             temperature: t.profile.temperature, endpointID: r.endpoint.id, reasoning: r.entry.reasoning,
                             providers: r.entry.providers)
    }

    public static func == (a: SubagentPoolBox, b: SubagentPoolBox) -> Bool { a.pool == b.pool }
    public func hash(into h: inout Hasher) { h.combine(pool) }
}
