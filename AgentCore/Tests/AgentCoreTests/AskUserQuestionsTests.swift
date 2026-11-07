import Foundation
import Testing
@testable import AgentCore

/// `ask_user` as models send it, whichever model it is, and what goes out to each API.
@Suite struct AskUserQuestionsTests {
    private func parsed(_ json: String) throws -> [UserQuestion] {
        try AskUserTool.questions(in: ToolArguments(json: json))
    }

    @Test func theFullFormKeepsEverything() throws {
        let questions = try parsed("""
            {"questions":[
              {"question":"Which database?","header":"Storage","options":[
                {"label":"SQLite","description":"Nothing to run."},{"label":"Postgres","description":"A server to keep up."}]},
              {"question":"What goes in it?","options":[{"label":"Users"},{"label":"Orders"}],"multiple":true},
              {"question":"Anything else?"}]}
            """)
        #expect(questions == [
            UserQuestion(question: "Which database?", header: "Storage",
                         options: [.init("SQLite", description: "Nothing to run."), .init("Postgres", description: "A server to keep up.")]),
            UserQuestion(question: "What goes in it?", options: ["Users", "Orders"], multiple: true),
            UserQuestion(question: "Anything else?"),
        ])
        #expect(questions[0].recommended == 0)
        #expect(questions[1].recommended == nil)                // several picks have no single best
        #expect(questions[2].recommended == nil)
    }

    @Test func theLooseFormsModelsSendAllWork() throws {
        let one = UserQuestion(question: "Which?", options: ["A", "B"])
        // The tool's first form, at the top level.
        #expect(try parsed(#"{"question":"Which?","options":["A","B"]}"#) == [one])
        // Options as plain strings, or the list as JSON text.
        #expect(try parsed(#"{"questions":[{"question":"Which?","options":["A","B"]}]}"#) == [one])
        #expect(try parsed(#"{"questions":[{"question":"Which?","options":"[\"A\",\"B\"]"}]}"#) == [one])
        #expect(try parsed(#"{"questions":[{"question":"Which?","options":"A\nB"}]}"#) == [one])
        // The whole list as JSON text, or a lone question instead of a list.
        #expect(try parsed(#"{"questions":"[{\"question\":\"Which?\",\"options\":[\"A\",\"B\"]}]"}"#) == [one])
        #expect(try parsed(#"{"questions":{"question":"Which?","options":["A","B"]}}"#) == [one])
        // Questions as plain strings.
        #expect(try parsed(#"{"questions":["First?","Second?"]}"#).map(\.question) == ["First?", "Second?"])
        // Other names for a label, and a boolean as text.
        #expect(try parsed(#"{"questions":[{"question":"Which?","options":[{"value":"A"},{"name":"B"}]}]}"#) == [one])
        #expect(try parsed(#"{"questions":[{"question":"Which?","multiple":"true"}]}"#)[0].multiple)
    }

    @Test func aRecommendationInTheLabelIsLeftToTheScreen() throws {
        let q = try parsed(#"{"questions":[{"question":"Which?","options":["SQLite (Recommended)","Postgres"]}]}"#)[0]
        #expect(q.options.map(\.label) == ["SQLite", "Postgres"])
    }

    @Test func aCallWithNothingToAskOrTooMuchIsSentBack() {
        #expect(throws: ToolFailure.self) { try parsed(#"{"questions":[]}"#) }
        #expect(throws: ToolFailure.self) { try parsed(#"{"questions":[{"question":"  "}]}"#) }
        #expect(throws: ToolFailure.self) { try parsed(#"{}"#) }
        #expect(throws: ToolFailure.self) { try parsed(#"{"questions":["1","2","3","4","5"]}"#) }
    }

    @Test func theModelReadsEachAnswerAndWhatToDoAboutTheRest() {
        let two = [UserQuestion(question: "First?"), UserQuestion(question: "Second?")]
        #expect(AskUserTool.report([two[0]], ["Yes"]) == "The user answered: Yes")
        #expect(AskUserTool.report(two, ["Yes", "No"]) == "The user answered:\n- First? → Yes\n- Second? → No")
        let partly = AskUserTool.report(two, ["Yes", nil])
        #expect(partly.contains("- First? → Yes") && partly.contains("- Second? → (no answer: decide this one yourself"))
        #expect(AskUserTool.report(two, [nil, nil]).hasPrefix("The user chose not to answer"))
        #expect(AskUserTool.report(two, []).hasPrefix("The user chose not to answer"))
    }

    @Test func theCardNamesTheQuestionsAsked() {
        let tool = AskUserTool()
        #expect(tool.summary(ToolArguments(["questions": ["First?", "Second?", "Third?"]])) == "Ask: First? (and 2 more)")
        #expect(tool.summary(ToolArguments(["question": "Only?"])) == "Ask: Only?")
    }

    // MARK: The schema, on each API

    /// Every keyword in the schema, at any depth (property names aren't keywords).
    private func keywords(_ value: JSONValue) -> Set<String> {
        guard case .object(let o) = value else { return [] }
        var found = Set(o.keys)
        for (key, child) in o {
            if key == "properties", case .object(let properties) = child {
                for property in properties.values { found.formUnion(keywords(property)) }
            } else if key == "items" {
                found.formUnion(keywords(child))
            }
        }
        return found
    }

    @Test func theSchemaUsesOnlyWhatEveryProviderTakes() {
        #expect(keywords(AskUserTool().parameters).isSubset(of: ["type", "properties", "items", "required", "description"]))
    }

    @Test func everyArrayInTheSchemaSaysWhatItHolds() {
        func check(_ value: JSONValue) {
            guard case .object(let o) = value else { return }
            if o["type"] == "array" { #expect(o["items"] != nil) }
            if case .object(let properties)? = o["properties"] { properties.values.forEach(check) }
            if let items = o["items"] { check(items) }
        }
        check(AskUserTool().parameters)
    }

    private func json(_ data: Data) throws -> [String: JSONValue] {
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data) else { throw ToolFailure("not an object") }
        return o
    }

    @Test func eachAPIGetsTheSchemaWhole() throws {
        let tool = AskUserTool()
        let request = ChatRequest(model: "m", messages: [.user("hi")], tools: [tool.definition], maxTokens: 1024)

        guard case .array(let chat)? = try json(WireFormat.encodeRequest(request))["tools"],
              case .object(let chatTool)? = chat.first, case .object(let function)? = chatTool["function"] else {
            Issue.record("no chat tool"); return
        }
        #expect(function["parameters"] == tool.parameters)

        guard case .array(let anthropic)? = try json(AnthropicWire.encodeRequest(request))["tools"],
              case .object(let anthropicTool)? = anthropic.first else { Issue.record("no Anthropic tool"); return }
        #expect(anthropicTool["input_schema"] == tool.parameters)

        guard case .array(let gemini)? = try json(GeminiWire.encodeRequest(request))["tools"],
              case .object(let geminiTools)? = gemini.first, case .array(let declarations)? = geminiTools["functionDeclarations"],
              case .object(let declaration)? = declarations.first else { Issue.record("no Gemini tool"); return }
        #expect(declaration["parametersJsonSchema"] == tool.parameters)
    }
}
