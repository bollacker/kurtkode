import Foundation

/// A plan the model presents in Plan mode (B1), for the user to approve, send back, or reject.
public struct PlanProposal: Sendable, Hashable {
    /// Markdown.
    public var plan: String
    /// Where it was saved (the session's outputs folder), when it was.
    public var file: URL?
    /// The call presenting it, so the app can match the card to it.
    public var callID: String?

    public init(plan: String, file: URL? = nil, callID: String? = nil) {
        self.plan = Self.unfenced(plan)
        self.file = file
        self.callID = callID
    }
}

extension PlanProposal {
    /// The plan with ```markdown fences around it taken off (Gemma 4 wraps its plans in one, which then shows as code).
    static func unfenced(_ text: String) -> String {
        text.replacingOccurrences(of: #"```(?:markdown|md)[ \t]*\n([\s\S]*?)\n```"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What the user decided about a plan.
public enum PlanDecision: Sendable, Hashable {
    /// Go ahead in this mode (Accept Edits or Full Auto); the same run carries on.
    case approve(PermissionMode)
    /// Change the plan as the feedback says, and present it again.
    case revise(String)
    /// Don't do it; the run stops (with the reason, if given).
    case reject(String?)

    /// What the user typed at a prompt (the CLI): "1"/"e" accept edits, "2"/"a" full auto, "3"/"r" revise (the rest of
    /// the line, or the next line, is the feedback), "4"/"n" reject; anything else is feedback for a revision.
    public static func parse(_ typed: String) -> PlanDecision? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        switch lower.trimmingCharacters(in: CharacterSet(charactersIn: ".!")) {
        case "1", "e", "edits", "y", "yes", "ok", "okay", "approve", "approved", "lgtm", "go", "go ahead", "sounds good",
             "do it", "accept", "accept edits": return .approve(.acceptEdits)
        case "2", "a", "auto", "full auto": return .approve(.fullAuto)
        case "3", "r", "revise": return .revise("")
        case "4", "n", "no", "reject": return .reject(nil)
        default: break
        }
        for prefix in ["3 ", "r ", "revise "] where lower.hasPrefix(prefix) {
            return .revise(String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        for prefix in ["4 ", "n ", "reject "] where lower.hasPrefix(prefix) {
            return .reject(String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        return .revise(t)
    }
}

/// Plan mode's way out (B1): the model presents its plan; the user approves it (the mode switches and the run carries
/// on with the plan), asks for changes, or rejects it. Offered in Plan mode when someone can answer.
public struct PresentPlanTool: Tool {
    public init() {}
    public let name = "present_plan"
    public let risk = ToolRisk.read
    public let description = """
        Present your plan to the user for approval, once you have looked into the task. Write it in Markdown: the \
        goal, the files you will change and how, the commands you will run to check the work, and anything you are \
        unsure of. If the user approves, the mode switches and you carry the plan out right away in this same \
        conversation; if they ask for changes, revise it and present it again.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": ["plan": ["type": "string", "description": "The plan, in Markdown."]],
        "required": ["plan"],
    ]

    public func summary(_ args: ToolArguments) -> String {
        let first = (args.string("plan") ?? "").split(separator: "\n").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        return "Present a plan" + (first.map { $0.isEmpty ? "" : ": " + ($0.count > 70 ? String($0.prefix(67)) + "…" : $0) } ?? "")
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let plan = (args.string("plan") ?? args.string("content") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plan.isEmpty else { throw ToolFailure("plan is empty. Write the plan in Markdown.") }
        guard let present = context.presentPlan else {
            return ToolOutput(text: "Nobody is here to approve a plan in this run. Give the plan as your final answer instead.")
        }
        // Saved beside the session's other outputs, so it outlives the conversation's compactions.
        let file = context.fullOutputURL.map { $0.deletingPathExtension().appendingPathExtension("md") }
        let proposal = PlanProposal(plan: plan, file: file, callID: context.callID)
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data((proposal.plan + "\n").utf8).write(to: file)
        }
        let decision = await present(proposal)
        if Task.isCancelled { throw ToolFailure("the run was stopped before the user decided.") }
        let saved = file.map { " The plan is saved in \($0.path)." } ?? ""
        switch decision {
        case .approve(let mode):
            var out = ToolOutput(text: "The user approved the plan. You are now in \(mode.displayName) mode"
                + (mode == .fullAuto ? " (actions run without asking)" : " (edits are allowed without asking; commands are asked about)")
                + ". Carry out the plan now, step by step, and check the work as it says." + saved)
            out.newMode = mode
            return out
        case .revise(let feedback):
            return ToolOutput(text: "The user wants changes to the plan: \(feedback)\nRevise it and present it again with "
                + "present_plan. You are still in plan mode." + saved)
        case .reject(let reason):
            var out = ToolOutput(text: "The user rejected the plan" + (reason.map { $0.isEmpty ? "" : ": \($0)" } ?? "")
                + ". Don't carry it out; stop and wait for their instructions." + saved)
            out.endsRun = true
            return out
        }
    }
}

extension PermissionPolicy {
    /// A command line that only reads (B1: Plan mode runs these, in a sandbox that blocks writes): every command in
    /// it is one of a list of readers (git's read-only subcommands, ls, cat, grep, find without -exec or -delete, …)
    /// or a `--version`/`--help`, nothing writes a file through a redirection, and nothing is opaque.
    public static func readOnly(_ line: String) -> Bool {
        let commands = ShellSplit.commands(line)
        guard !commands.isEmpty else { return false }
        return commands.allSatisfy { words in
            ShellSplit.opaqueReason(words) == nil && !writesFile(words) && readOnlyCommand(words.filter { !isRedirection($0) })
        }
    }

    /// Toolchains whose `--version` (or `--help`) only prints: asked by bare name, so a project's own script with
    /// the same first word can't stand in.
    static let versionTools: Set<String> = ["python", "python3", "node", "npm", "npx", "yarn", "pnpm", "bun", "deno", "swift",
                                            "swiftc", "go", "cargo", "rustc", "java", "javac", "ruby", "gem", "pip", "pip3",
                                            "make", "cmake", "git", "brew", "uv", "poetry", "clang", "gcc", "xcodebuild", "rg"]

    /// Where a read-only command may come from: by name (looked up on PATH; Plan mode runs without carried variables,
    /// so PATH is the login one) or from a system folder. "./tools/git" or "node_modules/.bin/cat" is a project file.
    static func systemCommand(_ word: String) -> Bool {
        guard word.contains("/") else { return true }
        return ["/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/opt/homebrew/bin/", "/usr/local/bin/"].contains { word.hasPrefix($0) }
            && !word.contains("..")
    }

    static func readOnlyCommand(_ words: [String]) -> Bool {
        guard let first = words.first else { return true }
        guard systemCommand(first) else { return false }
        let name = (first as NSString).lastPathComponent
        let args = Array(words.dropFirst())
        if name == "sort", args.contains(where: { $0.hasPrefix("--compress-program") }) { return false }
        if passThrough([name] + args) { return true }
        if args.count == 1, versionTools.contains(name), ["--version", "-version", "-V", "-v", "--help", "-h", "version"].contains(args[0]) {
            return true
        }
        switch name {
        case "ls", "file", "stat", "du", "df", "which", "whereis", "type", "basename", "dirname", "realpath",
             "readlink", "uname", "sw_vers", "date", "whoami", "hostname", "diff", "cmp", "hexdump",
             "od", "strings", "shasum", "sha1sum", "sha256sum", "md5", "md5sum", "false", "test", "[":
            // file -C compiles a magic file (writes); date and hostname with an argument set them.
            if name == "file", args.contains(where: { $0.hasPrefix("-C") || $0 == "--compile" }) { return false }
            if ["date", "hostname"].contains(name), args.contains(where: { !$0.hasPrefix("-") && !$0.hasPrefix("+") }) { return false }
            return true
        case "tree":
            return !args.contains { $0 == "-o" || $0.hasPrefix("-o") && $0.count > 2 && !$0.hasPrefix("--") }
        case "xxd":
            // A second file name is where it writes.
            return args.filter { !$0.hasPrefix("-") }.count <= 1 && !args.contains("-r")
        case "rg", "ag":
            // A preprocessor (--pre) or decompressors (-z) run programs.
            return !args.contains { $0.hasPrefix("--pre") || $0 == "-z" || $0 == "--search-zip" || $0.hasPrefix("--hostname-bin") }
        case "find":
            let acting: Set<String> = ["-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"]
            return !args.contains { acting.contains($0) }
        case "sed":
            return sedPrintsOnly(args)
        case "git": return gitReadOnly(args)
        default: return false
        }
    }

    /// sed that only prints a range or the lines matching a pattern (`sed -n '10,40p' f`, `sed -n '/x/p' f`): -i/-I edit in
    /// place and a w command writes, so anything else is refused rather than parsed.
    static func sedPrintsOnly(_ args: [String]) -> Bool {
        var scripts: [String] = []
        var files = 0
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-e", i + 1 < args.count { scripts.append(args[i + 1]); i += 2; continue }
            if a == "-n" || a == "-E" || a == "-r" || a == "--quiet" || a == "--silent" { i += 1; continue }
            if a.hasPrefix("-") { return false }
            if scripts.isEmpty && files == 0 && !args.contains("-e") { scripts.append(a) } else { files += 1 }
            i += 1
        }
        let address = #"(\d+|\$|/[^/]*/)"#
        return !scripts.isEmpty && scripts.allSatisfy {
            $0.range(of: "^\(address)(,\(address))?p$", options: .regularExpression) != nil
        }
    }

    static func gitReadOnly(_ args: [String]) -> Bool {
        var a = args[...]
        // Global options: only ones that don't change what runs (-c, --config-env, --exec-path and the like can).
        while let f = a.first, f.hasPrefix("-") {
            guard ["-C", "--no-pager", "-P", "--no-optional-locks", "--literal-pathspecs", "--no-replace-objects"].contains(f) else { return false }
            a = a.dropFirst(f == "-C" ? 2 : 1)
        }
        guard let sub = a.first else { return true }
        let rest = Array(a.dropFirst())
        // Options that write a file, run a program (a pager, an external diff, a text converter) or open a browser.
        if rest.contains(where: { o in
            ["--output", "--ext-diff", "-O", "--open-files-in-pager", "--textconv", "--web", "-w", "--man", "-m", "-i", "--info",
             "--config-env"].contains { o == $0 || o.hasPrefix($0 + "=") || ($0 == "-O" && o.hasPrefix("-O")) }
                && !(sub != "help" && ["-w", "-m", "-i"].contains(o))
        }) { return false }
        if sub == "help", rest.contains(where: { $0.hasPrefix("-") }) { return false }
        switch sub {
        case "log", "show", "diff", "blame", "annotate", "status", "ls-files", "ls-tree", "grep", "rev-parse", "rev-list",
             "describe", "shortlog", "cat-file", "merge-base", "name-rev", "for-each-ref", "show-ref", "count-objects",
             "whatchanged", "help", "version":
            return true
        case "branch":
            let listing: Set<String> = ["-a", "-r", "-v", "-vv", "--list", "-l", "--all", "--remotes", "--show-current",
                                        "--merged", "--no-merged", "--contains", "--no-color", "--color=never"]
            return rest.allSatisfy { listing.contains($0) || (!$0.hasPrefix("-") && (rest.contains("--list") || rest.contains("-l")
                || rest.contains("--contains") || rest.contains("--merged") || rest.contains("--no-merged"))) }
        case "tag": return rest.isEmpty || ["-l", "--list", "-n"].contains(rest[0])
        case "remote": return rest.isEmpty || rest == ["-v"]
        case "stash": return ["list", "show"].contains(rest.first ?? "")
        case "reflog": return rest.isEmpty || rest.first == "show"
        case "worktree": return rest.first == "list"
        case "config": return rest.contains { ["--get", "--get-all", "--list", "-l", "--get-regexp"].contains($0) }
        default: return false
        }
    }
}

/// A run's mode, sandbox and session rules as they are now, for what reads them later in the run: subagents started
/// after an approved plan switched the mode, the checks run at the end, and the parent's own authorizations after a
/// subagent's card added an "always allow" rule (its `.ruleAdded` is noted here as it passes through the run's emit).
final class RunMode: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: PermissionPolicy
    private var sandbox: SandboxPolicy?

    init(policy: PermissionPolicy, sandbox: SandboxPolicy?) {
        self.policy = policy
        self.sandbox = sandbox
    }

    /// The mode and sandbox change; rules only ever accrue.
    func set(policy: PermissionPolicy, sandbox: SandboxPolicy?) {
        lock.withLock {
            let known = self.policy.rules
            self.policy = policy
            self.policy.rules = known + policy.rules.filter { !known.contains($0) }
            self.sandbox = sandbox
        }
    }

    /// An "always allow" the user gave this run (through the main agent's card or a subagent's).
    func add(_ rule: AllowRule) {
        lock.withLock { if !policy.rules.contains(rule) { policy.rules.append(rule) } }
    }

    /// The session's rules so far, into a policy about to decide a call.
    func syncRules(into policy: inout PermissionPolicy) {
        let known = lock.withLock { self.policy.rules }
        policy.rules += known.filter { !policy.rules.contains($0) }
    }

    /// `config` with the run's current mode, sandbox and rules.
    func applied(to config: AgentConfig) -> AgentConfig {
        var c = config
        lock.withLock {
            (c.policy.mode, c.sandbox) = (policy.mode, sandbox)
            c.policy.rules += policy.rules.filter { !c.policy.rules.contains($0) }
        }
        return c
    }
}
