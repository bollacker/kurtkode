import Foundation
import Testing
@testable import AgentCore

private func temp(_ name: String) -> URL { FileManager.default.temporaryDirectory.appending(path: "kk-\(name)-\(UUID().uuidString.prefix(6))") }

private func object(_ data: Data) throws -> [String: JSONValue] {
    guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
    return o
}

/// A recorded turn: run the loop once with a wire log, return the record of its first reply and the reply.
private func recordedTurn() async throws -> (WireRecord, ChatMessage, URL) {
    let ws = try makeProject()
    let wire = temp("wire")
    let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#), SSE.content("Done.")]))
    var config = AgentConfig(tools: AllTools.all)
    config.wireLog = WireLog(directory: wire)
    config.providers = ProviderRouting(order: ["A"])
    final class Box: @unchecked Sendable { var replies: [ChatMessage] = [] }
    let box = Box()
    await AgentLoop.run(client: client, model: "m", systemPrompt: "SYSTEM", history: [.user("Read the README")], config: config,
                        workspace: ws) { if case .assistant(let m) = $0 { box.replies.append(m) } }
    let first = try #require(box.replies.first)
    return (try #require(WireLog.read(wire, replyID: first.id)), first, wire)
}

@Suite struct ReplayTests {
    @Test func sweepsEffortLevelsAndComparesThem() async throws {
        let (record, original, wire) = try await recordedTurn()
        // "none" answers at once; "high" reads another file than the original did.
        let (client, host) = MockServer.client(.init(turns: [SSE.content("It's a demo."),
                                                             SSE.toolCall("y", "read_file", #"{"path":"docs/guide.md"}"#)]))
        let rs = await Replay.sweep(record, client: client, endpointName: "Mock", endpointID: nil, model: "m",
                                    levels: ["none", "high"], wire: wire)
        #expect(rs.map { $0.options.reasoningEffort } == ["none", "high"])
        #expect(MockServer.requestBodies(host).compactMap { try? object($0)["reasoning_effort"] } == ["none", "high"])
        #expect(Replay.load(wire, sourceReply: original.id).count == 2)
        let rows = Replay.effortRows(original: original, replays: rs)
        #expect(rows.map(\.level) == ["as recorded", "none", "high"])
        #expect(rows.map(\.actions) == ["read_file README.md", "answer", "read_file docs/guide.md"])
        #expect(rows.map(\.sameCallsAsOriginal) == [true, false, false])

        #expect(Replay.effortLevels(api: .anthropic, model: "claude-opus-5-5") == ["low", "medium", "high", "xhigh", "max"])
        #expect(Replay.effortLevels(api: .anthropic, model: "claude-haiku-4-5").first == "none")
        #expect(Replay.effortLevels(api: .gemini, model: "gemini-3-flash-preview").first == "minimal")
        #expect(Replay.effortLevels(api: .openai, model: "qwen") == ["none", "low", "medium", "high"])
    }

    @Test func replaysWithChangesAndComparesWithTheOriginal() async throws {
        let (record, original, wire) = try await recordedTurn()
        let (client, host) = MockServer.client(.init(turns: [SSE.toolCall("x", "read_file", #"{"path": "src/main.swift"}"#)]))
        let options = ReplayOptions(model: "other-model", temperature: 0.2, reasoningEffort: "none", systemPrompt: "NEW SYSTEM")
        let r = await Replay.run(record, client: client, endpointName: "Mock", endpointID: nil, options: options)
        let sent = try object(try #require(MockServer.requestBodies(host).first))
        #expect(sent["model"] == "other-model" && sent["temperature"] == .number(0.2) && sent["reasoning_effort"] == "none")
        #expect(sent["provider"] == nil)                                         // the recorded routing doesn't apply elsewhere
        guard case .array(let msgs)? = sent["messages"], case .object(let sys)? = msgs.first else { Issue.record("no messages"); return }
        #expect(sys["content"] == "NEW SYSTEM")
        #expect(msgs.count == 2)                                                 // the same conversation as recorded
        #expect(r.reply.toolCalls.map(\.name) == ["read_file"] && r.sourceReply == original.id)
        #expect(r.wire.statuses == [200] && !r.wire.lines.isEmpty)

        let cmp = Replay.compare(original: original, replay: r.reply)
        #expect(!cmp.sameToolCalls && cmp.toolCallDifferences.count == 1)
        #expect(cmp.toolCallDifferences[0].hasPrefix("read_file: "))
        // The same call with other spacing counts as the same.
        var same = r.reply
        same.toolCalls = [ToolCall(id: "y", name: "read_file", arguments: #"{ "path" : "README.md" }"#)]
        #expect(Replay.compare(original: original, replay: same).sameToolCalls)

        try Replay.save(r, wire: wire)
        #expect(Replay.load(wire, sourceReply: original.id).map(\.id) == [r.id])
    }

    @Test func imagesThatWerentRecordedAreLeftOutWithAWarning() throws {
        let request: JSONValue = ["model": "m", "messages": [
            ["role": "user", "content": [["type": "text", "text": "what is this"],
                                         ["type": "image_url", "image_url": ["url": "[image, 120 KB as a data URL]"]]]],
        ]]
        let record = WireRecord(replyID: UUID(), startedAt: Date(), duration: 1, url: "http://127.0.0.1:1234/v1/chat/completions",
                                request: request, statuses: [200], lines: [])
        let (body, warnings) = try Replay.body(from: record, options: ReplayOptions(model: "m"))
        #expect(warnings == ["1 image isn't in the record; replayed without it."])
        #expect(!String(decoding: body, as: UTF8.self).contains("[image,"))
    }

    @Test func copiesATurnAsCurl() async throws {
        let (record, _, _) = try await recordedTurn()
        let local = Replay.curl(record)
        #expect(local.contains("curl -sN '\(record.url)'") && local.contains("<<'KURTKODE_JSON'") && local.hasSuffix("KURTKODE_JSON"))
        #expect(local.contains("$KURTKODE_API_KEY"))                   // the mock's host isn't this Mac: a key placeholder
        var remote = record
        remote.url = "https://openrouter.ai/api/v1/chat/completions"
        let r = Replay.curl(remote)
        #expect(r.contains(#"-H "Authorization: Bearer $KURTKODE_API_KEY""#))
        let json = r.components(separatedBy: "<<'KURTKODE_JSON'\n")[1].components(separatedBy: "\nKURTKODE_JSON")[0]
        let o = try object(Data(json.utf8))
        #expect(o["provider"] != nil && o["stream"] == true)              // as recorded, routing kept
        var lan = record
        lan.url = "http://127.0.0.1:1234/v1/chat/completions"
        #expect(!Replay.curl(lan).contains("Authorization"))
    }
}

@Suite struct ForkAndExportTests {
    /// A stored session: ask, a turn with a read, a final answer; wire records and index for both replies.
    private func storedSession() async throws -> (SessionStore, Session) {
        let ws = try makeProject()
        let store = SessionStore(root: temp("store"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path)
        try await store.create(header)
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#), SSE.content("It's a demo.")]))
        var config = AgentConfig(tools: AllTools.all)
        config.wireLog = WireLog(directory: store.wireDirectory(for: header))
        let ask = ChatMessage.user("What is this project?")
        try await store.append(.message(ask), to: header.id)
        final class Box: @unchecked Sendable { var records: [SessionRecord] = [] }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [ask], config: config, workspace: ws) { e in
            switch e {
            case .assistant(let m), .toolFinished(let m): box.records.append(.message(m))
            default: break
            }
        }
        for r in box.records { try await store.append(r, to: header.id) }
        try await store.append(.title("Demo"), to: header.id)
        return (store, try #require(try await store.load(header.id)))
    }

    @Test func forksBeforeAndAfterATurn() async throws {
        let (store, s) = try await storedSession()
        let turn = try #require(s.messages.first { $0.role == .assistant })
        let before = try await store.fork(s, atReply: turn.id, after: false, title: "Fork before turn 1")
        #expect(before.messages.map(\.role) == [.user])
        #expect(before.header.forkedFrom == s.header.id && before.header.forkedAtReply == turn.id && before.header.forkedAfter == false)
        #expect(before.title == "Fork before turn 1" && before.header.workspace == s.header.workspace)
        #expect(WireLog.contexts(store.wireDirectory(for: before.header)).isEmpty)    // no turn of its own yet

        let after = try await store.fork(s, atReply: turn.id, after: true, title: "Fork after turn 1")
        #expect(after.messages.map(\.role) == [.user, .assistant, .tool])
        #expect(after.messages.last?.content.contains("Demo") == true)
        let wire = store.wireDirectory(for: after.header)
        #expect(WireLog.read(wire, replyID: turn.id) != nil)                           // the turn's record came along
        #expect(WireLog.contexts(wire).map(\.replyID) == [turn.id])
        #expect(try await store.list().count == 3)                                      // forks are sessions of their own
    }

    @Test func exportsMarkdownAndJSON() async throws {
        let (_, s) = try await storedSession()
        let md = SessionExport.markdown(s, maxResultLines: 2)
        #expect(md.hasPrefix("# Demo\n"))
        #expect(md.contains("## You\n\nWhat is this project?"))
        #expect(md.contains("## Turn 1 · `") && md.contains("**read_file** `{\"path\":\"README.md\"}`"))
        #expect(md.contains("… (") && md.contains("more lines)"))                     // the read's result, shortened
        #expect(md.contains("## Turn 2 · `") && md.contains("It's a demo."))
        let json = try object(SessionExport.json(s))
        #expect(json["format"] == "kurtkode-session" && json["title"] == "Demo")
        if case .array(let m)? = json["messages"] { #expect(m.count == 4) } else { Issue.record("no messages") }
    }

    @Test func summaryRequestsGoToTheWireLog() async throws {
        let ws = try makeProject()
        let big = (1...400).map { "let value\($0) = compute(\($0)) // some explanatory text to take up room" }.joined(separator: "\n")
        for f in ["Big.swift", "Big2.swift"] { try Data(big.utf8).write(to: ws.root.appending(path: f)) }
        let wire = temp("wire")
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("r1", "read_file", #"{"path":"Big.swift"}"#), SSE.toolCall("r2", "read_file", #"{"path":"Big2.swift"}"#),
            SSE.content("## Summary\nRead Big.swift and Big2.swift; each defines 400 computed values. Next: answer."),
            SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all, context: ContextBudget(limit: 12_000, outputReserve: 500))
        config.wireLog = WireLog(directory: wire)
        final class Box: @unchecked Sendable { var c: Compaction? }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")], config: config, workspace: ws) {
            if case .compacted(let c) = $0 { box.c = c }
        }
        let ids = try #require(box.c?.summaryRequests)
        #expect(ids.count == 1)
        let rec = try #require(WireLog.read(wire, replyID: ids[0]))
        #expect(rec.messages.last.map { if case .object(let o) = $0, case .string(let t)? = o["content"] { t.hasPrefix("Summarize this session") } else { false } } == true)
    }
}
