import Foundation

/// A row of the chat transcript: a message, or several replies that only looked around, shown as one line.
public enum TranscriptRow: Sendable, Hashable, Identifiable {
    case message(ChatMessage)
    /// Consecutive replies with no text of their own whose calls only read. The id is the first one's, so a row keeps
    /// its identity as its group grows.
    case tools([ChatMessage])

    public var id: UUID {
        switch self {
        case .message(let m): m.id
        case .tools(let ms): ms[0].id
        }
    }

    public var messages: [ChatMessage] {
        switch self {
        case .message(let m): [m]
        case .tools(let ms): ms
        }
    }

    /// Calls that don't change anything and have nothing to read in them: they fold into a group. Not `bash` (its
    /// command is the point) and not `task` (a subagent's report is).
    static let quietTools: Set<String> = ["read_file", "list_dir", "glob", "grep", "todo_write", "skill"]

    /// A reply that can join a group: tool calls only, all quiet, none denied, and nothing to say about how it ended.
    static func isQuiet(_ m: ChatMessage, results: [String: ChatMessage]) -> Bool {
        guard m.role == .assistant, !m.toolCalls.isEmpty, m.content.allSatisfy(\.isWhitespace),
              m.toolCalls.allSatisfy({ quietTools.contains($0.name) }),
              !m.toolCalls.contains(where: { results[$0.id]?.toolResult?.denied == true }) else { return false }
        guard let meta = m.meta else { return true }
        return meta.stopReason == .completed && meta.error == nil && !meta.modelMismatch && meta.finishReason != .length
    }

    /// The rows for `messages` (tool results are shown in their call's card, so they get none). `breakAfter` ends a
    /// group: something is drawn after that message. A lone call stays a plain message.
    public static func rows(_ messages: [ChatMessage], results: [UUID: [String: ChatMessage]],
                            breakAfter: (ChatMessage) -> Bool = { _ in false }) -> [TranscriptRow] {
        var out: [TranscriptRow] = []
        var group: [ChatMessage] = []
        func flush() {
            if group.count == 1, group[0].toolCalls.count == 1 { out.append(.message(group[0])) }
            else if !group.isEmpty { out.append(.tools(group)) }
            group = []
        }
        for m in messages where m.role != .tool {
            if isQuiet(m, results: results[m.id] ?? [:]) {
                group.append(m)
                if breakAfter(m) { flush() }
            } else {
                flush()
                out.append(.message(m))
            }
        }
        flush()
        return out
    }
}

/// The one line that stands for a group of quiet calls: "Read 3 files, searched 2 times".
public enum ToolGroupSummary {
    public static func text(_ calls: [ToolCall]) -> String {
        var files = Set<String>(), reads = 0, searches = 0, folders = 0, skills = 0, todos = 0
        for c in calls {
            switch c.name {
            case "read_file":
                reads += 1
                if let p = (try? ToolArguments(json: c.arguments))?.string("path") { files.insert(p) }
            case "grep", "glob": searches += 1
            case "list_dir": folders += 1
            case "skill": skills += 1
            case "todo_write": todos += 1
            default: break
            }
        }
        // The same file read in parts is one file; calls with arguments that can't be read still count.
        let read = max(files.count, reads == 0 ? 0 : 1)
        var parts: [String] = []
        if read > 0 { parts.append("Read \(read) file\(read == 1 ? "" : "s")") }
        if searches > 0 { parts.append("searched \(searches) time\(searches == 1 ? "" : "s")") }
        if folders > 0 { parts.append("listed \(folders) folder\(folders == 1 ? "" : "s")") }
        if skills > 0 { parts.append("loaded \(skills) skill\(skills == 1 ? "" : "s")") }
        if todos > 0 { parts.append("updated the todo list") }
        guard let first = parts.first else { return "\(calls.count) calls" }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: ", ")
    }
}

/// Find in a chat: which messages hold the text. A tool's result counts as the reply that called it.
public enum TranscriptSearch {
    /// Ids of the user and assistant messages that match, in order, each once.
    public static func hits(_ messages: [ChatMessage], query: String) -> [UUID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        func has(_ text: String?) -> Bool { text?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        var results: [UUID: [ChatMessage]] = [:]
        for (reply, byCall) in ChatMessage.resultsByReply(messages) { results[reply] = Array(byCall.values) }
        return messages.filter { m in
            switch m.role {
            case .user:
                return m.contextNote != true && (has(m.content) || has(m.userCommand?.output))
            case .assistant:
                return has(m.content) || has(m.reasoning) || m.toolCalls.contains { has($0.arguments) }
                    || (results[m.id] ?? []).contains { has($0.content) }
            default:
                return false
            }
        }.map(\.id)
    }
}

extension Session {
    /// What the user asked for, oldest first, with repeats in a row left out: for ↑ in the composer.
    public var prompts: [String] {
        var out: [String] = []
        for m in messages where m.role == .user && m.contextNote != true && m.subagentReport == nil {
            let text = m.userCommand.map { "!" + $0.command } ?? m.content
            if !text.isEmpty, text != out.last { out.append(text) }
        }
        return out
    }

    /// What the model still has: the messages after the last compaction's summary.
    public var messagesInContext: [ChatMessage] {
        guard let id = compactions.last?.lastSummarizedID, let i = messages.firstIndex(where: { $0.id == id }) else { return messages }
        return Array(messages[(i + 1)...])
    }

    /// The conversation stops where a reply was due, and no run ended after it: kurtkode quit or crashed mid-run. A run
    /// that was stopped, paused at a limit or failed leaves a record, so it doesn't count.
    public var wasInterrupted: Bool {
        // A fork's copied messages: no run of this session was meant to answer them.
        guard let last = messages.last(where: { $0.contextNote != true }), last.userCommand == nil,
              header.forkedFrom == nil || last.createdAt > header.createdAt else { return false }
        let replyDue = switch last.role {
        case .user, .tool: true
        case .assistant: !last.toolCalls.isEmpty
        default: false
        }
        guard replyDue else { return false }
        return !runs.contains { $0.agent == "main" && $0.ended >= last.createdAt }
    }
}
