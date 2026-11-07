import Foundation

/// A question the model asks the user mid-task (`ask_user`).
public struct UserQuestion: Sendable, Hashable {
    /// A choice: what's picked, and what picking it means.
    public struct Option: Sendable, Hashable, ExpressibleByStringLiteral {
        public var label: String
        public var description: String

        public init(_ label: String, description: String = "") {
            self.label = label
            self.description = description
        }

        public init(stringLiteral value: String) { self.init(value) }
    }

    public var question: String
    /// A word or two naming the question, for the screen.
    public var header: String
    /// Choices to pick from; empty: answered in words. The user may always answer in words instead.
    public var options: [Option]
    /// Whether several options may be picked.
    public var multiple: Bool
    /// The call asking, so the app can match the card to it.
    public var callID: String?

    public init(question: String, header: String = "", options: [Option] = [], multiple: Bool = false, callID: String? = nil) {
        self.question = question
        self.header = header
        self.options = options
        self.multiple = multiple
        self.callID = callID
    }

    /// The option to mark as recommended: the tool asks for that one first. Several picks have no single best.
    public var recommended: Int? { !multiple && options.count > 1 ? 0 : nil }

    /// What the user typed at a prompt, as the answer: option numbers ("2", or "1,3" when several may be picked)
    /// become the options' text; anything else is taken as written. Nil for nothing typed.
    public func answer(fromTyped typed: String) -> String? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let parts = t.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        let picks = parts.compactMap(Int.init)
        guard !options.isEmpty, picks.count == parts.count, !picks.isEmpty, picks.allSatisfy({ (1...options.count).contains($0) }),
              multiple || picks.count == 1 else { return t }
        return picks.map { options[$0 - 1].label }.joined(separator: "; ")
    }
}

/// Lets the model ask the user questions and wait for the answers, instead of guessing or stopping.
public struct AskUserTool: Tool {
    public let name = "ask_user"
    public let risk = ToolRisk.read
    public let description = """
        Ask the user one or more questions and wait for the answers. Use it when a decision is genuinely theirs (a \
        choice of approach, scope, or a fact you can't find out) and guessing wrong would waste work. Don't ask what \
        you can find out by reading the project, and don't ask for permission to use tools (that's asked for you). \
        Offer options when there are a few clear choices; the user can always answer in their own words. Ask related \
        questions together in one call, not one after another.
        """
    /// How many questions a call may ask.
    public static let maxQuestions = 4
    /// Plain JSON Schema: every provider takes these keywords, and the limits are in the descriptions because some
    /// don't take `minItems` and `maxItems`.
    public var parameters: JSONValue {
        let option: JSONValue = ["type": "object",
                                 "properties": [
                                    "label": ["type": "string", "description": "The choice, in a few words."],
                                    "description": ["type": "string", "description": "What choosing it means, or what it costs."],
                                 ],
                                 "required": ["label"]]
        let question: JSONValue = ["type": "object",
                                   "properties": [
                                    "question": ["type": "string", "description": "The question, complete and self-contained."],
                                    "header": ["type": "string", "description": "A label of one or two words, for the screen."],
                                    "options": ["type": "array", "items": option,
                                                "description": .string("2 to 6 choices, the one you recommend first (it's shown as "
                                                    + "recommended). Leave out for an open question.")],
                                    "multiple": ["type": "boolean", "description": "Whether the user may pick several options."],
                                   ],
                                   "required": ["question"]]
        return ["type": "object",
                "properties": ["questions": ["type": "array", "items": question,
                                             "description": .string("1 to \(Self.maxQuestions) questions, shown to the user together.")]],
                "required": ["questions"]]
    }

    public init() {}

    public func summary(_ args: ToolArguments) -> String {
        let questions = (try? Self.questions(in: args)) ?? []
        guard let first = questions.first else { return "Ask: " + (args.string("question") ?? "?") }
        return "Ask: " + first.question + (questions.count > 1 ? " (and \(questions.count - 1) more)" : "")
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let questions = try Self.questions(in: args, callID: context.callID)
        guard let ask = context.askUser else {
            return ToolOutput(text: "Nobody is available to answer in this run. Decide yourself, carry on, and say in your "
                + "final answer what you assumed.")
        }
        let answers = await ask(questions)
        if Task.isCancelled { throw ToolFailure("the run was stopped before the user answered.") }
        return ToolOutput(text: Self.report(questions, answers))
    }

    /// The questions in a call. `questions` as the schema has it, or a single question at the top level (the tool's
    /// first form, which some models fall back to); models also send the lists as JSON text and options as plain strings.
    static func questions(in args: ToolArguments, callID: String? = nil) throws -> [UserQuestion] {
        let items = args.values["questions"].map(list) ?? [.object(args.values)]
        let questions = items.compactMap { question(from: $0, callID: callID) }
        guard !questions.isEmpty else { throw ToolFailure("question is empty.") }
        guard questions.count <= maxQuestions else {
            throw ToolFailure("that's \(questions.count) questions; ask at most \(maxQuestions) in one call, the ones that matter most.")
        }
        return questions
    }

    private static func question(from value: JSONValue, callID: String?) -> UserQuestion? {
        let fields: ToolArguments
        switch value {
        case .string(let s): fields = ToolArguments(["question": .string(s)])
        case .object(let o): fields = ToolArguments(o)
        default: return nil
        }
        let question = trimmed(fields.string("question"))
        guard !question.isEmpty else { return nil }
        let options = fields.values["options"].map(list)?.compactMap(option(from:)) ?? []
        return UserQuestion(question: question, header: trimmed(fields.string("header")), options: Array(options.prefix(8)),
                            multiple: fields.bool("multiple") ?? false, callID: callID)
    }

    private static func option(from value: JSONValue) -> UserQuestion.Option? {
        let fields: ToolArguments
        switch value {
        case .string(let s): fields = ToolArguments(["label": .string(s)])
        case .object(let o): fields = ToolArguments(o)
        default: return nil
        }
        var label = trimmed(["label", "value", "text", "name", "title"].lazy.compactMap(fields.string).first)
        // Models used to Claude's tool mark the choice in its label; here the screen does.
        if let mark = label.range(of: "(recommended)", options: [.caseInsensitive, .anchored, .backwards]) {
            label = trimmed(String(label[..<mark.lowerBound]))
        }
        return label.isEmpty ? nil : UserQuestion.Option(label, description: trimmed(fields.string("description")))
    }

    /// A list as models send it: an array, a lone item, or either as JSON text (else one item a line).
    private static func list(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let a): return a
        case .object: return [value]
        case .string(let s):
            if let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) {
                if case .array(let a) = decoded { return a }
                if case .object = decoded { return [decoded] }
            }
            return s.split(separator: "\n").map { .string(String($0)) }
        default: return []
        }
    }

    private static func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the model reads: each answer, and what to do about the ones it didn't get.
    static func report(_ questions: [UserQuestion], _ answers: [String?]) -> String {
        let given = questions.indices.map { $0 < answers.count ? answers[$0] : nil }
        if given.allSatisfy({ $0 == nil }) {
            return "The user chose not to answer. Decide yourself, carry on, and say in your final answer what you assumed. "
                + "Don't ask this again."
        }
        if questions.count == 1, let answer = given[0] { return "The user answered: " + answer }
        var lines = ["The user answered:"]
        for (question, answer) in zip(questions, given) {
            lines.append("- " + question.question + " → " + (answer ?? "(no answer: decide this one yourself and say what you assumed)"))
        }
        return lines.joined(separator: "\n")
    }
}
