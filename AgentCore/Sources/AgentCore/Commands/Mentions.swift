import Foundation

/// `@path` in a user message: the file (or folder) goes into the conversation as a read_file (or list_dir)
/// call and its result, placed right after the message. That reuses the tools' confinement, line numbers,
/// truncation, and binary handling; the transcript shows an ordinary tool card; and progress tracking
/// counts the file as read.
public enum Mentions {
    public struct Mention: Sendable, Hashable {
        /// Relative to the project root.
        public var path: String
        public var isDirectory: Bool
    }

    /// At most this many mentions per message are attached.
    public static let limit = 10

    /// `@` tokens in `text` that name existing files or folders inside the workspace, in order, once each.
    public static func find(in text: String, workspace: Workspace) -> [Mention] {
        var out: [Mention] = []
        for token in tokens(text) {
            // Trailing punctuation belongs to the sentence ("see @calc.py."), unless the file has it.
            var candidates = [token]
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}'\""))
            if trimmed != token, !trimmed.isEmpty { candidates.append(trimmed) }
            for c in candidates {
                guard let url = try? workspace.resolve(c) else { continue }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
                let m = Mention(path: workspace.relative(url), isDirectory: isDir.boolValue)
                if !out.contains(m) { out.append(m) }
                break
            }
            if out.count == limit { break }
        }
        return out
    }

    /// `@word` at the start or after whitespace or an opening bracket (so a@b.com isn't one), or `@"a b"`.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            defer { i += 1 }
            guard chars[i] == "@", i == 0 || chars[i - 1].isWhitespace || "([{".contains(chars[i - 1]) else { continue }
            var j = i + 1
            if j < chars.count, chars[j] == "\"" {
                j += 1
                let start = j
                while j < chars.count, chars[j] != "\"" { j += 1 }
                if j < chars.count, j > start { out.append(String(chars[start..<j])) }
                i = j
                continue
            }
            let start = j
            while j < chars.count, !chars[j].isWhitespace { j += 1 }
            if j > start { out.append(String(chars[start..<j])) }
            i = j - 1
        }
        return out
    }

    /// The assistant turn with one call per mention, and the calls' results, ready to append after the
    /// user's message.
    public static func messages(for mentions: [Mention], workspace: Workspace, shell: ShellState? = nil,
                                maxOutputBytes: Int = 16_000) async -> [ChatMessage] {
        guard !mentions.isEmpty else { return [] }
        let tag = UUID().uuidString.prefix(8).lowercased()
        let calls = mentions.enumerated().map { i, m in
            ToolCall(id: "at_\(tag)_\(i)", name: m.isDirectory ? "list_dir" : "read_file",
                     arguments: TextToolCalls.encode(.object(["path": .string(m.path)])))
        }
        var out = [ChatMessage(role: .assistant, content: "", toolCalls: calls)]
        let context = ToolContext(workspace: workspace, maxOutputBytes: maxOutputBytes, shell: shell)
        for (call, m) in zip(calls, mentions) {
            let tool: any Tool = m.isDirectory ? ListDirTool() : ReadFileTool()
            let start = Date()
            let output: ToolOutput
            do { output = try await tool.run(ToolArguments(["path": .string(m.path)]), context: context) }
            catch let f as ToolFailure { output = .error(f.message) }
            catch { output = .error(error.localizedDescription) }
            out.append(ChatMessage(role: .tool, content: output.text, toolCallID: call.id,
                                   toolResult: ToolResultInfo(toolName: call.name, isError: output.isError,
                                                              truncated: output.truncated,
                                                              duration: Date().timeIntervalSince(start),
                                                              display: output.display)))
        }
        return out
    }

    /// Paths (files, and folders ending in /) matching a partial `@` token: file names starting with it
    /// first, then path components starting with it, then any substring; shorter paths first in each group.
    public static func completions(_ partial: String, files: [String], limit: Int = 12) -> [String] {
        var all = Set(files)
        for f in files {
            var dir = (f as NSString).deletingLastPathComponent
            while !dir.isEmpty, dir != "." {
                all.insert(dir + "/")
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        let q = partial.lowercased()
        func name(_ p: String) -> String {
            let t = p.hasSuffix("/") ? String(p.dropLast()) : p
            return (t as NSString).lastPathComponent.lowercased()
        }
        func rank(_ p: String) -> Int? {
            let lower = p.lowercased()
            if q.isEmpty { return p.contains("/") && !p.hasSuffix("/") ? 1 : 0 }
            if lower.hasPrefix(q) || name(p).hasPrefix(q) { return 0 }
            if lower.split(separator: "/").contains(where: { $0.hasPrefix(q) }) { return 1 }
            if lower.contains(q) { return 2 }
            return nil
        }
        var ranked: [(path: String, rank: Int)] = []
        for p in all { if let r = rank(p) { ranked.append((p, r)) } }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }
        return ranked.prefix(limit).map(\.path)
    }
}
