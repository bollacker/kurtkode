import Foundation

/// A session as a sequence of what happened, for debugging tool use: what the user sent, each model turn with the
/// tool calls it made and their results, compactions, and commands the user ran.
public enum TimelineItem: Identifiable, Sendable, Hashable {
    case user(ChatMessage)
    case turn(TurnEntry)
    case userCommand(ChatMessage)
    case compaction(Compaction)

    public var id: String {
        switch self {
        case .user(let m), .userCommand(let m): m.id.uuidString
        case .turn(let t): t.id.uuidString
        case .compaction(let c): "compaction-" + c.lastSummarizedID.uuidString
        }
    }
}

/// One model turn: the reply (with its reasoning and meta), and each tool call it made with the result.
public struct TurnEntry: Identifiable, Sendable, Hashable {
    public var reply: ChatMessage
    public var calls: [CallEntry]
    /// The turn's position among the session's model turns, from 1; 0 for files the user attached with @ (sent as
    /// calls and results, with no model behind them).
    public var number: Int
    public var id: UUID { reply.id }

    /// Something went wrong or was changed: shown as a badge.
    public var flags: [String] {
        var f: [String] = []
        let meta = reply.meta
        if AgentLoop.droppedCall(reply) { f.append("lost") }
        if meta?.stopReason != nil, meta?.stopReason != .completed { f.append(meta!.stopReason.rawValue) }
        if meta?.finishReason == .length { f.append("cut off") }
        if meta?.rawContent != nil { f.append("recovered") }
        if meta?.notes?.contains(where: { $0.hasPrefix("The reply was empty") }) == true { f.append("nudged") }
        if meta?.modelMismatch == true { f.append("other model") }
        if calls.contains(where: { $0.result?.toolResult?.isError == true }) { f.append("error") }
        if calls.contains(where: { !($0.result?.toolResult?.argumentProblems ?? []).isEmpty }) { f.append("bad arguments") }
        return f
    }
}

public struct CallEntry: Identifiable, Sendable, Hashable {
    public var call: ToolCall
    public var result: ChatMessage?
    public var id: String { call.id }
}

public enum SessionTimeline {
    /// The session's messages in order, with tool results joined to their calls.
    public static func items(_ session: Session) -> [TimelineItem] {
        let results = ChatMessage.resultsByReply(session.messages)
        let boundaries = Dictionary(session.compactions.map { ($0.lastSummarizedID, $0) }, uniquingKeysWith: { _, b in b })
        var out: [TimelineItem] = []
        var number = 0
        for m in session.messages {
            switch m.role {
            case .user:
                out.append(m.userCommand == nil ? .user(m) : .userCommand(m))
            case .assistant:
                if m.meta != nil { number += 1 }
                out.append(.turn(TurnEntry(reply: m, calls: m.toolCalls.map { CallEntry(call: $0, result: results[m.id]?[$0.id]) },
                                           number: m.meta == nil ? 0 : number)))
            case .tool, .system:
                break
            }
            if let c = boundaries[m.id] { out.append(.compaction(c)) }
        }
        return out
    }
}

/// Counts over a session, for a quick read of how its tool use went.
public struct SessionStats: Sendable, Hashable {
    public var turns = 0
    public var toolCalls = 0
    public var callsByTool: [String: Int] = [:]
    public var errorsByTool: [String: Int] = [:]
    public var badArguments = 0
    public var notRun = 0
    public var denied = 0
    public var lostReplies = 0
    public var nudges = 0
    public var recoveredTextCalls = 0
    public var compactions = 0
    public var promptTokens = 0
    /// Cache reads and writes, and the prompt tokens of the turns whose server reported them (the cached share's base).
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0
    public var cacheReportedPromptTokens = 0
    /// Reasoning shown against reasoning billed, over the turns whose server reported what it billed.
    public var reasoningShownTokens = 0
    public var reasoningBilledTokens = 0
    public var completionTokens = 0
    public var reasoningTokens = 0
    public var costByProvider: [String: Double] = [:]
    /// Every billed request of the session (its cost records): replies, summaries, retried attempts.
    public var cost = CostSummary()
    public var turnsByModel: [String: Int] = [:]
    /// The session's subagent runs (`add(subagents:)`), apart from the main agent's own counts.
    public var subagents = 0
    public var subagentToolCalls = 0
    public var subagentPromptTokens = 0
    public var subagentCompletionTokens = 0
    public var subagentCost = 0.0

    public init(_ session: Session) {
        compactions = session.compactions.count
        cost = CostSummary(session.costs)
        costByProvider = cost.byProvider
        for item in SessionTimeline.items(session) {
            guard case .turn(let t) = item, t.reply.meta != nil else { continue }
            turns += 1
            let meta = t.reply.meta
            turnsByModel[meta?.reportedModel ?? meta?.requestedModel ?? "?", default: 0] += 1
            if let u = meta?.usage {
                promptTokens += u.promptTokens
                if u.cacheReadTokens != nil || u.cacheWriteTokens != nil {
                    cacheReadTokens += u.cacheReadTokens ?? 0
                    cacheWriteTokens += u.cacheWriteTokens ?? 0
                    cacheReportedPromptTokens += u.promptTokens
                }
                completionTokens += u.completionTokens
                reasoningTokens += u.reasoningTokens
                let shown = ReasoningShown(t.reply)
                if let b = shown.billedTokens {
                    reasoningBilledTokens += b
                    reasoningShownTokens += Int((shown.shownShare ?? 0) * Double(b))
                }

            }
            if AgentLoop.droppedCall(t.reply) { lostReplies += 1 }
            if meta?.notes?.contains(where: { $0.hasPrefix("The reply was empty") }) == true { nudges += 1 }
            if meta?.rawContent != nil { recoveredTextCalls += t.calls.count }
            for c in t.calls {
                toolCalls += 1
                callsByTool[c.call.name, default: 0] += 1
                guard let info = c.result?.toolResult else { continue }
                if info.isError { errorsByTool[c.call.name, default: 0] += 1 }
                if !(info.argumentProblems ?? []).isEmpty { badArguments += 1 }
                if info.notes?.contains(where: { $0.hasPrefix("Not run") }) == true { notRun += 1 }
                if info.denied == true { denied += 1 }
            }
        }
    }

    public var errors: Int { errorsByTool.values.reduce(0, +) }
}

/// How one request differs from the one before it. The server reuses its prompt cache up to the first difference,
/// so where that is says how much it had to process again.
public struct WireDiff: Sendable, Hashable {
    public var systemChanged: Bool
    public var toolsChanged: Bool
    public var modelChanged: Bool
    /// Messages identical from the start (the system prompt included, when it's the first message).
    public var commonPrefix: Int
    public var previousCount: Int
    public var currentCount: Int

    public init(previous: WireRecord, current: WireRecord) {
        func field(_ r: WireRecord, _ k: String) -> JSONValue? {
            if case .object(let o) = r.request { return o[k] }
            return nil
        }
        let a = previous.messages, b = current.messages
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        commonPrefix = i
        previousCount = a.count
        currentCount = b.count
        systemChanged = a.first.map { Self.role($0) == "system" } == true && b.first.map { Self.role($0) == "system" } == true && a.first != b.first
        toolsChanged = field(previous, "tools") != field(current, "tools")
        modelChanged = field(previous, "model") != field(current, "model")
    }

    static func role(_ m: JSONValue) -> String? {
        if case .object(let o) = m, case .string(let r)? = o["role"] { return r }
        return nil
    }

    /// One line: what changed, and whether the cached prefix could be reused.
    public var summary: String {
        var parts: [String] = []
        if modelChanged { parts.append("another model (no cache)") }
        if systemChanged { parts.append("the system prompt changed (no cache)") }
        if toolsChanged { parts.append("the tool definitions changed") }
        if commonPrefix == previousCount {
            parts.append("adds \(currentCount - previousCount) message\(currentCount - previousCount == 1 ? "" : "s") to the previous request")
        } else {
            parts.append("first \(commonPrefix) of \(previousCount) earlier messages unchanged; differs from message \(commonPrefix + 1)")
        }
        return parts.joined(separator: "; ")
    }
}
