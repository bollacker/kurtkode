import Foundation

/// A commit message for the staged change, written by a model the Git panel chooses.
public enum CommitMessage {
    static func prompt(diff: String) -> String {
        """
        Write a git commit message for this change. A subject line under 72 characters in the imperative mood, saying what \
        the change does; then, only if the reason isn't obvious from the subject, a blank line and a few short lines saying \
        why. No quotes, no code fences, no labels. Reply with the message only.

        \(diff.prefix(16_000))
        """
    }

    /// The message in a reply: without a code fence around it or trailing space. Nil when nothing's left.
    public static func clean(_ reply: String) -> String? {
        var lines = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.hasPrefix("```") == true { lines.removeLast() }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Asks `model`. The request's cost goes to `costs` (purpose `commitMessage`); nil if it failed.
    public static func write(diff: String, client: ChatClient, model: String, limits: TurnLimits, costs: CostSink? = nil) async -> String? {
        var question = ChatRequest(model: model, messages: [.user(prompt(diff: diff))], tools: [], maxTokens: 600, sendReasoning: false)
        question.oneOff = true             // asked once: no cache write to pay for
        question.temperature = 0
        if client.api == .openai { question.reasoningEffort = "none" }
        var l = limits
        l.maxTokens = question.maxTokens
        l.wallClock = min(l.wallClock, 60)
        let started = Date()
        let answer = await TurnRunner.run(client: client, request: question, limits: l) { _ in }
        await costs?.record(answer, purpose: .commitMessage, client: client, start: started)
        guard answer.meta?.stopReason == .completed else { return nil }
        return clean(answer.content)
    }
}
