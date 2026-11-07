import Foundation

/// How much of the model's context a session may use before compacting.
///
/// Measured on LM Studio (Qwen3-Coder 30B, M1 Max): re-processing a 24k-token prompt took 122 s; the same
/// prompt from the cache took 0.5 s. So context is managed in rare, large steps: never trim a little at a
/// time, since any change to earlier messages throws away the cache for everything after it.
public struct ContextBudget: Sendable, Hashable {
    /// The model's context length in tokens.
    public var limit: Int
    /// Compact when the next prompt would pass this fraction of `limit` (after reserving output room).
    public var compactAt: Double
    /// Recent messages kept verbatim after compacting, as a fraction of `limit`.
    public var keepFraction: Double
    /// Room held back for the reply.
    public var outputReserve: Int

    public init(limit: Int, compactAt: Double = 0.7, keepFraction: Double = 0.2, outputReserve: Int = 4096) {
        self.limit = limit
        self.compactAt = compactAt
        self.keepFraction = keepFraction
        self.outputReserve = min(outputReserve, limit / 4)
    }

    public var compactThreshold: Int { Int(Double(limit) * compactAt) - outputReserve }
    /// How far below the threshold trimming tool outputs aims, so it doesn't happen again on the next turn.
    var trimHeadroom: Int { limit / 4 }
    var keepBudget: Int { Int(Double(limit) * keepFraction) }
}

/// A summary that stands in for the start of a session.
public struct Compaction: Codable, Sendable, Hashable {
    public var summary: String
    /// The summary covers messages up to and including this one.
    public var lastSummarizedID: UUID
    /// When the kept messages don't start with a user message, this user turn is inserted before them.
    public var continuation: String?
    /// The newest kept message whose tool output a compaction may have trimmed: the last one before the model's latest
    /// reply at compaction time (outputs after that reply hadn't been read yet, so they were kept whole). Tool outputs
    /// from the boundary through here were trimmed, and later prompts trim them the same way so they match what the
    /// model saw. Nil when nothing kept was trimmed.
    public var lastKeptID: UUID?
    public var tokensBefore: Int
    public var tokensAfter: Int
    public var date: Date
    /// Tracked progress at compaction time (cumulative over the session).
    public var facts: SessionFacts?
    /// The summary requests in the wire log (the cached one, then the fallback if it was needed), by record id.
    public var summaryRequests: [UUID]?

    public init(summary: String, lastSummarizedID: UUID, continuation: String?, lastKeptID: UUID? = nil,
                tokensBefore: Int, tokensAfter: Int, date: Date = Date(), facts: SessionFacts? = nil) {
        self.summary = summary
        self.lastSummarizedID = lastSummarizedID
        self.continuation = continuation
        self.lastKeptID = lastKeptID
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.date = date
        self.facts = facts
    }

    /// The text the model sees for this compaction: its summary, then the tracked progress.
    public var modelText: String {
        let f = facts?.rendered() ?? ""
        return f.isEmpty ? summary : summary + "\n\n" + f
    }

    /// Appended to the system prompt. (A separate message would break templates that require
    /// strictly alternating user and assistant turns, such as Gemma's.)
    public static func systemSection(_ summary: String) -> String {
        "# Summary of the earlier conversation\n\nThe start of this session was summarized to save context. "
            + "Continue from it.\n\n" + summary
    }
}

/// What a /compact came to.
public enum ManualCompaction: Sendable {
    case done(Compaction)
    /// A summary wouldn't make the prompt smaller: predicted before asking (no request made), or measured on the
    /// summary that came back (it was dropped). Token counts are the whole prompt's.
    case noSaving(before: Int, after: Int, measured: Bool)
    /// No usable summary came back.
    case failed

    public var compaction: Compaction? { if case .done(let c) = self { c } else { nil } }

    /// What to tell the user when nothing was summarized.
    public var explanation: String? {
        switch self {
        case .done: nil
        case .noSaving(let before, let after, measured: false):
            "Not summarized: the conversation is about \(before) tokens with the system prompt and tools, and a summary "
                + "would leave about \(after). Nothing to gain yet."
        case .noSaving(let before, let after, measured: true):
            "Not summarized: the summary came out longer than what it would replace (about \(before) → \(after) tokens), "
                + "so the conversation stays as it is."
        case .failed: "Couldn't summarize the conversation: the model didn't return a usable summary."
        }
    }
}

/// Token estimates from byte counts, calibrated against the server's reported prompt sizes.
public struct TokenEstimator: Sendable {
    /// Bytes per token; code and JSON run about 3–3.5.
    public var bytesPerToken: Double = 3.3

    public init() {}

    public func tokens(_ messages: [ChatMessage], tools: [ToolDefinition] = []) -> Int {
        Int(Double(Self.bytes(messages, tools: tools)) / bytesPerToken)
    }

    public mutating func calibrate(bytes: Int, promptTokens: Int) {
        guard promptTokens > 200, bytes > 0 else { return }
        let observed = Double(bytes) / Double(promptTokens)
        bytesPerToken = min(6, max(1.5, observed))
    }

    /// Roughly what the chat template renders: content, tool-call JSON, and per-message overhead.
    public static func bytes(_ messages: [ChatMessage], tools: [ToolDefinition] = []) -> Int {
        var n = 0
        for m in messages {
            n += 12 + m.content.utf8.count + (m.images?.count ?? 0) * ImageStore.estimatedBytes
            for c in m.toolCalls { n += 40 + c.name.utf8.count + c.arguments.utf8.count }
        }
        if !tools.isEmpty, let json = try? JSONEncoder().encode(tools.map { JSONValue.object(["name": .string($0.name),
                                                                                    "description": .string($0.description),
                                                                                    "parameters": $0.parameters]) }) {
            n += json.count
        }
        return n
    }
}

/// Ids of the requests a step made (summary requests, for the wire log's links).
final class RequestIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [UUID] = []
    func add(_ id: UUID) { lock.withLock { list.append(id) } }
    var ids: [UUID] { lock.withLock { list } }
}

public enum Compactor {
    /// Summarizes a whole conversation on request (/compact). Sends the same system prompt, history, and
    /// tools as the agent would, plus the instruction, so the server can reuse its cache.
    /// `extraInstructions` lets the user say what to focus on. With `contextLimit` the summary gets the output room
    /// the context leaves (`summaryMaxTokens`), as in the loop; without it, 1,500 tokens.
    /// `systemPrompt` is the prompt as sent (with an earlier summary, if any); `baseSystemPrompt` is the prompt
    /// without one, which the new summary goes into. Like the loop's compaction, it predicts the result first and
    /// doesn't ask when a summary couldn't make the prompt smaller (a short chat: seen 1k → 2k tokens), and it
    /// drops a summary that came back longer than what it replaces.
    public static func compactAll(client: ChatClient, model: String, systemPrompt: String, baseSystemPrompt: String? = nil,
                                  history: [ChatMessage], tools: [any Tool], limits: TurnLimits,
                                  extraInstructions: String? = nil, facts: SessionFacts? = nil,
                                  shape: HistoryShape = HistoryShape(), thinking: Bool = true, cacheForAnHour: Bool = false,
                                  cacheKey: String? = nil, contextLimit: Int? = nil, costs: CostSink? = nil,
                                  wire: WireLog? = nil) async -> ManualCompaction {
        guard let last = history.last(where: { !AgentLoop.isContinuation($0) }) else { return .failed }
        let base = baseSystemPrompt ?? systemPrompt
        let messages = [ChatMessage.system(systemPrompt)] + AgentLoop.sendable(history)
        let defs = tools.map(\.definition)
        let estimator = TokenEstimator()
        let before = estimator.tokens(messages, tools: defs)
        func after(_ summaryText: String) -> Int {
            estimator.tokens([.system(base + (base.isEmpty ? "" : "\n\n") + Compaction.systemSection(summaryText))], tools: defs)
        }
        let factsText = facts.flatMap { $0.isEmpty ? nil : $0.rendered() } ?? ""
        let words = summaryWords(limit: contextLimit)
        let reserve = String(repeating: "x", count: summaryReserveBytes(words: words))
        let predicted = after(factsText.isEmpty ? reserve : reserve + "\n\n" + factsText)
        guard predicted < before else { return .noSaving(before: before, after: predicted, measured: false) }
        var instructionHistory = messages
        if let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            instructionHistory.append(.user("When you summarize, focus on: \(extra)"))
            instructionHistory.append(ChatMessage(role: .assistant, content: "Understood."))
        }
        let recorded = RequestIDs()
        guard let summary = await summarize(client: client, model: model, messages: instructionHistory, tools: defs,
                                            limits: limits,
                                            maxTokens: contextLimit.map { summaryMaxTokens(limit: $0, promptTokens: estimator.tokens(instructionHistory, tools: defs)) } ?? 1500,
                                            shape: shape, thinking: thinking, cacheForAnHour: cacheForAnHour, cacheKey: cacheKey,
                                            costs: costs, wire: wire, recorded: recorded, words: words) else { return .failed }
        var c = Compaction(summary: summary, lastSummarizedID: last.id, continuation: nil,
                           tokensBefore: before, tokensAfter: 0,
                           facts: facts.flatMap { $0.isEmpty ? nil : $0 })
        c.summaryRequests = recorded.ids.isEmpty ? nil : recorded.ids
        c.tokensAfter = after(c.modelText)
        guard c.tokensAfter < before else { return .noSaving(before: before, after: c.tokensAfter, measured: true) }
        return .done(c)
    }

    /// The summary request (B7): sections that keep what a continuation needs (the user's words, the step in
    /// progress, errors, the test state), in a length that suits the context.
    static func summaryInstruction(words: Int = 400) -> String {
        """
        Summarize this session so far so the work can continue with only your summary as context. \
        Stop working on the task for this one reply: do not call tools and do not continue the work. \
        Start your reply with the line "## Summary", then fill in these sections in Markdown, under \(words) words in \
        all (leave out a section that would be empty):

        ### Requests
        Every request the user made, in order, quoted word for word where the wording carries instructions or \
        constraints. The latest one last.
        ### Done
        What is finished, with the files changed (path and what changed).
        ### Current step
        What you were doing when this summary was asked for, and exactly where you stopped.
        ### Decisions and constraints
        Choices made and why, and rules to keep (from the user, the project, or what you found).
        ### Errors and fixes
        Errors you met, their causes, and how each was fixed, or that it's still open.
        ### Tests and checks
        The last test or build command you ran and its result (passed or failed, counts, failing names).
        ### Next step
        The very next action, specific enough to start on without reading anything again.

        Include any earlier summary's content that still matters.
        """
    }

    /// How long a summary may be: longer as the context allows (a 16k context keeps the old ~400 words).
    static func summaryWords(limit: Int?) -> Int {
        guard let limit else { return 400 }
        switch limit {
        case ..<20_000: return 400
        case ..<48_000: return 550
        case ..<120_000: return 750
        default: return 900
        }
    }

    /// Where to cut: messages before `index` get summarized; from `index` on are kept. Keeps as many recent
    /// messages as fit in `keepTokens` (sized as they'll be kept, with answered tool outputs trimmed and the newest
    /// results, which the model hasn't read yet, whole), never separating a tool result from the assistant call
    /// before it. The newest group is always kept, so a run in progress still has its latest step. `continuation`
    /// is true when the kept part doesn't start with a user message.
    static func cut(_ history: [ChatMessage], keepTokens: Int, estimator: TokenEstimator) -> (index: Int, continuation: Bool) {
        var index = history.count
        var used = 0
        var i = history.count - 1
        let unseen = history.lastIndex(where: { $0.role == .assistant }) ?? history.count
        while i >= 0 {
            // Take a whole group: an assistant message with its tool results, or a single message.
            var start = i
            while start > 0, history[start].role == .tool { start -= 1 }
            let group = start >= unseen ? Array(history[start...i]) : trimKept(Array(history[start...i]))
            let cost = estimator.tokens(group)
            if used + cost > keepTokens, index < history.count { break }
            used += cost
            index = start
            if history[start].role == .user { break }     // a user turn is a natural boundary
            i = start - 1
        }
        // Summarize at least something, and never start the kept part on an orphaned tool result.
        if index == 0 { index = min(1, history.count) }
        while index < history.count, history[index].role == .tool { index += 1 }
        let continuation = index < history.count ? history[index].role != .user : false
        return (index, continuation)
    }

    /// Tool outputs in the kept part are trimmed: they were already acted on, and the summary covers them. Not the
    /// results after the model's latest reply, which it hasn't read yet: `plan` and `compact` use `trimAnswered`.
    /// Trimming again at the same size leaves a message as it is (its truncation note fits in the slack), so
    /// repeated trims don't change earlier messages and the prompt cache holds.
    static func trimKept(_ messages: [ChatMessage], maxToolBytes: Int = 4000,
                         hint: String = "Trimmed when the session was compacted.") -> [ChatMessage] {
        messages.map { m in
            guard m.role == .tool, m.content.utf8.count > maxToolBytes + 200 else { return m }
            var t = m
            let (head, _) = capOutput(m.content, maxBytes: maxToolBytes, hint: hint)
            t.content = head
            return t
        }
    }

    /// Room held for the model's summary when predicting a compaction's result: 2,600 bytes at 400 words (measured
    /// 1.1–2.0 KB with Gemma 4 26B, growing as it folds in earlier summaries), and as much more for longer ones.
    static func summaryReserveBytes(words: Int = 400) -> Int { words * 13 / 2 }

    /// What a compaction would leave, worked out before asking for a summary.
    struct Plan: Equatable {
        /// Messages of the body before this index get summarized.
        var index: Int
        var continuation: Bool
        /// The prompt afterwards: system prompt with summary and progress, tools, and the kept messages.
        var predictedTokens: Int
    }

    /// Plans a compaction of `body` (the conversation without its system prompt). The kept part is sized from
    /// the room the threshold leaves after the fixed part (base system prompt, tools, summary, progress): at
    /// most half of it, so there's space to work before the next compaction, and never more than the budget's
    /// keep fraction. (Sizing it from the limit alone kept everything in a 9k context, where the system prompt
    /// and tools took two thirds of the prompt: the summary replaced only the user's message and the prompt grew.)
    static func plan(body: [ChatMessage], baseSystem: String, facts: SessionFacts?, previousSummaryBytes: Int,
                     tools: [ToolDefinition], budget: ContextBudget, estimator: TokenEstimator) -> Plan {
        let reserve = String(repeating: "x", count: max(summaryReserveBytes(words: summaryWords(limit: budget.limit)), previousSummaryBytes))
        let factsText = facts?.rendered() ?? ""
        let section = Compaction.systemSection(factsText.isEmpty ? reserve : reserve + "\n\n" + factsText)
        let fixed = estimator.tokens([.system(baseSystem + (baseSystem.isEmpty ? "" : "\n\n") + section)], tools: tools)
        let keepTokens = min(budget.keepBudget, max(0, (budget.compactThreshold - fixed) / 2))
        let (index, continuation) = cut(body, keepTokens: keepTokens, estimator: estimator)
        var kept = trimAnswered(Array(body[index...]), maxToolBytes: 4000)
        if continuation { kept.insert(.user(continuationText), at: 0) }
        return Plan(index: index, continuation: continuation, predictedTokens: fixed + estimator.tokens(kept))
    }

    /// The note on a result cut as a last resort, when the newest results alone overflowed the context.
    static let oversizeHint = "This result was too big for the context and was cut before you could read it. "
        + "Read it in parts (offset and limit, or a narrower search) rather than making the same call again."

    /// A compaction must save at least this much to be worth a summary request and a cold prompt cache.
    static func minimumSaving(_ budget: ContextBudget) -> Int { budget.limit / 10 }

    /// Answered tool outputs (all but those after the last assistant message, which the model hasn't seen yet)
    /// trimmed to `maxToolBytes`. What a compaction trims in the part it keeps, and the lighter step when compacting
    /// can't shrink the prompt.
    static func trimAnswered(_ messages: [ChatMessage], maxToolBytes: Int) -> [ChatMessage] {
        guard let last = messages.lastIndex(where: { $0.role == .assistant }) else { return messages }
        return trimKept(Array(messages[..<last]), maxToolBytes: maxToolBytes) + messages[last...]
    }

    /// Answered tool outputs trimmed oldest first, only until the prompt is `budget.trimHeadroom` below the compaction
    /// threshold (all of them, if it can't get there). Trimming every answered output whenever the prompt is over the
    /// threshold changed the history on every turn near the limit: each change makes the server process everything
    /// after it again (at 1.25× on Anthropic) and voids Claude's later thinking (seen: turns 2–4 read only the first
    /// 3,151 tokens from the cache). With room left, the next trim comes only after the session has grown again.
    /// Deterministic in the history: a later run trims the same old outputs the same way, then possibly more.
    /// Two passes: to 1,200 bytes, then (when that isn't enough) the oldest further, to 300.
    static func trimForHeadroom(_ messages: [ChatMessage], budget: ContextBudget, estimator: TokenEstimator,
                                tools: [ToolDefinition]) -> [ChatMessage] {
        guard let last = messages.lastIndex(where: { $0.role == .assistant }) else { return messages }
        let target = trimTarget(budget)
        var out = messages
        var size = estimator.tokens(out, tools: tools)
        for cap in [1200, 300] {
            for i in 0..<last where out[i].role == .tool {
                if size <= target { return out }
                let trimmed = trimKept([out[i]], maxToolBytes: cap)[0]
                guard trimmed.content.utf8.count < out[i].content.utf8.count else { continue }
                size -= estimator.tokens([out[i]]) - estimator.tokens([trimmed])
                out[i] = trimmed
            }
        }
        return out
    }

    /// Where trimming aims: `trimHeadroom` below the compaction threshold.
    static func trimTarget(_ budget: ContextBudget) -> Int {
        max(budget.compactThreshold / 2, budget.compactThreshold - budget.trimHeadroom)
    }

    /// When trimming may change the history: over the threshold, and, after a trim that couldn't make room (the
    /// prompt is mostly things trimming doesn't touch), only once the prompt has grown a tenth of the limit past what
    /// it left. Otherwise every turn would trim the output it just answered.
    /// Growth is measured in bytes: the token estimate is recalibrated from each reply, which would move the mark.
    struct TrimGate: Sendable {
        var nextAtBytes: Int?

        func allows(_ messages: [ChatMessage], tools: [ToolDefinition], _ estimator: TokenEstimator, _ budget: ContextBudget) -> Bool {
            estimator.tokens(messages, tools: tools) > budget.compactThreshold
                && TokenEstimator.bytes(messages, tools: tools) > (nextAtBytes ?? 0)
        }

        mutating func trimmed(_ messages: [ChatMessage], tools: [ToolDefinition], _ estimator: TokenEstimator, _ budget: ContextBudget) {
            let bytes = TokenEstimator.bytes(messages, tools: tools)
            nextAtBytes = estimator.tokens(messages, tools: tools) > Compactor.trimTarget(budget)
                ? bytes + Int(Double(budget.limit / 10) * estimator.bytesPerToken) : nil
        }
    }

    static let continuationText = "Continue the task from the summary above. My most recent messages are below."

    /// Output room for a summary: the summary itself is under 400 words, but a reasoning model thinks first
    /// (Gemma 4 26B used all of 1,500 tokens on two summary requests in a row, 67 s, and left no summary). As
    /// much as the context leaves after the prompt, from 1,500 to 4,000.
    static func summaryMaxTokens(limit: Int, promptTokens: Int) -> Int {
        max(1500, min(4000, limit - promptTokens - 256))
    }

    /// Asks the model for a summary by appending one instruction to the exact messages and tools the
    /// agent has been sending, so the server can reuse its prompt cache for everything before it. Unless
    /// `thinking`, it asks for no reasoning (`reasoning_effort: none`; on LM Studio that loses the cache when tools
    /// are offered). The fallback never has a cache to lose and is mostly reached when thinking used up the output
    /// room, so it always asks for none.
    /// With `wire`, each request and its response go to the wire log, and their ids to `recorded`.
    static func summarize(client: ChatClient, model: String, messages: [ChatMessage], tools: [ToolDefinition],
                          limits: TurnLimits, maxTokens: Int = 1500, shape: HistoryShape = HistoryShape(),
                          thinking: Bool = true, cacheForAnHour: Bool = false, cacheKey: String? = nil, meter: CostMeter? = nil,
                          costs: CostSink? = nil, wire: WireLog? = nil, recorded: RequestIDs? = nil, words: Int = 400) async -> String? {
        let summaryInstruction = Self.summaryInstruction(words: words)
        func send(_ request: ChatRequest, _ limits: TurnLimits, accepted: (ChatMessage) -> Bool) async -> ChatMessage {
            let tap = wire == nil ? nil : WireTap()
            let started = Date()
            let reply = await TurnRunner.run(client: client, request: request, limits: limits, tap: tap) { _ in }
            // A first try that isn't used (the plain fallback follows) is a summary attempt.
            if let entry = await costs?.record(reply, purpose: accepted(reply) ? .summary : .summaryAttempt, client: client, start: started) {
                meter?.add(entry)
            } else {
                meter?.add(reply.meta?.usage)
            }
            if let wire, let tap {
                await wire.write(tap.record(replyID: reply.id, startedAt: started, duration: Date().timeIntervalSince(started)))
                recorded?.add(reply.id)
            }
            return reply
        }
        var request = ChatRequest(model: model, messages: HistoryShaper.shape(messages + [.user(summaryInstruction)], for: shape),
                                  tools: tools, maxTokens: maxTokens, sendReasoning: shape.sendReasoning)
        request.cacheForAnHour = cacheForAnHour
        request.cacheKey = cacheKey             // the session's: it reads the cache the session's requests left
        // Claude's and Gemini's thinking counts against the output limit: room for it, beyond the summary itself.
        if client.api != .openai { request.maxTokens = max(maxTokens, 16_000) }
        // Not on Claude: a different effort voids its cached history (the whole session is read at full price), and
        // the newest models can't stop thinking anyway.
        if !thinking, client.api != .anthropic { request.reasoningEffort = "none" }
        var summaryLimits = limits
        summaryLimits.maxTokens = request.maxTokens
        func usable(_ r: ChatMessage) -> Bool {
            r.meta?.stopReason == .completed && r.toolCalls.isEmpty && looksLikeSummary(r.content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let reply = await send(request, summaryLimits, accepted: usable)
        let text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if usable(reply) { return text }
        guard reply.meta?.stopReason != .cancelled, !Task.isCancelled else { return nil }

        // Fallback: a plain transcript with no tools, cut to fit. Slower (no cache), but always works.
        request = ChatRequest(model: model,
                              messages: [.system("You summarize coding sessions."),
                                         .user(summaryInstruction + "\n\nThe session:\n\n" + transcript(messages, maxBytes: 40_000))],
                              maxTokens: maxTokens)
        request.reasoningEffort = "none"
        request.oneOff = true
        let retry = await send(request, summaryLimits) { _ in true }
        let t = retry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return retry.meta?.stopReason == .completed && t.count > 80 ? t : nil
    }

    /// A model in the middle of a task sometimes keeps working instead of summarizing ("Let me check the
    /// next file…"). The instruction asks for a "## Summary" heading; a reply without one near the top
    /// isn't a summary. Structural on purpose: no wording heuristics that fit one model's habits.
    static func looksLikeSummary(_ text: String) -> Bool {
        text.count > 80 && text.prefix(200).lowercased().contains("summary")
    }

    /// Plain-text rendering for the fallback summary, keeping the start and the most recent part.
    static func transcript(_ messages: [ChatMessage], maxBytes: Int) -> String {
        var parts: [String] = []
        for m in messages {
            switch m.role {
            case .system: parts.append("[system prompt]\n" + String(m.content.prefix(3000)))
            case .user: parts.append("USER: " + m.content)
            case .assistant:
                var s = "ASSISTANT: " + m.content
                for c in m.toolCalls { s += "\n(calls \(c.name) \(c.arguments.prefix(300)))" }
                parts.append(s)
            case .tool: parts.append("TOOL RESULT: " + String(m.content.prefix(600)))
            }
        }
        let text = parts.joined(separator: "\n\n")
        guard text.utf8.count > maxBytes else { return text }
        let bytes = Array(text.utf8)
        return String(decoding: bytes.prefix(maxBytes / 3), as: UTF8.self) + "\n\n[…]\n\n"
            + String(decoding: bytes.suffix(maxBytes * 2 / 3), as: UTF8.self)
    }

    /// The server rejected the prompt as longer than the model's context.
    static func isOverflowError(_ message: ChatMessage) -> Bool {
        guard message.meta?.stopReason == .failed, let e = message.meta?.error?.lowercased() else { return false }
        return e.contains("context length") || e.contains("context window") || e.contains("maximum context")
            || e.contains("too many tokens")
            || e.contains("prompt is too long")                                                   // Claude
            || (e.contains("input token count") && e.contains("exceeds the maximum number of tokens"))   // Gemini
    }
}

/// Progress facts kurtkode tracks itself from the tool history, so they survive compaction exactly,
/// whatever the model's summary says. (Seen: after several compactions a model re-read files it had
/// already done and never reached the rest, because its summaries didn't list them.)
public struct SessionFacts: Codable, Sendable, Hashable {
    public var filesRead: [String] = []
    public var filesChanged: [String: Int] = [:]      // path -> number of edits
    public var changeOrder: [String] = []
    public var todos: [TodoEntry] = []
    /// The last test, build or lint command run, and how it ended (B7).
    public var lastCheck: Check?

    public struct Check: Codable, Sendable, Hashable {
        public var command: String
        public var exitCode: Int32?
        public var timedOut: Bool?

        public var failed: Bool { timedOut == true || (exitCode ?? 0) != 0 }
    }

    public struct TodoEntry: Codable, Sendable, Hashable {
        public var content: String
        public var status: String
    }

    public init() {}

    /// Adds what successful tool calls in `messages` read, changed, and planned, and the last check command run.
    /// Paths are as the project names them (`root`: the project, so absolute paths in it count as relative ones).
    public mutating func absorb(_ messages: [ChatMessage], root: String? = nil) {
        let results = ChatMessage.resultsByReply(messages)
        func changed(_ path: String) {
            let p = Self.normalize(path, root: root)
            if filesChanged[p] == nil { changeOrder.append(p) }
            filesChanged[p, default: 0] += 1
        }
        for m in messages where m.role == .assistant {
            for c in m.toolCalls {
                guard let r = results[m.id]?[c.id], let args = try? ToolArguments(json: c.arguments) else { continue }
                // A failing test run is a result like any other: its exit code is what's kept.
                // Not a call that was refused or denied: it never ran, and an earlier real result stands.
                if c.name == "bash", args.bool("run_in_background") != true, let command = args.string("command"),
                   r.toolResult?.denied != true, !r.content.hasPrefix("Error:"), Self.isCheck(command) {
                    let first = command.split(separator: "\n").first.map(String.init) ?? command
                    lastCheck = Check(command: first.count > 200 ? String(first.prefix(197)) + "…" : first,
                                      exitCode: r.toolResult?.exitCode,
                                      timedOut: r.content.contains("[Timed out after") ? true : nil)
                }
                guard r.toolResult?.isError != true, !r.content.hasPrefix("Error:") else { continue }
                switch c.name {
                case "read_file":
                    if let p = (args.string("path") ?? args.string("file_path")).map({ Self.normalize($0, root: root) }),
                       !filesRead.contains(p) { filesRead.append(p) }
                case "edit_file":
                    if let p = try? EditFileTool.path(args) { changed(p) }
                case "write_file":
                    if let p = args.string("path") ?? args.string("file_path") { changed(p) }
                case "apply_patch":
                    for p in (try? PatchParser.parse(ApplyPatchTool.text(args)))?.flatMap(\.paths) ?? [] { changed(p) }
                case "todo_write":
                    if let items = try? TodoWriteTool.items(from: args) {
                        todos = items.map { TodoEntry(content: $0.content, status: $0.status.rawValue) }
                    }
                default: break
                }
            }
        }
    }

    public var isEmpty: Bool { filesRead.isEmpty && filesChanged.isEmpty && todos.isEmpty && lastCheck == nil }

    /// A path as the project names it: inside `root` relative to it, without "./", with "a/../b" as "b".
    static func normalize(_ path: String, root: String?) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if let root {
            let r = root.hasSuffix("/") ? String(root.dropLast()) : root
            for prefix in [r + "/", "/private" + r + "/"] where p.hasPrefix(prefix) { p = String(p.dropFirst(prefix.count)) }
        }
        let absolute = p.hasPrefix("/")
        var parts: [Substring] = []
        for c in p.split(separator: "/") {
            if c == "." || c.isEmpty { continue }
            if c == "..", let last = parts.last, last != ".." { parts.removeLast(); continue }
            parts.append(c)
        }
        let joined = parts.joined(separator: "/")
        return absolute ? "/" + joined : (joined.isEmpty ? "." : joined)
    }

    /// Whether a command line runs tests, a build, or a linter or type checker.
    static func isCheck(_ line: String) -> Bool {
        ShellSplit.commands(line).contains { raw in
            isCheck(words: ShellSplit.unwrap(raw.filter { !PermissionPolicy.isRedirection($0) }), written: raw)
        }
    }

    static func isCheck(words: [String], written: [String]) -> Bool {
        guard let first = words.first else { return false }
        let name = (first as NSString).lastPathComponent
        let rest = Array(words.dropFirst())
        let positional = rest.filter { !$0.hasPrefix("-") }
        // Asking a tool its version or for help isn't a check.
        if !rest.isEmpty, rest.allSatisfy({ ["--version", "-v", "-V", "--help", "-h", "version"].contains($0) }) { return false }
        // Runners in front of the real command: uv run pytest, npx jest, bundle exec rspec.
        let runners: [String: Int] = ["uv": 1, "poetry": 1, "pipenv": 1, "hatch": 1, "pdm": 1, "rye": 1, "bundle": 1,
                                      "npx": 0, "bunx": 0, "pnpx": 0]
        if let skip = runners[name], skip == 0 || ["run", "exec"].contains(rest.first ?? "") {
            let inner = Array(rest.dropFirst(skip)).drop { $0.hasPrefix("-") }
            if !inner.isEmpty { return isCheck(words: Array(inner), written: Array(inner)) }
        }
        if ["pnpm", "yarn"].contains(name), ["exec", "dlx"].contains(rest.first ?? "") {
            return isCheck(words: Array(rest.dropFirst()), written: Array(rest.dropFirst()))
        }
        let tools: Set<String> = ["pytest", "tox", "nox", "jest", "vitest", "mocha", "rspec", "ctest", "xcodebuild", "tsc",
                                  "eslint", "mypy", "flake8", "pylint", "gradle", "gradlew", "mvn", "ninja", "bazel", "phpunit"]
        if tools.contains(name) { return true }
        // make with no target, or a target that builds or checks (not clean, install, deploy).
        if name == "make" {
            let targets = positional.filter { !$0.contains("=") }
            return targets.isEmpty || targets.contains { $0.range(of: #"^(all|build|test|tests|check|lint|ci|verify)$|test"#, options: .regularExpression) != nil }
        }
        if name == "cmake" { return rest.contains("--build") }
        if name == "ruff" { return rest.first == "check" }
        let verbs: Set<String> = ["test", "build", "check", "vet", "clippy", "lint", "t"]
        if ["go", "cargo", "swift", "dotnet", "deno", "bun"].contains(name), let v = rest.first, verbs.contains(v) { return true }
        if ["npm", "yarn", "pnpm"].contains(name), let v = rest.first {
            if verbs.contains(v) { return true }
            if v == "run", let script = rest.dropFirst().first,
               script.range(of: #"test|build|lint|check|typecheck"#, options: .regularExpression) != nil { return true }
        }
        if ["python", "python3", "py"].contains(name) {
            if let i = rest.firstIndex(of: "-m"), i + 1 < rest.count,
               ["pytest", "unittest", "tox", "mypy", "ruff", "pylint", "flake8"].contains(rest[i + 1]) { return true }
            if let script = positional.first, (script as NSString).lastPathComponent.range(
                of: #"^(test_.*|.*_test|run_?tests?|check)\.py$"#, options: .regularExpression) != nil { return true }
        }
        // A script named for what it does: `./build.sh`, `sh ci.sh`, `scripts/run_tests.sh`.
        let firstWritten = written.first { !$0.contains("=") } ?? first
        let script = ["sh", "bash", "zsh"].contains(name) ? positional.first ?? ""
            : (firstWritten.contains("/") || firstWritten.hasSuffix(".sh") ? firstWritten : "")
        let base = ((script as NSString).lastPathComponent as NSString).deletingPathExtension
        return !script.isEmpty && base.range(of: #"^(tests?|check|lint|ci|build|run[-_]?tests?|test[-_]all)$"#,
                                              options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Markdown for the system prompt, after the model's summary.
    public func rendered(maxItems: Int = 80) -> String {
        guard !isEmpty else { return "" }
        var s = "## Progress so far (tracked by kurtkode from your tool calls; exact)\n"
        if !todos.isEmpty {
            s += "\nTodo list:\n" + todos.map { t in
                "- [\(t.status == "completed" ? "x" : t.status == "in_progress" ? "~" : " ")] \(t.content)"
            }.joined(separator: "\n") + "\n"
        }
        if !filesRead.isEmpty {
            let shown = filesRead.suffix(maxItems)
            s += "\nFiles you have already read (\(filesRead.count)"
                + (filesRead.count > shown.count ? ", most recent \(shown.count)" : "") + "): "
                + shown.joined(separator: ", ") + "\n"
        }
        if !changeOrder.isEmpty {
            s += "\nFiles you have changed: " + changeOrder.map { "\($0) (\(filesChanged[$0] ?? 0) edit\(filesChanged[$0] == 1 ? "" : "s"))" }
                .joined(separator: ", ") + "\n"
        }
        if let c = lastCheck {
            let how = c.timedOut == true ? "timed out" : c.exitCode.map { $0 == 0 ? "exit 0 (passed)" : "exit \($0) (failed)" }
                ?? "ended without an exit code (stopped or killed)"
            s += "\nLast test or build command: `\(c.command)` → \(how)\n"
        }
        s += "\nDon't redo work listed here. Continue with what's left; re-read a file only if you need its details again."
        return s
    }
}
