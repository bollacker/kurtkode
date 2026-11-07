import AgentCore
import Foundation

/// One kurtkode session driven from the command line: the same agent loop, tools, sandbox, MCP servers,
/// subagents, and session files as the app, without the UI. A frontend supplies approvals and renders events.
public final class CLISession: @unchecked Sendable {
    public struct Failure: LocalizedError, CustomStringConvertible {
        public let message: String
        public var description: String { message }
        public var errorDescription: String? { message }
    }

    public typealias ClientFactory = @Sendable (Endpoint, String?) -> ChatClient

    public let settings: AppSettings
    /// The project folder; the workspace adds the session's extra folders.
    public let root: URL
    public var workspace: Workspace { Workspace(root: root, folders: session.folders) }
    public private(set) var session: Session
    public private(set) var endpoint: Endpoint
    public var mode: PermissionMode
    public var maxSteps: Int
    public var sandboxUse: SandboxUse?
    public var subagentsEnabled = true
    /// Someone is at the terminal (not `-p`, not piped input): the run may pause, so it gets the longer cache.
    public var interactive = true
    /// --no-builtin-skills turns them off for this process, whatever Settings says.
    public var builtinSkillsEnabled = true
    /// --skill-router, else Settings.
    public var skillRouting: SkillRouting?
    /// --reasoning: over the profile's setting for this process ("default": the model's own).
    public var reasoning: String?
    /// Stops one subagent run (Ctrl-C while one runs) while the main agent goes on.
    public let subagentControl = SubagentControl()
    public private(set) var sessionRules: [AllowRule] = []
    /// Asks the user; the default refuses (a -p run has nobody to ask).
    public var approve: @Sendable (ApprovalRequest) async -> ApprovalDecision = { request in
        if let reason = request.reason {
            // Asked even in --mode auto (a dangerous command, a rule, a repeat): nobody can say yes here.
            return .refuse(message: "This needs the user's approval because \(reason), and they can't approve actions in this "
                           + "run (kurtkode -p). Don't retry; say what you would do, so they can do it themselves.",
                           why: "nobody to ask (kurtkode -p): \(reason)")
        }
        return .refuse(message: "The user can't approve actions in this run (kurtkode -p). Don't retry; say what you would do "
                       + "and which command or change it needs, so they can rerun with --mode auto or do it themselves.",
                       why: "nobody to ask (kurtkode -p)")
    }
    /// Asks the user the model's questions (`ask_user`), an answer for each; nil (-p): the tool isn't offered.
    public var askUser: (@Sendable ([UserQuestion]) async -> [String?])?
    /// Shows the model's plan and returns the user's decision (`present_plan`); nil (-p): the tool isn't offered.
    public var presentPlan: (@Sendable (PlanProposal) async -> PlanDecision)?
    public var onEvent: @Sendable (AgentEvent) -> Void = { _ in }
    /// The conversation so far for a question on the side, which can come during a run: `session` belongs to the run.
    private let sideLock = NSLock()
    private var sideMessages: [ChatMessage] = []
    /// What the user typed during the run, taken at its next step.
    public var takeQueued: (@Sendable () async -> [String])?
    /// Images for the next message (`ImageStore`), when the model takes them.
    public var pendingImages: [ImageAttachment] = []
    public private(set) var hub: MCPHub?
    /// The project's hooks while they wait for approval (the frontend asks, or -p skips them).
    public private(set) var pendingHooks: HookConfig?
    public private(set) var hookProblem: String?
    let store: SessionStore
    let shell: ShellState
    let makeClient: ClientFactory
    /// Built at the first message and reused, so the server's prompt cache keeps working across messages.
    let prompt = FrozenSystemPrompt()
    private var persisted: Bool
    /// The context length of the current model, once known.
    public private(set) var contextLimit: Int?
    /// What LM Studio's list says about the model's images. Nil until it's read, and on other servers.
    private var visionListed: Bool?

    public init(settings: AppSettings, workspace: URL, options: CLIOptions,
                makeClient: @escaping ClientFactory = { ChatClient(endpoint: $0, apiKey: $1) }) async throws {
        self.settings = settings
        self.makeClient = makeClient
        let root = workspace.standardizedFileURL
        let canonical = Workspace(root: root).root
        self.root = canonical
        store = settings.sessionStore
        shell = ShellState(cwd: root)
        mode = options.mode ?? settings.defaultMode
        maxSteps = options.maxSteps ?? settings.run.maxSteps
        sandboxUse = options.sandbox
        subagentsEnabled = options.subagents
        builtinSkillsEnabled = options.builtinSkills
        skillRouting = options.skillRouting
        interactive = !options.printMode && isatty(STDIN_FILENO) == 1
        reasoning = options.reasoning

        var existing: Session?
        if options.continueLast || options.resume != nil {
            let mine = try await store.list().filter { Self.sameFolder($0.workspace, canonical) }.sorted { $0.updatedAt > $1.updatedAt }
            var pick = mine.first
            if let prefix = options.resume {
                // An id prefix that fits several sessions is refused, as `inspect` does: resuming the wrong one adds the
                // user's turn to another conversation.
                let hits = mine.filter { $0.id.uuidString.lowercased().hasPrefix(prefix.lowercased()) }
                guard hits.count < 2 else {
                    throw Failure(message: "\(prefix) matches \(hits.count) sessions in this project: "
                                  + hits.prefix(5).map { $0.id.uuidString.prefix(8).lowercased() }.joined(separator: ", ")
                                  + ". Give more of the id.")
                }
                pick = hits.first
            }
            guard let pick else {
                throw Failure(message: options.resume.map { "No session in this project starts with \($0) (see --list-sessions)." }
                              ?? "There's no earlier session in this project to continue.")
            }
            existing = try await store.load(pick.id)
        }
        if let existing {
            session = existing
            endpoint = settings.endpoint(existing.endpointID) ?? settings.defaultEndpoint
            persisted = true
            if options.mode == nil, let m = existing.permissionMode { mode = m }
        } else {
            let (e, model) = try options.model.map { try CLIOptions.resolveModel($0, settings: settings) } ?? (settings.defaultEndpoint, settings.defaultModel)
            endpoint = e
            // The resolved path (symlinks, /private/tmp): the app and the MCP and hook approvals use it too.
            let header = SessionHeader(endpointID: e.id, model: model, workspace: canonical.path)
            session = Session(header: header, messages: [], model: model, endpointID: e.id)
            persisted = false
        }
        sideMessages = session.messages
        if let spec = options.model, existing != nil { try await setModel(spec) }
        if !options.folders.isEmpty { try await setFolders(Self.merged(session.folders, options.folders)) }
    }

    /// Whether a stored session's workspace is this folder, however either is spelled (older sessions were stored
    /// under the path as typed, a symlink included).
    static func sameFolder(_ stored: String?, _ root: URL) -> Bool {
        guard let stored else { return false }
        return stored == root.path || Workspace(path: stored).root.path == root.path
    }

    /// Folders from `added` replace same-path ones in `current` (so --read-dir can make one read-only again).
    static func merged(_ current: [ExtraFolder], _ added: [ExtraFolder]) -> [ExtraFolder] {
        current.filter { c in !added.contains { $0.path == c.path } } + added
    }

    /// The session's extra folders (saved with it).
    public func setFolders(_ folders: [ExtraFolder]) async throws {
        session.folders = folders
        if persisted { try await store.append(.folders(folders), to: session.header.id) }
    }

    public var model: String { session.model }
    public var profile: ModelProfile {
        var p = settings.profile(endpoint.id, session.model)
        if let o = escalatedProfile, o.key == ModelProfile.key(endpoint.id, session.model) {
            if p.providers == nil { p.providers = o.providers }
            if p.reasoning == nil { p.reasoning = o.reasoning }
        }
        return p
    }

    // MARK: Model

    /// Switches model ("model" or "endpoint:model") for the next turn. Returns what the switch costs, when it's worth
    /// saying (a large session resent without a cache).
    @discardableResult
    public func setModel(_ spec: String) async throws -> String? {
        let (e, m) = try CLIOptions.resolveModel(spec, settings: settings)
        let unchanged = e.id == session.endpointID && m == session.model
        var note: String?
        if !unchanged, let used = session.messages.last(where: { $0.meta?.usage != nil })?.meta?.usage?.totalTokens {
            let thinks = session.messages.last(where: { $0.role == .assistant && $0.meta != nil })?.native.map { n in
                n.api == .anthropic && (n.blocks.arrayValue ?? []).contains { if case .object(let b) = $0 { b["type"] == "thinking" } else { false } }
            } ?? false
            note = PriceList.switchNote(promptTokens: used, api: e.kind.api, model: m, fromThinking: thinks,
                                        cacheHour: settings.run.cacheHour(interactive: interactive).main)
        }
        endpoint = e
        session.model = m
        session.endpointID = e.id
        contextLimit = nil
        visionListed = nil
        if persisted, !unchanged { try await store.append(.model(m, endpoint: e.id), to: session.header.id) }
        return note
    }

    /// Makes sure the model can answer: on this Mac's LM Studio it must exist and be loaded (loading it with
    /// an explicit context and one slot, and only with 30% of memory free, never by LM Studio's on-demand
    /// load). Returns a note about a load, if one happened.
    @discardableResult
    public func prepareModel() async throws -> String? {
        let profile = profile
        guard endpoint.kind == .lmstudio else {
            // Anthropic and Google list every model's context; some OpenAI-compatible servers do too (OpenRouter,
            // vLLM, Ollama), where a context entered for the endpoint wins.
            var listed: Int?
            let native = endpoint.kind.reportsContextLength
            if profile.contextLength == nil, native || endpoint.manualContextLength == nil {
                var lister = ChatClient(endpoint: endpoint, apiKey: settings.apiKey(for: endpoint))
                lister.idleTimeout = 10                 // a stalled server shouldn't hold up the start
                listed = await lister.contextLength(of: session.model)
                    .map { min($0, Endpoint.nativeContextCap) }
            }
            // On OpenAI-compatible servers a listed context only lowers the default (a model with a small window), never
            // raises it: OpenRouter lists each model's largest provider window, and a bigger budget means bigger requests.
            let openAIListed = listed.map { min($0, settings.run.defaultContextLength) }
            contextLimit = profile.contextLength ?? (native ? listed ?? endpoint.manualContextLength : endpoint.manualContextLength ?? openAIListed)
                ?? settings.run.defaultContextLength
            return nil
        }
        let infos: [ModelInfo]
        do { infos = try await LMStudioService(endpoint: endpoint).models() }
        catch { throw Failure(message: "\(endpoint.name) isn't responding (\(error.localizedDescription)). Is the LM Studio server running?") }
        guard let info = infos.first(where: { $0.id == session.model }) else {
            let chat = infos.filter(\.isChatModel).map(\.id).joined(separator: ", ")
            throw Failure(message: "\(endpoint.name) has no model \(session.model). It has: \(chat)")
        }
        visionListed = info.supportsVision
        if info.state == .loaded {
            contextLimit = profile.contextLength ?? info.loadedContextLength ?? info.maxContextLength
            return nil
        }
        guard endpoint.isLocal else { throw Failure(message: "\(session.model) isn't loaded on \(endpoint.name).") }
        let context = min(profile.contextLength ?? settings.run.defaultContextLength, info.maxContextLength ?? .max)
        let free = MemoryStatus.current().freePercent
        guard free >= 30 else {
            throw Failure(message: "\(session.model) isn't loaded, and only \(free)% of memory is free (30% needed). "
                          + "Unload a model (the app's Models window, or lms unload) and try again.")
        }
        do { try await LMSCLI().load(session.model, contextLength: context, parallel: 1) }
        catch { throw Failure(message: "Couldn't load \(session.model): \(error.localizedDescription)") }
        contextLimit = profile.contextLength ?? context
        return "Loaded \(session.model) with \(context / 1024)k context (free memory was \(free)%)."
    }

    // MARK: MCP

    /// Reads the MCP config and starts the servers the user trusts; returns project servers that wait for
    /// approval, for the frontend to ask about.
    public func startMCP() async -> [MCPHub.Status] {
        let hub = MCPHub(workspace: workspace.root, approvals: settings.mcpApprovals)
        self.hub = hub
        await hub.reload()
        await hub.waitForStartup()
        return await hub.statusList.filter { $0.state == .needsApproval }
    }

    public func approveMCP(_ name: String) async throws { try await hub?.approve(name) }

    // MARK: Hooks

    var hookApprovals: HookApprovals { HookApprovals(fileURL: settings.support.appending(path: "hook-approvals.json")) }

    /// The user's hooks plus the project's once approved; notes project hooks that wait for approval.
    public func loadHooks() -> Hooks? {
        let (hooks, pending, problem) = Hooks.load(workspace: workspace.root, approvals: hookApprovals,
                                                   sessionID: session.header.id.uuidString,
                                                   transcriptPath: store.fileURL(for: session.header).path)
        pendingHooks = pending
        hookProblem = problem
        return hooks.isEmpty ? nil : hooks
    }

    public func approveHooks() throws {
        guard let pending = pendingHooks else { return }
        try hookApprovals.approve(pending, workspace: workspace.root)
        pendingHooks = nil
    }

    // MARK: Permission rules

    var permissionApprovals: PermissionApprovals { PermissionApprovals(fileURL: settings.support.appending(path: "permission-approvals.json")) }

    /// The project's allow rules while they wait for approval (deny and ask rules apply at once).
    public private(set) var pendingRules: (fingerprint: String, rules: [String])?
    public private(set) var rulesProblem: String?

    /// Allow, ask, and deny rules from the user's and the project's settings files.
    public func loadPermissionRules() -> PermissionRules {
        let (rules, pending, problem) = PermissionRules.load(root: workspace.root, approvals: permissionApprovals)
        pendingRules = pending
        rulesProblem = problem
        return rules
    }

    public func approveRules() throws {
        guard let pending = pendingRules else { return }
        try permissionApprovals.approve(pending.fingerprint, workspace: workspace.root)
        pendingRules = nil
    }

    // MARK: Running

    /// Sends a message: attaches its @ mentions, runs the agent until it answers or stops, and saves
    /// everything to the session file (the app shows CLI sessions too).
    @discardableResult
    public func send(_ text: String) async throws -> AgentStop? {
        // One run at a time on a session, across the app and every terminal (`SessionLock`); checked before the
        // message is saved, so a refused one isn't left in the session unanswered.
        try await locked { try await self.sendLocked(text) }
    }

    /// Runs an operation that adds to or restores the session while holding its lock (`SessionLock.withLock`), after
    /// picking up what another kurtkode wrote. Refused with the "running in another kurtkode" message when it's held.
    private func locked<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await SessionLock.withLock(store.lockURL(for: session.header.id),
                                                  holder: SessionLock.describe("kurtkode in a terminal"),
                                                  reload: { await self.reloadIfChangedElsewhere() }, body)
        } catch let busy as SessionBusy {
            throw Failure(message: busy.errorDescription ?? SessionLock.busyMessage(busy.who))
        }
    }

    private func sendLocked(_ text: String) async throws -> AgentStop? {
        if contextLimit == nil { try await prepareModel() }
        var hookContext: [String] = []
        if let hooks = loadHooks(), hooks.matchers[.userPromptSubmit]?.isEmpty == false {
            let outcome = await hooks.userPromptSubmit(text)
            for e in outcome.errors { onEvent(.hookNotice(e)) }
            if outcome.blocked { throw Failure(message: "A hook blocked this message: " + (outcome.reason ?? "no reason given")) }
            hookContext = outcome.context
        }
        var message = ChatMessage.user(text)
        if !pendingImages.isEmpty {
            message.images = pendingImages
            pendingImages = []
        }
        try await append(message)
        // The hook's context is a note of its own, so the user's message (recall, rewind, resend) stays their words.
        if !hookContext.isEmpty {
            try await append(FrozenSystemPrompt.noteMessage("[Context from a hook]\n" + hookContext.joined(separator: "\n")))
        }
        let tools = PermissionPolicy(mode: mode).offered(AllTools.all)
        let mentions = Mentions.find(in: text, workspace: workspace)
        for m in await Mentions.messages(for: mentions, workspace: workspace, shell: shell) {
            try await append(m)
            onEvent(m.role == .assistant ? .assistant(m) : .toolFinished(m))
        }
        return await run(tools: tools)
    }

    /// Runs a command for the user (`!command`) and adds its output to the conversation.
    public func runUserCommand(_ command: String, progress: (@Sendable (String) -> Void)? = nil) async throws -> ChatMessage {
        try await locked {
            let m = await UserShell.run(command, workspace: workspace, shell: shell, progress: progress)
            try await append(m)
            return m
        }
    }

    /// This session's subagent runs, one line each (`/agents`).
    public func agentsSummary() async -> String {
        let runs = await store.subagentRuns(of: session.header)
        guard !runs.isEmpty else { return "No subagent runs in this session yet." }
        return runs.enumerated().map { i, r in "\(i + 1). " + SubagentRunSummary(r).line }.joined(separator: "\n")
    }

    /// Summarizes the conversation now (`/compact`). Returns what happened.
    public func compact(focus: String) async throws -> String {
        try await locked { try await compactLocked(focus: focus) }
    }

    private func compactLocked(focus: String) async throws -> String {
        if contextLimit == nil { try await prepareModel() }
        guard !session.messages.isEmpty else { return "Nothing to summarize yet." }
        guard SessionRun.hasNewMessagesToCompact(session) else { return SessionRun.nothingToCompact }
        let tools = PermissionPolicy(mode: mode).offered(AllTools.all)
        let outcome = await SessionRun.compact(session: session, client: client(), model: session.model, hooks: loadHooks(),
                                               baseSystemPrompt: await systemPrompt(tools: tools), tools: tools,
                                               settings: settings.run, profile: profile, focus: focus,
                                               contextLimit: contextLimit,
                                               costs: CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { [self] e in
                                                   try? await persist(.cost(e))
                                               },
                                               wire: WireLog(directory: store.wireDirectory(for: session.header)))
        guard let c = outcome.compaction else { return outcome.explanation ?? "" }
        session.compactions.append(c)
        try await persist(.compaction(c))
        return "Summarized: about \(c.tokensBefore / 1000)k tokens down to \(max(1, c.tokensAfter / 1000))k."
    }

    public func setMode(_ m: PermissionMode) async throws {
        mode = m
        if persisted { try await store.append(.permissionMode(m), to: session.header.id) }
    }

    /// Whether the model takes images: the profile's setting, else what LM Studio's list says, else anything but a local
    /// server's model.
    public var acceptsImages: Bool { profile.supportsImages ?? visionListed ?? (endpoint.kind != .lmstudio) }

    /// `/rename`.
    /// `/btw`: an answer from the conversation so far, on the session's model, kept out of the conversation. Safe during
    /// a run. Its cost goes in the session's file.
    public func askOnTheSide(_ question: String) async -> String {
        let messages = sideLock.withLock { sideMessages.isEmpty ? nil : sideMessages }
        let store = store, id = session.header.id, onEvent = onEvent
        let costs = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { e in
            try? await store.append(.cost(e), to: id)
            onEvent(.cost(e))
        }
        let answer = await SideQuestion.ask(question, messages: messages ?? [], client: client(), model: session.model,
                                            limits: settings.run.limits(for: profile, api: endpoint.kind.api), costs: costs)
        return answer ?? "The side question got no answer."
    }

    private func noteForTheSide(_ messages: [ChatMessage], replace: Bool = false) {
        sideLock.withLock { if replace { sideMessages = messages } else { sideMessages += messages } }
    }

    public func rename(_ title: String) async throws {
        session.title = title
        try await persist(.title(title))
    }

    /// `/retry`: the last reply goes, and the model answers again.
    public func retry() async throws -> AgentStop? {
        try await locked {
            // After the reload: the last reply may be one the app added meanwhile.
            guard let last = session.messages.last, last.role == .assistant else {
                throw Failure(message: "There's no reply to retry yet.")
            }
            session.messages.removeLast()
            noteForTheSide(session.messages, replace: true)
            try await persist(.retract(last.id))
            return await run(tools: PermissionPolicy(mode: mode).offered(AllTools.all))
        }
    }

    /// `/resume`: goes on with another of this project's sessions, on its own model. Its permission mode comes along.
    /// Mid-session, the mode stays: it's what this terminal chose, and another session's Full Auto mustn't come with it.
    public func resume(_ id: UUID) async throws {
        guard let loaded = try await store.load(id) else { throw Failure(message: "That session is gone.") }
        session = loaded
        noteForTheSide(loaded.messages, replace: true)
        endpoint = settings.endpoint(loaded.endpointID) ?? settings.defaultEndpoint
        persisted = true
        sessionRules = []
        prompt.reset()
        contextLimit = nil
    }

    /// The session as Markdown, as `kurtkode export` writes it.
    public func exportMarkdown() -> String { SessionExport.markdown(session) }

    /// `/status`: where this session stands.
    public var statusReport: String {
        let spent = CostSummary(session.costs)
        var lines = ["Session  \(session.header.id.uuidString.prefix(8).lowercased())  \(session.displayTitle)",
                     "Model    \(session.model) on \(endpoint.name)",
                     "Mode     \(mode.displayName)",
                     "Project  \(root.path)" + (GitRepo(root: root).isLinkedWorktree ? " (a worktree)" : "")]
        lines += session.folders.map { "Folder   \($0.displayPath)\($0.writable ? "" : " (read-only)")" }
        lines.append(contextSummary)
        lines.append(spent.isEmpty ? "Spent    nothing recorded" : "Spent    \(spent.spentText()) in \(spent.requests) requests")
        return lines.joined(separator: "\n")
    }

    /// Starts over in a new session, with the same model and settings (`/clear`).
    public func clear() {
        let header = SessionHeader(endpointID: endpoint.id, model: session.model, workspace: workspace.root.path)
        let folders = session.folders
        session = Session(header: header, messages: [], model: session.model, endpointID: endpoint.id)
        session.folders = folders
        noteForTheSide([], replace: true)
        persisted = false
        sessionRules = []
        prompt.reset()
    }

    public var contextSummary: String {
        let used = session.messages.last(where: { $0.meta?.usage != nil })?.meta?.usage?.totalTokens ?? 0
        guard let limit = contextLimit else { return "About \(used / 1000)k tokens used; the context length isn't known yet." }
        return "Context: about \(used / 1000)k of \(limit / 1000)k tokens (\(used * 100 / max(1, limit))%)."
    }

    func client() -> ChatClient { makeClient(endpoint, settings.apiKey(for: endpoint)) }

    /// The session's base system prompt, kept across processes (the session records it; see `FrozenSystemPrompt`).
    func systemPrompt(tools: [any Tool]) async -> String {
        let text = await prompt.text(workspace: workspace, tools: tools, mode: mode, sandbox: sandbox,
                                     userPrompt: settings.run.systemPrompt, addendum: profile.promptAddendum,
                                     style: settings.run.style(for: endpoint.kind.api), subagents: subagentsEnabled && !tools.isEmpty,
                                     skills: !tools.isEmpty && !Skills.load(root: root, builtin: builtinSkills).isEmpty,
                                     recorded: session.recordedPrompt)
        if let r = prompt.takeRecord() {
            session.recordedPrompt = r
            session.systemPrompt = r.text
            try? await persist(.systemPrompt(r))
        }
        return text
    }

    /// As Settings says, unless --sandbox overrides when it applies (the extra paths and network still come from Settings).
    var sandbox: SandboxPolicy? { settings.run.sandbox(for: mode, use: sandboxUse) }

    /// The built-in skills folder, when Settings and the command line allow them.
    public var builtinSkills: URL? { Skills.builtin(builtinSkillsEnabled && settings.run.builtinSkills) }

    private func run(tools builtIn: [any Tool]) async -> AgentStop? {
        var run = settings.run
        run.builtinSkills = builtinSkills != nil
        let approve = approve
        var subagentModel: SubagentModelResolver?
        let main = endpoint, mainModel = session.model
        if subagentsEnabled {
            let settings = settings, makeClient = makeClient
            subagentModel = { agent, card in
                Self.subagentModel(agent, card: card, main: main, mainModel: mainModel, settings: settings, makeClient: makeClient)
            }
        }
        let turn = TurnKey(session.lastRequest?.id ?? UUID())
        var setup = SessionRun(session: session, store: store, settings: run, profile: profile, endpointID: endpoint.id,
                               api: endpoint.kind.api, permissionRules: loadPermissionRules(),
                               mode: mode, rules: sessionRules, tools: builtIn, workspace: workspace, shell: shell,
                               contextLimit: contextLimit, sandbox: sandbox,
                               turn: turn,
                               checkpoints: CheckpointStore(directory: store.checkpointDirectory(for: session.header)),
                               approve: { await approve($0) }, hooks: loadHooks(), subagentModel: subagentModel,
                               maxSteps: maxSteps, sandboxUse: sandboxUse, interactive: interactive)
        setup.config.subagents?.control = subagentControl
        if let take = takeQueued {
            let workspace = workspace, shell = shell
            // As in the app: edits after a queued message are snapshotted under it.
            setup.config.takeInput = {
                var out: [ChatMessage] = []
                for text in await take() {
                    let message = ChatMessage.user(text)
                    if out.isEmpty { turn.id = message.id }
                    out.append(message)
                    out += await Mentions.messages(for: Mentions.find(in: text, workspace: workspace), workspace: workspace, shell: shell)
                }
                return out
            }
        }
        if run.subagentRetry {
            let settings = settings, makeClient = makeClient
            setup.config.subagents?.retryModel = { agent, endpointID, model, reasoning in
                SubagentRouting.retry(after: endpointID, model: model, reasoning: reasoning,
                                      routed: SubagentRouting.routed(agent, settings: settings.run), main: main, pool: settings.pool,
                                      endpoints: settings.endpoints).map { Self.model($0, settings: settings, makeClient: makeClient) }
            }
        }
        if let r = reasoning { setup.config.reasoningEffort = r == "default" ? nil : r }
        setup.config.subagents?.slots = SubagentSetup.slots(
            parallel: run.subagentParallel,
            localLMStudio: Set(settings.endpoints.filter { $0.kind == .lmstudio && $0.isLocal }.map(\.id)))
        if run.graderModel == nil, run.graderAutomatic {
            let settings = settings, makeClient = makeClient
            setup.config.subagents?.grader = { runEndpoint, runModel in
                SubagentRouting.grader(main: main, runEndpointID: runEndpoint, runModel: runModel, pool: settings.pool,
                                       endpoints: settings.endpoints).map { Self.model($0, settings: settings, makeClient: makeClient) }
            }
        }
        if let ref = run.graderModel {
            let settings = settings, makeClient = makeClient
            setup.config.subagents?.grader = { _, _ in Self.model(ref, settings: settings, makeClient: makeClient) }
        }
        // A6: important subagent runs that change files get another vendor's review, in hosted sessions only.
        if main.isCloudAPI {
            let settings = settings, makeClient = makeClient
            setup.config.subagents?.reviewer = { runEndpoint, runModel in
                ReviewRouting.reviewer(for: runModel, endpoint: settings.endpoints.first { $0.id == runEndpoint } ?? main,
                                       pool: settings.pool, endpoints: settings.endpoints).map { Self.model($0, settings: settings, makeClient: makeClient) }
            }
        }
        setup.config.sendImages = acceptsImages
        setup.config.askUser = askUser
        setup.config.presentPlan = presentPlan
        if let ref = run.summarizer(excluding: endpoint.id, session.model), let e = settings.endpoint(ref.endpointID) {
            setup.config.summarizer = Summarizer(client: makeClient(e, settings.apiKey(for: e)), model: ref.model,
                                                 historyShape: settings.profile(e.id, ref.model).history, endpointID: e.id)
        }
        if let ref = run.fallback(excluding: endpoint.id, session.model), let e = settings.endpoint(ref.endpointID),
           await Self.isReady(ref.model, on: e) {
            let p = settings.profile(e.id, ref.model)
            setup.config.fallback = FallbackModel(client: makeClient(e, settings.apiKey(for: e)), model: ref.model,
                                                  historyShape: p.history, temperature: p.temperature, endpointID: e.id)
        }
        if let hub { setup.config.tools += await hub.allTools }
        await setup.countSubagentSpending(session: session, store: store)
        await setup.countDailySpending(settings: run, store: store, workspace: session.header.workspace, main: endpoint)
        let system = await systemPrompt(tools: setup.offeredTools)
        // The skill router (by default for OpenAI-compatible servers): which skill fits the request, said after it.
        var history = setup.history
        final class Routed: @unchecked Sendable { let lock = NSLock(); var costs: [CostEntry] = [] }
        let routed = Routed()
        let routeNote = await setup.routeSkill(client: client(), model: session.model, routing: skillRouting ?? run.skillRouting,
                                               project: root) { e in routed.lock.withLock { routed.costs.append(e) } }
        for e in routed.lock.withLock({ routed.costs }) {
            try? await persist(.cost(e))
            session.costs.append(e)
        }
        // A resumed session keeps its prompt; the date and git status it states go after the user's message.
        let serverNote = await hub?.instructionNote(alreadySent: session.messagesInContext).map(FrozenSystemPrompt.noteMessage)
        for m in [prompt.takeNote().map(FrozenSystemPrompt.noteMessage), routeNote, serverNote].compactMap({ $0 }) {
            try? await append(m)
            history.append(m)
        }
        let config = setup.config

        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var records: [SessionRecord] = []
            var rules: [AllowRule] = []
            var stop: AgentStop?
            var mode: PermissionMode?
        }
        let box = Box()
        let onEvent = onEvent
        // Each record is saved as it arrives, as the app does: a run cut off (killed, crashed) keeps what it did, and
        // the app and `kurtkode inspect` can follow it while it goes.
        await AgentLoop.run(client: client(), model: session.model, systemPrompt: system, history: history,
                            config: config, workspace: workspace) { [self] event in
            var record: SessionRecord?
            switch event {
            case .assistant(let m), .toolFinished(let m), .injected(let m):
                record = .message(m)
                noteForTheSide([m])
            case .compacted(let c): record = .compaction(c)
            case .cost(let e): record = .cost(e)
            case .runEnded(let r): record = .run(r)
            case .judged(let j): record = .judgment(j)
            case .ruleAdded(let r): box.lock.withLock { box.rules.append(r) }
            case .modeChanged(let m):
                box.lock.withLock { box.mode = m }
                if persisted { try? await store.append(.permissionMode(m), to: session.header.id) }
            case .finished(let s): box.lock.withLock { box.stop = s }
            default: break
            }
            if let record {
                box.lock.withLock { box.records.append(record) }
                try? await persist(record)
            }
            onEvent(event)
        }
        let (records, rules, stop, newMode) = box.lock.withLock { (box.records, box.rules, box.stop, box.mode) }
        for r in rules where !sessionRules.contains(r) { sessionRules.append(r) }
        if let newMode { mode = newMode }
        for r in records {
            if let m = r.message { session.messages.append(m) }
            if let c = r.compaction { session.compactions.append(c) }
            if let e = r.cost {
                if let i = session.costs.firstIndex(where: { $0.id == e.id }) { session.costs[i] = e } else { session.costs.append(e) }
            }
            if let x = r.run { session.runs.append(x) }
        }
        return stop
    }

    /// `/good`, `/bad`: the user's thumbs on the latest main run, kept in the session. Returns what to print.
    /// `/diff [session]`: what the latest run, or the whole session, changed in the project's files.
    public func diff(_ arguments: String) async -> String {
        let words = arguments.split(separator: " ").map { $0.lowercased() }
        if let first = words.first, ["uncommitted", "branch"].contains(where: { $0.hasPrefix(first) }), first != "s" {
            let repo = GitRepo(root: root)
            guard repo.exists else { return "This project isn't a git repository." }
            let base: GitRepo.DiffBase
            if "uncommitted".hasPrefix(first) { base = .uncommitted }
            else if let name = words.dropFirst().first ?? nil { base = .branch(name) }
            else if let name = await repo.defaultBranch() { base = .branch(name) }
            else { return "Name the branch to compare with: /diff branch <name>." }
            do {
                let changes = try await repo.changes(base)
                guard !changes.isEmpty else { return "No changes." }
                let list = changes.map { "\($0.kind.rawValue) \($0.path) +\($0.additions ?? 0) −\($0.deletions ?? 0)" }.joined(separator: "\n")
                return list + "\n\n" + String(try await repo.patch(base).prefix(60_000))
            } catch { return "\(error.localizedDescription)" }
        }
        guard let snaps = store.snapshots(for: root) else { return "There are no snapshots for this folder." }
        let scope: ProjectSnapshots.Scope = arguments.lowercased().hasPrefix("s") ? .session : .lastRun
        do { return try await snaps.report(session: session.header.id, scope: scope) } catch { return "\(error.localizedDescription)" }
    }

    // MARK: Escalation (A4)

    /// The offer the latest main run earns (its signals; with Settings' review on, a hosted run's change reviewed by
    /// another vendor), or one for `reasons` given (the user's /bad or /escalate). Recorded when made; a run gets one
    /// offer from its own signals (a turn that failed before recording a run doesn't bring the last one's back).
    public func escalationOffer(reasons given: [String] = [], source: String = "signals", unknownTier: PoolEntry.Tier? = nil) async -> EscalationOffer? {
        reviewToFix = nil
        let run = session.runs.last { $0.agent == "main" }
        if given.isEmpty, let id = run?.id, session.escalations.contains(where: { $0.run == id }) { return nil }
        var fromEndpoint: Endpoint = endpoint
        var fromModel: String = session.model
        if let r = run, let e = settings.endpoint(r.setup.endpointID ?? endpoint.id) {
            fromEndpoint = e
            fromModel = r.setup.model
        }
        var reasons = given, source = source
        if reasons.isEmpty, let run { reasons = Escalation.reasons(run) }
        if reasons.isEmpty, let run, settings.run.escalationReview, fromEndpoint.isCloudAPI, run.outcome.stop != "costLimit",
           run.snapshots?.changed == true,
           let tier = Escalation.tier(endpoint: fromEndpoint, model: fromModel, pool: settings.pool, endpoints: settings.endpoints), tier < .frontier,
           case (_, let review?) = await review(""), let verdict = review.verdict, verdict != .looksRight {
            // "Has problems": findings for this model to fix (`reviewToFix`), not a stronger model.
            guard review.escalates else { reviewToFix = review; return nil }
            reasons = ["the review on \(review.reviewer) found it \(verdict.label)" + (review.findings.first.map { ": " + $0.problem } ?? "")]
            source = "review"
        }
        let settings = settings
        let context = session.messages.last(where: { $0.meta?.usage != nil })?.meta?.usage?.totalTokens
        guard var offer = Escalation.offer(run: run?.id, reasons: reasons, source: source, endpoint: fromEndpoint, model: fromModel,
                                           pool: settings.pool, endpoints: settings.endpoints, contextTokens: context,
                                           changedFiles: run?.snapshots?.changed == true, unknownTier: unknownTier, price: { r in PriceList.price(api: r.endpoint.kind.api, model: r.model) })
        else { return nil }
        // A listed price (OpenRouter's model list needs no key, so none is read for it).
        if offer.estimate == nil, let to = settings.endpoint(offer.toEndpointID), to.kind == .openai,
           let (p, _) = await RemotePrices.shared.price(client: ChatClient(endpoint: to, apiKey: nil), model: offer.toModel) {
            offer.estimate = Escalation.estimate(p, contextTokens: context, changedFiles: run?.snapshots?.changed == true)
            if offer.canReview { offer.reviewEstimate = Escalation.reviewEstimate(p) }
        }
        session.escalations.append(offer)
        try? await persist(.escalation(offer))
        return offer
    }

    /// The latest automatic review's findings when it found the change "has problems" and so made no offer: for the
    /// session's model to fix (`CodeReview.fixRequest`). Cleared by the next `escalationOffer`.
    public private(set) var reviewToFix: CodeReview?

    /// The user's answer: on yes, the session switches to the offer's model (with the pool entry's provider pins and
    /// reasoning, for this process) and the hand-over message to send comes back: the offer's run's request and change,
    /// without files withheld from remote models when the new model is remote.
    public func decide(_ offer: EscalationOffer, accept: Bool) async -> String? {
        var o = offer
        o.decision = accept ? .accepted : .declined
        if let i = session.escalations.firstIndex(where: { $0.id == o.id }) { session.escalations[i] = o }
        try? await persist(.escalation(o))
        guard accept, let target = settings.endpoint(o.toEndpointID) else { return nil }
        let run = session.runs.first { $0.id == o.run }
        let request = run?.userMessage.flatMap { id in session.messages.first { $0.id == id }?.content } ?? session.lastRequest?.content ?? ""
        var diff: String?
        if let refs = run?.snapshots, let snaps = store.snapshots(for: root),
           let d = try? await snaps.patch(session: session.header.id, from: refs.start, to: refs.end) {
            diff = target.isThirdParty ? UnifiedDiff.withholding(d, patterns: settings.run.withheldFromRemote).0 : d
        }
        _ = try? await setModel(target.name + ":" + o.toModel)
        escalatedProfile = (ModelProfile.key(o.toEndpointID, o.toModel), o.toProviders, o.toReasoning)
        return Escalation.handOver(o, request: request, diff: diff)
    }

    /// Decision 4: the offer's first action, one read-only review of the latest run's change on the model the offer would
    /// escalate to (with the pool entry's reasoning and provider pins). The offer is recorded as reviewed; escalating
    /// afterwards is still `decide`.
    public func reviewForEscalation(_ offer: EscalationOffer) async -> (text: String, review: CodeReview?) {
        var o = offer
        o.decision = .reviewed
        if let i = session.escalations.firstIndex(where: { $0.id == o.id }) { session.escalations[i] = o }
        try? await persist(.escalation(o))
        guard let e = settings.endpoint(o.toEndpointID),
              var reviewer = Self.model(ModelRef(endpointID: e.id, model: o.toModel), settings: settings, makeClient: makeClient)
        else { return ("\(o.toLabel) can't be reached.", nil) }
        if let r = o.toReasoning { reviewer.reasoning = r }
        if let p = o.toProviders { reviewer.providers = p }
        return await review("", using: (reviewer, e.isThirdParty))
    }

    /// The pool entry's settings for the model an escalation switched to (`profile` applies them where it sets none).
    private var escalatedProfile: (key: String, providers: ProviderRouting?, reasoning: String?)?

    func addCost(_ e: CostEntry) async {
        session.costs.append(e)
        try? await persist(.cost(e))
    }

    // MARK: Review (A6)

    /// `/review [session] [-m endpoint:model]`: another vendor's model (of the ones that made the change) reviews the
    /// latest run's change, or the session's; its verdict is kept as a judgment of the run (not for a whole session).
    /// Returns the text to show and the review.
    /// `using`: the reviewer already chosen (decision 4's review on the offer's model) and whether it is remote.
    public func review(_ arguments: String, using preset: (model: SubagentModel, remote: Bool)? = nil) async -> (text: String, review: CodeReview?) {
        var words = arguments.split(separator: " ").map(String.init)
        var named: String?
        if let i = words.firstIndex(of: "-m"), i + 1 < words.count { named = words[i + 1]; words.removeSubrange(i...(i + 1)) }
        let scope: ProjectSnapshots.Scope = words.first?.lowercased().hasPrefix("s") == true ? .session : .lastRun
        do {
            var input = try await ReviewInput.gather(scope: scope, session: session, snapshots: store.snapshots(for: root))
            guard !input.diff.isEmpty || input.run != nil else { return ("Nothing to review yet.", nil) }
            let reviewer: SubagentModel?, remote: Bool
            if let preset {
                reviewer = preset.model
                remote = preset.remote
            } else if let named {
                // A name the CLI doesn't know mustn't fall through to the default endpoint (a remote one, say).
                guard let colon = named.firstIndex(of: ":"), settings.endpoint(named: String(named[..<colon])) != nil else {
                    let known = (settings.endpoints.map(\.name) + ["lmstudio"]).joined(separator: ", ")
                    return ("No endpoint named \(named.split(separator: ":").first.map(String.init) ?? named); endpoints: \(known). "
                            + "Give endpoint:model (`kurtkode endpoint list`).", nil)
                }
                let (e, m) = try CLIOptions.resolveModel(named, settings: settings)
                reviewer = Self.model(ModelRef(endpointID: e.id, model: m), settings: settings, makeClient: makeClient)
                remote = e.isThirdParty
            } else {
                let vendors = input.vendors.isEmpty ? [ModelVendor.of(session.model, endpoint: endpoint)] : input.vendors
                let pick = ReviewRouting.reviewer(excluding: vendors, session: endpoint, pool: settings.pool, endpoints: settings.endpoints)
                reviewer = pick.map { Self.model($0, settings: settings, makeClient: makeClient) }
                remote = pick?.endpoint.isThirdParty ?? false
                if pick == nil {
                    return ("No reviewer of another vendor than \(vendors.sorted().joined(separator: ", ")) in the model pool"
                            + (endpoint.isCloudAPI ? "" : " on this Mac or its network") + ". Name one: /review -m endpoint:model (`kurtkode pool` lists the pool).", nil)
                }
            }
            guard let reviewer else { return ("That reviewer can't be reached.", nil) }
            if remote { input.withholding(settings.run.withheldFromRemote) }
            let costs = CostSink(scope: CostScope(run: input.run?.id, agent: "main", userMessage: input.run?.userMessage),
                                 endpointID: reviewer.endpointID, emit: { [weak self] e in await self?.addCost(e) })
            let review = await CodeReview.run(reviewer, prompt: input.prompt, costs: costs, meter: nil, limits: settings.run.limits(for: profile))
            if let run = input.run {
                let j = review.judgment(run: run.id)
                session.judgments.append(j)
                try? await persist(.judgment(j))
            }
            return (review.text + (input.withheld.isEmpty ? "" : "\n(Left out, withheld from remote models: " + input.withheld.joined(separator: ", ") + ")"), review)
        } catch { return ("Couldn't gather the change: \(error.localizedDescription)", nil) }
    }

    // MARK: Rewind (C3)

    /// The session's requests, for `/rewind`.
    public func rewindPoints() async -> [RewindPoint] {
        await RewindPoint.list(messages: session.messages, runs: session.runs, snapshots: store.snapshots(for: root),
                               session: session.header.id)
    }

    public func rewindPlan(to id: UUID) async -> RewindPlan {
        await RewindPlan.make(target: id, messages: session.messages, runs: session.runs, snapshots: store.snapshots(for: root),
                              session: session.header.id, checkpoints: CheckpointStore(directory: store.checkpointDirectory(for: session.header)))
    }

    /// Rewinds to just before request `id`, as the app does: the restored files, and the request's text when the
    /// messages went (to type again).
    public func rewind(to id: UUID, choice: RewindChoice) async throws -> (restored: [CheckpointStore.Restored], request: String?) {
        try await locked { try await rewindLocked(to: id, choice: choice) }
    }

    private func rewindLocked(to id: UUID, choice: RewindChoice) async throws -> (restored: [CheckpointStore.Restored], request: String?) {
        guard let idx = session.messages.firstIndex(where: { $0.id == id }), session.messages[idx].role == .user else { return ([], nil) }
        let plan = await rewindPlan(to: id)
        var restored: [CheckpointStore.Restored] = []
        if choice.restoresFiles {
            restored = try await plan.restoreFiles(snapshots: store.snapshots(for: root),
                                                   checkpoints: CheckpointStore(directory: store.checkpointDirectory(for: session.header)))
            for run in session.runs where run.agent == "main" && run.userMessage == id {
                let j = MainRunJudgments.implicit(run: run.id, why: "rewound")
                session.judgments.append(j)
                try await persist(.judgment(j))
            }
        }
        if choice.removesMessages {
            let removed = Array(session.messages[idx...])
            session.messages.removeSubrange(idx...)
            for m in removed { try await persist(.retract(m.id)) }
            return (restored, removed[0].content)
        }
        if !restored.isEmpty {
            try await append(FrozenSystemPrompt.noteMessage(plan.note(request: session.messages[idx].content, root: root.path)))
        }
        return (restored, nil)
    }

    public func rateLatestRun(up: Bool, note: String) async -> String {
        guard let run = session.latestReplyRun else { return "There's no reply to rate yet." }
        let j = MainRunJudgments.thumbs(run: run.id, up: up, note: note)
        session.judgments.append(j)
        do { try await persist(.judgment(j)) } catch { return "Couldn't save it: \(error.localizedDescription)" }
        return up ? "Marked the last reply as right." : "Marked the last reply as wrong."
    }

    /// Whether a model can answer without LM Studio loading it on demand (with a small context).
    static func isReady(_ model: String, on e: Endpoint) async -> Bool {
        guard e.kind == .lmstudio else { return true }
        return (try? await LMStudioService(endpoint: e).models())?.contains { $0.id == model && $0.state == .loaded } ?? false
    }

    /// A saved model (the grader), on its endpoint.
    static func model(_ ref: ModelRef, settings: AppSettings, makeClient: ClientFactory) -> SubagentModel? {
        guard let e = settings.endpoint(ref.endpointID) else { return nil }
        let p = settings.profile(e.id, ref.model)
        return SubagentModel(client: makeClient(e, settings.apiKey(for: e)), model: ref.model, historyShape: p.history,
                             contextLimit: p.contextLength ?? e.manualContextLength ?? settings.run.defaultContextLength,
                             temperature: p.temperature, endpointID: e.id, sendImages: false,
                             reasoning: p.reasoning, providers: p.providers)
    }

    /// A pool entry made ready to send to: its model's profile, with the entry's reasoning and provider pins.
    static func model(_ r: ResolvedPoolEntry, settings: AppSettings, makeClient: ClientFactory) -> SubagentModel {
        let p = settings.profile(r.endpoint.id, r.model)
        return SubagentModel(client: makeClient(r.endpoint, settings.apiKey(for: r.endpoint)), model: r.model, historyShape: p.history,
                             contextLimit: p.contextLength ?? r.endpoint.manualContextLength ?? settings.run.defaultContextLength,
                             temperature: p.temperature, endpointID: r.endpoint.id, sendImages: false,
                             reasoning: r.entry.reasoning ?? p.reasoning, providers: r.entry.providers ?? p.providers)
    }

    /// A subagent's model from its `model:` ("model" or "endpoint:model"/"endpoint|model"), else the app's Subagent
    /// model setting, else (the setting on automatic) the pool's entry for the card's tier, for a remote session only
    /// (`SubagentRouting`). Only models that are ready are used (the command line doesn't load extra models).
    static func subagentModel(_ agent: AgentDefinition, card: TaskCard, main: Endpoint, mainModel: String, settings: AppSettings,
                              makeClient: ClientFactory) -> SubagentModel? {
        if agent.model == nil, settings.run.subagentModel == nil, settings.run.subagentAutomatic {
            return SubagentRouting.automatic(card: card, main: main, mainModel: mainModel, pool: settings.pool,
                                             endpoints: settings.endpoints).map { model($0, settings: settings, makeClient: makeClient) }
        }
        var pair: (Endpoint, String)?
        if let spec = agent.model, ModelAlias.isAlias(spec) {
            pair = ModelAlias.resolve(spec, endpoints: settings.endpoints).map { ($0.endpoint, $0.model) }
        } else if let spec = agent.model?.replacingOccurrences(of: "|", with: ":") {
            // A misspelled endpoint leaves the subagent on the main model rather than on the default endpoint.
            pair = try? CLIOptions.resolveModel(spec, settings: settings)
        } else if let ref = settings.run.subagentModel, let e = settings.endpoint(ref.endpointID) {
            pair = (e, ref.model)
        }
        guard let (e, model) = pair else { return nil }
        let p = settings.profile(e.id, model)
        return SubagentModel(client: makeClient(e, settings.apiKey(for: e)), model: model, historyShape: p.history,
                             contextLimit: p.contextLength ?? e.manualContextLength ?? settings.run.defaultContextLength,
                             temperature: p.temperature, endpointID: e.id, sendImages: false,
                             reasoning: p.reasoning, providers: p.providers)
    }

    private func append(_ m: ChatMessage) async throws {
        session.messages.append(m)
        noteForTheSide([m])
        try await persist(.message(m))
    }

    /// Reloads the session when another process (the app shares sessions) appended to its file since this one last
    /// read or wrote it, so the next request holds what the other added. Returns how many messages that added.
    @discardableResult
    public func reloadIfChangedElsewhere() async -> Int? {
        guard persisted, await store.changedElsewhere(session.header.id),
              var fresh = try? await store.load(session.header.id) else { return nil }
        let added = fresh.messages.count - session.messages.count
        // This run's model stays (it may be a one-run --endpoint the other process doesn't know).
        fresh.model = session.model
        fresh.endpointID = session.endpointID
        session = fresh
        noteForTheSide(fresh.messages, replace: true)
        onEvent(.status("This session was changed by another kurtkode (the app?), so it was reloaded"
                        + (added > 0 ? ": \(added) new message\(added == 1 ? "" : "s")." : ".")))
        return added
    }

    private func persist(_ record: SessionRecord) async throws {
        if !persisted {
            try await store.create(session.header)
            persisted = true
            if mode != settings.defaultMode { try await store.append(.permissionMode(mode), to: session.header.id) }
            if !session.folders.isEmpty { try await store.append(.folders(session.folders), to: session.header.id) }
        }
        try await store.append(record, to: session.header.id)
    }

    /// This project's sessions, newest first.
    public func sessions() async throws -> [SessionSummary] {
        try await store.list().filter { Self.sameFolder($0.workspace, root) }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
