import Foundation
import CryptoKit

/// Standing permission rules from settings files, in Claude Code's format, so files written for it work:
///
///     {"permissions": {"allow": ["Bash(git status)", "Bash(npm run test:*)", "Edit(src/**)"],
///                      "ask":   ["Bash(git push:*)"],
///                      "deny":  ["Read(./.env)", "Bash(rm -rf:*)"]}}
///
/// A rule is a tool (`Bash`, `Read`, `Edit`, `Write`, `Grep`, `Glob`, `LS`, `mcp__server`, `mcp__server__tool`), with an
/// optional specifier: for Bash a command (`git status` exactly, `npm run test:*` by its leading words, `git * main` with
/// wildcards); for files a gitignore-style path (`//abs/path`, `~/path`, `/path` from the project root, `path` or
/// `./path` from the working folder, `**` across folders). Read rules cover every tool that reads files; Edit rules
/// every tool that changes them. Deny wins over ask, ask over allow, in every permission mode.
public struct PermissionRule: Sendable, Hashable {
    public enum Action: String, Codable, Sendable { case allow, ask, deny }

    public var action: Action
    public var tool: String
    public var specifier: String?
    /// The settings file it came from, as shown to the user.
    public var source: String

    public init(action: Action, tool: String, specifier: String?, source: String) {
        self.action = action
        self.tool = tool
        self.specifier = specifier
        self.source = source
    }

    /// Parses "Bash(npm run test:*)" or "Edit"; nil for an empty or malformed rule.
    public init?(_ text: String, action: Action, source: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let open = t.firstIndex(of: "("), t.hasSuffix(")") {
            let name = String(t[..<open]).trimmingCharacters(in: .whitespaces)
            let inner = String(t[t.index(after: open)..<t.index(before: t.endIndex)]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            self.init(action: action, tool: name, specifier: inner.isEmpty || inner == "*" ? nil : inner, source: source)
        } else {
            guard !t.contains("(") && !t.contains(")") else { return nil }
            self.init(action: action, tool: t, specifier: nil, source: source)
        }
    }

    /// "Bash(git push:*)" as written.
    public var text: String { specifier.map { "\(tool)(\($0))" } ?? tool }
}

/// The rules that apply to a run, and the decision for a call.
public struct PermissionRules: Sendable, Hashable {
    public var rules: [PermissionRule]
    /// Where relative path patterns start (the project root or chat folder).
    public var root: URL?

    public init(rules: [PermissionRule] = [], root: URL? = nil) {
        self.rules = rules
        self.root = root
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// kurtkode's tools under Claude Code's names. Read and Edit rules also cover the other tools that read or change files.
    static let claudeNames = ["bash": "Bash", "read_file": "Read", "edit_file": "Edit", "write_file": "Write", "grep": "Grep", "web_fetch": "WebFetch",
                              "glob": "Glob", "list_dir": "LS", "todo_write": "TodoWrite", "task": "Task",
                              "skill": "Skill", "ask_user": "AskUserQuestion",
                              "bash_output": "BashOutput", "kill_shell": "KillShell"]
    static let readers: Set<String> = ["read_file", "grep", "glob", "list_dir"]
    static let editors: Set<String> = ["edit_file", "write_file", "apply_patch"]

    /// The strongest rule matching the call (deny, then ask, then allow), or nil.
    public func decision(toolName: String, args: ToolArguments) -> PermissionRule? {
        // A command line is split once for all the rules.
        let commands = toolName == "bash" ? args.string("command").map { ($0, ShellSplit.commands($0)) } : nil
        let matching = rules.filter { matches($0, toolName: toolName, args: args, commands: commands) }
        if let r = matching.first(where: { $0.action == .deny }) { return r }
        if let r = matching.first(where: { $0.action == .ask }) { return r }
        // A command kurtkode can't read (`ShellSplit.opaque`: a computed command name, a shell reading piped input)
        // could be the one a deny or ask rule names: asked about, never let through by an allow rule.
        if let (_, parsed) = commands, parsed.contains(where: { ShellSplit.opaqueReason($0) != nil }),
           var r = rules.first(where: { $0.action != .allow && $0.specifier != nil && covers($0.tool, toolName) }) {
            r.action = .ask
            return r
        }
        if let r = matching.first(where: { $0.action == .allow }) { return r }
        // A line of several commands is allowed when each is (`PermissionPolicy.compoundAllowed`): the rule given is
        // the first allow rule that matched one of them.
        if let (line, parsed) = commands, !PermissionPolicy.isSimple(line) {
            let allows = rules.filter { $0.action == .allow && covers($0.tool, toolName) }
            func rule(for words: [String]) -> PermissionRule? {
                allows.first { r in r.specifier.map { Self.commandMatches(words.joined(separator: " "), $0) } ?? true }
            }
            var first: PermissionRule?
            if PermissionPolicy.compoundAllowed(line, parsed: parsed, allowed: { words in
                guard let r = rule(for: words) else { return false }
                if first == nil { first = r }
                return true
            }) { return first }
        }
        return nil
    }

    /// Whether an allow rule that names this command's dangers lets it run without the danger check's question
    /// (`Bash(git reset --hard:*)` for `git reset --hard HEAD~1`): the rule matches the command, and every reason the
    /// command is dangerous is one the rule's own command has. A broad rule (`Bash(git:*)`) names none, and a rule
    /// covers only the commands it matches, not the rest of their line.
    func allowsDanger(_ words: [String], reasons: [String], roots: [String]) -> Bool {
        let plain = words.filter { !PermissionPolicy.isRedirection($0) }.joined(separator: " ")
        return rules.contains { r in
            guard r.action == .allow, covers(r.tool, "bash"), let spec = r.specifier, Self.commandMatches(plain, spec) else { return false }
            let named = Set(DangerousCommands.reasons(named: spec, roots: roots))
            return !named.isEmpty && Set(reasons).isSubset(of: named)
        }
    }

    /// Whether a Read deny rule covers this file (for searches, which read files the call doesn't name).
    public func deniesRead(_ url: URL) -> Bool {
        decision(toolName: "read_file", args: ToolArguments(["path": .string(url.path)]))?.action == .deny
    }

    /// Whether any deny rule is about reading files.
    var deniesSomeReads: Bool { rules.contains { $0.action == .deny && $0.specifier != nil && covers($0.tool, "read_file") } }

    func matches(_ rule: PermissionRule, toolName: String, args: ToolArguments,
                 commands: (line: String, parsed: [[String]])? = nil) -> Bool {
        if MCPHub.resourceTools.contains(toolName), rule.tool.hasPrefix("mcp__") { return resourcesMatch(rule, toolName, args) }
        guard covers(rule.tool, toolName) else { return false }
        guard let spec = rule.specifier else { return true }
        if toolName == "bash" {
            guard let command = commands?.line ?? args.string("command") else { return false }
            return Self.commandMatches(command, spec, action: rule.action, parsed: commands?.parsed)
        }
        if rule.tool.hasPrefix("mcp__") { return false }        // MCP rules take no specifier
        if toolName == WebFetchTool.toolName {
            // `WebFetch(domain:example.com)`, as in Claude Code.
            guard spec.lowercased().hasPrefix("domain:") else { return false }
            // An address with no host to check can't be said to be outside a deny or an ask.
            guard let host = WebFetchTool.host(args) else { return rule.action != .allow }
            return Self.host(host, inDomain: String(spec.dropFirst(7)))
        }
        let paths = Self.paths(toolName, args)
        guard !paths.isEmpty else { return false }
        // A call naming several files (a patch): a deny or ask rule matches if it covers any of them, an allow rule
        // only if it covers them all.
        // A deny or ask also goes by the name in the call, which may be a link to a file the rule doesn't name; an allow
        // goes only by the file that would be touched.
        return rule.action == .allow ? paths.allSatisfy { pathMatches($0, pattern: spec) }
            : paths.contains { pathMatches($0, pattern: spec) || pathMatches($0, pattern: spec, asNamed: true) }
    }

    /// The resource tools act for a server: a rule on all of that server covers them. Listing reaches every server, so a
    /// deny or ask on any of them covers it, and an allow on one doesn't. A rule on one tool of a server isn't about them.
    private func resourcesMatch(_ rule: PermissionRule, _ toolName: String, _ args: ToolArguments) -> Bool {
        let named = rule.tool.dropFirst("mcp__".count)
        guard !named.contains("__"), rule.specifier == nil else { return false }
        if let server = args.string("server") { return String(named) == MCPTool.cleanName(server) }
        return rule.action != .allow
    }

    /// The files a call names, however it names them: `path`, Claude Code's `file_path`, inside edit_file's `edits`,
    /// or a patch's file headers. A search with none searches the root.
    static func paths(_ toolName: String, _ args: ToolArguments) -> [String] {
        switch toolName {
        case "apply_patch": return ((try? PatchParser.parse(ApplyPatchTool.text(args))) ?? []).flatMap(\.paths)
        case "edit_file": return (try? EditFileTool.path(args)).map { [$0] } ?? []
        default:
            if let p = args.string("path") ?? args.string("file_path") { return [p] }
            return readers.contains(toolName) ? ["."] : []
        }
    }

    /// The host is the domain or under it (not merely ending in the same letters: notexample.com isn't example.com).
    static func host(_ host: String, inDomain domain: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: .whitespaces)
        return !d.isEmpty && (host == d || host.hasSuffix("." + d))
    }

    /// Whether a rule's tool name covers kurtkode's tool.
    func covers(_ ruleTool: String, _ toolName: String) -> Bool {
        if ruleTool == "*" { return true }
        if ruleTool.hasPrefix("mcp__") {
            // "mcp__server" covers all of a server's tools; "mcp__server__tool" one of them.
            return toolName == ruleTool || toolName.hasPrefix(ruleTool + "__")
        }
        if ruleTool == "Read" { return Self.readers.contains(toolName) }
        if ruleTool == "Edit" { return Self.editors.contains(toolName) }
        return Self.claudeNames[toolName] == ruleTool || toolName == ruleTool
    }

    // MARK: Commands

    /// The simple commands in a command line, each as one normalized string (`ShellSplit`).
    static func subcommands(_ command: String) -> [String] {
        ShellSplit.commands(command).map { $0.joined(separator: " ") }
    }

    /// A deny or ask rule matches when any command in the line does, as written or with its wrappers and path removed
    /// (`env X=1 /bin/rm -rf x` is `rm -rf x`), including commands inside `$( )`, backticks, and `sh -c` scripts. An
    /// allow rule only matches one simple command (so "git status && rm -rf x" isn't allowed by "Bash(git status)").
    /// (A command kurtkode can't read turns a deny or ask rule into a question: `decision`.)
    static func commandMatches(_ command: String, _ spec: String, action: PermissionRule.Action, parsed: [[String]]? = nil) -> Bool {
        let commands = parsed ?? ShellSplit.commands(command)
        if action == .allow {
            let simple = !PermissionPolicy.compoundMarkers.contains { command.contains($0) }
            return simple && commands.count == 1 && commandMatches(commands[0].joined(separator: " "), spec)
        }
        return commands.contains { words in
            ShellSplit.opaqueReason(words) == nil && commandMatches(words.joined(separator: " "), spec) || commandMatches(ShellSplit.unwrap(words).joined(separator: " "), spec)
        }
    }

    static func commandMatches(_ command: String, _ spec: String) -> Bool {
        let c = command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if spec.hasSuffix(":*") {
            let prefix = spec.dropLast(2).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return c == prefix || c.hasPrefix(prefix + " ")
        }
        if spec.contains("*") { return wildcard(spec, matches: c) }
        return c == spec.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `*` matches any run of characters (spaces too).
    static func wildcard(_ pattern: String, matches s: String) -> Bool {
        fnmatch(pattern, s, 0) == 0
    }

    // MARK: Paths

    func pathMatches(_ path: String, pattern: String, asNamed: Bool = false) -> Bool {
        guard let target = absolute(path, asNamed: asNamed) else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = pattern
        if p.hasPrefix("//") { p = String(p.dropFirst()) }
        else if p.hasPrefix("~/") { p = home + String(p.dropFirst()) }
        else if p.hasPrefix("/") { p = (root?.path ?? "") + p }
        else if p.hasPrefix("./") { p = (root?.path ?? "") + "/" + p.dropFirst(2) }    // anchored at the working folder
        else {
            // gitignore-style: a pattern without a slash matches at any depth.
            p = (root?.path ?? "") + (p.contains("/") ? "/" : "/**/") + p
        }
        return Self.glob(p, matches: target) || Self.glob(p + "/**", matches: target)
    }

    /// `path` in full: what it leads to, or with `asNamed` where it is, a link at its end not followed.
    func absolute(_ path: String, asNamed: Bool = false) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : (root ?? URL(fileURLWithPath: "/")).appending(path: expanded)
        guard asNamed else { return Workspace.canonical(url).path }
        return Workspace.canonical(url.deletingLastPathComponent()).appending(path: url.lastPathComponent).path
    }

    /// Glob with `**` (any folders, or none), `*` and `?` (within one path component).
    static func glob(_ pattern: String, matches path: String) -> Bool {
        let p = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let s = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func match(_ i: Int, _ j: Int) -> Bool {
            if i == p.count { return j == s.count }
            if p[i] == "**" {
                for k in j...s.count where match(i + 1, k) { return true }
                return false
            }
            // Like gitignore, `*` matches dotfiles too; and case is ignored, as macOS's disks ignore it.
            guard j < s.count, fnmatch(p[i], s[j], FNM_CASEFOLD) == 0 else { return false }
            return match(i + 1, j + 1)
        }
        return match(0, 0)
    }
}

// MARK: - Loading

/// The `"permissions"` section of a settings file.
public struct PermissionsSection: Codable, Sendable, Hashable {
    public var allow: [String]?
    public var ask: [String]?
    public var deny: [String]?

    public var isEmpty: Bool { (allow ?? []).isEmpty && (ask ?? []).isEmpty && (deny ?? []).isEmpty }

    /// What a project approval covers: every allow rule. Any change asks again.
    public var allowFingerprint: String {
        let text = (allow ?? []).sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    struct File: Codable { var permissions: PermissionsSection? }

    static func load(_ url: URL) throws -> PermissionsSection? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(File.self, from: data).permissions }
        catch { throw MCPError.config("\(url.path) isn't valid: \(error.localizedDescription)") }
    }

    func rules(source: String, includeAllow: Bool) -> [PermissionRule] {
        var out: [PermissionRule] = []
        for (list, action) in [(deny, PermissionRule.Action.deny), (ask, .ask), (includeAllow ? allow : nil, .allow)] {
            out += (list ?? []).compactMap { PermissionRule($0, action: action, source: source) }
        }
        return out
    }
}

/// Which projects' allow rules the user approved (project path + fingerprint of its allow rules).
public struct PermissionApprovals: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    static func key(_ workspace: URL, _ fingerprint: String) -> String { "\(workspace.standardizedFileURL.path)|\(fingerprint)" }

    public func isApproved(_ fingerprint: String, workspace: URL) -> Bool { load().contains(Self.key(workspace, fingerprint)) }

    public func approve(_ fingerprint: String, workspace: URL) throws {
        var set = load()
        set.insert(Self.key(workspace, fingerprint))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(set.sorted()).write(to: fileURL, options: .atomic)
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }
}

extension PermissionRules {
    /// The files rules come from: the user's (trusted), then the project's (its allow rules need approval once: a
    /// cloned repository could otherwise grant itself commands; its deny and ask rules only restrict, so they apply).
    public static func userFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appending(path: ".kurtkode/settings.json"), home.appending(path: ".claude/settings.json")]
    }

    public static func projectFiles(_ root: URL) -> [URL] {
        [".kurtkode/settings.json", ".kurtkode/settings.local.json", ".claude/settings.json", ".claude/settings.local.json"]
            .map { root.appending(path: $0) }
    }

    /// The rules for a run in `root`, the project's allow rules waiting for approval (fingerprint and the rules, for the
    /// frontend to ask about), and a problem reading a file.
    public static func load(root: URL?, approvals: PermissionApprovals,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> (rules: PermissionRules, pending: (fingerprint: String, rules: [String])?, problem: String?) {
        var rules: [PermissionRule] = []
        var problem: String?
        for url in userFiles(home: home) {
            do { if let s = try PermissionsSection.load(url) { rules += s.rules(source: "~/" + url.path.replacingOccurrences(of: home.path + "/", with: ""), includeAllow: true) } }
            catch { problem = error.localizedDescription }
        }
        var pending: (String, [String])?
        if let root {
            var projectAllow: [(rule: String, file: String)] = []
            for url in projectFiles(root) {
                do {
                    guard let s = try PermissionsSection.load(url) else { continue }
                    let name = String(url.path.dropFirst(root.path.count + 1))
                    rules += s.rules(source: name, includeAllow: false)
                    projectAllow += (s.allow ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        .map { ($0, name) }
                } catch { problem = error.localizedDescription }
            }
            if !projectAllow.isEmpty {
                let section = PermissionsSection(allow: projectAllow.map(\.rule))
                if approvals.isApproved(section.allowFingerprint, workspace: root) {
                    for entry in projectAllow {
                        if let r = PermissionRule(entry.rule, action: .allow, source: entry.file) { rules.append(r) }
                    }
                } else {
                    pending = (section.allowFingerprint, section.allow ?? [])
                }
            }
        }
        return (PermissionRules(rules: rules, root: root), pending, problem)
    }
}
