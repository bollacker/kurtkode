import CEditLine
import Darwin
import Foundation

/// What was typed at the prompt, kept across runs. One JSON string per line in the file, so an entry can span
/// several lines. Like a shell: empty lines, repeats of the last entry, and lines that start with a space
/// aren't kept.
public struct InputHistory: Sendable {
    public let fileURL: URL
    public let limit: Int
    public private(set) var entries: [String]

    public init(fileURL: URL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        entries = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(String.self, from: Data($0.utf8)) }.suffix(limit)
    }

    /// Adds an entry; false if it isn't kept.
    @discardableResult
    public mutating func add(_ entry: String) -> Bool {
        guard !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !entry.hasPrefix(" "), entry != entries.last else { return false }
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        return true
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = entries.compactMap { (try? JSONEncoder().encode($0)).map { String(decoding: $0, as: UTF8.self) } }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: fileURL, options: .atomic)
    }
}

/// Reads lines at the prompt: with editing, history (↑/↓, Ctrl-R), and Tab completion of /commands and @paths
/// when stdin is a terminal (macOS's libedit); plain `readLine` when it isn't (piped input). A line ending in
/// a backslash continues on the next one.
public final class LineEditor: @unchecked Sendable {
    /// Completions for the word being typed: (word, whole line, where the word starts) → candidates.
    public typealias Completer = @Sendable (_ word: String, _ line: String, _ start: Int) -> [String]

    public let isTerminal: Bool
    private var history: InputHistory?
    private let lock = NSLock()

    /// libedit calls a C function to complete, with no context pointer: the one editor in the process is global.
    nonisolated(unsafe) static var completer: Completer?
    nonisolated(unsafe) static var matches: [String] = []

    public init(history: InputHistory?, completer: Completer?, isTerminal: Bool = isatty(STDIN_FILENO) == 1) {
        self.isTerminal = isTerminal
        self.history = history
        guard isTerminal else { return }
        Self.completer = completer
        kk_editline_setup(strdup("kurtkode"), { text, start, _ in
            kk_completion_over()
            guard let text, let complete = LineEditor.completer else { return nil }
            let line = String(cString: kk_line_buffer())
            LineEditor.matches = complete(String(cString: text), line, Int(start))
            guard !LineEditor.matches.isEmpty else { return nil }
            // A folder gets no space after it, so the path can go on.
            kk_completion_append(LineEditor.matches.count == 1 && LineEditor.matches[0].hasSuffix("/") ? 0 : 32)
            return rl_completion_matches(text) { _, state in
                Int(state) < LineEditor.matches.count ? strdup(LineEditor.matches[Int(state)]) : nil
            }
        })
        for entry in history?.entries ?? [] { add_history(entry) }
    }

    /// Reads one entry (a line, or several joined by trailing backslashes). Nil at end of input (Ctrl-D).
    /// `prompt` may contain terminal escapes; they're marked so the editor doesn't count them as width.
    public func read(prompt: String, continuation: String = "… ", remember: Bool = true) -> String? {
        var lines: [String] = []
        while true {
            guard let line = readOne(lines.isEmpty ? prompt : continuation) else {
                return lines.isEmpty ? nil : lines.joined(separator: "\n")
            }
            if line.hasSuffix("\\"), !line.hasSuffix("\\\\") {
                lines.append(String(line.dropLast()))
                continue
            }
            lines.append(line)
            break
        }
        let entry = lines.joined(separator: "\n")
        guard remember else { return entry }
        lock.withLock {
            if history?.add(entry) == true {
                if isTerminal { add_history(entry) }
                try? history?.save()
            }
        }
        return entry
    }

    private func readOne(_ prompt: String) -> String? {
        guard isTerminal else {
            _ = try? FileHandle.standardOutput.write(contentsOf: Data(prompt.utf8))
            return readLine()
        }
        guard let p = readline(Self.markEscapes(prompt)) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    /// Ends a read in progress, as if Enter were pressed (a no-op when stdin isn't a terminal).
    public func interrupt() {
        guard isTerminal else { return }
        _ = kk_push_newline()
    }

    /// Wraps each terminal escape sequence in \1…\2, readline's "takes no space" markers.
    static func markEscapes(_ prompt: String) -> String {
        var out = ""
        var inEscape = false
        for ch in prompt {
            if ch == "\u{1B}" { out += "\u{1}"; inEscape = true }
            out.append(ch)
            if inEscape, ch.isLetter { out += "\u{2}"; inEscape = false }
        }
        return out
    }

    /// Completions for the kurtkode prompt: /commands at the start of the line, and project paths after @.
    public static func completions(commands: @escaping @Sendable () -> [String], files: @escaping @Sendable () -> [String]) -> Completer {
        { word, line, start in
            let before = line.utf8.prefix(start)
            if start == 0, word.hasPrefix("/") {
                return commands().map { "/" + $0 }.filter { $0.hasPrefix(word) }.sorted()
            }
            guard before.last == UInt8(ascii: "@") else { return [] }
            // Files whose path starts with the word, and the folders on the way to them (one level at a time).
            var out = Set<String>()
            for f in files() where f.hasPrefix(word) {
                let rest = f.dropFirst(word.count)
                if let slash = rest.firstIndex(of: "/") { out.insert(word + rest[..<slash] + "/") } else { out.insert(f) }
            }
            return out.sorted()
        }
    }
}

/// The history file, from the live screen's thread.
public final class HistoryKeeper: @unchecked Sendable {
    private let lock = NSLock()
    private var history: InputHistory

    public init(_ history: InputHistory) { self.history = history }

    public var entries: [String] { lock.withLock { history.entries } }

    public func add(_ entry: String) {
        lock.withLock {
            if history.add(entry) { try? history.save() }
        }
    }
}
