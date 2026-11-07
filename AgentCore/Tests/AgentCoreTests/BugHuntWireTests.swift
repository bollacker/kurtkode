import Foundation
import Testing
@testable import AgentCore

/// Gemini thinking budgets per model family, price-list name matching, and Gemini tool-use prompt tokens.
@Suite struct BugHuntWireTests {
    private func thinking(_ model: String, _ effort: String) throws -> [String: JSONValue] {
        var r = ChatRequest(model: model, messages: [.user("x")], maxTokens: 100)
        r.reasoningEffort = effort
        let o = try JSONDecoder().decode([String: JSONValue].self, from: GeminiWire.encodeRequest(r))
        guard case .object(let g)? = o["generationConfig"], case .object(let t)? = g["thinkingConfig"] else { throw ToolFailure("shape") }
        return t
    }

    @Test func geminiBudgetsStayInEachFamilysRange() throws {
        // Pro can't turn thinking off: 128 is the least it takes.
        #expect(try thinking("gemini-2.5-pro", "none")["thinkingBudget"] == 128)
        #expect(try thinking("gemini-2.5-pro", "none")["includeThoughts"] == true)
        #expect(try thinking("gemini-2.5-pro", "minimal")["thinkingBudget"] == 512)
        #expect(try thinking("gemini-2.5-pro", "max")["thinkingBudget"] == 32768)
        // Flash tops out at 24576 and may be turned off.
        #expect(try thinking("gemini-2.5-flash", "max")["thinkingBudget"] == 24576)
        #expect(try thinking("gemini-2.5-flash", "none")["thinkingBudget"] == 0)
        #expect(try thinking("gemini-2.5-flash", "none")["includeThoughts"] == false)
        // Flash-Lite: off, or 512 and up.
        #expect(try thinking("gemini-2.5-flash-lite", "none")["thinkingBudget"] == 0)
        #expect(try thinking("gemini-2.5-flash-lite", "minimal")["thinkingBudget"] == 512)
        #expect(try thinking("gemini-2.5-flash-lite", "xhigh")["thinkingBudget"] == 24576)
        // Gemini 3 keeps levels.
        #expect(try thinking("gemini-3-flash-preview", "none")["thinkingLevel"] == "minimal")
        #expect(try thinking("gemini-3-flash-preview", "none")["thinkingBudget"] == nil)
    }

    @Test func priceListRejectsUnlistedVersionsAndVariants() {
        #expect(PriceList.price(api: .anthropic, model: "claude-sonnet-5-6-20270101") == nil)
        #expect(PriceList.price(api: .anthropic, model: "claude-opus-5-6-20270101") == nil)
        #expect(PriceList.price(api: .anthropic, model: "claude-haiku-5-5-20260101")?.input == 0.10)
        #expect(PriceList.price(api: .anthropic, model: "claude-sonnet-5-20260101")?.input == 2)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash-image") == nil)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash-image-preview") == nil)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash-preview-tts") == nil)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash-preview-09-2025")?.input == 0.30)
        #expect(PriceList.price(api: .gemini, model: "gemini-2.5-flash")?.input == 0.30)
    }

    @Test func geminiToolUsePromptTokensCountAsInput() async {
        let chunk = #"{"candidates":[{"content":{"parts":[{"text":"hi"}],"role":"model"},"finishReason":"STOP"}],"#
            + #""usageMetadata":{"promptTokenCount":100,"toolUsePromptTokenCount":40,"candidatesTokenCount":5}}"#
        let (client, _) = MockServer.client(MockServer.Route(chunks: [Data("data: \(chunk)\n\n".utf8)]), api: .gemini)
        let reply = await TurnRunner.run(client: client, request: ChatRequest(model: "gemini-3-flash-preview", messages: [.user("x")], maxTokens: 100),
                                         limits: TurnLimits(maxTokens: 100, wallClock: 30)) { _ in }
        #expect(reply.meta?.usage?.promptTokens == 140)
    }
}
