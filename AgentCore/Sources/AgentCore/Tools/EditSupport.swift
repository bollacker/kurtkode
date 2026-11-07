import Foundation

/// Which files the run has read, and when, so an edit of a file the model hasn't seen (or that changed since it
/// looked) is refused (B5). One per agent run, seeded from the history it starts with: reads, edits and writes before a
/// compaction drop out with the messages, which is right, since the model no longer has those files' text.
public final class FileReads: @unchecked Sendable {
    private struct Seen {
        /// The file's modification date when it was read; nil for a read known only from the history.
        var modified: Date?
        var at: Date
    }
    private let lock = NSLock()
    private var seen: [String: Seen] = [:]

    public init() {}

    /// The tools whose successful calls mean the model has the file's current text.
    static let readers: Set<String> = ["read_file", "edit_file", "write_file", "apply_patch"]

    /// A log holding the reads, edits and writes in `history` (each as of its result's time).
    public static func seeded(from history: [ChatMessage], workspace: Workspace?) -> FileReads {
        let log = FileReads()
        guard let workspace else { return log }
        var calls: [String: ToolCall] = [:]
        for m in history {
            for c in m.toolCalls where readers.contains(c.name) { calls[c.id] = c }
            guard m.role == .tool, m.toolResult?.isError != true, let id = m.toolCallID, let call = calls[id],
                  let args = try? ToolArguments(json: call.arguments) else { continue }
            // Appends don't count: the model didn't see the file.
            if call.name == "write_file", args.bool("append") == true { continue }
            let paths = call.name == "apply_patch"
                ? ((try? PatchParser.parse(args.string("patch") ?? args.string("input") ?? ""))?.flatMap(\.paths) ?? [])
                : call.name == "edit_file" ? [try? EditFileTool.path(args)].compactMap { $0 }
                : [args.string("path") ?? args.string("file_path")].compactMap { $0 }
            for p in paths {
                if let url = try? workspace.resolve(p) { log.record(url, modified: nil, at: m.createdAt) }
            }
        }
        return log
    }

    /// The file was read (or written) now.
    public func record(_ url: URL) {
        record(url, modified: Self.modified(url), at: Date())
    }

    func record(_ url: URL, modified: Date?, at: Date) {
        let key = Workspace.canonical(url).path
        lock.withLock { seen[key] = Seen(modified: modified, at: at) }
    }

    public func hasRead(_ url: URL) -> Bool { lock.withLock { seen[Workspace.canonical(url).path] != nil } }

    /// Refuses a file that wasn't read, or changed after it was.
    public func check(_ url: URL, path: String) throws {
        guard let s = lock.withLock({ seen[Workspace.canonical(url).path] }) else {
            throw ToolFailure("\(path) hasn't been read in this session. Read it first with read_file (a range around the "
                              + "change is enough), then edit it: an edit made without seeing the file can lose text.")
        }
        guard let now = Self.modified(url) else { return }
        let changed = s.modified.map { abs(now.timeIntervalSince($0)) > 0.001 } ?? (now > s.at)
        if changed {
            throw ToolFailure("\(path) changed since you last read it (a command, a formatter or the user changed it). Read it "
                              + "again before editing, so the edit doesn't undo those changes.")
        }
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// A second pass for an edit whose old text isn't in the file exactly: whole lines compared without trailing
/// whitespace, then without indentation. Used only when it finds one place (B5): weak models often get indentation
/// wrong by a level, or drop trailing spaces, and each failed edit costs a turn.
enum LooseMatch {
    struct Match {
        /// The file's lines that matched (0-based, end exclusive).
        var lines: Range<Int>
        /// What was ignored, for the note to the model.
        var ignored: String
        /// The new text's indentation was changed to the file's.
        var reindented = false
        /// Each matched line's indentation in the old text and in the file, and the old lines without it.
        var oldIndents: [String] = []
        var fileIndents: [String] = []
        var oldContent: [Substring] = []
        var crlf = false

        static func indent(_ s: String) -> String { String(s.prefix { $0 == " " || $0 == "\t" }) }

        /// One shift for every line (the old text is the file's, a level or two off), as (from, to).
        var shift: (String, String)? {
            let pairs = zip(oldIndents, fileIndents).enumerated().filter { !oldContent[$0.offset].isEmpty }.map(\.element)
            guard let (from, to) = pairs.first else { return nil }
            let base = pairs.map(\.0).min { $0.count < $1.count } ?? from
            let target = String(to.dropLast(max(0, from.count - base.count)))
            return pairs.allSatisfy { o, f in o.hasPrefix(base) && f == target + o.dropFirst(base.count) } ? (base, target) : nil
        }

        /// `new`'s lines with the file's indentation: shifted when the old text was shifted as a whole; else (it was
        /// flattened) each line takes the indentation of the old line it repeats, or of the line it stands in for.
        func reindent(_ new: [String]) -> [String] {
            if let (from, to) = shift {
                return new.map { l in
                    l.trimmingCharacters(in: .whitespaces).isEmpty ? l : (l.hasPrefix(from) ? to + l.dropFirst(from.count) : to + l)
                }
            }
            var p = 0
            return new.map { l in
                let content = l.drop { $0 == " " || $0 == "\t" }
                guard !content.isEmpty, !oldContent.isEmpty else { return l }
                let mine = Self.indent(l)
                if let j = (p..<min(oldContent.count, p + 4)).first(where: { oldContent[$0] == content.trimmingCharacters(in: .whitespaces)[...] }) {
                    p = j + 1
                    let extra = mine.hasPrefix(oldIndents[j]) ? String(mine.dropFirst(oldIndents[j].count)) : ""
                    return fileIndents[j] + extra + content
                }
                let j = min(p, oldContent.count - 1)
                let extra = mine.hasPrefix(oldIndents[j]) ? String(mine.dropFirst(oldIndents[j].count)) : ""
                return fileIndents[j] + extra + content
            }
        }

        /// `text` with the matched lines replaced by `new` (re-indented, and with CRLF ends where the file has them).
        func replace(in text: String, with new: String) -> String {
            var lines = text.components(separatedBy: "\n")
            var replacement = new.isEmpty ? [] : new.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            if new.hasSuffix("\n") { replacement.removeLast() }
            if reindented { replacement = reindent(replacement) }
            if crlf { replacement = replacement.map { $0 + "\r" } }
            lines.replaceSubrange(self.lines, with: replacement)
            return lines.joined(separator: "\n")
        }
    }

    enum Result {
        case one(Match)
        /// Several places (0-based first lines): too ambiguous to use.
        case many([Int])
    }

    static func find(_ old: String, in text: String) -> Result? {
        var want = old.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if old.hasSuffix("\n") { want.removeLast() }
        guard !want.isEmpty, want.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let lines = text.components(separatedBy: "\n")
        let usable = lines.count - (text.utf8.last == 0x0A ? 1 : 0)
        guard usable >= want.count else { return nil }

        func rstrip(_ s: String) -> Substring {
            var t = Substring(s)
            while let c = t.last, c.isWhitespace { t.removeLast() }
            return t
        }
        func strip(_ s: String) -> Substring { rstrip(s).drop { $0.isWhitespace } }
        for (norm, ignored) in [(rstrip, "trailing whitespace"), (strip, "indentation and trailing whitespace")] {
            let target = want.map(norm)
            let starts = (0...(usable - want.count)).filter { i in
                (0..<want.count).allSatisfy { norm(lines[i + $0]) == target[$0] }
            }
            if starts.count > 1 { return .many(starts) }
            guard let i = starts.first else { continue }
            var m = Match(lines: i..<(i + want.count), ignored: ignored, crlf: lines[i].hasSuffix("\r"))
            m.oldIndents = want.map(Match.indent)
            m.fileIndents = (i..<(i + want.count)).map { Match.indent(lines[$0]) }
            m.oldContent = want.map(strip)
            m.reindented = m.oldIndents != m.fileIndents
            return .one(m)
        }
        return nil
    }
}

extension LineDiff {
    /// The new text's changed lines with two lines around each, numbered as read_file numbers them; at most `limit`
    /// lines, with "…" between regions and where it stops.
    static func changedRegions(old: String, new: String, around: Int = 2, limit: Int = 60) -> String {
        changedRegions(compare(old: old, new: new), around: around, limit: limit)
    }

    /// The same from a comparison already made; empty when the change was too large to diff.
    static func changedRegions(_ c: Comparison, around: Int = 2, limit: Int = 60) -> String {
        let b = c.newLines
        guard !b.isEmpty, let ops = c.ops else { return "" }
        var changed: [Int] = []      // 0-based lines of the new text
        var j = 0
        for op in ops {
            switch op {
            case .same: j += 1
            case .added: changed.append(j); j += 1
            case .removed: changed.append(min(j, b.count - 1))
            }
        }
        var windows: [ClosedRange<Int>] = []
        for c in changed {
            let w = max(0, c - around)...min(b.count - 1, c + around)
            if let last = windows.last, w.lowerBound <= last.upperBound + 1 {
                windows[windows.count - 1] = last.lowerBound...max(last.upperBound, w.upperBound)
            } else { windows.append(w) }
        }
        var out: [String] = []
        var shown = 0
        for (k, w) in windows.enumerated() {
            if k > 0 { out.append("…") }
            for n in w {
                if shown == limit { out.append("…"); return out.joined(separator: "\n") + "\n" }
                let line = b[n].count > 300 ? String(b[n].prefix(300)) + "…" : b[n]
                out.append("\(n + 1)\t\(line)")
                shown += 1
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
