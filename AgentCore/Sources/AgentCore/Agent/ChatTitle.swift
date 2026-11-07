import Foundation

/// A short title for a chat, written by the chat's own model once its first exchange is done. The first line of the
/// request is kept when it already reads as a title, so most chats cost nothing.
public enum ChatTitle {
    /// The first request is worth a title: the default (its first line) would be cut, or leave most of it out.
    public static func worthWriting(request: String) -> Bool {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 60 || text.contains(where: \.isNewline)
    }

    static func prompt(request: String, reply: String) -> String {
        """
        Write a title for this conversation with a coding agent: three to six plain words, no quotes, no punctuation at \
        the end, capitalized like a sentence. Say what the work is about. Reply with the title only.

        The user asked:
        \(request.prefix(1500))

        The agent answered:
        \(reply.prefix(600))
        """
    }

    /// The title in a reply: its first line that has any words, without quotes, markup or a "Title:" label; nil when
    /// nothing usable is left.
    public static func clean(_ reply: String) -> String? {
        guard var line = reply.split(whereSeparator: \.isNewline).lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        let strip = CharacterSet(charactersIn: "\"'`*#_“”‘’ ")
        line = line.trimmingCharacters(in: strip)
        if line.lowercased().hasPrefix("title:") { line = String(line.dropFirst(6)).trimmingCharacters(in: strip) }
        while let l = line.last, ".:;,".contains(l) { line.removeLast() }
        guard line.contains(where: \.isLetter) else { return nil }
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    /// The request. `providers`: the ones the model's profile allows, the same as for its turns: this sends the chat's text.
    static func question(request: String, reply: String, model: String, providers: ProviderRouting?) -> ChatRequest {
        var question = ChatRequest(model: model, messages: [.user(prompt(request: request, reply: reply))], tools: [],
                                   maxTokens: 400, sendReasoning: false)
        question.oneOff = true             // asked once: no cache write to pay for
        question.temperature = 0
        question.provider = providers
        return question
    }

    /// Asks `model` for a title. The request's cost goes to `costs` (purpose `title`); nil if it failed.
    public static func write(request: String, reply: String, client: ChatClient, model: String, providers: ProviderRouting? = nil,
                             limits: TurnLimits, costs: CostSink? = nil) async -> String? {
        var question = question(request: request, reply: reply, model: model, providers: providers)
        // As for the skill router: no thinking where the server takes the switch.
        if client.api == .openai { question.reasoningEffort = "none" }
        var l = limits
        l.maxTokens = question.maxTokens
        l.wallClock = min(l.wallClock, 60)
        let started = Date()
        let answer = await TurnRunner.run(client: client, request: question, limits: l) { _ in }
        await costs?.record(answer, purpose: .title, client: client, start: started)
        guard answer.meta?.stopReason == .completed else { return nil }
        return clean(answer.content)
    }
}
