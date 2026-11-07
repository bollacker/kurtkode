import Foundation

/// `/btw`: a quick question on the side. The model answers from the conversation so far, with no tools, and neither the
/// question nor the answer joins the conversation, so it can be asked while a run goes without touching it.
public enum SideQuestion {
    /// The conversation as text: the latest of it, up to `limit` characters. (Not the messages themselves: sending tool
    /// calls without tools is refused by some APIs.)
    public static func transcript(_ messages: [ChatMessage], limit: Int = 24_000) -> String {
        var parts: [String] = []
        var used = 0
        for m in messages.reversed() where m.contextNote != true {
            var line: String
            switch m.role {
            case .user: line = "User: " + m.content
            case .assistant:
                line = "Agent: " + m.content
                if !m.toolCalls.isEmpty { line += " [called " + m.toolCalls.map(\.name).joined(separator: ", ") + "]" }
            case .tool: line = "Tool result: " + m.content.prefix(1500)
            default: continue
            }
            if used + line.count > limit {
                // The latest message alone is too long: its end is better than no conversation.
                if parts.isEmpty { parts.append("[…] " + line.suffix(limit)) }
                break
            }
            used += line.count
            parts.append(line)
        }
        return parts.reversed().joined(separator: "\n\n")
    }

    static func prompt(question: String, transcript: String) -> String {
        """
        Answer the user's side question briefly, from this conversation and what you know. You have no tools here, and this \
        exchange isn't part of the conversation. If the answer needs something you can't see, say so.

        The conversation so far:
        \(transcript)

        The side question: \(question)
        """
    }

    /// The answer; nil if the request failed. The cost goes to `costs` (purpose `side`).
    public static func ask(_ question: String, messages: [ChatMessage], client: ChatClient, model: String, limits: TurnLimits,
                           costs: CostSink? = nil) async -> String? {
        var request = ChatRequest(model: model, messages: [.user(prompt(question: question, transcript: transcript(messages)))], tools: [],
                                  maxTokens: 1500, sendReasoning: false)
        request.oneOff = true             // asked once: no cache write to pay for
        request.temperature = 0
        if client.api == .openai { request.reasoningEffort = "none" }
        var l = limits
        l.maxTokens = request.maxTokens
        l.wallClock = min(l.wallClock, 120)
        let started = Date()
        let answer = await TurnRunner.run(client: client, request: request, limits: l) { _ in }
        await costs?.record(answer, purpose: .side, client: client, start: started)
        guard answer.meta?.stopReason == .completed, !answer.content.isEmpty else { return nil }
        return answer.content
    }
}
