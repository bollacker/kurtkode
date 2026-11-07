import CryptoKit
import Foundation

/// One agent run, written when it ends (`SessionRecord.run`): what it was asked, how it was set up, what it cost, and
/// how it ended, for judging it later and putting its cost next to how well it did (COST_TRACKING_DESIGN.md).
/// A main run is one send (a user message, or Continue after a pause); a subagent run is one `task` call.
public struct AgentRunRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The user message a main run answers (runs for one message: the first, a /retry, a Continue).
    public var userMessage: UUID?
    /// A subagent run's parent run and the `task` call that started it.
    public var parentRun: UUID?
    public var taskCall: String?
    /// `main`, or the subagent's name.
    public var agent: String
    /// What the agent is: a subagent's definition (instructions, tools, model setting); the main agent's prompt style and
    /// tools. An edited agent hashes differently.
    public var definitionHash: String
    /// The exact system prompt sent (it also holds the date and project facts, so it differs between sessions).
    public var systemPromptHash: String
    public var setup: RunSetup
    public var build: BuildInfo
    /// For a model on this Mac or the local network: the machine and the loaded model.
    public var machine: MachineInfo?
    public var localModel: LocalModelInfo?
    public var task: RunTask
    public var started: Date
    public var ended: Date
    public var totals: RunTotals
    public var outcome: RunOutcome
    /// Subagent runs this run started, with what they cost.
    public var children: [ChildRun]
    /// Filled in later by whatever judges the run (a person, a grader model, tests).
    public var judgment: JSONValue?
    /// A second attempt at a subagent task (D3): the run that failed.
    public var attemptOf: UUID?
    /// How it ended, as far as can be checked without asking anyone (GAP_ANALYSIS.md A3); nil in older records.
    public var signals: RunSignals?
    /// A main run's snapshots of the project's files (C1): its net change is the diff between them.
    public var snapshots: RunSnapshotRefs?
}

/// The snapshot commits (in the project's shadow repository) taken when a main run started and ended.
public struct RunSnapshotRefs: Codable, Sendable, Hashable {
    public var start: String
    /// Nil when the end snapshot failed.
    public var end: String?
    /// What wasn't captured (folders and files over the size limits).
    public var skipped: [String]?
    /// Whether the files differ between the two (commands' changes included); nil without an end snapshot.
    public var changed: Bool?

    public init(start: String, end: String?, skipped: [String], changed: Bool? = nil) {
        self.start = start
        self.end = end
        self.skipped = skipped.isEmpty ? nil : skipped
        self.changed = changed
    }
}

/// Grounded signals about how a run ended, recorded with it: with the user's thumbs and the implicit judgments (a
/// retry, a rewind), the labels main runs are routed by later. Signals, not verdicts: a request to "run the tests and
/// say what fails" ends on a failing check and is fine.
public struct RunSignals: Codable, Sendable, Hashable {
    /// The last test, build, lint or type-check command the run ran, and how it ended.
    public var lastCheck: SessionFacts.Check?
    /// Files it changed whose names the request doesn't mention (a scope signal: many good runs change files nobody
    /// named).
    public var filesNotNamed: [String]
    /// Todo items it left pending or in progress.
    public var unfinishedTodos: [String]
    /// The project's test command (`TestSuite`) run again by kurtkode after the run, and how it ended; nil: not run.
    public var suite: SessionFacts.Check?
    /// The checks of this run's subagent tasks that failed when run again at its end.
    public var failedRechecks: [String]?
    /// The request asked for a change to the files (`Escalation.asksForChange`) and the run's last reply didn't end on
    /// a question to the user; nil in older records.
    public var changeAsked: Bool?

    public init(lastCheck: SessionFacts.Check? = nil, filesNotNamed: [String] = [], unfinishedTodos: [String] = []) {
        self.lastCheck = lastCheck
        self.filesNotNamed = filesNotNamed
        self.unfinishedTodos = unfinishedTodos
    }

    /// From a run's own messages and the request it answered (with its task card, for a subagent task).
    public static func evaluate(_ messages: [ChatMessage], request: String, card: TaskCard? = nil) -> RunSignals {
        var facts = SessionFacts()
        facts.absorb(messages)
        let asked = request.lowercased()
        let notNamed = facts.filesChanged.keys.sorted().filter { path in
            let name = (path as NSString).lastPathComponent.lowercased()
            return !asked.contains(name) && !asked.contains(path.lowercased())
        }
        var s = RunSignals(lastCheck: facts.lastCheck, filesNotNamed: notNamed,
                           unfinishedTodos: facts.todos.filter { $0.status != "completed" }.map(\.content))
        let last = messages.last { $0.role == .assistant && !$0.content.isEmpty }?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        s.changeAsked = Escalation.asksForChange(request, card: card) && last?.hasSuffix("?") != true
        return s
    }

    public var lastCheckFailed: Bool { lastCheck?.failed ?? false }

    /// "the last check failed (exit 1): swift test; 2 todos left unfinished".
    public var problems: [String] {
        var p: [String] = []
        if let c = lastCheck, lastCheckFailed {
            p.append(c.timedOut == true ? "the last check timed out: \(c.command)" : "the last check failed (exit \(c.exitCode.map(String.init) ?? "?")): \(c.command)")
        }
        if let s = suite, s.failed {
            p.append(s.timedOut == true ? "the project's tests timed out after the run" : "the project's tests failed after the run (exit \(s.exitCode.map(String.init) ?? "?"))")
        }
        for c in failedRechecks ?? [] { p.append("a task's check failed when run again: \(c)") }
        if !unfinishedTodos.isEmpty { p.append("\(unfinishedTodos.count) todo\(unfinishedTodos.count == 1 ? "" : "s") left unfinished") }
        if !filesNotNamed.isEmpty { p.append("changed \(filesNotNamed.count) file\(filesNotNamed.count == 1 ? "" : "s") the request doesn't name") }
        return p
    }
}

public struct RunSetup: Codable, Sendable, Hashable {
    public var endpointID: UUID?
    public var api: WireAPI
    public var host: String?
    public var model: String
    public var temperature: Double?
    public var maxOutputTokens: Int
    public var wallClock: Double
    public var maxSteps: Int
    public var promptStyle: String?
    public var webSearch: Bool
    public var promptCacheHour: Bool
    public var tools: [String]
    public var summarizerModel: String?
    public var fallbackModel: String?
    /// The reasoning setting sent: a profile's ("none" or an effort level), or the eval's `reasoning` object as JSON.
    public var reasoning: String?
}

public struct RunTask: Codable, Sendable, Hashable {
    /// The request (the user's message, or the subagent's prompt), up to 4,000 characters.
    public var text: String
    public var bytes: Int
    public var estimatedTokens: Int
    /// SHA-256 of the whole text, to group runs of the same task.
    public var hash: String
    /// A subagent task's card (kind, importance, check), when the parent gave one.
    public var card: TaskCard?
}

/// Sums over a run's own cost entries (its subagents' are in `children`).
public struct RunTotals: Codable, Sendable, Hashable {
    public var requests = 0
    /// List price of the priced requests, by component and in all.
    public var listPrice = ComponentCosts()
    /// Requests without a list price (local models, models missing from the price lists).
    public var unpricedRequests = 0
    /// What the account was charged, where the server said (OpenRouter).
    public var charged: Double?
    /// What it spent: each request's charge where the server said it, else its list price (`CostEntry.spent`), summed. A
    /// run whose summary went to another server has both kinds. Nil in older records and when nothing was priced.
    public var spent: Double?
    public var promptTokens = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0
    public var completionTokens = 0
    public var reasoningTokens = 0
    public var searches = 0
    /// Requests checked against the provider's own record, and what it charged for them.
    public var reconciledRequests = 0
    /// Seconds from the run's start to its end, and the part spent waiting on the model.
    public var wallSeconds = 0.0
    public var modelSeconds = 0.0
}

public struct ComponentCosts: Codable, Sendable, Hashable {
    public var uncachedInput = 0.0
    public var cacheRead = 0.0
    public var cacheWrite5m = 0.0
    public var cacheWrite1h = 0.0
    public var output = 0.0
    public var reasoning = 0.0
    public var searches = 0.0
    public var requests = 0.0
    public var total = 0.0

    mutating func add(_ b: CostBreakdown) {
        uncachedInput += b.uncachedInput
        cacheRead += b.cacheRead
        cacheWrite5m += b.cacheWrite5m
        cacheWrite1h += b.cacheWrite1h
        output += b.output
        reasoning += b.reasoning
        searches += b.searches
        requests += b.requests
        total += b.total
    }
}

public struct RunOutcome: Codable, Sendable, Hashable {
    /// `AgentStop` as text.
    public var stop: String
    public var steps: Int
    public var toolCalls: [String: Int]
    public var toolErrors: Int
    public var denied: Int
    public var filesChanged: [String]
    public var compactions: Int
    /// The last reply's size (a subagent's report, before the note the parent adds).
    public var finalReplyBytes: Int
    public var finalReplyEstimatedTokens: Int
}

public struct ChildRun: Codable, Sendable, Hashable {
    public var run: UUID
    public var agent: String
    public var stop: String
    public var listPrice: Double?
    public var unpricedRequests: Int?
    public var requests: Int?
    /// The charge where the server said it, else list price.
    public var spent: Double?
}

/// Which build of kurtkode made the run: its version, a hash of the running executable, and, when the executable is
/// inside a git checkout (a build of the repository), the commit and whether the tree had changes.
public struct BuildInfo: Codable, Sendable, Hashable {
    public var version: String
    public var executableHash: String?
    public var gitCommit: String?
    public var gitDirty: Bool?

    public static let version = "0.1"

    public static let current: BuildInfo = {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        var info = BuildInfo(version: version)
        if let data = try? Data(contentsOf: exe, options: .mappedIfSafe) {
            info.executableHash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        // A checkout above the executable: Debug builds live in the repository (build/, AgentCore/.build/).
        var dir = exe.deletingLastPathComponent()
        while dir.path.count > 1 {
            if FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) {
                func git(_ args: [String]) -> String? { BuildInfo.git(args, in: dir) }
                info.gitCommit = git(["rev-parse", "--short=12", "HEAD"])
                info.gitDirty = git(["status", "--porcelain", "--untracked-files=no"]).map { !$0.isEmpty }
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        return info
    }()

    init(version: String) { self.version = version }

    /// Git's trimmed output in `dir`, or nil when it fails. Its output is read while it runs (a pipe holds only 64 KB,
    /// and a dirty tree's status can be more), and it's stopped after 30 seconds.
    static func git(_ args: [String], in dir: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + GitRepo.safeConfig + args
        p.environment = GitRepo.environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard let exited = try? p.startWithExitSignal() else { return nil }
        let drain = PipeDrain(out.fileHandleForReading)
        let status = p.waitForExit(exited, timeout: 30)
        guard status == 0, let data = drain.wait(timeout: 2) else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The Mac a local model ran on.
public struct MachineInfo: Codable, Sendable, Hashable {
    public var model: String?          // hw.model, e.g. "Mac14,6"
    public var chip: String?           // machdep.cpu.brand_string, e.g. "Apple M2 Max"
    public var memoryGB: Int?
    public var cores: Int?

    public static let current: MachineInfo = {
        func string(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buf = [UInt8](repeating: 0, count: size)
            guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
            return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
        }
        let memory = ProcessInfo.processInfo.physicalMemory
        return MachineInfo(model: string("hw.model"), chip: string("machdep.cpu.brand_string"),
                           memoryGB: Int((Double(memory) / 1_073_741_824).rounded()), cores: ProcessInfo.processInfo.processorCount)
    }()
}

/// A local model as LM Studio reports it.
public struct LocalModelInfo: Codable, Sendable, Hashable {
    public var arch: String?
    public var quantization: String?
    public var loadedContextLength: Int?
    public var maxContextLength: Int?

    /// From LM Studio's `/api/v0/models` (nil for another server, or one that doesn't answer in two seconds).
    static func lookup(client: ChatClient, model: String) async -> LocalModelInfo? {
        guard client.api == .openai, !client.isThirdParty else { return nil }
        var root = client.baseURL
        if root.lastPathComponent == "v1" { root = root.deletingLastPathComponent() }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        let service = LMStudioService(baseURL: root, session: URLSession(configuration: config))
        guard let info = try? await service.models().first(where: { $0.id == model }) else { return nil }
        return LocalModelInfo(arch: info.arch, quantization: info.quantization, loadedContextLength: info.loadedContextLength,
                              maxContextLength: info.maxContextLength)
    }
}

/// Builds a run's record from its events (`AgentLoop.run` passes every event through it).
final class RunTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var costs: [CostEntry] = []
    private var replies: [ChatMessage] = []
    private var results: [ChatMessage] = []
    private var compactions = 0
    private var children: [ChildRun] = []
    private var failedRechecks: [String] = []
    private let started = Date()

    func observe(_ event: AgentEvent) {
        lock.withLock {
            switch event {
            case .cost(let e):
                // A second record for an entry (its provider's record, fetched later) replaces the first.
                if let i = costs.firstIndex(where: { $0.id == e.id }) { costs[i] = e } else { costs.append(e) }
            case .assistant(let m): replies.append(m)
            case .toolFinished(let m): results.append(m)
            case .compacted: compactions += 1
            case .judged(let j) where j.judge == .recheck && j.checks?.isHardFailure == true:
                if let c = j.checks?.verifyCommand { failedRechecks.append(c) }
            case .subagentFinished(let id, let end):
                children.append(ChildRun(run: id, agent: end.agent ?? "subagent", stop: end.stop, listPrice: end.listPrice,
                                         unpricedRequests: end.unpricedRequests, requests: end.requests, spent: end.spent))
            default: break
            }
        }
    }

    /// Entries with a provider record still to fetch (OpenRouter).
    var unreconciled: [CostEntry] { lock.withLock { costs.filter { $0.generationID != nil } } }

    func record(stop: AgentStop, scope: CostScope, config: AgentConfig, client: ChatClient, model: String, systemPrompt: String,
                history: [ChatMessage], tools: [String], localModel: LocalModelInfo?) -> AgentRunRecord {
        let (costs, replies, results, compactions, children) = lock.withLock { (self.costs, self.replies, self.results, self.compactions, self.children) }
        var totals = RunTotals()
        var charged = 0.0
        var anyCharge = false
        var spent: Double?
        for e in costs {
            if let s = e.spent { spent = (spent ?? 0) + s }
            totals.requests += 1
            if let b = e.listPrice { totals.listPrice.add(b) } else { totals.unpricedRequests += 1 }
            if let c = e.charged { charged += c; anyCharge = true }
            if e.reconciled != nil { totals.reconciledRequests += 1 }
            if let u = e.tokens {
                totals.promptTokens += u.promptTokens
                totals.cacheReadTokens += u.cacheReadTokens ?? 0
                totals.cacheWriteTokens += u.cacheWriteTokens ?? 0
                totals.completionTokens += u.completionTokens
                totals.reasoningTokens += u.reasoningTokens
                totals.searches += u.webSearches ?? 0
            }
            totals.modelSeconds += e.duration
        }
        totals.charged = anyCharge ? charged : nil
        totals.spent = spent
        let now = Date()
        totals.wallSeconds = now.timeIntervalSince(started)

        var calls: [String: Int] = [:]
        for m in replies { for c in m.toolCalls { calls[c.name, default: 0] += 1 } }
        var facts = SessionFacts()
        facts.absorb(replies + results)
        let final = replies.last(where: { $0.toolCalls.isEmpty })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let outcome = RunOutcome(stop: "\(stop)", steps: replies.count, toolCalls: calls,
                                 toolErrors: results.filter { $0.toolResult?.isError == true }.count,
                                 denied: results.filter { $0.toolResult?.denied == true }.count,
                                 filesChanged: facts.filesChanged.keys.sorted(), compactions: compactions,
                                 finalReplyBytes: final.utf8.count, finalReplyEstimatedTokens: (final.utf8.count + 3) / 4)

        let taskText = history.last(where: { $0.role == .user && $0.contextNote != true })?.content
            ?? history.last(where: { $0.role == .user })?.content ?? ""
        let task = RunTask(text: String(taskText.prefix(4000)), bytes: taskText.utf8.count,
                           estimatedTokens: (taskText.utf8.count + 3) / 4, hash: Self.hash(taskText),
                           card: scope.card?.isEmpty == false ? scope.card : nil)
        let setup = RunSetup(endpointID: config.endpointID, api: client.api, host: client.baseURL.host(), model: model,
                             temperature: config.temperature, maxOutputTokens: config.limits.maxTokens,
                             wallClock: config.limits.wallClock, maxSteps: config.maxSteps, promptStyle: scope.promptStyle,
                             webSearch: config.webSearch, promptCacheHour: config.promptCacheHour, tools: tools,
                             summarizerModel: config.summarizer?.model, fallbackModel: config.fallback?.model,
                             reasoning: config.reasoning.flatMap { r in
                                 let enc = JSONEncoder()
                                 enc.outputFormatting = .sortedKeys        // the same setting, the same text
                                 return (try? enc.encode(r)).map { String(decoding: $0, as: UTF8.self) }
                             } ?? config.reasoningEffort)
        let definition = scope.definitionHash ?? Self.hash("main\u{0}\(scope.promptStyle ?? "")\u{0}" + tools.joined(separator: ","))
        let local = client.api == .openai && !client.isThirdParty
        return AgentRunRecord(id: scope.run ?? UUID(), userMessage: scope.userMessage, parentRun: scope.parentRun,
                              taskCall: scope.taskCall, agent: scope.agent, definitionHash: definition,
                              systemPromptHash: Self.hash(systemPrompt), setup: setup, build: .current,
                              machine: local ? .current : nil, localModel: localModel, task: task, started: started, ended: now,
                              totals: totals, outcome: outcome, children: children, judgment: nil,
                              attemptOf: scope.attemptOf, signals: {
                                  var s = RunSignals.evaluate(replies + results, request: taskText, card: task.card)
                                  if !failedRechecks.isEmpty { s.failedRechecks = failedRechecks }
                                  return s
                              }())
    }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// Records written before a field was added still decode (synthesized Codable needs every key, defaults or not).
extension RunTotals {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        listPrice = try c.decodeIfPresent(ComponentCosts.self, forKey: .listPrice) ?? ComponentCosts()
        unpricedRequests = try c.decodeIfPresent(Int.self, forKey: .unpricedRequests) ?? 0
        charged = try c.decodeIfPresent(Double.self, forKey: .charged)
        promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        cacheWriteTokens = try c.decodeIfPresent(Int.self, forKey: .cacheWriteTokens) ?? 0
        completionTokens = try c.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        reasoningTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        searches = try c.decodeIfPresent(Int.self, forKey: .searches) ?? 0
        reconciledRequests = try c.decodeIfPresent(Int.self, forKey: .reconciledRequests) ?? 0
        wallSeconds = try c.decodeIfPresent(Double.self, forKey: .wallSeconds) ?? 0
        modelSeconds = try c.decodeIfPresent(Double.self, forKey: .modelSeconds) ?? 0
    }
}

extension ComponentCosts {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        uncachedInput = try c.decodeIfPresent(Double.self, forKey: .uncachedInput) ?? 0
        cacheRead = try c.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheWrite5m = try c.decodeIfPresent(Double.self, forKey: .cacheWrite5m) ?? 0
        cacheWrite1h = try c.decodeIfPresent(Double.self, forKey: .cacheWrite1h) ?? 0
        output = try c.decodeIfPresent(Double.self, forKey: .output) ?? 0
        reasoning = try c.decodeIfPresent(Double.self, forKey: .reasoning) ?? 0
        searches = try c.decodeIfPresent(Double.self, forKey: .searches) ?? 0
        requests = try c.decodeIfPresent(Double.self, forKey: .requests) ?? 0
        total = try c.decodeIfPresent(Double.self, forKey: .total) ?? 0
    }
}
