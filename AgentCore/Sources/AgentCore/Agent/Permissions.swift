import Foundation

/// How much the agent may do without asking (D10).
public enum PermissionMode: String, Codable, Sendable, CaseIterable {
    /// Reads run freely; edits and commands ask.
    case ask
    /// Reads and edits run freely; commands ask.
    case acceptEdits
    /// Read-only: edit and command tools aren't offered.
    case plan
    /// Everything runs without asking; commands run in the sandbox by default (D9, `SandboxUse`).
    case fullAuto

    public var displayName: String {
        switch self {
        case .ask: "Ask"
        case .acceptEdits: "Accept Edits"
        case .plan: "Plan (read-only)"
        case .fullAuto: "Full Auto"
        }
    }
}

/// A standing "yes" for the rest of the session.
public struct AllowRule: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// Every call of a tool, e.g. all edits.
        case tool
        /// Simple commands starting with these words, e.g. "git status" or "python3 -m unittest".
        case commandPrefix
        /// `web_fetch` of this host and its subdomains.
        case webDomain
    }

    public var kind: Kind
    public var value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public static func tool(_ name: String) -> AllowRule { AllowRule(kind: .tool, value: name) }
    public static func command(_ prefix: String) -> AllowRule { AllowRule(kind: .commandPrefix, value: prefix) }
    public static func domain(_ host: String) -> AllowRule { AllowRule(kind: .webDomain, value: host) }

    public var displayName: String {
        switch kind {
        case .tool: "all \(value) calls"
        case .commandPrefix: "commands starting with \"\(value)\""
        case .webDomain: "fetching from \(value)"
        }
    }
}

public enum ApprovalDecision: Sendable, Equatable {
    case allow
    case allowAlways(AllowRule)
    /// With feedback the run continues and the model sees it; without, the run stops for the user.
    case deny(feedback: String?)
    /// Nobody can answer (kurtkode -p): the call doesn't run, the model gets `message`, and the run goes on. Recorded
    /// as refused before asking, with `why`, not as the user's decision.
    case refuse(message: String, why: String)
}

/// What the user is asked to approve.
public struct ApprovalRequest: Sendable, Identifiable {
    public var id: String { call.id }
    public let call: ToolCall
    public let summary: String
    public let risk: ToolRisk
    public let preview: ToolPreview?
    /// Offered as "Always allow …".
    public let suggestedRule: AllowRule?
    /// Why this call is asked about when the mode alone wouldn't ask: a dangerous command, a permission rule, a repeat.
    public let reason: String?

    public init(call: ToolCall, summary: String, risk: ToolRisk, preview: ToolPreview?, suggestedRule: AllowRule?,
                reason: String? = nil) {
        self.call = call
        self.summary = summary
        self.risk = risk
        self.preview = preview
        self.suggestedRule = suggestedRule
        self.reason = reason
    }
}

public struct PermissionPolicy: Sendable {
    public var mode: PermissionMode
    public var rules: [AllowRule]
    /// Addresses the user said yes to fetching in this run. A long page comes in parts, and each part is the same page.
    var fetched: Set<String> = []

    public init(mode: PermissionMode = .ask, rules: [AllowRule] = []) {
        self.mode = mode
        self.rules = rules
    }

    /// What a main run offers in every mode: all its tools (bash's background tools only with bash). The tool list
    /// leads the cached prompt, so changing it with the mode would make the server read the whole session again at
    /// full price; the mode is enforced when a call comes instead (`modeRefusal`). Subagents keep `offered`.
    public static func offeredInEveryMode(_ tools: [any Tool]) -> [any Tool] {
        if tools.contains(where: { $0.name == "bash" }) { return tools }
        return tools.filter { t in !BackgroundTools.all.contains { $0.name == t.name } }
    }

    /// Why a call of `tool` isn't run in this mode, as the model is told; nil when the mode allows it. Plan mode runs
    /// what `offered` would have offered there (the readers, bash for read-only commands, MCP tools that say they only
    /// read, present_plan); outside it there's no plan to present.
    public func modeRefusal(_ tool: any Tool) -> String? {
        if mode == .plan {
            guard !offered([tool]).isEmpty || BackgroundTools.all.contains(where: { $0.name == tool.name }) else {
                return "not run: plan mode doesn't change anything. Put this step in the plan and present the plan with "
                    + "present_plan; once the user approves it, you carry it out."
            }
            return nil
        }
        return tool.name == "present_plan"
            ? "not run: you're not in plan mode, so there is no plan to approve. Go ahead with the work." : nil
    }

    /// Plan mode offers only read tools; the model can't call what it isn't given.
    public func offered(_ tools: [any Tool]) -> [any Tool] {
        // Plan mode: the readers, and bash for read-only commands (B1); present_plan only there.
        // (An MCP tool that says it only reads comes too; being the server's word, it still asks.)
        let kept = mode == .plan ? tools.filter { $0.risk == .read || $0.name == "bash" || ($0 as? MCPTool)?.readOnly == true }
            : tools.filter { $0.name != "present_plan" }
        // bash_output and kill_shell go with bash.
        if kept.contains(where: { $0.name == "bash" }) { return kept }
        return kept.filter { t in !BackgroundTools.all.contains { $0.name == t.name } }
    }

    public func isAllowedWithoutAsking(_ tool: any Tool, _ args: ToolArguments) -> Bool {
        switch (mode, tool.risk) {
        case (_, .read): return true
        case (.fullAuto, _): return true
        case (.plan, _): return tool.name == "bash" && Self.readOnly(args.string("command") ?? "")
        case (.acceptEdits, .write): return true
        default: break
        }
        if tool.name == "bash", let command = args.string("command"), !Self.isSimple(command) {
            let prefixes = rules.filter { $0.kind == .commandPrefix }.map(\.value)
            return rules.contains { $0.kind == .tool && $0.value == tool.name }
                || Self.compoundAllowed(command) { words in prefixes.contains { Self.commandMatches(words.joined(separator: " "), prefix: $0) } }
        }
        return rules.contains { matches($0, tool: tool, args: args) }
    }

    func matches(_ rule: AllowRule, tool: any Tool, args: ToolArguments) -> Bool {
        switch rule.kind {
        case .tool:
            return rule.value == tool.name
        case .commandPrefix:
            guard tool.name == "bash", let command = args.string("command") else { return false }
            return Self.commandMatches(command, prefix: rule.value)
        case .webDomain:
            guard tool.name == WebFetchTool.toolName, let host = WebFetchTool.host(args) else { return false }
            return PermissionRules.host(host, inDomain: rule.value)
        }
    }

    /// A session's "always allow" covers this web fetch: the sandbox's network setting needn't ask again.
    func allowsDomain(_ tool: any Tool, _ args: ToolArguments) -> Bool {
        rules.contains { $0.kind == .webDomain && matches($0, tool: tool, args: args) }
    }

    /// Characters that let one command line do more than its first words say.
    static let compoundMarkers = [";", "&", "|", "`", "$(", ">", "<", "\n"]

    /// A prefix rule covers only simple commands: the same leading words, and nothing chained on.
    public static func commandMatches(_ command: String, prefix: String) -> Bool {
        let c = command.trimmingCharacters(in: .whitespaces)
        guard !compoundMarkers.contains(where: { c.contains($0) }) else { return false }
        let words = c.split(separator: " ").map(String.init)
        let want = prefix.split(separator: " ").map(String.init)
        return !want.isEmpty && words.count >= want.count && Array(words.prefix(want.count)) == want
    }

    /// A line with nothing that chains, pipes, redirects or substitutes.
    static func isSimple(_ command: String) -> Bool {
        !compoundMarkers.contains { command.trimmingCharacters(in: .whitespaces).contains($0) }
    }

    /// Whether a command line that runs several commands (`cd pkg && npm test 2>&1 | tail -50`, which models write
    /// all the time) is allowed: every command in it (`ShellSplit`: substitutions and `sh -c` scripts included) is
    /// allowed by `allowed`, or is `cd` or a read-only filter (`passThrough`); at least one is allowed by `allowed`;
    /// nothing redirects output into a file; nothing is opaque. Claude Code's rule, which kurtkode's allow rules
    /// lacked: an "always allow swift test" never matched `swift test 2>&1 | tail -30`. Deny, ask and the danger
    /// check still look at every command separately, before this.
    static func compoundAllowed(_ line: String, parsed: [[String]]? = nil, allowed: ([String]) -> Bool) -> Bool {
        let commands = parsed ?? ShellSplit.commands(line)
        guard !commands.isEmpty else { return false }
        var matched = false
        for words in commands {
            if ShellSplit.opaqueReason(words) != nil || writesFile(words) { return false }
            let plain = words.filter { !isRedirection($0) }
            if allowed(plain) { matched = true; continue }
            guard passThrough(plain) else { return false }
        }
        return matched
    }

    /// `cd`, and filters that only read their input or files and print: allowed inside a line whose real commands are.
    static func passThrough(_ words: [String]) -> Bool {
        guard let name = words.first else { return true }
        let args = words.dropFirst()
        switch name {
        case "cd", "true", "echo", "printf", "pwd": return true
        case "grep", "egrep", "fgrep", "wc", "cat", "nl", "cut", "tr", "column", "jq", "head", "tail": return true
        case "sort": return !args.contains { $0 == "-o" || $0.hasPrefix("--output") || $0.hasPrefix("--compress-program")
                                             || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("o")) }
        case "uniq": return args.filter { !$0.hasPrefix("-") }.count <= 1    // a second name is an output file
        default: return false
        }
    }

    /// A redirection word as `ShellSplit` leaves it: `2>&1`, `>`, `>>`, `>out.txt`, `&>log`, `<in`.
    static func isRedirection(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return first == ">" || first == "<" || first == "&" && word.dropFirst().first == ">"
            || (first.isNumber && word.drop(while: \.isNumber).first.map { $0 == ">" || $0 == "<" } == true)
    }

    /// Whether the command's redirections write to a file (not to a stream or /dev/null).
    static func writesFile(_ words: [String]) -> Bool {
        let harmless: Set<String> = ["/dev/null", "/dev/stdout", "/dev/stderr", "&1", "&2", "&-"]
        for (i, w) in words.enumerated() where isRedirection(w) {
            guard let gt = w.firstIndex(of: ">") else { continue }          // input redirection only reads
            var target = String(w[w.index(after: gt)...])
            if target.hasPrefix(">") || target.hasPrefix("|") { target.removeFirst() }
            if target.isEmpty { target = i + 1 < words.count ? words[i + 1] : "" }
            if target.hasPrefix("&"), target.dropFirst().allSatisfy({ $0.isNumber || $0 == "-" }) { continue }
            if !harmless.contains(target) { return true }
        }
        return false
    }

    /// Tools whose second word is the real action, and their global options that take a value.
    static let twoWord: [String: Set<String>] = [
        "git": ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"],
        "npm": ["--prefix", "-w", "--workspace"], "yarn": ["--cwd"], "pnpm": ["-C", "--dir", "-F", "--filter"],
        "swift": [], "cargo": ["-C", "--config", "-Z"], "go": ["-C"], "make": ["-C", "-f", "--directory", "--file"],
        "docker": ["-H", "--host", "-c", "--context", "--config", "-l", "--log-level"], "pip": [], "pip3": [], "brew": [],
        "xcodebuild": [], "uv": ["--directory", "--project"], "poetry": ["-C", "--directory"],
        "kubectl": ["-n", "--namespace", "--context", "--kubeconfig", "-s", "--server"], "gh": ["-R", "--repo"],
    ]

    /// Interpreters: like shells, what they run is the script or code they're given.
    static let interpreters: Set<String> = ["python", "python2", "python3", "node", "ruby", "perl", "php", "lua", "Rscript",
                                            "osascript", "tclsh", "pwsh", "deno", "bun", "awk", "gawk"]

    /// Words that fetch and run a package named after them.
    static let launchers: Set<String> = ["npx", "bunx", "uvx", "pipx", "pnpx"]

    /// The rule offered for "Always allow": the tool for edits, the first word or two for commands (never a bare
    /// wrapper, shell or interpreter, which would allow anything run through it).
    public static func suggestedRule(_ tool: any Tool, _ args: ToolArguments) -> AllowRule? {
        switch tool.risk {
        case .read: return nil
        case .write: return .tool(tool.name)
        case .execute:
            // An outside (MCP) tool: allow that one tool, whatever its arguments.
            if tool.name.hasPrefix("mcp__") { return .tool(tool.name) }
            if tool.name == WebFetchTool.toolName { return WebFetchTool.host(args).map(AllowRule.domain) }
            guard let command = args.string("command")?.trimmingCharacters(in: .whitespaces),
                  !compoundMarkers.contains(where: { command.contains($0) }) else { return nil }
            let words = command.split(separator: " ").map(String.init)
            guard let first = words.first else { return nil }
            // Wrappers (and assignments) run the command after them: only this command line is offered.
            if ShellSplit.wrappers[first] != nil || ShellSplit.isAssignment(first) || launchers.contains(first) {
                return .command(command)
            }
            // A shell or an interpreter runs whatever it's given: a script file is offered as this command line, and
            // nothing for code given inline or read from input. `python3 -m pytest` is a tool like any other.
            if ShellSplit.shells.contains(first) || interpreters.contains(first) {
                if ["python", "python3"].contains(first), words.count > 2, words[1] == "-m" {
                    return .command("\(first) -m \(words[2])")
                }
                return words.count > 1 && !words[1].hasPrefix("-") ? .command(command) : nil
            }
            // Tools whose second word is the real action: "git status" vs "git push". Global options before it are
            // kept in the rule (`git -C sub status`); one kurtkode can't place makes it this command line only.
            if let valued = twoWord[first] {
                var i = 1
                while i < words.count, words[i].hasPrefix("-") {
                    let key = words[i].firstIndex(of: "=").map { String(words[i][..<$0]) }
                    if valued.contains(words[i]) { i += 2 }
                    else if let key, valued.contains(key) { i += 1 }
                    else { return .command(command) }
                }
                return .command(words.prefix(i + 1).joined(separator: " "))
            }
            return .command(first)
        }
    }
}
