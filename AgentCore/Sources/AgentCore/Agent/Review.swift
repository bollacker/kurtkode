import Foundation

/// Cross-vendor review (GAP_ANALYSIS.md A6): a model from another vendor than the one that made a change reads the
/// request, what the agent said it did, the checks it ran and the diff, and returns findings and a verdict. On request
/// (`/review`, the Changes tab's Review button), and automatically for subagent tasks with `importance: high` that
/// changed files (hosted sessions). Its verdict is also a judgment of the run (judge `reviewer`), and A4 reads it as an
/// escalation trigger.
public struct CodeReview: Codable, Sendable, Hashable {
    public enum Verdict: String, Codable, Sendable, CaseIterable {
        case looksRight = "looks_right", hasProblems = "has_problems", wrong

        /// As a 0–3 run verdict (`RunJudgment.verdictMeanings`).
        public var score: Int {
            switch self {
            case .looksRight: 3
            case .hasProblems: 1
            case .wrong: 0
            }
        }

        public var label: String {
            switch self {
            case .looksRight: "looks right"
            case .hasProblems: "has problems"
            case .wrong: "wrong"
            }
        }
    }

    public struct Finding: Codable, Sendable, Hashable {
        public var file: String?
        public var line: Int?
        /// high, medium or low.
        public var severity: String
        public var problem: String

        public init(file: String?, line: Int?, severity: String, problem: String) {
            self.file = file
            self.line = line
            self.severity = severity
            self.problem = problem
        }

        /// "high · calc.py:12 · divides by the count, not the total".
        public var line1: String {
            ([severity] + [file.map { f in line.map { "\(f):\($0)" } ?? f }].compactMap { $0 } + [problem]).joined(separator: " · ")
        }
    }

    /// Nil when the reviewer gave none (its reply is in `response`).
    public var verdict: Verdict?
    public var findings: [Finding]
    public var summary: String?
    public var reviewer: String
    public var reviewerEndpointID: UUID?
    /// Why there's no verdict, when there isn't.
    public var problem: String?
    public var prompt: String?
    public var response: String?
    public var requestID: UUID?
    public var at = Date()

    /// Whether the verdict is a reason to hand the request to a stronger model: "wrong" only. At real size
    /// (COST_AUDIT.md §10, point 4) Sonnet's reviews called 60% of passing runs "has problems"; "wrong" caught 74% of
    /// real failures with 1 false alarm in 47. "Has problems" is findings for the session's own model to fix.
    public var escalates: Bool { verdict == .wrong }

    /// The judgment it makes of the run reviewed.
    public func judgment(run: UUID, taskCall: String? = nil) -> RunJudgment {
        // It saw the diff, not the files.
        var j = RunJudgment(run: run, taskCall: taskCall, judge: .reviewer, judgeModel: reviewer, judgeEndpointID: reviewerEndpointID,
                            verdict: verdict?.score, checked: RunJudgment.Checked.spotChecked.rawValue,
                            issues: [], note: verdict == nil ? "No verdict: \(problem ?? "unknown")." : summary)
        j.evidence = findings.isEmpty ? nil : findings.map(\.line1)
        j.requestID = requestID
        j.prompt = prompt
        j.response = response
        return j
    }

    /// For the transcript, the CLI, and a parent's view of a subagent's report.
    public var text: String {
        guard let verdict else { return "The review on \(reviewer) gave no verdict (\(problem ?? "unknown"))." }
        var s = "Review by \(reviewer): \(verdict.label)."
        if let summary, !summary.isEmpty { s += " " + summary }
        for f in findings { s += "\n- " + f.line1 }
        return s
    }

    /// The message that asks the session's model to deal with the findings.
    public var fixRequest: String {
        "A reviewer (\(reviewer), another vendor's model) read the change and found these problems. Check each one against "
            + "the code; fix the ones that are real and say which you think are wrong and why.\n\n"
            + findings.map { "- " + $0.line1 }.joined(separator: "\n")
    }

    // MARK: Asking

    static let toolName = "submit_review"

    static var tool: ToolDefinition {
        ToolDefinition(name: toolName, description: "Report your review of the change: a verdict and the problems found.",
                       parameters: .object([
                        "type": "object",
                        "properties": .object([
                            "verdict": .object(["type": "string", "enum": .array(Verdict.allCases.map { .string($0.rawValue) }),
                                                "description": "looks_right: does what was asked, nothing wrong found; has_problems: mostly right but with real problems to fix; wrong: doesn't do what was asked, breaks something, or claims work that isn't in the diff"]),
                            "findings": .object(["type": "array", "items": .object([
                                "type": "object",
                                "properties": .object([
                                    "file": .object(["type": "string"]), "line": .object(["type": "integer"]),
                                    "severity": .object(["type": "string", "enum": ["high", "medium", "low"]]),
                                    "problem": .object(["type": "string", "description": "What's wrong and why, in one or two sentences"]),
                                ]),
                                "required": ["severity", "problem"],
                            ])]),
                            "summary": .object(["type": "string", "description": "One or two sentences"]),
                        ]),
                        "required": ["verdict", "findings"],
                       ]))
    }

    static let system = "You review changes made by coding agents. Be concrete and strict: a confident description is not "
        + "evidence; the diff is. Report real problems only (bugs, missed parts of the request, changes nobody asked for, "
        + "broken behavior, claims the diff doesn't support), not style preferences."

    /// The review request: the request, the agent's account, the checks, and the diff (cut to `maxDiffBytes`).
    public static func prompt(request: String, report: String?, checks: [String], diff: String, maxDiffBytes: Int = 60_000) -> String {
        var s = "Review this change. Call \(toolName) once.\n\n## What was asked\n\n" + String(request.prefix(8_000))
        if let report, !report.isEmpty { s += "\n\n## What the agent says it did\n\n" + String(report.prefix(6_000)) }
        s += "\n\n## Checks it ran\n\n" + (checks.isEmpty ? "None recorded." : checks.map { "- " + $0 }.joined(separator: "\n"))
        if diff.isEmpty {
            s += "\n\n## The diff\n\n(No files changed.)"
        } else {
            let cut = diff.utf8.count > maxDiffBytes
            let shown = cut ? String(decoding: Data(diff.utf8.prefix(maxDiffBytes)), as: UTF8.self) : diff
            s += "\n\n## The diff\n\n```diff\n" + shown + (cut ? "\n… (cut: the whole diff is \(diff.utf8.count / 1000) KB)" : "") + "\n```"
        }
        return s
    }

    /// One request to the reviewer (no tools but `submit_review`; a call written as text is read too).
    public static func run(_ reviewer: SubagentModel, prompt: String, costs: CostSink?, meter: CostMeter?,
                           limits: TurnLimits) async -> CodeReview {
        var request = ChatRequest(model: reviewer.model, messages: [.system(system), .user(prompt)], tools: [tool],
                                  maxTokens: reviewer.client.api == .openai ? 8_000 : 16_000, temperature: reviewer.temperature)
        request.oneOff = true             // asked once: no cache write to pay for
        if let p = reviewer.providers, !p.isEmpty { request.provider = p }
        ReasoningSetting.apply(reviewer.reasoning, to: &request, client: reviewer.client)
        var reviewLimits = limits
        reviewLimits.maxTokens = request.maxTokens
        let started = Date()
        let reply = await TurnRunner.run(client: reviewer.client, request: request, limits: reviewLimits, tap: nil) { _ in }
        if let entry = await costs?.record(reply, purpose: .review, client: reviewer.client, start: started) { meter?.add(entry) }
        var result = CodeReview(verdict: nil, findings: [], summary: nil, reviewer: reviewer.model, reviewerEndpointID: reviewer.endpointID,
                                prompt: prompt, requestID: reply.id)
        var calls = reply.toolCalls.filter { $0.name == toolName }
        if calls.isEmpty, let found = TextToolCalls.extract(from: reply.content, knownTools: [toolName],
                                                            parameterSchemas: [toolName: tool.parameters]) {
            calls = found.calls.filter { $0.name == toolName }.map { ToolCall(id: "text", name: $0.name, arguments: $0.arguments) }
        }
        result.response = reply.content + calls.map { "\n[\($0.name) \($0.arguments)]" }.joined()
        guard let call = calls.first, let args = try? ToolArguments(json: call.arguments),
              let verdict = args.string("verdict").flatMap(Verdict.init(rawValue:)) else {
            if reply.meta?.finishReason == .length { result.problem = "the reply hit its output limit" }
            else if let stop = reply.meta?.stopReason, stop != .completed { result.problem = "the request ended early (\(stop))" }
            else { result.problem = calls.isEmpty ? "no \(toolName) call" : "the call had no usable verdict" }
            return result
        }
        result.verdict = verdict
        result.summary = args.string("summary")
        if case .array(let items)? = args.values["findings"] {
            result.findings = items.compactMap { item in
                guard case .object(let o) = item, case .string(let problem)? = o["problem"] else { return nil }
                let line: Int? = { if case .number(let n)? = o["line"] { Int(json: n) } else { nil } }()
                let file: String? = { if case .string(let f)? = o["file"], !f.isEmpty { f } else { nil } }()
                let sev: String = { if case .string(let s)? = o["severity"] { s.lowercased() } else { "medium" } }()
                return Finding(file: file, line: line, severity: sev, problem: problem)
            }
        }
        return result
    }
}

/// Which company's models these are, to keep a reviewer off the vendor whose model made the change.
public enum ModelVendor {
    /// "anthropic", "google", "openai", "deepseek", "alibaba", "meta", "mistral", "inclusionai", … from the model id
    /// (and the endpoint for native APIs); the id's own prefix otherwise.
    public static func of(_ model: String, endpoint: Endpoint? = nil) -> String {
        if endpoint?.kind == .anthropic { return "anthropic" }
        if endpoint?.kind == .gemini { return "google" }
        let id = model.lowercased()
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let known: [(String, [String])] = [
            ("anthropic", ["claude", "haiku", "sonnet", "opus"]), ("google", ["gemini", "gemma"]),
            ("openai", ["gpt-", "gpt", "o1", "o3", "o4", "codex"]), ("deepseek", ["deepseek"]), ("alibaba", ["qwen", "qwq"]),
            ("meta", ["llama"]), ("mistral", ["mistral", "magistral", "devstral", "codestral", "ministral"]),
            ("inclusionai", ["ling", "ring-"]), ("moonshot", ["kimi"]), ("zhipu", ["glm"]), ("xai", ["grok"]),
            ("microsoft", ["phi-"]), ("ibm", ["granite"]), ("nvidia", ["nemotron"]),
        ]
        for (vendor, names) in known where names.contains(where: { name.hasPrefix($0) }) { return vendor }
        if id.contains("/") { return String(id.split(separator: "/")[0]) }
        return name.split(separator: "-").first.map(String.init) ?? name
    }
}

public enum ReviewRouting {
    /// The reviewer for a change made on `model` at `endpoint`: the pool's first reviewer of another vendor (the lowest
    /// tier first). A hosted session may use any; a local one only reviewers on this Mac or its network, so nothing
    /// leaves it that didn't before (the user can still name a remote one).
    public static func reviewer(for model: String, endpoint: Endpoint, pool: ModelPool, endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        reviewer(excluding: [ModelVendor.of(model, endpoint: endpoint)], session: endpoint, pool: pool, endpoints: endpoints)
    }

    /// The same, keeping off every vendor in `vendors` (the models that made the change; a session may have switched
    /// since). "This Mac or its network" is the strict reading: a server kurtkode can't place counts as remote, so a
    /// local session's diff never goes to an unrecognized host (Azure, a cloud VM) on its own.
    public static func reviewer(excluding vendors: Set<String>, session endpoint: Endpoint, pool: ModelPool,
                                endpoints: [Endpoint]) -> ResolvedPoolEntry? {
        pool.available(.reviewer, endpoints: endpoints)
            .filter { !vendors.contains(ModelVendor.of($0.model, endpoint: $0.endpoint)) && (endpoint.isCloudAPI || !$0.endpoint.isThirdParty) }
            .min { ($0.entry.tier, $0.entry.ladder ?? .max) < ($1.entry.tier, $1.entry.ladder ?? .max) }
    }
}

/// What a review of a session's work reads, for a scope (`/review`, the Changes tab).
public struct ReviewInput: Sendable {
    public var request: String
    public var report: String?
    public var checks: [String]
    public var diff: String
    /// The main run reviewed, for the judgment: the run (or the turn's latest); nil for a whole session's change, whose
    /// verdict isn't one run's.
    public var run: AgentRunRecord?
    /// The vendors of the models whose runs made the change (the reviewer must be another).
    public var vendors: Set<String> = []
    /// Files left out of the diff because they're withheld from remote models (`withholding`).
    public var withheld: [String] = []

    public init(request: String, report: String?, checks: [String], diff: String, run: AgentRunRecord?) {
        self.request = request
        self.report = report
        self.checks = checks
        self.diff = diff
        self.run = run
    }

    /// From the runs' snapshots; without them, the project's uncommitted changes (`git diff HEAD`).
    public static func gather(scope: ProjectSnapshots.Scope, session: Session, snapshots: ProjectSnapshots?) async throws -> ReviewInput {
        let mains = session.runs.filter { $0.agent == "main" }.sorted { $0.started < $1.started }
        let id = session.header.id
        var diff = "", inScope: [AgentRunRecord] = []
        if let snaps = snapshots, let range = ProjectSnapshots.range(try await snaps.list(session: id), scope) {
            diff = try await snaps.patch(session: id, from: range.from.commit, to: range.to?.commit)
            let starts = Set(try await snaps.list(session: id).filter { $0.phase == .start && $0.date >= range.from.date }.compactMap(\.run))
            inScope = mains.filter { starts.contains($0.id) }
            if case .turn(let t) = scope { inScope = mains.filter { $0.userMessage == t } }
        } else if let root = snapshots?.project ?? session.header.workspace.map({ URL(fileURLWithPath: $0) }) {
            diff = (try? await GitRepo(root: root).git(["diff", "--no-ext-diff", "-M", "HEAD"])) ?? ""
            inScope = Array(mains.suffix(1))
        }
        if inScope.isEmpty { inScope = Array(mains.suffix(scope == .session ? mains.count : 1)) }
        let requests = inScope.compactMap { r in session.messages.first { $0.id == r.userMessage }?.content }
        var unique: [String] = []
        for r in requests where !unique.contains(r) { unique.append(r) }
        let request = unique.isEmpty ? (session.lastRequest?.content ?? "") :
            unique.count == 1 ? unique[0] : unique.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
        let report = session.messages.last { $0.role == .assistant && !$0.content.isEmpty }?.content
        let vendors = Set(inScope.map { ModelVendor.of($0.setup.model, endpoint: nil) })
        var checks: [String] = []
        for r in inScope {
            if let c = r.signals?.lastCheck { checks.append("\(c.command) → " + (c.timedOut == true ? "timed out" : "exit \(c.exitCode.map(String.init) ?? "?")")) }
            if let t = r.signals?.unfinishedTodos, !t.isEmpty { checks.append("todos left unfinished: " + t.joined(separator: "; ")) }
        }
        var input = ReviewInput(request: request, report: report, checks: checks, diff: diff, run: scope == .session ? nil : inScope.last)
        input.vendors = vendors
        return input
    }

    /// Leaves out of the diff the files Settings withholds from remote models (for a reviewer that isn't local).
    public mutating func withholding(_ patterns: [String]) {
        (diff, withheld) = UnifiedDiff.withholding(diff, patterns: patterns)
        if !withheld.isEmpty { checks.append("(\(withheld.count) file\(withheld.count == 1 ? "" : "s") withheld from remote models left out of the diff)") }
    }

    public var prompt: String { CodeReview.prompt(request: request, report: report, checks: checks, diff: diff) }
}
