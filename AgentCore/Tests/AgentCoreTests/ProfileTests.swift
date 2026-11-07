import Foundation
import Testing
@testable import AgentCore

@Suite struct ProfileTests {
    @Test func familyDefaultsComeFromTheTable() {
        let ep = UUID()
        #expect(ModelProfile.defaults(endpointID: ep, model: "mistralai/devstral-small-2-2512").history.toolCallIDs == .alphanumeric9)
        #expect(ModelProfile.defaults(endpointID: ep, model: "google/gemma-4-12b-qat").history.mergeConsecutive)
        #expect(ModelProfile.defaults(endpointID: ep, model: "qwen/qwen3-coder-30b").history == HistoryShape(parseTextToolCalls: true))
        #expect(ModelProfile.defaults(endpointID: ep, model: "openai/gpt-oss-120b").history.sendReasoning)
        let plain = ModelProfile.defaults(endpointID: ep, model: "meta-llama/llama-3.3-70b-instruct")
        #expect(plain.history == HistoryShape())
        #expect(plain.temperature == nil)
    }

    @Test func reasoningIsSentOnlyWhenTheShapeKeepsIt() throws {
        var m = ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: "c1", name: "list_dir", arguments: "{}")])
        m.reasoning = "List the root first."
        func sent(_ shape: HistoryShape) -> JSONValue? {
            guard case .object(let o) = WireFormat.encodeMessage(HistoryShaper.shape([m], for: shape)[0], reasoning: shape.sendReasoning)
            else { return nil }
            return o["reasoning"]
        }
        let kept = sent(HistoryShape(sendReasoning: true))
        let dropped = sent(HistoryShape())
        #expect(kept == .string("List the root first."))
        #expect(dropped == nil)
    }

    @Test func alphanumericIDsAreStableAndValid() {
        let a = HistoryShaper.alphanumeric9("call_173991649")
        #expect(a.count == 9)
        #expect(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        #expect(HistoryShaper.alphanumeric9("call_173991649") == a)          // deterministic: cache-friendly
        #expect(HistoryShaper.alphanumeric9("call_173991650") != a)
        #expect(HistoryShaper.alphanumeric9("Ab3dE9gH1") == "Ab3dE9gH1")      // already valid: unchanged
    }

    @Test func shapingRewritesCallsAndResultsConsistently() {
        let call = ToolCall(id: "173991649", name: "read_file", arguments: "{}")
        let history: [ChatMessage] = [
            .system("S"), .user("a"),
            ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "x", toolCallID: "173991649"),
        ]
        let shaped = HistoryShaper.shape(history, for: HistoryShape(toolCallIDs: .alphanumeric9))
        #expect(shaped[2].toolCalls[0].id == shaped[3].toolCallID)
        #expect(shaped[2].toolCalls[0].id.count == 9)
        #expect(HistoryShaper.shape(history, for: HistoryShape()) == history)
    }

    @Test func mergingMakesRolesAlternate() {
        let history: [ChatMessage] = [
            .system("S"), .user("summary follows"), .user("the real question"),
            ChatMessage(role: .assistant, content: "part 1"), ChatMessage(role: .assistant, content: "part 2"),
            .user("next"),
        ]
        let merged = HistoryShaper.shape(history, for: HistoryShape(mergeConsecutive: true))
        #expect(merged.map(\.role) == [.system, .user, .assistant, .user])
        #expect(merged[1].content == "summary follows\n\nthe real question")
        #expect(merged[2].content == "part 1\n\npart 2")
    }

    @Test func profilesRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kk-profiles-\(UUID().uuidString.prefix(6)).json")
        let store = ProfileStore(fileURL: url)
        var p = ModelProfile.defaults(endpointID: Endpoint.localLMStudio.id, model: "mistralai/devstral-small-2-2512")
        p.contextLength = 24_576
        p.promptAddendum = "Prefer small edits."
        p.measuredPeakMemoryBytes = 21_000_000_000
        try store.save([p.key: p])
        #expect(store.load()[p.key] == p)
    }

    @Test func loopSendsShapedHistoryAndTagsTheEndpoint() async throws {
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("call_abc-123", "list_dir", "{}"), SSE.content("done")]))
        final class Box: @unchecked Sendable { let l = NSLock(); var m: [ChatMessage] = []; func add(_ x: ChatMessage) { l.withLock { m.append(x) } } }
        let box = Box()
        let ep = UUID()
        var config = AgentConfig(tools: ReadTools.all)
        config.historyShape = HistoryShape(toolCallIDs: .alphanumeric9)
        config.temperature = 0.2
        config.endpointID = ep
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config,
                            workspace: ws) { if case .assistant(let m) = $0 { box.add(m) } }
        #expect(box.m.allSatisfy { $0.meta?.endpointID == ep })
        #expect(box.m.first?.toolCalls.first?.id == "call_abc-123")          // stored as the model sent it
        let body = try #require(MockServer.requestBodies(host).last)
        let json = String(decoding: body, as: UTF8.self)
        let shaped = HistoryShaper.alphanumeric9("call_abc-123")
        #expect(json.contains("\"tool_call_id\":\"\(shaped)\""))              // sent in the template's form
        #expect(!json.contains("call_abc-123"))
        #expect(json.contains("\"temperature\":0.2"))
    }
}

@Suite struct TemplateShapingTests {
    @Test func strictAlternationBridgesToolResultsBeforeAUserTurn() {
        let call = ToolCall(id: "1", name: "read_file", arguments: "{}")
        let history: [ChatMessage] = [.system("S"), .user("go"), ChatMessage(role: .assistant, content: "", toolCalls: [call]),
                                      ChatMessage(role: .tool, content: "x", toolCallID: "1"), .user("Summarize this session")]
        let shaped = HistoryShaper.shape(history, for: HistoryShape(mergeConsecutive: true))
        #expect(shaped.map(\.role) == [.system, .user, .assistant, .tool, .assistant, .user])
        #expect(shaped[4].content == HistoryShaper.bridge)
        // Deterministic, so the cached prefix survives the next request.
        #expect(HistoryShaper.shape(history, for: HistoryShape(mergeConsecutive: true)) == shaped)
    }

    @Test func recoversTextToolCallsOnlyWhenWellFormed() throws {
        let known: Set = ["edit_file", "read_file", "list_dir"]
        let mistral = try #require(TextToolCalls.extract(from: #"I'll add it.[TOOL_CALLS]edit_file {"path": "FILES.md", "old_string": "a", "new_string": "b"}"#, knownTools: known))
        #expect(mistral.calls.map(\.name) == ["edit_file"])
        #expect(mistral.calls[0].arguments.contains("FILES.md"))
        #expect(mistral.remaining == "I'll add it.")
        let args = try #require(TextToolCalls.extract(from: #"[TOOL_CALLS]read_file[ARGS]{"path":"a.py"}"#, knownTools: known))
        #expect(args.calls.first?.arguments == #"{"path":"a.py"}"#)
        let list = try #require(TextToolCalls.extract(from: #"[TOOL_CALLS][{"name":"list_dir","arguments":{}},{"name":"read_file","arguments":{"path":"x"}}]"#, knownTools: known))
        #expect(list.calls.map(\.name) == ["list_dir", "read_file"])
        let hermes = try #require(TextToolCalls.extract(from: "<tool_call>\n{\"name\": \"read_file\", \"arguments\": {\"path\": \"a\"}}\n</tool_call>", knownTools: known))
        #expect(hermes.calls.map(\.name) == ["read_file"])
        // Qwen3-Coder XML, without the opening <tool_call> (as OpenRouter returned it); values typed by schema.
        let schema: JSONValue = ["type": "object", "properties": ["path": ["type": "string"], "limit": ["type": "integer"]]]
        let qwen = try #require(TextToolCalls.extract(
            from: "Let me look.\n\n<function=read_file>\n<parameter=path>\n 007\n</parameter>\n<parameter=limit>\n20\n</parameter>\n</function>\n</tool_call>",
            knownTools: known, parameterSchemas: ["read_file": schema]))
        #expect(qwen.calls.map(\.name) == ["read_file"])
        #expect(qwen.calls.first?.arguments == #"{"limit":20,"path":" 007"}"#)
        #expect(qwen.remaining == "Let me look.")
        let wrapped = try #require(TextToolCalls.extract(from: "<tool_call>\n<function=list_dir>\n</function>\n</tool_call>", knownTools: known))
        #expect(wrapped.calls.map(\.name) == ["list_dir"])
        #expect(wrapped.remaining.isEmpty)
        #expect(TextToolCalls.extract(from: "<function=rm_rf>\n</function>", knownTools: known) == nil)
        #expect(TextToolCalls.extract(from: #"[TOOL_CALLS]rm_rf {"path":"/"}"#, knownTools: known) == nil)       // unknown tool
        #expect(TextToolCalls.extract(from: "You could call read_file on it, e.g. {\"path\": \"a\"}.", knownTools: known) == nil)
        #expect(TextToolCalls.extract(from: #"[TOOL_CALLS]read_file {"path": "unterminated"#, knownTools: known) == nil)
    }

    @Test func repairsToolNamesWithEchoedTextGluedOn() {
        let known: Set = ["read_file", "todo_write", "edit_file"]
        #expect(TextToolCalls.repairName("Todo list updated (4/14 completed).[TOOL_CALLS]read_file", known: known) == "read_file")
        #expect(TextToolCalls.repairName("Todo_list_updated_8_14_completed_TOOL_CALLS_read_file", known: known) == "read_file")
        #expect(TextToolCalls.repairName("read_file", known: known) == "read_file")
        #expect(TextToolCalls.repairName("unread_file", known: known) == nil)          // not at a word boundary
        #expect(TextToolCalls.repairName("delete_everything", known: known) == nil)
    }

    @Test func loopRunsRecoveredCalls() async throws {
        let ws = try makeProject()
        let textCall = SSE.content(#"Reading it now.[TOOL_CALLS]read_file {"path": "README.md"}"#)
        let (client, _) = MockServer.client(.init(turns: [textCall, SSE.content("It is a demo.")]))
        final class Box: @unchecked Sendable { let l = NSLock(); var r: [ChatMessage] = []; func add(_ m: ChatMessage) { l.withLock { r.append(m) } } }
        let box = Box()
        var config = AgentConfig(tools: ReadTools.all)
        config.historyShape = HistoryShape(parseTextToolCalls: true)
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("what is it?")], config: config,
                            workspace: ws) { if case .toolFinished(let m) = $0 { box.add(m) } }
        #expect(box.r.first?.content.contains("# Demo") == true)
    }
}
