import Foundation

/// A kind of subagent: what it's for (shown to the main agent), its instructions, which of the main
/// agent's tools it gets, and optionally its own model.
public struct AgentDefinition: Sendable, Hashable, Identifiable {
    public var name: String
    public var description: String
    public var instructions: String
    /// Tool names it may use; nil means the main agent's tools. "mcp" stands for every MCP tool.
    public var tools: [String]?
    /// "model" or "endpoint|model"; nil means the subagent setting, else the main model.
    public var model: String?
    public var source: URL?
    /// `isolation: worktree` in its file: it always works on a branch of its own.
    public var isolated = false
    public var id: String { name }

    public init(name: String, description: String, instructions: String, tools: [String]? = nil, model: String? = nil,
                source: URL? = nil) {
        self.name = name
        self.description = description
        self.instructions = instructions
        self.tools = tools
        self.model = model
        self.source = source
    }

    public static let explore = AgentDefinition(
        name: "explore",
        description: "Finds and reads code to answer a question (read-only). Good for searches that would take many steps.",
        instructions: """
            Answer the question by searching and reading the project. Don't change anything. Report what you \
            found, citing files as `path:line`, and say plainly if something doesn't exist.
            """,
        tools: ["read_file", "list_dir", "glob", "grep"])

    public static let general = AgentDefinition(
        name: "general",
        description: "Does a self-contained task with the same tools as you: research, edits, commands.",
        instructions: "Do the task completely. If you change files, say which ones and why.")

    public static let builtIns = [explore, general]
}

public enum AgentDefinitions {
    /// Built-ins, then Markdown files from `.kurtkode/agents/` and `.claude/agents/` in the project and the
    /// home folder (first wins; a file can't replace a built-in). Front matter: name, description, tools
    /// (comma-separated), model. The body is the instructions.
    public static func load(workspace: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentDefinition] {
        var out = AgentDefinition.builtIns
        var dirs: [URL] = []
        if let workspace { dirs += [workspace.appending(path: ".kurtkode/agents"), workspace.appending(path: ".claude/agents")] }
        dirs += [home.appending(path: ".kurtkode/agents"), home.appending(path: ".claude/agents")]
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension.lowercased() == "md" {
                guard let data = try? Data(contentsOf: url), data.count < 100_000 else { continue }
                let (meta, body) = SlashCommands.frontMatter(String(decoding: data, as: UTF8.self))
                let name = (meta["name"] ?? url.deletingPathExtension().lastPathComponent).lowercased()
                guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                      !out.contains(where: { $0.name == name }) else { continue }
                let tools = meta["tools"].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                out.append(withIsolation(meta["isolation"], AgentDefinition(name: name, description: meta["description"] ?? String(body.prefix(100)),
                                           instructions: body, tools: tools?.isEmpty == true ? nil : tools,
                                           model: meta["model"].flatMap { $0.isEmpty || $0 == "inherit" ? nil : $0 }, source: url)))
            }
        }
        return out
    }
}

/// Claude Code's model aliases in agent files (`model: sonnet`). They name a Claude model, so they resolve on an
/// endpoint that serves Claude: Anthropic's API first, then OpenRouter. Without one, the agent runs on the session's
/// model, as an unknown model always has (a CLI run used to send "haiku" to the default server, and LM Studio
/// silently answers an unknown id with whatever model it has loaded).
public enum ModelAlias {
    /// Alias → (Anthropic API id, OpenRouter id).
    static let claude: [String: (native: String, openRouter: String)] = [
        "opus": ("claude-opus-5-5", "anthropic/claude-opus-5.5"),
        "sonnet": ("claude-sonnet-5-5", "anthropic/claude-sonnet-5.5"),
        "haiku": ("claude-haiku-5-5", "anthropic/claude-haiku-5.5"),
    ]

    public static func isAlias(_ spec: String) -> Bool { claude[spec.lowercased()] != nil }

    /// The endpoint and model an alias stands for here, or nil (not an alias, or no endpoint serves Claude).
    public static func resolve(_ spec: String, endpoints: [Endpoint]) -> (endpoint: Endpoint, model: String)? {
        guard let ids = claude[spec.lowercased()] else { return nil }
        if let e = endpoints.first(where: { $0.kind == .anthropic }) { return (e, ids.native) }
        if let e = endpoints.first(where: { $0.kind == .openai && ($0.baseURL.host()?.hasSuffix("openrouter.ai") ?? false) }) {
            return (e, ids.openRouter)
        }
        return nil
    }
}

/// The model a subagent runs on, when it isn't the main agent's.
public struct SubagentModel: Sendable {
    public var client: ChatClient
    public var model: String
    public var historyShape: HistoryShape
    public var contextLimit: Int?
    public var temperature: Double?
    public var endpointID: UUID?
    public var sendImages: Bool
    /// Its profile's (or pool entry's) reasoning setting (`ReasoningSetting`); nil: the model's default.
    public var reasoning: String?
    /// OpenRouter provider preferences for it (a pool entry's pins); nil: none.
    public var providers: ProviderRouting?

    public init(client: ChatClient, model: String, historyShape: HistoryShape = HistoryShape(), contextLimit: Int? = nil,
                temperature: Double? = nil, endpointID: UUID? = nil, sendImages: Bool = true, reasoning: String? = nil,
                providers: ProviderRouting? = nil) {
        self.reasoning = reasoning
        self.providers = providers
        self.client = client
        self.model = model
        self.historyShape = historyShape
        self.contextLimit = contextLimit
        self.temperature = temperature
        self.endpointID = endpointID
        self.sendImages = sendImages
    }
}

/// Finds the model for a subagent run from its definition and the task's card; nil: the main agent's model.
public typealias SubagentModelResolver = @Sendable (AgentDefinition, TaskCard) async -> SubagentModel?

/// Turns on the `task` tool. The loop runs each subagent itself: it has the client, model, and settings.
public struct SubagentSetup: Sendable {
    public var agents: [AgentDefinition]
    /// The model for an agent and task (its `model:`, an app setting, or the pool by the card's tier); nil: the main
    /// agent's model.
    public var resolveModel: SubagentModelResolver?
    /// The model to try a run on again after a hard failure (D3): the retry ladder's next rung above the model that
    /// failed (the agent, and the failed run's endpoint, model and reasoning setting); nil: no retry.
    public var retryModel: (@Sendable (_ agent: AgentDefinition, _ endpointID: UUID?, _ model: String, _ reasoning: String?) async -> SubagentModel?)?
    /// The subagent's system prompt; nil: `defaultPrompt`.
    public var systemPrompt: (@Sendable (AgentDefinition, [any Tool], PermissionMode) async -> String)?
    public var maxSteps = 50
    /// A reviewer of another vendor for runs whose card says `importance: high` and that changed files (A6), given the
    /// run's endpoint and model; nil: no review (local sessions, or no such reviewer).
    public var reviewer: (@Sendable (_ runEndpointID: UUID?, _ runModel: String) async -> SubagentModel?)?
    /// The model that judges runs whose card says `importance: high` (Settings → Subagents → Grader); nil: none.
    /// Given the run's own endpoint and model, so an automatic choice can pick another.
    public var grader: (@Sendable (_ runEndpointID: UUID?, _ runModel: String) async -> SubagentModel?)?
    /// Where each run is recorded, as a child session of the parent; nil: not recorded.
    public var recorder: SubagentRecorder?
    /// Lets the user stop one run while the main agent goes on.
    public var control: SubagentControl?
    /// Where a run's own undo store goes (its edits, undone before a retry on another model). It must be somewhere
    /// commands can't write: restoring trusts the store's index, and a run that could add entries to it would have
    /// kurtkode delete or overwrite any file outside the sandbox. Nil: under the user's Application Support.
    public var attemptStore: URL?
    /// How many runs may share an endpoint and model at once (LM Studio: the loaded model's parallel slots); nil:
    /// no limit. Runs that can change things (write, edit, run commands) also go one at a time among themselves.
    public var slots: (@Sendable (_ endpointID: UUID?, _ model: String) async -> Int)?
    /// Holds runs beyond those limits until a slot frees (shared by the runs of one main loop).
    public let limiter = SubagentLimiter()

    public init(agents: [AgentDefinition] = AgentDefinition.builtIns,
                resolveModel: SubagentModelResolver? = nil,
                recorder: SubagentRecorder? = nil) {
        self.agents = agents
        self.resolveModel = resolveModel
        self.recorder = recorder
    }

    /// The undo stores of runs with no `attemptStore` given: under Application Support, never in TMPDIR, which the
    /// sandbox lets commands write.
    static let defaultAttemptStore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "kurtkode/attempts")

    /// Slot limits as kurtkode sets them: for an endpoint in `localLMStudio` (LM Studio on this Mac), the loaded
    /// model's parallel slots (`lms ps --json`; 1 if it isn't listed); for any other endpoint, `parallel`.
    public static func slots(parallel: Int, localLMStudio: Set<UUID>,
                             lms: LMSCLI = LMSCLI()) -> @Sendable (UUID?, String) async -> Int {
        { endpointID, model in
            guard let id = endpointID, localLMStudio.contains(id) else { return max(1, parallel) }
            let loaded = (try? await lms.loadedModels()) ?? []
            return max(1, loaded.first { $0.identifier == model }?.parallel ?? 1)
        }
    }

    /// The task as the subagent gets it: with the card's check asked for at the end, so the run's own tool results
    /// show whether it passed.
    public static func taskText(_ prompt: String, card: TaskCard) -> String {
        card.verify.map { prompt + "\n\nWhen you're done, check the work by running `\($0)`, and say in your report whether it passed." }
            ?? prompt
    }

    /// What follows a report in the parent's task result. (Seen with Qwen3-Coder: good reports, and the same task
    /// sent again four more times.)
    public static func reportNote(agent: String) -> String {
        "\n\n[This is the \(agent) subagent's final report. Use it to continue or to answer the user; don't run the same task again.]"
    }

    public static let preamble = """
        You are a subagent. The main agent gave you one task, below. Do it with your tools, then reply with a \
        complete, self-contained report: the main agent sees only your final message, not your tool calls. Cite \
        files as `path:line`, so what you report can be checked.
        """

    /// The cost scope of a grader's or reviewer's requests: the parent's run (they count toward its limits and totals),
    /// with their own role as the agent, so their entries aren't taken for the main agent's (they said "main" before
    /// the cost audit, B9).
    static func judgeScope(_ parent: CostScope?, as role: String) -> CostScope {
        var s = parent ?? CostScope(run: nil, agent: role)
        s.agent = role
        return s
    }

    /// `templates` and `globalInstructions`: the eval passes the defaults and no personal file, for comparable runs.
    public static func defaultPrompt(workspace: Workspace?, agent: AgentDefinition, tools: [any Tool], mode: PermissionMode,
                                     templates: PromptTemplates? = nil, skills: Bool = false,
                                     globalInstructions: URL = FileManager.default.homeDirectoryForCurrentUser
                                        .appending(path: ".kurtkode/AGENTS.md"), userFiles: Bool = true) async -> String {
        var base = ""
        if let workspace {
            var builder = SystemPromptBuilder(workspace: workspace, tools: tools, mode: mode, globalInstructions: globalInstructions)
            builder.userFiles = userFiles
            if let templates { builder.templates = templates }
            builder.skills = skills
            base = await builder.build()
        }
        // The preamble and the role are the same on every run of this agent: before the changing section.
        return SystemPromptBuilder.insertingStable(preamble + "\n\nYour role (\(agent.name)): " + agent.instructions, into: base)
    }
}

/// A subagent run that started: what the UI lists.
public struct SubagentInfo: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var callID: String?
    public var agent: String
    public var title: String
    public var model: String
    public var started: Date

    public init(id: UUID, callID: String?, agent: String, title: String, model: String, started: Date = Date()) {
        self.id = id
        self.callID = callID
        self.agent = agent
        self.title = title
        self.model = model
        self.started = started
    }
}

/// A running subagent's progress so far.
public struct SubagentProgress: Sendable, Hashable {
    public var id: UUID
    public var steps: Int
    public var toolCalls: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var waitingForApproval: Bool
    /// Not started yet: waiting for a free slot (another run on its model, or another run that writes).
    public var waitingForSlot = false
    /// What it has spent so far (`CostEntry.spent`), summaries included.
    public var cost = 0.0

    public init(id: UUID, steps: Int, toolCalls: Int, promptTokens: Int, completionTokens: Int, waitingForApproval: Bool = false) {
        self.id = id
        self.steps = steps
        self.toolCalls = toolCalls
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.waitingForApproval = waitingForApproval
    }
}

/// Background subagent runs of one main loop: started, finished (their report messages waiting to be delivered),
/// and stopped together when the loop ends.
final class BackgroundRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var reports: [ChatMessage] = []

    /// Starts a run; `work` returns the message that delivers its report.
    func start(_ id: UUID, _ work: @escaping @Sendable () async -> ChatMessage) {
        lock.withLock {
            tasks[id] = Task {
                let m = await work()
                self.lock.withLock { self.tasks[id] = nil; self.reports.append(m) }
            }
        }
    }

    var running: Int { lock.withLock { tasks.count } }

    func takeReports() -> [ChatMessage] { lock.withLock { defer { reports.removeAll() }; return reports } }

    /// Returns when a report is waiting, nothing runs any more, or the task is cancelled.
    func waitForReport() async {
        while !Task.isCancelled, lock.withLock({ reports.isEmpty && !tasks.isEmpty }) {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func cancelAll() { for t in lock.withLock({ Array(tasks.values) }) { t.cancel() } }

    /// Cancels them and waits a moment for their reports.
    func stopAll() async {
        cancelAll()
        for _ in 0..<50 where lock.withLock({ !tasks.isEmpty }) { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

/// Counts runs per key (an endpoint and model, or "writers") and holds runs beyond a key's limit.
public actor SubagentLimiter {
    private var inUse: [String: Int] = [:]

    public init() {}

    /// Takes a slot now if one is free.
    func tryAcquire(_ key: String, limit: Int) -> Bool {
        guard inUse[key, default: 0] < limit else { return false }
        inUse[key, default: 0] += 1
        return true
    }

    /// Waits for a slot; false if `stopped` turned true (or the task was cancelled) first.
    func acquire(_ key: String, limit: Int, stopped: @Sendable () -> Bool) async -> Bool {
        while !tryAcquire(key, limit: limit) {
            if stopped() || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    func release(_ key: String) { inUse[key] = max(0, inUse[key, default: 0] - 1) }
}

/// Stops one subagent run: its report becomes "[Stopped by the user.]" and the main agent goes on. (Stopping the
/// main agent still stops everything, its subagents included.)
public final class SubagentControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancels: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    func register(_ id: UUID, cancel: @escaping @Sendable () -> Void) { lock.withLock { cancels[id] = cancel } }
    func unregister(_ id: UUID) { lock.withLock { cancels[id] = nil } }

    /// The runs that can be stopped now.
    public var running: Set<UUID> { lock.withLock { Set(cancels.keys) } }

    /// Stops a run; false if it isn't running.
    @discardableResult public func stop(_ id: UUID) -> Bool {
        guard let cancel = lock.withLock({ cancels[id] }) else { return false }
        cancel()
        return true
    }
}

/// Records each subagent run as a child session of `parent` (in its `.subagents/` folder), live: its system prompt
/// (kept whether or not the wire log is on), the prompt, each
/// reply and tool result, compactions, and how it ended. With `recordWire`, its requests go to its own wire log.
public struct SubagentRecorder: Sendable {
    public var store: SessionStore
    public var parent: SessionHeader
    public var recordWire: Bool

    public init(store: SessionStore, parent: SessionHeader, recordWire: Bool = true) {
        self.store = store
        self.parent = parent
        self.recordWire = recordWire
    }
}

/// The main agent's way to delegate: runs a subagent with a fresh context and returns its final report.
/// Its own risk is read: the subagent's calls go through the same permission policy and approvals.
public struct TaskTool: Tool {
    let agents: [AgentDefinition]
    /// Where its description comes from (`tool-task.md`).
    var templates = PromptTemplates(overrides: [])
    let runner: @Sendable (_ agent: AgentDefinition, _ description: String, _ prompt: String, _ context: ToolContext,
                           _ background: Bool, _ isolated: Bool, _ card: TaskCard) async -> ToolOutput
    public let name = "task"
    public let risk = ToolRisk.read

    public var description: String {
        let list = agents.map { "\($0.name) (\($0.description))" }.joined(separator: "; ")
        let text = templates.render("tool-task", ["agents": list])
        return text.isEmpty ? "Hand a self-contained task to a subagent. Agents: " + list : text
    }

    public var parameters: JSONValue {
        let own: [String: JSONValue] = [
             "description": ["type": "string", "description": "A short title for the task, 3 to 6 words."],
             "prompt": ["type": "string", "description": "The complete task, with all the context the subagent needs."],
             "agent": ["type": "string", "enum": .array(agents.map { .string($0.name) }),
                       "description": "Which agent to use. Default: general."],
             "background": ["type": "boolean",
                            "description": "Run it in the background (agents that only read, or any agent with isolation): its report arrives later as a message."],
             "isolation": ["type": "string", "enum": ["worktree"],
                           "description": "worktree: it works on a branch of its own in a separate checkout, so it can change files alongside you and other subagents. Nothing is merged; its report names the branch."],
        ]
        return ["type": "object",
                "properties": .object(own.merging(TaskCard.parameters) { a, _ in a }),
                "required": ["description", "prompt"]]
    }

    public func summary(_ args: ToolArguments) -> String { Self.summary(args) }

    static func summary(_ args: ToolArguments) -> String {
        "Task (\(args.string("agent") ?? "general")): \(args.string("description") ?? "")"
    }

    /// For a stored call: "Task (explore): Find the parser".
    public static func summary(forCallNamed name: String, arguments: String) -> String? {
        guard name == "task" else { return nil }
        return summary((try? ToolArguments(json: arguments)) ?? ToolArguments())
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let prompt = try args.require("prompt")
        let name = (args.string("agent") ?? "general").lowercased()
        guard let agent = agents.first(where: { $0.name == name }) else {
            throw ToolFailure("there's no agent named \(name). Agents: \(agents.map(\.name).joined(separator: ", ")).")
        }
        return await runner(agent, args.string("description") ?? "", prompt, context, args.bool("background") ?? false,
                            agent.isolated || args.string("isolation") == "worktree", TaskCard(args))
    }
}

/// `isolation: worktree` from an agent's file.
private func withIsolation(_ value: String?, _ agent: AgentDefinition) -> AgentDefinition {
    var a = agent
    a.isolated = value?.trimmingCharacters(in: .whitespaces).lowercased() == "worktree"
    return a
}

extension AgentLoop {
    /// Runs one subagent to the end and returns its report as the task's result. Its steps stream to the task
    /// card as progress; with `setup.recorder` the run is recorded as a child session (`subagentRun` links it).
    /// It never writes to the parent's wire log: its requests are its own (in its child's wire log, or none).
    /// The tools an agent gets: its listed ones from the main agent's (all of them if it lists none), never `task`.
    /// Names may be kurtkode's (`read_file`) or Claude Code's (`Read`, `Grep`, `Bash`, `MultiEdit`), so a Claude Code
    /// agent file works as written (it used to get no tools at all); `mcp__server` lists all of a server's tools.
    static func subagentTools(_ agent: AgentDefinition, parent: AgentConfig) -> [any Tool] {
        let own = parent.tools.filter { $0.name != "task" }
        guard let listed = agent.tools else { return own }
        let names = Set(listed.flatMap { name -> [String] in
            if name == "MultiEdit" { return ["edit_file"] }
            return [name] + PermissionRules.claudeNames.filter { $0.value == name }.map(\.key)
        })
        return own.filter { tool in
            names.contains(tool.name)
                || (tool.name.hasPrefix("mcp__") && (names.contains("mcp") || names.contains { $0.hasPrefix("mcp__") && tool.name.hasPrefix($0 + "__") }))
        }
    }

    /// - Parameters:
    ///   - retry: set on a second attempt (D3): the failed run, and the model to use instead of resolving one.
    static func runSubagent(_ agent: AgentDefinition, title: String, prompt: String, context: ToolContext,
                            setup: SubagentSetup, parent: AgentConfig, client: ChatClient, model: String,
                            workspace: Workspace?, emit: @escaping @Sendable (AgentEvent) async -> Void,
                            runID: UUID = UUID(), card: TaskCard = TaskCard(), registry: TaskRuns? = nil,
                            isolated: Bool = false, retry: (of: UUID, model: SubagentModel, note: String)? = nil) async -> ToolOutput {
        let tools = subagentTools(agent, parent: parent)
        let original = prompt
        // In a worktree of its own it sees the project there; the parent's folders stay the parent's.
        var isolation: IsolatedRun?
        var workspace = workspace
        if isolated {
            guard let root = workspace?.root else { return .error("isolation needs a project folder.") }
            do {
                let run = try await IsolatedRun.start(from: root, id: runID)
                isolation = run
                workspace = Workspace(root: run.root)
            } catch { return .error("couldn't make a worktree for this subagent: \(error.localizedDescription)") }
        }
        let prompt = (isolation.map { $0.note + "\n\n" } ?? "") + SubagentSetup.taskText(prompt, card: card) + (retry.map { "\n\n" + $0.note } ?? "")
        let chosen: SubagentModel?
        if let retry { chosen = retry.model } else { chosen = await setup.resolveModel?(agent, card) }
        var config = parent
        config.tools = tools
        config.subagents = nil                       // no subagents of subagents
        config.askUser = nil                         // the main agent asks the user; a subagent reports back
        config.presentPlan = nil                     // and presents plans
        config.memoryHome = nil                      // and keeps the project's memory
        config.snapshots = nil                       // the main run's snapshots cover its subagents' changes
        config.previousReply = nil                   // its cache starts with its own first request
        config.promptCacheHour = parent.subagentCacheHour   // its requests follow each other within seconds
        config.sameToolsInEveryMode = false          // read-only in plan mode by what it's given
        // Runs of one kind under one session share a cache key: their prompts start alike (Codex keys its sub-requests
        // the same way).
        config.cacheKey = parent.cacheKey.map { "\(agent.name):\($0)" }
        config.costScope = CostScope(run: runID, agent: agent.name, parentRun: parent.costScope?.run, taskCall: context.callID,
                                     definitionHash: RunTracker.hash([agent.name, agent.instructions, (agent.tools ?? ["(all)"]).joined(separator: ","),
                                                                      agent.model ?? ""].joined(separator: "\u{0}")),
                                     card: card.isEmpty ? nil : card, attemptOf: retry?.of)
        if let names = agent.tools, !names.contains("skill") { config.skills = [] }
        // The run's own edits, so a failed run's can be undone before it's tried again (as well as the parent's
        // snapshots, which a rewind of the turn uses). Edits made by shell commands aren't captured.
        let undo = CheckpointStore(directory: (setup.attemptStore ?? SubagentSetup.defaultAttemptStore).appending(path: "kk-attempt-\(runID.uuidString)"))
        defer { try? FileManager.default.removeItem(at: undo.directory) }
        // What a restore may touch: the run's project (its worktree, when isolated) and the folders it may write.
        let undoRoots = [workspace?.root].compactMap { $0 } + (workspace?.folders ?? []).filter(\.writable).map(\.url)
        let parentCheckpoint = config.checkpoint
        config.checkpoint = { urls in
            try await parentCheckpoint?(urls)
            for u in urls { try await undo.snapshot(u, turn: runID) }
        }
        config.maxSteps = setup.maxSteps
        config.summary = nil
        config.facts = nil
        config.takeInput = nil
        // Its cd and exports don't change the main agent's shell; it starts with the main agent's.
        config.shell = ShellState(cwd: isolation?.root ?? context.shell.cwd, exported: context.shell.exported, unset: context.shell.unset,
                                  sandboxed: context.shell.sandboxed)
        // Its files aren't the parent's: rewinding the parent has nothing to do with them.
        if isolation != nil { config.checkpoint = { urls in for u in urls { try await undo.snapshot(u, turn: runID) } } }
        config.wireLog = nil
        if let m = chosen {
            config.historyShape = m.historyShape
            config.temperature = m.temperature
            config.providers = m.providers          // the main model's provider preferences don't apply
            config.reasoning = nil                  // nor its reasoning setting
            config.reasoningEffort = m.reasoning
            config.endpointID = m.endpointID
            config.sendImages = m.sendImages
            // A subagent on Claude or Gemini thinks within its output limit: give it those APIs' limits.
            if m.client.api != .openai, let native = config.nativeLimits {
                config.limits.maxTokens = max(config.limits.maxTokens, native.maxTokens)
                config.limits.wallClock = max(config.limits.wallClock, native.wallClock)
            }
            if let limit = m.contextLimit {
                config.context = ContextBudget(limit: limit, outputReserve: config.limits.maxTokens)
                config.maxToolOutputBytes = AgentConfig.toolOutputBytes(contextLimit: limit)
            }
        }
        final class Log: @unchecked Sendable {
            let lock = NSLock()
            var messages: [ChatMessage] = []
            var steps: [String] = []
            var stop: AgentStop?
            /// The run's record (`AgentEvent.runEnded`), for the totals on its end record.
            var run: AgentRunRecord?
            /// Its billed requests so far, for the progress events' cost.
            var costs: [CostEntry] = []
            /// Its first reply has started streaming (a fan-out's siblings may go: `CacheWarmup`).
            var warmed = false
            /// Where it stands, for the progress events.
            func progress(_ id: UUID, waiting: Bool = false) -> SubagentProgress {
                lock.withLock {
                    let usage = messages.compactMap { $0.role == .assistant ? $0.meta?.usage : nil }
                    var p = SubagentProgress(id: id, steps: messages.filter { $0.role == .assistant }.count, toolCalls: steps.count,
                                             promptTokens: usage.map(\.promptTokens).reduce(0, +),
                                             completionTokens: usage.map(\.completionTokens).reduce(0, +), waitingForApproval: waiting)
                    p.cost = costs.compactMap(\.spent).reduce(0, +)
                    return p
                }
            }
        }
        let log = Log()
        // Approval cards say which subagent is asking; the run shows as waiting meanwhile.
        if let approve = parent.approve {
            config.approve = { r in
                await emit(.subagentProgress(log.progress(runID, waiting: true)))
                let answer = await approve(ApprovalRequest(call: r.call, summary: "[\(agent.name) subagent] " + r.summary, risk: r.risk,
                                                           preview: r.preview, suggestedRule: r.suggestedRule, reason: r.reason))
                await emit(.subagentProgress(log.progress(runID)))
                return answer
            }
        }
        let offered = config.policy.offered(tools)
        let system: String
        if let make = setup.systemPrompt { system = await make(agent, offered, config.policy.mode) }
        else { system = await SubagentSetup.defaultPrompt(workspace: workspace, agent: agent, tools: offered, mode: config.policy.mode,
                                                          skills: !config.skills.isEmpty) }

        let started = Date()
        let modelName = chosen?.model ?? model
        let rec = setup.recorder
        var header = SessionHeader(id: runID, endpointID: chosen?.endpointID ?? parent.endpointID ?? rec?.parent.endpointID ?? UUID(),
                                   model: modelName, workspace: rec?.parent.workspace)
        header.parent = rec?.parent.id
        header.parentCallID = context.callID
        header.agent = agent.name
        var created = false
        if let rec {
            do {
                try await rec.store.create(header)
                for r: SessionRecord in [.title(title.isEmpty ? agent.name : title), .permissionMode(config.policy.mode),
                                         .systemPrompt(system), .message(.user(prompt))] {
                    try await rec.store.append(r, to: runID)
                }
                created = true
                if rec.recordWire { config.wireLog = WireLog(directory: rec.store.wireDirectory(for: header)) }
                config.outputDirectory = rec.store.outputDirectory(for: header)
            } catch {}
        }
        let recording = created
        let record: @Sendable (SessionRecord) async -> Void = { r in
            guard recording, let rec else { return }
            try? await rec.store.append(r, to: runID)
        }
        /// A judgment goes in the run's session, and out to the parent's (which keeps a copy).
        let judged: @Sendable (RunJudgment) async -> Void = { j in
            await record(.judgment(j))
            await emit(.judged(j))
        }

        context.progress?("\(agent.name) subagent on \(modelName)\n")
        // Stoppable from the moment it's announced (a Stop before its task exists applies once it does).
        final class StopFlag: @unchecked Sendable {
            let lock = NSLock()
            var stopped = false
            var task: Task<Void, Never>?
            func stop() { lock.withLock { stopped = true; return task }?.cancel() }
            func set(_ t: Task<Void, Never>) { if lock.withLock({ task = t; return stopped }) { t.cancel() } }
        }
        let flag = StopFlag()
        setup.control?.register(runID) { flag.stop() }
        await emit(.subagentStarted(SubagentInfo(id: runID, callID: context.callID, agent: agent.name,
                                                 title: title.isEmpty ? agent.name : title, model: modelName, started: started)))
        let byName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        // Limits: runs on one endpoint and model share its slots, and runs that can change things go one at a time
        // among themselves. A run beyond them waits (shown as waiting for a slot) until one frees, or it's stopped.
        let isStopped: @Sendable () -> Bool = { flag.lock.withLock { flag.stopped } }
        let writes = isolation == nil && offered.contains { $0.risk != .read }
        var keys: [(String, Int)] = []
        if writes { keys.append(("writers", 1)) }
        if let limit = await setup.slots?(chosen?.endpointID ?? parent.endpointID, modelName) {
            keys.append(("\((chosen?.endpointID ?? parent.endpointID)?.uuidString ?? "-")|\(modelName)", max(1, limit)))
        }
        var held: [String] = []
        var admitted = true
        var waited = false
        for (key, limit) in keys {
            if await setup.limiter.tryAcquire(key, limit: limit) { held.append(key); continue }
            if !waited {
                waited = true
                var p = log.progress(runID)
                p.waitingForSlot = true
                await emit(.subagentProgress(p))
                context.progress?("waiting for a free slot…\n")
            }
            guard await setup.limiter.acquire(key, limit: limit, stopped: isStopped) else { admitted = false; break }
            held.append(key)
        }
        if waited, admitted { await emit(.subagentProgress(log.progress(runID))) }
        // The run goes in a task of its own, so it can be stopped alone (`setup.control`); stopping the main agent
        // stops it too.
        let runConfig = config, runClient = chosen?.client ?? client
        // An important run that may change files: the project as it is now, to review its change against (A6).
        var reviewBase: String?
        if card.importance == .high, setup.reviewer != nil, admitted, isolation == nil, let s = parent.snapshots {
            // The session's index as a start, so only files changed since its last snapshot are read again.
            let dir = s.store.gitDir
            try? FileManager.default.copyItem(at: dir.appending(path: "index-\(s.session.uuidString)"), to: dir.appending(path: "index-\(runID.uuidString)"))
            reviewBase = try? await s.store.currentTree(session: runID).tree
        }
        if admitted {
        // In a fan-out, a hosted model's runs of one kind start once the first has begun replying (`CacheWarmup`).
        let warmup = runClient.isThirdParty ? context.cacheWarmup : nil
        let warmKey = "\(agent.name)|\(runConfig.endpointID?.uuidString ?? "")|\(modelName)"
        await warmup?.admit(warmKey)
        let work = Task {
            // Its background commands end with it: nothing else can read or stop them.
            defer { runConfig.shell?.jobs.stopAll() }
            await AgentLoop.run(client: runClient, model: modelName, systemPrompt: system,
                                history: [.user(prompt)], config: runConfig, workspace: workspace) { event in
            switch event {
            case .streaming:
                if let warmup, log.lock.withLock({ () -> Bool in defer { log.warmed = true }; return !log.warmed }) {
                    await warmup.warmed(warmKey)
                }
            case .assistant(let m):
                var lines: [String] = []
                for c in m.toolCalls {
                    let args = (try? ToolArguments(json: c.arguments)) ?? ToolArguments()
                    lines.append("→ " + (byName[c.name]?.summary(args) ?? c.name))
                }
                log.lock.withLock { log.messages.append(m); log.steps += lines }
                for l in lines { context.progress?(l + "\n") }
                await record(.message(m))
                await emit(.subagentProgress(log.progress(runID)))
            case .toolFinished(let m):
                log.lock.withLock { log.messages.append(m) }
                await record(.message(m))
            case .injected(let m):
                await record(.message(m))
            case .compacted(let c):
                await record(.compaction(c))
            case .cost(let e):
                log.lock.withLock {
                    if let i = log.costs.firstIndex(where: { $0.id == e.id }) { log.costs[i] = e } else { log.costs.append(e) }
                }
                await record(.cost(e))
            case .runEnded(let r):
                log.lock.withLock { log.run = r }
                await record(.run(r))
            case .ruleAdded:
                await emit(event)                    // "Always allow" holds for the main agent too
            case .finished(let s):
                log.lock.withLock { log.stop = s }
            default:
                break
            }
            }
        }
        flag.set(work)
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        await warmup?.warmed(warmKey)                // ended without streaming (an error): don't hold the others
        } else {
            log.lock.withLock { log.stop = .cancelled }          // stopped while it waited for a slot
        }
        // Stopped alone (the main agent wasn't): the main agent should carry on without it.
        let stoppedAlone = log.lock.withLock { log.stop } == .cancelled && !Task.isCancelled
        let (messages, steps, stop) = log.lock.withLock { (log.messages, log.steps, log.stop) }
        let final = messages.last(where: { $0.role == .assistant && $0.toolCalls.isEmpty })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // What can be checked without asking anyone; the parent sees any problems with the report.
        let checks = GroundedChecks.evaluate(messages: messages, report: final, stop: stop, maxSteps: setup.maxSteps,
                                             workspace: workspace, verify: card.verify)
        // D3: a run that failed outright is tried once more, a rung up the ladder, within the budget. Decided, and its
        // edits undone, while it still holds its slots, so another writing run can't have changed the same files in
        // between. A failed check isn't retried here: that's the parent's call (SUBAGENT_ROUTING_DESIGN.md §4).
        var planned: (next: SubagentModel, undone: [CheckpointStore.Restored], why: String)?
        if retry == nil, isolation == nil, !checks.retryableFailures.isEmpty, stop != .cancelled, stop != .denied, !Task.isCancelled,
           parent.costMeter?.reached == nil,
           let next = await setup.retryModel?(agent, chosen?.endpointID ?? parent.endpointID, modelName,
                                              chosen == nil ? parent.reasoningEffort : chosen?.reasoning) {
            // If its edits can't all be undone, the project is in an unknown state: no retry.
            if let undone = try? await undo.restore(turns: [runID], only: nil, within: undoRoots) {
                planned = (next, undone, checks.retryableFailures.joined(separator: "; "))
            }
        }
        for key in held { await setup.limiter.release(key) }
        setup.control?.unregister(runID)
        var text = final.isEmpty ? "(The subagent gave no final report.)" : final
        switch stop {
        case .completed, nil: break
        case .stepLimit: text += "\n\n[The subagent stopped at its step limit (\(setup.maxSteps)); the report may be incomplete.]"
        case .costLimit: text += "\n\n[The subagent stopped: the run reached its cost limit; the report may be incomplete.]"
        case .cancelled: text = stoppedAlone ? "[The user stopped this subagent before it finished. Don't run it again; "
            + "carry on without its report.]" : "[Stopped by the user.]"
        case .denied: text += "\n\n[The user denied one of its actions, so it stopped. Don't take that action yourself: "
            + "stop and wait for the user's instructions.]"
        case .truncated: text += "\n\n[Its report was cut off at the output limit.]"
        case .turnStopped(let why): text += "\n\n[It stopped early: \(why).]"
        }
        if stop != .cancelled, !checks.problems.isEmpty {
            text += "\n\n[Automatic checks: " + checks.problems.joined(separator: "; ") + ".]"
        }
        if let isolation { text += await isolation.finish(title: title) }
        if let hooks = parent.hooks {
            for e in await hooks.subagentStop(agent: agent.name, report: text).errors { await emit(.hookNotice(e)) }
        }
        let replies = messages.filter { $0.role == .assistant }
        let usage = replies.compactMap { $0.meta?.usage }
        let note = SubagentSetup.reportNote(agent: agent.name)
        let (body, truncated) = BashTool.capHeadTail(text, maxBytes: max(1000, context.maxOutputBytes - note.utf8.count))
        let capped = stop == .cancelled ? body : body + note
        var end = SubagentEnd(stop: stop.map { "\($0)" } ?? "completed", steps: replies.count,
                              toolCalls: steps.count, promptTokens: usage.map(\.promptTokens).reduce(0, +),
                              completionTokens: usage.map(\.completionTokens).reduce(0, +),
                              seconds: Date().timeIntervalSince(started), report: text)
        end.agent = agent.name
        if let r = log.lock.withLock({ log.run }) {
            end.listPrice = r.totals.listPrice.total
            let spent = log.lock.withLock { log.costs }.compactMap(\.spent)
            end.spent = spent.isEmpty ? nil : spent.reduce(0, +)
            end.requests = r.totals.requests
            end.unpricedRequests = r.totals.unpricedRequests
        }
        end.taskBytes = title.utf8.count + prompt.utf8.count
        end.reportBytes = capped.utf8.count
        end.card = card.isEmpty ? nil : card
        end.attemptOf = retry?.of
        if recording {
            await judged(RunJudgment(run: runID, taskCall: context.callID, judge: .checks, checks: checks))
            // An important task gets a second opinion from the grader model (never the run's own model); not a run
            // that is about to be tried again (its retry is graded instead).
            if card.importance == .high, stop != .cancelled, planned == nil,
               let g = await setup.grader?(chosen?.endpointID ?? parent.endpointID, modelName),
               !(g.model == modelName && g.endpointID == (chosen?.endpointID ?? parent.endpointID)) {
                await emit(.status("Grading the \(agent.name) subagent's report on \(g.model)…"))
                let costs = CostSink(scope: SubagentSetup.judgeScope(parent.costScope, as: "grader"), endpointID: g.endpointID,
                                     emit: { await emit(.cost($0)) })
                let ask = graderPrompt(task: prompt, card: card, report: final, checks: checks, workspace: workspace)
                if let j = await grade(g, prompt: ask, run: runID, taskCall: context.callID, costs: costs,
                                       meter: parent.costMeter, limits: parent.limits) {
                    await judged(j)
                }
            }
        }
        // A6: an important run that changed files is reviewed by another vendor's model; the parent reads the review.
        var reviewNote = ""
        if let base = reviewBase, let snaps = parent.snapshots?.store {
            defer {
                try? FileManager.default.removeItem(at: snaps.gitDir.appending(path: "index-\(runID.uuidString)"))
                try? FileManager.default.removeItem(at: snaps.gitDir.appending(path: "skip-\(runID.uuidString)"))
            }
            if planned == nil, stop != .cancelled, !Task.isCancelled,
               let now = try? await snaps.currentTree(session: runID).tree, now != base,
               let r = await setup.reviewer?(chosen?.endpointID ?? parent.endpointID, modelName) {
                await emit(.status("Reviewing the \(agent.name) subagent's change on \(r.model)…"))
                var diff = (try? await snaps.shadow(["diff", "--no-ext-diff", "--no-color", "-M", base, now])) ?? ""
                // The reviewer is remote (hosted sessions only): files withheld from remote models stay out.
                if r.client.isThirdParty { diff = UnifiedDiff.withholding(diff, patterns: parent.withheldFromRemote).0 }
                var ran = checks.problems
                if let v = checks.verifyCommand { ran.insert("\(v) → exit \(checks.verifyExitCode.map(String.init) ?? "?")", at: 0) }
                let costs = CostSink(scope: SubagentSetup.judgeScope(parent.costScope, as: "reviewer"), endpointID: r.endpointID,
                                     emit: { await emit(.cost($0)) })
                let review = await CodeReview.run(r, prompt: CodeReview.prompt(request: prompt, report: final, checks: ran, diff: diff),
                                                  costs: costs, meter: parent.costMeter, limits: parent.limits)
                if recording { await judged(review.judgment(run: runID, taskCall: context.callID)) }
                if review.verdict != nil { reviewNote = "\n\n[Cross-vendor " + review.text.prefix(1).lowercased() + review.text.dropFirst() + "]" }
            }
        }
        registry?.add(TaskRuns.Entry(callID: context.callID ?? runID.uuidString, run: recording ? runID : nil, title: title,
                                     agent: agent.name, model: modelName, endpointID: chosen?.endpointID ?? parent.endpointID,
                                     stop: end.stop, card: card.isEmpty ? nil : card, thisRun: true))
        await record(.subagentEnd(end))
        await emit(.subagentFinished(id: runID, end: end))
        let display = "\(agent.name) subagent on \(modelName) · \(steps.count) tool calls\n"
            + steps.joined(separator: "\n") + (steps.isEmpty ? "" : "\n\n") + text
        // A run that was stopped, denied, or failed didn't do its task: an error for the main agent (and its hooks).
        let failed: Bool
        switch stop {
        case .cancelled?, .denied?, .turnStopped?: failed = true
        default: failed = false
        }
        if let (next, undone, why) = planned {
            await emit(.status("The \(agent.name) subagent failed on \(modelName) (\(why)); trying again on \(next.model)…"))
            context.progress?("failed on \(modelName) (\(why)); trying again on \(next.model)\n")
            let note = "[kurtkode: an earlier attempt at this task, on another model, failed: \(why)."
                + (undone.isEmpty ? "" : " Its edits were undone: " + undone.map { ($0.path as NSString).lastPathComponent }.joined(separator: ", ") + ".")
                + "]"
            var again = await runSubagent(agent, title: title, prompt: original, context: context, setup: setup, parent: parent,
                                          client: client, model: model, workspace: workspace, emit: emit, card: card,
                                          registry: registry, retry: (runID, next, note))
            let lead = "[The first attempt, on \(modelName), failed (\(why))"
                + (undone.isEmpty ? "" : "; its edits were undone") + ". This is the second attempt, on \(next.model).]\n\n"
            again.text = lead + again.text
            again.display = lead + (again.display ?? "")
            return again
        }
        var output = ToolOutput(text: capped + reviewNote, isError: failed, truncated: truncated, display: display + reviewNote)
        output.subagentRun = recording ? runID : nil
        return output
    }
}
