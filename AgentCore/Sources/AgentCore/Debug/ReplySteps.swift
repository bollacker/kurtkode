import Foundation

/// A reply as the steps the model took, in the order the server sent them: thinking, text, tool calls, and what the
/// server said between them (a fallback to another model). Native APIs keep that order (`ChatMessage.native`);
/// OpenAI-compatible replies are stored as reasoning, text, and calls, so their order is only that.
public struct ReplyStep: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// Reasoning the server showed: a summary (Claude 4.7+, Gemini) or the model's own text (local models).
        case thinking(String)
        /// Reasoning that happened but wasn't shown: an empty thinking block that carries only its signature, or a
        /// redacted one. `bytes`: the size of the opaque part the server keeps it in.
        case hiddenThinking(bytes: Int)
        case text(String)
        case call(ToolCall)
        /// The server's own word between steps (a fallback: one model declined and another continued).
        case server(String)
        /// The server searched the web (its own tool): the query.
        case webSearch(String)
        /// What a search found: "title — url" lines, or the error.
        case webResults([String])
    }

    public var id: Int
    public var kind: Kind
}

public enum ReplySteps {
    /// The reply's steps, and whether their order is the server's (false: reasoning, text, then calls, as stored).
    public static func steps(of m: ChatMessage) -> (steps: [ReplyStep], ordered: Bool) {
        var out: [ReplyStep] = []
        func add(_ k: ReplyStep.Kind) { out.append(ReplyStep(id: out.count, kind: k)) }
        let callsByID = Dictionary(m.toolCalls.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let n = m.native, case .array(let blocks) = n.blocks {
            switch n.api {
            case .anthropic:
                for case .object(let b) in blocks {
                    switch NativeWire.string(b["type"]) {
                    case "thinking":
                        let t = NativeWire.string(b["thinking"]) ?? ""
                        if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            add(.hiddenThinking(bytes: NativeWire.string(b["signature"])?.utf8.count ?? 0))
                        } else {
                            add(.thinking(t))
                        }
                    case "redacted_thinking":
                        add(.hiddenThinking(bytes: NativeWire.string(b["data"])?.utf8.count ?? 0))
                    case "text":
                        if let t = NativeWire.string(b["text"]), !t.isEmpty { add(.text(t)) }
                    case "tool_use":
                        let id = NativeWire.string(b["id"]) ?? ""
                        add(.call(callsByID[id] ?? ToolCall(id: id, name: NativeWire.string(b["name"]) ?? "?",
                                                            arguments: NativeWire.text(b["input"] ?? .object([:])))))
                    case "server_tool_use":
                        if case .object(let input)? = b["input"], let q = NativeWire.string(input["query"]) { add(.webSearch(q)) }
                        else { add(.webSearch(NativeWire.text(b["input"] ?? .object([:])))) }
                    case "web_search_tool_result":
                        switch b["content"] {
                        case .array(let results)?:
                            add(.webResults(results.compactMap { r in
                                guard case .object(let o) = r else { return nil }
                                let title = NativeWire.string(o["title"]) ?? "?"
                                return NativeWire.string(o["url"]).map { "\(title) — \($0)" } ?? title
                            }))
                        case .object(let e)?:
                            add(.webResults(["Search failed: " + (NativeWire.string(e["error_code"]) ?? "unknown error")]))
                        default:
                            break
                        }
                    case "fallback":
                        func model(_ v: JSONValue?) -> String {
                            if case .object(let o)? = v { return NativeWire.string(o["model"]) ?? "a model" }
                            return "a model"
                        }
                        add(.server("\(model(b["from"])) declined; \(model(b["to"])) continued"))
                    default:
                        break
                    }
                }
                return (out, true)
            case .gemini:
                var call = 0
                for case .object(let p) in blocks {
                    if case .object(let fc)? = p["functionCall"] {
                        let stored = call < m.toolCalls.count ? m.toolCalls[call] : nil
                        add(.call(stored ?? ToolCall(id: "", name: NativeWire.string(fc["name"]) ?? "?",
                                                     arguments: NativeWire.text(fc["args"] ?? .object([:])))))
                        call += 1
                    } else if case .object(let tc)? = p["toolCall"] {
                        // The server's own tool (Google Search grounding): its queries.
                        var queries: [String] = []
                        if case .object(let args)? = tc["args"], case .array(let qs)? = args["queries"] { queries = qs.compactMap { NativeWire.string($0) } }
                        add(.webSearch(queries.isEmpty ? (NativeWire.string(tc["toolType"]) ?? "search") : queries.joined(separator: "; ")))
                    } else if let t = NativeWire.string(p["text"]) {
                        if p["thought"] == .bool(true) {
                            if !t.isEmpty { add(.thinking(t)) }
                        } else if !t.isEmpty {
                            add(.text(t))
                        }
                    }
                }
                return (out, true)
            case .openai:
                break
            }
        }
        if let r = m.reasoning, !r.isEmpty { add(.thinking(r)) }
        if !m.content.isEmpty { add(.text(m.content)) }
        for c in m.toolCalls { add(.call(c)) }
        return (out, false)
    }
}

/// How much of a reply's reasoning the server showed, against what it billed.
public struct ReasoningShown: Sendable, Hashable {
    /// Reasoning tokens the server billed (`Usage.reasoningTokens`); nil when it doesn't report them.
    public var billedTokens: Int?
    /// The shown reasoning's size in tokens, estimated from its text (about four bytes a token).
    public var shownTokens: Int
    /// Thinking that happened with nothing shown (signature-only or redacted blocks).
    public var hiddenBlocks: Int
    /// Whether the shown text is a summary written for display (Claude 4.7+, Gemini), not the model's own words.
    public var isSummary: Bool

    public init(_ m: ChatMessage) {
        billedTokens = (m.meta?.usage?.reasoningTokens).flatMap { $0 > 0 ? $0 : nil }
        let steps = ReplySteps.steps(of: m).steps
        var shownBytes = 0
        hiddenBlocks = 0
        for s in steps {
            switch s.kind {
            case .thinking(let t): shownBytes += t.utf8.count
            case .hiddenThinking: hiddenBlocks += 1
            default: break
            }
        }
        shownTokens = (shownBytes + 3) / 4
        switch m.native?.api {
        case .anthropic?: isSummary = AnthropicWire.generation(m.native?.model ?? "") == .current
        case .gemini?: isSummary = true
        default: isSummary = false
        }
    }

    /// Whether there's anything to say: reasoning shown, billed, or hidden.
    public var isEmpty: Bool { (billedTokens ?? 0) == 0 && shownTokens == 0 && hiddenBlocks == 0 }

    /// The shown part as a share of the billed reasoning, when the server billed some. A model's own reasoning text
    /// (local models) is all of it, whatever the estimate from its size says; only summaries are measured.
    public var shownShare: Double? {
        guard let b = billedTokens, b > 0 else { return nil }
        if !isSummary { return shownTokens > 0 ? 1 : 0 }
        return min(1, Double(shownTokens) / Double(b))
    }

    /// "Thought for 1,240 tokens; shown: a summary of about 180 (15%)", or nil when there was no reasoning.
    public var summary: String? {
        guard !isEmpty else { return nil }
        let shownWord = isSummary ? "a summary of about \(shownTokens.formatted())" : "about \(shownTokens.formatted())"
        guard let b = billedTokens else {
            if shownTokens == 0 { return "Thought without showing it (\(hiddenBlocks) hidden block\(hiddenBlocks == 1 ? "" : "s"))" }
            return "Reasoning shown: \(shownWord) tokens (the server doesn't say how many it billed)"
        }
        if shownTokens == 0 { return "Thought for \(b.formatted()) tokens; none of it shown" }
        if !isSummary { return "Thought for \(b.formatted()) tokens; all of it shown" }
        let pct = Int(((shownShare ?? 0) * 100).rounded())
        return "Thought for \(b.formatted()) tokens; shown: \(shownWord) (\(pct)%)"
    }
}
