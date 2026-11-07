import Foundation

public struct EditFileTool: Tool {
    public init() {}
    public let name = "edit_file"
    public let description = """
        Edit a file by replacing exact text. old_string must match the file exactly, including indentation, \
        and must occur exactly once unless replace_all is true. Include enough surrounding lines to make it \
        unique. Don't include the line-number prefixes that read_file shows. Read the file before editing it. \
        For several changes to one file, pass edits: a list of {old_string, new_string}, applied in order, all or none.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "File to edit, relative to the project root."],
            "old_string": ["type": "string", "description": "Exact text to replace."],
            "new_string": ["type": "string", "description": "Replacement text."],
            "replace_all": ["type": "boolean", "description": "Replace every occurrence. Default false."],
            "edits": [
                "type": "array",
                "description": "Several replacements in one call, applied in order (instead of old_string/new_string).",
                "items": [
                    "type": "object",
                    "properties": [
                        "old_string": ["type": "string"], "new_string": ["type": "string"], "replace_all": ["type": "boolean"],
                    ],
                    "required": ["old_string", "new_string"],
                ],
            ],
        ],
        "required": ["path"],
    ]
    public let risk = ToolRisk.write

    public func summary(_ args: ToolArguments) -> String {
        let n = Self.edits(args).count
        return "Edit \((try? Self.path(args)) ?? "?")" + (n > 1 ? " (\(n) changes)" : "")
    }

    /// The file: `path` (or Claude Code's `file_path`), else the one the edits name (models put it there too).
    static func path(_ args: ToolArguments) throws -> String {
        if let p = args.string("path") ?? args.string("file_path"), !p.isEmpty { return p }
        var named = Set<String>()
        var list = args.values["edits"]
        if case .string(let s)? = list { list = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }
        if case .array(let items)? = list {
            for case .object(let o) in items {
                if let p = ToolArguments(o).string("path") ?? ToolArguments(o).string("file_path"), !p.isEmpty { named.insert(p) }
            }
        }
        if named.count > 1 { throw ToolFailure("the edits name \(named.count) files; edit_file changes one file per call (give path once).") }
        guard let p = named.first else { throw ToolFailure("missing required argument \"path\"") }
        return p
    }

    struct Edit {
        var old: String
        var new: String
        var replaceAll: Bool
    }

    /// The call's edits: `edits` (an array, or one sent as a JSON string), after old_string/new_string when both are given.
    static func edits(_ args: ToolArguments) -> [Edit] {
        var out: [Edit] = []
        if args.values["old_string"] != nil || args.values["new_string"] != nil {
            out.append(Edit(old: args.string("old_string") ?? "", new: args.string("new_string") ?? "",
                            replaceAll: args.bool("replace_all") == true))
        }
        var list = args.values["edits"]
        if case .string(let s)? = list { list = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }
        if case .array(let items)? = list {
            for case .object(let o) in items {
                let e = ToolArguments(o)
                out.append(Edit(old: e.string("old_string") ?? "", new: e.string("new_string") ?? "",
                                replaceAll: e.bool("replace_all") == true))
            }
        }
        return out
    }

    struct Plan {
        let url: URL
        let relative: String
        let before: String
        let after: String
        let count: Int
        /// What the model should know about how its text was matched (a loose match).
        let notes: [String]
    }

    /// Works out the edit without writing, so the preview and the run agree.
    func plan(_ args: ToolArguments, context: ToolContext) throws -> Plan {
        let path = try Self.path(args)
        let url = try context.workspace.resolveForWriting(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolFailure("\(path) does not exist. Use write_file to create a new file.")
        }
        try context.reads?.check(url, path: path)
        let data = try Data(contentsOf: url)
        if looksBinary(data) { throw ToolFailure("\(path) is a binary file") }
        guard let before = String(data: data, encoding: .utf8) else { throw ToolFailure(notUTF8(path)) }
        let edits = Self.edits(args)
        guard !edits.isEmpty else { throw ToolFailure("missing required argument \"old_string\" (or \"edits\")") }
        var text = before
        var count = 0
        var notes: [String] = []
        for (i, edit) in edits.enumerated() {
            let which = edits.count > 1 ? "edit \(i + 1) of \(edits.count): " : ""
            do {
                let (after, n, note) = try Self.apply(edit, to: text, path: path)
                text = after
                count += n
                if let note { notes.append(which + note) }
            } catch let f as ToolFailure {
                throw ToolFailure(which + f.message + (edits.count > 1 ? " Nothing was changed." : ""))
            }
        }
        return Plan(url: url, relative: context.workspace.relative(url), before: before, after: text, count: count, notes: notes)
    }

    /// One replacement: exact first, then (for whole lines) ignoring trailing whitespace, then indentation.
    static func apply(_ edit: Edit, to before: String, path: String) throws -> (String, Int, String?) {
        guard !edit.old.isEmpty else {
            throw ToolFailure("old_string is empty. To add text, include a nearby line in old_string and repeat it in new_string.")
        }
        var new = edit.new
        if edit.old == new { throw ToolFailure("old_string and new_string are the same; nothing to change.") }
        // A file with Windows line ends: the model writes lines with "\n" (read_file shows no "\r"); match and write CRLF.
        var old = edit.old
        if before.contains("\r\n"), !old.contains("\r"), old.contains("\n") || new.contains("\n") {
            let crlf = { (s: String) in s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") }
            if !before.contains(old), before.contains(crlf(old)) { old = crlf(old) }
            if !new.contains("\r") { new = crlf(new) }
        }

        let count = before.components(separatedBy: old).count - 1
        if count == 0 {
            if let loose = LooseMatch.find(edit.old, in: before) {
                switch loose {
                case .one(let m):
                    return (m.replace(in: before, with: edit.new), 1,
                            "old_string matched lines \(m.lines.lowerBound + 1)–\(m.lines.upperBound) only after ignoring \(m.ignored); "
                            + "new_string was placed there\(m.reindented ? " with the file's indentation" : ""). Check the lines below.")
                case .many(let starts):
                    throw ToolFailure("old_string was not found in \(path) exactly; ignoring whitespace it matches \(starts.count) places "
                                      + "(lines \(starts.prefix(8).map { String($0 + 1) }.joined(separator: ", "))). Copy the exact text, "
                                      + "with enough surrounding lines to make it unique.")
                }
            }
            throw ToolFailure(notFoundMessage(old: old, path: path, text: before))
        }
        if count > 1 && !edit.replaceAll {
            let lines = lineNumbers(of: old, in: before, limit: 8).map(String.init).joined(separator: ", ")
            throw ToolFailure("old_string occurs \(count) times in \(path) (lines \(lines)). Include more surrounding "
                              + "lines to make it unique, or set replace_all to true to change every one.")
        }
        if edit.replaceAll { return (before.replacingOccurrences(of: old, with: new), count, nil) }
        return (before.replacingCharacters(in: before.range(of: old)!, with: new), 1, nil)
    }

    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? {
        let p = try plan(args, context: context)
        return .diff(path: p.relative, unified: LineDiff.unified(old: p.before, new: p.after, path: p.relative), isNewFile: false)
    }

    public func affectedFiles(_ args: ToolArguments, context: ToolContext) throws -> [URL] {
        [try context.workspace.resolveForWriting(try Self.path(args))]
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let p = try plan(args, context: context)
        try Data(p.after.utf8).write(to: p.url, options: .atomic)
        context.reads?.record(p.url)
        let comparison = LineDiff.compare(old: p.before, new: p.after)
        let diff = LineDiff.unified(comparison, path: p.relative)
        let (added, removed) = LineDiff.stats(comparison)
        // Show the model the edited regions with line numbers, so it can check the result and edit again.
        let snippet = LineDiff.changedRegions(comparison)
        var text = "Edited \(p.relative): \(p.count) replacement\(p.count == 1 ? "" : "s"), +\(added) −\(removed) lines."
        for n in p.notes { text += "\nNote: " + n }
        if !snippet.isEmpty { text += " Now:\n" + snippet }
        return ToolOutput(text: text, display: diff)
    }

    /// The lines `needle` starts on, at most `limit` of them. Newlines are counted as bytes (a CRLF file's "\r\n" is
    /// one Character, which a Character count misses), going forward from the last match, so it's linear in the text.
    static func lineNumbers(of needle: String, in text: String, limit: Int = .max) -> [Int] {
        var out: [Int] = []
        var search = text.startIndex..<text.endIndex
        var line = 1
        var counted = text.startIndex
        while out.count < limit, let r = text.range(of: needle, range: search) {
            line += text.utf8[counted..<r.lowerBound].reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
            counted = r.lowerBound
            out.append(line)
            search = r.upperBound..<text.endIndex
        }
        return out
    }

    /// Explains a failed match with the most likely cause.
    static func notFoundMessage(old: String, path: String, text: String) -> String {
        var msg = "old_string was not found in \(path)."
        if old.range(of: #"(^|\n)\s*\d+\t"#, options: .regularExpression) != nil {
            msg += " It looks like it includes line-number prefixes from read_file; remove them."
        } else {
            let squash = { (s: String) in s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if squash(text).contains(squash(old)) {
                msg += " The text is there but the whitespace or indentation differs; copy it exactly."
            } else if let firstLine = old.split(separator: "\n").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
                      firstLine.count > 3, let n = lineNumbers(of: firstLine, in: text, limit: 1).first {
                msg += " Its first line appears at line \(n), but the following lines differ. Read the file again."
            } else {
                msg += " Read the file again and copy the exact text."
            }
        }
        // Often the model is appending after a line that has since changed: show the current end of the
        // file so it can retry without another read. (To add at the end, write_file with append is simpler.)
        let lines = LineDiff.lines(text)
        if !lines.isEmpty {
            let from = max(0, lines.count - 5)
            let tail = lines[from...].enumerated().map { i, l in "\(from + i + 1)\t\(l.count > 300 ? String(l.prefix(300)) + "…" : l)" }
            msg += " The file has \(lines.count) lines and currently ends with:\n" + tail.joined(separator: "\n")
                + "\nTo add text at the end, use write_file with append: true."
        }
        return msg
    }
}

public struct WriteFileTool: Tool {
    public init() {}
    public let name = "write_file"
    public let description = """
        Create a new file, replace a file's entire contents, or (with append: true) add text to the end of \
        a file. Creates parent folders as needed. Prefer edit_file for changing part of an existing file.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "File path, relative to the project root."],
            "content": ["type": "string", "description": "The complete file contents, or the text to append."],
            "append": ["type": "boolean", "description": "Add content to the end of the file instead of replacing it. Default false."],
        ],
        "required": ["path", "content"],
    ]
    public let risk = ToolRisk.write

    public func summary(_ args: ToolArguments) -> String {
        (args.bool("append") == true ? "Append to " : "Write ") + (args.string("path") ?? "?")
    }

    /// The file's new contents. Appending adds a newline first if the file doesn't end with one.
    static func newContents(existing: String?, content: String, append: Bool) -> String {
        guard append, let existing, !existing.isEmpty else { return content }
        // utf8: a CRLF file's "\r\n" is one Character, which hasSuffix("\n") doesn't see.
        let crlf = existing.utf8.suffix(2).elementsEqual([0x0D, 0x0A])
        return existing + (existing.utf8.last == 0x0A ? "" : (crlf ? "\r\n" : "\n")) + content
    }

    func target(_ args: ToolArguments, context: ToolContext) throws -> (URL, String, String?) {
        let path = try args.require("path")
        let url = try context.workspace.resolveForWriting(path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { throw ToolFailure("\(path) is a directory") }
            // Replacing a file needs its text seen first; appending doesn't.
            if args.bool("append") != true { try context.reads?.check(url, path: path) }
            let data = try Data(contentsOf: url)
            if looksBinary(data) { throw ToolFailure("\(path) is a binary file; not overwriting it") }
            return (url, context.workspace.relative(url), String(decoding: data, as: UTF8.self))
        }
        return (url, context.workspace.relative(url), nil)
    }

    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? {
        let (_, rel, existing) = try target(args, context: context)
        let content = Self.newContents(existing: existing, content: args.string("content") ?? "", append: args.bool("append") == true)
        return .diff(path: rel, unified: LineDiff.unified(old: existing ?? "", new: content, path: rel), isNewFile: existing == nil)
    }

    public func affectedFiles(_ args: ToolArguments, context: ToolContext) throws -> [URL] {
        [try context.workspace.resolveForWriting(try args.require("path"))]
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let (url, rel, existing) = try target(args, context: context)
        let append = args.bool("append") == true
        if append, existing != nil, String(data: try Data(contentsOf: url), encoding: .utf8) == nil {
            throw ToolFailure(notUTF8(args.string("path") ?? rel))
        }
        let content = Self.newContents(existing: existing, content: args.string("content") ?? "", append: append)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        // Appending doesn't show the model the file; it counts as read only if it was before.
        if !append || context.reads?.hasRead(url) == true { context.reads?.record(url) }
        let comparison = LineDiff.compare(old: existing ?? "", new: content)
        let n = comparison.newLines.count
        let diff = LineDiff.unified(comparison, path: rel)
        if existing == nil { return ToolOutput(text: "Created \(rel) (\(n) lines).", display: diff) }
        if append {
            let added = LineDiff.lines(args.string("content") ?? "").count
            return ToolOutput(text: "Appended \(added) line\(added == 1 ? "" : "s") to \(rel); it now has \(n) lines.", display: diff)
        }
        let (added, removed) = LineDiff.stats(comparison)
        return ToolOutput(text: "Replaced the contents of \(rel) (\(n) lines, +\(added) −\(removed)).", display: diff)
    }
}

/// Why a file that isn't UTF-8 text (Latin-1, CP1252, …) isn't edited: rewriting it would turn each of those bytes into
/// U+FFFD.
func notUTF8(_ path: String) -> String {
    "\(path) isn't UTF-8 text (it has bytes of another encoding, such as Latin-1); editing it here would replace them. "
        + "Edit it with a command that keeps its bytes (sed, perl, iconv), or rewrite the whole file with write_file."
}
