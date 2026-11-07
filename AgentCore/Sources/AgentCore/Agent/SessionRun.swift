import Foundation

/// The user's run preferences. The app reads them from its own defaults (Settings binds to the same keys), the
/// command line from the app's defaults domain; unset keys take the app's defaults.
/// How long Anthropic keeps a session's prompt cache.
public enum PromptCacheTTL: String, Codable, Sendable, CaseIterable {
    /// An hour for the requests of a run someone is watching (the app, the CLI's live screen), where pauses happen;
    /// five minutes for subagents, `-p`, piped input and the eval, whose requests follow each other within seconds.
    /// Claude Code's policy.
    case auto
    case fiveMinutes = "5m"
    case hour = "1h"
}

public struct RunSettings: Sendable {
    public enum Key {
        public static let maxTokens = "maxTokens"
        public static let wallClockSeconds = "wallClockSeconds"
        public static let detectRepetition = "detectRepetition"
        public static let maxSteps = "maxSteps"
        public static let defaultContextLength = "defaultContextLength"
        public static let systemPrompt = "systemPrompt"
        public static let summarizerModel = "summarizerModel"
        public static let summaryThinking = "summaryThinking"
        public static let promptCacheHour = "promptCacheHour"      // before the TTL setting: true meant an hour for all
        public static let promptCacheTTL = "promptCacheTTL"
        public static let runCostLimit = "runCostLimit"
        public static let withheldFromRemote = "withheldFromRemote"
        public static let webSearch = "webSearch"
        public static let guardDangerous = "guardDangerous"
        public static let notify = "notify"
        public static let promptStyle = "promptStyle"
        public static let nativeMaxTokens = "nativeMaxTokens"
        public static let nativeWallClockSeconds = "nativeWallClockSeconds"
        public static let sessionCostLimit = "sessionCostLimit"
        public static let dailyCostLimit = "dailyCostLimit"
        public static let projectCostLimit = "projectCostLimit"
        public static let subagentModel = "subagentModel"
        public static let graderModel = "graderModel"
        public static let delegationAdvice = "delegationAdvice"
        public static let delegationForce = "delegationForce"
        public static let builtinSkills = "builtinSkills"
        public static let skillRouting = "skillRouting"
        public static let subagentParallel = "subagentParallel"
        public static let fallbackModel = "fallbackModel"
        public static let recordWire = "recordWire"
        public static let sandboxUse = "sandboxUse"
        public static let sandboxNetwork = "sandboxNetwork"
        public static let sandboxWritable = "sandboxWritable"
        public static let snapshots = "snapshots"
        public static let escalationOffers = "escalationOffers"
        public static let escalationReview = "escalationReview"
        public static let subagentRetry = "subagentRetry"
        public static let hourlyRate = "hourlyRate"
    }

    public var maxTokens = 8192
    public var wallClock: Double = 600
    public var detectRepetition = true
    public var maxSteps = 100
    public var defaultContextLength = 32768
    /// Extra text from Settings for the end of the system prompt.
    public var systemPrompt = ""
    /// The model that writes compaction summaries; nil: the session's own model.
    public var summarizerModel: ModelRef?
    /// Let the model think before writing a summary (its default). Off asks for no reasoning, which on LM Studio
    /// also loses the prompt cache when tools are offered (PLAN.md "Summaries without thinking").
    public var summaryThinking = true
    /// How long Anthropic keeps the prompt cache (`cacheHour(interactive:)`). An hour costs more to write (2× the input
    /// price, against 1.25×) and pays off over pauses of 5 to 60 minutes: waiting on the user or an approval. Claude
    /// Code's sessions on this Mac paid 25% less with it than five minutes would have (CACHING_REPORT.md section 1).
    public var promptCacheTTL = PromptCacheTTL.auto

    /// Whether a main run's requests, and its subagents', ask for an hour's cache. `interactive`: someone is watching
    /// the run and may pause (the app, the CLI's live screen), not `-p` or piped input.
    public func cacheHour(interactive: Bool) -> (main: Bool, subagents: Bool) {
        switch promptCacheTTL {
        case .auto: (interactive, false)
        case .fiveMinutes: (false, false)
        case .hour: (true, true)
        }
    }
    /// Limits for replies from Anthropic's and Google's APIs, whose thinking counts against the output limit and whose
    /// turns can run long (the general ones above suit local models).
    public var nativeMaxTokens = 32768
    public var nativeWallClock: Double = 1800
    /// The system prompt's style: nil for automatic (lean for Claude and Gemini), else the one chosen.
    public var promptStyle: PromptStyle?
    /// Ask before destructive commands (git reset --hard, force pushes, deleting outside the project…) in every mode.
    public var guardDangerous = true
    /// Tell the user when a run ends or waits for them (app: a notification in the background; CLI: the bell).
    public var notify = true
    /// Let Claude and Gemini search the web with their servers' own tools (billed per search); off by default.
    public var webSearch = false
    /// Patterns of files whose contents aren't sent to a third-party model (one per line in Settings); empty: none.
    public var withheldFromRemote = WithheldFiles.defaults
    /// Dollars a run may spend before it pauses (as at the step limit); 0: no limit.
    public var runCostLimit = 2.0
    /// Dollars a session may spend in all; 0: no limit.
    public var sessionCostLimit = 0.0
    /// Dollars all sessions may spend in a day, and one project's sessions; 0: no limit.
    public var dailyCostLimit = 0.0
    public var projectCostLimit = 0.0
    /// The model subagents use when their definition doesn't name one; nil: the main model, or the pool when
    /// `subagentAutomatic`.
    public var subagentModel: ModelRef?
    /// Subagents with no model chosen run on the model pool's (`SubagentRouting`): the setting unset or "auto". Saved
    /// as "" it means the session's own model.
    public var subagentAutomatic = true
    /// The model that judges subagent runs whose task is marked `importance: high`; nil: none, or the pool's judge
    /// when `graderAutomatic`.
    public var graderModel: ModelRef?
    public var graderAutomatic = true
    /// Suggest the explore subagent when the agent reads broadly itself (once a run).
    public var delegationAdvice = true
    /// A7: at the threshold the next step is a task call, not only a suggestion.
    public var delegationForce = true
    /// Offer kurtkode's built-in skills (debugging, tests, review, git, releases, …) besides the project's and the
    /// user's own, and tell the model about skills in the system prompt.
    public var builtinSkills = true
    /// Ask the model which skill fits each new request and tell the agent to load it (`SkillRouter`); auto: on
    /// OpenAI-compatible servers, where small and local models seldom load skills by themselves.
    public var skillRouting = SkillRouting.auto
    /// How many subagents may run at once on one endpoint other than this Mac's LM Studio (where the loaded
    /// model's parallel slots decide).
    public var subagentParallel = 4
    /// The model that takes over a turn whose tool call the server lost (after other providers, if any).
    public var fallbackModel: ModelRef?
    /// Keep each model request and its raw response with the session (the Debug window shows them).
    public var recordWire = true
    public var sandboxUse: SandboxUse = .fullAuto
    public var sandboxNetwork = false
    public var sandboxWritable: [String] = []
    /// Snapshots of the project's files around each main run (C1), so command-made changes show and rewind.
    public var snapshots = true
    /// A4: offer to hand a request to the next tier's model when a cheaper model's run looks wrong (a card; never automatic).
    public var escalationOffers = true
    /// A4: have A6's reviewer look at the changes of runs on models below the frontier first (one cheap request each), so
    /// wrong changes get the offer too. Hosted sessions only, as for automatic reviews.
    public var escalationReview = false
    /// D3: a subagent run on the pool that fails outright is tried once more on the next retry rung. Off by default
    /// since the cost audit (decision 7): on the eval data it added one pass in 479 runs for 1% more cost, and three of
    /// its four firings were on runs that had passed (`--retry-sim cf6`).
    public var subagentRetry = false
    /// What an hour of the user's waiting is worth, in dollars, for the "time cost" the spending reports show beside
    /// what models charged (the cost audit's θ, decision 6): a local model that takes 50 s where a hosted one takes
    /// 17 s costs nothing to run but not nothing to wait for. Display only; 0 hides it.
    public var hourlyRate = 30.0

    public init() {}

    public init(defaults d: UserDefaults) {
        func has(_ key: String) -> Bool { d.object(forKey: key) != nil }
        if has(Key.maxTokens) { maxTokens = d.integer(forKey: Key.maxTokens) }
        if has(Key.wallClockSeconds) { wallClock = d.double(forKey: Key.wallClockSeconds) }
        if has(Key.detectRepetition) { detectRepetition = d.bool(forKey: Key.detectRepetition) }
        if has(Key.maxSteps) { maxSteps = d.integer(forKey: Key.maxSteps) }
        if has(Key.defaultContextLength) { defaultContextLength = d.integer(forKey: Key.defaultContextLength) }
        systemPrompt = d.string(forKey: Key.systemPrompt) ?? ""
        summarizerModel = d.string(forKey: Key.summarizerModel).flatMap(ModelRef.init(key:))
        if has(Key.summaryThinking) { summaryThinking = d.bool(forKey: Key.summaryThinking) }
        if let t = d.string(forKey: Key.promptCacheTTL).flatMap(PromptCacheTTL.init(rawValue:)) { promptCacheTTL = t }
        else if d.bool(forKey: Key.promptCacheHour) { promptCacheTTL = .hour }
        if has(Key.nativeMaxTokens) { nativeMaxTokens = d.integer(forKey: Key.nativeMaxTokens) }
        if has(Key.nativeWallClockSeconds) { nativeWallClock = d.double(forKey: Key.nativeWallClockSeconds) }
        webSearch = d.bool(forKey: Key.webSearch)
        if has(Key.guardDangerous) { guardDangerous = d.bool(forKey: Key.guardDangerous) }
        if has(Key.notify) { notify = d.bool(forKey: Key.notify) }
        promptStyle = d.string(forKey: Key.promptStyle).flatMap(PromptStyle.init(rawValue:))
        if let w = d.string(forKey: Key.withheldFromRemote) {
            withheldFromRemote = w.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if has(Key.runCostLimit) { runCostLimit = max(0, d.double(forKey: Key.runCostLimit)) }
        if has(Key.sessionCostLimit) { sessionCostLimit = max(0, d.double(forKey: Key.sessionCostLimit)) }
        if has(Key.dailyCostLimit) { dailyCostLimit = max(0, d.double(forKey: Key.dailyCostLimit)) }
        if has(Key.projectCostLimit) { projectCostLimit = max(0, d.double(forKey: Key.projectCostLimit)) }
        subagentModel = d.string(forKey: Key.subagentModel).flatMap(ModelRef.init(key:))
        subagentAutomatic = subagentModel == nil && [nil, "auto"].contains(d.string(forKey: Key.subagentModel))
        graderModel = d.string(forKey: Key.graderModel).flatMap(ModelRef.init(key:))
        graderAutomatic = graderModel == nil && [nil, "auto"].contains(d.string(forKey: Key.graderModel))
        if has(Key.delegationAdvice) { delegationAdvice = d.bool(forKey: Key.delegationAdvice) }
        if has(Key.delegationForce) { delegationForce = d.bool(forKey: Key.delegationForce) }
        if has(Key.builtinSkills) { builtinSkills = d.bool(forKey: Key.builtinSkills) }
        skillRouting = d.string(forKey: Key.skillRouting).flatMap(SkillRouting.init(rawValue:)) ?? .auto
        if has(Key.subagentParallel) { subagentParallel = max(1, d.integer(forKey: Key.subagentParallel)) }
        fallbackModel = d.string(forKey: Key.fallbackModel).flatMap(ModelRef.init(key:))
        if has(Key.recordWire) { recordWire = d.bool(forKey: Key.recordWire) }
        sandboxUse = d.string(forKey: Key.sandboxUse).flatMap(SandboxUse.init(rawValue:)) ?? .fullAuto
        sandboxNetwork = d.bool(forKey: Key.sandboxNetwork)
        sandboxWritable = (d.string(forKey: Key.sandboxWritable) ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if has(Key.snapshots) { snapshots = d.bool(forKey: Key.snapshots) }
        if has(Key.escalationOffers) { escalationOffers = d.bool(forKey: Key.escalationOffers) }
        escalationReview = d.bool(forKey: Key.escalationReview)
        subagentRetry = d.bool(forKey: Key.subagentRetry)
        if has(Key.hourlyRate) { hourlyRate = max(0, d.double(forKey: Key.hourlyRate)) }
    }

    /// The sandbox for a run in `mode` (nil: none), as Settings says or as `use` overrides it.
    public func sandbox(for mode: PermissionMode, use: SandboxUse? = nil) -> SandboxPolicy? {
        (use ?? sandboxUse).policy(for: mode, SandboxPolicy(allowNetwork: sandboxNetwork, extraWritable: sandboxWritable))
    }

    /// Per-turn limits, with the model's own output cap when its profile sets one; `api` picks the native APIs' defaults.
    public func limits(for profile: ModelProfile, api: WireAPI = .openai) -> TurnLimits {
        let native = api != .openai
        return TurnLimits(maxTokens: profile.maxOutputTokens ?? (native ? nativeMaxTokens : maxTokens),
                          wallClock: native ? nativeWallClock : wallClock, detectRepetition: detectRepetition)
    }

    /// The system prompt's style for a model on `api`.
    public func style(for api: WireAPI) -> PromptStyle { promptStyle ?? .automatic(for: api) }

    /// The native APIs' limits, for subagents that run on Claude or Gemini under a session that doesn't.
    public var nativeLimits: TurnLimits {
        TurnLimits(maxTokens: nativeMaxTokens, wallClock: nativeWallClock, detectRepetition: detectRepetition)
    }

    /// Limits for a summary the user asked for (/compact): a summary is short.
    public var compactionLimits: TurnLimits { TurnLimits(maxTokens: 1500, wallClock: wallClock) }

    /// The summarizer, unless it's the model the session already uses (which can reuse its prompt cache).
    public func summarizer(excluding endpointID: UUID, _ model: String) -> ModelRef? {
        summarizerModel.flatMap { $0.endpointID == endpointID && $0.model == model ? nil : $0 }
    }

    /// The fallback, unless it's the session's model (which just lost the reply).
    public func fallback(excluding endpointID: UUID, _ model: String) -> ModelRef? {
        fallbackModel.flatMap { $0.endpointID == endpointID && $0.model == model ? nil : $0 }
    }
}

/// A model on an endpoint. Its key ("endpointID|model") is how preferences and profiles name it.
public struct ModelRef: Hashable, Identifiable, Sendable {
    public var endpointID: UUID
    public var model: String
    public var id: String { key }
    public var key: String { ModelProfile.key(endpointID, model) }

    public init(endpointID: UUID, model: String) {
        self.endpointID = endpointID
        self.model = model
    }

    public init?(key: String) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
        self.init(endpointID: id, model: parts[1])
    }
}

/// The user message undo snapshots are filed under; moves forward when queued input goes in mid-run.
public final class TurnKey: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: UUID
    public init(_ id: UUID) { _id = id }
    public var id: UUID {
        get { lock.withLock { _id } }
        set { lock.withLock { _id = newValue } }
    }
}

/// A session's system prompt as recorded with it: the text, what it was built for (`key`), and the date and git status
/// it states (`facts`).
public struct RecordedPrompt: Sendable, Hashable {
    public var text: String
    public var key: String
    public var facts: String

    public init(text: String, key: String, facts: String) {
        self.text = text
        self.key = key
        self.facts = facts
    }
}

/// A session's system prompt, built once and reused while the mode, the sandbox, and the model's addendum stay
/// the same. It starts every prompt, and any change to it (the git status it lists changes after every edit)
/// makes the server re-process the whole conversation: 24k tokens took 122 s, cached 0.5 s; on a paid API the whole
/// session is billed again at full price.
///
/// It lasts beyond one process: given the session's recorded prompt, a later process (the CLI's `-c`, the app after a
/// restart) sends that one again when the only difference is the date and git status it states, and offers the new
/// ones as a note (`takeNote`) to send after the user's message. A prompt built new is offered for recording
/// (`takeRecord`).
public final class FrozenSystemPrompt: @unchecked Sendable {
    private let lock = NSLock()
    private var frozen: (key: String, text: String)?
    private var pendingRecord: RecordedPrompt?
    private var pendingNote: String?

    public init() {}

    /// The base prompt, without any compaction summary (`SessionRun.withSummary` adds one). `isChat`: the
    /// workspace is a chat's working folder. `recorded`: the session's latest recorded prompt.
    public func text(workspace: Workspace?, tools: [any Tool], mode: PermissionMode, sandbox: SandboxPolicy?,
                     userPrompt: String, addendum: String, isChat: Bool = false, style: PromptStyle = .detailed,
                     subagents: Bool = false, skills: Bool = false,
                     recorded: RecordedPrompt? = nil, now: Date = Date()) async -> String {
        // The folders are part of it: adding one changes what the agent may touch, so the prompt must say so.
        let folders = (workspace?.folders ?? []).map { $0.path + ($0.writable ? ":rw" : ":ro") }.joined(separator: ",")
        var builder = workspace.map { SystemPromptBuilder(workspace: $0, tools: tools, mode: mode, userPrompt: userPrompt) }
        builder?.sandbox = sandbox
        builder?.isChat = isChat
        builder?.style = style
        builder?.subagents = subagents
        builder?.skills = skills
        // Edited templates are part of it too (a hash of them; none when they're the defaults, so keys recorded
        // before templates existed still match). The default style adds nothing, for the same reason.
        let edited = builder.map { $0.templates.fingerprint($0.templateNames) } ?? ""
        let key = mode.rawValue + "|" + (sandbox?.promptText ?? "") + "|" + addendum + "|" + folders + (isChat ? "|chat" : "")
            + (style == .detailed ? "" : "|" + style.rawValue) + (subagents && builder != nil ? "|sub" : "")
            + (skills && builder != nil ? "|skills" : "")
            + (edited.isEmpty ? "" : "|t:" + edited)
        if let f = lock.withLock({ frozen }), f.key == key { return f.text }
        var text: String
        var facts = ""
        if let builder {
            (text, facts) = await builder.buildWithFacts(now: now)
        } else {
            text = userPrompt
        }
        // The addendum is the same on every run: before the changing section, so it stays in the cached prefix.
        text = SystemPromptBuilder.insertingStable(addendum, into: text)
        // The recorded prompt, if this one only states other facts (anything else changed: tools, instructions, the
        // user's prompt text, and the new one is used).
        if let r = recorded, r.key == key,
           (facts.isEmpty ? text : Self.replacingFirst(facts, with: r.facts, in: text)) == r.text {
            lock.withLock {
                frozen = (key, r.text)
                pendingRecord = nil
                pendingNote = facts == r.facts ? nil : Self.note(facts)
            }
            return r.text
        }
        lock.withLock {
            frozen = (key, text)
            pendingRecord = RecordedPrompt(text: text, key: key, facts: facts)
            pendingNote = nil
        }
        return text
    }

    /// A prompt built new since the last call, for the session to record (once).
    public func takeRecord() -> RecordedPrompt? {
        lock.withLock { defer { pendingRecord = nil }; return pendingRecord }
    }

    /// The date and git status as they are now, when the reused prompt states older ones (once).
    public func takeNote() -> String? {
        lock.withLock { defer { pendingNote = nil }; return pendingNote }
    }

    /// Forgets the prompt (a new session).
    public func reset() { lock.withLock { frozen = nil; pendingRecord = nil; pendingNote = nil } }

    static func note(_ facts: String) -> String {
        "[kurtkode: this session was resumed, and its system prompt shows the environment as it was then. Now:\n"
            + facts + "]"
    }

    static func replacingFirst(_ target: String, with replacement: String, in text: String) -> String {
        guard let r = text.range(of: target) else { return text }
        return text.replacingCharacters(in: r, with: replacement)
    }

    /// How the transcript names a note to the model (every note used to show as the resumed session's date and git
    /// status).
    public static func noteLabel(_ content: String) -> String {
        if content.hasPrefix("[kurtkode: this session was resumed") { return "Told the model today's date and the git status (the session was resumed)" }
        if content.hasPrefix("[kurtkode: the skill router loaded the \""), let name = content.split(separator: "\"").dropFirst().first {
            return "The skill router gave the model the \(name) skill"
        }
        if content.hasPrefix("[kurtkode: the user restored these files") { return "Told the model that files were restored (rewind)" }
        return "A note to the model from kurtkode"
    }

    /// A user message carrying `note` (marked, so it isn't shown as the user's words).
    public static func noteMessage(_ note: String) -> ChatMessage {
        var m = ChatMessage.user(note)
        m.contextNote = true
        return m
    }
}

/// One agent run in a session, configured the same way by the app and the command line: limits, permission
/// policy, undo snapshots, context budget, the model's profile, sandbox, hooks, and subagents. What differs
/// between the two (asking for approval, queued input, images, MCP tools, how a subagent's model is found)
/// comes in as arguments or is set on `config` afterwards.
public struct SessionRun: Sendable {
    public var config: AgentConfig
    /// The conversation to send: the messages after the latest compaction (its summary is in `config.summary`).
    public var history: [ChatMessage]

    /// - Parameters:
    ///   - tools: the built-in tools to offer; none for a plain chat or a model without tools.
    ///   - subagentModel: finds a subagent's model; nil turns subagents off.
    public init(session: Session, store: SessionStore, settings: RunSettings, profile: ModelProfile, endpointID: UUID,
                api: WireAPI = .openai, permissionRules: PermissionRules = PermissionRules(),
                mode: PermissionMode, rules: [AllowRule], tools: [any Tool], workspace: Workspace?, shell: ShellState,
                contextLimit: Int?, sandbox: SandboxPolicy?, turn: TurnKey, checkpoints: CheckpointStore,
                approve: @escaping @Sendable (ApprovalRequest) async -> ApprovalDecision, hooks: Hooks?,
                subagentModel: SubagentModelResolver?, maxSteps: Int? = nil,
                sandboxUse: SandboxUse? = nil, interactive: Bool = true) {
        let limits = settings.limits(for: profile, api: api)
        let (history, summary) = session.modelHistory
        let outputs = store.outputDirectory(for: session.header)
        var config = AgentConfig(
            tools: tools, maxSteps: max(1, maxSteps ?? settings.maxSteps), limits: limits,
            policy: PermissionPolicy(mode: mode, rules: rules),
            approve: approve,
            checkpoint: { urls in for u in urls { try await checkpoints.snapshot(u, turn: turn.id) } },
            shell: shell,
            context: contextLimit.map { ContextBudget(limit: $0, outputReserve: limits.maxTokens) },
            summary: summary, facts: session.facts, outputDirectory: outputs)
        config.historyShape = profile.history
        config.temperature = profile.temperature
        config.providers = profile.providers
        config.reasoningEffort = profile.reasoning
        if profile.offersPatchTool, tools.contains(where: { $0.name == "edit_file" }) { config.tools.append(ApplyPatchTool()) }
        config.maxToolOutputBytes = AgentConfig.toolOutputBytes(contextLimit: contextLimit)
        config.summaryThinking = settings.summaryThinking
        config.delegationAdvice = settings.delegationAdvice
        config.delegationForce = settings.delegationForce
        (config.promptCacheHour, config.subagentCacheHour) = settings.cacheHour(interactive: interactive)
        config.cacheKey = session.header.id.uuidString
        config.previousReply = session.lastReplyCost
        config.nativeLimits = settings.nativeLimits
        config.withheldFromRemote = settings.withheldFromRemote
        if workspace != nil { config.memoryHome = FileManager.default.homeDirectoryForCurrentUser }
        config.webSearch = settings.webSearch
        config.imagesDirectory = store.imagesDirectory(for: session.header)
        config.permissionRules = permissionRules
        config.guardDangerous = settings.guardDangerous
        // One look for OpenRouter's record of each reply at the run's end, without waiting: records lag by minutes, so
        // waiting up to 10 s (the eval's setting) mostly found nothing; the rest are settled in the background
        // (`CostReconciler`), and reports read the settled entries (the cost audit's improvement 9).
        config.generationLookupDelays = []
        config.costMeter = CostMeter(runLimit: settings.runCostLimit, sessionLimit: settings.sessionCostLimit,
                                     sessionBefore: CostMeter.counted(session))
        if settings.recordWire { config.wireLog = WireLog(directory: store.wireDirectory(for: session.header)) }
        config.endpointID = endpointID
        config.costScope = CostScope(run: UUID(), agent: "main", userMessage: turn.id, promptStyle: settings.style(for: api).rawValue)
        // Commands may write in the writable extra folders too (their .git hooks and config stay protected).
        let folders = workspace?.folders ?? []
        let withFolders: @Sendable (SandboxPolicy?) -> SandboxPolicy? = { policy in
            policy.map { s in
                var s = s
                s.extraWritable += folders.filter(\.writable).map(\.path)
                s.readOnly += folders.filter { !$0.writable }.map(\.path)
                return s
            }
        }
        config.sandbox = withFolders(sandbox)
        // An approved plan switches the mode mid-run: the sandbox Settings give that mode (Full Auto's, usually).
        let runSettings = settings
        config.sandboxFor = { mode in withFolders(runSettings.sandbox(for: mode, use: sandboxUse)) }
        config.hooks = hooks
        if let workspace, !tools.isEmpty { config.testSuite = TestSuite.command(root: workspace.root) }
        if settings.snapshots, let workspace, !tools.isEmpty, let snaps = store.snapshots(for: workspace.root) {
            config.snapshots = RunSnapshots(store: snaps, session: session.header.id, turn: turn.id)
        }
        if let workspace, !tools.isEmpty { config.skills = Skills.load(root: workspace.root, builtin: Skills.builtin(settings.builtinSkills)) }
        if let subagentModel, let workspace, !tools.isEmpty {
            config.subagents = SubagentSetup(agents: AgentDefinitions.load(workspace: workspace.root),
                                             resolveModel: subagentModel,
                                             recorder: SubagentRecorder(store: store, parent: session.header,
                                                                        recordWire: settings.recordWire))
            // Beside the session's own checkpoints, where commands can't write (the sandbox's write set is the project,
            // the temp and cache folders, and the writable extra folders).
            config.subagents?.attemptStore = store.checkpointDirectory(for: session.header).appending(path: "attempts")
        }
        self.config = config
        self.history = history
    }

    /// The skill router's note for this run's request, when `routing` applies to the server and the router picks a
    /// skill (`SkillRouter`); nil otherwise. Call it before adding other notes: it routes the user's latest message.
    /// The question's cost entry goes to `emit` and counts against the run's limit. The caller sends the note after
    /// the user's message and keeps it in the session.
    public func routeSkill(client: ChatClient, model: String, routing: SkillRouting, project: URL?,
                           emit: @escaping @Sendable (CostEntry) async -> Void) async -> ChatMessage? {
        guard routing.applies(to: client.api), !config.skills.isEmpty,
              history.last.map({ !$0.content.hasPrefix(Escalation.handOverPrefix) }) ?? true else { return nil }
        let scope = config.costScope ?? CostScope(run: UUID(), agent: "main")
        return await SkillRouter.route(history: history, skills: config.skills, client: client, model: model,
                                       templates: .standard(project: project), limits: config.limits,
                                       costs: CostSink(scope: scope, endpointID: config.endpointID, emit: emit),
                                       meter: config.costMeter)
    }

    /// With a daily or project limit, counts what was spent today (this Mac's day) by every session and by this
    /// project's (read from disk: a fraction of a second for a few hundred sessions). Call it after
    /// `countSubagentSpending`.
    /// Only for a session on a paid server (`main` third party): a local model costs nothing, and a limit reached on
    /// paid models mustn't stop it.
    public mutating func countDailySpending(settings: RunSettings, store: SessionStore, workspace: String?, main: Endpoint) async {
        guard main.isThirdParty, let m = config.costMeter, settings.dailyCostLimit > 0 || settings.projectCostLimit > 0 else { return }
        let (day, project) = await Spending.today(store, workspace: workspace)
        config.costMeter = m.with(dayLimit: settings.dailyCostLimit, dayBefore: day, projectLimit: workspace == nil ? nil : settings.projectCostLimit,
                                  projectBefore: project)
    }

    /// With a session limit, counts what the session's subagent runs spent too (their records are read from disk).
    public mutating func countSubagentSpending(session: Session, store: SessionStore) async {
        guard let m = config.costMeter, m.sessionLimit != nil else { return }
        config.costMeter = CostMeter(runLimit: m.runLimit, sessionLimit: m.sessionLimit,
                                     sessionBefore: CostMeter.counted(session, runs: await store.ownSubagentRuns(of: session.header)))
    }

    /// The tools the model is offered once MCP tools are added: what the system prompt lists.
    public var offeredTools: [any Tool] { config.policy.offered(config.tools) }

    /// A system prompt with the latest compaction summary, for a summary made outside the loop (/compact).
    public static func withSummary(_ system: String, _ summary: String?) -> String {
        guard let summary else { return system }
        return system + (system.isEmpty ? "" : "\n\n") + Compaction.systemSection(summary)
    }

    /// Whether `/compact` has anything to summarize: messages since the last summary other than the continuation
    /// line a summary leaves. Right after a summary there is nothing; asking the model anyway sends no request and
    /// used to be reported as "the model didn't return a usable summary".
    public static func hasNewMessagesToCompact(_ session: Session) -> Bool {
        session.modelHistory.messages.contains { !AgentLoop.isContinuation($0) }
    }

    public static let nothingToCompact = "Nothing new to summarize since the last summary."

    /// Summarizes the whole conversation now (/compact), on the session's model and its history shape.
    public static func compact(session: Session, client: ChatClient, model: String, hooks: Hooks? = nil, baseSystemPrompt: String,
                               tools: [any Tool], settings: RunSettings, profile: ModelProfile,
                               focus: String, contextLimit: Int? = nil, costs: CostSink? = nil,
                               wire: WireLog? = nil) async -> ManualCompaction {
        _ = await hooks?.preCompact(trigger: "manual", instructions: focus)
        let (history, summary) = session.modelHistory
        return await Compactor.compactAll(client: client, model: model, systemPrompt: withSummary(baseSystemPrompt, summary),
                                          baseSystemPrompt: baseSystemPrompt,
                                          history: history, tools: tools, limits: settings.compactionLimits,
                                          extraInstructions: focus, facts: session.facts, shape: profile.history,
                                          thinking: settings.summaryThinking, cacheForAnHour: settings.cacheHour(interactive: true).main,
                                          cacheKey: session.header.id.uuidString, contextLimit: contextLimit, costs: costs,
                                          wire: settings.recordWire ? wire : nil)
    }
}
