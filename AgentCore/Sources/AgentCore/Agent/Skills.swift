import Foundation

/// Agent Skills: folders with a `SKILL.md` (front matter `name` and `description`, then instructions), the format
/// Claude Code and opencode share. Only each skill's name and description sit in the prompt (in the `skill` tool's
/// description); the model loads a skill's instructions when it needs them, and may then read the skill's other
/// files (scripts, references), read-only, even when the skill lives outside the project.
public struct Skill: Sendable, Hashable, Identifiable {
    public var name: String
    public var description: String
    public var folder: URL
    /// False when its front matter says the model shouldn't pick it by itself (`disable-model-invocation: true`, or
    /// opencode's `autoinvoke: false`): it's left out of the tool's list but loads by exact name (and as `/name`).
    public var modelInvocable: Bool
    public var id: String { name }

    public var file: URL { folder.appending(path: "SKILL.md") }
}

public enum Skills {
    /// Where skills live, the project's first (a project's skill replaces a user's of the same name): kurtkode's own
    /// folders, then Claude Code's and the shared `.agents` ones, then kurtkode's built-in skills (`builtin`, when
    /// they're on), so a project or a user can replace any of them by name.
    public static func directories(root: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                   builtin: URL? = nil) -> [URL] {
        let names = [".kurtkode/skills", ".claude/skills", ".agents/skills"]
        return (root.map { r in names.map { r.appending(path: $0) } } ?? []) + names.map { home.appending(path: $0) }
            + (builtin.map { [$0] } ?? [])
    }

    /// The skills kurtkode ships (`BuiltinSkills`, the library in skilllib/): in the app's resources, beside the
    /// command-line binary, or in the sources (tests, `swift run`). Found the way the prompt templates are.
    public static let builtinFolder: URL? = PromptTemplates.resourceFolder("BuiltinSkills", marker: "verify-before-done/SKILL.md")

    /// The built-in folder when the setting allows it, for `load`'s `builtin`.
    public static func builtin(_ enabled: Bool) -> URL? { enabled ? builtinFolder : nil }

    /// Every skill found, the first of each name winning, sorted by name.
    public static func load(root: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            builtin: URL? = nil) -> [Skill] {
        var seen = Set<String>()
        var out: [Skill] = []
        for dir in directories(root: root, home: home, builtin: builtin) {
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                        options: [.skipsHiddenFiles])) ?? []
            for folder in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let skill = read(folder), seen.insert(skill.name).inserted else { continue }
                out.append(skill)
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    /// A skill folder's `SKILL.md`, if it has one with a description. The name is the front matter's, else the folder's.
    static func read(_ folder: URL) -> Skill? {
        let file = folder.appending(path: "SKILL.md")
        guard let data = try? Data(contentsOf: file), data.count < 200_000 else { return nil }
        let (meta, _) = SlashCommands.frontMatter(String(decoding: data, as: UTF8.self))
        guard let description = meta["description"].map(unquote), !description.isEmpty else { return nil }
        let name = meta["name"].map(unquote).flatMap { $0.isEmpty ? nil : $0 } ?? folder.lastPathComponent
        let off = ["true", "yes"].contains(meta["disable-model-invocation"]?.lowercased() ?? "")
            || ["false", "no"].contains((meta["autoinvoke"] ?? meta["opencode/autoinvoke"])?.lowercased() ?? "")
        return Skill(name: name.lowercased(), description: description, folder: Workspace.canonical(folder), modelInvocable: !off)
    }

    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let f = t.first, f == t.last, f == "\"" || f == "'" else { return t }
        return String(t.dropFirst().dropLast())
    }

    /// What `/skills` shows: each skill, where it's from, and whether the model picks it by itself.
    public static func listing(root: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               builtin: URL? = nil) -> String {
        let skills = load(root: root, home: home, builtin: builtin)
        guard !skills.isEmpty else {
            return "No skills. A skill is a folder with a SKILL.md (front matter `name` and `description`, then instructions) "
                + "in .kurtkode/skills, .claude/skills, or .agents/skills, in the project or your home folder."
        }
        let homePath = home.standardizedFileURL.path
        let builtinPath = builtin.map { Workspace.canonical($0).path + "/" }
        return skills.map { s in
            let path = builtinPath.map { s.folder.path.hasPrefix($0) } == true ? "(built-in)"
                : s.folder.path.hasPrefix(homePath + "/") ? "~" + s.folder.path.dropFirst(homePath.count) : s.folder.path
            return "/\(s.name)  \(s.description)\n    \(path)\(s.modelInvocable ? "" : "  (only when asked for)")"
        }.joined(separator: "\n")
    }

    /// The skills as `/name` commands: each loads its skill, then follows it with what was typed after the name.
    public static func commands(_ skills: [Skill]) -> [SlashCommand] {
        skills.compactMap { s in
            guard SlashCommands.parse("/" + s.name)?.name == s.name else { return nil }
            return SlashCommand(name: s.name, description: "Skill: " + s.description.prefix(70), argumentHint: "[request]",
                                kind: .custom(template: "Load the skill \"\(s.name)\" with the skill tool and follow it.\n\n$ARGUMENTS",
                                              source: s.file))
        }
    }
}

/// Loads a skill's instructions into the conversation.
public struct SkillTool: Tool {
    public let skills: [Skill]
    public let name = "skill"
    public let risk = ToolRisk.read

    public init(skills: [Skill]) { self.skills = skills }

    public var description: String {
        let listed = skills.filter(\.modelInvocable)
        return """
            Load a skill: instructions for a kind of task, with any scripts or reference files it brings. When a task \
            matches a skill's description, load it first and follow it. Its files can then be read by absolute path.

            <available_skills>
            \(listed.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))
            </available_skills>
            """
    }

    public var parameters: JSONValue {
        ["type": "object",
         "properties": ["name": ["type": "string", "description": "The skill's name, as listed."]],
         "required": ["name"]]
    }

    public func summary(_ args: ToolArguments) -> String { "Load skill \(args.string("name") ?? "?")" }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let wanted = (args.string("name") ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard let skill = skills.first(where: { $0.name == wanted }) else {
            throw ToolFailure("No skill named \"\(wanted)\". Available: \(skills.filter(\.modelInvocable).map(\.name).joined(separator: ", ")).")
        }
        guard let text = Self.instructions(skill) else { throw ToolFailure("\(skill.file.path) can't be read.") }
        let (capped, cut) = capOutput(text, maxBytes: max(context.maxOutputBytes, 24_000), hint: "The skill is longer than shown.")
        return ToolOutput(text: capped, truncated: cut)
    }

    /// What loading `skill` gives the model: its instructions, its folder and its other files. Nil if SKILL.md
    /// can't be read. The skill router (`SkillRouter`) sends the same text.
    public static func instructions(_ skill: Skill) -> String? {
        guard let data = try? Data(contentsOf: skill.file) else { return nil }
        let (_, body) = SlashCommands.frontMatter(String(decoding: data, as: UTF8.self))
        let others = ((try? FileManager.default.subpathsOfDirectory(atPath: skill.folder.path)) ?? [])
            .filter { $0 != "SKILL.md" && !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
            .sorted().prefix(40)
        var text = "Skill \(skill.name) (\(skill.folder.path)):\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !others.isEmpty {
            text += "\n\nIts other files (read them by absolute path when the instructions call for them):\n"
                + others.map { "- " + skill.folder.appending(path: $0).path }.joined(separator: "\n")
        }
        return text
    }
}
