import Foundation
import Testing
@testable import AgentCore

@Suite struct WireFormatTests {
    @Test func encodesRequestWithLimitsAndToolMessages() throws {
        let call = ToolCall(id: "173991649", name: "read_file", arguments: #"{"path":"a.txt"}"#)
        let req = ChatRequest(
            model: "qwen/qwen3-coder-30b",
            messages: [.system("sys"), .user("hi"),
                       ChatMessage(role: .assistant, content: "", reasoning: "secret thoughts", toolCalls: [call]),
                       ChatMessage(role: .tool, content: "file text", toolCallID: "173991649")],
            tools: [ToolDefinition(name: "read_file", description: "Read a file.",
                                   parameters: ["type": "object", "properties": ["path": ["type": "string"]]])],
            maxTokens: 4096)
        let json = try JSONDecoder().decode(JSONValue.self, from: WireFormat.encodeRequest(req))
        guard case .object(let o) = json, case .array(let msgs) = o["messages"] else { Issue.record("shape"); return }

        #expect(o["max_tokens"] == .number(4096))
        #expect(o["stream"] == .bool(true))
        #expect(o["stream_options"] == ["include_usage": true])
        #expect(msgs.count == 4)
        // Tool-only assistant message: null content, tool_calls in OpenAI shape, no reasoning sent.
        guard case .object(let a) = msgs[2] else { Issue.record("assistant"); return }
        #expect(a["content"] == .null)
        #expect(a["reasoning"] == nil)
        #expect(a["tool_calls"] == [["id": "173991649", "type": "function",
                                     "function": ["name": "read_file", "arguments": #"{"path":"a.txt"}"#]]])
        guard case .object(let t) = msgs[3] else { Issue.record("tool"); return }
        #expect(t["tool_call_id"] == "173991649")
        guard case .array(let tools) = o["tools"], case .object(let tool) = tools.first else { Issue.record("tools"); return }
        #expect(tool["type"] == "function")
    }

    /// A call cut off by a cancelled or length-limited turn must not reach the server as broken JSON: LM Studio
    /// parses the history's `arguments` and answers the whole request with a 500.
    @Test func sendsTruncatedToolArgumentsAsValidJSON() throws {
        let cut = #"{"path":"a.py","new":"def f():\n    return"#
        let calls = [ToolCall(id: "1", name: "edit_file", arguments: cut),
                     ToolCall(id: "2", name: "list_dir", arguments: ""),
                     ToolCall(id: "3", name: "read_file", arguments: #"{"path":"a.txt"}"#)]
        let msg = ChatMessage(role: .assistant, content: "", toolCalls: calls)
        guard case .object(let o) = WireFormat.encodeMessage(msg), case .array(let sent)? = o["tool_calls"] else {
            Issue.record("shape"); return
        }
        let args: [String] = sent.compactMap {
            guard case .object(let c) = $0, case .object(let f)? = c["function"],
                  case .string(let a)? = f["arguments"] else { return nil }
            return a
        }
        #expect(args.count == 3)
        for a in args {
            let v = try JSONDecoder().decode(JSONValue.self, from: Data(a.utf8))
            guard case .object = v else { Issue.record("not an object: \(a)"); continue }
        }
        #expect(args[0].contains("invalid_arguments") && args[0].contains("def f()"))
        #expect(args[1] == "{}")
        #expect(args[2] == #"{"path":"a.txt"}"#)
    }

    @Test func parsesSSELines() {
        #expect(SSELineParser.parse("data: {\"a\":1}") == .data("{\"a\":1}"))
        #expect(SSELineParser.parse("data:{\"a\":1}") == .data("{\"a\":1}"))
        #expect(SSELineParser.parse("data: [DONE]") == .done)
        #expect(SSELineParser.parse(": keep-alive") == .ignore)
        #expect(SSELineParser.parse("event: message") == .ignore)
        #expect(SSELineParser.parse("") == .ignore)
    }

    @Test func assemblesParallelToolCallsFromQwenStream() throws {
        var acc = TurnAccumulator()
        for e in try sseEvents(fixture: "sse_qwen_toolcalls") { acc.apply(e) }
        let calls = acc.snapshot.toolCalls
        #expect(calls.count == 2)
        #expect(calls.map(\.name) == ["read_file", "read_file"])
        #expect(calls.map(\.arguments) == [#"{"path":"src/main.swift"}"#, #"{"path":"README.md"}"#])
        #expect(calls.allSatisfy { !$0.id.isEmpty })
        #expect(acc.finishReason == .toolCalls)
        #expect(acc.usage == Usage(promptTokens: 282, completionTokens: 45))
        #expect(acc.snapshot.reportedModel == "qwen/qwen3-coder-30b")
    }

    @Test func separatesGemmaReasoningFromContent() throws {
        var acc = TurnAccumulator()
        for e in try sseEvents(fixture: "sse_gemma_reasoning") { acc.apply(e) }
        #expect(!acc.snapshot.reasoning.isEmpty)
        #expect(!acc.snapshot.content.isEmpty)
        #expect(acc.snapshot.content.contains("91"))
        #expect(acc.usage?.reasoningTokens == 266)
        #expect(acc.finishReason == .stop)
    }

    @Test func reportsTruncationAtMaxTokens() throws {
        var acc = TurnAccumulator()
        for e in try sseEvents(fixture: "sse_qwen_length") { acc.apply(e) }
        #expect(acc.finishReason == .length)
        #expect(acc.usage?.completionTokens == 11)
    }

    @Test func readsReportedCost() throws {
        let chunk = #"{"model":"m","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"cost":0.0012}}"#
        let events = try WireFormat.events(fromChunk: Data(chunk.utf8))
        #expect(events.contains(.usage(Usage(promptTokens: 10, completionTokens: 2, cost: 0.0012))))
    }

    @Test func readsCachedPromptTokens() throws {
        let chunk = #"{"model":"m","choices":[],"usage":{"prompt_tokens":1000,"completion_tokens":2,"prompt_tokens_details":{"cached_tokens":900,"cache_write_tokens":50}}}"#
        let events = try WireFormat.events(fromChunk: Data(chunk.utf8))
        #expect(events.contains(.usage(Usage(promptTokens: 1000, completionTokens: 2, cacheReadTokens: 900, cacheWriteTokens: 50))))
        #expect(Usage(promptTokens: 1000, completionTokens: 2, cacheReadTokens: 900, cacheWriteTokens: 50).cacheSummary == "90% cached, 50 written")
        #expect(Usage(promptTokens: 10, completionTokens: 2).cacheSummary == nil)
    }

    @Test func extractsErrorMessagesInBothShapes() throws {
        let body = try fixtureData("http_400_bad_request", "txt")
        let lmstudio = body.split(separator: 0x0A).first.map { Data($0) } ?? body   // file ends with "HTTP 400"
        #expect(WireFormat.errorMessage(fromBody: lmstudio)?.contains("not valid JSON") == true)
        #expect(WireFormat.errorMessage(fromBody: Data(#"{"error":{"message":"bad key","type":"auth"}}"#.utf8)) == "bad key")
        #expect(WireFormat.errorMessage(fromBody: Data("upstream down".utf8)) == "upstream down")
    }

    @Test func decodesV1ModelsFixture() throws {
        struct List: Decodable { struct M: Decodable { let id: String }; let data: [M] }
        let list = try JSONDecoder().decode(List.self, from: fixtureData("v1_models", "json"))
        #expect(list.data.contains { $0.id == "qwen/qwen3-coder-30b" })
    }
}
