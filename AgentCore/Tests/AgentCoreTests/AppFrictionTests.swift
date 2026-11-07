import Foundation
import Testing
@testable import AgentCore

// The app's everyday friction (GAP_ANALYSIS.md C5, C7, U5): the logic behind the composer, transcript and sidebar.

private func reply(_ calls: [(id: String, name: String, args: String)], content: String = "", meta: TurnMeta? = nil) -> ChatMessage {
    ChatMessage(role: .assistant, content: content, toolCalls: calls.map { ToolCall(id: $0.id, name: $0.name, arguments: $0.args) }, meta: meta)
}

private func result(_ id: String, _ text: String = "ok", error: Bool = false, denied: Bool = false) -> ChatMessage {
    var info = ToolResultInfo(toolName: "read_file", isError: error, truncated: false, duration: 0)
    info.denied = denied
    return ChatMessage(role: .tool, content: text, toolCallID: id, toolResult: info)
}

private func rows(_ messages: [ChatMessage], breakAfter: (ChatMessage) -> Bool = { _ in false }) -> [TranscriptRow] {
    TranscriptRow.rows(messages, results: ChatMessage.resultsByReply(messages), breakAfter: breakAfter)
}

private func session(_ messages: [ChatMessage], runs: [AgentRunRecord] = []) -> Session {
    var s = Session(header: SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: nil), messages: messages, model: "m")
    s.runs = runs
    return s
}

@Suite struct PastedTextTests {
    @Test func onlyLongPastesBecomeTokens() {
        #expect(!PastedText.isLong("short"))
        #expect(!PastedText.isLong(String(repeating: "line\n", count: 10)))
        #expect(PastedText.isLong(String(repeating: "line\n", count: 12)))
        #expect(PastedText.isLong(String(repeating: "x", count: 800)))
    }

    @Test func tokensExpandToTheirTextAndNothingElseDoes() {
        let a = PastedText(id: 1, text: "one\ntwo\n"), b = PastedText(id: 2, text: "three")
        #expect(a.token == "[Pasted text #1: 2 lines]" && b.token == "[Pasted text #2: 1 line]")
        let draft = "before \(a.token) mid \(b.token) and [Pasted text #9: 3 lines]"
        #expect(PastedText.expand(draft, [a, b]) == "before one\ntwo\n mid three and [Pasted text #9: 3 lines]")
    }
}

@Suite struct PromptRecallTests {
    @Test func goesBackThenForwardToWhatWasTyped() {
        var r = PromptRecall(entries: ["first", "second"])
        #expect(r.newer() == nil)                               // nothing recalled yet: ↓ does nothing
        #expect(r.older(draft: "half typed") == "second")
        #expect(r.older(draft: "second") == "first")
        #expect(r.older(draft: "first") == nil)                 // the oldest stays
        #expect(r.newer() == "second")
        #expect(r.newer() == "half typed")
        #expect(r.newer() == nil)
    }

    @Test func noHistoryLeavesTheDraftAlone() {
        var r = PromptRecall(entries: [])
        #expect(r.older(draft: "text") == nil)
    }

    @Test func promptsAreWhatTheUserAsked() {
        var command = ChatMessage.user("output")
        command.userCommand = UserCommandInfo(command: "ls", output: "output", exitCode: 0)
        var note = ChatMessage.user("the date is")
        note.contextNote = true
        var report = ChatMessage.user("a subagent reported")
        report.subagentReport = UUID()
        let s = session([.user("one"), .user("one"), note, command, report, .user("two"), reply([], content: "hi")])
        #expect(s.prompts == ["one", "!ls", "two"])
    }
}

@Suite struct SlashCommandsWhileRunningTests {
    @Test func onlyCommandsThatShowSomethingAnswerDuringARun() {
        #expect(SlashCommands.answersWhileRunning.isSubset(of: Set(SlashCommands.builtIns.map(\.name))))
        for name in ["compact", "clear", "model", "retry", "rewind", "review", "init", "mode"] {
            #expect(!SlashCommands.answersWhileRunning.contains(name))
        }
    }
}

@Suite struct TranscriptRowTests {
    @Test func looksAroundFoldIntoOneRow() {
        let a = reply([("1", "read_file", #"{"path":"a.swift"}"#)])
        let b = reply([("2", "grep", #"{"pattern":"x"}"#), ("3", "read_file", #"{"path":"b.swift"}"#)])
        let user = ChatMessage.user("go")
        let edit = reply([("4", "edit_file", #"{"path":"a.swift"}"#)])
        let out = rows([user, a, result("1"), b, result("2"), result("3"), edit, result("4")])
        #expect(out.map(\.id) == [user.id, a.id, edit.id])
        guard case .tools(let group) = out[1] else { Issue.record("no group"); return }
        #expect(group.map(\.id) == [a.id, b.id])
    }

    @Test func aRowKeepsItsIdentityAsItsGroupGrows() {
        let a = reply([("1", "read_file", #"{"path":"a"}"#)])
        let b = reply([("2", "read_file", #"{"path":"b"}"#)])
        let one = rows([a, result("1")]), two = rows([a, result("1"), b, result("2")])
        guard case .message = one[0], case .tools = two[0] else { Issue.record("wrong rows"); return }
        #expect(one[0].id == two[0].id)
    }

    @Test func whatDeservesAttentionStaysOnItsOwnRow() {
        let said = reply([("1", "read_file", #"{"path":"a"}"#)], content: "Let me look at the failing test first.")
        let command = reply([("2", "bash", #"{"command":"ls"}"#)])
        let denied = reply([("3", "read_file", #"{"path":"b"}"#)])
        let failed = reply([("4", "read_file", #"{"path":"c"}"#)], meta: TurnMeta(requestedModel: "m", stopReason: .failed, duration: 1))
        let out = rows([said, result("1"), command, result("2"), denied, result("3", denied: true), failed])
        #expect(out.count == 4)
        #expect(out.allSatisfy { if case .message = $0 { true } else { false } })
    }

    @Test func aSummaryOrADividerBetweenRepliesEndsAGroup() {
        let a = reply([("1", "read_file", #"{"path":"a"}"#)]), b = reply([("2", "glob", #"{"pattern":"x"}"#)])
        let c = reply([("3", "list_dir", #"{}"#)])
        let out = rows([a, result("1"), b, result("2"), c, result("3")]) { $0.id == a.id }
        #expect(out.map(\.id) == [a.id, b.id])
    }

    @Test func aGroupSaysWhatItDid() {
        func call(_ name: String, _ args: String = "{}") -> ToolCall { ToolCall(id: UUID().uuidString, name: name, arguments: args) }
        let calls = [call("read_file", #"{"path":"a"}"#), call("read_file", #"{"path":"a","offset":90}"#),
                     call("read_file", #"{"path":"b"}"#), call("grep"), call("glob"), call("list_dir"), call("todo_write")]
        #expect(ToolGroupSummary.text(calls) == "Read 2 files, searched 2 times, listed 1 folder, updated the todo list")
        #expect(ToolGroupSummary.text([call("grep")]) == "Searched 1 time")
    }
}

@Suite struct TranscriptSearchTests {
    @Test func findsWordsWhereverTheyShowAndCountsToolOutputForItsReply() {
        var note = ChatMessage.user("needle in a note")
        note.contextNote = true
        let asked = ChatMessage.user("Find the NEEDLE")
        let looked = reply([("1", "grep", #"{"pattern":"elsewhere"}"#)])
        let answered = reply([], content: "nothing here")
        let messages = [note, asked, looked, result("1", "src/a.swift: needle"), answered]
        #expect(TranscriptSearch.hits(messages, query: "needle") == [asked.id, looked.id])
        #expect(TranscriptSearch.hits(messages, query: "elsewhere") == [looked.id])
        #expect(TranscriptSearch.hits(messages, query: "  ").isEmpty)
    }
}

@Suite struct InterruptedRunTests {
    private func ended(after: Date) -> AgentRunRecord {
        var r = AgentRunRecord.test(agent: "main")
        r.ended = after.addingTimeInterval(1)
        return r
    }

    @Test func aRequestOrCallLeftWithoutARunsEndIsInterrupted() {
        #expect(session([.user("go")]).wasInterrupted)
        #expect(session([.user("go"), reply([("1", "bash", "{}")])]).wasInterrupted)
        #expect(session([.user("go"), reply([("1", "bash", "{}")]), result("1")]).wasInterrupted)
    }

    @Test func aRunThatEndedIsnt() {
        let waiting = result("1")
        let s = session([.user("go"), reply([("1", "bash", "{}")]), waiting], runs: [ended(after: waiting.createdAt)])
        #expect(!s.wasInterrupted)                              // stopped, or paused at a limit: it left a record
    }

    @Test func aFinishedChatIsnt() {
        #expect(!session([]).wasInterrupted)
        #expect(!session([.user("go"), reply([], content: "done")]).wasInterrupted)
        var command = ChatMessage.user("output")
        command.userCommand = UserCommandInfo(command: "ls", output: "output", exitCode: 0)
        #expect(!session([command]).wasInterrupted)
    }

    @Test func anEarlierRunsEndDoesntCoverALaterRequest() {
        let old = reply([], content: "done")
        let run = ended(after: old.createdAt)
        var later = ChatMessage.user("again")
        later.createdAt = run.ended.addingTimeInterval(5)
        #expect(session([old, later], runs: [run]).wasInterrupted)
    }

    @Test func aSubagentsRunDoesntCount() {
        let m = ChatMessage.user("go")
        var r = ended(after: m.createdAt)
        r.agent = "explore"
        #expect(session([m], runs: [r]).wasInterrupted)
    }

    @Test func aNoteAfterTheCutOffDoesntHideIt() {
        var note = ChatMessage.user("the date is")
        note.contextNote = true
        #expect(session([.user("go"), note]).wasInterrupted)
        #expect(!session([reply([], content: "done"), note]).wasInterrupted)
    }
}

@Suite struct ForkAtARequestTests {
    private func stored() async throws -> (SessionStore, Session, ChatMessage) {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-fork-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
        try await store.create(header)
        let second = ChatMessage.user("second")
        for m in [ChatMessage.user("first"), reply([], content: "one"), second, reply([], content: "two")] {
            try await store.append(.message(m), to: header.id)
        }
        return (store, try #require(try await store.load(header.id)), second)
    }

    @Test func keepsWhatCameBeforeTheRequest() async throws {
        let (store, s, second) = try await stored()
        let fork = try await store.fork(s, before: second.id, title: "Try again")
        #expect(fork.messages.map(\.content) == ["first", "one"])
        #expect(fork.header.forkedFrom == s.header.id && fork.title == "Try again" && fork.model == "m")
        #expect(try await store.load(s.header.id)?.messages.count == 4)         // the original is as it was
    }

    @Test func noRequestCopiesTheWholeChat() async throws {
        let (store, s, _) = try await stored()
        #expect(try await store.fork(s, before: nil, title: "Copy").messages.count == 4)
    }

    @Test func aMessageThatIsntThereFails() async throws {
        let (store, s, _) = try await stored()
        await #expect(throws: (any Error).self) { try await store.fork(s, before: UUID(), title: "x") }
    }
}

@Suite struct SessionSearchTests {
    private func store(_ chats: [(title: String, messages: [ChatMessage])]) async throws -> (SessionStore, [UUID]) {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-find-\(UUID().uuidString.prefix(8))"))
        var ids: [UUID] = []
        for c in chats {
            let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: "/tmp/p")
            try await store.create(header)
            try await store.append(.title(c.title), to: header.id)
            for m in c.messages { try await store.append(.message(m), to: header.id) }
            ids.append(header.id)
        }
        return (store, ids)
    }

    @Test func findsTheChatsThatHoldTheWords() async throws {
        let (store, ids) = try await store([("a", [.user("the Sandbox denies writes"), reply([], content: "fixed")]),
                                            ("b", [.user("nothing relevant"), reply([], content: "ok")])])
        let hits = try await store.search("sandbox")
        #expect(hits.map(\.id) == [ids[0]])
        #expect(hits[0].snippet == "the Sandbox denies writes")
    }

    @Test func wordsThatJSONEscapesAreFoundToo() async throws {
        let (store, ids) = try await store([("a", [.user("look in src/main.swift"), reply([], content: "said \"hello\" to café")])])
        #expect(try await store.search("src/main").map(\.id) == ids)
        #expect(try await store.search("\"hello\"").map(\.id) == ids)
        #expect(try await store.search("café").map(\.id) == ids)
    }

    @Test func toolOutputAndNotesDontCount() async throws {
        var note = ChatMessage.user("needle")
        note.contextNote = true
        let (store, _) = try await store([("a", [note, reply([("1", "bash", "{}")]), result("1", "needle")])])
        #expect(try await store.search("needle").isEmpty)
    }

    @Test func aLongMessageGivesOneLineAroundTheMatch() {
        let text = String(repeating: "before ", count: 20) + "needle\nand " + String(repeating: "after ", count: 20)
        let snippet = SessionSearchHit.snippet(text, around: text.range(of: "needle")!)
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…") && snippet.contains("needle and"))
        #expect(!snippet.contains("\n") && snippet.count < 110)
    }
}

@Suite struct ChatTitleTests {
    @Test func aShortOneLineRequestIsItsOwnTitle() {
        #expect(!ChatTitle.worthWriting(request: "Fix the failing test"))
        #expect(ChatTitle.worthWriting(request: String(repeating: "word ", count: 20)))
        #expect(ChatTitle.worthWriting(request: "Fix this\nHere is the log"))
    }

    @Test func aRepliesDecorationComesOff() {
        #expect(ChatTitle.clean("\n  \"Fix the login redirect.\"\nMore text") == "Fix the login redirect")
        #expect(ChatTitle.clean("Title: Refactor the parser") == "Refactor the parser")
        #expect(ChatTitle.clean("**Add dark mode**") == "Add dark mode")
        #expect(ChatTitle.clean("  \n ") == nil)
        #expect(ChatTitle.clean("...") == nil)
        #expect(ChatTitle.clean(String(repeating: "x", count: 90))?.count == 60)
    }

    @Test func writesATitleAndRecordsItsCost() async throws {
        let (client, host) = MockServer.client(.init(chunks: SSE.content("Fix the parser")))
        let box = Box()
        let sink = CostSink(scope: CostScope(run: nil, agent: "main"), endpointID: nil) { box.add($0) }
        let title = await ChatTitle.write(request: "the long request", reply: "the reply", client: client, model: "m",
                                          limits: TurnLimits(), costs: sink)
        #expect(title == "Fix the parser")
        #expect(box.entries.map(\.purpose) == [.title])
        let body = String(decoding: try #require(MockServer.requestBody(host)), as: UTF8.self)
        #expect(body.contains("the long request") && body.contains("the reply"))
        #expect(!body.contains("\"tools\":[{"))
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [CostEntry] = []
        var entries: [CostEntry] { lock.withLock { stored } }
        func add(_ e: CostEntry) { lock.withLock { stored.append(e) } }
    }

    @Test func aFailedRequestGivesNoTitle() async {
        let (client, _) = MockServer.client(.init(status: 500, chunks: []))
        let title = await ChatTitle.write(request: "r", reply: "a", client: client, model: "m", limits: TurnLimits())
        #expect(title == nil)
    }
}
