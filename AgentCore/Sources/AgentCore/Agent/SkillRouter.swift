import Foundation

/// When the skill router runs. Small and local models rarely load a skill by themselves (Qwen 3.5 9B: 10% of the
/// requests that should load one, even told to check), but they pick the right one when asked directly (95%) and
/// follow it when told to (31 of 31 runs); Claude and Gemini already load the right skill about 90% of the time.
/// So by default it runs on OpenAI-compatible servers (LM Studio, OpenRouter) and not on the native APIs.
public enum SkillRouting: String, Codable, Sendable, CaseIterable {
    case auto, on, off

    public func applies(to api: WireAPI) -> Bool { self == .on || (self == .auto && api == .openai) }
}

/// Picks the one skill that fits a run's new request, with a short side question to the session's model (no tools,
/// no thinking), and loads it for the agent: a note after the user's message (like a resumed session's) with what
/// the skill tool would have returned. A note that only said "load it" was ignored by Qwen 3.5 9B in 9% of runs;
/// the instructions themselves can't be skipped that way. The question's wording is the `router-skill` template.
public enum SkillRouter {
    /// Long requests (pasted logs, attached files) are cut: the start says what the task is.
    static let maxRequestCharacters = 2000

    /// The request a run starts with: the user's latest message, when it's new (the last message, written by the
    /// user, not a note or a subagent's report). Nil when there's nothing new to route.
    public static func request(in history: [ChatMessage]) -> String? {
        guard let last = history.last, last.role == .user, last.contextNote != true, last.subagentReport == nil else { return nil }
        let text = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // A /skill command already says which skill to load; a bare "yes" or "go on" carries on the task in hand.
        guard !text.isEmpty, !text.hasPrefix("Load the skill \""), !isAcknowledgement(text) else { return nil }
        return String(text.prefix(maxRequestCharacters))
    }

    /// Words of a reply that only says "go on": acknowledgements, never a task.
    static let acknowledgements: Set<String> = [
        "yes", "yeah", "yep", "yup", "y", "ok", "okay", "k", "sure", "please", "pls", "go", "ahead", "on", "continue",
        "proceed", "thanks", "thank", "you", "great", "perfect", "good", "fine", "sounds", "looks", "lgtm", "do", "it",
        "that", "this", "cool", "nice", "right", "correct", "agreed", "alright", "keep", "going", "and", "so", "then",
    ]

    /// A follow-up made only of acknowledgements ("yes please do that", "ok go ahead", "continue"): routing it costs a
    /// request (about 2k uncached tokens with the built-in skills) and can't find a skill, so it isn't asked. Anything
    /// with a word of its own ("fix the flaky tests") is a request and is routed.
    static func isAcknowledgement(_ text: String) -> Bool {
        let words = text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return !words.isEmpty && words.count <= 8 && words.allSatisfy(acknowledgements.contains)
    }

    /// Whether the conversation already loaded `name`, by the skill tool or the router (its instructions are still
    /// in the history).
    static func alreadyLoaded(_ name: String, in history: [ChatMessage]) -> Bool {
        history.contains { m in
            m.toolCalls.contains { $0.name == "skill" && pickedName($0.arguments) == name }
                || (m.contextNote == true && m.content.hasPrefix(header(name)))
        }
    }

    static func header(_ name: String) -> String { "[kurtkode: the skill router loaded the \"\(name)\" skill" }

    /// The question asked: the skills and the request in the `router-skill` template.
    public static func question(request: String, skills: [Skill], templates: PromptTemplates) -> String {
        let listing = skills.filter(\.modelInvocable).map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        return templates.render("router-skill", ["skills": listing, "request": request])
    }

    /// The skill a reply names: a call to the skill tool, or the last skill name the text mentions; nil for "none",
    /// an empty or cut reply, or a name that isn't offered.
    public static func pick(_ reply: ChatMessage, among skills: [Skill]) -> Skill? {
        let offered = skills.filter(\.modelInvocable)
        if let call = reply.toolCalls.first(where: { $0.name == "skill" }), let name = pickedName(call.arguments) {
            return offered.first { $0.name == name }
        }
        // Whole names only (a name inside a longer one isn't that name), and the last one mentioned: models sometimes
        // explain first.
        let words = reply.content.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "-") }.map(String.init)
        return words.reversed().lazy.compactMap { w in offered.first { $0.name == w } }.first
    }

    static func pickedName(_ arguments: String) -> String? {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8)),
              case .string(let name)? = o["name"] else { return nil }
        return name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// What the agent is told: the skill is loaded, follow it, and its instructions as the skill tool gives them.
    /// Nil if the skill can't be read.
    public static func note(_ skill: Skill) -> String? {
        guard let text = SkillTool.instructions(skill) else { return nil }
        return header(skill.name) + " for this request; follow its instructions below. If it doesn't fit the request "
            + "after all, say so and carry on without it.]\n\n" + String(text.prefix(24_000))
    }

    /// Asks which skill fits the run's new request and returns the note for it (a context note, to send after the
    /// user's message), or nil: no new request, no skills, "none", the skill already loaded, or the question failed.
    /// The question's cost goes to `costs` (purpose `routing`) and `meter`.
    public static func route(history: [ChatMessage], skills: [Skill], client: ChatClient, model: String,
                             templates: PromptTemplates, limits: TurnLimits, costs: CostSink? = nil,
                             meter: CostMeter? = nil) async -> ChatMessage? {
        guard !skills.isEmpty, let text = request(in: history) else { return nil }
        var request = ChatRequest(model: model, messages: [.user(question(request: text, skills: skills, templates: templates))],
                                  tools: [], maxTokens: 400, sendReasoning: false)
        request.oneOff = true             // asked once: no cache write to pay for
        request.temperature = 0
        // No thinking where the server takes the switch (it would take seconds to minutes on a local model); not on
        // Claude, where another effort level voids the session's cached history.
        if client.api == .openai { request.reasoningEffort = "none" }
        var l = limits
        l.maxTokens = request.maxTokens
        l.wallClock = min(l.wallClock, 60)
        let started = Date()
        let reply = await TurnRunner.run(client: client, request: request, limits: l) { _ in }
        if let entry = await costs?.record(reply, purpose: .routing, client: client, start: started) {
            meter?.add(entry)
        } else {
            meter?.add(reply.meta?.usage)
        }
        guard reply.meta?.stopReason == .completed, let skill = pick(reply, among: skills),
              !alreadyLoaded(skill.name, in: history), let text = note(skill) else { return nil }
        return FrozenSystemPrompt.noteMessage(text)
    }
}
