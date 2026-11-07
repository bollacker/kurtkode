import AgentCore
import Foundation
import Observation

/// One session's conversation and its in-flight agent run.
@MainActor @Observable
final class ChatController: Identifiable {
    unowned let app: AppModel
    var session: Session
    /// The model turn being generated, updated as it streams. Nil between turns and when idle.
    var streaming: TurnSnapshot?
    /// When the current turn started; drives the elapsed-time display between stream events.
    var streamStartedAt: Date?
    /// The tool currently running, if any.
    /// Tool calls running now (several when subagents run in parallel).
    private(set) var runningTools: [ToolCall] = []
    var runningTool: ToolCall? { runningTools.last }
    var runningToolIDs: Set<String> { Set(runningTools.map(\.id)) }
    /// When each running tool call started, for its elapsed time.
    private(set) var runningSince: [String: Date] = [:]
    /// When the run going now started.
    private(set) var runStartedAt: Date?
    /// A run ended while another session was showing: the sidebar marks this one until it's looked at.
    var unread = false
    /// How the last run ended, when it needs the user's attention (step limit).
    var lastStop: AgentStop?
    /// When the streaming snapshot was last shown (updates are throttled).
    @ObservationIgnored private var lastStreamPublish = Date.distantPast
    /// What was typed while the agent was working. Messages go in at its next step (queued input); commands wait for
    /// the run's end (`afterRun`).
    var queued: [String] = []
    /// Long pastes the draft holds as tokens. Kept for the session, so undoing a deleted token brings its text back too.
    private(set) var pastes: [PastedText] = []
    /// Why the last run stopped at a cost limit (`CostMeter.stopNote`), for the banner.
    var costLimitNote: String?
    /// Images attached to the next message.
    var pendingImages: [ImageAttachment] = []

    /// Whether the current model takes images: the profile's setting, else what its server reports, else yes (no
    /// for an LM Studio model it doesn't list).
    var acceptsImages: Bool {
        if let set = profile.supportsImages { return set }
        guard let kind = endpoint?.kind else { return true }
        return modelEntry?.acceptsImages(kind) ?? (kind != .lmstudio)
    }

    /// Adds an image (any format ImageIO reads) to the next message, downscaled and saved with the session.
    func attachImage(_ data: Data) {
        do {
            pendingImages.append(try ImageStore.save(data, in: app.sessionStore.imagesDirectory(for: session.header)))
        } catch {
            notice = error.localizedDescription
        }
    }
    /// Comments on lines of the change, waiting to go to the model together (`ReviewComment`).
    var reviewComments: [ReviewComment] = []

    /// Sends the comments as a message, or queues it while a run goes.
    func sendReviewComments() {
        guard !reviewComments.isEmpty else { return }
        let text = ReviewComment.message(reviewComments)
        reviewComments = []
        if task != nil { queued.append(text) } else { submit(text) }
    }

    /// A commit message for `diff`, from this chat's model. Files withheld from remote models stay out of what's sent, and
    /// the request is billed to the session like any other.
    func writeCommitMessage(diff: String) async -> String? {
        guard let endpoint else { return nil }
        let text = endpoint.isThirdParty ? UnifiedDiff.withholding(diff, patterns: Pref.run.withheldFromRemote).0 : diff
        let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
        let costs = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { [weak self] e in await self?.recordCost(e) }
        return await CommitMessage.write(diff: text, client: client, model: session.model,
                                         limits: Pref.run.limits(for: profile, api: endpoint.kind.api), costs: costs)
    }

    /// Keeps a long paste and gives the token that stands for it in the draft.
    func holdPaste(_ text: String) -> String {
        let paste = PastedText(id: (pastes.last?.id ?? 0) + 1, text: text)
        pastes.append(paste)
        return paste.token
    }

    /// How the last run ended.
    private var lastFinish: AgentStop?
    var draft = ""
    var permissionMode: PermissionMode
    /// "Always allow" choices, for this session while the app runs.
    var sessionRules: [AllowRule] = []
    /// A tool call waiting for the user's decision.
    /// Approvals waiting for the user, answered in order (subagents running at once can ask together).
    private(set) var approvals: [PendingApproval] = []
    /// The approval card shown now.
    var pendingApproval: PendingApproval? { approvals.first }
    /// Live output of running commands, by call id.
    var liveOutput: [String: String] = [:]
    let shell: ShellState
    private let checkpoints: CheckpointStore
    /// True while a summary is being made (automatic or /compact).
    var isCompacting = false
    /// Estimated size of the prompt most recently sent.
    var promptEstimate: Int?
    var notice: String?
    /// Held while this session runs, so the command line doesn't run it at the same time (`SessionLock`).
    private var runLock: SessionLock?
    /// Built once per session and mode, and reused (any change re-processes the whole conversation).
    @ObservationIgnored private let prompt = FrozenSystemPrompt()

    /// Questions from the model (`ask_user`) waiting for the user's answer, answered in order.
    private(set) var questions: [PendingQuestion] = []
    var pendingQuestion: PendingQuestion? { questions.first }

    /// Plans from the model (`present_plan`) waiting for the user's decision.
    private(set) var plans: [PendingPlan] = []
    #if DEBUG
    /// Plans answered by KURTKODE_AUTOPLAN so far.
    @ObservationIgnored private var autoPlanCount = 0
    #endif
    var pendingPlan: PendingPlan? { plans.first }

    struct PendingPlan: Identifiable {
        let proposal: PlanProposal
        let resume: (PlanDecision) -> Void
        let id: UUID
    }

    struct PendingQuestion: Identifiable {
        let questions: [UserQuestion]
        let resume: ([String?]) -> Void
        let id: UUID
    }

    struct PendingApproval: Identifiable {
        let request: ApprovalRequest
        let resume: (ApprovalDecision) -> Void
        var id: String { request.id }
    }
    private var task: Task<Void, Never>?
    /// Session writes run one after another, in the order they were made.
    private var lastWrite: Task<Void, Never>?
    /// False until the session file exists; it's created with the first record.
    private(set) var isPersisted: Bool

    nonisolated var id: UUID { sessionID }
    private nonisolated let sessionID: UUID
    /// The session's subagent runs, oldest first: stored ones, then live ones as they start and go.
    var subagents: [SubagentRow] = []
    /// Runs in `subagents` that a fork copied from its original (not this session's spending).
    var inheritedRuns: Set<UUID> = []
    /// Stops one subagent run while the main agent goes on.
    let subagentControl = SubagentControl()

    init(app: AppModel, session: Session, isPersisted: Bool = true) {
        self.app = app
        self.session = session
        self.isPersisted = isPersisted
        sessionID = session.header.id
        permissionMode = session.permissionMode
            ?? PermissionMode(rawValue: Pref.d.string(forKey: Pref.defaultPermissionMode) ?? "") ?? .ask
        let root = session.header.workspace.map { URL(fileURLWithPath: $0) }
            ?? Pref.chatFolder ?? FileManager.default.homeDirectoryForCurrentUser
        shell = ShellState(cwd: root)
        checkpoints = CheckpointStore(directory: app.sessionStore.checkpointDirectory(for: session.header))
        #if DEBUG
        // KURTKODE_FOLDERS=/path:rw,/path2:ro: give the session these extra folders (when it has none yet).
        if self.session.folders.isEmpty, let spec = ProcessInfo.processInfo.environment["KURTKODE_FOLDERS"] {
            for item in spec.split(separator: ",") {
                let parts = item.split(separator: ":").map(String.init)
                addFolder(URL(fileURLWithPath: parts[0]), writable: parts.count > 1 && parts[1] == "rw")
            }
        }
        #endif
        // Start the project's MCP servers now, so their tools are ready by the first message.
        if let ws = session.header.workspace { app.mcpHub(for: ws) }
        _ = loadHooks()          // notices a project's hooks that need approval
        _ = loadPermissionRules()   // and its allow rules
        if isPersisted { Task { await loadSubagents(); await noteFileSize() } }
    }

    /// What the session has spent: every billed request of it (its cost records: replies, summaries, retried attempts)
    /// and of its subagents, at the charge where the server said it and list price otherwise; whether any of it is an
    /// estimate; and the session's own requests summed (for the toolbar's tooltip). Nil while nothing has a cost.
    var sessionCost: (dollars: Double, estimate: Bool, own: CostSummary, subagents: Double)? {
        let own = CostSummary(session.costs)
        let subs = subagents.filter { !inheritedRuns.contains($0.id) }.map(\.cost).reduce(0, +)
        let dollars = own.spent + subs
        guard dollars > 0 else { return nil }
        return (dollars, own.estimated || subs > 0, own, subs)
    }

    /// The runs already recorded for this session (a run with no end that isn't going now was cut off).
    func loadSubagents() async {
        let runs = await app.sessionStore.subagentRuns(of: session.header)
        // A fork's copies of the original's runs are shown, but their spending was the original's.
        inheritedRuns = Set(runs.filter { $0.header.parent.map { $0 != session.header.id } ?? false }.map(\.header.id))
        let live = subagentControl.running
        let stored = runs.map { r in
            var row = SubagentRow(SubagentRunSummary(r), interrupted: r.subagentEnd == nil && !live.contains(r.header.id))
            row.judgments = r.judgments
            return row
        }
        let known = Set(stored.map(\.id))
        subagents = stored + subagents.filter { !known.contains($0.id) }
    }

    /// The user's thumbs on a main run (the reply's 👍/👎, /good, /bad), kept in the session; a second click on the same
    /// thumb takes it back (recorded as a judgment without a verdict, so the history stays whole).
    func rateRun(_ run: UUID, up: Bool, note: String = "", toggle: Bool = true) {
        var j = MainRunJudgments.thumbs(run: run, up: up, note: note)
        if toggle, session.thumbs(run) == up { j.verdict = nil; j.note = "withdrawn" }
        session.judgments.append(j)
        persist(.judgment(j))
        if !up, j.verdict != nil, Pref.run.escalationOffers {
            offerEscalation(run: session.runs.first { $0.id == run }, reasons: ["you marked the reply wrong"], source: "user")
        }
    }

    /// A retry or rewind: an implicit 0 for the main run whose reply goes away.
    private func noteImplicit(_ run: AgentRunRecord?, why: String) {
        guard let run else { return }
        let j = MainRunJudgments.implicit(run: run.id, why: why)
        session.judgments.append(j)
        persist(.judgment(j))
    }

    /// The user's judgment of a subagent run: in the run's own session and, as a copy, in this one. It counts most.
    func judgeSubagent(_ id: UUID, verdict: Int) {
        guard let i = subagents.firstIndex(where: { $0.id == id }) else { return }
        let j = RunJudgment(run: id, judge: .user, verdict: verdict, checked: RunJudgment.Checked.readTheFiles.rawValue)
        subagents[i].judgments.append(j)
        session.judgments.append(j)
        persist(.judgment(j))
        let store = app.sessionStore, parent = session.header
        Task { try? await store.append(.judgment(j), toRun: id, of: parent) }
    }

    /// Stops one subagent: its report says it was stopped, and the main agent goes on.
    func stopSubagent(_ id: UUID) {
        subagentControl.stop(id)
    }

    var isGenerating: Bool { task != nil || reloading }

    // MARK: Changes made by another kurtkode

    /// True while the session is reloaded before a send.
    private var reloading = false
    /// The session file's size when this app last read or wrote it (mirrors the store's, for a quick check).
    @ObservationIgnored private var knownFileSize: UInt64?

    /// A quick check (one stat) that the session file isn't the size this app left it.
    private var mayHaveChangedElsewhere: Bool {
        guard isPersisted, pendingWrites == 0, let known = knownFileSize,
              let size = (try? FileManager.default.attributesOfItem(atPath: app.sessionStore.fileURL(for: session.header).path))?[.size]
                as? NSNumber else { return false }
        return size.uint64Value != known
    }
    /// This app's session writes not finished yet (the file is behind until they are).
    @ObservationIgnored private var pendingWrites = 0

    /// Reloads the session when another process (the command line shares sessions) appended to its file since this
    /// app last read it. Only while idle: a run goes on with the history it started with. Returns whether it did.
    /// `holdingLock`: called by `locked` for its own operation, whose task may already be set, before it changes anything.
    @discardableResult
    func reloadIfChangedElsewhere(holdingLock: Bool = false) async -> Bool {
        guard isPersisted, task == nil || holdingLock else { return false }
        await lastWrite?.value
        let store = app.sessionStore
        guard await store.changedElsewhere(id), task == nil || holdingLock, let fresh = try? await store.load(id) else {
            knownFileSize = await store.knownSize(id) ?? knownFileSize
            return false
        }
        knownFileSize = await store.knownSize(id)
        let added = fresh.messages.count - session.messages.count
        var s = fresh
        // A model on a server this app doesn't know (the command line's one-run --endpoint) stays as it was here.
        if app.endpoint(s.endpointID) == nil {
            s.model = session.model
            s.endpointID = session.endpointID
        }
        session = s
        if let m = s.permissionMode { permissionMode = m }
        app.updateSummary(for: session)
        await loadSubagents()
        notice = "This session was changed by another kurtkode (the command line?), so it was reloaded"
            + (added > 0 ? ": \(added) new message\(added == 1 ? "" : "s")." : ".")
        return true
    }

    /// Records the store's view of the file after this app's own load or write.
    func noteFileSize() async {
        knownFileSize = await app.sessionStore.knownSize(id)
    }
    /// The endpoint and model the next turn uses. A session can move between models and servers.
    var endpoint: Endpoint? { app.endpoint(session.endpointID) }
    var modelEntry: ModelEntry? { app.catalogs[session.endpointID]?.entry(session.model) }
    var profile: ModelProfile {
        var p = app.profile(session.endpointID, session.model)
        // An escalation to a pool entry carries its provider pins and reasoning, where the profile sets none.
        if let o = escalatedProfile, o.key == ModelProfile.key(session.endpointID, session.model) {
            if p.providers == nil { p.providers = o.providers }
            if p.reasoning == nil { p.reasoning = o.reasoning }
        }
        return p
    }
    /// The pool entry's settings for the model an escalation switched to, for this window.
    private var escalatedProfile: (key: String, providers: ProviderRouting?, reasoning: String?)?

    /// Set when the next turn uses a different model than the last reply: the new model has no prompt
    /// cache for this conversation, so its first reply re-processes all of it.
    var switchNotice: String? {
        guard let last = session.messages.last(where: { $0.role == .assistant && $0.meta != nil })?.meta else { return nil }
        let lastEndpoint = last.endpointID ?? session.header.endpointID
        guard last.requestedModel != session.model || lastEndpoint != session.endpointID else { return nil }
        let tokens = contextUsed.map { " (about \(ContextMeter.tokens($0)) tokens)" } ?? ""
        return "Switched from \(last.requestedModel) to \(session.model). Its first reply re-reads the whole conversation\(tokens)."
    }
    /// Where the agent works: the project, or for a plain chat its working folder (Settings), plus the session's
    /// extra folders. Nil for a chat when chats don't get tools.
    var workspace: Workspace? {
        if let path = session.header.workspace { return Workspace(path: path, folders: session.folders) }
        return Pref.chatFolder.map { Workspace(root: $0, folders: session.folders) }
    }
    /// A plain chat (no project), possibly with a working folder.
    var isChat: Bool { session.header.workspace == nil }

    // MARK: Folders

    /// Lets the agent use another folder (read-only unless `writable`); replaces the same folder's earlier setting.
    func addFolder(_ url: URL, writable: Bool) {
        let folder = ExtraFolder(path: url.path, writable: writable)
        if let ws = workspace, ws.contains(folder.url) {
            notice = "\(folder.displayPath) is already inside \(isChat ? "the working folder" : "the project")."
            return
        }
        setFolders(session.folders.filter { $0.path != folder.path } + [folder])
    }

    func setWritable(_ folder: ExtraFolder, _ writable: Bool) {
        setFolders(session.folders.map { $0.path == folder.path ? ExtraFolder(path: $0.path, writable: writable) : $0 })
    }

    func removeFolder(_ folder: ExtraFolder) {
        setFolders(session.folders.filter { $0.path != folder.path })
    }

    private func setFolders(_ folders: [ExtraFolder]) {
        guard folders != session.folders else { return }
        session.folders = folders
        persist(.folders(folders))
    }

    /// A chat's working folder is made the first time the agent needs it.
    private func ensureChatFolder() {
        guard isChat, let root = workspace?.root else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Tools offered to the model: in a project, whatever the permission mode allows; none in a plain chat.
    var tools: [any Tool] {
        guard workspace != nil, profile.supportsTools ?? modelEntry?.supportsTools ?? true else { return [] }
        return PermissionPolicy(mode: permissionMode).offered(AllTools.all)
    }

    /// Why sending is blocked, if it is.
    var sendBlocker: String? {
        guard let endpoint else { return "This session's endpoint was deleted." }
        if sessionFileGone { return "This session's file is gone (moved to the Trash?): start a new chat." }
        if case .unreachable = app.catalogs[endpoint.id]?.reachability { return "\(endpoint.name) isn't responding." }
        // LM Studio would load an unloaded model on demand with a small default context; load it ourselves.
        if endpoint.kind == .lmstudio, let entry = modelEntry, !entry.isLoaded { return "\(session.model) isn't loaded." }
        if let ws = session.header.workspace, !FileManager.default.fileExists(atPath: ws) {
            return "The project folder \(ws) no longer exists."
        }
        return nil
    }

    /// Tokens the conversation uses now: the latest prompt estimate while running, else the last turn's
    /// reported size (prompt plus reply), unless a compaction came after it.
    var contextUsed: Int? {
        if isGenerating, let promptEstimate { return promptEstimate }
        let lastUsage = session.messages.lastIndex(where: { $0.meta?.usage != nil })
        if let c = session.activeCompaction,
           let boundary = session.messages.firstIndex(where: { $0.id == c.lastSummarizedID }),
           lastUsage.map({ $0 <= boundary + 2 }) ?? true {
            return c.tokensAfter
        }
        return lastUsage.flatMap { session.messages[$0].meta?.usage?.totalTokens }
    }

    var contextLimit: Int? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["KURTKODE_CONTEXT_LIMIT"].flatMap(Int.init) { return override }
        #endif
        // OpenAI-style servers don't report it; without a budget nothing is ever compacted, so assume the
        // default context length (as the command line and the eval do) until one is set.
        let fallback = Pref.d.integer(forKey: Pref.defaultContextLength)
        // A context an OpenAI-compatible server lists (OpenRouter, vLLM, Ollama) only lowers the default: OpenRouter lists
        // each model's largest provider window, and a bigger budget means bigger requests (as the command line does).
        if endpoint?.kind == .openai, endpoint?.manualContextLength == nil, profile.contextLength == nil, let listed = modelEntry?.contextLength {
            return min(listed, fallback)
        }
        return profile.contextLength ?? modelEntry?.contextLength ?? endpoint?.manualContextLength
            ?? (endpoint.map { $0.kind != .lmstudio } == true ? fallback : nil)
    }

    /// The agent's current todo list: the last successful todo_write in the session.
    var todos: [TodoWriteTool.Item] {
        let results = Dictionary(session.messages.compactMap { m in m.toolCallID.map { ($0, m) } }, uniquingKeysWith: { _, b in b })
        for m in session.messages.reversed() where m.role == .assistant {
            for c in m.toolCalls.reversed() where c.name == "todo_write" {
                guard results[c.id]?.toolResult?.isError == false,
                      let args = try? ToolArguments(json: c.arguments),
                      let items = try? TodoWriteTool.items(from: args) else { continue }
                return items
            }
        }
        return []
    }

    /// The project's snapshots (C1): the shadow repository the runs' snapshots go to; nil without a folder.
    var snapshots: ProjectSnapshots? { workspace.flatMap { app.sessionStore.snapshots(for: $0.root) } }

    /// Files the agent edited in this session, with the diffs of each edit.
    var changedFiles: [(path: String, diffs: [String])] {
        var order: [String] = []
        var diffs: [String: [String]] = [:]
        let results = Dictionary(session.messages.compactMap { m in m.toolCallID.map { ($0, m) } }, uniquingKeysWith: { _, b in b })
        for m in session.messages where m.role == .assistant {
            for c in m.toolCalls where c.name == "edit_file" || c.name == "write_file" {
                guard let r = results[c.id]?.toolResult, !r.isError, let diff = r.display,
                      let path = (try? ToolArguments(json: c.arguments))?.string("path") else { continue }
                if diffs[path] == nil { order.append(path) }
                diffs[path, default: []].append(diff)
            }
        }
        return order.map { ($0, diffs[$0] ?? []) }
    }

    /// Takes the latest queued item back to edit it; false when nothing is queued.
    func takeBackQueued() -> Bool {
        guard let last = queued.popLast() else { return false }
        draft = last
        return true
    }

    /// The pencil on a queued item: back in the draft, ahead of what's being typed there.
    func editQueued(at i: Int) {
        guard i < queued.count else { return }
        restoreToDraft(queued.remove(at: i))
    }

    private func restoreToDraft(_ text: String) { draft = joinedDraft([text, draft]) }

    private static func isCommand(_ text: String) -> Bool {
        SlashCommands.parse(text) != nil || UserShell.command(in: text) != nil
    }

    /// `keeping`: what was being typed when ↑ put an earlier prompt in the draft. It's back once that's sent.
    func send(keeping waiting: String = "") {
        keptDraft = waiting
        // Another kurtkode (the command line) may have added to this session: pick that up first, so this message
        // goes on top of the whole conversation, not the copy this window loaded.
        if task == nil, !reloading, mayHaveChangedElsewhere {
            reloading = true
            Task {
                await reloadIfChangedElsewhere()
                reloading = false
                sendNow()
            }
            return
        }
        sendNow()
    }

    @ObservationIgnored private var keptDraft = ""

    private func sendNow() {
        defer {
            if draft.isEmpty { draft = keptDraft }
            keptDraft = ""
        }
        let text = PastedText.text(of: draft, pastes)
        guard !text.isEmpty || (!pendingImages.isEmpty && task == nil) else { return }
        // "# fact": kept in the project's memory, not sent (B6); at once, even while the agent runs. Not with images
        // attached: then it's a message.
        if pendingImages.isEmpty, let note = Memory.note(in: text), let root = workspace?.root {
            do {
                let url = try Memory.remember(note, root: root)
                draft = ""
                notice = "Remembered \"\(note)\" in \(url.path). Later sessions in this project will have it (/memory shows them)."
            } catch { notice = "Couldn't save it: \(error.localizedDescription)" }
            return
        }
        if task != nil {
            if let (name, arguments) = SlashCommands.parse(text) {
                guard let command = commands.first(where: { $0.name == name }) else {
                    notice = "There's no /\(name) command. Type /help to see the list."
                    return
                }
                if SlashCommands.answersWhileRunning.contains(name) {
                    run(command, arguments: arguments)
                    return
                }
            }
            // Queued, it would go later, and the images might then go with something else.
            if !pendingImages.isEmpty {
                notice = "An image goes with a message once the run is done: send it then."
                return
            }
            queued.append(text)
            draft = ""
            return
        }
        dispatch(text)
    }

    /// Runs what was typed, while nothing else is going: a command, a `!command`, or a message for the model. False when
    /// it was refused, with a notice: a queued item then has to go back to the user. `fromDraft`: it's what's in the draft.
    @discardableResult
    private func dispatch(_ text: String, fromDraft: Bool = true) -> Bool {
        // The command line may be running this session: say so before the message is saved (`SessionLock`).
        if let who = SessionLock.holder(app.sessionStore.lockURL(for: session.header.id)) {
            notice = SessionLock.busyMessage(who)
            return false
        }
        if let (name, arguments) = SlashCommands.parse(text) {
            guard let command = commands.first(where: { $0.name == name }) else {
                notice = "There's no /\(name) command. Type /help to see the list."
                return false
            }
            run(command, arguments: arguments)
            return true
        }
        if let command = UserShell.command(in: text) {
            runUserCommand(command)
            return true
        }
        // A large session whose prompt cache has expired: say what the next message costs, and what /compact or a new
        // session would, once; sending again goes ahead (CACHING_PLAN.md 1.7).
        if fromDraft, let last = session.lastReplyCost, coldWarned != last.id, let note = CacheLedger.coldResumeNote(last: last) {
            coldWarned = last.id
            notice = note + " Send again to go ahead."
            return false
        }
        return submit(text, fromDraft: fromDraft)
    }

    /// The last reply whose expired cache the user was told about (`CacheLedger.coldResumeNote`).
    @ObservationIgnored private var coldWarned: UUID?

    /// Sends a message to the model. Files and folders it mentions with `@` go in first, as read_file and
    /// list_dir results (only for models with tools: a tool-less model can't take tool messages).
    @discardableResult
    private func submit(_ text: String, fromDraft: Bool = true) -> Bool {
        let text = PastedText.withoutMark(text)
        if let blocker = sendBlocker { notice = blocker; return false }
        setAside()                          // a new message moves past the offer
        if !pendingImages.isEmpty, !acceptsImages {
            notice = "\(shortName(session.model)) can't see images. Remove them, switch to a vision model, "
                + "or turn Images on in this model's settings."
            return false
        }
        // UserPromptSubmit hooks can block the message (it stays in the composer) or add context to it.
        if let hooks = loadHooks(), hooks.matchers[.userPromptSubmit]?.isEmpty == false {
            if fromDraft { draft = "" }
            task = Task {
                let outcome = await hooks.userPromptSubmit(text)
                let stopped = Task.isCancelled
                task = nil
                if let e = outcome.errors.first { notice = e }
                if outcome.blocked || stopped {
                    // Messages queued while the hook ran go back into the draft (they were typed after this one).
                    afterRun(stopped: true)
                    restoreToDraft(text)
                    if outcome.blocked { notice = "A hook blocked this message: " + (outcome.reason ?? "no reason given") }
                    return
                }
                // The hook's context is a note of its own, not part of the message: the bubble, recall and rewind stay the user's words.
                deliver(text, fromDraft: false, hookContext: outcome.context)
            }
            return true
        }
        deliver(text, fromDraft: fromDraft)
        return true
    }

    /// Reads the hooks for this session's project (the user's, plus the project's once approved), and notes
    /// project hooks that wait for approval.
    func loadHooks() -> Hooks? {
        guard let ws = workspace else { return nil }
        let (hooks, pending, problem) = Hooks.load(workspace: ws.root, approvals: app.hookApprovals, sessionID: session.header.id.uuidString,
                                                   transcriptPath: app.sessionStore.fileURL(for: session.header).path)
        pendingProjectHooks = pending
        hookProblem = problem
        return hooks.isEmpty ? nil : hooks
    }

    /// Allow, ask, and deny rules from the user's and the project's settings files; notes the project's allow rules
    /// while they wait for approval (its deny and ask rules apply at once).
    func loadPermissionRules() -> PermissionRules {
        let (rules, pending, problem) = PermissionRules.load(root: workspace?.root, approvals: app.permissionApprovals)
        pendingProjectRules = pending.map { PendingRules(fingerprint: $0.fingerprint, rules: $0.rules) }
        if let problem { hookProblem = problem }
        return rules
    }

    struct PendingRules: Equatable { var fingerprint: String; var rules: [String] }
    var pendingProjectRules: PendingRules?

    func approveProjectRules() {
        guard let root = workspace?.root, let pending = pendingProjectRules else { return }
        do {
            try app.permissionApprovals.approve(pending.fingerprint, workspace: root)
            pendingProjectRules = nil
        } catch { notice = error.localizedDescription }
    }

    /// The project's hooks, while they wait for the user's approval.
    var pendingProjectHooks: HookConfig?
    var hookProblem: String?

    func approveProjectHooks() {
        guard let ws = workspace, let pending = pendingProjectHooks else { return }
        do {
            try app.hookApprovals.approve(pending, workspace: ws.root)
            pendingProjectHooks = nil
        } catch { notice = error.localizedDescription }
    }

    private func deliver(_ text: String, fromDraft: Bool = true, hookContext: [String] = []) {
        // The run's lock, taken before the message is saved: the command line may have started on this session since
        // `dispatch` looked, and the message mustn't land in the middle of its turn.
        guard takeRunLock() else {
            if !fromDraft { restoreToDraft(text) }
            return
        }
        if fromDraft { draft = "" }
        var message = ChatMessage.user(text)
        if !pendingImages.isEmpty {
            message.images = pendingImages
            pendingImages = []
        }
        append(message)
        if !hookContext.isEmpty {
            append(FrozenSystemPrompt.noteMessage("[Context from a hook]\n" + hookContext.joined(separator: "\n")))
        }
        ensureChatFolder()
        guard let workspace, !tools.isEmpty else { generate(); return }
        let mentions = Mentions.find(in: text, workspace: workspace)
        guard !mentions.isEmpty else { generate(); return }
        let shell = shell
        task = Task {
            let attached = await Mentions.messages(for: mentions, workspace: workspace, shell: shell)
            task = nil
            guard !Task.isCancelled else { releaseRunLock(); afterRun(stopped: true); return }
            for m in attached { append(m) }
            generate()
        }
    }

    /// `!command`: runs it for the user and adds the output to the conversation, without a reply.
    private func runUserCommand(_ command: String) {
        guard let workspace else { notice = "!commands need a project folder."; return }
        draft = ""
        notice = "Running \(command)…"
        lastFinish = nil
        let shell = shell
        task = Task {
            do {
                try await locked {
                    let message = await UserShell.run(command, workspace: workspace, shell: shell)
                    append(message)
                }
                notice = nil
            } catch { notice = error.localizedDescription }
            task = nil
            afterRun(stopped: Task.isCancelled)
        }
    }

    /// Runs an operation that adds to or restores the session while holding its lock (`SessionLock.withLock`), after
    /// picking up what the command line wrote, so the two can't interleave records; its records are written before the
    /// lock goes. Throws `SessionBusy` (the "running in another kurtkode" message) when it's held.
    private func locked<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        try await SessionLock.withLock(app.sessionStore.lockURL(for: session.header.id),
                                       holder: SessionLock.describe("the kurtkode app"),
                                       reload: { await self.reloadIfChangedElsewhere(holdingLock: true) }) {
            let result = try await body()
            await lastWrite?.value
            return result
        }
    }

    /// Takes the session's lock for a run (`generate` releases it when the run ends); false, with a notice, when another
    /// kurtkode holds it.
    private func takeRunLock() -> Bool {
        guard runLock == nil else { return true }
        switch SessionLock.acquire(app.sessionStore.lockURL(for: session.header.id), holder: SessionLock.describe("the kurtkode app")) {
        case .held(let who):
            notice = SessionLock.busyMessage(who)
            return false
        case .acquired(let lock):
            runLock = lock
            return true
        }
    }

    private func releaseRunLock() {
        runLock?.release()
        runLock = nil
    }

    /// The model a subagent runs on: its definition's `model:` ("model" or "endpoint|model"), else the
    /// Subagent model setting, else (on automatic) the pool's entry for the card's tier when the session's model is
    /// remote (`SubagentRouting`), else nil (the session's model). A local model that isn't loaded is loaded
    /// first, with the usual memory checks; if that fails, the subagent uses the session's model.
    func subagentModel(for agent: AgentDefinition, card: TaskCard) async -> SubagentModel? {
        let run = Pref.run
        if agent.model == nil, run.subagentModel == nil, run.subagentAutomatic {
            guard let main = endpoint,
                  let r = SubagentRouting.automatic(card: card, main: main, mainModel: session.model, pool: app.pool,
                                                    endpoints: app.endpoints) else { return nil }
            return await model(for: r)
        }
        var ref: ModelRef?
        if let spec = agent.model, ModelAlias.isAlias(spec) {
            ref = ModelAlias.resolve(spec, endpoints: app.endpoints).map { ModelRef(endpointID: $0.endpoint.id, model: $0.model) }
        } else if let spec = agent.model {
            let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let e = app.endpoints.first(where: { $0.name.lowercased() == parts[0].lowercased() }) {
                ref = ModelRef(endpointID: e.id, model: parts[1])
            } else {
                let id = parts.last ?? spec
                let owner = app.catalogs[session.endpointID]?.entry(id) != nil ? session.endpointID
                    : app.endpoints.first(where: { app.catalogs[$0.id]?.entry(id) != nil })?.id
                ref = owner.map { ModelRef(endpointID: $0, model: id) }
            }
        } else {
            ref = Pref.run.subagentModel
        }
        guard let ref, !(ref.endpointID == session.endpointID && ref.model == session.model) else { return nil }
        return await model(for: ref)
    }

    /// A pool entry, ready to send to: its model's settings with the entry's reasoning and provider pins.
    func model(for r: ResolvedPoolEntry) async -> SubagentModel? {
        guard var m = await model(for: ModelRef(endpointID: r.endpoint.id, model: r.model)) else { return nil }
        if let reasoning = r.entry.reasoning { m.reasoning = reasoning }
        if let providers = r.entry.providers { m.providers = providers }
        return m
    }

    /// A saved model on its endpoint, ready to send to (a local one is loaded first, with the memory checks).
    func model(for ref: ModelRef) async -> SubagentModel? {
        guard let endpoint = app.endpoint(ref.endpointID) else { return nil }
        if endpoint.kind == .lmstudio, endpoint.isLocal, app.catalogs[endpoint.id]?.entry(ref.model)?.isLoaded != true {
            do { try await app.loadModel(ref.model, on: endpoint.id, contextLength: Pref.d.integer(forKey: Pref.defaultContextLength)) }
            catch { return nil }
        }
        let profile = app.profile(ref.endpointID, ref.model)
        let entry = app.catalogs[endpoint.id]?.entry(ref.model)
        let images = profile.supportsImages ?? entry?.acceptsImages(endpoint.kind) ?? (endpoint.kind != .lmstudio)
        return SubagentModel(client: ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint)), model: ref.model,
                             historyShape: profile.history,
                             contextLimit: profile.contextLength ?? endpoint.manualContextLength
                                ?? entry?.contextLength.map { endpoint.kind == .openai ? min($0, Pref.d.integer(forKey: Pref.defaultContextLength)) : $0 },
                             temperature: profile.temperature, endpointID: endpoint.id, sendImages: images,
                             reasoning: profile.reasoning, providers: profile.providers)
    }

    /// Hands queued messages to the running agent (with their @ mentions attached). Edits after them are
    /// snapshotted under the first of them, so rewinding to it undoes exactly what came after.
    private func takeQueued(_ turnKey: TurnKey) async -> [ChatMessage] {
        // Up to the first command: what was typed after that stays behind it.
        let texts = queued.prefix { !Self.isCommand($0) }.map(PastedText.withoutMark)
        guard !texts.isEmpty else { return [] }
        queued.removeFirst(texts.count)
        var out: [ChatMessage] = []
        for text in texts {
            let message = ChatMessage.user(text)
            if out.isEmpty { turnKey.id = message.id }
            out.append(message)
            if let workspace, !tools.isEmpty {
                out += await Mentions.messages(for: Mentions.find(in: text, workspace: workspace), workspace: workspace, shell: shell)
            }
        }
        return out
    }

    /// After a run or a command: what's still queued goes if it finished normally, in the order typed, messages in a
    /// row as one request; a run it starts brings this back at its end. Otherwise (stopped, denied, paused at the step
    /// limit) it goes back into the draft, so nothing is lost or sent unasked.
    private func afterRun(stopped: Bool = false) {
        guard !queued.isEmpty else { return }
        // What's being typed stays: sending clears the draft.
        let typed = draft
        defer { if draft.isEmpty { draft = typed } }
        func putBack() {
            draft = joinedDraft(queued + [typed])
            queued = []
        }
        guard !stopped, lastFinish == nil || lastFinish == .completed || lastFinish == .truncated else { return putBack() }
        while task == nil, let first = queued.first {
            if Self.isCommand(first) {
                queued.removeFirst()
                if !dispatch(first, fromDraft: false) {
                    queued.insert(first, at: 0)
                    return putBack()
                }
                continue
            }
            if sendBlocker != nil { return putBack() }
            let messages = queued.prefix { !Self.isCommand($0) }.map(PastedText.withoutMark)
            queued.removeFirst(messages.count)
            let text = messages.joined(separator: "\n\n")
            if !dispatch(text, fromDraft: false) {
                queued.insert(text, at: 0)
                return putBack()
            }
        }
    }

    /// Project files for `@` completion, listed at most every 30 seconds.
    private(set) var fileIndex: [String] = []
    private var fileIndexAt: Date?
    func refreshFileIndex() {
        guard let workspace, fileIndexAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true else { return }
        fileIndexAt = Date()
        Task { fileIndex = await workspace.files(limit: 20_000) }
    }

    /// Built-in commands, then custom ones from `.md` files (read from disk each time, so edits show up).
    var commands: [SlashCommand] { SlashCommands.all(workspace: workspace?.root, builtinSkills: Skills.builtin(Pref.run.builtinSkills)) }

    /// Runs a slash command. Those that only change the app work even when the model can't be reached.
    func run(_ command: SlashCommand, arguments: String) {
        notice = nil
        func sendToModel(_ text: String) { submit(text) }
        if case .custom(let template, _) = command.kind {
            sendToModel(SlashCommands.expand(template, arguments: arguments))
            return
        }
        draft = ""
        switch command.name {
        case "help":
            notice = commands.map { c in
                "/\(c.name)\(c.argumentHint.isEmpty ? "" : " " + c.argumentHint)  \(c.description)"
                    + (c.isBuiltIn ? "" : "  (custom)")
            }.joined(separator: "\n")
        case "clear":
            Task { _ = try? await app.newSession(endpointID: session.endpointID, model: session.model,
                                                 workspace: session.header.workspace, select: true) }
        case "compact":
            if let blocker = sendBlocker { notice = blocker } else { compactNow(focus: arguments) }
        case "context":
            notice = contextSummary
        case "btw":
            guard !arguments.isEmpty else { notice = "Give the question: /btw <question>."; break }
            guard let endpoint else { break }
            notice = "Asking on the side…"
            let app = app, messages = session.messages, model = session.model, limits = Pref.run.limits(for: profile, api: endpoint.kind.api)
            Task { [weak self] in
                let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
                let costs = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { [weak self] e in await self?.recordCost(e) }
                let answer = await SideQuestion.ask(arguments, messages: messages, client: client, model: model, limits: limits, costs: costs)
                self?.notice = answer.map { "On the side: " + $0 } ?? "The side question got no answer."
            }
        case "agents":
            Pref.d.set(InspectorView.Tab.agents.rawValue, forKey: "inspectorTab")
            Pref.d.set(true, forKey: "showInspector")
            notice = subagents.isEmpty ? "No subagent runs in this session yet."
                : "\(subagents.count) subagent run\(subagents.count == 1 ? "" : "s"), listed in the inspector's Agents tab."
        case "skills":
            notice = Skills.listing(root: workspace?.root, builtin: Skills.builtin(Pref.run.builtinSkills))
        case "model":
            switchModel(named: arguments)
        case "mode":
            let modes: [String: PermissionMode] = ["ask": .ask, "edits": .acceptEdits, "acceptedits": .acceptEdits,
                                                   "plan": .plan, "auto": .fullAuto, "fullauto": .fullAuto]
            if let mode = modes[arguments.lowercased().replacingOccurrences(of: " ", with: "")] {
                setPermissionMode(mode)
                notice = "Permission mode: \(mode.displayName)."
            } else {
                notice = "Permission mode is \(permissionMode.displayName). Use /mode ask, edits, plan, or auto."
            }
        case "init":
            if workspace == nil { notice = "/init needs a project folder." } else { sendToModel(SlashCommands.initPrompt) }
        case "retry":
            if let blocker = sendBlocker { notice = blocker } else { retry() }
        case "rename":
            if arguments.isEmpty { notice = "Give the new title: /rename <title>." } else { rename(arguments) }
        case "memory":
            if let root = workspace?.root { notice = Memory.listing(root: root) } else { notice = "/memory needs a project folder." }
        case "diff":
            guard let snaps = snapshots else { notice = "/diff needs a project folder."; break }
            Pref.d.set(InspectorView.Tab.changes.rawValue, forKey: "inspectorTab")
            Pref.d.set(true, forKey: "showInspector")
            let scope: ProjectSnapshots.Scope = arguments.lowercased().hasPrefix("s") ? .session : .lastRun
            let id = session.header.id
            Task {
                // The file list here; the diffs are in the Changes tab.
                let text = (try? await snaps.report(session: id, scope: scope, maxBytes: 0)) ?? "No snapshots."
                notice = text.components(separatedBy: "\n\n").first
            }
        case "review":
            Pref.d.set(InspectorView.Tab.changes.rawValue, forKey: "inspectorTab")
            Pref.d.set(true, forKey: "showInspector")
            startReview(arguments.lowercased().hasPrefix("s") ? .session : .lastRun)
        case "escalate":
            if isGenerating { notice = "Wait for the reply to finish, or stop it."; break }
            setAside()
            offerEscalation(run: session.latestReplyRun, reasons: ["you asked to escalate" + (arguments.isEmpty ? "" : ": " + arguments)],
                            source: "asked", unknownTier: .standard)
            if escalation != nil { acceptEscalation() }
        case "rewind":
            let points = session.messages.filter { $0.role == .user && $0.contextNote != true }
            let words = arguments.split(separator: " ")
            if let n = words.first.flatMap({ Int($0) }), points.indices.contains(n - 1) {
                rewindRequest = points[n - 1].id
            } else {
                Pref.d.set(InspectorView.Tab.changes.rawValue, forKey: "inspectorTab")
                Pref.d.set(true, forKey: "showInspector")
                notice = "Pick a request in the Changes tab's Checkpoints (or /rewind N, N from 1 to \(points.count)), or use a message's Rewind button."
            }
        case "good", "bad":
            if let run = session.latestReplyRun {
                rateRun(run.id, up: command.name == "good", note: arguments, toggle: false)
                notice = command.name == "good" ? "Marked the last reply as right." : "Marked the last reply as wrong."
            } else {
                notice = "There's no reply to rate yet."
            }
        default:
            notice = "/\(command.name) isn't available here."
        }
    }

    private var contextSummary: String {
        guard let limit = contextLimit else { return "The context length of \(session.model) isn't known." }
        let used = contextUsed ?? 0
        let budget = ContextBudget(limit: limit, outputReserve: Pref.run.limits(for: profile, api: endpoint?.kind.api ?? .openai).maxTokens)
        return "Context: about \(ContextMeter.tokens(used)) of \(ContextMeter.tokens(limit)) tokens "
            + "(\(used * 100 / max(1, limit))%). The conversation is summarized at about "
            + "\(ContextMeter.tokens(budget.compactThreshold)); /compact does it now."
    }

    /// `/model name`: the model whose id matches exactly, else the only one containing the name (loaded
    /// models and this session's endpoint first).
    private func switchModel(named query: String) {
        guard !query.isEmpty else {
            notice = "This chat uses \(session.model). Type /model <name>, or pick one from the model menu."
            return
        }
        let q = query.lowercased()
        var candidates: [(endpoint: Endpoint, entry: ModelEntry)] = []
        for e in app.endpoints { for m in app.catalogs[e.id]?.entries ?? [] { candidates.append((e, m)) } }
        let exact = candidates.filter { $0.entry.id.lowercased() == q }
        var found = exact.isEmpty ? candidates.filter { $0.entry.id.lowercased().contains(q) } : exact
        if found.count > 1 {
            let preferred = found.filter { $0.entry.isLoaded || $0.endpoint.id == session.endpointID }
            if preferred.count == 1 { found = preferred }
        }
        switch found.count {
        case 0:
            notice = "No model matches \"\(query)\"."
        case 1:
            setModel(found[0].entry.id, endpointID: found[0].endpoint.id)
            notice = "The next reply uses \(found[0].entry.id) (\(found[0].endpoint.name))."
        default:
            let names = found.prefix(6).map { "\($0.entry.id) (\($0.endpoint.name))" }.joined(separator: ", ")
            notice = "\"\(query)\" matches \(found.count) models: \(names)\(found.count > 6 ? ", …" : ""). Be more specific."
        }
    }

    /// Summarizes the conversation now; later turns start from the summary.
    func compactNow(focus: String = "") {
        guard task == nil, let endpoint, !session.messages.isEmpty else { return }
        guard SessionRun.hasNewMessagesToCompact(session) else {
            notice = SessionRun.nothingToCompact
            return
        }
        let app = app
        let tools = tools
        let profile = profile
        let limit = contextLimit
        let hooks = loadHooks()
        isCompacting = true
        notice = nil
        lastFinish = nil
        task = Task {
            do {
                try await locked {
                    let session = self.session          // as reloaded, if the command line added to it
                    let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
                    let outcome = await SessionRun.compact(session: session, client: client, model: session.model, hooks: hooks,
                                                           baseSystemPrompt: await systemPrompt(tools: tools), tools: tools,
                                                           settings: Pref.run, profile: profile, focus: focus, contextLimit: limit,
                                                           costs: CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { [weak self] e in
                                                               await self?.recordCost(e)
                                                           },
                                                           wire: WireLog(directory: app.sessionStore.wireDirectory(for: session.header)))
                    if let c = outcome.compaction {
                        self.session.compactions.append(c)
                        persist(.compaction(c))
                        notice = "Summarized the conversation: about \(c.tokensBefore / 1000)k tokens down to \(max(1, c.tokensAfter / 1000))k."
                    } else if !Task.isCancelled {
                        notice = outcome.explanation
                    }
                }
            } catch { notice = error.localizedDescription }
            isCompacting = false
            task = nil
            afterRun(stopped: Task.isCancelled)
        }
    }

    /// The session's base system prompt (no summary), built on first use and reused while the mode stays the same,
    /// and across restarts (the session records it).
    private func systemPrompt(tools: [any Tool]) async -> String {
        let text = await prompt.text(workspace: isChat && tools.isEmpty ? nil : workspace, tools: tools, mode: permissionMode,
                                     sandbox: Pref.sandbox(for: permissionMode), userPrompt: Pref.run.systemPrompt,
                                     addendum: profile.promptAddendum, isChat: isChat,
                                     style: Pref.run.style(for: endpoint?.kind.api ?? .openai), subagents: !tools.isEmpty,
                                     skills: !tools.isEmpty && workspace.map { !Skills.load(root: $0.root, builtin: Skills.builtin(Pref.run.builtinSkills)).isEmpty } == true,
                                     recorded: session.recordedPrompt)
        if let r = prompt.takeRecord() {
            session.recordedPrompt = r
            session.systemPrompt = r.text
            persist(.systemPrompt(r))
        }
        return text
    }

    func stop() {
        task?.cancel()
    }

    /// The last run never ended (kurtkode quit or crashed during it) and it's the user's to pick up: not while it's
    /// running, here or on the command line, nor once dismissed.
    var interruptedRun: Bool {
        guard task == nil, !interruptDismissed, session.wasInterrupted else { return false }
        return SessionLock.holder(app.sessionStore.lockURL(for: session.header.id)) == nil
    }
    var interruptDismissed = false

    /// Resumes after the step limit, or a run that was cut off: the model picks up from the last message.
    func continueRun() {
        guard task == nil, sendBlocker == nil else { return }
        generate()
    }

    func setPermissionMode(_ mode: PermissionMode) {
        guard mode != permissionMode else { return }
        permissionMode = mode
        persist(.permissionMode(mode))
    }

    // MARK: Approvals

    func answer(_ decision: ApprovalDecision) {
        guard !approvals.isEmpty else { return }
        let pending = approvals.removeFirst()
        pending.resume(decision)
    }

    /// A request whose asker stopped (Stop, or its subagent was stopped): answered "deny" and removed.
    private func withdraw(_ id: String) {
        guard let i = approvals.firstIndex(where: { $0.id == id }) else { return }
        approvals.remove(at: i).resume(.deny(feedback: nil))
    }

    /// Suspends the agent until the user answers the approval card. Stop counts as "deny".
    func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<ApprovalDecision, Never>) in
                approvals.append(PendingApproval(request: request) { cont.resume(returning: $0) })
                Notifier.shared.post(title: "\(session.displayTitle) needs your approval",
                                     body: request.reason.map { "\(request.summary) (\($0))" } ?? request.summary,
                                     session: session.header.id)
                #if DEBUG
                if let delay = ProcessInfo.processInfo.environment["KURTKODE_AUTOAPPROVE"].flatMap(Double.init) {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        if self?.pendingApproval?.id == request.id { self?.answer(.allow) }
                    }
                }
                #endif
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.withdraw(request.id) }
        }
    }

    /// Answers the card shown, with an answer for each question; nil dismisses it (the model is told nobody answered).
    func answerQuestion(_ answers: [String?]?) {
        guard !questions.isEmpty else { return }
        questions.removeFirst().resume(answers ?? [])
    }

    /// Suspends the agent until the user answers the model's questions. Stop withdraws them.
    func askUser(_ asked: [UserQuestion]) async -> [String?] {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<[String?], Never>) in
                questions.append(PendingQuestion(questions: asked, resume: { cont.resume(returning: $0) }, id: id))
                Notifier.shared.post(title: "\(session.displayTitle) needs your answer", body: asked.first?.question ?? "",
                                     session: session.header.id)
                #if DEBUG
                if let typed = ProcessInfo.processInfo.environment["KURTKODE_AUTOANSWER"] {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        if self?.pendingQuestion?.id == id { self?.answerQuestion(asked.map { $0.answer(fromTyped: typed) ?? typed }) }
                    }
                }
                #endif
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let i = questions.firstIndex(where: { $0.id == id }) else { return }
                questions.remove(at: i).resume([])
            }
        }
    }

    /// Decides on the plan shown.
    func decidePlan(_ decision: PlanDecision) {
        guard !plans.isEmpty else { return }
        plans.removeFirst().resume(decision)
    }

    /// Suspends the agent until the user decides on the model's plan. Stop withdraws it (as a rejection).
    func presentPlan(_ proposal: PlanProposal) async -> PlanDecision {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<PlanDecision, Never>) in
                plans.append(PendingPlan(proposal: proposal, resume: { cont.resume(returning: $0) }, id: id))
                Notifier.shared.post(title: "\(session.displayTitle) has a plan for you", body: String(proposal.plan.prefix(120)),
                                     session: session.header.id)
                #if DEBUG
                // KURTKODE_AUTOPLAN=edits | auto | reject | anything else (revise with that feedback); several, separated
                // by "|", answer the plans in turn (the last repeats): "add a test|edits".
                if let all = ProcessInfo.processInfo.environment["KURTKODE_AUTOPLAN"] {
                    let answers = all.split(separator: "|").map(String.init)
                    let typed = answers.isEmpty ? all : answers[min(autoPlanCount, answers.count - 1)]
                    autoPlanCount += 1
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        if self?.pendingPlan?.id == id { self?.decidePlan(PlanDecision.parse(typed) ?? .reject(nil)) }
                    }
                }
                #endif
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let i = plans.firstIndex(where: { $0.id == id }) else { return }
                plans.remove(at: i).resume(.reject(nil))
            }
        }
    }

    // MARK: Rewind

    /// What rewinding to this user message would restore and leave (C3): from the runs' snapshots, so command-made
    /// changes too, or from the edit tools' checkpoints when a run has none.
    func rewindPlan(to messageID: UUID) async -> RewindPlan {
        await RewindPlan.make(target: messageID, messages: session.messages, runs: session.runs, snapshots: snapshots,
                              session: session.header.id, checkpoints: checkpoints)
    }

    // MARK: Escalation (A4)

    /// The offer to hand the request to the next tier's model, shown as a card over the composer until it's taken,
    /// declined, or a new message goes.
    var escalation: EscalationOffer?

    /// After a main run: the free signals; with Settings' review on, a hosted run below the frontier that changed files is
    /// reviewed first (A6), and problems it finds are a reason too.
    private func considerEscalation(after run: AgentRunRecord) {
        guard run.agent == "main", Pref.run.escalationOffers, let endpoint = app.endpoint(run.setup.endpointID ?? session.endpointID) else { return }
        let reasons = Escalation.reasons(run)
        if !reasons.isEmpty { offerEscalation(run: run, reasons: reasons, source: "signals"); return }
        // Not after the cost limit (a review is another paid request), nor for a run that changed nothing.
        guard Pref.run.escalationReview, endpoint.isCloudAPI, run.outcome.stop != "costLimit", let refs = run.snapshots,
              refs.end != nil, refs.changed != false, snapshots != nil,
              let tier = Escalation.tier(endpoint: endpoint, model: run.setup.model, pool: app.pool, endpoints: app.endpoints), tier < .frontier,
              let pick = ReviewRouting.reviewer(for: run.setup.model, endpoint: endpoint, pool: app.pool, endpoints: app.endpoints) else { return }
        Task {
            guard let reviewer = await model(for: pick),
                  let r = await reviewRun(run, on: reviewer, remote: pick.endpoint.isThirdParty, api: endpoint.kind.api) else { return }
            // Only while it's still the latest run and nothing else is going (a late review mustn't bring back a card).
            guard let verdict = r.verdict, verdict != .looksRight, session.runs.last?.id == run.id, task == nil else { return }
            review = r
            // "Has problems": findings to fix here (the Changes tab's Fix These), not a stronger model.
            guard r.escalates else {
                notice = "The review on \(r.reviewer) found problems in the change: Changes has them, with Fix These."
                return
            }
            offerEscalation(run: run, reasons: ["the review on \(r.reviewer) found it \(verdict.label)" + (r.findings.first.map { ": " + $0.problem } ?? "")],
                            source: "review")
        }
    }

    /// A run's change reviewed (read-only) on `reviewer`; the verdict is kept as a judgment of the run. Nil: the run
    /// changed nothing that can be shown.
    private func reviewRun(_ run: AgentRunRecord, on reviewer: SubagentModel, remote: Bool, api: WireAPI) async -> CodeReview? {
        guard let refs = run.snapshots, let end = refs.end, let snaps = snapshots,
              let diff = try? await snaps.patch(session: session.header.id, from: refs.start, to: end), !diff.isEmpty else { return nil }
        var input = (try? await ReviewInput.gather(scope: .turn(run.userMessage ?? UUID()), session: session, snapshots: snaps))
            ?? ReviewInput(request: run.task.text, report: nil, checks: [], diff: diff, run: run)
        input.diff = diff
        if remote { input.withholding(Pref.run.withheldFromRemote) }
        let costs = CostSink(scope: CostScope(run: run.id, agent: "main", userMessage: run.userMessage), endpointID: reviewer.endpointID,
                             emit: { [weak self] e in await MainActor.run { self?.recordCost(e) } })
        let r = await CodeReview.run(reviewer, prompt: input.prompt, costs: costs, meter: nil, limits: Pref.run.limits(for: profile, api: api))
        let j = r.judgment(run: run.id)
        session.judgments.append(j)
        persist(.judgment(j))
        return r
    }

    /// Decision 4's review on the escalation card: the verdict, shown in the card (and the Changes tab) while the offer
    /// stands.
    var escalationReview: CodeReview?

    /// The card's first action for a run that changed files: the change reviewed on the model the offer would escalate
    /// to (a fraction of a re-run's cost). Escalating stays on offer afterwards.
    func reviewEscalation() {
        guard var o = escalation, o.canReview, task == nil, !reviewing, let target = app.endpoint(o.toEndpointID),
              let run = session.runs.first(where: { $0.id == o.run }) else { return }
        o.decision = .reviewed
        escalation = o
        record(o)
        reviewing = true
        notice = "Reviewing on \(o.toLabel)…"
        Task {
            defer { reviewing = false }
            guard var reviewer = await model(for: ModelRef(endpointID: o.toEndpointID, model: o.toModel)) else {
                notice = "\(o.toModel) couldn't be reached."
                return
            }
            if let r = o.toReasoning { reviewer.reasoning = r }
            if let p = o.toProviders { reviewer.providers = p }
            guard let r = await reviewRun(run, on: reviewer, remote: target.isThirdParty, api: target.kind.api) else {
                notice = "The run's change couldn't be gathered."
                return
            }
            notice = nil
            review = r
            if escalation?.id == o.id { escalationReview = r }
        }
    }

    /// After the card's review: its findings go to the session's model to fix, and the offer stays recorded as reviewed.
    func fixEscalationFindings() {
        escalation = nil
        escalationReview = nil
        fixReviewFindings()
    }

    /// Makes and records an offer for a run (its own model and endpoint), when there's a model to go to; an unanswered
    /// earlier offer is recorded as ignored.
    func offerEscalation(run: AgentRunRecord?, reasons: [String], source: String, unknownTier: PoolEntry.Tier? = nil) {
        guard let endpoint = app.endpoint(run?.setup.endpointID ?? session.endpointID) else { return }
        let app = app
        guard let offer = Escalation.offer(run: run?.id, reasons: reasons, source: source, endpoint: endpoint, model: run?.setup.model ?? session.model,
                                           pool: app.pool, endpoints: app.endpoints, contextTokens: contextUsed,
                                           changedFiles: run?.snapshots?.changed == true, unknownTier: unknownTier,
                                           price: { r in app.catalogs[r.endpoint.id]?.entry(r.model)?.price ?? PriceList.price(api: r.endpoint.kind.api, model: r.model) })
        else {
            if source == "asked" { notice = "There's no stronger main model in the pool to escalate \(session.model) to (Settings → Pool)." }
            return
        }
        setAside()
        escalation = offer
        session.escalations.append(offer)
        persist(.escalation(offer))
    }

    /// An unanswered card goes (recorded as ignored): a new message, another model, a newer offer.
    private func setAside() {
        guard var o = escalation else { return }
        escalation = nil
        escalationReview = nil
        // A reviewed offer keeps that answer.
        guard o.decision == .offered else { return }
        o.decision = .ignored
        record(o)
    }

    /// Takes the offer: the next turn goes to its model, sent the reasons and the run's change. Only while the session is
    /// still on the model the offer was made from (a stale card mustn't switch it down a tier).
    func acceptEscalation() {
        guard var o = escalation, task == nil else { return }
        guard o.fromModel == session.model, o.fromEndpointID == session.endpointID else {
            setAside()
            notice = "That offer was for \(o.fromModel); the session has switched models since."
            return
        }
        o.decision = .accepted
        escalation = nil
        escalationReview = nil
        record(o)
        let run = session.runs.first { $0.id == o.run }
        let request = run?.userMessage.flatMap { id in session.messages.first { $0.id == id }?.content } ?? session.lastRequest?.content ?? ""
        let refs = run?.snapshots, snaps = snapshots, id = session.header.id
        let remote = app.endpoint(o.toEndpointID)?.isThirdParty ?? true, withheld = Pref.run.withheldFromRemote
        Task {
            var diff: String?
            if let refs, let snaps, let d = try? await snaps.patch(session: id, from: refs.start, to: refs.end) {
                diff = remote ? UnifiedDiff.withholding(d, patterns: withheld).0 : d
            }
            setModel(o.toModel, endpointID: o.toEndpointID)
            escalatedProfile = (ModelProfile.key(o.toEndpointID, o.toModel), o.toProviders, o.toReasoning)
            submit(Escalation.handOver(o, request: request, diff: diff))
        }
    }

    func declineEscalation() {
        guard var o = escalation else { return }
        o.decision = .declined
        escalation = nil
        escalationReview = nil
        record(o)
    }

    private func record(_ o: EscalationOffer) {
        if let i = session.escalations.firstIndex(where: { $0.id == o.id }) { session.escalations[i] = o } else { session.escalations.append(o) }
        persist(.escalation(o))
    }

    // MARK: Review (A6)

    /// The latest review asked for in this window, shown in the Changes tab.
    var review: CodeReview?
    var reviewing = false

    /// Has another vendor's model from the pool review the change of `scope` (`/review`, the Changes tab's button). In
    /// a local session only reviewers on this Mac or its network are used. The verdict is kept as a judgment of the run.
    func startReview(_ scope: ProjectSnapshots.Scope) {
        guard !reviewing else { return }
        guard let endpoint else { notice = "The session's endpoint is missing."; return }
        reviewing = true
        review = nil
        let snaps = snapshots, current = session, app = app
        Task {
            defer { reviewing = false }
            do {
                var input = try await ReviewInput.gather(scope: scope, session: current, snapshots: snaps)
                guard !input.diff.isEmpty || input.run != nil else { notice = "Nothing to review yet."; return }
                // Another vendor than every model that made the change (the session may have switched since).
                let vendors = input.vendors.isEmpty ? [ModelVendor.of(current.model, endpoint: endpoint)] : input.vendors
                guard let pick = ReviewRouting.reviewer(excluding: vendors, session: endpoint, pool: app.pool, endpoints: app.endpoints) else {
                    notice = "No reviewer of another vendor than \(vendors.sorted().joined(separator: ", ")) in the model pool"
                        + (endpoint.isCloudAPI ? "" : " on this Mac or its network") + ": give one the reviewer role in Settings → Pool."
                    return
                }
                if pick.endpoint.isThirdParty { input.withholding(Pref.run.withheldFromRemote) }
                guard let reviewer = await model(for: pick) else { notice = "\(pick.model) couldn't be reached."; return }
                notice = "Reviewing on \(reviewer.model)…"
                let costs = CostSink(scope: CostScope(run: input.run?.id, agent: "main", userMessage: input.run?.userMessage),
                                     endpointID: reviewer.endpointID, emit: { [weak self] e in await MainActor.run { self?.recordCost(e) } })
                let result = await CodeReview.run(reviewer, prompt: input.prompt, costs: costs, meter: nil,
                                                  limits: Pref.run.limits(for: profile, api: endpoint.kind.api))
                review = result
                notice = input.withheld.isEmpty ? nil : "Left out of the review (withheld from remote models): " + input.withheld.joined(separator: ", ")
                if let run = input.run {
                    let j = result.judgment(run: run.id)
                    session.judgments.append(j)
                    persist(.judgment(j))
                }
            } catch { notice = "Couldn't gather the change: \(error.localizedDescription)" }
        }
    }

    /// Sends the review's findings to the session's model to deal with.
    func fixReviewFindings() {
        guard let r = review, !r.findings.isEmpty else { return }
        submit(r.fixRequest)
        review = nil
    }

    /// A rewind asked for from outside the transcript (the Changes tab's checkpoint list): the chat view confirms it.
    var rewindRequest: UUID?

    /// Undoes this user message and what came after it. `.both`: restores the files the runs changed, removes the
    /// messages, and puts the message text back in the composer; `.files`: only the files, and the model gets a note;
    /// `.conversation`: only the messages.
    @discardableResult
    func rewind(to messageID: UUID, choice: RewindChoice = .both) async throws -> [CheckpointStore.Restored] {
        guard task == nil else { return [] }
        return try await locked { try await rewindLocked(to: messageID, choice: choice) }
    }

    private func rewindLocked(to messageID: UUID, choice: RewindChoice) async throws -> [CheckpointStore.Restored] {
        guard task == nil, let idx = session.messages.firstIndex(where: { $0.id == messageID }),
              session.messages[idx].role == .user else { return [] }
        let plan = await rewindPlan(to: messageID)
        var restored: [CheckpointStore.Restored] = []
        if choice.restoresFiles {
            restored = try await plan.restoreFiles(snapshots: snapshots, checkpoints: checkpoints)
            // The runs that answered the message rewound to: the user didn't want what they did. Later turns go too, but
            // only as a consequence, so they get no judgment. Keeping the files (conversation only) isn't a verdict.
            for run in session.runs where run.agent == "main" && run.userMessage == messageID {
                noteImplicit(run, why: "rewound")
            }
        }
        if choice.removesMessages {
            let removed = Array(session.messages[idx...])
            session.messages.removeSubrange(idx...)
            for m in removed { persist(.retract(m.id)) }
            restoreToDraft(removed[0].content)
            pendingImages = removed[0].images ?? []
        } else if !restored.isEmpty {
            append(FrozenSystemPrompt.noteMessage(plan.note(request: session.messages[idx].content, root: workspace?.root.path)))
            notice = "Restored \(restored.count) file\(restored.count == 1 ? "" : "s"); the model is told on your next message."
        }
        lastStop = nil
        return restored
    }

    /// Uses another model, possibly on another endpoint, from the next turn on.
    func setModel(_ model: String, endpointID: UUID? = nil) {
        let ep = endpointID ?? session.endpointID
        guard model != session.model || ep != session.endpointID else { return }
        setAside()
        if let e = app.endpoint(ep), let tokens = contextUsed,
           let note = PriceList.switchNote(promptTokens: tokens, api: e.kind.api, model: model,
                                           fromThinking: Self.lastReplyThinks(session), cacheHour: Pref.run.cacheHour(interactive: true).main) {
            notice = "Switched to \(model). " + note
        }
        session.model = model
        session.endpointID = ep
        // Before the first message nothing is saved yet: the header (written with that message) takes the model,
        // instead of naming the default model and a `model` record correcting it.
        if isPersisted { persist(.model(model, endpoint: ep)) }
        else {
            session.header.model = model
            session.header.endpointID = ep
        }
        app.noteUsed(ModelRef(endpointID: ep, model: model))
    }

    /// A notification for a run's end, when kurtkode isn't the front app.
    private func notifyFinished(_ stop: AgentStop) {
        let title = session.displayTitle
        let text: String
        switch stop {
        case .completed: text = "Done" + (session.messages.last(where: { $0.role == .assistant })?.content
            .split(separator: "\n").first.map { ": " + $0.prefix(140) } ?? ".")
        case .stepLimit: text = "Paused at the step limit."
        case .costLimit: text = "Paused at the cost limit."
        case .denied: text = "Stopped after a denial; it waits for your instructions."
        case .cancelled: return
        case .truncated: text = "The reply was cut off at the output limit."
        case .turnStopped(let why): text = "Stopped: \(why)."
        }
        Notifier.shared.post(title: title, body: text, session: session.header.id)
    }

    /// Whether the latest reply carried Claude thinking blocks (which don't go to another model).
    static func lastReplyThinks(_ s: Session) -> Bool {
        guard let n = s.messages.last(where: { $0.role == .assistant && $0.meta != nil })?.native, n.api == .anthropic else { return false }
        return (n.blocks.arrayValue ?? []).contains { if case .object(let b) = $0 { b["type"] == "thinking" } else { false } }
    }

    /// What switching to `ref` would cost now, for the model menu ("≈$0.48 to switch"); nil when small or unpriced.
    func switchCostLabel(_ ref: ModelRef) -> String? {
        guard ref.model != session.model || ref.endpointID != session.endpointID, let tokens = contextUsed, tokens >= 8000,
              let e = app.endpoint(ref.endpointID) else { return nil }
        // Claude and Gemini: cache writes included; a listed price (OpenRouter): the history read once at full price.
        let c = PriceList.switchCost(promptTokens: tokens, api: e.kind.api, model: ref.model, cacheHour: Pref.run.cacheHour(interactive: true).main)
            ?? app.catalogs[e.id]?.entry(ref.model)?.price.map { Double(tokens) * $0.standard.input / 1e6 }
        guard let c else { return nil }
        return c < 0.01 ? String(format: "≈$%.3f to switch", c) : String(format: "≈$%.2f to switch", c)
    }

    func rename(_ title: String) {
        session.title = title
        persist(.title(title))
    }

    /// Re-runs the last assistant turn.
    func retry() {
        guard task == nil, !reloading, sendBlocker == nil else { return }
        // As `send`: what the command line added comes first (the last reply may be one it wrote).
        if mayHaveChangedElsewhere {
            reloading = true
            Task {
                await reloadIfChangedElsewhere()
                reloading = false
                retryNow()
            }
            return
        }
        retryNow()
    }

    private func retryNow() {
        guard task == nil, sendBlocker == nil, let last = session.messages.last, last.role == .assistant else { return }
        // The lock before the reply is retracted: refused, the reply stays.
        guard takeRunLock() else { return }
        noteImplicit(session.mainRun(for: last.id), why: "retried")
        session.messages.removeLast()
        persist(.retract(last.id))
        generate()
    }

    private func generate() {
        guard let endpoint else { releaseRunLock(); return }
        guard takeRunLock() else { return }
        ensureChatFolder()
        let app = app
        let run = Pref.run
        // Undo snapshots are keyed by the user message that started this turn, or the last one queued in.
        let turnKey = TurnKey(session.lastRequest?.id ?? UUID())
        var setup = SessionRun(
            session: session, store: app.sessionStore, settings: run, profile: profile, endpointID: endpoint.id,
            api: endpoint.kind.api, permissionRules: loadPermissionRules(),
            mode: permissionMode, rules: sessionRules, tools: tools, workspace: workspace, shell: shell,
            contextLimit: contextLimit, sandbox: Pref.sandbox(for: permissionMode), turn: turnKey, checkpoints: checkpoints,
            approve: { [weak self] request in await self?.requestApproval(request) ?? .deny(feedback: nil) },
            hooks: loadHooks(), subagentModel: { [weak self] agent, card in await self?.subagentModel(for: agent, card: card) })
        setup.config.takeInput = { [weak self] in await self?.takeQueued(turnKey) ?? [] }
        setup.config.subagents?.control = subagentControl
        if let ref = run.graderModel { setup.config.subagents?.grader = { [weak self] _, _ in await self?.model(for: ref) } }
        do {
            let main = endpoint, pool = app.pool, endpoints = app.endpoints
            if run.graderModel == nil, run.graderAutomatic {
                setup.config.subagents?.grader = { [weak self] runEndpoint, runModel in
                    guard let g = SubagentRouting.grader(main: main, runEndpointID: runEndpoint, runModel: runModel, pool: pool,
                                                         endpoints: endpoints) else { return nil }
                    return await self?.model(for: g)
                }
            }
            // A6: important subagent runs that change files get another vendor's review, in hosted sessions only.
            if main.isCloudAPI {
                setup.config.subagents?.reviewer = { [weak self] runEndpoint, runModel in
                    guard let r = ReviewRouting.reviewer(for: runModel, endpoint: endpoints.first { $0.id == runEndpoint } ?? main,
                                                         pool: pool, endpoints: endpoints) else { return nil }
                    return await self?.model(for: r)
                }
            }
            if run.subagentRetry {
                setup.config.subagents?.retryModel = { [weak self] agent, endpointID, model, reasoning in
                    guard let r = SubagentRouting.retry(after: endpointID, model: model, reasoning: reasoning,
                                                        routed: SubagentRouting.routed(agent, settings: run), main: main, pool: pool,
                                                        endpoints: endpoints) else { return nil }
                    return await self?.model(for: r)
                }
            }
        }
        setup.config.subagents?.slots = SubagentSetup.slots(
            parallel: run.subagentParallel,
            localLMStudio: Set(app.endpoints.filter { $0.kind == .lmstudio && $0.isLocal }.map(\.id)))
        setup.config.sendImages = acceptsImages
        setup.config.askUser = { [weak self] questions in await self?.askUser(questions) ?? [] }
        setup.config.presentPlan = { [weak self] proposal in await self?.presentPlan(proposal) ?? .reject(nil) }
        lastFinish = nil
        app.noteUsed(ModelRef(endpointID: endpoint.id, model: session.model))
        let workspace = workspace
        let model = session.model
        titleTarget = (endpoint, model, profile)
        let mcpWorkspace = tools.isEmpty ? nil : session.header.workspace
        lastStop = nil
        notice = nil
        liveOutput = [:]
        streaming = TurnSnapshot()
        streamStartedAt = Date()
        runStartedAt = Date()

        let summarizerRef = run.summarizer(excluding: endpoint.id, model)
        // A local fallback must already be loaded: LM Studio's on-demand load uses a small context.
        let fallbackRef = run.fallback(excluding: endpoint.id, model).flatMap { ref -> ModelRef? in
            guard let e = app.endpoint(ref.endpointID) else { return nil }
            return e.kind == .lmstudio && app.catalogs[e.id]?.entry(ref.model)?.isLoaded != true ? nil : ref
        }

        task = Task {
            let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
            if let ref = summarizerRef, let e = app.endpoint(ref.endpointID) {
                setup.config.summarizer = Summarizer(client: ChatClient(endpoint: e, apiKey: await app.apiKey(for: e)),
                                                     model: ref.model, historyShape: app.profile(ref.endpointID, ref.model).history, endpointID: e.id)
            }
            if let ref = fallbackRef, let e = app.endpoint(ref.endpointID) {
                let p = app.profile(ref.endpointID, ref.model)
                setup.config.fallback = FallbackModel(client: ChatClient(endpoint: e, apiKey: await app.apiKey(for: e)), model: ref.model,
                                                      historyShape: p.history, temperature: p.temperature, endpointID: e.id)
            }
            // Tools from the project's MCP servers (waiting briefly for any still starting).
            if let mcpWorkspace { setup.config.tools += await app.mcpTools(for: mcpWorkspace) }
            await setup.countSubagentSpending(session: session, store: app.sessionStore)
            await setup.countDailySpending(settings: Pref.run, store: app.sessionStore, workspace: session.header.workspace, main: endpoint)
            // The summary goes in via config, so the frozen base prompt stays byte-identical.
            let system = await systemPrompt(tools: setup.offeredTools)
            // The skill router (by default for OpenAI-compatible servers): which skill fits the request, said after it.
            var history = setup.history
            let routeNote = await setup.routeSkill(client: client, model: model, routing: run.skillRouting,
                                                   project: workspace?.root) { [weak self] e in
                await MainActor.run { self?.recordCost(e) }
            }
            // A resumed session keeps its prompt; the date and git status it states go after the user's message.
            var serverNote: String?
            if let mcpWorkspace { serverNote = await app.mcpHub(for: mcpWorkspace).instructionNote(alreadySent: session.messagesInContext) }
            for m in [prompt.takeNote().map(FrozenSystemPrompt.noteMessage), routeNote, serverNote.map(FrozenSystemPrompt.noteMessage)].compactMap({ $0 }) {
                session.messages.append(m)
                persist(.message(m))
                history.append(m)
            }
            await AgentLoop.run(client: client, model: model, systemPrompt: system, history: history,
                                config: setup.config, workspace: workspace) { [weak self] event in
                await MainActor.run { self?.handle(event) }
            }
            streaming = nil
            streamStartedAt = nil
            for a in approvals { a.resume(.deny(feedback: nil)) }
            approvals.removeAll()
            for q in questions { q.resume([]) }
            questions.removeAll()
            runningTools.removeAll()
            runningSince.removeAll()
            runStartedAt = nil
            isCompacting = false
            promptEstimate = nil
            task = nil
            releaseRunLock()
            await reloadIfChangedElsewhere()
            afterRun()
            writeTitle()
        }
    }

    /// Asked once per session, so a failed or useless answer isn't paid for again.
    @ObservationIgnored private var titleAsked = false
    /// What the run went to: the model picked since may be one this chat has never been sent to.
    @ObservationIgnored private var titleTarget: (endpoint: Endpoint, model: String, profile: ModelProfile)?

    /// After a run that finished, the first time: a title from the model that ran it, for a chat whose first line doesn't
    /// make one. Nothing that model hasn't seen goes out, or anywhere its profile rules out, and nothing after a Stop, a
    /// cost limit or a Move to Trash. The request is a billed one like any other (purpose `title`).
    private func writeTitle() {
        defer { titleTarget = nil }
        guard !titleAsked, lastFinish == .completed, session.title == nil, Pref.d.object(forKey: Pref.autoTitles) as? Bool ?? true else { return }
        guard let request = session.messages.first(where: { $0.role == .user })?.content, ChatTitle.worthWriting(request: request),
              let reply = session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.content,
              let (endpoint, model, profile) = titleTarget,
              FileManager.default.fileExists(atPath: app.sessionStore.fileURL(for: session.header).path) else { return }
        titleAsked = true
        let app = app, limits = Pref.run.limits(for: profile, api: endpoint.kind.api)
        Task { [weak self] in
            let client = ChatClient(endpoint: endpoint, apiKey: await app.apiKey(for: endpoint))
            let costs = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: endpoint.id) { [weak self] e in
                await self?.recordCost(e)
            }
            guard let title = await ChatTitle.write(request: request, reply: reply, client: client, model: model, providers: profile.providers,
                                                    limits: limits, costs: costs), let self, self.session.title == nil else { return }
            self.rename(title)
        }
    }

    /// Seconds between UI updates of a streaming reply: 0.1 up to 8 KB, growing to 0.25 by 32 KB. Each update costs
    /// SwiftUI more as the reply has more pieces (a 60 KB reply: ~60 rows to diff and place), and nobody reads the
    /// middle of a long reply at ten frames a second.
    static func streamUpdateInterval(_ snap: TurnSnapshot) -> TimeInterval {
        let size = snap.content.utf8.count + snap.reasoning.utf8.count
        return 0.1 + 0.15 * min(1, max(0, Double(size - 8_000) / 24_000))
    }

    private func handle(_ event: AgentEvent) {
        switch event {
        case .streaming(let snap):
            // At most 10 UI updates a second: each one re-lays out the reply (measured: 20 a second kept the
            // main thread about a third busy for the whole reply). The final message arrives separately.
            let now = Date()
            if streaming == nil || now.timeIntervalSince(lastStreamPublish) >= Self.streamUpdateInterval(snap)
                || (streaming?.toolCalls.count ?? 0) != snap.toolCalls.count {
                streaming = snap
                lastStreamPublish = now
            }
        case .assistant(let message):
            streaming = nil
            append(message)
        case .toolStarted(let call):
            runningTools.append(call)
            runningSince[call.id] = Date()
        case .toolProgress(let id, let text):
            let current = liveOutput[id, default: ""] + text
            liveOutput[id] = current.count > 20_000 ? String(current.suffix(16_000)) : current
        case .ruleAdded(let rule):
            if !sessionRules.contains(rule) { sessionRules.append(rule) }
        case .modeChanged(let mode):
            setPermissionMode(mode)
        case .promptSize(let tokens):
            promptEstimate = tokens
        case .compacting:
            isCompacting = true
        case .cost(let e):
            recordCost(e)
        case .runEnded(let r):
            session.runs.append(r)
            persist(.run(r))
            considerEscalation(after: r)
        case .judged(let j):
            session.judgments.append(j)
            persist(.judgment(j))
            if let i = subagents.firstIndex(where: { $0.id == j.run }) { subagents[i].judgments.append(j) }
        case .compacted(let c):
            isCompacting = false
            session.compactions.append(c)
            persist(.compaction(c))
            promptEstimate = c.tokensAfter
            notice = "Context was getting full, so the earlier conversation was summarized "
                + "(about \(c.tokensBefore / 1000)k tokens down to \(max(1, c.tokensAfter / 1000))k)."
        case .toolFinished(let result):
            runningTools.removeAll { $0.id == result.toolCallID }
            if let id = result.toolCallID {
                liveOutput[id] = nil
                runningSince[id] = nil
            }
            append(result)
            // The next model turn starts now; show it as waiting.
            streaming = TurnSnapshot()
            streamStartedAt = Date()
        case .injected(let message):
            append(message)
            if message.subagentReport != nil { notice = nil }       // the "waiting for…" status is over
        case .status(let text):
            notice = text
            if text.hasPrefix(CostMeter.stopPrefix) { costLimitNote = text }
        case .hookNotice(let text), .retrying(let text):
            notice = text
        case .subagentStarted(let info):
            if !subagents.contains(where: { $0.id == info.id }) { subagents.append(SubagentRow(info)) }
            #if DEBUG
            // KURTKODE_STOP_SUBAGENT_AFTER=seconds: stop each subagent that long after it starts (as the Stop button does).
            if let s = ProcessInfo.processInfo.environment["KURTKODE_STOP_SUBAGENT_AFTER"].flatMap(Double.init) {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(s))
                    self?.stopSubagent(info.id)
                }
            }
            #endif
        case .subagentProgress(let p):
            if let i = subagents.firstIndex(where: { $0.id == p.id }) { subagents[i].update(p) }
        case .subagentFinished(let id, let end):
            if let i = subagents.firstIndex(where: { $0.id == id }) { subagents[i].finish(end) }
        case .finished(let stop):
            notifyFinished(stop)
            lastFinish = stop
            if stop != .cancelled, app.lastSelectedSession != id { unread = true }
            streaming = nil
            // Step and cost limits and denial need a prompt from the user; other stops show on the message itself.
            lastStop = (stop == .stepLimit || stop == .costLimit || stop == .denied) ? stop : nil
        }
    }

    private func append(_ message: ChatMessage) {
        session.messages.append(message)
        persist(.message(message))
    }

    /// A billed request: kept with the session (`Session.costs`, a `cost` record).
    func recordCost(_ e: CostEntry) {
        if let i = session.costs.firstIndex(where: { $0.id == e.id }) { session.costs[i] = e } else { session.costs.append(e) }
        persist(.cost(e))
    }

    /// Set when the session file is gone (moved to the Trash, or deleted): nothing more can be saved, so nothing more is
    /// sent. A trashed session's controller sets it at once, so its last writes don't create the file again.
    var sessionFileGone = false
    /// Kinds of save failure already shown, so a full disk doesn't replace every other notice with the same one.
    @ObservationIgnored private var saveFailuresShown: Set<String> = []

    /// A record couldn't be written: say so once per kind of failure, and stop the run when the file is gone, so
    /// replies (and what they cost) don't go on being made where nothing keeps them.
    private func saveFailed(_ error: Error) {
        let ns = error as NSError
        let gone = (ns.domain == NSCocoaErrorDomain && ns.code == NSFileNoSuchFileError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
        Log.app.error("saving session \(self.sessionID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if gone {
            guard !sessionFileGone else { return }
            sessionFileGone = true
            stop()
            notice = "This session's file is gone (moved to the Trash?), so nothing more of it can be saved. The run was stopped."
            return
        }
        guard saveFailuresShown.insert("\(ns.domain)/\(ns.code)").inserted else { return }
        notice = "Couldn't save this session: \(error.localizedDescription) What's shown here may not be kept."
    }

    private func persist(_ record: SessionRecord) {
        guard !sessionFileGone else { return }
        let store = app.sessionStore
        let header = session.header
        let create = !isPersisted
        isPersisted = true
        let previous = lastWrite
        pendingWrites += 1
        lastWrite = Task {
            await previous?.value
            do {
                if create { try await store.create(header) }
                try await store.append(record, to: header.id)
            } catch { saveFailed(error) }
            knownFileSize = await store.knownSize(header.id)
            pendingWrites -= 1
        }
        app.updateSummary(for: session)
    }
}
