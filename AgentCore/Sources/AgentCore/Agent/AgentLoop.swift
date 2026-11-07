import Foundation

public struct AgentConfig: Sendable {
    public var tools: [any Tool]
    /// Model turns per run before pausing for "Continue". Spike: 10 caused every failure; a 25-file task
    /// needed more than 30. The real guards are the per-turn limits, repetition detection, and Stop.
    public var maxSteps: Int
    public var limits: TurnLimits
    public var maxToolOutputBytes: Int
    public var policy: PermissionPolicy
    /// Asks the user. Required for any call the policy doesn't allow outright; without it those are denied.
    public var approve: (@Sendable (ApprovalRequest) async -> ApprovalDecision)?
    /// Called with the files a write tool is about to change, before it runs (for undo).
    public var checkpoint: (@Sendable ([URL]) async throws -> Void)?
    public var shell: ShellState?
    /// When set, the loop compacts before the context fills, and after an overflow error.
    public var context: ContextBudget?
    /// A summary from an earlier compaction, appended to the system prompt (`Compaction.modelText`).
    public var summary: String?
    /// Progress tracked over the whole session so far, including before earlier compactions.
    public var facts: SessionFacts?
    /// Where tools save full output that was too long to send (bash).
    public var outputDirectory: URL?
    /// How to shape history for this model's template, and its sampling temperature (from its profile).
    public var historyShape = HistoryShape()
    public var temperature: Double?
    /// Recorded on each reply, for sessions that use several endpoints.
    public var endpointID: UUID?
    /// Another model to write compaction summaries (e.g. a fast local one for an expensive remote one).
    /// Nil: the agent's own model, which can reuse its prompt cache.
    public var summarizer: Summarizer?
    /// Let the model think before writing a summary (`RunSettings.summaryThinking`).
    public var summaryThinking = true
    /// With subagents on: after a long run of reads that fill the context, suggest the explore subagent (once a run).
    public var delegationAdvice = true
    /// A7: at the delegation threshold, the next step is a `task` call: the model's, forced, where the server can be made
    /// to (`ToolForcing`), else one kurtkode writes from the request. Off: the note only.
    public var delegationForce = true
    /// Improvement 7 (COST_AUDIT.md): a long run of reads also earns the note once it adds up to this many tokens, however
    /// big the context (a fifth of a hosted model's context is 40k–200k tokens, which a session rarely reads in a row).
    /// This trigger gives the note alone, never a forced task call: forcing made a strong parent 1.7–2× dearer. 0: off.
    public var delegationTokens = 30_000
    /// Keep Anthropic's prompt cache for an hour (`RunSettings.cacheHour`); summaries use the same.
    public var promptCacheHour = false
    /// The same for this run's subagents (five minutes unless the setting says an hour for all).
    public var subagentCacheHour = false
    /// Offer the same tools in every mode and refuse by mode when a call comes, so an approved plan doesn't change the
    /// cached prompt (CACHING_PLAN.md 1.2). Off for subagents: their prompt is their own, and in plan mode they're
    /// given only the tools that read.
    public var sameToolsInEveryMode = true
    /// The session's last reply request before this run (the main agent's), so the run's first request can tell what
    /// its cache lost over the pause between turns (`CacheLedger`).
    public var previousReply: CostEntry?
    /// Sent as the requests' `cacheKey` (OpenAI's `prompt_cache_key`, OpenRouter's `session_id`): the session's id, or
    /// a subagent kind's under it. Nil sends none.
    public var cacheKey: String?
    /// Limits for a subagent whose model is on Anthropic's or Google's API (`RunSettings.nativeLimits`); nil: `limits`.
    public var nativeLimits: TurnLimits?
    /// Allow, ask, and deny rules from settings files (`PermissionRules`).
    public var permissionRules = PermissionRules()
    /// Ask before destructive commands in every mode (`DangerousCommands`; `RunSettings.guardDangerous`).
    public var guardDangerous = true
    /// Offer Claude's and Gemini's own web search (`RunSettings.webSearch`).
    public var webSearch = false
    /// OpenRouter's `reasoning` object for each turn (the eval's "reasoning off" configurations); nil: not sent.
    public var reasoning: JSONValue?
    /// The model profile's reasoning setting ("none" or an effort level; `ReasoningSetting`), when `reasoning` isn't set.
    public var reasoningEffort: String?
    /// Files whose contents aren't sent to a third-party model (`RunSettings.withheldFromRemote`); empty: none.
    public var withheldFromRemote: [String] = []
    /// Counts what the run and its subagents spend, against the user's limits (shared with subagent runs).
    public var costMeter: CostMeter?
    /// The agent run these requests belong to, for their cost entries (`AgentEvent.cost`).
    public var costScope: CostScope?
    /// Waits between tries for a reply's OpenRouter generation record, at the end of the run (it can lag the reply).
    public var generationLookupDelays: [Double] = [1, 3, 6]
    /// Run commands in this sandbox (D9). The app sets it for Full Auto.
    public var sandbox: SandboxPolicy?
    /// Messages the user typed while the run was going (queued input). Taken before each model request, and
    /// before the run would finish, so they steer the task at the next step instead of waiting for the end.
    public var takeInput: (@Sendable () async -> [ChatMessage])?
    /// Where images a tool reads are kept with the session.
    public var imagesDirectory: URL?
    /// Whether this model takes images; when not, attached images go as a note.
    public var sendImages = true
    /// Edits and overwrites of files the run hasn't read, or that changed since it read them, are refused (B5).
    public var readBeforeEdit = true
    /// The run's read log, made by the loop from the history when `readBeforeEdit` is on.
    var reads: FileReads?

    func withReads(from history: [ChatMessage], workspace: Workspace?) -> AgentConfig {
        var c = self
        if readBeforeEdit { c.reads = FileReads.seeded(from: history, workspace: workspace) }
        return c
    }
    /// Set to offer the `task` tool, which runs subagents.
    public var subagents: SubagentSetup?
    /// Skills the `skill` tool can load (`Skills.load`); empty: no tool. Their folders are readable during the run.
    public var skills: [Skill] = []
    /// Asks the user a question mid-task and returns the answer (nil: no answer, e.g. stopped). Set to offer
    /// `ask_user`; runs nobody is watching (`-p`, subagents) leave it nil.
    public var askUser: (@Sendable ([UserQuestion]) async -> [String?])?
    /// Offer `remember`, which keeps facts in the project's memory under this home folder (B6); nil: not offered
    /// (subagents, the eval).
    public var memoryHome: URL?
    /// The sandbox commands get in each mode (Settings), for a run whose mode changes when a plan is approved; nil:
    /// Full Auto gets the default sandbox, other modes keep `sandbox`.
    public var sandboxFor: (@Sendable (PermissionMode) -> SandboxPolicy?)?
    /// Shows the user the model's plan and returns their decision. Set to offer `present_plan` in Plan mode; runs
    /// nobody is watching leave it nil.
    public var presentPlan: (@Sendable (PlanProposal) async -> PlanDecision)?
    /// The user's hooks (PreToolUse, PostToolUse, Stop run inside the loop).
    public var hooks: Hooks?
    /// The project's test command (`TestSuite`), run again after a main run that changed files; nil: none.
    public var testSuite: String?
    /// The model's provider preferences (OpenRouter), from its profile.
    public var providers: ProviderRouting?
    /// Where each model request and its raw response are saved (the wire log); nil: not kept.
    public var wireLog: WireLog?
    /// Where a turn goes when the server dropped the model's tool call and no other provider could take it.
    public var fallback: FallbackModel?
    /// A main run's snapshots of the project's files, at its start and end (C1); nil: none (subagents, chats).
    public var snapshots: RunSnapshots?

    public init(tools: [any Tool], maxSteps: Int = 100, limits: TurnLimits = TurnLimits(), maxToolOutputBytes: Int = 16_000,
                policy: PermissionPolicy = PermissionPolicy(mode: .fullAuto),
                approve: (@Sendable (ApprovalRequest) async -> ApprovalDecision)? = nil,
                checkpoint: (@Sendable ([URL]) async throws -> Void)? = nil,
                shell: ShellState? = nil, context: ContextBudget? = nil, summary: String? = nil,
                facts: SessionFacts? = nil, outputDirectory: URL? = nil) {
        self.tools = tools
        self.maxSteps = maxSteps
        self.limits = limits
        self.maxToolOutputBytes = maxToolOutputBytes
        self.policy = policy
        self.approve = approve
        self.checkpoint = checkpoint
        self.shell = shell
        self.context = context
        self.summary = summary
        self.facts = facts
        self.outputDirectory = outputDirectory
    }
}

extension AgentConfig {
    /// The most one tool result may hold, from the model's context: about 8% of it (3.3 bytes a token), at least
    /// 16 KB (the old fixed cap, which suits 32–64k local contexts) and at most 200 KB. A 200k Claude session reads
    /// ~53 KB per call instead of 16 KB; a 1M Gemini one 200 KB. The turn's own budget (35% of the context) still
    /// bounds a reply that makes many calls.
    public static func toolOutputBytes(contextLimit: Int?) -> Int {
        guard let limit = contextLimit, limit > 0 else { return 16_000 }
        return min(200_000, max(16_000, Int(Double(limit) * 0.08 * 3.3)))
    }
}

/// A model used only for writing summaries.
public struct Summarizer: Sendable {
    public var client: ChatClient
    public var model: String
    public var historyShape: HistoryShape
    public var endpointID: UUID?

    public init(client: ChatClient, model: String, historyShape: HistoryShape = HistoryShape(), endpointID: UUID? = nil) {
        self.client = client
        self.model = model
        self.historyShape = historyShape
        self.endpointID = endpointID
    }
}

/// Another model that takes over one turn when the main model's tool call was lost.
public struct FallbackModel: Sendable {
    public var client: ChatClient
    public var model: String
    public var historyShape: HistoryShape
    public var temperature: Double?
    public var endpointID: UUID?
    public var sendImages: Bool

    public init(client: ChatClient, model: String, historyShape: HistoryShape = HistoryShape(), temperature: Double? = nil,
                endpointID: UUID? = nil, sendImages: Bool = false) {
        self.client = client
        self.model = model
        self.historyShape = historyShape
        self.temperature = temperature
        self.endpointID = endpointID
        self.sendImages = sendImages
    }
}

/// How an agent run ended.
public enum AgentStop: Sendable, Equatable {
    /// The model answered without calling tools.
    case completed
    /// Hit `maxSteps`; the user can continue.
    case stepLimit
    /// Spent what Settings allows a run (the user can continue) or the session (they must raise the limit).
    case costLimit
    /// A model turn stopped early: timed out, repeating, or failed.
    case turnStopped(StopReason)
    /// The model's answer was cut off at the output-token limit.
    case truncated
    case cancelled
    /// The user denied a call without feedback; the run waits for their instructions.
    case denied
}

public enum AgentEvent: Sendable {
    /// Live view of the model's current turn.
    case streaming(TurnSnapshot)
    /// A finished assistant message (may contain tool calls).
    case assistant(ChatMessage)
    case toolStarted(ToolCall)
    /// Output from a running tool, for the UI.
    case toolProgress(callID: String, text: String)
    /// The tool's result message (role .tool), ready to store.
    case toolFinished(ChatMessage)
    /// The user chose "always allow"; the rule holds for the rest of the session.
    case ruleAdded(AllowRule)
    /// The run switched permission mode (an approved plan, B1): the app and CLI show and save it.
    case modeChanged(PermissionMode)
    /// Estimated size of the prompt about to be sent.
    case promptSize(tokens: Int)
    /// A message the user queued during the run, now part of the conversation (store it).
    case injected(ChatMessage)
    /// Something a hook said that the user should see (a failed hook, a blocked call).
    case hookNotice(String)
    /// The server lost the model's reply; the same turn is being sent elsewhere (why, and where).
    case retrying(String)
    /// Summarizing the conversation to free context.
    case compacting
    /// The start of the session was replaced by a summary.
    case compacted(Compaction)
    /// A request that was (or may have been) billed: store it with the session (`SessionRecord.cost`).
    case cost(CostEntry)
    /// The run's record, just before `.finished`: store it with the session (`SessionRecord.run`).
    case runEnded(AgentRunRecord)
    /// A subagent run started (a `task` call).
    case subagentStarted(SubagentInfo)
    /// A running subagent's progress: steps, tool calls, tokens, and whether it waits for the user's approval.
    case subagentProgress(SubagentProgress)
    /// A subagent run ended (what its session records as its end).
    case subagentFinished(id: UUID, end: SubagentEnd)
    /// A subagent run was judged (checks, the parent's rating, a grader). The run's own session has it already;
    /// store a copy with the session that started it (`SessionRecord.judgment`).
    case judged(RunJudgment)
    /// What the loop is doing while nothing else shows (waiting for background subagents to report).
    case status(String)
    case finished(AgentStop)
}

/// The agent loop: stream a turn, run the tools it calls (asking when the policy says to), feed back
/// the results, repeat.
public enum AgentLoop {
    public static func run(client: ChatClient,
                           model: String,
                           systemPrompt: String?,
                           history: [ChatMessage],
                           config: AgentConfig,
                           workspace: Workspace?,
                           emit: @escaping @Sendable (AgentEvent) async -> Void) async {
        // Every event passes through the run's tracker; when the run ends, its record goes out before `.finished`.
        let tracker = RunTracker()
        let scope = config.costScope ?? CostScope(run: UUID(), agent: "main")
        var config = config
        config.costScope = scope
        var tools = (config.sameToolsInEveryMode ? PermissionPolicy.offeredInEveryMode(config.tools) : config.policy.offered(config.tools)).map(\.name)
        if tools.contains("bash") { tools += BackgroundTools.all.map(\.name) }
        if !config.skills.isEmpty { tools.append("skill") }
        if config.askUser != nil { tools.append("ask_user") }
        if config.presentPlan != nil, config.sameToolsInEveryMode || config.policy.mode == .plan { tools.append("present_plan") }
        if config.memoryHome != nil { tools.append("remember") }
        if config.subagents != nil { tools += ["task", "rate_task"] }
        let localModel = await LocalModelInfo.lookup(client: client, model: model)
        let recordConfig = config, toolNames = tools.sorted()
        let startSnapshot = await config.snapshots?.take(.start, run: scope.run, emit: emit)
        // The mode, sandbox and rules as the loop leaves them: an approved plan or an "always allow" during the run
        // changes what the end-of-run suite may do (it used to be authorized with the run's starting policy).
        let runMode = RunMode(policy: config.policy, sandbox: config.sandbox)
        await runLoop(client: client, model: model, systemPrompt: systemPrompt, history: history, config: config,
                      workspace: workspace, runMode: runMode) { event in
            tracker.observe(event)
            if case .finished(let stop) = event {
                // OpenRouter's record of each reply (the exact charge, native token counts), once, at the end of the run.
                if !Task.isCancelled, case let pending = tracker.unreconciled, !pending.isEmpty {
                    let clients = [client] + [recordConfig.summarizer?.client, recordConfig.fallback?.client].compactMap { $0 }
                    for e in await CostEntry.reconcile(pending, clients: clients, delays: recordConfig.generationLookupDelays) {
                        tracker.observe(.cost(e))
                        await emit(.cost(e))
                    }
                }
                var record = tracker.record(stop: stop, scope: scope, config: recordConfig, client: client, model: model,
                                            systemPrompt: systemPrompt ?? "", history: history, tools: toolNames,
                                            localModel: localModel)
                if let s = recordConfig.snapshots, let start = startSnapshot {
                    let end = await s.take(.end, run: scope.run, emit: emit)
                    record.snapshots = RunSnapshotRefs(start: start.commit, end: end?.commit, skipped: (end ?? start).skipped,
                                                       changed: end.map { $0.tree != start.tree })
                }
                // The project's own tests, once more after a main run that changed files and ended on its own (11b).
                if let command = recordConfig.testSuite, scope.agent == "main", stop == .completed, let workspace, !Task.isCancelled,
                   record.snapshots?.changed ?? !record.outcome.filesChanged.isEmpty {
                    await emit(.status("Running the project's tests after the run: \(command)"))
                    let byName = Dictionary(recordConfig.tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                    if let check = await runCheck(command, tools: byName, config: runMode.applied(to: recordConfig), workspace: workspace,
                                                  callID: "suite_" + (scope.run ?? UUID()).uuidString, fromRoot: true,
                                                  emit: emit), check.ran {
                        record.signals?.suite = SessionFacts.Check(command: command, exitCode: exitStatus(check.output),
                                                                   timedOut: check.output.text.contains("[Timed out after") ? true : nil)
                    }
                }
                await emit(.runEnded(record))
            }
            await emit(event)
        }
    }

    static func runLoop(client: ChatClient,
                        model: String,
                        systemPrompt: String?,
                        history: [ChatMessage],
                        config: AgentConfig,
                        workspace: Workspace?,
                        runMode shared: RunMode? = nil,
                        emit send: @escaping @Sendable (AgentEvent) async -> Void) async {
        // On a third-party model, secrets in the project (Settings → Generation → Privacy) aren't read or changed.
        // Searches skip files a Read deny rule covers. Skill folders outside the project are readable, not writable.
        let workspace = workspace.map { ws -> Workspace in
            var w = ws
            if client.isThirdParty, !config.withheldFromRemote.isEmpty {
                w.withheld = WithheldFiles(patterns: config.withheldFromRemote, host: client.baseURL.host() ?? "the model's server")
            }
            if config.permissionRules.deniesSomeReads { w.readDenied = config.permissionRules }
            for s in config.skills where !w.contains(s.folder) && w.folder(containing: s.folder) == nil {
                w.folders.append(ExtraFolder(path: s.folder.path, writable: false))
            }
            // Full output of long commands is saved there, and the result names the file: readable, never writable.
            if let dir = config.outputDirectory, !w.contains(dir), w.folder(containing: dir) == nil {
                w.folders.append(ExtraFolder(path: dir.path, writable: false))
            }
            return w
        }
        let config = config.withReads(from: history, workspace: workspace)
        let baseSystem = systemPrompt ?? ""
        let background = BackgroundRuns()
        /// The mode, sandbox and session rules as they are now, for subagents, the end-of-run checks and the caller.
        let runMode = shared ?? RunMode(policy: config.policy, sandbox: config.sandbox)
        /// The messages the session stores: the history it gave (not a continuation it inserted) and what this run
        /// emits. A compaction's boundaries are chosen among these, or the store can't place the compaction.
        let stored = StoredIDs(history.filter { !isContinuation($0) }.map(\.id))
        // A run that ends stops its background subagents; what they report still goes in the conversation, since an
        // isolated one's says where its work is. An "always allow" from any card (a subagent's too) joins the run's rules.
        let emit: @Sendable (AgentEvent) async -> Void = { event in
            if case .finished = event {
                await background.stopAll()
                for m in background.takeReports() { await send(.injected(m)) }
            }
            switch event {
            case .ruleAdded(let rule): runMode.add(rule)
            case .assistant(let m), .toolFinished(let m), .injected(let m): stored.insert(m.id)
            default: break
            }
            await send(event)
        }
        var system = baseSystem
        if let summary = config.summary, !summary.isEmpty {
            system += (system.isEmpty ? "" : "\n\n") + Compaction.systemSection(summary)
        }
        var messages: [ChatMessage] = []
        if !system.isEmpty { messages.append(.system(system)) }
        messages += sendable(history)
        // A new session's first run: what SessionStart hooks print goes to the model. Not a subagent's.
        // (A summary means it isn't new: a compaction leaves no replies in the history.)
        if (config.costScope?.agent ?? "main") == "main", !history.contains(where: { $0.role == .assistant }), config.summary?.isEmpty != false,
           let hooks = config.hooks {
            let start = await hooks.sessionStart()
            for e in start.errors { await emit(.hookNotice(e)) }
            if !start.context.isEmpty {
                let m = FrozenSystemPrompt.noteMessage("[Context from a hook]\n" + start.context.joined(separator: "\n"))
                messages.append(m)
                await emit(.injected(m))
            }
        }
        // The history before this run (all but the request that starts it), for the cost entries' `promptMix`.
        let earlierIDs = Set(history.dropLast(history.last?.role == .user ? 1 : 0).map(\.id))
        var estimator = TokenEstimator()
        var lastSummarizedID = history.last(where: { stored.contains($0.id) })?.id
        /// Everything this run adds, untrimmed. With `config.facts` (the session before this run), the
        /// source for tracked progress.
        var runMessages: [ChatMessage] = []
        var policy = config.policy
        /// The sandbox commands run in; it follows the mode when an approved plan changes it.
        var sandbox = config.sandbox
        var available = config.tools
        if !config.skills.isEmpty { available.append(SkillTool(skills: config.skills)) }
        if config.askUser != nil { available.append(AskUserTool()) }
        if config.presentPlan != nil { available.append(PresentPlanTool()) }
        if config.memoryHome != nil { available.append(RememberTool()) }
        // Subfolders' instruction files go out with the first result that touches their folder (B6).
        let nested = workspace.map { NestedInstructions(root: $0.root, history: history) }
        if available.contains(where: { $0.name == "bash" }) { available += BackgroundTools.all }
        // The session's subagent runs, for the parent's ratings of them (`rate_task`).
        let taskRuns = TaskRuns()
        taskRuns.seed(history)
        /// Records the parent's rating of a run: in the run's session, and (through the event) in this one's.
        @Sendable func rate(_ ref: String, _ verdict: Int, _ checked: String, _ issues: [String], _ note: String?,
                            request: (id: UUID, prompt: String, response: String)? = nil) async -> Result<String, ToolFailure> {
            guard let e = taskRuns.find(ref) else {
                if taskRuns.isEmpty {
                    return .failure(ToolFailure("no subagent has run in this session, so there's nothing to rate: rate_task is only for the task tool's runs. Go on without it."))
                }
                return .failure(ToolFailure("no subagent task matches \"\(ref)\"; give the task's title."))
            }
            guard let run = e.run else { return .failure(ToolFailure("that task's run wasn't recorded, so it can't be rated.")) }
            var j = RunJudgment(run: run, taskCall: e.callID, judge: .parent, judgeModel: model, judgeEndpointID: config.endpointID,
                                verdict: verdict, checked: checked, issues: issues, note: note)
            // The rating call itself isn't a check.
            let (confirmed, evidence) = TaskRuns.evidence(e.callsAfter.filter { $0.name != "rate_task" }, checked: checked)
            j.checkedConfirmed = confirmed
            j.evidence = evidence.isEmpty ? nil : evidence
            if let request { (j.requestID, j.prompt, j.response) = (request.id, request.prompt, request.response) }
            if let rec = config.subagents?.recorder { try? await rec.store.append(.judgment(j), toRun: run, of: rec.parent) }
            await emit(.judged(j))
            taskRuns.markRated(e.callID)
            return .success("Recorded: \"\(e.title.isEmpty ? e.agent : e.title)\" rated \(verdict)/3. It's rated now; don't rate it again.")
        }
        if let setup = config.subagents {
            let parentAtStart = config
            let templates = PromptTemplates.standard(project: workspace?.root)
            available.append(RateTaskTool(templates: templates) { ref, verdict, checked, issues, note in
                await rate(ref, verdict, checked, issues, note)
            })
            available.append(TaskTool(agents: setup.agents, templates: templates) { agent, title, prompt, context, inBackground, isolated, card in
                // The parent's mode now: an approved plan changes it mid-run, and subagents follow.
                let parent = runMode.applied(to: parentAtStart)
                guard inBackground else {
                    return await runSubagent(agent, title: title, prompt: prompt, context: context, setup: setup, parent: parent,
                                             client: client, model: model, workspace: workspace, emit: emit,
                                             card: card, registry: taskRuns, isolated: isolated)
                }
                // In the background: agents that only read, or that have a worktree of their own (one that writes here
                // would change files under the main agent's feet). The call returns at once; the report comes as a
                // message later in this run.
                let tools = subagentTools(agent, parent: parent)
                guard isolated || parent.policy.offered(tools).allSatisfy({ $0.risk == .read }) else {
                    return .error("background runs are for agents that only read (explore, or one whose tools are all "
                        + "read-only), or that have isolation: worktree; \(agent.name) can change things, so run it without "
                        + "background, or with isolation.")
                }
                let id = UUID()
                var silenced = context
                silenced.progress = nil                 // the card is done; its progress shows in the Agents list
                let quiet = silenced
                background.start(id) {
                    let out = await runSubagent(agent, title: title, prompt: prompt, context: quiet, setup: setup, parent: parent,
                                                client: client, model: model, workspace: workspace, emit: emit, runID: id,
                                                card: card, registry: taskRuns, isolated: isolated)
                    var m = ChatMessage.user("[Report from the \(agent.name) subagent you started in the background: \"\(title)\". "
                        + "This is its final report, not a message from the user.]\n\n" + out.text)
                    m.subagentReport = out.subagentRun ?? id          // a retried run: the second attempt's
                    return m
                }
                var started = ToolOutput(text: "Started the \(agent.name) subagent in the background (\"\(title)\"). Its report will "
                    + "arrive as a message when it's done. Keep working on something else meanwhile; don't start the same "
                    + "task again or wait for it.")
                started.subagentRun = setup.recorder == nil ? nil : id
                return started
            })
        }
        // The same tools in every mode, so an approved plan doesn't change the cached prompt; the mode is enforced when
        // a call comes (`PermissionPolicy.modeRefusal`).
        let steady = config.sameToolsInEveryMode
        func offer() -> [any Tool] { steady ? PermissionPolicy.offeredInEveryMode(available) : policy.offered(available) }
        var tools = Dictionary(offer().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var definitions = offer().map(\.definition)
        /// Switches the run to `mode` (an approved plan): the sandbox, what subagents get, and the tools offered when
        /// they follow the mode. Returns what the model should know about the sandbox now.
        func switchMode(to mode: PermissionMode) async -> String {
            policy.mode = mode
            if !steady {
                tools = Dictionary(offer().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                definitions = offer().map(\.definition)
            }
            if let f = config.sandboxFor { sandbox = f(mode) }
            else if mode == .fullAuto, sandbox == nil, SandboxPolicy.isAvailable { sandbox = SandboxPolicy() }
            runMode.set(policy: policy, sandbox: sandbox)
            await emit(.modeChanged(mode))
            guard let sandbox else { return "" }
            return " Commands run in a sandbox: they can write only inside the project and temp directories"
                + (sandbox.allowNetwork ? "." : ", and have no network.")
        }
        let shell = config.shell ?? workspace.map { ShellState(cwd: $0.root) }
        // Background subagent runs started in this run; whatever is still going when it ends is stopped.
        defer { background.cancelAll() }
        // Read calls already answered, by name + arguments: small models repeat themselves. Cleared
        // whenever something changes, since a re-read after an edit is legitimate.
        var seen = Set<String>()
        /// The last call that could change something, and how many times in a row the model made it.
        var lastAction: String?
        var actionRepeats = 0

        /// The system prompt carries a compaction summary.
        var hasSummary = !(config.summary ?? "").isEmpty
        /// The model's last summary (without the tracked progress), for sizing the next one.
        var lastSummaryBytes = (config.summary ?? "").components(separatedBy: "\n\n## Progress so far").first?.utf8.count ?? 0
        /// Why the last compaction didn't happen, for the next reply's notes.
        var compactionNote: String?
        /// A skipped compaction is noted once until one happens (it would otherwise repeat on every reply).
        var skipNoted = false
        /// Cost entries of this step's requests, emitted once it's known whether each reply was kept, asked again, or
        /// retried elsewhere (`flushCosts`).
        var pendingCosts: [CostEntry] = []
        let scope = config.costScope ?? CostScope(run: nil, agent: "main")
        /// The run's last kept reply's cost, to notice a lost prompt cache (`CacheWatch`), once a run.
        var lastKept: CostEntry? = config.previousReply
        var cacheNoted = false
        /// What happened to the history since `lastKept`, and whether each pending request's history extended its
        /// (`PromptPrint`), for naming a cache miss.
        var changesSinceKept = CacheLedger.Changes()
        var extendsKept: [UUID: Bool] = [:]
        func flushCosts(retried: Set<UUID> = [], nudged: UUID? = nil) async {
            for var e in pendingCosts {
                if retried.contains(e.reply) { e.purpose = .retryAttempt } else if e.reply == nudged { e.purpose = .nudgedReply }
                // The main model's own replies only: a fallback model's or a retried one's cache is another.
                let kept = e.purpose == .reply || e.purpose == .nudgedReply
                if kept, let p = lastKept {
                    var changes = changesSinceKept
                    changes.extends = extendsKept[e.id]
                    e.cacheMiss = CacheLedger.classify(previous: p, current: e, changes: changes)
                }
                await emit(.cost(e))
                guard kept else { continue }
                if !cacheNoted, let note = CacheWatch.check(previous: lastKept, current: e) {
                    cacheNoted = true
                    await emit(.status(note))
                }
                lastKept = e
                changesSinceKept = CacheLedger.Changes()
            }
            pendingCosts = []
            extendsKept = [:]
        }
        /// Paused turns sent back in a row (Claude's `pause_turn`).
        var pausedContinues = 0
        /// Holds trims of the history back until they can make room or the session has grown (`Compactor.TrimGate`).
        var trimGate = Compactor.TrimGate()
        /// Replaces the start of the conversation with a summary. Returns false if it couldn't, or if it wouldn't
        /// save `minimumSaving` tokens (predicted before asking for a summary, checked again after).
        func compact(minimumSaving: Int) async -> Bool {
            guard let budget = config.context else { return false }
            let before = estimator.tokens(messages, tools: definitions)
            let body = Array(messages.drop { $0.role == .system })
            // Progress over the whole session: what was known at the start of the run plus this run so far.
            var facts = config.facts ?? SessionFacts()
            facts.absorb(runMessages, root: workspace?.root.path)
            let plan = Compactor.plan(body: body, baseSystem: baseSystem, facts: facts.isEmpty ? nil : facts,
                                      previousSummaryBytes: lastSummaryBytes, tools: definitions, budget: budget,
                                      estimator: estimator)
            guard plan.index > 0, plan.predictedTokens <= before - minimumSaving else {
                if !skipNoted {
                    compactionNote = "Didn't compact: a summary would leave about \(plan.predictedTokens) of \(before) "
                        + "tokens; trimming older tool outputs instead."
                    skipNoted = true
                }
                return false
            }
            if let hooks = config.hooks {
                for e in await hooks.preCompact(trigger: "auto").errors { await emit(.hookNotice(e)) }
            }
            await emit(.compacting)
            let s = config.summarizer
            let recorded = RequestIDs()
            guard let summary = await Compactor.summarize(client: s?.client ?? client, model: s?.model ?? model,
                                                          messages: messages, tools: definitions, limits: config.limits,
                                                          maxTokens: Compactor.summaryMaxTokens(limit: budget.limit, promptTokens: before),
                                                          shape: s?.historyShape ?? config.historyShape,
                                                          thinking: config.summaryThinking, cacheForAnHour: config.promptCacheHour,
                                                          cacheKey: config.cacheKey, meter: config.costMeter,
                                                          costs: CostSink(scope: scope, endpointID: s == nil ? config.endpointID : s?.endpointID,
                                                                          emit: { await emit(.cost($0)) }),
                                                          wire: config.wireLog, recorded: recorded,
                                                          words: Compactor.summaryWords(limit: budget.limit)) else {
                if !Task.isCancelled { compactionNote = "Didn't compact: no usable summary came back; trimming older tool outputs instead." }
                return false
            }
            let (index, continuation) = (plan.index, plan.continuation)
            // Answered outputs in the kept part are trimmed; the results after the model's latest reply go on whole, since
            // it hasn't read them yet (trimmed, a big read was cut before it was ever seen, and read again after).
            var kept = Compactor.trimAnswered(Array(body[index...]), maxToolBytes: 4000)
            if continuation { kept.insert(.user(Compactor.continuationText), at: 0) }
            // The store trims the same way on reload: through the last kept message before the latest reply, if any.
            let unseen = body.lastIndex(where: { $0.role == .assistant }) ?? body.count
            let trimmedThrough = body[index..<max(index, unseen)].last(where: { stored.contains($0.id) })?.id
            var compaction = Compaction(summary: summary, lastSummarizedID: lastSummarizedID ?? UUID(),
                                        continuation: continuation ? Compactor.continuationText : nil,
                                        lastKeptID: trimmedThrough,
                                        tokensBefore: before, tokensAfter: 0, facts: facts.isEmpty ? nil : facts)
            let newSystem = baseSystem + (baseSystem.isEmpty ? "" : "\n\n") + Compaction.systemSection(compaction.modelText)
            let after = [ChatMessage.system(newSystem)] + kept
            compaction.tokensAfter = estimator.tokens(after, tools: definitions)
            compaction.summaryRequests = recorded.ids.isEmpty ? nil : recorded.ids
            // The summary came out longer than planned: keep the conversation as it is.
            guard compaction.tokensAfter < before else {
                compactionNote = "Didn't compact: the summary left \(compaction.tokensAfter) tokens of \(before)."
                return false
            }
            // The boundary must be a message the session actually stores, not an inserted continuation or a result
            // placeholder; with none in the summarized part, the previous boundary still holds (everything stored after
            // it is kept).
            if let real = body[..<index].last(where: { stored.contains($0.id) }) { lastSummarizedID = real.id }
            guard let boundary = lastSummarizedID else { return false }
            compaction.lastSummarizedID = boundary
            messages = after
            nested?.reseed(from: messages)      // rules the summary dropped go out again on the next touch
            seen.removeAll()                    // the results are summarized away: reading again is legitimate
            hasSummary = true
            changesSinceKept.compacted = true
            lastSummaryBytes = summary.utf8.count
            compactionNote = nil
            skipNoted = false
            await emit(.compacted(compaction))
            return true
        }

        /// At the end of a run that used subagents: asks the parent to rate the runs it hasn't rated, aside from the
        /// conversation (nothing here is kept in it), with the same prefix as its last request so the server's cache
        /// covers it. The parent may look before it rates (seen: asked to rate "from what you checked", qwen3.5-9b read
        /// the files first): read-only calls run, for up to 4 requests, and count as the check its rating claims.
        func askForRatings(_ unrated: [TaskRuns.Entry]) async {
            let ask = Self.ratingRequest(unrated)
            await emit(.status("Asking for ratings of the subagent runs…"))
            let routing = (config.providers ?? ProviderRouting()).avoiding(avoidedProviders)
            await Self.ratingSideLoop(client: client, model: model, messages: messages, ask: ask, tools: tools,
                                      definitions: definitions, config: config, workspace: workspace,
                                      provider: routing.isEmpty ? nil : routing,
                                      costs: CostSink(scope: scope, endpointID: config.endpointID, emit: { await emit(.cost($0)) }),
                                      verify: Set(unrated.compactMap { $0.card?.verify }), emit: emit,
                                      done: { taskRuns.unrated.isEmpty },
                                      looked: { taskRuns.noteCalls($0) }) { r, request in
                switch await rate(r.task, r.verdict, r.checked, r.issues, r.note, request: request) {
                case .success(let t): return ToolOutput(text: t)
                case .failure(let f): return .error(f.message)
                }
            }
        }

        /// Reads in a row by this agent, and what they put into the context, for the advice to delegate.
        var readStreak = 0, readStreakBytes = 0
        var delegationAdvised = false
        /// A7: the next step is a `task` call (set at the threshold, used by the next turn).
        var delegationDue = false
        let canForce = ToolForcing.supported(client: client, model: model, effort: config.reasoningEffort)
        let canWrite = ToolForcing.canWrite(client: client, model: model, effort: config.reasoningEffort)
        /// The note for a long run of reads (`note-delegate.md`), once a run, when subagents are on.
        func delegationNote(_ call: ToolCall, _ output: ToolOutput) -> String? {
            guard config.subagents != nil, config.delegationAdvice, !delegationAdvised, let budget = config.context else { return nil }
            if Self.broadReads.contains(call.name) {
                readStreak += 1
                readStreakBytes += output.text.utf8.count
            } else {
                readStreak = 0
                readStreakBytes = 0
                return nil
            }
            let tokens = Int(Double(readStreakBytes) / estimator.bytesPerToken)
            let byShare = tokens * 5 >= budget.limit
            let byTokens = config.delegationTokens > 0 && tokens >= config.delegationTokens
            guard readStreak >= 6, byShare || byTokens else { return nil }
            delegationAdvised = true
            var vars = ["reads": "\(readStreak)", "tokens": "\(tokens)"]
            // Forced where the server can be made to, written where it can't but may be, else the note alone. The
            // absolute trigger alone (a big context) only ever gives the note.
            if byShare, config.delegationForce, tools["task"] != nil, canForce || canWrite {
                delegationDue = true
                vars[canForce ? "force" : "delegated"] = "yes"
            }
            let note = PromptTemplates.standard(project: workspace?.root).render("note-delegate", vars)
            return note.isEmpty ? nil : note
        }

        /// The `task` call kurtkode writes when the server can't be made to (A7): the explore agent, told the request and
        /// what has been read already.
        func delegationCall() -> ChatMessage {
            let request = history.last { $0.role == .user && $0.contextNote != true && $0.subagentReport == nil }?.content ?? ""
            var read: [String] = []
            for m in runMessages where m.role == .assistant {
                for c in m.toolCalls where Self.broadReads.contains(c.name) {
                    let a = (try? ToolArguments(json: c.arguments)) ?? ToolArguments()
                    if let p = a.string("path") ?? a.string("pattern"), !read.contains(p) { read.append(p) }
                }
            }
            let prompt = "The main agent is working on this request:\n\n" + String(request.prefix(4_000))
                + (read.isEmpty ? "" : "\n\nIt has already looked at: " + read.prefix(30).joined(separator: ", ") + ".")
                + "\n\nRead the rest of what bears on the request (re-read those only if you need to) and report what the main "
                + "agent needs to answer it: the relevant files, functions and facts, with path:line, briefly."
            let args: JSONValue = ["description": "Read the rest for the request", "prompt": .string(prompt), "agent": "explore"]
            let text = String(decoding: (try? JSONEncoder().encode(args)) ?? Data(), as: UTF8.self)
            // No meta: no model wrote it (the note on the last result says kurtkode did).
            return ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "kk_delegate_\(UUID().uuidString.prefix(8))", name: "task", arguments: text)])
        }

        /// Providers that dropped a call in this run; later requests avoid them too.
        var avoidedProviders = Set<String>()
        /// The nudges sent this run, for the context index.
        var nudgeIDs = Set<UUID>()
        /// Sends the model a nudge: a context note, stored with the session like any other, so a later run's history
        /// (and a compaction's boundary) agrees with what was sent.
        func sendNudge(_ text: String) async {
            let m = FrozenSystemPrompt.noteMessage(text)
            nudgeIDs.insert(m.id)
            messages.append(m)
            runMessages.append(m)
            await emit(.injected(m))
        }

        /// What this request carries, by session message, for the context index.
        func contextRefs(_ shape: HistoryShape, api: WireAPI, model: String) -> [ContextRef] {
            messages.map { m in
                if m.role == .system {
                    return ContextRef(id: nil, role: "system", kind: hasSummary ? "system+summary" : "system", bytes: m.content.utf8.count)
                }
                let sendsReasoning = m.role == .assistant && !(m.reasoning ?? "").isEmpty
                    && (shape.sendReasoning || NativeWire.carriesReasoning(m, api: api, model: model))
                let bytes = m.content.utf8.count + m.toolCalls.reduce(0) { $0 + $1.name.utf8.count + $1.arguments.utf8.count }
                    + (sendsReasoning ? (m.reasoning ?? "").utf8.count : 0)
                let kind: String? = nudgeIDs.contains(m.id) ? "nudge" : isContinuation(m) ? "continuation" : nil
                return ContextRef(id: m.id, role: m.role.rawValue, kind: kind, bytes: bytes, reasoning: sendsReasoning ? true : nil)
            }
        }

        /// One model turn on the main model (or `alt`), with the reply repaired: tool names with text glued on,
        /// calls written as text.
        func turn(on alt: FallbackModel?) async -> ChatMessage {
            let shape = alt?.historyShape ?? config.historyShape
            let shaped = HistoryShaper.shape(messages, for: shape)
            var notes: [String] = []
            if let alt { notes.append("Sent to the fallback model \(alt.model).") }
            if shaped != messages { notes.append("The history was reshaped for this model's chat template.") }
            var request = ChatRequest(model: alt?.model ?? model, messages: shaped,
                                      tools: definitions, maxTokens: config.limits.maxTokens,
                                      temperature: alt == nil ? config.temperature : alt?.temperature,
                                      sendReasoning: shape.sendReasoning, sendImages: alt?.sendImages ?? config.sendImages)
            if alt == nil, delegationDue, canForce {
                request.forcedTool = "task"          // cleared once a reply comes back (a dropped or overflowing turn keeps it)
                notes.append("kurtkode required a task call: the delegation threshold was reached (A7).")
            }
            request.cacheForAnHour = config.promptCacheHour
            request.cacheKey = config.cacheKey
            request.webSearch = config.webSearch
            if alt == nil {
                if let r = config.reasoning { request.reasoning = r }
                else { ReasoningSetting.apply(config.reasoningEffort, to: &request, client: client) }
            }
            if alt == nil {
                let routing = (config.providers ?? ProviderRouting()).avoiding(avoidedProviders)
                request.provider = routing.isEmpty ? nil : routing
                if !avoidedProviders.isEmpty { notes.append("Avoiding providers that lost a reply: \(avoidedProviders.sorted().joined(separator: ", ")).") }
            }
            let tap = config.wireLog == nil ? nil : WireTap()
            let started = Date()
            var reply = await TurnRunner.run(client: alt?.client ?? client, request: request, limits: config.limits, tap: tap) { snap in
                await emit(.streaming(snap))
            }
            let usedClient = alt?.client ?? client
            let price = await PriceLookup.lookup(client: usedClient, model: CostEntry.pricedModel(reply))
            var entry = CostEntry.make(reply: reply, purpose: alt == nil ? .reply : .fallbackReply, run: scope.run,
                                       agent: scope.agent, client: usedClient,
                                       endpointID: alt == nil ? config.endpointID : alt?.endpointID, start: started, price: price)
            entry.promptMix = CostEntry.promptMix(messages, baseSystem: baseSystem, tools: definitions, earlier: earlierIDs,
                                                  promptTokens: reply.meta?.usage?.promptTokens)
            if alt == nil {
                let (print, extends) = PromptPrint.of(request, ttl: request.cacheForAnHour ? "1h" : nil, previous: lastKept?.prompt)
                entry.prompt = print
                if let extends { extendsKept[entry.id] = extends }
            }
            config.costMeter?.add(entry)
            pendingCosts.append(entry)
            if let log = config.wireLog, let tap {
                await log.write(tap.record(replyID: reply.id, startedAt: started, duration: Date().timeIntervalSince(started)))
                await log.writeContext(ContextSnapshot(replyID: reply.id, startedAt: started, refs: contextRefs(shape, api: (alt?.client ?? client).api, model: request.model)))
            }
            reply.meta?.endpointID = alt == nil ? config.endpointID : alt?.endpointID
            // A call whose name has text glued on (the model echoed the last tool result) is repaired to the
            // tool it ends with; any other unknown name is left for the "unknown tool" error.
            reply.toolCalls = reply.toolCalls.map { c in
                guard tools[c.name] == nil, let fixed = TextToolCalls.repairName(c.name, known: Set(tools.keys)) else { return c }
                notes.append("Renamed the tool call \"\(c.name.prefix(80))\" to \(fixed) (text was glued onto the name).")
                return ToolCall(id: c.id, name: fixed, arguments: c.arguments)
            }
            if shape.parseTextToolCalls, reply.toolCalls.isEmpty,
               let found = TextToolCalls.extract(from: reply.content, knownTools: Set(tools.keys),
                                                  parameterSchemas: tools.mapValues(\.parameters)) {
                reply.toolCalls = found.calls.enumerated().map { i, c in
                    ToolCall(id: "text_\(reply.id.uuidString.prefix(8))_\(i)", name: c.name, arguments: c.arguments)
                }
                notes.append("Recovered \(found.calls.count) tool call\(found.calls.count == 1 ? "" : "s") written as text (\(found.calls.map(\.name).joined(separator: ", "))).")
                reply.meta?.rawContent = reply.content
                reply.content = found.remaining
            }
            if !notes.isEmpty {
                let fromServer = reply.meta?.notes ?? []
                reply.meta?.notes = fromServer + notes
            }
            return reply
        }

        func noted(_ m: ChatMessage, _ note: String) -> ChatMessage {
            var m = m
            let old = m.meta?.notes ?? []
            m.meta?.notes = old + [note]
            return m
        }

        /// A tool call the server dropped can't be recovered by asking again: the model, which never sees the
        /// lost call, sends it again (measured: 0 of 9 runs recovered with any nudge wording). So the same request
        /// goes elsewhere: to other providers of the model (OpenRouter; at most two more), then to the fallback
        /// model for this one turn. Each lost reply is still reported (it was paid for), but not sent back.
        /// Returns the reply to go on with, and the replies before it (lost ones, failed retries), with notes, for the
        /// caller to report first.
        func recoverDroppedCall(_ first: ChatMessage) async -> (ChatMessage, earlier: [ChatMessage]) {
            var reply = first
            var earlier: [ChatMessage] = []
            var providerRetries = 0
            var usedFallback = false
            while Self.droppedCall(reply), !Task.isCancelled {
                let lost = reply
                let provider = providerRetries < 2 ? lost.meta?.provider : nil
                let fallback = usedFallback ? nil : config.fallback
                guard provider != nil || fallback != nil else { break }
                let what = "lost the reply (\(lost.meta?.usage?.completionTokens ?? 0) tokens generated, nothing delivered)"
                if let provider {
                    providerRetries += 1
                    avoidedProviders.insert(provider)
                    earlier.append(noted(lost, "\(provider) \(what); the same request went to another provider."))
                    await emit(.retrying("\(provider) \(what). Sending it to another provider."))
                    reply = await turn(on: nil)
                    // No provider is left, or OpenRouter refused the preferences: forget them and move on. The failed
                    // request isn't a message; its wire record stays, linked from the lost reply.
                    if reply.meta?.stopReason == .failed {
                        let why = reply.meta?.error ?? "the request failed"
                        await emit(.retrying("No other provider took it: \(why)."))
                        var back = noted(earlier.removeLast(), "No other provider took the retry (\(why)); going on without provider preferences.")
                        let earlierRetries = back.meta?.retryRequests ?? []
                        back.meta?.retryRequests = earlierRetries + [reply.id]
                        avoidedProviders.removeAll()
                        providerRetries = 2
                        reply = back
                    }
                } else if let fallback {
                    usedFallback = true
                    earlier.append(noted(lost, "The server \(what); this turn went to the fallback model \(fallback.model)."))
                    await emit(.retrying("The server \(what). Sending this turn to \(fallback.model)."))
                    reply = await turn(on: fallback)
                }
            }
            return (reply, earlier)
        }

        var overflowRetried = false
        /// Replies in a row whose last call was cut off at the output limit (its arguments incomplete).
        var cutReplies = 0
        var emptyNudges = 0
        var todoNudged = false
        /// A reply stopped for repeating itself was answered with a nudge (once a run).
        var repetitionNudged = false
        /// Plans given as answers in Plan mode that went to the user as plans (B1).
        var planFallbacks = 0
        var stopHookContinues = 0
        /// Appends what the user queued; true if there was anything.
        /// What the user queued, then the reports of background subagents that finished.
        @discardableResult func takeQueuedInput() async -> Bool {
            // After Stop, what the user typed stays theirs (the app puts it back in the composer), not sent unanswered.
            guard !Task.isCancelled else { return false }
            let queued = (await config.takeInput?() ?? []) + background.takeReports()
            if !queued.isEmpty { seen.removeAll() }     // the user may have changed files the model read
            for m in queued {
                messages.append(m)
                runMessages.append(m)
                await emit(.injected(m))
            }
            return !queued.isEmpty
        }
        for _ in 0..<config.maxSteps {
            if Task.isCancelled { await emit(.finished(.cancelled)); return }
            // Spent what Settings allows: pause before the next request, as at the step limit.
            if let note = config.costMeter?.stopNote { await emit(.status(note)); await emit(.finished(.costLimit)); return }
            // Over the threshold: compact if that shrinks the prompt enough (the planner works it out before
            // asking for a summary); otherwise trim the tool outputs the model has already answered, oldest first, enough
            // to leave room so the next turns don't trim again (each trim changes the history the server has cached).
            if let budget = config.context, estimator.tokens(messages, tools: definitions) > budget.compactThreshold,
               await !compact(minimumSaving: Compactor.minimumSaving(budget)),
               trimGate.allows(messages, tools: definitions, estimator, budget) {
                let trimmed = Compactor.trimForHeadroom(messages, budget: budget, estimator: estimator, tools: definitions)
                // Nothing trimmable yet (the outputs aren't answered): the history is unchanged, so the gate stays open.
                if trimmed != messages {
                    messages = trimmed
                    changesSinceKept.trimmed = true
                    trimGate.trimmed(messages, tools: definitions, estimator, budget)
                    seen.removeAll()            // earlier results may be gone now: reading again is legitimate
                }
            }
            await takeQueuedInput()
            await emit(.promptSize(tokens: estimator.tokens(messages, tools: definitions)))
            var (reply, earlier): (ChatMessage, [ChatMessage])
            // The user's queued message came in: it decides what's next, not a call kurtkode would write.
            if delegationDue, messages.last?.role == .user { delegationDue = false }
            if delegationDue, !canForce {
                delegationDue = false
                (reply, earlier) = (delegationCall(), [])
            } else {
                (reply, earlier) = await recoverDroppedCall(await turn(on: nil))
                if delegationDue, !Compactor.isOverflowError(reply), reply.meta?.stopReason != .failed { delegationDue = false }
            }
            for m in earlier { await emit(.assistant(m)) }
            // The server said the prompt is too long: compact once and try again.
            let retried = Set(earlier.flatMap { [$0.id] + ($0.meta?.retryRequests ?? []) } + (reply.meta?.retryRequests ?? []))
            if Compactor.isOverflowError(reply), !overflowRetried, config.context != nil {
                await flushCosts(retried: retried)
                overflowRetried = true
                if await compact(minimumSaving: 1) { continue }
                let trimmed = Compactor.trimAnswered(messages, maxToolBytes: 1200)
                if TokenEstimator.bytes(trimmed) < TokenEstimator.bytes(messages) { messages = trimmed; seen.removeAll(); continue }
                // Nothing answered was left to trim: the newest results alone don't fit. As a last resort they're cut too,
                // told why; `seen` stays, so the same read again is refused rather than overflowing again (a read in parts
                // is a different call).
                let cut = Compactor.trimKept(messages, maxToolBytes: 1200, hint: Compactor.oversizeHint)
                if TokenEstimator.bytes(cut) < TokenEstimator.bytes(messages) { messages = cut; continue }
            }
            // A reply that fit lets a later overflow in a long run be compacted again (was: once a run, then the run failed).
            if !Compactor.isOverflowError(reply) { overflowRetried = false }
            if let note = compactionNote, reply.meta != nil {          // a call kurtkode wrote has no meta: the next reply carries it
                reply = noted(reply, note)
                compactionNote = nil
            }
            if let prompt = reply.meta?.usage?.promptTokens {
                estimator.calibrate(bytes: TokenEstimator.bytes(messages, tools: definitions), promptTokens: prompt)
            }
            // An empty reply is a silent give-up, not an answer (seen: a grep found nothing, then the model ended its
            // turn with no text; gpt-oss wrote its call into the reasoning). Ask, up to 3 times in a row; the empty
            // turn itself isn't sent back. Decided here so the reply records the nudge.
            // A reply that is only a tool-call marker (Gemma 4 wrote `<tool_call|>` and stopped) is a broken call,
            // not an answer: it gets the same treatment.
            var nudge: String?
            let declined = reply.meta?.declined == true     // a refusal: asking again gets the same answer
            let paused = reply.meta?.paused == true         // the server paused the turn; it's sent back to continue
            if reply.meta?.stopReason ?? .completed == .completed, !Task.isCancelled, reply.toolCalls.isEmpty,
               reply.meta?.finishReason != .length, emptyNudges < 3, !declined, !paused {
                if let reason = Self.brokenCallReason(reply) {
                    // The server threw a call away (Gemini: MALFORMED_FUNCTION_CALL); the text before it isn't an answer.
                    nudge = Self.brokenCallNudge
                    reply = noted(reply, "The server dropped a tool call (\(reason)); the loop asked again: \"\(nudge!)\"")
                } else if reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nudge = emptyReplyNudge(reasoning: reply.reasoning, generatedTokens: reply.meta?.usage?.completionTokens ?? 0)
                    reply = noted(reply, "The reply was empty; the loop asked again: \"\(nudge!)\"")
                } else if Self.onlyToolCallMarkers(reply.content) {
                    nudge = Self.markerOnlyNudge
                    reply = noted(reply, "The reply was only a tool-call marker, with no call; the loop asked again: \"\(nudge!)\"")
                }
            }
            // A plan this run made and left unfinished: ask once whether it's really done (seen: Gemma 4 wrote "the next
            // step is to continue documenting the remaining files" with 5 of 14 left, and the run ended there). The reply
            // stays: it's an answer, just maybe an early one.
            var todoNudge: String?
            // In Plan mode nothing on the list can be done yet, so it isn't asked about.
            if nudge == nil, !todoNudged, !declined, !paused, policy.mode != .plan, reply.meta?.stopReason ?? .completed == .completed, !Task.isCancelled,
               reply.toolCalls.isEmpty, reply.meta?.finishReason != .length {
                todoNudge = Self.openTodosNudge(runMessages)
                if let todoNudge { reply = noted(reply, "The run's todo list still had open items; the loop asked once: \"\(todoNudge)\"") }
            }
            let stop = reply.meta?.stopReason ?? .completed
            // A reply stopped for repeating itself (a reasoning loop) gets one more try, told what happened, before the
            // run ends: the work so far is fine, only the reply went round in circles.
            let repeating = stop == .repetition && !repetitionNudged && reply.toolCalls.isEmpty
            // A reply the loop takes back is stored (it was paid for, and the notes say why) but never sent again.
            if nudge != nil || repeating { reply.meta?.unsent = true }
            await flushCosts(retried: retried, nudged: nudge == nil ? nil : reply.id)
            await emit(.assistant(reply))
            messages.append(reply)
            runMessages.append(reply)
            taskRuns.noteCalls(reply.toolCalls)

            if stop == .cancelled || Task.isCancelled { await emit(.finished(.cancelled)); return }
            if repeating {
                repetitionNudged = true
                messages.removeLast()
                await sendNudge("Your last reply was stopped because it kept repeating itself. Don't write it out "
                    + "again: take the next step now, with a tool call if it needs one.")
                continue
            }
            if stop != .completed { await emit(.finished(.turnStopped(stop))); return }
            if reply.toolCalls.isEmpty {
                if reply.meta?.finishReason == .length { await emit(.finished(.truncated)); return }
                // A paused turn (a long server-side search) is sent back as it is, and the server goes on with it.
                if paused, pausedContinues < 5 {
                    pausedContinues += 1
                    continue
                }
                if let text = nudge {
                    emptyNudges += 1
                    messages.removeLast()
                    await sendNudge(text)
                    continue
                }
                if let todoNudge {
                    todoNudged = true
                    await sendNudge(todoNudge)
                    continue
                }
                // Plan mode: a plan given as an answer instead of through present_plan (Gemma 4 wrote it out, as the
                // plan-work skill says) still goes to the user to approve, send back or reject (B1). Their decision comes
                // back as their message.
                if policy.mode == .plan, let present = config.presentPlan, planFallbacks < 3, !Task.isCancelled,
                   Self.planMayBeAnAnswer(runMessages),
                   Self.looksLikePlan(reply.content) {
                    planFallbacks += 1
                    let file = config.outputDirectory?.appending(path: "plan-\(reply.id.uuidString.prefix(8)).md")
                    let proposal = PlanProposal(plan: reply.content, file: file)
                    if let file {
                        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? Data((proposal.plan + "\n").utf8).write(to: file)
                    }
                    let decision = await present(proposal)
                    if Task.isCancelled { await emit(.finished(.cancelled)); return }
                    let text: String
                    switch decision {
                    case .approve(let mode):
                        let sandboxNote = await switchMode(to: mode)
                        text = "I approve this plan. You are now in \(mode.displayName) mode"
                            + (mode == .fullAuto ? " (actions run without asking)" : " (edits run without asking; commands are asked about)")
                            + ": carry it out now, step by step, and check the work as it says." + sandboxNote
                    case .revise(let feedback):
                        text = "Please revise the plan: \(feedback)\nThen present the revised plan with present_plan."
                    case .reject(let reason):
                        if let reason, !reason.isEmpty {
                            let m = ChatMessage.user("I don't want this plan carried out: \(reason)")
                            messages.append(m)
                            runMessages.append(m)
                            await emit(.injected(m))
                        }
                        await emit(.finished(.denied))
                        return
                    }
                    let m = ChatMessage.user(text)
                    messages.append(m)
                    runMessages.append(m)
                    await emit(.injected(m))
                    continue
                }
                // The user wrote more while this reply was being written: keep going with it.
                if await takeQueuedInput() { continue }
                // Not done while background subagents run: wait for the next report and go on with it.
                if background.running > 0 {
                    let n = background.running
                    await emit(.status("Waiting for \(n) background subagent\(n == 1 ? "" : "s") to report…"))
                    await background.waitForReport()
                    if Task.isCancelled { await emit(.finished(.cancelled)); return }
                    if await takeQueuedInput() { continue }
                }
                // A Stop hook can send the agent back to work, a few times in a row at most. The main agent's run only:
                // a subagent's end is SubagentStop's (a "block unless the tests pass" Stop hook would loop an explore run).
                if let hooks = config.hooks, stopHookContinues < 3, (config.costScope?.agent ?? "main") == "main" {
                    let outcome = await hooks.stop(active: stopHookContinues > 0)
                    for e in outcome.errors { await emit(.hookNotice(e)) }
                    if outcome.blocked {
                        stopHookContinues += 1
                        let m = ChatMessage.user("A Stop hook says the task isn't done: " + (outcome.reason ?? "keep going."))
                        messages.append(m)
                        runMessages.append(m)
                        await emit(.injected(m))
                        continue
                    }
                }
                // Each of this run's tasks with a check: run it again now, after everything the parent did, and record
                // the result as a grounded judgment (a failure is a hard failure, whatever any rating says).
                if let rec = config.subagents?.recorder, let workspace, !Task.isCancelled {
                    for e in taskRuns.recheckable {
                        guard let command = e.card?.verify, let run = e.run else { continue }
                        await emit(.status("Running the check of \"\(e.title.isEmpty ? e.agent : e.title)\" again: \(command)"))
                        let check = await Self.runCheck(command, tools: tools, config: runMode.applied(to: config), workspace: workspace,
                                                        callID: "recheck_" + e.callID, emit: emit)
                        let exit = check.flatMap { $0.ran ? Self.exitStatus($0.output) : nil }
                        taskRuns.setRecheck(e.callID, exit: exit)
                        var j = RunJudgment(run: run, taskCall: e.callID, judge: .recheck,
                                            note: check?.ran == true ? "Ran its check again at the end of the parent's run."
                                                : "Couldn't run its check again: " + String((check?.output.text ?? "no bash tool").prefix(300)),
                                            checks: .recheck(command: command, exitCode: exit))
                        if let out = check?.output, check?.ran == true { j.response = String(out.text.suffix(2000)) }
                        try? await rec.store.append(.judgment(j), toRun: run, of: rec.parent)
                        await emit(.judged(j))
                    }
                }
                // The subagent runs it used and didn't rate: asked once, aside from the conversation.
                if config.subagents?.recorder != nil, !Task.isCancelled, config.costMeter?.reached == nil,
                   case let unrated = taskRuns.unrated, !unrated.isEmpty {
                    await askForRatings(unrated)
                }
                await emit(.finished(.completed))
                return
            }
            emptyNudges = 0
            pausedContinues = 0

            var stopAfterCalls = false
            /// Subfolders' rule files this turn's calls touched, sent after the results (`NestedInstructions`).
            var turnRules: [String] = []
            var turnImages: [ImageAttachment] = []
            var turnRuleBytes = 0
            /// A plan was approved in this turn: the turn's later calls were written before it, in Plan mode.
            var modeSwitched = false
            // One turn's tool output shouldn't swamp the context: past this, further calls in the same turn
            // are refused with advice to work in smaller steps. (Seen: 14 parallel reads in one turn, more than
            // the whole budget, so compaction couldn't keep them and the model lost what it had read.)
            let turnBudget = config.context.map { Int(Double($0.limit) * 0.35 * estimator.bytesPerToken) }
                ?? config.maxToolOutputBytes * 8
            var turnBytes = 0
            var relays: [ProgressRelay] = []
            // Several subagent tasks in one reply run at once: each starts as soon as it's authorized and the other
            // calls go on; results still go back in call order (so everything is emitted after the last call). Their
            // share of the turn's output budget is set when they start.
            let parallelTasks = reply.toolCalls.filter { $0.name == "task" }.count > 1
            let warmup = parallelTasks ? CacheWarmup() : nil
            var tasksLeft = reply.toolCalls.filter { $0.name == "task" }.count
            // Several reads in one reply, and nothing else, run at once (frontier models often ask for six files in one
            // reply). Only when every call is a plain read (a read next to an edit must see the file before or after it,
            // in call order), and only when all of them fit the turn's budget in full: in a small context the first
            // reads run whole and the rest are refused with "work in smaller steps", as before, rather than every read
            // coming back cut to a sliver.
            let parallelReads = !parallelTasks && reply.toolCalls.count > 1
                && reply.toolCalls.allSatisfy { Self.concurrentReads.contains($0.name) }
                && reply.toolCalls.count * config.maxToolOutputBytes <= turnBudget
            let parallel = parallelTasks || parallelReads
            var readsLeft = parallelReads ? reply.toolCalls.count : 0
            // A reply cut off at the output limit while writing a call: that call's arguments are incomplete JSON.
            // Running it would fail as "not valid JSON", and the model, not told why, sends the same oversized call
            // again. It's refused with the size problem named instead; calls before it, which are complete, run.
            let cutOff = reply.meta?.finishReason == .length
            var refusedCut = false
            struct Started {
                var call: ToolCall
                var work: Task<ToolOutput, Never>
                var start: Date
                var key: String
                var approval: ApprovalRecord?
                var problems: [String]
                var relay: ProgressRelay
            }
            enum Slot { case done(ChatMessage, ProgressRelay?), running(Started) }
            var slots: [Slot] = []
            for call in reply.toolCalls {
                if Task.isCancelled {
                    for case .running(let r) in slots { r.work.cancel() }
                    await emit(.finished(.cancelled)); return
                }
                var start = Date()
                var output: ToolOutput
                var denied = false
                var approval: ApprovalRecord?
                var notes: [String] = []
                let problems = tools[call.name].map { ArgumentCheck.problems(call.arguments, schema: $0.parameters) }
                    ?? ["there is no tool named \"\(call.name)\""]

                if stopAfterCalls {
                    output = .error("not run: the user denied an earlier action in this turn.")
                    notes.append("Not run: an earlier call in this turn was denied.")
                } else if modeSwitched {
                    output = .error("not run: this call was written before the user approved the plan. Make it again now if "
                        + "the plan still needs it.")
                    notes.append("Not run: written in the same reply as the plan, before it was approved.")
                } else if cutOff, (try? ToolArguments(json: call.arguments)) == nil {
                    refusedCut = true
                    output = .error(Self.cutCallMessage(outputTokens: reply.meta?.usage?.completionTokens))
                    notes.append("Not run: the reply reached its output limit while writing this call, so its arguments were cut off.")
                } else if turnBudget - turnBytes < Self.minimumCallOutput {
                    // Less left than the least a call is given (a read stops at a line boundary just under its share,
                    // so "at or over the budget" alone let one more call through with a sliver).
                    notes.append("Not run: this turn's tool output had used its budget (\(turnBudget / 1000) KB).")
                    output = .error("not run: this turn already returned about \(turnBytes / 1000) KB of tool output, "
                        + "as much as fits in the context. Work in smaller steps: act on what you have (for example, "
                        + "write down what you learned), then make this call again.")
                } else if let tool = tools[call.name], let refusal = policy.modeRefusal(tool) {
                    output = .error(refusal)
                    notes.append(policy.mode == .plan ? "Not run: plan mode." : "Not run: present_plan outside plan mode.")
                } else if let workspace, tools[call.name]?.risk == .write,
                          let rules = nested?.take(for: call, workspace: workspace, room: NestedInstructions.maxTurnBytes - turnRuleBytes) {
                    // A change in a folder whose rules the model hasn't seen waits until it has (they come next).
                    turnRules.append(rules.text)
                    turnRuleBytes += rules.text.utf8.count
                    output = .error("not run: " + rules.files.joined(separator: " and ") + (rules.files.count == 1 ? " has" : " have")
                        + " rules for the files you're changing, which you hadn't seen; they're in the next message. Make the "
                        + "call again following them.")
                    notes.append("Not run: held until the model has seen " + rules.files.joined(separator: ", ") + ".")
                } else if let tool = tools[call.name], let workspace, let shell {
                    let callID = call.id
                    let relay = ProgressRelay { text in await emit(.toolProgress(callID: callID, text: text)) }
                    relays.append(relay)
                    let share = parallelTasks && call.name == "task" ? max(1, tasksLeft) : parallelReads ? max(1, readsLeft) : 1
                    if call.name == "task" { tasksLeft -= 1 }
                    if parallelReads { readsLeft -= 1 }
                    var context = ToolContext(workspace: workspace,
                                              maxOutputBytes: max(Self.minimumCallOutput, min(config.maxToolOutputBytes, (turnBudget - turnBytes) / share)),
                                              shell: shell, progress: { relay.add($0) })
                    context.fullOutputURL = config.outputDirectory?.appending(path: "\(call.id)-\(UUID().uuidString.prefix(6)).txt")
                    context.sandbox = sandbox
                    context.callID = call.id
                    context.askUser = config.askUser
                    context.reads = config.reads
                    context.presentPlan = config.presentPlan
                    context.memoryHome = config.memoryHome
                    context.imagesDirectory = config.imagesDirectory
                    context.acceptsImages = config.sendImages
                    context.cacheWarmup = warmup
                    // Plan mode's read-only commands run where they can't write (B1), whatever the mode's sandbox.
                    if policy.mode == .plan {
                        context.sandbox = Self.planSandbox(workspace, sandbox)
                        // Plan mode's commands run without the variables earlier commands exported (they could
                        // point git or rg at programs), and what they export isn't kept.
                        context.cleanShell = true
                    }
                    let key = call.name + "\u{0}" + normalizedArguments(call.arguments)
                    // Asking the user and loading a skill are reads that may rightly repeat (a new answer; a skill's
                    // instructions after a compaction).
                    let cached = tool.risk == .read && !Self.uncachedReads.contains(call.name)
                    if cached, seen.contains(key) {
                        output = ToolOutput(text: "You already called \(call.name) with these arguments; the result is "
                            + "above in the conversation. Use it, or call a different tool or arguments.", isError: true)
                        notes.append("Not run: the same read as an earlier call (the model was told to use that result).")
                    } else {
                        // Repeats count the same call that changes something made again and again with nothing else
                        // in between (a read between two test runs makes them separate attempts).
                        if tool.risk != .read {
                            actionRepeats = key == lastAction ? actionRepeats + 1 : 1
                            lastAction = key
                        } else {
                            lastAction = nil
                            actionRepeats = 0
                        }
                        runMode.syncRules(into: &policy)          // rules a subagent's card added since
                        let (authorization, record) = await authorize(call, tool: tool, context: context, policy: &policy,
                                                                      config: config, repeats: tool.risk == .read ? 0 : actionRepeats,
                                                                      emit: emit)
                        approval = record
                        switch authorization {
                        case .run where (parallelTasks && call.name == "task") || parallelReads:
                            await emit(.toolStarted(call))
                            let work = Task { await perform(call, tool: tool, context: context, config: config) }
                            slots.append(.running(Started(call: call, work: work, start: Date(), key: key, approval: record,
                                                          problems: problems, relay: relay)))
                            relays.removeAll { $0 === relay }
                            continue
                        case .run:
                            start = Date()          // time the tool, not the approval wait
                            await emit(.toolStarted(call))
                            output = await perform(call, tool: tool, context: context, config: config)
                            if let mode = output.newMode, mode != policy.mode {
                                output.text += await switchMode(to: mode)
                                modeSwitched = true
                                notes.append("The user approved the plan: the mode is now \(mode.displayName).")
                            }
                            if output.endsRun { stopAfterCalls = true }
                            if tool.risk == .read { if !output.isError, cached { seen.insert(key) } } else { seen.removeAll() }
                            if Self.invalidatesReads.contains(call.name) { seen.removeAll() }
                            if let hooks = config.hooks {
                                let post = await hooks.postToolUse(call, output: output)
                                for e in post.errors { await emit(.hookNotice(e)) }
                                let feedback = [post.blocked ? post.reason : nil].compactMap { $0 } + post.context
                                if !feedback.isEmpty {
                                    output.text += "\n\n[Hook feedback: " + feedback.joined(separator: "\n") + "]"
                                    notes.append("A PostToolUse hook added: " + feedback.joined(separator: " / "))
                                }
                            }
                        case .result(let o):
                            output = o
                        case .denied(let o, let stopRun):
                            output = o
                            denied = true
                            stopAfterCalls = stopRun
                        }
                    }
                } else {
                    output = await execute(call, tools: tools, config: config, workspace: workspace)
                }

                if let note = delegationNote(call, output) {
                    output.text += "\n\n" + note
                    notes.append("Suggested the explore subagent after \(readStreak) reads in a row.")
                }
                if !output.isError, let workspace,
                   let rules = nested?.take(for: call, workspace: workspace, room: NestedInstructions.maxTurnBytes - turnRuleBytes) {
                    turnRules.append(rules.text)
                    turnRuleBytes += rules.text.utf8.count
                    notes.append("The rules of " + rules.files.joined(separator: ", ") + " were sent after this turn's results.")
                }
                turnImages += output.images
                let result = resultMessage(call, output, start: start, denied: denied, approval: approval,
                                           problems: problems, notes: notes)
                turnBytes += result.content.utf8.count
                if parallel {
                    slots.append(.done(result, relays.last))
                    relays.removeAll()
                    continue
                }
                messages.append(result)
                runMessages.append(result)
                for r in relays { await r.flush() }        // the last live output before the result
                relays.removeAll()
                await emit(.toolFinished(result))
            }
            if parallel {
                // A denial stops the rest of the turn, the subagents still running included.
                if stopAfterCalls { for case .running(let r) in slots { r.work.cancel() } }
                let works = slots.compactMap { if case .running(let r) = $0 { r.work } else { nil } }
                for slot in slots {
                    var result: ChatMessage
                    var relay: ProgressRelay?
                    switch slot {
                    case .done(let m, let r):
                        result = m
                        relay = r
                    case .running(let r):
                        var output = await withTaskCancellationHandler { await r.work.value } onCancel: {
                            for w in works { w.cancel() }
                        }
                        var notes: [String] = []
                        if r.call.name == "task" {
                            seen.removeAll()            // the subagent may have changed files the main agent read
                        } else {
                            if !output.isError { seen.insert(r.key) }
                            if let note = delegationNote(r.call, output) {
                                output.text += "\n\n" + note
                                notes.append("Suggested the explore subagent after \(readStreak) reads in a row.")
                            }
                            if !output.isError, let workspace,
                               let rules = nested?.take(for: r.call, workspace: workspace, room: NestedInstructions.maxTurnBytes - turnRuleBytes) {
                                turnRules.append(rules.text)
                                turnRuleBytes += rules.text.utf8.count
                                notes.append("The rules of " + rules.files.joined(separator: ", ") + " were sent after this turn's results.")
                            }
                        }
                        if let hooks = config.hooks {
                            let post = await hooks.postToolUse(r.call, output: output)
                            for e in post.errors { await emit(.hookNotice(e)) }
                            let feedback = [post.blocked ? post.reason : nil].compactMap { $0 } + post.context
                            if !feedback.isEmpty {
                                output.text += "\n\n[Hook feedback: " + feedback.joined(separator: "\n") + "]"
                                notes.append("A PostToolUse hook added: " + feedback.joined(separator: " / "))
                            }
                        }
                        notes.append(r.call.name == "task" ? "Ran in parallel with the turn's other subagent tasks."
                                                           : "Ran at the same time as the turn's other reads.")
                        turnImages += output.images
                        result = resultMessage(r.call, output, start: r.start, denied: false, approval: r.approval,
                                               problems: r.problems, notes: notes)
                        relay = r.relay
                    }
                    messages.append(result)
                    runMessages.append(result)
                    await relay?.flush()
                    await emit(.toolFinished(result))
                }
                if Task.isCancelled { await emit(.finished(.cancelled)); return }
            }
            // Stop while an approval was pending answers it "deny"; that's a stop, not a denial.
            if !turnRules.isEmpty {
                let m = ChatMessage.user(turnRules.joined(separator: "\n\n"))
                messages.append(m)
                runMessages.append(m)
                await emit(.injected(m))
            }
            // Images follow the results: not every API can carry one in a tool result.
            if !turnImages.isEmpty {
                var m = FrozenSystemPrompt.noteMessage("[The image\(turnImages.count == 1 ? "" : "s") the tool read.]")
                m.images = turnImages
                turnImages = []
                messages.append(m)
                runMessages.append(m)
                await emit(.injected(m))
            }
            if stopAfterCalls { await emit(.finished(Task.isCancelled ? .cancelled : .denied)); return }
            // Three replies in a row cut off mid-call: smaller calls aren't coming, so stop as a cut-off reply does.
            cutReplies = refusedCut ? cutReplies + 1 : 0
            if cutReplies >= 3 { await emit(.finished(.truncated)); return }
        }
        await emit(.finished(.stepLimit))
    }

    enum Authorization {
        case run
        /// Answer without running (e.g. the preview found the call can't succeed).
        case result(ToolOutput)
        case denied(ToolOutput, stopRun: Bool)
    }

    /// Decides whether a call may run: by policy, or by asking the user with a preview. Also says who decided.
    /// `repeats`: how many times in a row the model has made this same call (for calls that change things).
    static func authorize(_ call: ToolCall, tool: any Tool, context: ToolContext, policy: inout PermissionPolicy,
                          config: AgentConfig, repeats: Int = 0,
                          emit: @Sendable (AgentEvent) async -> Void) async -> (Authorization, ApprovalRecord?) {
        let args: ToolArguments
        do { args = try ToolArguments(json: call.arguments) } catch let f as ToolFailure { return (.result(.error(f.message)), nil) }
        catch { return (.result(.error(error.localizedDescription)), nil) }

        // PreToolUse hooks decide first: deny blocks, allow skips the approval, ask forces one (even in Full Auto).
        // Deny rules and the danger check still apply after a hook's allow.
        var mustAsk = false
        var hookAllowed: String??
        var askReason: String?
        if let hooks = config.hooks {
            let pre = await hooks.preToolUse(call)
            for e in pre.errors { await emit(.hookNotice(e)) }
            switch pre.permission {
            case .deny?:
                let why = pre.reason ?? "no reason given"
                await emit(.hookNotice("A PreToolUse hook blocked \(call.name): \(why)"))
                return (.result(ToolOutput(text: "A hook blocked this \(call.name) call: \(why)", isError: true)),
                        ApprovalRecord(decider: .hook, allowed: false, detail: why))
            case .allow?:
                if policy.mode != .plan { hookAllowed = .some(pre.reason) }
            case .ask?:
                mustAsk = true
                askReason = "a PreToolUse hook asks" + (pre.reason.map { ": \($0)" } ?? "")
            case nil:
                break
            }
        }
        // Rules from settings files: deny wins over ask over allow, in every mode.
        let rule = config.permissionRules.decision(toolName: call.name, args: args)
        switch rule?.action {
        case .deny?:
            let r = rule!
            return (.result(ToolOutput(text: "A permission rule denies this \(call.name) call: \(r.text) (\(r.source)). Do something "
                                       + "else, or ask the user.", isError: true)),
                    ApprovalRecord(decider: .rule, allowed: false, detail: "\(r.text) (\(r.source))"))
        case .ask?:
            mustAsk = true
            askReason = "a permission rule asks: \(rule!.text) (\(rule!.source))"
        default:
            break
        }
        // Destructive commands are asked about in every mode, unless the user's own rule names them: each command in
        // the line is checked, and a rule lets through only the commands it matches and names the dangers of.
        let roots = [context.workspace.root.path] + context.workspace.folders.map(\.path)
        var danger: String?
        if config.guardDangerous, call.name == "bash", let command = args.string("command") {
            let rules = config.permissionRules
            danger = DangerousCommands.reason(command, roots: roots) { rules.allowsDanger($0, reasons: $1, roots: roots) }
        }
        // A web fetch leaves the machine: with the sandbox's network off, Full Auto mustn't make it a way around that.
        if call.name == WebFetchTool.toolName, context.sandbox?.allowNetwork == false, rule?.action != .allow, !policy.allowsDomain(tool, args) {
            mustAsk = true
            askReason = askReason ?? "the sandbox's network is off, and this fetch would go around it"
        }
        if let danger {
            mustAsk = true
            askReason = "this command \(danger)"
        }
        if repeats >= 3 {
            mustAsk = true
            askReason = "the model has made this same call \(repeats) times in a row"
        }
        // Plan mode runs read-only commands unasked, unless files are kept from the model that a command could still
        // read: Read deny rules (bash isn't covered by them), or withheld files with no sandbox to block them.
        let planCommand = policy.mode == .plan && call.name == "bash" && PermissionPolicy.readOnly(args.string("command") ?? "")
        if planCommand, context.workspace.readDenied != nil
            || (context.workspace.withheld != nil && (context.sandbox?.unreadable.isEmpty ?? true)) {
            mustAsk = true
            askReason = askReason ?? "permission rules or Privacy settings keep some files from the model, and a command could read them"
        }
        if !mustAsk, let hookAllowed {
            return (.run, ApprovalRecord(decider: .hook, allowed: true, detail: hookAllowed))
        }
        if !mustAsk, let rule, rule.action == .allow, policy.mode != .plan || tool.risk == .read {
            return (.run, ApprovalRecord(decider: .rule, allowed: true, detail: "\(rule.text) (\(rule.source))"))
        }
        if !mustAsk, policy.isAllowedWithoutAsking(tool, args) {
            var withoutRules = policy
            withoutRules.rules = []
            if withoutRules.isAllowedWithoutAsking(tool, args) { return (.run, ApprovalRecord(decider: .mode, allowed: true)) }
            let rule = policy.rules.first { policy.matches($0, tool: tool, args: args) }
            return (.run, ApprovalRecord(decider: .rule, allowed: true, detail: rule?.displayName))
        }
        if policy.mode == .plan, call.name == "bash", !(planCommand && mustAsk) {
            return (.result(.error("plan mode runs only commands that read (git log, diff, show, blame, status; ls, cat, "
                + "head, grep, rg, find, wc, sed -n; --version), with no output to files. Put running this in the plan instead"
                + (config.presentPlan != nil ? ", and present the plan with present_plan when it's ready." : "."))),
                    ApprovalRecord(decider: .refused, allowed: false, detail: "plan mode: not read-only"))
        }
        if policy.mode == .plan, !(planCommand && mustAsk) {
            return (.result(.error("\(call.name) isn't available in plan mode (read-only). Describe the change instead.")),
                    ApprovalRecord(decider: .refused, allowed: false, detail: "plan mode"))
        }
        // Preview first: a call that would fail anyway goes straight back to the model.
        let preview: ToolPreview?
        do { preview = try await tool.preview(args, context: context) }
        catch let f as ToolFailure {
            return (.result(.error(f.message)), ApprovalRecord(decider: .refused, allowed: false, detail: "the preview failed: \(f.message)"))
        }
        catch { return (.result(.error(error.localizedDescription)), nil) }

        let fetchAddress = call.name == WebFetchTool.toolName ? args.string("url") : nil
        if let fetchAddress, (args.int("start") ?? 0) > 0, repeats < 3, policy.fetched.contains(fetchAddress) {
            return (.run, ApprovalRecord(decider: .user, allowed: true, detail: "the next part of a page already allowed"))
        }
        guard let approve = config.approve else {
            return (.denied(.error("this action needs the user's approval, and none is available."), stopRun: true),
                    ApprovalRecord(decider: .refused, allowed: false, detail: "no one to ask"))
        }
        if let hooks = config.hooks {
            let summary = tool.summary(args)
            Task { _ = await hooks.notification("kurtkode needs your approval: " + summary) }
        }
        // No "always allow" for a dangerous command or a repeat: each one is asked about.
        let request = ApprovalRequest(call: call, summary: tool.summary(args), risk: tool.risk, preview: preview,
                                      suggestedRule: danger == nil && repeats < 3 ? PermissionPolicy.suggestedRule(tool, args) : nil,
                                      reason: askReason)
        let asked = Date()
        let answer = await approve(request)
        let waited = Date().timeIntervalSince(asked)
        switch answer {
        case .allow:
            if let fetchAddress { policy.fetched.insert(fetchAddress) }
            return (.run, ApprovalRecord(decider: .user, allowed: true, waited: waited))
        case .allowAlways(let rule):
            policy.rules.append(rule)
            await emit(.ruleAdded(rule))
            return (.run, ApprovalRecord(decider: .user, allowed: true, waited: waited, detail: "always allow \(rule.displayName)"))
        case .deny(let feedback):
            if let feedback, !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (.denied(ToolOutput(text: "The user denied this \(call.name) call and said: \(feedback)", isError: true),
                                stopRun: false),
                        ApprovalRecord(decider: .user, allowed: false, waited: waited, detail: feedback))
            }
            return (.denied(ToolOutput(text: "The user denied this \(call.name) call. Stop and wait for their instructions.",
                                       isError: true), stopRun: true),
                    ApprovalRecord(decider: .user, allowed: false, waited: waited))
        case .refuse(let message, let why):
            return (.denied(ToolOutput(text: "Not run: \(message)", isError: true), stopRun: false),
                    ApprovalRecord(decider: .refused, allowed: false, detail: why))
        }
    }

    /// Runs an authorized call, snapshotting the files a write will change.
    static func perform(_ call: ToolCall, tool: any Tool, context: ToolContext, config: AgentConfig) async -> ToolOutput {
        do {
            let args = try ToolArguments(json: call.arguments)
            if tool.risk == .write, let checkpoint = config.checkpoint {
                try await checkpoint(try tool.affectedFiles(args, context: context))
            }
            return try await tool.run(args, context: context)
        } catch let f as ToolFailure {
            return .error(f.message)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Runs a call with no policy or approval; for unknown tools and tests.
    /// A call's result message, with what the loop knows about how it ran.
    static func resultMessage(_ call: ToolCall, _ output: ToolOutput, start: Date, denied: Bool, approval: ApprovalRecord?,
                              problems: [String], notes: [String]) -> ChatMessage {
        var info = ToolResultInfo(toolName: call.name, isError: output.isError, truncated: output.truncated,
                                  duration: Date().timeIntervalSince(start), display: output.display,
                                  denied: denied ? true : nil, exitCode: output.exitCode,
                                  fullOutputPath: output.fullOutputPath)
        info.approval = approval
        info.subagentRun = output.subagentRun
        info.argumentProblems = problems.isEmpty ? nil : problems
        info.notes = notes.isEmpty ? nil : notes
        return ChatMessage(role: .tool, content: output.text, toolCallID: call.id, toolResult: info)
    }

    static func execute(_ call: ToolCall, tools: [String: any Tool], config: AgentConfig, workspace: Workspace?) async -> ToolOutput {
        guard let tool = tools[call.name] else {
            return .error("unknown tool \"\(call.name)\". Available tools: \(tools.keys.sorted().joined(separator: ", ")).")
        }
        guard let workspace else { return .error("no project folder is open, so tools are unavailable.") }
        var context = ToolContext(workspace: workspace, maxOutputBytes: config.maxToolOutputBytes, shell: config.shell)
        context.sandbox = config.sandbox
        context.callID = call.id
        context.reads = config.reads
        return await perform(call, tool: tool, context: context, config: config)
    }

    /// The arguments of a rating, checked (`RateTaskTool.parse`).
    typealias Rating = (task: String, verdict: Int, checked: String, issues: [String], note: String?)

    /// The rating request's side loop: `messages` (the conversation as the model last saw it) plus `ask`, sent
    /// with the same tools so the server's cache covers the prefix; read-only calls run (up to 4 requests) so the model
    /// can look before it rates, and each rate_task call goes to `rate` with the request that made it (its id, the
    /// ask, the reply). Nothing here becomes part of the conversation. The eval's judge calibration runs it too.
    /// Returns how it ended when it stopped without the ratings it wanted (nil when they all came), and the last reply.
    @discardableResult
    static func ratingSideLoop(client: ChatClient, model: String, messages: [ChatMessage], ask: String,
                               tools: [String: any Tool], definitions: [ToolDefinition], config: AgentConfig,
                               workspace: Workspace?, provider: ProviderRouting?, costs: CostSink,
                               verify: Set<String> = [], emit: @escaping @Sendable (AgentEvent) async -> Void = { _ in },
                               done: @Sendable () -> Bool, looked: @Sendable ([ToolCall]) -> Void,
                               rate: @Sendable (Rating, (id: UUID, prompt: String, response: String)) async -> ToolOutput) async
        -> (why: String, last: String)? {
        let shape = config.historyShape
        var side = messages + [.user(ask)]
        var last = ""
        let lookers = tools.filter { $0.value.risk == .read && !["task", "ask_user", "skill", "rate_task"].contains($0.key) }
        for round in 0..<4 {
            guard !Task.isCancelled, config.costMeter?.reached == nil, !done() else {
                return done() ? nil : ("stopped (cancelled or over the spending limit)", last)
            }
            // The last request: time to decide. (Seen: gemma-4-26b kept reading through all four and never rated, in
            // 110 of 300 calibration runs.)
            if round == 3 { side.append(.user("That's enough checking: call rate_task now, once for each task, with what you have.")) }
            var request = ChatRequest(model: model, messages: HistoryShaper.shape(side, for: shape), tools: definitions,
                                      maxTokens: min(config.limits.maxTokens, client.api == .openai ? 4_096 : 16_000),
                                      temperature: config.temperature, sendReasoning: shape.sendReasoning, sendImages: config.sendImages)
            request.cacheForAnHour = config.promptCacheHour
            request.cacheKey = config.cacheKey
            request.provider = provider
            let tap = config.wireLog == nil ? nil : WireTap()
            let started = Date()
            var reply = await TurnRunner.run(client: client, request: request, limits: config.limits, tap: tap) { _ in }
            // (Not inside `costMeter?.add(…)`: optional chaining would skip recording when there's no meter.)
            let entry = await costs.record(reply, purpose: .rating, client: client, start: started)
            config.costMeter?.add(entry)
            if let log = config.wireLog, let tap {
                await log.write(tap.record(replyID: reply.id, startedAt: started, duration: Date().timeIntervalSince(started)))
            }
            if reply.toolCalls.isEmpty, !reply.content.isEmpty,
               let found = TextToolCalls.extract(from: reply.content, knownTools: Set(tools.keys),
                                                 parameterSchemas: tools.mapValues(\.parameters)) {
                reply.toolCalls = found.calls.enumerated().map { i, c in
                    ToolCall(id: "text_\(reply.id.uuidString.prefix(8))_\(i)", name: c.name, arguments: c.arguments)
                }
            }
            last = reply.content + reply.toolCalls.map { "\n[\($0.name) \($0.arguments)]" }.joined()
            if let stop = reply.meta?.stopReason, stop != .completed {
                return ("the request ended early (\(stop))" + (reply.meta?.error.map { ": " + String($0.prefix(300)) } ?? ""), last)
            }
            guard !reply.toolCalls.isEmpty else {
                return (reply.meta?.finishReason == .length ? "the reply hit its output limit" : "a reply without a tool call", last)
            }
            let response = reply.content + reply.toolCalls.map { "\n[\($0.name) \($0.arguments)]" }.joined()
            side.append(reply)
            for c in reply.toolCalls {
                let out: ToolOutput
                if c.name == "rate_task" {
                    if let args = try? ToolArguments(json: c.arguments), let r = try? RateTaskTool.parse(args) {
                        out = await rate(r, (reply.id, ask, response))
                    } else {
                        out = .error("rate_task needs task, verdict (0 to 3) and checked.")
                    }
                } else if lookers[c.name] != nil {
                    out = await execute(c, tools: lookers, config: config, workspace: workspace)
                    looked([c])                     // evidence for the rating: only calls that ran
                } else if c.name == "bash", let workspace,
                          let command = (try? ToolArguments(json: c.arguments))?.string("command")?
                            .trimmingCharacters(in: .whitespacesAndNewlines), verify.contains(command),
                          let check = await runCheck(command, tools: tools, config: config, workspace: workspace, callID: c.id, emit: emit) {
                    // A task's own check, exactly as its card gives it, so the rating can rest on running it.
                    out = check.output
                    if check.ran { looked([c]) }
                } else if c.name == "bash" {
                    out = .error("only a task's check command, exactly as given, can run now"
                                 + (verify.isEmpty ? " (these tasks have none)." : ": " + verify.sorted().joined(separator: ", ") + "."))
                } else {
                    out = .error("only reading, a task's check command, and rate_task are possible now.")
                }
                side.append(ChatMessage(role: .tool, content: out.text, toolCallID: c.id))
            }
        }
        return done() ? nil : ("4 requests without a rating", last)
    }

    /// Runs a task's check command as bash, authorized like any command (hooks, rules, the danger check, the mode,
    /// the user's approval). `ran`: it ran (the output is its result); else the output says why not. Nil without bash.
    /// `fromRoot`: in a copy of the session's shell at the project's root, for a command named from there (the
    /// project's tests): a model's `cd` doesn't move it, and its own `cd` or exports don't carry over to the session.
    /// `timeout`: seconds, as the bash tool's own argument (its default and its cap apply).
    public static func runCheck(_ command: String, tools: [String: any Tool], config: AgentConfig, workspace: Workspace,
                                callID: String, fromRoot: Bool = false, timeout: Int? = nil,
                                emit: @escaping @Sendable (AgentEvent) async -> Void = { _ in }) async
        -> (ran: Bool, output: ToolOutput)? {
        guard let bash = tools["bash"] else { return nil }
        var fields: [String: JSONValue] = ["command": .string(command)]
        if let timeout { fields["timeout"] = .number(Double(timeout)) }
        let arguments = String(decoding: (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data(), as: UTF8.self)
        let call = ToolCall(id: callID, name: "bash", arguments: arguments)
        let shell = fromRoot
            ? config.shell.map { ShellState(cwd: workspace.root, exported: $0.exported, unset: $0.unset, sandboxed: $0.sandboxed) }
            : config.shell
        var context = ToolContext(workspace: workspace, maxOutputBytes: config.maxToolOutputBytes, shell: shell)
        context.sandbox = config.sandbox
        context.callID = callID
        context.reads = config.reads
        var policy = config.policy
        switch await authorize(call, tool: bash, context: context, policy: &policy, config: config, emit: emit).0 {
        case .run: return (true, await perform(call, tool: bash, context: context, config: config))
        case .result(let o), .denied(let o, _): return (false, o)
        }
    }

    /// A check's exit status from its output: the command's own, or 1 for an error without one.
    public static func exitStatus(_ output: ToolOutput) -> Int32 { output.exitCode ?? (output.isError ? 1 : 0) }

    /// The least output a call is given, however little of the turn's budget is left.
    static let minimumCallOutput = 2000

    /// Reads that may run at the same time when a reply makes several of them and nothing else.
    static let concurrentReads: Set<String> = ["read_file", "list_dir", "glob", "grep"]

    /// What the model is told about a call cut off at the output limit. The advice is the dropped-call nudge's: a size
    /// it can act on beats "don't do that again".
    static func cutCallMessage(outputTokens: Int?) -> String {
        let limit = outputTokens.map { " (\($0) tokens)" } ?? ""
        return "not run: your reply reached its output limit\(limit) while you were writing this call, so its arguments "
            + "were cut off and nothing ran. Make smaller calls: to write a long file, write_file the first part and add "
            + "the rest with write_file and append: true, a few dozen lines per call; to change a file, edit a short "
            + "unique snippet at a time."
    }

    /// The calls that count as broad reading for the advice to delegate.
    static let broadReads: Set<String> = ["read_file", "grep", "glob", "list_dir"]

    /// Reads that aren't answered from the duplicate-read check.
    static let uncachedReads: Set<String> = ["ask_user", "skill", "task", "bash_output", "kill_shell", "present_plan"]

    /// The sandbox for Plan mode's commands: the mode's own (network, extra folders) or a default one, with the project
    /// and every extra folder read-only; only temp directories are writable.
    static func planSandbox(_ workspace: Workspace, _ base: SandboxPolicy?) -> SandboxPolicy? {
        guard SandboxPolicy.isAvailable else { return base }
        var s = base ?? SandboxPolicy()
        s.extraWritable = []
        s.readOnly = [workspace.root.path] + workspace.folders.map(\.path)
        // On a remote model the files withheld from it can't be read by a command either.
        s.unreadable = workspace.withheld?.patterns ?? []
        return s
    }
    /// Calls after which earlier reads may be out of date: a subagent may have changed files, and so may the user
    /// while answering a question.
    static let invalidatesReads: Set<String> = ["task", "ask_user"]

    static let emptyReplyNudge = "Your last reply was empty. Continue the task (try a different approach if a "
        + "search found nothing), or give your answer."

    /// Says what most likely happened. Reasoning that ends in a JSON object was meant as a tool call. Output
    /// tokens with nothing delivered mean the server couldn't parse the call and dropped it (seen on
    /// OpenRouter with Qwen3-Coder writing FILES.md: 25-72 tokens each time, then the same call again).
    static func emptyReplyNudge(reasoning: String?, generatedTokens: Int = 0) -> String {
        let tail = (reasoning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.hasSuffix("}"), tail.contains("{") {
            return "Your last reply was empty: the tool call at the end of your reasoning was not made. "
                + "Call the tool with the tool-calling interface, or give your answer."
        }
        let reasoningTokens = (reasoning ?? "").utf8.count / 4
        let lost = generatedTokens - reasoningTokens
        if lost > 10 {
            // The model can't see the lost call, so "don't repeat it" alone got the same call back every time
            // (measured through a fault-injecting proxy). A size to stay under is something it can act on.
            let budget = max(200, lost * 4 / 2)
            return "Your last reply arrived empty, although you generated about \(generatedTokens) tokens: the server "
                + "could not read your tool call and dropped it, and it will likely drop the same call again. Make a "
                + "smaller call: keep its arguments under about \(budget) characters. To write a file, use write_file "
                + "with append: true and add a few lines per call; to change a file, edit a short unique snippet."
        }
        return emptyReplyNudge
    }

    /// Whether an answer reads as a plan: a heading or line naming a plan or steps, or three or more list items, in a
    /// text of some length. (A short answer to a question asked in Plan mode isn't one.)
    static func looksLikePlan(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 80 else { return false }
        let lines = t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let items = lines.filter { $0.range(of: #"^([-*+]\s|\d+[.)]\s|- \[[ x]\])"#, options: .regularExpression) != nil }.count
        // A heading that names it, and steps under it. A list alone is an ordinary answer ("which files use X?").
        let named = lines.contains { l in
            (l.hasPrefix("#") || l.hasPrefix("**")) && l.range(of: #"\b(plan|steps|approach)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return named && items >= 2
    }

    /// A plan written as an answer may be presented: none was presented with present_plan in this run, or the latest
    /// was sent back for changes (the revision then came as text).
    static func planMayBeAnAnswer(_ runMessages: [ChatMessage]) -> Bool {
        let presented = Set(runMessages.flatMap(\.toolCalls).filter { $0.name == "present_plan" }.map(\.id))
        guard let last = runMessages.last(where: { $0.role == .tool && presented.contains($0.toolCallID ?? "") }) else { return true }
        return last.content.hasPrefix("The user wants changes")
    }

    /// The nudge for a run that wrote a todo list and stopped with items still open; nil when there's none.
    /// Only lists written in this run count (an old list shouldn't hold up an unrelated question).
    static func openTodosNudge(_ runMessages: [ChatMessage]) -> String? {
        var facts = SessionFacts()
        facts.absorb(runMessages)
        let open = facts.todos.filter { $0.status != TodoWriteTool.Item.Status.completed.rawValue }
        guard let first = open.first else { return nil }
        let count = open.count == 1 ? "1 open item" : "\(open.count) open items"
        return "Your todo list still has \(count) (next: \"\(first.content.prefix(80))\"). If there's more to do, "
            + "continue with it now. If you're stopping, update the list and say why the rest is left."
    }

    /// Finish reasons that mean the model tried to call a tool and the server dropped the call.
    static let brokenCallReasons = ["MALFORMED_FUNCTION_CALL", "UNEXPECTED_TOOL_CALL", "TOO_MANY_TOOL_CALLS"]

    /// Why the server dropped the reply's tool call, or nil.
    static func brokenCallReason(_ reply: ChatMessage) -> String? {
        guard reply.meta?.finishReason == .other else { return nil }
        let notes = reply.meta?.notes ?? []
        return brokenCallReasons.first { r in notes.contains { $0.contains(r) } }
    }

    static let brokenCallNudge = "Your last tool call was malformed, so the server dropped it and nothing ran. Make the "
        + "call again with valid arguments (one call at a time if there were several), or give your answer."

    static let markerOnlyNudge = "Your last reply was only a tool-call marker, with no tool call in it. Call the tool "
        + "with the tool-calling interface, or give your answer."

    /// Text that is nothing but chat-template tool-call markers (`<tool_call|>`, `<|tool_call>`, `<tool_call>`,
    /// `</tool_call>`, `<|tool_calls_section_begin|>`, …): the model started a call and the server delivered only that.
    static func onlyToolCallMarkers(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: #"</?\|?(tool_calls?|function_calls?)(_section_(begin|end))?\|?>"#,
                                                 with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stripped.count < text.count
    }

    /// An empty reply that reports output tokens beyond its reasoning: the server couldn't parse the model's
    /// tool call and dropped it (seen on OpenRouter). A call written into the reasoning is the model's own
    /// doing, and the nudge handles it.
    public static func droppedCall(_ m: ChatMessage) -> Bool {
        guard m.role == .assistant, m.toolCalls.isEmpty, m.meta?.stopReason == .completed, m.meta?.finishReason != .length,
              m.meta?.declined != true,
              m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let tail = (m.reasoning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.hasSuffix("}"), tail.contains("{") { return false }
        // Thinking the server billed but showed only as a summary (Claude, Gemini) isn't a lost reply's output.
        let thinking = max(m.meta?.usage?.reasoningTokens ?? 0, (m.reasoning ?? "").utf8.count / 4)
        return (m.meta?.usage?.completionTokens ?? 0) - thinking > 10
    }

    static func isContinuation(_ m: ChatMessage) -> Bool {
        m.role == .user && m.content == Compactor.continuationText
    }

    /// Messages as they go to the model. Assistant turns with no text and no calls (failed turns) are
    /// dropped, as are replies the loop took back (`TurnMeta.unsent`) and tool results whose call isn't in the history.
    static func sendable(_ history: [ChatMessage]) -> [ChatMessage] {
        var callIDs = Set<String>()
        var out: [ChatMessage] = []
        for m in history {
            switch m.role {
            case .assistant:
                if m.content.isEmpty && m.toolCalls.isEmpty && m.meta?.paused != true { continue }
                if m.meta?.unsent == true { continue }          // taken back and answered with a nudge: never sent again
                m.toolCalls.forEach { callIDs.insert($0.id) }
                out.append(m)
            case .tool:
                guard let id = m.toolCallID, callIDs.contains(id) else { continue }
                out.append(m)
            case .user:
                out.append(m)
            case .system:
                continue
            }
        }
        // An assistant turn whose tool calls never got results (stopped mid-run) would be rejected by
        // strict servers; give each missing result a placeholder.
        // Results are matched to the reply just before them, by position, since ids can repeat across replies (a
        // server that sends none gets local ones: call_0, call_1, … in every reply).
        var fixed: [ChatMessage] = []
        var pending: [ToolCall] = []
        func placeholders() {
            for c in pending {
                // It may have been running when kurtkode stopped (a quit, a crash): say what's known, not more.
                fixed.append(ChatMessage(role: .tool, content: "Error: no result was recorded for this tool call. kurtkode "
                                         + "stopped before it ran or while it was running, so any effect it had is unknown; "
                                         + "check before relying on it.",
                                         toolCallID: c.id))
            }
            pending = []
        }
        for m in out {
            switch m.role {
            case .assistant:
                placeholders()
                fixed.append(m)
                pending = m.toolCalls
            case .tool:
                if let i = pending.firstIndex(where: { $0.id == m.toolCallID }) { pending.remove(at: i) }
                fixed.append(m)
            default:
                placeholders()
                fixed.append(m)
            }
        }
        placeholders()
        return fixed
    }

    /// The ids of the messages the session stores, kept as the run emits them (`.assistant`, `.toolFinished`,
    /// `.injected`), so a compaction's boundaries can be chosen among them.
    final class StoredIDs: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: Set<UUID>
        init(_ ids: [UUID]) { self.ids = Set(ids) }
        func insert(_ id: UUID) { lock.withLock { _ = ids.insert(id) } }
        func contains(_ id: UUID) -> Bool { lock.withLock { ids.contains(id) } }
    }

    /// Arguments compared semantically, so `{"path": "a"}` and `{"path":"a"}` count as the same call.
    static func normalizedArguments(_ json: String) -> String {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else { return json }
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? json
    }
}
