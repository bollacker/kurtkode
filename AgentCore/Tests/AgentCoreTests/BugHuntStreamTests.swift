import Foundation
import Testing
@testable import AgentCore

/// Bug hunt 2026-11-02, items 27 (stream line splitting, multi-line SSE events, a 200 that is not a stream) and 28
/// (parallel tool calls without distinct indexes, repeated names).
@Suite struct BugHuntStreamTests {
    /// Streams one reply from `route` and folds it; the error the stream ended with, if any.
    func drain(_ route: MockServer.Route, api: WireAPI = .openai) async -> (TurnAccumulator, Error?) {
        let (client, _) = MockServer.client(route, api: api)
        var acc = TurnAccumulator()
        do {
            for try await e in client.stream(ChatRequest(model: "test-model", messages: [.user("hi")], maxTokens: 100)) { acc.apply(e) }
            return (acc, nil)
        } catch {
            return (acc, error)
        }
    }

    static let separators = "a\u{2028}b\u{2029}c\u{85}d"

    // MARK: 27

    @Test func rawLineSeparatorsInContentDoNotCutTheLine() async throws {
        // The characters raw inside the JSON string, as LM Studio and llama.cpp send them.
        let (acc, error) = await drain(.init(chunks: [
            SSE.line(#"{"model":"m","choices":[{"index":0,"delta":{"content":"\#(Self.separators)"},"finish_reason":null}]}"#),
            SSE.line(#"{"model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#),
            Data("data: [DONE]\n".utf8),
        ]))
        #expect(error == nil)
        #expect(acc.snapshot.content == Self.separators)
    }

    @Test func rawLineSeparatorsInToolArgumentsDoNotCutTheLine() async throws {
        let args = #"{\"text\":\"\#(Self.separators)\"}"#
        let (acc, error) = await drain(.init(chunks: [
            SSE.line(#"{"model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"write","arguments":"\#(args)"}}]},"finish_reason":null}]}"#),
            SSE.line(#"{"model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#),
        ]))
        #expect(error == nil)
        #expect(acc.snapshot.toolCalls.map(\.arguments) == [#"{"text":"\#(Self.separators)"}"#])
    }

    @Test func rawLineSeparatorsOnTheAnthropicWire() async throws {
        let events = [
            #"{"type":"message_start","message":{"model":"claude-x","usage":{"input_tokens":10}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(Self.separators)"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
        ]
        // Anthropic's own framing: an event line, the data, a blank line; CRLF line ends here.
        let (acc, error) = await drain(.init(chunks: events.map { Data("event: x\r\ndata: \($0)\r\n\r\n".utf8) }), api: .anthropic)
        #expect(error == nil)
        #expect(acc.snapshot.content == Self.separators)
    }

    @Test func joinsAnEventSplitAcrossDataLines() async throws {
        // One event over three `data:` lines, ended by a blank line, then a one-line event without a blank line.
        let body = "data: {\"model\":\"m\",\"choices\":[{\"index\":0,\n"
            + "data: \"delta\":{\"content\":\"Hello\"},\n"
            + "data: \"finish_reason\":null}]}\n\n"
            + "data: {\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n"
            + "data: [DONE]\n"
        // Delivered a few bytes at a time, so lines arrive in pieces too.
        let bytes = Array(body.utf8)
        let chunks = stride(from: 0, to: bytes.count, by: 7).map { Data(bytes[$0..<min($0 + 7, bytes.count)]) }
        let (acc, error) = await drain(.init(chunks: chunks))
        #expect(error == nil)
        #expect(acc.snapshot.content == "Hello")
        #expect(acc.finishReason == .stop)
    }

    @Test func aBrokenEventIsStillMalformed() async throws {
        let (_, error) = await drain(.init(chunks: [Data("data: {\"choices\":[\n\ndata: [DONE]\n".utf8)]))
        guard case .malformedChunk? = error as? ChatError else { Issue.record("got \(String(describing: error))"); return }
    }

    @Test func aPlainJSONErrorWithStatus200SaysWhatTheServerSaid() async throws {
        let (_, error) = await drain(.init(chunks: [Data(#"{"error":{"message":"Model is not loaded","code":"x"}}"#.utf8)]))
        #expect(error as? ChatError == .server("Model is not loaded"))
        // Pretty-printed, over several lines.
        let pretty = "{\n  \"error\": {\n    \"message\": \"quota exceeded\"\n  }\n}\n"
        let (_, error2) = await drain(.init(chunks: [Data(pretty.utf8)]))
        #expect(error2 as? ChatError == .server("quota exceeded"))
        // A whole non-streamed completion (a server ignoring `stream`): said so, not "the connection closed".
        let (_, error3) = await drain(.init(chunks: [Data(#"{"choices":[{"message":{"content":"hi"}}]}"#.utf8)]))
        guard case .server(let m)? = error3 as? ChatError else { Issue.record("got \(String(describing: error3))"); return }
        #expect(m.hasPrefix("the server sent this instead of a stream"))
        // An empty 200 is still a cut stream.
        let (_, error4) = await drain(.init(chunks: []))
        #expect(error4 as? ChatError == .streamCut)
    }

    @Test func splitsLinesOnNewlineOnly() async throws {
        let text = "one\r\ntwo\u{2028}still two\n\nthree"
        struct Bytes: AsyncSequence {
            typealias Element = UInt8
            let bytes: [UInt8]
            func makeAsyncIterator() -> AsyncStream<UInt8>.Iterator {
                AsyncStream { c in for b in bytes { c.yield(b) }; c.finish() }.makeAsyncIterator()
            }
        }
        var lines: [String] = []
        for try await l in ByteLines(base: Bytes(bytes: Array(text.utf8))) { lines.append(l) }
        #expect(lines == ["one", "two\u{2028}still two", "", "three"])
    }

    // MARK: 28

    func calls(_ deltas: [StreamEvent]) -> [ToolCall] {
        var acc = TurnAccumulator()
        for d in deltas { acc.apply(d) }
        return acc.snapshot.toolCalls
    }

    @Test func parallelCallsUnderOneIndexStaySeparate() {
        let c = calls([
            .toolCallDelta(index: 0, id: "a", name: "read_file", arguments: nil),
            .toolCallDelta(index: 0, id: nil, name: nil, arguments: #"{"path":"x"}"#),
            .toolCallDelta(index: 0, id: "b", name: "read_file", arguments: nil),
            .toolCallDelta(index: 0, id: nil, name: nil, arguments: #"{"path":"y"}"#),
        ])
        #expect(c.map(\.id) == ["a", "b"])
        #expect(c.map(\.name) == ["read_file", "read_file"])
        #expect(c.map(\.arguments) == [#"{"path":"x"}"#, #"{"path":"y"}"#])
    }

    @Test func parallelCallsWithoutIndexOnTheWireStaySeparate() throws {
        // Some Ollama versions: no `index` at all, one call per chunk, each whole.
        let chunk = { (id: String, path: String) in
            #"{"choices":[{"index":0,"delta":{"tool_calls":[{"id":"\#(id)","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"\#(path)\"}"}}]}}]}"#
        }
        var acc = TurnAccumulator()
        for e in try WireFormat.events(fromChunk: Data(chunk("call_1", "a").utf8)) + WireFormat.events(fromChunk: Data(chunk("call_2", "b").utf8)) {
            acc.apply(e)
        }
        #expect(acc.snapshot.toolCalls.map(\.name) == ["read_file", "read_file"])
        #expect(acc.snapshot.toolCalls.map(\.arguments) == [#"{"path":"a"}"#, #"{"path":"b"}"#])
    }

    @Test func aNameRepeatedInEveryDeltaIsNotDoubled() {
        let c = calls([
            .toolCallDelta(index: 0, id: "a", name: "bash", arguments: #"{"com"#),
            .toolCallDelta(index: 0, id: "a", name: "bash", arguments: #"mand":"ls"}"#),
            .toolCallDelta(index: 0, id: nil, name: "bash", arguments: nil),
        ])
        #expect(c.map(\.name) == ["bash"])
        #expect(c.map(\.arguments) == [#"{"command":"ls"}"#])
    }

    @Test func aNameSplitAcrossDeltasIsJoined() {
        #expect(calls([
            .toolCallDelta(index: 0, id: "a", name: "read", arguments: nil),
            .toolCallDelta(index: 0, id: nil, name: "_file", arguments: "{}"),
        ]).map(\.name) == ["read_file"])
        // The name so far, repeated and growing.
        #expect(calls([
            .toolCallDelta(index: 0, id: "a", name: "read", arguments: nil),
            .toolCallDelta(index: 0, id: nil, name: "read_file", arguments: "{}"),
        ]).map(\.name) == ["read_file"])
    }

    @Test func theOpenAIShapeIsUnchanged() {
        // OpenAI: id and name once, at distinct indexes, arguments in pieces, the id never repeated.
        let c = calls([
            .toolCallDelta(index: 0, id: "call_1", name: "read_file", arguments: ""),
            .toolCallDelta(index: 1, id: "call_2", name: "grep", arguments: ""),
            .toolCallDelta(index: 0, id: nil, name: nil, arguments: #"{"path":"#),
            .toolCallDelta(index: 1, id: nil, name: nil, arguments: #"{"pattern":"x"}"#),
            .toolCallDelta(index: 0, id: nil, name: nil, arguments: #""a"}"#),
        ])
        #expect(c.map(\.id) == ["call_1", "call_2"])
        #expect(c.map(\.name) == ["read_file", "grep"])
        #expect(c.map(\.arguments) == [#"{"path":"a"}"#, #"{"pattern":"x"}"#])
    }
}
