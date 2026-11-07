import Foundation

/// A command typed as `/name arguments` in the composer: built into the app, or a Markdown prompt template.
public struct SlashCommand: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case builtIn
        /// A prompt template from a `.md` file; sent to the model after expansion.
        case custom(template: String, source: URL)
    }

    public var name: String
    public var description: String
    /// Shown after the name while typing, e.g. "[focus]".
    public var argumentHint: String
    public var kind: Kind
    public var id: String { name }

    public init(name: String, description: String, argumentHint: String = "", kind: Kind = .builtIn) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.kind = kind
    }

    public var isBuiltIn: Bool { kind == .builtIn }
    /// Built-ins that do their work without arguments run as soon as they're picked.
    public var runsWithoutArguments: Bool { argumentHint.isEmpty || argumentHint.hasPrefix("[") }
}

public enum SlashCommands {
    public static let builtIns: [SlashCommand] = [
        SlashCommand(name: "help", description: "List the commands"),
        SlashCommand(name: "clear", description: "Start a new chat in this project, with the same model"),
        SlashCommand(name: "compact", description: "Summarize the conversation to free up context", argumentHint: "[what to focus on]"),
        SlashCommand(name: "context", description: "Show how much of the context is in use"),
        SlashCommand(name: "agents", description: "List this session's subagent runs"),
        SlashCommand(name: "skills", description: "List the skills the agent can load"),
        SlashCommand(name: "model", description: "Switch the model for the next reply", argumentHint: "<name>"),
        SlashCommand(name: "mode", description: "Set the permission mode", argumentHint: "<ask | edits | plan | auto>"),
        SlashCommand(name: "init", description: "Have the agent write AGENTS.md for this project"),
        SlashCommand(name: "retry", description: "Run the last reply again"),
        SlashCommand(name: "diff", description: "Show what the latest run changed (or the whole session, what's uncommitted, or the branch)", argumentHint: "[session | uncommitted | branch]"),
        SlashCommand(name: "escalate", description: "Hand the request to the next tier's model in the pool, with this run's changes", argumentHint: "[why]"),
        SlashCommand(name: "review", description: "Have another vendor's model review the latest change (or the session's)", argumentHint: "[session] [-m model]"),
        SlashCommand(name: "rewind", description: "Go back to before a request: files, conversation, or both", argumentHint: "[N] [files | chat]"),
        SlashCommand(name: "btw", description: "Ask a quick question on the side; it doesn't join the conversation", argumentHint: "<question>"),
        SlashCommand(name: "rename", description: "Rename this chat", argumentHint: "<title>"),
        SlashCommand(name: "memory", description: "Show this project's memory (\"# text\" adds to it)"),
        SlashCommand(name: "good", description: "Mark the last reply as right (kept to choose models later)", argumentHint: "[note]"),
        SlashCommand(name: "bad", description: "Mark the last reply as wrong (kept to choose models later)", argumentHint: "[note]"),
    ]

    /// The prompt `/init` sends (D11: kurtkode's instruction file is AGENTS.md).
    public static let initPrompt = """
        Write an AGENTS.md file at the project root for coding agents that will work on this project later. \
        First read what matters: the README, build and package files, and the main source files. Then write \
        concisely (under about 60 lines): what the project is, how it's laid out, how to build, test, and run \
        it (exact commands), and conventions to follow. Only state what you have verified by reading files. \
        If AGENTS.md already exists, improve it instead of replacing what's still true.
        """

    /// Splits `/name arguments`. Nil when the text isn't a command: the name must be letters, digits, `-`,
    /// `_`, or `:` and end at whitespace, so a message that starts with a path (/usr/bin …) is a message.
    public static func parse(_ text: String) -> (name: String, arguments: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/") else { return nil }
        let body = t.dropFirst()
        let name = body.prefix { !$0.isWhitespace }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || "-_:".contains($0) }) else { return nil }
        let args = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.lowercased(), args)
    }

    /// Where custom commands live, in precedence order: the project's, then the user's. `.claude/commands`
    /// is read too, so existing Claude Code commands work.
    public static func directories(workspace: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var dirs: [URL] = []
        if let workspace {
            dirs += [workspace.appending(path: ".kurtkode/commands"), workspace.appending(path: ".claude/commands")]
        }
        return dirs + [home.appending(path: ".kurtkode/commands"), home.appending(path: ".claude/commands")]
    }

    /// Built-ins, then custom commands, then skills (a custom command can't replace a built-in, nor a skill a
    /// command; the first file with a name wins).
    /// Built-ins added in Phase 3: a user's own command of the same name (Claude Code users often have a `review.md`)
    /// keeps working and takes the name; the others can't be replaced.
    static let yielding: Set<String> = ["diff", "rewind", "review", "escalate"]

    public static func all(workspace: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           builtinSkills: URL? = nil) -> [SlashCommand] {
        let custom = directories(workspace: workspace, home: home).flatMap(loadCustom)
        let taken = Set(custom.map(\.name)).intersection(yielding)
        var out = builtIns.filter { !taken.contains($0.name) }
        var seen = Set(out.map(\.name))
        for c in custom where seen.insert(c.name).inserted { out.append(c) }
        for c in Skills.commands(Skills.load(root: workspace, home: home, builtin: builtinSkills)) where seen.insert(c.name).inserted {
            out.append(c)
        }
        return out
    }

    /// `.md` files under `dir`; a subfolder becomes a namespace (`frontend/component.md` → `frontend:component`).
    static func loadCustom(from dir: URL) -> [SlashCommand] {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var out: [SlashCommand] = []
        let base = dir.standardizedFileURL.path
        for case let url as URL in walker where url.pathExtension.lowercased() == "md" {
            guard let data = try? Data(contentsOf: url), data.count < 100_000 else { continue }
            let relative = url.standardizedFileURL.deletingPathExtension().path.dropFirst(base.count + 1)
            let name = relative.split(separator: "/").joined(separator: ":").lowercased()
            guard parse("/" + name)?.name == name else { continue }
            let (meta, template) = frontMatter(String(decoding: data, as: UTF8.self))
            let firstLine = template.split(separator: "\n").first.map(String.init) ?? ""
            out.append(SlashCommand(name: name,
                                    description: meta["description"] ?? String(firstLine.prefix(80)),
                                    argumentHint: meta["argument-hint"] ?? "",
                                    kind: .custom(template: template, source: url)))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// `---` front matter as simple `key: value` lines, and the text after it.
    static func frontMatter(_ text: String) -> ([String: String], String) {
        // Files written on Windows (CRLF) or saved with a byte-order mark read the same.
        var text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var meta: [String: String] = [:]
        // A value may go on over indented lines (`description: >` and the like, or a long plain value).
        var key: String?
        var literal = false
        var block = false
        for line in lines[1..<end] {
            // A blank line inside a block value (`description: |`) is part of it.
            if let k = key, block, line.trimmingCharacters(in: .whitespaces).isEmpty {
                if literal, let v = meta[k], !v.isEmpty { meta[k] = v + "\n" }
                continue
            }
            if let k = key, line.first?.isWhitespace == true {
                let more = line.trimmingCharacters(in: .whitespaces)
                let had = meta[k] ?? ""
                meta[k] = had.isEmpty ? more : had + (literal ? "\n" : " ") + more
                continue
            }
            key = nil
            guard let colon = line.firstIndex(of: ":") else { continue }
            let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
            literal = value.hasPrefix("|")
            block = [">", ">-", ">+", "|", "|-", "|+"].contains(value)
            if block { value = "" }
            meta[k] = value
            key = k
        }
        return (meta, lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Fills in a template: `$ARGUMENTS` is everything typed after the name; `$1` … `$9` are its words.
    /// A template that uses neither gets the arguments appended, so they aren't lost.
    /// One pass over the template, so nothing in the arguments is itself substituted ("price is $1 off" stays as typed).
    public static func expand(_ template: String, arguments: String) -> String {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
        var out = ""
        var used = false
        var rest = template[...]
        while let dollar = rest.firstIndex(of: "$") {
            out += rest[..<dollar]
            let after = rest[rest.index(after: dollar)...]
            if after.hasPrefix("ARGUMENTS") {
                out += arguments
                rest = after.dropFirst("ARGUMENTS".count)
                used = true
            } else if let d = after.first, let n = d.wholeNumberValue, n >= 1 {
                out += n <= words.count ? words[n - 1] : ""
                rest = after.dropFirst()
                used = true
            } else {
                out += "$"
                rest = after
            }
        }
        out += rest
        if !used, !arguments.isEmpty { out += "\n\n" + arguments }
        return out
    }

    /// Commands whose name starts with what's typed after the slash (then those that contain it).
    public static func matching(_ typed: String, in commands: [SlashCommand]) -> [SlashCommand] {
        let q = typed.lowercased()
        guard !q.isEmpty else { return commands }
        let starts = commands.filter { $0.name.hasPrefix(q) }
        let contains = commands.filter { !$0.name.hasPrefix(q) && $0.name.contains(q) }
        return starts + contains
    }
}
