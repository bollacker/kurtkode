import Foundation

/// Written once, as the first line of a session file.
public struct SessionHeader: Codable, Sendable, Hashable {
    public var version: Int = 1
    public var id: UUID
    public var createdAt: Date
    public var endpointID: UUID
    public var model: String
    /// Project folder the agent works in. Nil for plain chats (Phase 1).
    public var workspace: String?
    /// A subagent run: the session that started it, its `task` call, and the agent. The run is stored in the
    /// parent's `<id>.subagents/` folder and is never listed as a session of its own.
    public var parent: UUID?
    public var parentCallID: String?
    public var agent: String?
    /// A fork: the session it was copied from, the turn (its reply id), and whether it starts after that turn.
    public var forkedFrom: UUID?
    public var forkedAtReply: UUID?
    public var forkedAfter: Bool?

    public init(id: UUID = UUID(), createdAt: Date = Date(), endpointID: UUID, model: String, workspace: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.endpointID = endpointID
        self.model = model
        self.workspace = workspace
    }

    public var isSubagent: Bool { parent != nil }
}

/// How a subagent run ended: the last record of its session.
public struct SubagentEnd: Codable, Sendable, Hashable {
    /// `AgentStop` as text: completed, stepLimit, cancelled, denied, truncated, or the reason it stopped early.
    public var stop: String
    /// Model turns and tool calls.
    public var steps: Int
    public var toolCalls: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var seconds: Double
    /// What the main agent got back (before the "final report" note).
    public var report: String
    /// The agent's name, and what the run cost: the list price of its priced requests, how many it made, and how many
    /// had no price. Older records have none of these.
    public var agent: String?
    public var listPrice: Double?
    /// What it spent: the charge where the server said it, else list price (`CostEntry.spent`).
    public var spent: Double?
    public var requests: Int?
    public var unpricedRequests: Int?
    /// Sizes of the task the parent wrote and of what it read back (the report as returned, note included). Their cost
    /// is the parent's; the sizes are for analysis.
    public var taskBytes: Int?
    public var reportBytes: Int?
    /// The task's card, as the parent gave it.
    public var card: TaskCard?
    /// A second attempt (D3): the failed run it retries.
    public var attemptOf: UUID?

    public init(stop: String, steps: Int, toolCalls: Int, promptTokens: Int, completionTokens: Int, seconds: Double, report: String) {
        self.stop = stop
        self.steps = steps
        self.toolCalls = toolCalls
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.seconds = seconds
        self.report = report
    }
}

/// One line of a session's JSONL file. Exactly one payload field is set, named by `type`.
public struct SessionRecord: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case header, message, title, model, retract, permissionMode, compaction, folders, subagentEnd, systemPrompt, cost, run, judgment
        case escalation
    }

    public var type: Kind
    public var header: SessionHeader?
    public var message: ChatMessage?
    public var title: String?
    /// Model switch mid-session; later turns use it. With `endpointID`, the switch can be to another server.
    public var model: String?
    public var endpointID: UUID?
    /// Removes an earlier message (retry, rewind). The file stays append-only.
    public var retracted: UUID?
    public var permissionMode: PermissionMode?
    public var compaction: Compaction?
    /// The session's extra folders, all of them (each record replaces the last).
    public var folders: [ExtraFolder]?
    public var subagentEnd: SubagentEnd?
    /// The system prompt a subagent run was given, or a session's base prompt (`FrozenSystemPrompt`), with what it
    /// was built for and the date and git status it states.
    public var systemPrompt: String?
    public var systemPromptKey: String?
    public var systemPromptFacts: String?
    /// A billed request (`CostEntry`).
    public var cost: CostEntry?
    /// An agent run's record, at its end (`AgentRunRecord`).
    public var run: AgentRunRecord?
    /// A judgment of a subagent run (`RunJudgment`): in the run's own session and, copied, in its parent's.
    public var judgment: RunJudgment?
    /// An offer to escalate to a stronger model (A4), written when it's made and again when the user decides.
    public var escalation: EscalationOffer?
    /// When the record was written (set on append).
    public var at: Date?

    public static func header(_ h: SessionHeader) -> SessionRecord { SessionRecord(type: .header, header: h) }
    public static func message(_ m: ChatMessage) -> SessionRecord { SessionRecord(type: .message, message: m) }
    public static func title(_ t: String) -> SessionRecord { SessionRecord(type: .title, title: t) }
    public static func model(_ m: String, endpoint: UUID? = nil) -> SessionRecord {
        SessionRecord(type: .model, model: m, endpointID: endpoint)
    }
    public static func retract(_ id: UUID) -> SessionRecord { SessionRecord(type: .retract, retracted: id) }
    public static func permissionMode(_ m: PermissionMode) -> SessionRecord { SessionRecord(type: .permissionMode, permissionMode: m) }
    public static func compaction(_ c: Compaction) -> SessionRecord { SessionRecord(type: .compaction, compaction: c) }
    public static func folders(_ f: [ExtraFolder]) -> SessionRecord { SessionRecord(type: .folders, folders: f) }
    public static func subagentEnd(_ e: SubagentEnd) -> SessionRecord { SessionRecord(type: .subagentEnd, subagentEnd: e) }
    public static func cost(_ e: CostEntry) -> SessionRecord { SessionRecord(type: .cost, cost: e) }
    public static func run(_ r: AgentRunRecord) -> SessionRecord { SessionRecord(type: .run, run: r) }
    public static func judgment(_ j: RunJudgment) -> SessionRecord { SessionRecord(type: .judgment, judgment: j) }
    public static func escalation(_ e: EscalationOffer) -> SessionRecord { SessionRecord(type: .escalation, escalation: e) }
    public static func systemPrompt(_ s: String) -> SessionRecord { SessionRecord(type: .systemPrompt, systemPrompt: s) }
    public static func systemPrompt(_ p: RecordedPrompt) -> SessionRecord {
        SessionRecord(type: .systemPrompt, systemPrompt: p.text, systemPromptKey: p.key, systemPromptFacts: p.facts)
    }
}

/// A change during a session that isn't a message: another model, permission mode, set of folders, or title.
public struct SessionEvent: Sendable, Hashable {
    public enum Kind: String, Sendable { case model, mode, folders, title }
    public var kind: Kind
    public var text: String
    public var at: Date

    init?(_ r: SessionRecord, at: Date) {
        self.at = at
        switch r.type {
        case .model: kind = .model; text = r.model ?? "?"
        case .permissionMode: kind = .mode; text = r.permissionMode?.displayName ?? "?"
        case .folders:
            kind = .folders
            let f = r.folders ?? []
            text = f.isEmpty ? "no other folders" : f.map { $0.displayPath + ($0.writable ? "" : " (read-only)") }.joined(separator: ", ")
        case .title: kind = .title; text = r.title ?? ""
        default: return nil
        }
    }
}

/// A session as reconstructed from its file.
public struct Session: Sendable, Hashable {
    public var header: SessionHeader
    public var messages: [ChatMessage]
    public var title: String?
    public var model: String
    /// The endpoint for the next turn; starts as the header's, changes with model switches.
    public var endpointID: UUID
    public var permissionMode: PermissionMode?
    /// Every compaction, oldest first. Rewinding past one's boundary makes it stale.
    public var compactions: [Compaction]
    /// Folders outside the project (or a chat's working folder) the agent may also use.
    public var folders: [ExtraFolder] = []
    /// Changes of model, mode, folders, and title, in order (those written with a time).
    public var events: [SessionEvent] = []
    /// A subagent run's ending; nil while it runs (or if it was cut off).
    public var subagentEnd: SubagentEnd?
    /// A subagent run's system prompt, as recorded at its start, or a session's latest base prompt (no summary).
    public var systemPrompt: String?
    /// The base system prompt a session last recorded, for a later process to send again (`FrozenSystemPrompt`).
    public var recordedPrompt: RecordedPrompt?
    /// Every billed request, in the order recorded (retracted replies' entries stay: they were paid for).
    public var costs: [CostEntry] = []

    /// The main agent's last reply request: where the session's prompt cache stands (`CacheLedger.coldResumeNote`).
    public var lastReplyCost: CostEntry? {
        costs.last { $0.agent == "main" && ($0.purpose == .reply || $0.purpose == .nudgedReply) }
    }
    /// Every agent run's record, in the order they ended.
    public var runs: [AgentRunRecord] = []
    /// Judgments of subagent runs: this run's own (a child session) or its runs' (copies, in a parent).
    public var judgments: [RunJudgment] = []
    /// Escalation offers (A4), each as last recorded (offered, then accepted or declined).
    public var escalations: [EscalationOffer] = []

    public init(header: SessionHeader, messages: [ChatMessage], title: String? = nil, model: String,
                endpointID: UUID? = nil, permissionMode: PermissionMode? = nil, compactions: [Compaction] = []) {
        self.header = header
        self.messages = messages
        self.title = title
        self.model = model
        self.endpointID = endpointID ?? header.endpointID
        self.permissionMode = permissionMode
        self.compactions = compactions
    }

    /// Progress over the whole session, from every message including those before compactions.
    public var facts: SessionFacts {
        var f = SessionFacts()
        f.absorb(messages, root: header.workspace)
        return f
    }

    /// The latest compaction whose boundary message still exists.
    public var activeCompaction: Compaction? {
        let ids = Set(messages.map(\.id))
        return compactions.last { ids.contains($0.lastSummarizedID) }
    }

    /// What the model sees: messages after the active compaction's boundary (with its continuation turn
    /// when needed), and the summary for the system prompt.
    public var modelHistory: (messages: [ChatMessage], summary: String?) {
        guard let c = activeCompaction, let i = messages.firstIndex(where: { $0.id == c.lastSummarizedID }) else {
            return (messages, nil)
        }
        var rest = Array(messages[(i + 1)...])
        if let lastKept = c.lastKeptID, let k = rest.firstIndex(where: { $0.id == lastKept }) {
            rest.replaceSubrange(0...k, with: Compactor.trimKept(Array(rest[0...k])))
        }
        if let cont = c.continuation, rest.first?.role != .user { rest.insert(.user(cont), at: 0) }
        return (rest, c.modelText)
    }

    public var displayTitle: String { title ?? Self.defaultTitle(for: messages) }

    static func defaultTitle(for messages: [ChatMessage]) -> String {
        guard let firstMessage = messages.first(where: { $0.role == .user }) else { return "New chat" }
        var first = firstMessage.userCommand.map { "!" + $0.command } ?? firstMessage.content
        if first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, firstMessage.images?.isEmpty == false { first = "Image" }
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }
}

/// A session a search found, and the words around the match.
public struct SessionSearchHit: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var snippet: String

    /// One line: some words before the match and more after it, marked where cut.
    static func snippet(_ text: String, around match: Range<String.Index>) -> String {
        let from = text.index(match.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let to = text.index(match.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let line = text[from..<to].split(whereSeparator: \.isNewline).joined(separator: " ")
        return (from > text.startIndex ? "…" : "") + line + (to < text.endIndex ? "…" : "")
    }
}

public struct SessionSummary: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var model: String
    public var workspace: String?
    public var updatedAt: Date
    public var messageCount: Int
    /// The endpoint the session uses now.
    public var endpointID: UUID?

    public init(id: UUID, title: String, model: String, workspace: String?, updatedAt: Date, messageCount: Int,
                endpointID: UUID? = nil) {
        self.endpointID = endpointID
        self.id = id
        self.title = title
        self.model = model
        self.workspace = workspace
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}

/// Append-only JSONL session files, one per session (D7), under `root/<project>/<id>.jsonl`.
/// Plain chats without a workspace go in `root/_chats/`.
public actor SessionStore {
    public nonisolated let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) {
        self.root = root
        // ISO 8601 with milliseconds: readable in the file, and fine-grained enough to order messages.
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(date.formatted(style))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let d = try? style.parse(s) { return d }
            return try Date.ISO8601FormatStyle().parse(s)
        }
    }

    /// Folder name for a workspace: its last path component plus a short hash of the full path, so two
    /// folders with the same name don't collide and the directory stays readable.
    public static func projectKey(for workspace: String?) -> String {
        guard let workspace else { return "_chats" }
        var hash: UInt64 = 14_695_981_039_346_656_037            // FNV-1a
        for b in workspace.utf8 { hash = (hash ^ UInt64(b)) &* 1_099_511_628_211 }
        let name = URL(fileURLWithPath: workspace).lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return "\(name)-\(String(hash, radix: 16).prefix(8))"
    }

    /// The folder a session's file and its companions live in: the project's, or for a subagent run, its parent's
    /// `<parent>.subagents/` (one level deeper, so listings skip it).
    nonisolated func folder(for header: SessionHeader) -> URL {
        let project = root.appending(path: Self.projectKey(for: header.workspace))
        guard let parent = header.parent else { return project }
        return project.appending(path: "\(parent.uuidString).subagents")
    }

    /// Where a session's subagent runs are stored.
    public nonisolated func subagentDirectory(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).subagents")
    }

    /// Where a session keeps full tool outputs that were too long to send.
    public nonisolated func outputDirectory(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).outputs")
    }

    /// Where a session's attached images live, next to its file.
    public nonisolated func imagesDirectory(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).images")
    }

    /// Where a session's wire log (each model request and its raw response) lives, next to its file.
    public nonisolated func wireDirectory(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).wire")
    }

    /// The project's snapshots (C1): a shadow repository beside the sessions folder; nil for the home folder or the root.
    public nonisolated func snapshots(for project: URL) -> ProjectSnapshots? {
        ProjectSnapshots.allowed(project) ? ProjectSnapshots(project: project, root: root.deletingLastPathComponent().appending(path: "snapshots")) : nil
    }

    /// Where a session's undo snapshots live, next to its file.
    public nonisolated func checkpointDirectory(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).checkpoints")
    }

    /// The session's JSONL file (hooks get it as transcript_path).
    public nonisolated func fileURL(for header: SessionHeader) -> URL {
        folder(for: header).appending(path: "\(header.id.uuidString).jsonl")
    }

    private var locations: [UUID: URL] = [:]
    /// Each session file's size after this store last read or wrote it. Another process (the app and the command
    /// line share sessions) that appends makes the file bigger than that.
    private var knownSizes: [UUID: UInt64] = [:]
    /// Sessions another process appended to since this store last loaded them.
    private var changedByOthers: Set<UUID> = []

    public func create(_ header: SessionHeader) throws {
        let url = fileURL(for: header)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try line(.header(header))
        try data.write(to: url, options: .withoutOverwriting)
        locations[header.id] = url
        knownSizes[header.id] = UInt64(data.count)
    }

    public func append(_ record: SessionRecord, to id: UUID) throws {
        guard let url = try location(of: id) else { throw CocoaError(.fileNoSuchFile) }
        var record = record
        if record.at == nil { record.at = Date() }
        let (before, after) = try JSONLines.append(try line(record), to: url)
        if let known = knownSizes[id], before != known { changedByOthers.insert(id) }
        knownSizes[id] = after
    }

    /// Appends to one subagent run's file, the one in `parent`'s folder. A fork holds copies of its original's runs with
    /// the same ids, so the id alone can mean either file: a record meant for this session's run (a judgment) goes by
    /// where the caller found the run.
    public func append(_ record: SessionRecord, toRun id: UUID, of parent: SessionHeader) throws {
        let url = subagentDirectory(for: parent).appending(path: "\(id.uuidString).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        locations[id] = url
        try append(record, to: id)
    }

    public func load(_ id: UUID) throws -> Session? {
        guard let url = try location(of: id) else { return nil }
        let data = try Data(contentsOf: url)
        knownSizes[id] = UInt64(data.count)
        changedByOthers.remove(id)
        return try parse(data)
    }

    /// The session file's size after this store last read or wrote it (nil if it hasn't).
    public func knownSize(_ id: UUID) -> UInt64? { knownSizes[id] }

    /// Whether another process wrote to this session since this store last loaded it: its file grew by more than
    /// this store wrote. False for a session this store hasn't loaded or written.
    public func changedElsewhere(_ id: UUID) -> Bool {
        if changedByOthers.contains(id) { return true }
        guard let known = knownSizes[id], let url = try? location(of: id),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return false }
        return size.uint64Value != known
    }

    /// All sessions, newest first.
    public func list() throws -> [SessionSummary] {
        var out: [SessionSummary] = []
        for url in try sessionFiles() {
            guard let data = try? Data(contentsOf: url), let s = try? parse(data) else { continue }
            locations[s.header.id] = url
            let updated = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? s.header.createdAt
            out.append(SessionSummary(id: s.header.id, title: s.displayTitle, model: s.model,
                                      workspace: s.header.workspace, updatedAt: updated,
                                      messageCount: s.messages.count, endpointID: s.endpointID))
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Sessions whose conversation holds `query`, with the words around its first appearance. Quick on sessions without
    /// it: their files are only looked through. Case and accents don't matter.
    public func search(_ query: String, limit: Int = 100) throws -> [SessionSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        // A file holds JSON, where these are written escaped: such a query can't be looked for in the raw text.
        let raw = !q.contains { "\"\\/".contains($0) || $0.isNewline || !$0.isASCII }
        var out: [SessionSearchHit] = []
        for url in try sessionFiles() {
            if Task.isCancelled || out.count >= limit { break }
            guard let data = try? Data(contentsOf: url) else { continue }
            if raw, String(decoding: data, as: UTF8.self).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { continue }
            guard let s = try? parse(data) else { continue }
            for m in s.messages where (m.role == .user && m.contextNote != true) || m.role == .assistant {
                guard let r = m.content.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                out.append(SessionSearchHit(id: s.header.id, snippet: SessionSearchHit.snippet(m.content, around: r)))
                break
            }
        }
        return out
    }

    /// Every agent run recorded: main sessions' runs and their subagent runs' (a subagent run's session ends with its
    /// `subagentEnd`, which has the delegation sizes). Oldest first.
    public func runRecords() throws -> [(session: SessionHeader, run: AgentRunRecord, end: SubagentEnd?)] {
        var out: [(session: SessionHeader, run: AgentRunRecord, end: SubagentEnd?)] = []
        for url in try sessionFiles() {
            guard let data = try? Data(contentsOf: url), let s = try? parse(data) else { continue }
            out += s.runs.map { (s.header, $0, nil) }
            for child in ownSubagentRuns(of: s.header) { out += child.runs.map { (child.header, $0, child.subagentEnd) } }
        }
        return out.sorted { $0.run.started < $1.run.started }
    }

    /// Judgments of main runs (thumbs, retries, rewinds, `kurtkode judge`), by run id: from each session, those naming one
    /// of its own main runs.
    public func mainRunJudgments() throws -> [UUID: [RunJudgment]] {
        var out: [UUID: [RunJudgment]] = [:]
        for url in try sessionFiles() {
            guard let data = try? Data(contentsOf: url), let s = try? parse(data), !s.judgments.isEmpty else { continue }
            let mine = Set(s.runs.filter { $0.agent == "main" }.map(\.id))
            for j in s.judgments where mine.contains(j.run) { out[j.run, default: []].append(j) }
        }
        return out
    }

    /// Every subagent run with its judgments, from the runs' own sessions (where every judgment is written first), with
    /// the session that started each. Runs without a judgment are included. Oldest first.
    public func judgedRuns() throws -> [(parent: SessionHeader, run: Session)] {
        var out: [(parent: SessionHeader, run: Session)] = []
        for url in try sessionFiles() {
            guard let data = try? Data(contentsOf: url), let s = try? parse(data) else { continue }
            out += ownSubagentRuns(of: s.header).map { (s.header, $0) }
        }
        return out.sorted { $0.run.header.createdAt < $1.run.header.createdAt }
    }

    /// Every cost entry recorded: main sessions', their subagent runs', and their replays' (kept beside the wire log),
    /// with the session each belongs to. Oldest first.
    public func costEntries() throws -> [(session: SessionHeader, entry: CostEntry)] {
        var out: [(session: SessionHeader, entry: CostEntry)] = []
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        for url in try sessionFiles() {
            guard let data = try? Data(contentsOf: url), let s = try? parse(data) else { continue }
            out += s.costs.map { (s.header, $0) }
            for child in ownSubagentRuns(of: s.header) { out += child.costs.map { (child.header, $0) } }
            // A subagent run's replays are kept under the run's own wire folder.
            for header in [s.header] + ownSubagentRuns(of: s.header).map(\.header) {
                let replays = wireDirectory(for: header).appending(path: "replays")
                for dir in (try? FileManager.default.contentsOfDirectory(at: replays, includingPropertiesForKeys: nil)) ?? [] {
                    for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
                        if let r = try? iso.decode(ReplayRecord.self, from: Data(contentsOf: f)), let e = r.cost { out.append((header, e)) }
                    }
                }
            }
        }
        return out.sorted { $0.entry.start < $1.entry.start }
    }

    /// A session's subagent runs, oldest first, a fork's copies of its original's runs included (`ownSubagentRuns` leaves
    /// them out; use that for anything that adds up what a session spent).
    public func subagentRuns(of parent: SessionHeader) -> [Session] {
        let dir = subagentDirectory(for: parent)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? parse($0) } }
            .sorted { $0.header.createdAt < $1.header.createdAt }
    }

    /// Puts a checked cost entry back where it came from: the replay record that holds it (true), or nowhere (false: it
    /// isn't a replay's). Replays' costs live in their records, not in the session file.
    public func updateReplayCost(_ entry: CostEntry, session: SessionHeader) -> Bool {
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        let replays = wireDirectory(for: session).appending(path: "replays")
        for dir in (try? FileManager.default.contentsOfDirectory(at: replays, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
                guard var r = try? iso.decode(ReplayRecord.self, from: Data(contentsOf: f)), r.cost?.id == entry.id else { continue }
                r.cost = entry
                return (try? Replay.save(r, wire: wireDirectory(for: session))) != nil
            }
        }
        return false
    }

    /// The subagent runs this session started itself: a fork also holds copies of the runs in the part it copied (for
    /// drilling into them), which name the original session as their parent and whose spending was the original's.
    public func ownSubagentRuns(of parent: SessionHeader) -> [Session] {
        subagentRuns(of: parent).filter { $0.header.parent == nil || $0.header.parent == parent.id }
    }

    /// One subagent run of a session.
    public func subagentRun(_ id: UUID, of parent: SessionHeader) -> Session? {
        let url = subagentDirectory(for: parent).appending(path: "\(id.uuidString).jsonl")
        guard let data = try? Data(contentsOf: url) else { return nil }
        locations[id] = url
        return try? parse(data)
    }

    /// Moves the session file to the Trash, so it can be recovered, with its companion folders (subagent runs, wire log,
    /// long outputs, undo snapshots, images): left behind, they were kept forever, and the wire log holds the request
    /// bodies with the files they read. Images (and subagent runs) a fork still points at stay where they are.
    public func trash(_ id: UUID) throws {
        try trash(id) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    }

    /// `trash`, moving each item with `moveToTrash` (tests use a folder of their own rather than the user's Trash).
    func trash(_ id: UUID, moveToTrash: (URL) throws -> Void) throws {
        guard let url = try location(of: id) else { return }
        // Its snapshots go too (they can hold the project's files); the Trash keeps the session, not them.
        let workspace = (try? Data(contentsOf: url)).flatMap { try? parse($0) }?.header.workspace
        let fm = FileManager.default
        try moveToTrash(url)
        locations[id] = nil
        let folder = url.deletingLastPathComponent()
        for kind in ["subagents", "wire", "outputs", "checkpoints", "images"] {
            let companion = folder.appending(path: "\(id.uuidString).\(kind)")
            guard fm.fileExists(atPath: companion.path) else { continue }
            // A fork's messages name the original's image files by path, and its copied subagent runs theirs.
            if kind == "images" || kind == "subagents", Self.isReferenced(companion, in: folder, except: id) { continue }
            try? moveToTrash(companion)
        }
        // The lock file, unless a run elsewhere still holds it (its next `acquire` would then make a second one).
        if SessionLock.holder(lockURL(for: id)) == nil { try? fm.removeItem(at: lockURL(for: id)) }
        if let w = workspace, let snaps = snapshots(for: URL(fileURLWithPath: w)) { Task { try? await snaps.drop(session: id) } }
    }

    /// Whether a session file in `folder` (or a subagent run of one) other than `id`'s names a path inside `companion`.
    nonisolated static func isReferenced(_ companion: URL, in folder: URL, except id: UUID) -> Bool {
        let needle = Data((companion.path + "/").utf8)
        let fm = FileManager.default
        var files: [URL] = []
        for f in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            if f.pathExtension == "jsonl", f.deletingPathExtension().lastPathComponent != id.uuidString { files.append(f) }
            if f.pathExtension == "subagents", f.deletingPathExtension().lastPathComponent != id.uuidString {
                files += ((try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "jsonl" }
            }
        }
        return files.contains { (try? Data(contentsOf: $0, options: .mappedIfSafe))?.range(of: needle) != nil }
    }

    // MARK: -

    private func line(_ record: SessionRecord) throws -> Data {
        var d = try encoder.encode(record)
        d.append(0x0A)
        return d
    }

    /// Tolerates a torn last line (a crash mid-append): unreadable lines are skipped.
    func parse(_ data: Data) throws -> Session? {
        var header: SessionHeader?
        var messages: [ChatMessage] = []
        var title: String?
        var model: String?
        var mode: PermissionMode?
        var endpointID: UUID?
        var compactions: [Compaction] = []
        var folders: [ExtraFolder] = []
        var events: [SessionEvent] = []
        var end: SubagentEnd?
        var systemPrompt: String?
        var recordedPrompt: RecordedPrompt?
        var costs: [CostEntry] = []
        var runs: [AgentRunRecord] = []
        var judgments: [RunJudgment] = []
        var escalations: [EscalationOffer] = []
        for raw in data.split(separator: 0x0A) where !raw.isEmpty {
            guard let r = try? decoder.decode(SessionRecord.self, from: Data(raw)) else { continue }
            if let at = r.at, let e = SessionEvent(r, at: at) { events.append(e) }
            switch r.type {
            case .header: header = r.header
            case .message: if let m = r.message { messages.append(m) }
            case .title: title = r.title
            case .model:
                model = r.model
                if let e = r.endpointID { endpointID = e }
            case .retract: messages.removeAll { $0.id == r.retracted }
            case .permissionMode: mode = r.permissionMode ?? mode
            case .compaction: if let c = r.compaction { compactions.append(c) }
            case .folders: folders = r.folders ?? []
            case .subagentEnd: end = r.subagentEnd
            case .cost:
                guard let e = r.cost else { break }
                // A later record of an entry (the provider's record of it, fetched afterwards) replaces the earlier one.
                if let i = costs.firstIndex(where: { $0.id == e.id }) { costs[i] = e } else { costs.append(e) }
            case .run: if let x = r.run { runs.append(x) }
            case .judgment: if let j = r.judgment, !judgments.contains(where: { $0.id == j.id }) { judgments.append(j) }
            case .escalation:
                guard let e = r.escalation else { break }
                if let i = escalations.firstIndex(where: { $0.id == e.id }) { escalations[i] = e } else { escalations.append(e) }
            case .systemPrompt:
                systemPrompt = r.systemPrompt ?? systemPrompt
                if let text = r.systemPrompt, let key = r.systemPromptKey {
                    recordedPrompt = RecordedPrompt(text: text, key: key, facts: r.systemPromptFacts ?? "")
                }
            }
        }
        guard let header else { return nil }
        var session = Session(header: header, messages: messages, title: title, model: model ?? header.model,
                              endpointID: endpointID, permissionMode: mode, compactions: compactions)
        session.folders = folders
        session.events = events
        session.subagentEnd = end
        session.systemPrompt = systemPrompt
        session.recordedPrompt = recordedPrompt
        session.costs = costs
        session.runs = runs
        session.judgments = judgments
        session.escalations = escalations
        return session
    }

    /// The lock a run holds on a session (`SessionLock`).
    public nonisolated func lockURL(for id: UUID) -> URL { SessionLock.url(forSession: id, sessionsRoot: root) }

    private func location(of id: UUID) throws -> URL? {
        if let url = locations[id] { return url }
        let name = "\(id.uuidString).jsonl"
        var url = try sessionFiles().first { $0.lastPathComponent == name }
        if url == nil {
            // A subagent run's session, in its parent's `.subagents` folder.
            let fm = FileManager.default
            let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            url = projects.lazy.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
                .filter { $0.pathExtension == "subagents" }
                .map { $0.appending(path: name) }
                .first { fm.fileExists(atPath: $0.path) }
        }
        locations[id] = url
        return url
    }

    private func sessionFiles() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .flatMap { dir in
                (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            }
            .filter { $0.pathExtension == "jsonl" }
    }
}
