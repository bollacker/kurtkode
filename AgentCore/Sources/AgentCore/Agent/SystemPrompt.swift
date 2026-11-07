import Foundation

/// How the system prompt coaches the model: the name of a `style-<name>.md` template (PromptTemplates). kurtkode
/// ships two. Small local models need step-by-step working rules ("detailed"); frontier models do worse with prompts
/// that over-constrain them (Anthropic's guidance for its newest models), so they get "lean". Users add their own.
public struct PromptStyle: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    /// Nil unless `rawValue` is a template name (lowercase letters, digits, hyphens).
    public init?(rawValue: String) {
        guard PromptTemplates.isValidName(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public static let detailed = PromptStyle(rawValue: "detailed")!
    public static let lean = PromptStyle(rawValue: "lean")!

    /// Lean for Claude and Gemini, detailed for everything else.
    public static func automatic(for api: WireAPI) -> PromptStyle { api == .openai ? .detailed : .lean }
}

/// Builds the agent's system prompt: base instructions, environment, and project instruction files (D11).
public struct SystemPromptBuilder: Sendable {
    public var workspace: Workspace
    public var tools: [any Tool]
    public var mode: PermissionMode
    /// Extra text from Settings, appended last.
    public var userPrompt: String
    /// `~/.kurtkode/AGENTS.md`: personal instructions for every project.
    public var globalInstructions: URL
    /// Where the user's files are (`~/.claude/CLAUDE.md`, the memory folder): the home folder, but for tests.
    public var home = FileManager.default.homeDirectoryForCurrentUser
    /// Read the user's files, parent folders' and the project's memory (B6); the eval turns it off.
    public var userFiles = true
    /// The command sandbox, when commands run in one.
    public var sandbox: SandboxPolicy?
    /// A chat's working folder rather than a project: the prompt says so.
    public var isChat = false
    /// The task tool is offered: the prompt says when to use it (`delegation.md`).
    public var subagents = false
    /// The skill tool is offered: the prompt says to check the skills before starting a task (`skills.md`).
    public var skills = false
    public var style: PromptStyle = .detailed
    /// Where the prompt's text comes from (project and user overrides, then the defaults).
    public var templates: PromptTemplates

    public init(workspace: Workspace, tools: [any Tool], mode: PermissionMode = .ask, userPrompt: String = "",
                globalInstructions: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kurtkode/AGENTS.md")) {
        self.workspace = workspace
        self.tools = tools
        self.mode = mode
        self.userPrompt = userPrompt
        self.globalInstructions = globalInstructions
        self.templates = .standard(project: workspace.root)
    }

    /// Instruction files in load order, with their text (`InstructionFiles`). Missing files are skipped.
    public func instructionFiles() -> [(label: String, text: String)] {
        var files = InstructionFiles(root: workspace.root, home: home, global: globalInstructions)
        files.userFiles = userFiles
        return files.load().map { ($0.label, $0.text) }
    }

    /// The style used: the one asked for, or detailed when no template has its name.
    public var resolvedStyle: PromptStyle { templates.has(style: style) ? style : .detailed }

    /// The templates this prompt is made from.
    public var templateNames: [String] {
        PromptTemplates.shared + (subagents ? ["delegation"] : []) + (skills ? ["skills"] : []) + ["style-" + resolvedStyle.rawValue]
    }

    /// What the templates can test and show (SYSTEM_PROMPT.md lists them). A flag is "1" when set, else "".
    public var templateValues: [String: String] {
        func flag(_ b: Bool) -> String { b ? "1" : "" }
        return [
            "chat": flag(isChat),
            "other_folders": flag(!workspace.folders.isEmpty),
            "writable_folders": flag(workspace.folders.contains(where: \.writable)),
            "read_only": flag(mode == .plan || !tools.contains(where: { $0.risk != .read })),
            "plan": flag(mode == .plan),
            "full_auto": flag(mode == .fullAuto),
            "sandbox": flag(sandbox != nil),
            "network": flag(sandbox?.allowNetwork ?? false),
            "mode": mode.rawValue,
            "style": resolvedStyle.rawValue,
            "lean": flag(resolvedStyle == .lean),
            "subagents": flag(subagents),
            "skills": flag(skills),
            "root": workspace.root.path,
            "tools": tools.map(\.name).joined(separator: ", "),
        ]
    }

    /// The templated part of the prompt: the style's text, with the intro and the mode's rules in it.
    public func head() -> String {
        var values = templateValues
        values["intro"] = templates.render("intro", values)
        values["mode_rules"] = templates.render("mode", values)
        if subagents { values["delegation"] = templates.render("delegation", values) }
        if skills { values["skills_note"] = templates.render("skills", values) }
        return templates.render("style-" + resolvedStyle.rawValue, values)
    }

    public func build(now: Date = Date()) async -> String { await buildWithFacts(now: now).text }

    /// The heading of the prompt's last section, which holds what differs from one run to the next: the project root
    /// (each eval run and worktree has its own) and the `facts`. Everything before it is the same for every run with
    /// the same tools, instructions and settings, so a provider's prefix cache can serve it across runs; the Claude
    /// wire formats put a cache breakpoint just before it (`splitVolatile`). Before the cost audit (F4) the
    /// environment came right after the working rules, and Haiku read a cache across runs 0 times in 480.
    public static let volatileHeading = "Current environment (changes between runs):"
    static let volatileMarker = "\n\n" + volatileHeading + "\n"

    /// A prompt split where its changing last section starts: `stable + volatile == text`; `volatile` is empty when
    /// there's no such section, and starts with the blank line before the heading.
    public static func splitVolatile(_ text: String) -> (stable: String, volatile: String) {
        guard let r = text.range(of: volatileMarker), r.lowerBound > text.startIndex else { return (text, "") }
        return (String(text[..<r.lowerBound]), String(text[r.lowerBound...]))
    }

    /// `text` with `extra` added at the end of its stable part (before the changing section, or at the end when there
    /// is none): for what is the same on every run, such as a model's addendum or a subagent's role.
    public static func insertingStable(_ extra: String, into text: String) -> String {
        guard !extra.isEmpty else { return text }
        guard !text.isEmpty else { return extra }
        let (stable, volatile) = splitVolatile(text)
        return stable + "\n\n" + extra + volatile
    }

    /// What the prompt says that changes by itself (the date, the git status), in the words it uses. They come last,
    /// in the changing section, so a session resumed later can keep its prompt (and the server's cache of it) and be
    /// told the new ones in a message (`FrozenSystemPrompt`).
    public func facts(now: Date = Date()) async -> String {
        var s = "- Date: \(now.formatted(date: .complete, time: .omitted))"
        if let git = await workspace.gitSummary() { s += "\n" + git }
        return s
    }

    /// The prompt, and its `facts` as they appear in it.
    public func buildWithFacts(now: Date = Date()) async -> (text: String, facts: String) {
        var parts: [String] = []
        let rules = head()
        if !rules.isEmpty { parts.append(rules) }

        var env = "Environment:\n- Platform: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        for f in workspace.folders {
            env += "\n- Other folder: \(f.path) (\(f.writable ? "read and write" : "read-only"))"
        }
        parts.append(env)

        if !tools.isEmpty {
            parts.append("Tools available: " + tools.map(\.name).joined(separator: ", ") + ".")
        }

        for file in instructionFiles() {
            parts.append("Instructions from \(file.label):\n\n\(file.text)")
        }
        let extra = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { parts.append(extra) }

        // Last: what changes between runs (see `volatileHeading`).
        let facts = await facts(now: now)
        parts.append(Self.volatileHeading + "\n- \(isChat ? "Working folder" : "Project root"): \(workspace.root.path)\n" + facts)
        return (parts.joined(separator: "\n\n"), facts)
    }
}
