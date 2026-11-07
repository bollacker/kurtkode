import Foundation

/// The instruction files a session's prompt carries (B6), general to specific: the user's (`~/.kurtkode/AGENTS.md`,
/// Claude Code's `~/.claude/CLAUDE.md`), the project's parent folders' (a monorepo's root), the project's own
/// (`AGENTS.md`, `CLAUDE.md`, `.claude/CLAUDE.md`, the personal `CLAUDE.local.md`), then the project's memory. A file
/// that says the same as one before it loads once; `@path` lines pull in other files (as Claude Code's imports do).
public struct InstructionFiles: Sendable {
    public struct File: Sendable, Hashable {
        public var label: String
        public var text: String
        public var url: URL
    }

    public var root: URL
    public var home: URL
    /// `~/.kurtkode/AGENTS.md`, or another file in its place (tests, the eval's ".none").
    public var global: URL
    /// The user's files, parent folders' and memory are read (the eval turns them off, so runs compare across machines).
    public var userFiles = true

    static let maxFileBytes = 32_000
    static let maxTotalBytes = 96_000
    static let maxImportDepth = 5

    public init(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, global: URL? = nil) {
        self.root = root
        self.home = home
        self.global = global ?? home.appending(path: ".kurtkode/AGENTS.md")
    }

    /// The files to read, labeled, in order (whether or not they exist).
    var candidates: [(String, URL)] {
        var out: [(String, URL)] = [("~/.kurtkode/AGENTS.md (your personal instructions)", global)]
        if userFiles {
            out.append(("~/.claude/CLAUDE.md (your personal instructions)", home.appending(path: ".claude/CLAUDE.md")))
            // Parent folders, outermost first, up to (not including) the home folder.
            let homePath = Workspace.canonical(home).path
            for d in parentFolders.reversed() {
                let shown = d.path.hasPrefix(homePath + "/") ? "~" + d.path.dropFirst(homePath.count) : d.path
                for name in ["AGENTS.md", "CLAUDE.md"] { out.append(("\(shown)/\(name) (a parent folder's instructions)", d.appending(path: name))) }
            }
        }
        out += [("AGENTS.md (project instructions)", root.appending(path: "AGENTS.md")),
                ("CLAUDE.md (project instructions)", root.appending(path: "CLAUDE.md")),
                (".claude/CLAUDE.md (project instructions)", root.appending(path: ".claude/CLAUDE.md"))]
        if userFiles {
            out.append(("CLAUDE.local.md (your personal instructions for this project)", root.appending(path: "CLAUDE.local.md")))
        }
        return out
    }

    /// The project's parent folders between it and the home folder (none for a project outside home: /tmp or
    /// /Users/Shared are anyone's to write in), innermost first, 8 at most.
    var parentFolders: [URL] {
        let homePath = Workspace.canonical(home).path
        var dir = Workspace.canonical(root).deletingLastPathComponent()
        guard dir.path.hasPrefix(homePath + "/") || dir.path == homePath else { return [] }
        var dirs: [URL] = []
        while dir.path.hasPrefix(homePath + "/"), dirs.count < 8 {
            dirs.append(dir)
            dir = dir.deletingLastPathComponent()
        }
        return dirs
    }

    /// Where an instruction file or an import may come from, once links are resolved: the project, its parent folders,
    /// and the user's ~/.claude and ~/.kurtkode (never ~/.ssh and the like), and never a withheld file (`.env`, keys,
    /// credentials). Instructions go to whatever model the session uses, remote ones included.
    func allowed(_ url: URL) -> Bool {
        let real = Workspace.canonical(url)
        if WithheldFiles(patterns: WithheldFiles.defaults, host: "").matches(real) { return false }
        let homePath = Workspace.canonical(home).path
        let bases = [Workspace.canonical(root).path] + parentFolders.map(\.path)
            + [homePath + "/.claude", homePath + "/.kurtkode", Workspace.canonical(global.deletingLastPathComponent()).path]
        return bases.contains { real.path == $0 || real.path.hasPrefix($0 + "/") }
    }

    /// The files' texts, deduplicated, with their imports after each, within the size limits.
    public func load() -> [File] {
        var out: [File] = []
        var seenPaths = Set<String>()
        var seenTexts: [String: Int] = [:]          // normalized text → index in out
        var total = 0
        func add(_ label: String, _ url: URL, depth: Int) {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard total < Self.maxTotalBytes, !seenPaths.contains(path), allowed(url), let data = try? Data(contentsOf: url),
                  !data.isEmpty, !looksBinary(data) else { return }
            seenPaths.insert(path)
            let room = min(Self.maxFileBytes, Self.maxTotalBytes - total)
            var text = String(decoding: data.prefix(room), as: UTF8.self)
            if data.count > room { text += "\n[…truncated at \(room / 1000) KB]" }
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = seenTexts[key] {
                out[i].label += ", the same as \(label.components(separatedBy: " (").first ?? label)"
                return
            }
            seenTexts[key] = out.count
            out.append(File(label: label, text: text, url: url))
            total += text.utf8.count
            guard depth < Self.maxImportDepth else { return }
            for imported in Self.imports(in: text, from: url.deletingLastPathComponent(), home: home) {
                let name = label.components(separatedBy: " (").first ?? label
                add("\(Self.shown(imported, root: root, home: home)) (imported by \(name))", imported, depth: depth + 1)
            }
        }
        for (label, url) in candidates { add(label, url, depth: 0) }
        if userFiles, let memory = Memory.text(root: root, home: home) {
            out.append(File(label: "memory (facts kept for this project: saved with remember, or noted by the user)",
                            text: memory, url: Memory.file(root: root, home: home)))
        }
        return out
    }

    /// The files `@path` lines name, relative to `dir` (or `~`, or absolute), that exist; not inside code.
    static func imports(in text: String, from dir: URL, home: URL) -> [URL] {
        var out: [URL] = []
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            guard !inFence else { continue }
            // Code spans hold examples, not imports.
            let plain = line.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
            for m in plain.matches(of: /(?:^|\s)@([~.\/A-Za-z0-9_][^\s,;:)]*)/) {
                var p = String(m.1)
                while let last = p.last, ".!?".contains(last) { p.removeLast() }
                guard !p.isEmpty else { continue }
                let url = p.hasPrefix("~/") ? home.appending(path: String(p.dropFirst(2)))
                    : p.hasPrefix("/") ? URL(fileURLWithPath: p) : dir.appending(path: p)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue { out.append(url) }
            }
        }
        return out
    }

    static func shown(_ url: URL, root: URL, home: URL) -> String {
        let p = url.standardizedFileURL.path, r = root.standardizedFileURL.path, h = home.standardizedFileURL.path
        if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
        return p
    }
}

/// Instruction files in the project's subfolders (B6): `pkg/AGENTS.md` applies to the files under `pkg/`, so it's
/// sent the first time the model reads or changes something there, rather than in every prompt. The rules go in a
/// message of their own after the turn's results (in a tool result, trimming cut them); a change to a file there is
/// held back until they've been seen. One per run, seeded from the history and again after a compaction: rules a
/// summary dropped are sent again on the next touch.
final class NestedInstructions: @unchecked Sendable {
    private let lock = NSLock()
    private var sent = Set<String>()
    let root: URL

    static let marker = "[kurtkode: instructions from "
    static let names = ["AGENTS.md", "CLAUDE.md"]
    /// The tools whose paths count as touching a folder.
    static let tools: Set<String> = ["read_file", "edit_file", "write_file", "list_dir", "apply_patch"]
    static let maxFileBytes = 8_000
    static let maxTurnBytes = 16_000
    /// Folders whose rule files are another project's (dependencies, vendored code): never sent.
    static let skipped: Set<String> = Workspace.defaultIgnores.union(["vendor", "third_party", "site-packages", "Carthage", "bower_components"])

    init(root: URL, history: [ChatMessage]) {
        self.root = Workspace.canonical(root)
        reseed(from: history)
    }

    /// What the messages show was sent: the rule messages themselves, not text that only quotes the marker.
    func reseed(from messages: [ChatMessage]) {
        var found = Set<String>()
        for m in messages where m.role == .user && m.content.hasPrefix(Self.marker) {
            for match in m.content.matches(of: /\[kurtkode: instructions from (.+?), which apply to files under\b/) {
                found.insert(String(match.1))
            }
        }
        lock.withLock { sent = found }
    }

    /// The paths a call touches.
    static func paths(_ call: ToolCall) -> [String] {
        guard tools.contains(call.name), let args = try? ToolArguments(json: call.arguments) else { return [] }
        switch call.name {
        case "apply_patch": return (try? PatchParser.parse(ApplyPatchTool.text(args)))?.flatMap(\.paths) ?? []
        case "edit_file": return (try? EditFileTool.path(args)).map { [$0] } ?? []
        default: return [args.string("path") ?? args.string("file_path")].compactMap { $0 }
        }
    }

    /// The rule files over the folders `call` touches that haven't been sent, as (relative path, folder, text).
    func pending(for call: ToolCall, workspace: Workspace) -> [(file: String, folder: String, text: String)] {
        var out: [(String, String, String)] = []
        let fm = FileManager.default
        for p in Self.paths(call) where !p.isEmpty {
            guard let url = try? workspace.resolve(p), workspace.contains(url) else { continue }
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            var dir = Workspace.canonical(exists && isDir.boolValue ? url : url.deletingLastPathComponent())
            var chain: [URL] = []
            while dir.path.hasPrefix(root.path + "/") {
                chain.append(dir)
                dir = dir.deletingLastPathComponent()
            }
            for d in chain.reversed() {
                // A dependency's or another repository's folder (and what's under it) has rules for its own makers.
                if Self.skipped.contains(d.lastPathComponent) || d.lastPathComponent.hasPrefix(".")
                    || fm.fileExists(atPath: d.appending(path: ".git").path) { break }
                for name in Self.names {
                    let file = d.appending(path: name)
                    let rel = String(file.path.dropFirst(root.path.count + 1))
                    guard !out.contains(where: { $0.0 == rel }), lock.withLock({ !sent.contains(rel) }) else { continue }
                    // A link must stay in the project and not be a withheld file.
                    let real = Workspace.canonical(file)
                    guard real.path.hasPrefix(root.path + "/"), !WithheldFiles(patterns: WithheldFiles.defaults, host: "").matches(real),
                          let data = try? Data(contentsOf: file), !data.isEmpty, !looksBinary(data) else { continue }
                    var text = String(decoding: data.prefix(Self.maxFileBytes), as: UTF8.self)
                    if data.count > Self.maxFileBytes { text += "\n[…truncated at \(Self.maxFileBytes / 1000) KB; read_file \(rel) for the rest]" }
                    out.append((rel, String(d.path.dropFirst(root.path.count + 1)) + "/", text))
                }
            }
        }
        return out
    }

    /// The pending rules for `call`, marked sent and rendered (within the turn's room), or nil.
    func take(for call: ToolCall, workspace: Workspace, room: Int = maxTurnBytes) -> (files: [String], text: String)? {
        var used = 0
        var files: [String] = []
        var parts: [String] = []
        for (file, folder, text) in pending(for: call, workspace: workspace) {
            let part = "\(Self.marker)\(file), which apply to files under \(folder):]\n" + text
            guard used + part.utf8.count <= room else { break }
            used += part.utf8.count
            lock.withLock { _ = sent.insert(file) }
            files.append(file)
            parts.append(part)
        }
        return parts.isEmpty ? nil : (files, parts.joined(separator: "\n\n"))
    }
}

/// What the model (`remember`) and the user (`#` notes, `/memory`) keep for later sessions on a project (B6): one
/// Markdown file per project, `~/.kurtkode/memory/<project>/MEMORY.md`, loaded into the prompt after the instructions.
public enum Memory {
    public static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".kurtkode/memory")
    }

    public static func file(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        folder(home: home).appending(path: SessionStore.projectKey(for: Workspace.canonical(root).path)).appending(path: "MEMORY.md")
    }

    static let maxBytes = 16_000

    /// The project's memory, or nil when there's none.
    public static func text(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard let data = try? Data(contentsOf: file(root: root, home: home)), !data.isEmpty else { return nil }
        // The newest facts matter most: when it's long, its end is kept, from a line's start.
        guard data.count > maxBytes else { return String(decoding: data, as: UTF8.self) }
        var tail = data.suffix(maxBytes)
        if let nl = tail.firstIndex(of: 0x0A) { tail = tail[tail.index(after: nl)...] }
        return "[…older entries left out]\n" + String(decoding: tail, as: UTF8.self)
    }

    /// Adds one entry (a line) and returns the file.
    @discardableResult
    public static func remember(_ fact: String, root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                date: Date = Date()) throws -> URL {
        let line = fact.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !line.isEmpty else { throw ToolFailure("nothing to remember.") }
        let url = file(root: root, home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // One write with O_APPEND: the app and a terminal saving at once each add their line whole.
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw ToolFailure("couldn't open \(url.path) (errno \(errno))") }
        defer { close(fd) }
        var info = stat()
        let size = fstat(fd, &info) == 0 ? info.st_size : 0
        var lastByte: UInt8 = 0x0A
        if size > 0 { _ = pread(fd, &lastByte, 1, size - 1) }
        let head = size == 0 ? "# Memory for \(Workspace.canonical(root).path)\n\n" : (lastByte == 0x0A ? "" : "\n")
        let entry = Data((head + "- \(line) (\(DayFormat.formatter(zone: .current).string(from: date)))\n").utf8)
        let written = entry.withUnsafeBytes { write(fd, $0.baseAddress, entry.count) }
        guard written == entry.count else { throw ToolFailure("couldn't write to \(url.path) (errno \(errno))") }
        return url
    }

    /// The note a message is, when it's one line starting with "# " (the composer's shortcut for remembering).
    public static func note(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("# "), !t.contains("\n") else { return nil }
        let note = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return note.isEmpty ? nil : note
    }

    /// What `/memory` shows: where the file is and what's in it.
    public static func listing(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let url = file(root: root, home: home)
        guard let text = text(root: root, home: home) else {
            return "No memory for this project yet. The agent saves facts with its remember tool; type \"# …\" to add one "
                + "yourself. It will be kept in \(url.path)."
        }
        return "Memory for this project (\(url.path); edit it in any editor):\n\n" + text
    }
}

/// Lets the model keep a fact for later sessions on the project (B6).
public struct RememberTool: Tool {
    public init() {}
    public let name = "remember"
    // It changes what every later session is told: asked about like an edit (and never offered in Plan mode, where it
    // would be the one thing a read-only run could keep).
    public let risk = ToolRisk.write
    public let description = """
        Save a fact for later sessions on this project; it goes into the instructions of every future session here. \
        Use it for what the user tells you to remember, a preference they state ("always use pnpm"), or a project fact \
        you had to work out that isn't written down (a command that works, a trap to avoid). One short sentence. Not \
        for this task's progress, and not for what AGENTS.md already says.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": ["memory": ["type": "string", "description": "The fact, in one sentence."]],
        "required": ["memory"],
    ]

    public func summary(_ args: ToolArguments) -> String {
        "Remember: " + (args.string("memory") ?? args.string("fact") ?? args.string("content") ?? "?")
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let fact = args.string("memory") ?? args.string("fact") ?? args.string("content") ?? args.string("text") ?? ""
        let url = try Memory.remember(fact, root: context.workspace.root, home: context.memoryHome ?? FileManager.default.homeDirectoryForCurrentUser)
        let saved = fact.split(whereSeparator: \.isNewline).joined(separator: " ")
        return ToolOutput(text: "Saved to this project's memory (\(url.path)); later sessions here will have it in their instructions.",
                          display: "Remembered: " + saved)
    }
}
