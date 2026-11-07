import Foundation

/// One file's change in a patch.
struct PatchOp: Equatable, Sendable {
    struct Hunk: Equatable, Sendable {
        /// V4A's `@@ text` lines (each a line to find first, in order: `@@ class B:` then `@@ def run`).
        var anchors: [String] = []
        /// Lines with their mark: " " context, "-" removed, "+" added.
        var lines: [(mark: Character, text: String)]
        /// `*** End of File`: the hunk ends at the file's end.
        var atEnd = false
        /// A unified diff's old start line (1-based), a hint for where the hunk goes.
        var oldStart: Int?

        init(anchors: [String] = [], lines: [(mark: Character, text: String)] = [], oldStart: Int? = nil) {
            self.anchors = anchors
            self.lines = lines
            self.oldStart = oldStart
        }

        static func == (a: Hunk, b: Hunk) -> Bool {
            a.anchors == b.anchors && a.atEnd == b.atEnd && a.oldStart == b.oldStart && a.lines.map(\.mark) == b.lines.map(\.mark)
                && a.lines.map(\.text) == b.lines.map(\.text)
        }
        var old: [String] { lines.filter { $0.mark != "+" }.map(\.text) }
        var new: [String] { lines.filter { $0.mark != "-" }.map(\.text) }
    }
    enum Kind: Equatable, Sendable {
        case add(content: String)
        case delete
        case update(moveTo: String?, hunks: [Hunk])
    }
    var path: String
    var kind: Kind

    var paths: [String] {
        if case .update(let to?, _) = kind { return [path, to] }
        return [path]
    }
}

/// Reads the two patch formats models write: Codex's (`*** Begin Patch` … `*** Update File:` … `@@` … `*** End Patch`,
/// known as V4A) and unified diffs (`--- a/x`, `+++ b/x`, `@@ -1,3 +1,4 @@`, with or without `diff --git` lines).
enum PatchParser {
    static func parse(_ patch: String) throws -> [PatchOp] {
        var text = patch.replacingOccurrences(of: "\r\n", with: "\n")
        // Some models wrap the patch in a code fence or a heredoc.
        if let fence = text.range(of: #"```[a-z]*\n([\s\S]*?)\n```"#, options: .regularExpression) {
            text = String(text[fence]).components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        let lines = text.components(separatedBy: "\n")
        if lines.contains(where: { $0.hasPrefix("*** Begin Patch") || $0.hasPrefix("*** Update File:") || $0.hasPrefix("*** Add File:") }) {
            return try parseV4A(lines)
        }
        if lines.contains(where: { $0.hasPrefix("--- ") }) && lines.contains(where: { $0.hasPrefix("+++ ") }) {
            return try parseUnified(lines)
        }
        throw ToolFailure("the patch has no file headers. Use *** Begin Patch / *** Update File: path / @@ / lines marked "
                          + "with space, - or + / *** End Patch, or a unified diff (--- a/path, +++ b/path, @@).")
    }

    static func parseV4A(_ lines: [String]) throws -> [PatchOp] {
        var ops: [PatchOp] = []
        var i = 0
        func header(_ line: String, _ prefix: String) -> String? {
            line.hasPrefix(prefix) ? line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) : nil
        }
        func isHeader(_ l: String) -> Bool { l.hasPrefix("*** ") && !l.hasPrefix("*** End of File") }
        while i < lines.count {
            let line = lines[i]
            if let path = header(line, "*** Add File:") {
                i += 1
                var body: [String] = []
                while i < lines.count, !isHeader(lines[i]) {
                    let l = lines[i]
                    if l.hasPrefix("+") { body.append(String(l.dropFirst())) }
                    else if l.isEmpty {
                        // A blank line whose "+" was left out, unless only headers or the end follow.
                        if let next = lines[(i + 1)...].first(where: { !$0.isEmpty }), !isHeader(next) { body.append("") }
                    }
                    else { throw ToolFailure("in *** Add File: \(path), every line must start with +; got: \(l.prefix(80))") }
                    i += 1
                }
                ops.append(PatchOp(path: path, kind: .add(content: body.isEmpty ? "" : body.joined(separator: "\n") + "\n")))
            } else if let path = header(line, "*** Delete File:") {
                ops.append(PatchOp(path: path, kind: .delete))
                i += 1
            } else if let path = header(line, "*** Update File:") {
                i += 1
                var moveTo: String?
                if i < lines.count, let to = header(lines[i], "*** Move to:") { moveTo = to; i += 1 }
                var hunks: [PatchOp.Hunk] = []
                var current: PatchOp.Hunk?
                while i < lines.count, !isHeader(lines[i]) {
                    let l = lines[i]
                    if l.hasPrefix("@@") {
                        let anchor = l.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        // A unified-diff range ("@@ -3,4 +3,5 @@") isn't an anchor; its start line is a hint.
                        let range = anchor.firstMatch(of: /^-(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@/)
                        let text = anchor.isEmpty || range != nil ? nil : anchor
                        if var c = current, c.lines.isEmpty {
                            // Stacked @@ lines narrow one hunk (Codex writes "@@ class B:" then "@@ def run").
                            if let text { c.anchors.append(text) }
                            current = c
                        } else {
                            if let c = current { hunks.append(c) }
                            current = PatchOp.Hunk(anchors: text.map { [$0] } ?? [], oldStart: range.flatMap { Int($0.1) })
                        }
                    } else if l.hasPrefix("*** End of File") {
                        current?.atEnd = true
                    } else if let mark = l.first, mark == " " || mark == "-" || mark == "+" {
                        if current == nil { current = PatchOp.Hunk() }
                        current!.lines.append((mark, String(l.dropFirst())))
                    } else if l.isEmpty {
                        // A blank context line whose leading space was dropped; blank lines just before the next header
                        // or the end are nothing.
                        if let next = lines[(i + 1)...].first(where: { !$0.isEmpty }), !isHeader(next) {
                            if current == nil { current = PatchOp.Hunk() }
                            current!.lines.append((" ", ""))
                        }
                    } else {
                        throw ToolFailure("in *** Update File: \(path), a line must start with space, - or + (or be @@): \(l.prefix(80))")
                    }
                    i += 1
                }
                if let c = current, !c.lines.isEmpty { hunks.append(c) }
                if hunks.isEmpty, moveTo == nil { throw ToolFailure("*** Update File: \(path) has no changes") }
                ops.append(PatchOp(path: path, kind: .update(moveTo: moveTo, hunks: hunks)))
            } else {
                i += 1   // *** Begin Patch, *** End Patch, stray text
            }
        }
        if ops.isEmpty { throw ToolFailure("the patch has no *** Add File, *** Update File or *** Delete File sections") }
        return ops
    }

    static func parseUnified(_ lines: [String]) throws -> [PatchOp] {
        var ops: [PatchOp] = []
        var i = 0
        func path(_ s: Substring) -> String? {
            var p = s.trimmingCharacters(in: .whitespaces)
            if let tab = p.firstIndex(of: "\t") { p = String(p[..<tab]) }     // "--- a/x\t2026-10-25 …"
            if p == "/dev/null" { return nil }
            if p.hasPrefix("a/") || p.hasPrefix("b/") { p.removeFirst(2) }
            return p
        }
        while i < lines.count {
            guard lines[i].hasPrefix("--- "), i + 1 < lines.count, lines[i + 1].hasPrefix("+++ ") else { i += 1; continue }
            let from = path(lines[i].dropFirst(4)), to = path(lines[i + 1].dropFirst(4))
            i += 2
            var hunks: [PatchOp.Hunk] = []
            // The next file starts at "--- " followed by "+++ " (a removed line "-- comment" is "--- comment").
            func fileHeader(_ k: Int) -> Bool { lines[k].hasPrefix("--- ") && k + 1 < lines.count && lines[k + 1].hasPrefix("+++ ") }
            while i < lines.count, !fileHeader(i), !lines[i].hasPrefix("diff ") {
                let l = lines[i]
                if l.hasPrefix("@@") {
                    let start = l.firstMatch(of: /^@@ -(\d+)/).flatMap { Int($0.1) }
                    hunks.append(PatchOp.Hunk(oldStart: start))
                } else if !hunks.isEmpty, let mark = l.first, mark == " " || mark == "-" || mark == "+" {
                    hunks[hunks.count - 1].lines.append((mark, String(l.dropFirst())))
                } else if !hunks.isEmpty, l.isEmpty, i + 1 < lines.count, !fileHeader(i + 1) {
                    hunks[hunks.count - 1].lines.append((" ", ""))
                } else if l.hasPrefix("\\") {
                    // "\ No newline at end of file"
                }
                i += 1
            }
            hunks.removeAll { $0.lines.isEmpty }
            switch (from, to) {
            case (nil, let to?):
                ops.append(PatchOp(path: to, kind: .add(content: hunks.flatMap(\.new).map { $0 + "\n" }.joined())))
            case (let from?, nil):
                ops.append(PatchOp(path: from, kind: .delete))
            case (let from?, let to?):
                ops.append(PatchOp(path: from, kind: .update(moveTo: to == from ? nil : to, hunks: hunks)))
            default: break
            }
        }
        if ops.isEmpty { throw ToolFailure("the unified diff has no --- / +++ file headers") }
        return ops
    }

    /// `text` with `hunks` applied in order, each found at or after the previous one (exact, then ignoring trailing
    /// whitespace, then indentation). Notes say where a loose match was used. A loose match must be the only one (else
    /// the hunk is refused), and one found by ignoring indentation has its new lines re-indented to the file's.
    static func apply(_ hunks: [PatchOp.Hunk], to text: String, path: String) throws -> (String, [String]) {
        let crlf = text.contains("\r\n")
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let trailingNewline = lines.last == ""
        if trailingNewline { lines.removeLast() }
        var cursor = 0
        var notes: [String] = []
        /// Lines earlier hunks added (or took away, if negative): a unified diff's start lines are the old file's.
        var shift = 0
        func rstrip(_ s: String) -> Substring {
            var t = Substring(s)
            while let c = t.last, c.isWhitespace { t.removeLast() }
            return t
        }
        func strip(_ s: String) -> Substring { rstrip(s).drop { $0.isWhitespace } }
        let levels: [(String) -> Substring] = [{ Substring($0) }, rstrip, strip]
        enum Seek { case found(Int, level: Int), several([Int], level: Int), none }
        /// Where `want` is, at or after `from`: the first exact match, or with a line `hint` (0-based) the match nearest it.
        /// A loose match must be the only one (or the one clearly nearest the hint), and so must an exact one when
        /// `unique` (the search of the whole file, after the in-order one failed).
        func seek(_ want: [String], from: Int, atEnd: Bool, hint: Int? = nil, unique: Bool = false) -> Seek {
            let last = lines.count - want.count
            guard want.count <= lines.count, atEnd || from <= last else { return .none }
            for (level, norm) in levels.enumerated() {
                let target = want.map(norm)
                let starts = atEnd ? [last] : Array(max(0, from)...last)
                let found = starts.filter { s in s >= 0 && (0..<want.count).allSatisfy({ norm(lines[s + $0]) == target[$0] }) }
                guard let first = found.first else { continue }
                if let hint {
                    let byDistance = found.sorted { abs($0 - hint) < abs($1 - hint) }
                    if level == 0 && !unique || byDistance.count == 1 || abs(byDistance[0] - hint) < abs(byDistance[1] - hint) {
                        return .found(byDistance[0], level: level)
                    }
                    return .several(found, level: level)
                }
                if found.count > 1, level > 0 || unique { return .several(found, level: level) }
                return .found(first, level: level)
            }
            return .none
        }
        for (n, hunk) in hunks.enumerated() {
            let which = hunks.count > 1 ? "hunk \(n + 1) of \(hunks.count) in \(path)" : "the hunk in \(path)"
            // Each @@ line in turn, each found after the one before.
            for (k, anchor) in hunk.anchors.enumerated() {
                let a = strip(anchor)
                let after = cursor <= lines.count ? cursor : lines.count
                if let i = (after..<lines.count).first(where: { strip(lines[$0]) == a })
                    ?? (after..<lines.count).first(where: { lines[$0].contains(a) }) {
                    cursor = i + 1
                } else if k == 0, let i = (0..<after).first(where: { strip(lines[$0]) == a }) {
                    cursor = i + 1
                } else {
                    throw ToolFailure("\(which): its @@ line \"\(anchor.prefix(80))\" isn't in the file"
                                      + (k > 0 ? " after \"\(hunk.anchors[k - 1].prefix(60))\"" : "") + ". Read the file and make the patch again.")
                }
            }
            let old = hunk.old, new = hunk.new
            let hint = hunk.anchors.isEmpty ? hunk.oldStart.map { max(0, $0 - 1 + shift) } : nil
            if old.isEmpty {
                // Only additions: after the anchor, at a unified diff's line ("@@ -3,0 +4 @@" is after line 3), or at the end.
                let at = !hunk.anchors.isEmpty ? cursor : hunk.oldStart.map { min(lines.count, max(0, $0 + shift)) } ?? lines.count
                lines.insert(contentsOf: new, at: at)
                cursor = at + new.count
                shift += new.count
                continue
            }
            var result = seek(old, from: cursor, atEnd: hunk.atEnd, hint: hint)
            if case .none = result { result = seek(old, from: 0, atEnd: hunk.atEnd, hint: hint, unique: true) }
            let start: Int, level: Int
            switch result {
            case .found(let s, let l): (start, level) = (s, l)
            case .several(let starts, let l):
                let ignoring = ["", " once trailing whitespace is ignored", " once indentation and trailing whitespace are ignored"][l]
                let places = starts.prefix(5).map { String($0 + 1) }.joined(separator: ", ") + (starts.count > 5 ? ", …" : "")
                throw ToolFailure("\(which) matches \(starts.count) places in the file\(ignoring) (lines \(places)), so it's unclear "
                                  + "which to change. Add context lines, or an @@ line naming the function or class above the "
                                  + "change, so it matches one place. Nothing was changed.")
            case .none:
                let shown = old.prefix(6).map { "  " + $0 }.joined(separator: "\n")
                throw ToolFailure("\(which) doesn't match the file: these lines (context and -) weren't found in order:\n\(shown)"
                                  + (old.count > 6 ? "\n  …" : "") + "\nRead the file again and make the patch from its current text.")
            }
            var replacement = new
            if level > 0 {
                notes.append("\(which) matched lines \(start + 1)–\(start + old.count) only after ignoring "
                             + (level == 1 ? "trailing whitespace" : "indentation and trailing whitespace") + ".")
            }
            if level == 2 {
                // The patch's indentation is off from the file's: its new lines take the file's, as edit_file does.
                var m = LooseMatch.Match(lines: start..<(start + old.count), ignored: "indentation")
                m.oldIndents = old.map(LooseMatch.Match.indent)
                m.fileIndents = (start..<(start + old.count)).map { LooseMatch.Match.indent(lines[$0]) }
                m.oldContent = old.map(strip)
                if m.oldIndents != m.fileIndents { replacement = m.reindent(new) }
            }
            lines.replaceSubrange(start..<(start + old.count), with: replacement)
            cursor = start + replacement.count
            shift += replacement.count - old.count
        }
        var out = lines.joined(separator: "\n") + (trailingNewline || text.isEmpty ? "\n" : "")
        if lines.isEmpty { out = "" }
        if crlf { out = out.replacingOccurrences(of: "\n", with: "\r\n") }
        return (out, notes)
    }
}

/// Codex's patch tool (B5), offered to model families trained on it (GPT, Codex, gpt-oss) beside edit_file: several
/// files' changes, adds, deletes and moves in one call, all or none.
public struct ApplyPatchTool: Tool {
    public init() {}
    public let name = "apply_patch"
    public let description = """
        Change files with a patch: several hunks and files in one call, applied all or none. Format:
        *** Begin Patch
        *** Update File: path/to/file.py
        @@ def some_function():
         context line (starts with a space)
        -line to remove
        +line to add
        *** Add File: path/to/new.py
        +each line of the new file
        *** Delete File: path/to/old.py
        *** End Patch
        "*** Move to: new/path" may follow an Update File line. The @@ line names a line just above the change (it may be \
        empty). Give 3 lines of context around each change. A unified diff (--- a/x, +++ b/x, @@ -1,3 +1,4 @@) also works. \
        Read a file before changing it.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": ["patch": ["type": "string", "description": "The patch text, from *** Begin Patch to *** End Patch."]],
        "required": ["patch"],
    ]
    public let risk = ToolRisk.write

    public func summary(_ args: ToolArguments) -> String {
        guard let ops = try? PatchParser.parse(Self.text(args)) else { return "Apply a patch" }
        return ops.count == 1 ? "Patch \(ops[0].path)" : "Patch \(ops.count) files"
    }

    static func text(_ args: ToolArguments) -> String { args.string("patch") ?? args.string("input") ?? args.string("diff") ?? "" }

    struct Change {
        var url: URL
        var relative: String
        var before: String?     // nil: a new file
        var after: String?      // nil: deleted
        var notes: [String] = []
    }

    func plan(_ args: ToolArguments, context: ToolContext) throws -> [Change] {
        let text = Self.text(args)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolFailure("missing required argument \"patch\"") }
        let ws = context.workspace
        var changes: [Change] = []
        func current(_ url: URL, _ path: String) throws -> String {
            if let c = changes.last(where: { $0.url == url }) {
                guard let a = c.after else { throw ToolFailure("\(path) is deleted earlier in the patch") }
                return a
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ToolFailure("\(path) does not exist. To create it, use *** Add File: \(path).")
            }
            let data = try Data(contentsOf: url)
            if looksBinary(data) { throw ToolFailure("\(path) is a binary file") }
            guard let s = String(data: data, encoding: .utf8) else { throw ToolFailure(notUTF8(path)) }
            return s
        }
        for op in try PatchParser.parse(text) {
            let url = try ws.resolveForWriting(op.path)
            let rel = ws.relative(url)
            switch op.kind {
            case .add(let content):
                if FileManager.default.fileExists(atPath: url.path), !changes.contains(where: { $0.url == url && $0.after == nil }) {
                    throw ToolFailure("\(op.path) already exists. To change it, use *** Update File: \(op.path).")
                }
                changes.append(Change(url: url, relative: rel, before: nil, after: content))
            case .delete:
                if !changes.contains(where: { $0.url == url }) { try context.reads?.check(url, path: op.path) }
                let before = try current(url, op.path)
                changes.append(Change(url: url, relative: rel, before: before, after: nil))
            case .update(let moveTo, let hunks):
                if !changes.contains(where: { $0.url == url }) { try context.reads?.check(url, path: op.path) }
                let before = try current(url, op.path)
                let (after, notes) = try PatchParser.apply(hunks, to: before, path: op.path)
                if let moveTo {
                    let dest = try ws.resolveForWriting(moveTo)
                    if FileManager.default.fileExists(atPath: dest.path) { throw ToolFailure("can't move \(op.path) to \(moveTo): it exists") }
                    changes.append(Change(url: url, relative: rel, before: before, after: nil))
                    changes.append(Change(url: dest, relative: ws.relative(dest), before: nil, after: after, notes: notes))
                } else {
                    changes.append(Change(url: url, relative: rel, before: before, after: after, notes: notes))
                }
            }
        }
        return changes
    }

    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? {
        let changes = try plan(args, context: context)
        let diff = changes.map { LineDiff.unified(old: $0.before ?? "", new: $0.after ?? "", path: $0.relative) }.joined()
        let path = changes.count == 1 ? changes[0].relative : "\(Set(changes.map(\.relative)).count) files"
        return .diff(path: path, unified: diff, isNewFile: changes.allSatisfy { $0.before == nil })
    }

    public func affectedFiles(_ args: ToolArguments, context: ToolContext) throws -> [URL] {
        var urls: [URL] = []
        for p in (try PatchParser.parse(Self.text(args))).flatMap(\.paths) {
            let u = try context.workspace.resolveForWriting(p)
            if !urls.contains(u) { urls.append(u) }
        }
        return urls
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let changes = try plan(args, context: context)
        let fm = FileManager.default
        // The final state of each file, in order of first mention.
        var order: [URL] = []
        var final: [URL: Change] = [:]
        for c in changes {
            if !order.contains(c.url) { order.append(c.url) }
            var merged = c
            if let earlier = final[c.url] { merged.before = earlier.before; merged.notes = earlier.notes + c.notes }
            final[c.url] = merged
        }
        // Every file must be writable before any is written: a path through an existing file ("README.md/x") failed
        // halfway, after earlier files had changed (a move had already lost its source).
        let root = context.workspace.root.standardizedFileURL.path
        for url in order where final[url]?.after != nil {
            var dir = url.deletingLastPathComponent().standardizedFileURL
            while dir.path.count >= root.count {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
                    if !isDir.boolValue {
                        throw ToolFailure("can't write \(final[url]!.relative): \(context.workspace.relative(dir)) is a file, not a "
                                          + "folder. Nothing was changed.")
                    }
                    break
                }
                dir = dir.deletingLastPathComponent()
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                throw ToolFailure("can't write \(final[url]!.relative): it's a folder. Nothing was changed.")
            }
        }
        // Writes first, deletions after (a move's source goes only once its destination is written).
        order.sort { (final[$0]?.after == nil ? 1 : 0) < (final[$1]?.after == nil ? 1 : 0) }
        try Self.writeAllOrNone(order.compactMap { url in final[url].flatMap { c in c.after.map { (c, $0) } } },
                                workspace: context.workspace)
        var lines: [String] = []
        var display = ""
        for url in order {
            guard let c = final[url] else { continue }
            let comparison = LineDiff.compare(old: c.before ?? "", new: c.after ?? "")
            display += LineDiff.unified(comparison, path: c.relative)
            if c.after != nil {
                context.reads?.record(url)
                if c.before != nil {
                    let (a, r) = LineDiff.stats(comparison)
                    var line = "Updated \(c.relative) (+\(a) −\(r))."
                    for n in c.notes { line += " Note: " + n }
                    let region = LineDiff.changedRegions(comparison, limit: 30)
                    lines.append(line + (region.isEmpty ? "" : " Now:\n" + region))
                } else {
                    lines.append("Added \(c.relative) (\(comparison.newLines.count) lines).")
                }
            } else if c.before != nil {
                do {
                    try fm.removeItem(at: url)
                    lines.append("Deleted \(c.relative).")
                } catch {
                    lines.append("Couldn't delete \(c.relative): \(error.localizedDescription)")
                }
            }
        }
        let (capped, cut) = capOutput(lines.joined(separator: "\n"), maxBytes: context.maxOutputBytes,
                                      hint: "The patch was applied in full; read the files to see the rest.")
        return ToolOutput(text: capped, truncated: cut, display: display)
    }

    /// Writes every file or none: each new text goes to a file beside its target first, and only when all are written
    /// are they renamed into place. A rename that fails puts back what the earlier ones replaced. Folders made for new
    /// files are removed again when nothing was written. The error names the file that failed.
    static func writeAllOrNone(_ writes: [(Change, String)], workspace: Workspace) throws {
        let fm = FileManager.default
        var staged: [(change: Change, temp: URL)] = []
        var madeFolders: [URL] = []
        func removeStaged() {
            for s in staged { try? fm.removeItem(at: s.temp) }
            for folder in madeFolders.reversed() { rmdir(folder.path) }      // only the ones made here, once empty
        }
        for (c, after) in writes {
            let folder = c.url.deletingLastPathComponent()
            do {
                var missing: [URL] = []
                var dir = folder
                while !fm.fileExists(atPath: dir.path), dir.path.count > 1 { missing.append(dir); dir = dir.deletingLastPathComponent() }
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                madeFolders += missing.reversed()
                let temp = folder.appending(path: ".\(c.url.lastPathComponent).kk-patch-\(UUID().uuidString.prefix(8))")
                try Data(after.utf8).write(to: temp)
                staged.append((c, temp))
                // An updated file keeps its permissions (an executable script stays executable).
                if c.before != nil, let mode = (try? fm.attributesOfItem(atPath: c.url.path))?[.posixPermissions] {
                    try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
                }
            } catch {
                removeStaged()
                throw ToolFailure("couldn't write \(c.relative): \(error.localizedDescription). Nothing was changed.")
            }
        }
        var done: [Change] = []
        for (i, s) in staged.enumerated() {
            if rename(s.temp.path, s.change.url.path) == 0 { done.append(s.change); continue }
            let why = String(cString: strerror(errno))
            // Put back what the files already renamed into place replaced.
            for c in done {
                if let before = c.before { try? Data(before.utf8).write(to: c.url) } else { try? fm.removeItem(at: c.url) }
            }
            for rest in staged[i...] { try? fm.removeItem(at: rest.temp) }
            for folder in madeFolders.reversed() { rmdir(folder.path) }
            throw ToolFailure("couldn't write \(s.change.relative): \(why). Nothing was changed"
                              + (done.isEmpty ? "." : " (the files written before it were put back)."))
        }
    }
}
