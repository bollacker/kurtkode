import Foundation

/// What the parent says about a task when it hands it to a subagent (SUBAGENT_ROUTING_DESIGN.md "The task card"). All
/// optional: small models leave fields out, and values that aren't on the lists are dropped.
public struct TaskCard: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case search, explain, summarize, edit, refactor, fix, writeTests = "write-tests", review, research, run
    }
    public enum Importance: String, Codable, Sendable, CaseIterable { case low, normal, high }
    public enum Tier: String, Codable, Sendable, CaseIterable { case cheap, standard, strong }

    public var kind: Kind?
    public var importance: Importance?
    /// A command that checks the work (`swift test`), or nil.
    public var verify: String?
    public var tier: Tier?

    public init(kind: Kind? = nil, importance: Importance? = nil, verify: String? = nil, tier: Tier? = nil) {
        self.kind = kind
        self.importance = importance
        self.verify = verify
        self.tier = tier
    }

    /// From a `task` call's arguments.
    public init(_ args: ToolArguments) {
        func pick<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
            args.string(key).flatMap { T(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        }
        kind = pick("kind")
        importance = pick("importance")
        tier = pick("tier")
        let v = (args.string("verify") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        verify = v.isEmpty || ["none", "n/a", "no"].contains(v.lowercased()) ? nil : String(v.prefix(500))
    }

    public var isEmpty: Bool { kind == nil && importance == nil && verify == nil && tier == nil }

    /// The `task` tool's parameters for the card.
    static var parameters: [String: JSONValue] {
        ["kind": ["type": "string", "enum": .array(Kind.allCases.map { .string($0.rawValue) }),
                  "description": "What sort of task this is."],
         "importance": ["type": "string", "enum": .array(Importance.allCases.map { .string($0.rawValue) }),
                        "description": .string("How much rides on it. high: its result decides an irreversible action or the "
                            + "answer you give the user. Default: normal.")],
         "verify": ["type": "string",
                    "description": .string("A shell command that checks the work (run the tests, a build), or \"none\". "
                        + "The subagent is asked to run it at the end.")],
         "tier": ["type": "string", "enum": .array(Tier.allCases.map { .string($0.rawValue) }),
                  "description": "Optional: how capable a model the task needs."]]
    }
}

/// One judgment of a subagent run: the automatic checks, the parent's rating, a grader model's, or the user's
/// (SUBAGENT_ROUTING_DESIGN.md §3). Every judgment is kept, never replaced: they're training data for later.
public struct RunJudgment: Codable, Sendable, Hashable, Identifiable {
    /// `recheck`: the task's check, run again by kurtkode at the end of the parent's run (grounded, like `checks`).
    /// `implicit`: what the user did rather than said: retried a main run's reply or rewound its turn (verdict 0).
    /// `reviewer`: a cross-vendor review of the run's change (A6), its verdict mapped to 3 (looks right), 1, or 0.
    public enum Judge: String, Codable, Sendable { case checks, recheck, parent, grader, user, implicit, reviewer }
    public enum Checked: String, Codable, Sendable, CaseIterable {
        case ranTests = "ran-tests", readTheFiles = "read-the-files", spotChecked = "spot-checked", notChecked = "not-checked"
    }
    public static let issueTags = ["incomplete", "wrong-facts", "made-up", "ignored-instructions", "out-of-scope",
                                   "broke-things", "slow", "too-long"]
    public static let verdictMeanings = [0: "failed, wrong, or harmful", 1: "partial: needed real rework",
                                         2: "done, with minor gaps", 3: "done and right, as far as checked"]

    public var id: UUID
    /// The subagent run judged (its child session's id) and the `task` call that started it.
    public var run: UUID
    public var taskCall: String?
    public var judge: Judge
    /// The model that judged (parent, grader), and where it runs.
    public var judgeModel: String?
    public var judgeEndpointID: UUID?
    /// 0 to 3 (`verdictMeanings`); nil for the automatic checks.
    public var verdict: Int?
    /// How the judge knows (`Checked`).
    public var checked: String?
    public var issues: [String]
    public var note: String?
    public var checks: GroundedChecks?
    /// For the parent's rating: whether its own calls after the report back up `checked` (it read files or ran
    /// commands), and those calls. Nil when it claimed no check, or for other judges. (Seen: a parent wrote "verified by
    /// reading the files" with no call after the report.)
    public var checkedConfirmed: Bool?
    public var evidence: [String]?
    /// The request that produced it (its wire log record), and what was asked and answered (a grader's or a rating
    /// request's prompt and reply), for fine-tuning judges later.
    public var requestID: UUID?
    public var prompt: String?
    public var response: String?
    public var at: Date

    public init(id: UUID = UUID(), run: UUID, taskCall: String? = nil, judge: Judge, judgeModel: String? = nil,
                judgeEndpointID: UUID? = nil, verdict: Int? = nil, checked: String? = nil, issues: [String] = [],
                note: String? = nil, checks: GroundedChecks? = nil, at: Date = Date()) {
        self.id = id
        self.run = run
        self.taskCall = taskCall
        self.judge = judge
        self.judgeModel = judgeModel
        self.judgeEndpointID = judgeEndpointID
        self.verdict = verdict
        self.checked = checked
        self.issues = issues
        self.note = note
        self.checks = checks
        self.at = at
    }

    /// The label the router learns from: the verdict as a fraction, or 0 for a hard failure the checks found.
    public var label: Double? {
        if let checks, checks.isHardFailure { return 0 }
        return verdict.map { Double($0) / 3 }
    }

    /// "parent 2/3 (read-the-files): incomplete".
    public var summary: String {
        var s = judge.rawValue
        if let verdict { s += " \(verdict)/3" }
        if let checked { s += " (\(checked)\(checkedConfirmed == false ? ", unconfirmed" : ""))" }
        if let checks { s += checks.problems.isEmpty ? " no problems" : " " + checks.problems.joined(separator: "; ") }
        if !issues.isEmpty { s += ": " + issues.joined(separator: ", ") }
        return s
    }
}

extension Array where Element == RunJudgment {
    /// The latest judgment from each judge, most trusted first: user, implicit, grader, parent, the re-run check, checks.
    public var latestByJudge: [RunJudgment] {
        var latest: [RunJudgment.Judge: RunJudgment] = [:]
        for j in self where (latest[j.judge]?.at ?? .distantPast) <= j.at { latest[j.judge] = j }
        return [RunJudgment.Judge.user, .implicit, .grader, .reviewer, .parent, .recheck, .checks].compactMap { latest[$0] }
    }

    /// The label from the most trusted judgment (user > a retry or rewind (0) > a grounded hard failure, from the
    /// checks or the re-run check > grader > parent).
    public var label: Double? {
        let latest = latestByJudge
        if let u = latest.first(where: { $0.judge == .user && $0.label != nil })?.label { return u }
        if latest.contains(where: { $0.judge == .implicit }) { return 0 }
        if latest.contains(where: { ($0.judge == .checks || $0.judge == .recheck) && $0.checks?.isHardFailure == true }) { return 0 }
        return latest.first(where: { [.grader, .reviewer, .parent].contains($0.judge) && $0.label != nil })?.label
    }
}

/// What can be checked about a subagent run without asking anyone: how it ended, whether the files and lines its
/// report cites exist, whether the files it changed are the ones it mentions, and whether the card's check passed.
public struct GroundedChecks: Codable, Sendable, Hashable {
    public var stop: String
    public var steps: Int
    public var maxSteps: Int
    public var toolCalls: Int
    public var toolErrors: Int
    /// Calls identical to an earlier call of the run.
    public var repeatedCalls: Int
    public var emptyReport: Bool
    /// `path:line` references in the report, and those that don't resolve (no such file, or past its end).
    public var citations: Int
    public var unresolvedCitations: [String]
    public var filesChanged: [String]
    /// Changed files the report doesn't name.
    public var unmentionedChanges: [String]
    /// The card's check, and its exit status when the run ran it (nil: not run).
    public var verifyCommand: String?
    public var verifyExitCode: Int32?
    /// Reasons the run failed outright: no report, stopped on an error, made-up citations, a failed check.
    public var hardFailures: [String]

    public var isHardFailure: Bool { !hardFailures.isEmpty }

    /// Hard failures kurtkode tries again on another model (D3): all but a failed check, which the parent judges, and
    /// a missing report from a run that changed files (cut off at the output limit after doing the work: 6 of 8 such
    /// runs in the cost-floor re-run had done it right, and a retry would undo it).
    public var retryableFailures: [String] {
        hardFailures.filter { !$0.hasPrefix("the check failed") && !($0 == "no report" && !filesChanged.isEmpty) }
    }

    /// These checks with the report's citations resolved again in `workspace` (an eval run's restored fixture), for
    /// re-scoring stored runs after the resolver changes. The other checks stay as recorded.
    public func resolvingCitations(report: String, in workspace: Workspace) -> GroundedChecks {
        var c = self
        let cited = Self.citations(in: report.trimmingCharacters(in: .whitespacesAndNewlines))
        let unresolved = cited.compactMap { Self.resolve($0, in: workspace) }
        c.citations = cited.count
        c.unresolvedCitations = unresolved
        c.hardFailures = hardFailures.filter { !$0.hasPrefix("made-up citations") }
        if let made = Self.madeUp(unresolved, of: cited.count) { c.hardFailures.append(made) }
        return c
    }

    /// "made-up citations: …" when at least two citations, and at least half of them, don't resolve.
    static func madeUp(_ unresolved: [String], of cited: Int) -> String? {
        guard unresolved.count >= 2, unresolved.count * 2 >= cited else { return nil }
        return "made-up citations: \(unresolved.count) of \(cited) don't resolve (" + unresolved.prefix(3).joined(separator: ", ") + ")"
    }

    /// Short lines about anything wrong, for the parent and for listings.
    public var problems: [String] {
        var p = hardFailures
        if !unresolvedCitations.isEmpty, !hardFailures.contains(where: { $0.hasPrefix("made-up") }) {
            p.append("\(unresolvedCitations.count) of \(citations) citations don't resolve: "
                     + unresolvedCitations.prefix(3).joined(separator: ", "))
        }
        if !unmentionedChanges.isEmpty { p.append("changed files the report doesn't mention: " + unmentionedChanges.prefix(5).joined(separator: ", ")) }
        if verifyCommand != nil, verifyExitCode == nil { p.append("didn't run the check (\(verifyCommand!))") }
        if steps >= maxSteps { p.append("reached its step limit") }
        if repeatedCalls >= 3 { p.append("repeated \(repeatedCalls) calls") }
        return p
    }

    /// Checks a run from its messages and report.
    public static func evaluate(messages: [ChatMessage], report: String, stop: AgentStop?, maxSteps: Int,
                                workspace: Workspace?, verify: String?) -> GroundedChecks {
        let replies = messages.filter { $0.role == .assistant }
        let calls = replies.flatMap(\.toolCalls)
        var seen = Set<String>(), repeated = 0
        for c in calls where !seen.insert(c.name + "\u{0}" + c.arguments).inserted { repeated += 1 }
        let results = messages.filter { $0.role == .tool }
        let errors = results.filter { $0.toolResult?.isError == true && $0.toolResult?.denied != true }.count
        var facts = SessionFacts()
        facts.absorb(messages)
        let changed = facts.changeOrder
        let text = report.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        let unmentioned = changed.filter { !lowered.contains((($0 as NSString).lastPathComponent).lowercased()) }
        let cited = citations(in: text)
        let unresolved = workspace.map { ws in cited.compactMap { resolve($0, in: ws) } } ?? []

        // The check's last run: a bash call whose command contains it.
        var exit: Int32?
        if let verify {
            let wanted = verify.trimmingCharacters(in: .whitespacesAndNewlines)
            let byID = Dictionary(results.compactMap { m in m.toolCallID.map { ($0, m) } }, uniquingKeysWith: { _, b in b })
            for c in calls where c.name == "bash" {
                let command = ((try? ToolArguments(json: c.arguments))?.string("command") ?? "")
                guard command.contains(wanted), let r = byID[c.id] else { continue }
                exit = r.toolResult?.exitCode ?? (r.toolResult?.isError == true ? 1 : nil)
            }
        }

        var hard: [String] = []
        if text.isEmpty || text == "(The subagent gave no final report.)" { hard.append("no report") }
        if case .turnStopped(let why)? = stop { hard.append("stopped early: \(why)") }
        if let made = madeUp(unresolved, of: cited.count) { hard.append(made) }
        if let exit, exit != 0 { hard.append("the check failed (exit \(exit)): \(verify!)") }
        return GroundedChecks(stop: stop.map { "\($0)" } ?? "completed", steps: replies.count, maxSteps: maxSteps,
                              toolCalls: calls.count, toolErrors: errors, repeatedCalls: repeated, emptyReport: text.isEmpty,
                              citations: cited.count, unresolvedCitations: unresolved, filesChanged: changed,
                              unmentionedChanges: unmentioned, verifyCommand: verify, verifyExitCode: exit, hardFailures: hard)
    }

    /// A check run again after the run: only the command and how it ended, a hard failure when it failed. `exitCode`
    /// nil: it didn't run (denied, refused).
    public static func recheck(command: String, exitCode: Int32?) -> GroundedChecks {
        GroundedChecks(stop: "re-run", steps: 0, maxSteps: 1, toolCalls: 0, toolErrors: 0, repeatedCalls: 0, emptyReport: false,
                       citations: 0, unresolvedCitations: [], filesChanged: [], unmentionedChanges: [], verifyCommand: command,
                       verifyExitCode: exitCode,
                       hardFailures: exitCode.map { $0 != 0 ? ["the check failed when re-run after the run (exit \($0)): \(command)"] : [] } ?? [])
    }

    /// These checks with a re-run of the check added (the eval puts both in one).
    public func addingRecheck(_ r: GroundedChecks) -> GroundedChecks {
        var c = self
        c.hardFailures += r.hardFailures
        return c
    }

    /// A cited location: a path and a line.
    public struct Citation: Hashable, Sendable {
        public var path: String
        public var line: Int
    }

    // A path with a dot or slash in it, then :line (:line:column, :line-line). Not after "//" or a word character, so
    // URLs (host:port) and times don't count.
    private static let citationPattern = try! NSRegularExpression(
        pattern: #"(?<![\w/:.~-])((?:~/|/|\./|\.\./)?[\w.@+-]+(?:/[\w.@+-]+)*):(\d+)(?:[-–:]\d+)?"#)

    // On one line: a path (with a slash, or a file name with an extension), then "line N" or a table cell holding N.
    private static let pathPattern = try! NSRegularExpression(
        pattern: #"(?<![\w/:.~-])((?:~/|/|\./|\.\./)?[\w.@+-]+(?:/[\w.@+-]+)+|[\w@+-]+\.[A-Za-z][A-Za-z0-9]{0,5})(?![\w/])"#)
    private static let lineNumberPattern = try! NSRegularExpression(
        pattern: #"(?:\bline\s*[*_`]*\s*:?\s*[*_`]*\s*|\|\s*[*_`]*)(\d+)(?![\d.:/])"#, options: .caseInsensitive)

    /// The distinct cited locations in `text` (at most 200): `path:line`, and on one line a path followed by "line N"
    /// or, in a table row, by a cell holding the number.
    public static func citations(in text: String) -> [Citation] {
        var out: [Citation] = []
        var seen = Set<Citation>()
        func add(_ path: String, _ line: Int?) {
            guard out.count < 200, path.contains(where: { $0 == "." || $0 == "/" }), path.contains(where: \.isLetter),
                  !path.hasSuffix("."), let line, line > 0 else { return }
            let c = Citation(path: path, line: line)
            if seen.insert(c).inserted { out.append(c) }
        }
        let ns = text as NSString
        var colonCited = Set<NSRange>()
        for m in citationPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            add(ns.substring(with: m.range(at: 1)), Int(ns.substring(with: m.range(at: 2))))
            colonCited.insert(m.range(at: 1))
        }
        for lineText in text.components(separatedBy: "\n") {
            let l = lineText as NSString
            let whole = NSRange(location: 0, length: l.length)
            let paths = pathPattern.matches(in: lineText, range: whole)
                .filter { m in !(lineText as NSString).substring(with: m.range(at: 1)).allSatisfy { $0.isNumber || $0 == "." } }
            guard paths.count == 1, let p = paths.first,
                  l.substring(from: p.range.upperBound).hasPrefix(":") == false else { continue }
            let rest = NSRange(location: p.range.upperBound, length: l.length - p.range.upperBound)
            let numbers = lineNumberPattern.matches(in: lineText, range: rest)
            guard numbers.count == 1, let n = numbers.first else { continue }
            add(l.substring(with: p.range(at: 1)), Int(l.substring(with: n.range(at: 1))))
        }
        return out
    }

    /// Extensions that make a bare dotted name ("pricing.py") a file: without a slash, "cache.warm" or "self.total" is
    /// a name in the code, not a citation of a file (in the cost-floor re-run those were 5 of 5 "made-up" citations
    /// in reports that were right).
    static let fileExtensions: Set<String> = [
        "py", "pyi", "ipynb", "swift", "m", "mm", "h", "hpp", "hh", "c", "cc", "cpp", "cxx", "cs", "java", "kt", "kts", "scala",
        "go", "rs", "rb", "php", "pl", "pm", "lua", "r", "jl", "dart", "ex", "exs", "erl", "hs", "ml", "mli", "fs", "clj", "elm",
        "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "svelte", "html", "htm", "css", "scss", "sass", "less",
        "json", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "xml", "plist", "csv", "tsv", "sql", "graphql", "proto",
        "md", "markdown", "rst", "txt", "log", "tex", "sh", "bash", "zsh", "fish", "ps1", "bat", "mk", "cmake", "gradle",
        "lock", "sum", "mod", "tf", "hcl", "nix", "dockerfile", "make", "patch", "diff",
    ]

    /// Nil when the citation resolves in the project or one of its folders; else "path:line (why)". A bare file name
    /// ("pricing.py") also resolves to a file of that name anywhere in the project ("inventory/pricing.py"); a bare
    /// dotted name whose extension isn't a file type isn't a citation.
    static func resolve(_ c: Citation, in workspace: Workspace) -> String? {
        let fm = FileManager.default
        var candidates: [URL] = []
        let bare = !c.path.contains("/")
        if bare, !fileExtensions.contains((c.path as NSString).pathExtension.lowercased()) { return nil }
        if c.path.hasPrefix("/") { candidates.append(URL(filePath: c.path)) }
        else if c.path.hasPrefix("~/") { candidates.append(URL(filePath: (c.path as NSString).expandingTildeInPath)) }
        else {
            candidates.append(workspace.root.appending(path: c.path))
            candidates += workspace.folders.map { URL(filePath: $0.path).appending(path: c.path) }
        }
        var isDir: ObjCBool = false
        var found = candidates.filter { fm.fileExists(atPath: $0.path, isDirectory: &isDir) && !isDir.boolValue }
        if found.isEmpty, !c.path.hasPrefix("/"), !c.path.hasPrefix("~/") {
            found = findBySuffix(c.path, under: [workspace.root] + workspace.folders.map { URL(filePath: $0.path) })
        }
        guard !found.isEmpty else { return "\(c.path):\(c.line) (no such file)" }
        // Any file of that name long enough resolves it.
        var lines = 0
        for url in found {
            guard let data = try? Data(contentsOf: url) else { return nil }
            lines = max(lines, data.reduce(into: 1) { n, b in if b == 0x0A { n += 1 } } - (data.last == 0x0A ? 1 : 0))
            if c.line <= max(lines, 1) { return nil }
        }
        return "\(c.path):\(c.line) (the file has \(lines) lines)"
    }

    /// Files under `roots` whose path ends with `/<relative>`, skipping hidden and dependency folders; at most 20,000
    /// entries looked at.
    static func findBySuffix(_ relative: String, under roots: [URL]) -> [URL] {
        let suffix = "/" + (relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative)
        var out: [URL] = [], seen = 0
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                seen += 1
                if seen > 20_000 { return out }
                if ["node_modules", ".build", "build", "dist", "target", "__pycache__", ".venv", "venv"].contains(url.lastPathComponent) {
                    e.skipDescendants()
                    continue
                }
                if url.path.hasSuffix(suffix), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    out.append(url)
                    if out.count >= 5 { return out }
                }
            }
        }
        return out
    }
}

/// The subagent runs a main loop knows about: those it started, and those earlier in the session (for ratings).
final class TaskRuns: @unchecked Sendable {
    struct Entry: Sendable {
        var callID: String
        var run: UUID?
        var title: String
        var agent: String
        var model: String
        var endpointID: UUID?
        var stop: String
        var card: TaskCard?
        /// Started in this run (only these are asked about at its end).
        var thisRun: Bool
        var rated = false
        /// The parent's tool calls after the report came back, for checking what its rating says it checked.
        var callsAfter: [ToolCall] = []
        /// The task's check, run again at the end of the parent's run: whether it was, and its exit status (nil: it
        /// didn't run).
        var rechecked = false
        var recheckExit: Int32?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    var isEmpty: Bool { lock.withLock { entries.isEmpty } }

    /// Tasks earlier in the session, from their calls and results.
    func seed(_ history: [ChatMessage]) {
        var titles: [String: (String, String)] = [:]
        for m in history where m.role == .assistant {
            for c in m.toolCalls where c.name == "task" {
                let a = (try? ToolArguments(json: c.arguments)) ?? ToolArguments()
                titles[c.id] = (a.string("description") ?? "", (a.string("agent") ?? "general").lowercased())
            }
        }
        let found: [Entry] = history.compactMap { m in
            guard m.role == .tool, let id = m.toolCallID, let run = m.toolResult?.subagentRun, let (title, agent) = titles[id] else { return nil }
            return Entry(callID: id, run: run, title: title, agent: agent, model: "", endpointID: nil, stop: "completed", thisRun: false)
        }
        lock.withLock { entries = found + entries }
    }

    func add(_ e: Entry) { lock.withLock { entries.removeAll { $0.callID == e.callID }; entries.append(e) } }

    /// The parent's calls in a reply: they come after every report already back.
    func noteCalls(_ calls: [ToolCall]) {
        guard !calls.isEmpty else { return }
        lock.withLock { for i in entries.indices where entries[i].thisRun { entries[i].callsAfter += calls } }
    }

    /// Whether the calls after a report back up how a rating says it was checked, and those calls.
    static func evidence(_ calls: [ToolCall], checked: String) -> (confirmed: Bool?, calls: [String]) {
        let looked = calls.filter { ["read_file", "grep", "glob", "list_dir", "bash"].contains($0.name) }
        let shown = looked.prefix(10).map { $0.name + " " + String($0.arguments.prefix(160)) }
        switch RunJudgment.Checked(rawValue: checked) {
        case .ranTests?: return (looked.contains { $0.name == "bash" }, shown)
        case .readTheFiles?, .spotChecked?: return (!looked.isEmpty, shown)
        default: return (nil, shown)
        }
    }

    func markRated(_ callID: String) {
        lock.withLock { for i in entries.indices where entries[i].callID == callID { entries[i].rated = true } }
    }

    /// By call id, by title, or by number among this run's tasks ("1" is the first).
    func find(_ ref: String) -> Entry? {
        let r = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        return lock.withLock {
            if let e = entries.last(where: { $0.callID == r }) { return e }
            if let e = entries.last(where: { !$0.title.isEmpty && $0.title.caseInsensitiveCompare(r) == .orderedSame }) { return e }
            let mine = entries.filter(\.thisRun)
            if let n = Int(r), n >= 1, n <= mine.count { return mine[n - 1] }
            return entries.count == 1 ? entries[0] : nil
        }
    }

    /// This run's recorded tasks with a check that hasn't been run again yet.
    var recheckable: [Entry] {
        lock.withLock { entries.filter { $0.thisRun && $0.run != nil && $0.stop != "cancelled" && $0.card?.verify != nil && !$0.rechecked } }
    }

    func setRecheck(_ callID: String, exit: Int32?) {
        lock.withLock {
            for i in entries.indices where entries[i].callID == callID { entries[i].rechecked = true; entries[i].recheckExit = exit }
        }
    }

    /// This run's recorded tasks that finished and aren't rated yet.
    var unrated: [Entry] {
        lock.withLock { entries.filter { $0.thisRun && !$0.rated && $0.run != nil && $0.stop != "cancelled" } }
    }
}

/// `rate_task`: the parent's judgment of a subagent run it used (SUBAGENT_ROUTING_DESIGN.md §3).
public struct RateTaskTool: Tool {
    public let name = "rate_task"
    public let risk = ToolRisk.read
    /// Where its description comes from (`tool-rate-task.md`).
    var templates = PromptTemplates(overrides: [])
    public var description: String {
        let text = templates.render("tool-rate-task", [:])
        return text.isEmpty ? "Rate a subagent's work (0 to 3) after you've used its report." : text
    }
    let rate: @Sendable (_ task: String, _ verdict: Int, _ checked: String, _ issues: [String], _ note: String?) async -> Result<String, ToolFailure>

    public var parameters: JSONValue {
        ["type": "object",
         "properties": [
            "task": ["type": "string", "description": "The task's title (or its call id)."],
            "verdict": ["type": "integer", "minimum": 0, "maximum": 3,
                        "description": .string("3: done and right, as far as you checked. 2: done, with minor gaps. 1: partial, "
                            + "needed real rework. 0: failed, wrong, or harmful. Work that isn't actually done, or whose check "
                            + "fails, is 0 or 1.")],
            "checked": ["type": "string", "enum": .array(RunJudgment.Checked.allCases.map { .string($0.rawValue) }),
                        "description": "How you know: ran its tests, read the files it named, spot-checked, or not checked."],
            "issues": ["type": "array", "items": ["type": "string", "enum": .array(RunJudgment.issueTags.map { .string($0) })],
                       "description": "What went wrong, if anything."],
            "note": ["type": "string", "description": "One or two sentences: why this verdict."],
         ],
         "required": ["task", "verdict", "checked"]]
    }

    public func summary(_ args: ToolArguments) -> String {
        "Rate \"\(args.string("task") ?? "?")\": \(args.string("verdict") ?? "?")/3"
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let r = try Self.parse(args)
        switch await rate(r.task, r.verdict, r.checked, r.issues, r.note) {
        case .success(let text): return ToolOutput(text: text)
        case .failure(let f): throw f
        }
    }

    /// The arguments, checked and normalized: unknown issue tags dropped, `checked` defaulting to not-checked.
    static func parse(_ args: ToolArguments) throws -> (task: String, verdict: Int, checked: String, issues: [String], note: String?) {
        let task = try args.require("task")
        guard let verdict = args.int("verdict"), (0...3).contains(verdict) else { throw ToolFailure("verdict must be 0, 1, 2 or 3.") }
        let checked = RunJudgment.Checked(rawValue: (args.string("checked") ?? "").lowercased())?.rawValue ?? RunJudgment.Checked.notChecked.rawValue
        var tags: [String] = []
        switch args.values["issues"] {
        case .array(let a)?: tags = a.compactMap { if case .string(let s) = $0 { s } else { nil } }
        case .string(let s)?: tags = s.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        default: break
        }
        let issues = tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter(RunJudgment.issueTags.contains)
        let note = args.string("note").map { String($0.prefix(1000)) }
        return (task, verdict, checked, issues, note)
    }
}

extension AgentLoop {
    /// What a verdict must respect, whatever else the report gets right. (Seen: a parent that found the work undone,
    /// "calc.py still shows the buggy code", rated it 2/3.)
    static let rubric = "If the work isn't actually done, or its check fails, the verdict is 0 or 1, however good the rest looks."

    /// The note that asks the parent, at the end of its run, to rate the subagent runs it used.
    static func ratingRequest(_ unrated: [TaskRuns.Entry]) -> String {
        let list = unrated.enumerated().map { i, e in
            var line = "\(i + 1). \"\(e.title.isEmpty ? e.agent : e.title)\" (\(e.agent))"
            if let v = e.card?.verify {
                line += "; its check: `\(v)`"
                if e.rechecked {
                    line += e.recheckExit.map { $0 == 0 ? " (run again just now: it passed)" : " (run again just now: it FAILED, exit \($0))" }
                        ?? " (couldn't be run again)"
                }
            }
            return line
        }
        let checks = unrated.contains { $0.card?.verify != nil }
        return "Before you finish: rate the subagent \(unrated.count == 1 ? "run" : "runs") you used in this task with "
            + "rate_task, one call each, from what you checked yourself:\n" + list.joined(separator: "\n")
            + "\n" + Self.rubric
            + (checks ? "\nYou may read files and run a task's check, exactly as written, before you rate; nothing else."
                      : "\nYou may read files before you rate; nothing else.")
    }

    /// The grader's prompt for one run: the task, the report, what the checks found, and excerpts of the cited files.
    static func graderPrompt(task: String, card: TaskCard?, report: String, checks: GroundedChecks, workspace: Workspace?) -> String {
        var excerpts: [String] = []
        var budget = 8_000
        if let workspace {
            for c in GroundedChecks.citations(in: report).prefix(8) where GroundedChecks.resolve(c, in: workspace) == nil {
                let url = c.path.hasPrefix("/") ? URL(filePath: c.path) : workspace.root.appending(path: c.path)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lines = text.components(separatedBy: "\n")
                let lo = max(0, c.line - 4), hi = min(lines.count, c.line + 3)
                guard lo < hi else { continue }
                let block = "\(c.path):\(lo + 1)-\(hi)\n" + lines[lo..<hi].enumerated().map { "\(lo + $0 + 1)\t\($1)" }.joined(separator: "\n")
                guard block.utf8.count < budget else { break }
                budget -= block.utf8.count
                excerpts.append(block)
            }
        }
        var s = "Judge how well a subagent did the task below. You see its task, its final report, what automatic checks "
            + "found, and the lines of the files it cites. Call rate_task once with your verdict. " + rubric + "\n\n## Task\n\n" + task
        if let card, !card.isEmpty {
            s += "\n\n(kind: \(card.kind?.rawValue ?? "-"), importance: \(card.importance?.rawValue ?? "-"), check: \(card.verify ?? "none"))"
        }
        s += "\n\n## Report\n\n" + String(report.prefix(20_000))
        s += "\n\n## Automatic checks\n\n" + (checks.problems.isEmpty ? "No problems found." : checks.problems.map { "- " + $0 }.joined(separator: "\n"))
        s += "\nIt took \(checks.steps) steps and \(checks.toolCalls) tool calls"
            + (checks.filesChanged.isEmpty ? "." : ", and changed " + checks.filesChanged.joined(separator: ", ") + ".")
        if !excerpts.isEmpty { s += "\n\n## Cited lines\n\n" + excerpts.joined(separator: "\n\n") }
        return s
    }

    /// Asks a grader model to judge a run (one request, no tools but rate_task). Without a verdict in the reply, the
    /// judgment has none, and its note says why (the reply is kept with it).
    static func grade(_ grader: SubagentModel, prompt: String, run: UUID, taskCall: String?, costs: CostSink?,
                      meter: CostMeter?, limits: TurnLimits) async -> RunJudgment? {
        let tool = RateTaskTool { _, _, _, _, _ in .success("") }
        var request = ChatRequest(model: grader.model,
                                  messages: [.system("You review work done by coding agents. Be strict: a confident report "
                                                     + "is not evidence; the cited lines and the checks are."),
                                             .user(prompt)],
                                  // Room to think first (gemma-4-26b used all of 2,000 on 40 of 300 gradings).
                                  tools: [tool.definition], maxTokens: 8_000, temperature: grader.temperature)
        request.oneOff = true             // asked once: no cache write to pay for
        if grader.client.api != .openai { request.maxTokens = 16_000 }
        var gradeLimits = limits
        gradeLimits.maxTokens = request.maxTokens
        let started = Date()
        let reply = await TurnRunner.run(client: grader.client, request: request, limits: gradeLimits, tap: nil) { _ in }
        if let entry = await costs?.record(reply, purpose: .grading, client: grader.client, start: started) { meter?.add(entry) }
        var calls = reply.toolCalls.filter { $0.name == tool.name }
        if calls.isEmpty, let found = TextToolCalls.extract(from: reply.content, knownTools: [tool.name],
                                                            parameterSchemas: [tool.name: tool.parameters]) {
            calls = found.calls.filter { $0.name == tool.name }.map { ToolCall(id: "text", name: $0.name, arguments: $0.arguments) }
        }
        guard let call = calls.first, let args = try? ToolArguments(json: call.arguments),
              let verdict = args.int("verdict"), (0...3).contains(verdict) else {
            let why: String
            if reply.meta?.finishReason == .length { why = "the reply hit its output limit" }
            else if let stop = reply.meta?.stopReason, stop != .completed { why = "the request ended early (\(stop))" }
            else if calls.isEmpty { why = "no rate_task call" }
            else { why = "the call had no usable verdict" }
            var j = RunJudgment(run: run, taskCall: taskCall, judge: .grader, judgeModel: grader.model, judgeEndpointID: grader.endpointID,
                                note: "No verdict: \(why).")
            j.requestID = reply.id
            j.prompt = prompt
            j.response = reply.content + calls.map { "\n[\($0.name) \($0.arguments)]" }.joined()
            return j
        }
        // The grader has no tools: what it checked is what it was shown (cited lines, or nothing), whatever it says.
        // (Seen: qwen3.5-9b graders answering "ran-tests".)
        let shown = prompt.contains("## Cited lines") ? RunJudgment.Checked.spotChecked : .notChecked
        var j = RunJudgment(run: run, taskCall: taskCall, judge: .grader, judgeModel: grader.model, judgeEndpointID: grader.endpointID,
                            verdict: verdict, checked: shown.rawValue, note: args.string("note"))
        let claimed = (args.string("checked") ?? "").lowercased()
        if !claimed.isEmpty, claimed != shown.rawValue { j.evidence = ["claimed: \(claimed)"] }
        if case .array(let a)? = args.values["issues"] {
            j.issues = a.compactMap { if case .string(let s) = $0, RunJudgment.issueTags.contains(s) { s } else { nil } }
        }
        j.requestID = reply.id
        j.prompt = prompt
        j.response = reply.content + calls.map { "\n[\($0.name) \($0.arguments)]" }.joined()
        return j
    }
}

/// Judge calibration (the eval's task bank): the production rating paths, run on a recorded subagent run whose outcome
/// is known, so each judge's verdicts can be compared with gold (SUBAGENT_ROUTING_DESIGN.md "Calibrating the judges").
public enum JudgeCalibration {
    /// The task result a parent reads back: the report, what the checks found, and the closing note.
    public static func parentView(report: String, checks: GroundedChecks, agent: String) -> String {
        var text = report.isEmpty ? "(The subagent gave no final report.)" : report
        if !checks.problems.isEmpty { text += "\n\n[Automatic checks: " + checks.problems.joined(separator: "; ") + ".]" }
        return text + SubagentSetup.reportNote(agent: agent)
    }

    /// A parent's rating, asked as at the end of a real run: the conversation is the user's request, the parent's
    /// task call, and the report it read back; read-only calls may run before it rates.
    /// `recheck`: the check's exit status when run again before rating (nil: not run again).
    public static func parentRating(client: ChatClient, model: String, config: AgentConfig, systemPrompt: String,
                                    workspace: Workspace, request: String, title: String, agent: String, card: TaskCard,
                                    parentView: String, recheck: Int32?? = nil, costs: CostSink) async -> RunJudgment? {
        let callID = "call_task"
        var args: [String: JSONValue] = ["description": .string(title), "prompt": .string(request), "agent": .string(agent)]
        if let k = card.kind { args["kind"] = .string(k.rawValue) }
        if let i = card.importance { args["importance"] = .string(i.rawValue) }
        if let v = card.verify { args["verify"] = .string(v) }
        let argText = String(decoding: (try? JSONEncoder().encode(JSONValue.object(args))) ?? Data(), as: UTF8.self)
        let messages: [ChatMessage] = [
            .system(systemPrompt), .user(request),
            ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: callID, name: "task", arguments: argText)]),
            ChatMessage(role: .tool, content: parentView, toolCallID: callID),
        ]
        let run = UUID()
        var entry = TaskRuns.Entry(callID: callID, run: run, title: title, agent: agent, model: "", endpointID: nil,
                                   stop: "completed", card: card, thisRun: true)
        if let recheck { entry.rechecked = true; entry.recheckExit = recheck }
        let rateTool = RateTaskTool { _, _, _, _, _ in .success("") }
        let taskTool = TaskTool(agents: AgentDefinition.builtIns) { _, _, _, _, _, _, _ in ToolOutput(text: "") }
        let all: [any Tool] = config.tools + [rateTool, taskTool]
        let tools = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var calls: [ToolCall] = []
            var judgment: RunJudgment?
        }
        let box = Box()
        let ended = await AgentLoop.ratingSideLoop(client: client, model: model, messages: messages, ask: AgentLoop.ratingRequest([entry]),
                                       tools: tools, definitions: all.map(\.definition), config: config, workspace: workspace,
                                       provider: nil, costs: costs, verify: Set([card.verify].compactMap { $0 }), done: { box.lock.withLock { box.judgment != nil } },
                                       looked: { c in box.lock.withLock { box.calls += c } }) { r, req in
            var j = RunJudgment(run: run, taskCall: callID, judge: .parent, judgeModel: model, verdict: r.verdict,
                                checked: r.checked, issues: r.issues, note: r.note)
            let (confirmed, evidence) = TaskRuns.evidence(box.lock.withLock { box.calls }, checked: r.checked)
            j.checkedConfirmed = confirmed
            j.evidence = evidence.isEmpty ? nil : evidence
            (j.requestID, j.prompt, j.response) = (req.id, req.prompt, req.response)
            box.lock.withLock { box.judgment = j }
            return ToolOutput(text: "Recorded.")
        }
        if let j = box.lock.withLock({ box.judgment }) { return j }
        // No verdict: kept anyway, with why, so missing ratings can be told apart.
        var j = RunJudgment(run: run, taskCall: callID, judge: .parent, judgeModel: model,
                            note: "No verdict: " + (ended?.why ?? "unknown") + ".")
        j.response = ended.map { String($0.last.prefix(2000)) }
        return j
    }

    /// A grader's judgment, as for an `importance: high` run.
    public static func grade(grader: SubagentModel, task: String, card: TaskCard, report: String, checks: GroundedChecks,
                             workspace: Workspace, limits: TurnLimits, costs: CostSink) async -> RunJudgment? {
        let prompt = AgentLoop.graderPrompt(task: task, card: card, report: report, checks: checks, workspace: workspace)
        return await AgentLoop.grade(grader, prompt: prompt, run: UUID(), taskCall: nil, costs: costs, meter: nil, limits: limits)
    }
}

/// Judgments of main runs (GAP_ANALYSIS.md A3): the user's thumbs on a reply, and what the user's later actions say
/// about it. Kept in the session, like subagent judgments, for routing main runs later (D8 extended).
public enum MainRunJudgments {
    /// Thumbs up: 3 (done and right); down: 0.
    public static func thumbs(run: UUID, up: Bool, note: String? = nil) -> RunJudgment {
        RunJudgment(run: run, judge: .user, verdict: up ? 3 : 0, note: note.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// A retry of the run's reply or a rewind of its turn: an implicit 0.
    public static func implicit(run: UUID, why: String) -> RunJudgment {
        RunJudgment(run: run, judge: .implicit, verdict: 0, note: why)
    }
}

extension Session {
    /// The user's latest request: their last message that isn't a note kurtkode added (the skill router's, a resumed
    /// session's) or a background subagent's report. A run started after it (a retry, a Continue) answers it too.
    public var lastRequest: ChatMessage? { messages.last { Self.isRequest($0) } }

    static func isRequest(_ m: ChatMessage) -> Bool { m.role == .user && m.contextNote != true && m.subagentReport == nil }

    /// The main run that produced an assistant message: the latest main run answering the nearest request before it
    /// that started a run (queued messages and notes in between don't start one).
    public func mainRun(for messageID: UUID) -> AgentRunRecord? {
        guard let i = messages.firstIndex(where: { $0.id == messageID }) else { return nil }
        let main = runs.filter { $0.agent == "main" }
        let keys = Set(main.compactMap(\.userMessage))
        guard let asked = messages[...i].last(where: { $0.role == .user && keys.contains($0.id) }) else {
            return main.last { $0.started <= messages[i].createdAt && messages[i].createdAt <= $0.ended.addingTimeInterval(1) }
        }
        return main.last { $0.userMessage == asked.id }
    }

    /// Each main run's final reply (its last assistant message without tool calls before the next request that started
    /// a run), by message id, in one pass: where the thumbs go.
    public var replyRuns: [UUID: UUID] {
        var byUser: [UUID: UUID] = [:]
        for r in runs where r.agent == "main" { if let u = r.userMessage { byUser[u] = r.id } }
        guard !byUser.isEmpty else { return [:] }
        var last: [UUID: UUID] = [:]                 // run → its latest final reply
        var current: UUID?
        for m in messages {
            if m.role == .user, let r = byUser[m.id] { current = r }
            else if m.role == .assistant, m.toolCalls.isEmpty, m.meta != nil, let r = current { last[r] = m.id }
        }
        return Dictionary(last.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The run whose reply is the session's latest (for /good and /bad): not a run whose reply was retried or rewound away.
    public var latestReplyRun: AgentRunRecord? {
        let map = replyRuns
        guard let reply = messages.last(where: { map[$0.id] != nil }), let id = map[reply.id] else { return nil }
        return runs.last { $0.id == id }
    }

    /// The session's latest main run.
    public var latestMainRun: AgentRunRecord? { runs.last { $0.agent == "main" } }

    /// The user's thumbs on a main run, if any (the latest).
    public func thumbs(_ run: UUID) -> Bool? {
        judgments.last { $0.run == run && $0.judge == .user }.flatMap { $0.verdict.map { $0 >= 2 } }
    }
}
