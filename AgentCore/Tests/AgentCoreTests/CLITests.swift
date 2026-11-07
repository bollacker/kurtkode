import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

/// Settings in a temporary data folder with one OpenAI-style endpoint ("mock") and an empty defaults domain.
private func testSettings() throws -> AppSettings {
    let support = FileManager.default.temporaryDirectory.appending(path: "kk-cli-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://mock.invalid/v1")!)
    try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock])
    let suite = "kk-cli-tests-\(UUID().uuidString.prefix(8))"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(mock.id.uuidString, forKey: "defaultEndpointID")
    defaults.set("test-model", forKey: "defaultModel")
    // The skill router would ask the mock server a question of its own first; these tests script the agent's turns.
    defaults.set(SkillRouting.off.rawValue, forKey: RunSettings.Key.skillRouting)
    return AppSettings(support: support, defaults: defaults, environment: [:])
}

@Suite struct CLIOptionsTests {
    @Test func parsesFlagsAndPrompt() throws {
        let o = try CLIOptions.parse(["-p", "--mode", "auto", "-m", "lmstudio:qwen/qwen3-coder-30b", "--output", "json",
                                      "explain", "the", "build", "--no-mcp"])
        #expect(o.printMode && o.mode == .fullAuto && o.output == .json && !o.mcp)
        #expect(o.model == "lmstudio:qwen/qwen3-coder-30b")
        #expect(o.prompt == "explain the build")
        #expect(try CLIOptions.parse(["--", "-not-a-flag"]).prompt == "-not-a-flag")
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["--mode", "yolo"]) }
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["--bogus"]) }
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["-c", "-r", "abc"]) }
    }

    @Test func splitsModelSpecsOnlyAtKnownEndpoints() throws {
        let s = try testSettings()
        let (e1, m1) = CLIOptions.splitModel("mock:qwen/qwen3-coder", settings: s)
        #expect(e1.name == "Mock" && m1 == "qwen/qwen3-coder")
        let (e2, m2) = CLIOptions.splitModel("google/gemma-4-26b-a4b-it:free", settings: s)     // a colon in the model id
        #expect(e2.name == "Mock" && m2 == "google/gemma-4-26b-a4b-it:free")
        #expect(CLIOptions.splitModel("lmstudio:x", settings: s).0.id == Endpoint.localLMStudio.id)
    }
}

@Suite struct CLISessionTests {
    @Test func printModeRunsSavesAndRefusesApprovals() async throws {
        let settings = try testSettings()
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_0", "read_file", ##"{"path":"README.md"}"##),
            SSE.toolCall("call_1", "edit_file", ##"{"path":"README.md","old_string":"# Demo","new_string":"# Demo!"}"##),
            SSE.content("I couldn't edit it here; change the title to \"# Demo!\" yourself."),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        var output = ""
        let renderer = Renderer(style: .print(.json), out: { output += $0 }, err: { _ in })
        session.onEvent = { renderer.handle($0) }
        let stop = try await session.send("Add an exclamation mark to the README title.")
        renderer.finish(session: session.session.header.id, model: session.model)

        #expect(stop == .completed)
        #expect(try String(contentsOf: ws.root.appending(path: "README.md"), encoding: .utf8).hasPrefix("# Demo\n"))  // refused
        let denied = try #require(session.session.messages.first { $0.role == .tool && $0.toolCallID == "call_1" })
        #expect(denied.content.contains("can't approve actions in this run"))
        // Recorded as refused before asking (nobody was asked), not as the user's decision.
        #expect(denied.toolResult?.approval?.decider == .refused)
        #expect(denied.toolResult?.approval?.detail == "nobody to ask (kurtkode -p)")
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
        guard case .object(let o) = result else { Issue.record("not an object"); return }
        #expect(o["result"] == .string("I couldn't edit it here; change the title to \"# Demo!\" yourself."))
        #expect(o["stop"] == "completed" && o["tool_calls"] == 2)

        // It's an ordinary session file: the app lists it, and --continue picks it up.
        let saved = try #require(try await settings.sessionStore.load(session.session.header.id))
        #expect(saved.messages.count == 6 && saved.model == "test-model")
        var again = CLIOptions()
        again.continueLast = true
        let resumed = try await CLISession(settings: settings, workspace: ws.root, options: again) { _, _ in client }
        #expect(resumed.session.header.id == session.session.header.id)
        #expect(resumed.session.messages.count == 6)
    }

    /// The app added to the session this CLI has open: the next message goes on top of the whole conversation.
    @Test func reloadsWhatAnotherProcessAdded() async throws {
        let settings = try testSettings()
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [SSE.content("First."), SSE.content("Second."), SSE.content("Porcupine77.")]))
        var options = CLIOptions()
        options.mcp = false
        let mine = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        final class Notes: @unchecked Sendable { let lock = NSLock(); var items: [String] = [] }
        let notes = Notes()
        mine.onEvent = { if case .status(let t) = $0 { notes.lock.withLock { notes.items.append(t) } } }
        _ = try await mine.send("one")
        // Another process (its own store) continues the same session.
        var again = CLIOptions()
        again.continueLast = true
        again.mcp = false
        let other = try await CLISession(settings: settings, workspace: ws.root, options: again) { _, _ in client }
        #expect(other.session.header.id == mine.session.header.id)
        _ = try await other.send("remember Porcupine77")
        _ = try await mine.send("what did I ask you to remember?")
        let last = try JSONDecoder().decode(JSONValue.self, from: try #require(MockServer.requestBodies(host).last))
        guard case .object(let o) = last, case .array(let msgs) = o["messages"] else { Issue.record("body"); return }
        let users = msgs.compactMap { m -> String? in
            guard case .object(let mo) = m, mo["role"] == "user", case .string(let t) = mo["content"] else { return nil }
            return t
        }
        #expect(users == ["one", "remember Porcupine77", "what did I ask you to remember?"])
        #expect(notes.lock.withLock { notes.items }.contains { $0.contains("reloaded: 2 new messages") })
        #expect(mine.session.messages.count == 6)
    }

    /// A project opened through a symlink is the same project: one place for its sessions, and -c and
    /// --list-sessions agree from either spelling (older sessions stored under the link's path included).
    @Test func aSymlinkedProjectIsOneProject() async throws {
        let settings = try testSettings()
        let ws = try makeProject()
        let link = FileManager.default.temporaryDirectory.appending(path: "kk-link-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: ws.root)
        let (client, _) = MockServer.client(.init(turns: [SSE.content("ok")]))
        var options = CLIOptions()
        options.mcp = false
        let viaLink = try await CLISession(settings: settings, workspace: link, options: options) { _, _ in client }
        _ = try await viaLink.send("hello")
        #expect(viaLink.session.header.workspace == ws.root.path)
        // An older session, stored under the link's own path.
        let store = settings.sessionStore
        let legacy = SessionHeader(endpointID: viaLink.endpoint.id, model: "test-model", workspace: link.path)
        try await store.create(legacy)
        try await store.append(.message(.user("from before")), to: legacy.id)

        var again = CLIOptions()
        again.mcp = false
        again.continueLast = true
        let direct = try await CLISession(settings: settings, workspace: ws.root, options: again) { _, _ in client }
        let fromLink = try await CLISession(settings: settings, workspace: link, options: again) { _, _ in client }
        #expect(direct.session.header.id == fromLink.session.header.id)
        let listed = Set(try await direct.sessions().map(\.id))
        #expect(listed == Set(try await fromLink.sessions().map(\.id)))
        #expect(listed == [viaLink.session.header.id, legacy.id])
    }

    /// The same --endpoint gets the same id every run (a continued session doesn't gain a model record each time).
    @Test func launchOnlyEndpointsKeepTheirID() {
        let url = URL(string: "http://192.168.1.20:1234/v1")!
        let a = Endpoint.launchOnly(name: "lan", url: url), b = Endpoint.launchOnly(name: "lan", url: url)
        #expect(a.id == b.id)
        #expect(a.id != Endpoint.launchOnly(name: "lan", url: URL(string: "http://127.0.0.1:1234/v1")!).id)
        #expect(a.id != Endpoint.launchOnly(name: "other", url: url).id)
        #expect(a.kind == .openai && !a.usesAPIKey)
    }

    @Test func savesEachRecordAsTheRunGoes() async throws {
        // The CLI used to save a run's records only when it ended: a killed run lost them all.
        let settings = try testSettings()
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "read_file", #"{"path":"README.md"}"#),
            SSE.content("It is a demo project."),
        ]))
        var options = CLIOptions()
        options.printMode = true
        options.mcp = false
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        let root = await settings.sessionStore.root
        let id = session.session.header.id
        final class Seen: @unchecked Sendable { let lock = NSLock(); var counts: [Int] = [] }
        let seen = Seen()
        session.onEvent = { event in
            guard case .toolFinished = event else { return }
            // Read the file as the app or `kurtkode inspect` would, while the run goes on.
            let file = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.first { $0.lastPathComponent == "\(id.uuidString).jsonl" }
            let text = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            let count = text.split(separator: "\n").filter { $0.contains(#""type":"message""#) }.count
            seen.lock.withLock { seen.counts.append(count) }
        }
        let stop = try await session.send("What is this project?")
        #expect(stop == .completed)
        // When the tool result was shown: the user message, the call, and the result were already in the file.
        #expect(seen.lock.withLock { seen.counts } == [3])
    }

    @Test func aHookBlockIsPrintedOnce() {
        // The hook's notice and the call's error result used to print the same reason twice.
        var out = ""
        let renderer = Renderer(style: .interactive, out: { out += $0 }, err: { _ in })
        renderer.handle(.hookNotice("A PreToolUse hook blocked bash: no rm here"))
        var result = ChatMessage(role: .tool, content: "A hook blocked this bash call: no rm here", toolCallID: "c1")
        result.toolResult = ToolResultInfo(toolName: "bash", isError: true, truncated: false, duration: 0)
        result.toolResult?.approval = ApprovalRecord(decider: .hook, allowed: false, detail: "no rm here")
        renderer.handle(.toolFinished(result))
        #expect(out.components(separatedBy: "no rm here").count - 1 == 1)
        // Other errors still get their line.
        result.toolResult?.approval = ApprovalRecord(decider: .mode, allowed: true)
        renderer.handle(.toolFinished(result))
        #expect(out.contains("✗ A hook blocked this bash call"))
    }

    @Test func printModeReportsWhyARunFailed() throws {
        // Seen with the server down: exit 1, an empty line on stdout, nothing on stderr (it wasn't a terminal).
        let failed = ChatMessage(role: .assistant, content: "",
                                 meta: TurnMeta(requestedModel: "m", stopReason: .failed, error: "Could not connect to the server.", duration: 0))
        for format in [CLIOptions.Output.text, .json] {
            var out = "", err = ""
            let renderer = Renderer(style: .print(format), out: { out += $0 }, err: { err += $0 })
            renderer.handle(.assistant(failed))
            renderer.handle(.finished(.turnStopped(.failed)))
            renderer.finish(session: UUID(), model: "m")
            #expect(err.contains("Could not connect to the server."))
            #expect(err.contains("the model's turn stopped: failed"))
            if format == .json {
                let result = try JSONDecoder().decode(JSONValue.self, from: Data(out.utf8))
                guard case .object(let o) = result else { Issue.record("not an object"); continue }
                #expect(o["error"] == .string("Could not connect to the server."))
                #expect(o["stop"] == "turn_stopped:failed")
            }
        }
    }

    @Test func autoModeActsAndMentionsAttach() async throws {
        let settings = try testSettings()
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "edit_file", ##"{"path":"README.md","old_string":"# Demo","new_string":"# Demo!"}"##),
            SSE.content("Done."),
        ]))
        var options = CLIOptions()
        options.mode = .fullAuto
        options.mcp = false
        options.sandbox = .never
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        _ = try await session.send("Fix the title in @README.md")
        #expect(try String(contentsOf: ws.root.appending(path: "README.md"), encoding: .utf8).hasPrefix("# Demo!\n"))
        // The @ mention went in as a read_file call before the first request.
        guard case .object(let first) = try JSONDecoder().decode(JSONValue.self, from: MockServer.requestBodies(host)[0]),
              case .array(let msgs)? = first["messages"] else { Issue.record("no request"); return }
        #expect(msgs.count == 4)       // system, user, the synthetic read_file call, its result
    }
}

@Suite struct SessionRunTests {
    /// The system prompt lists the git status, which an edit changes; rebuilt per message, it would make the
    /// server re-process the whole conversation every time. Both messages must start with the same bytes.
    @Test func theSkillRouterTellsTheAgentWhichSkillToLoad() async throws {
        let settings = try testSettings()
        let ws = try makeProject(git: true)
        let (client, host) = MockServer.client(.init(turns: [
            SSE.content("fix-flaky-tests"),                                                     // the router's answer
            SSE.content("Following it."),
        ]))
        var options = CLIOptions()
        options.mcp = false
        options.skillRouting = .on
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        _ = try await session.send("test_eur fails one CI run in five but never alone")
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 2)
        // The agent's first request carries the router's note, with the skill's instructions, after the user's message.
        let agent = String(decoding: bodies[1], as: UTF8.self)
        #expect(agent.contains("skill router loaded the") && agent.contains("Prove the flake and measure it"))
        let notes = session.session.messages.filter { $0.contextNote == true }
        #expect(notes.count == 1 && notes[0].content.contains("loaded the \"fix-flaky-tests\" skill"))
        #expect(session.session.costs.contains { $0.purpose == .routing })
        // --skill-router off asks nothing.
        var off = options
        off.skillRouting = .off
        let (quiet, quietHost) = MockServer.client(.init(turns: [SSE.content("Sure.")]))
        let plain = try await CLISession(settings: settings, workspace: ws.root, options: off) { _, _ in quiet }
        _ = try await plain.send("test_eur fails one CI run in five")
        #expect(MockServer.requestBodies(quietHost).count == 1)
    }

    @Test func cliKeepsTheSystemPromptAcrossMessages() async throws {
        let settings = try testSettings()
        let ws = try makeProject(git: true)
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("call_1", "edit_file", ##"{"path":"README.md","old_string":"# Demo","new_string":"# Demo!"}"##),
            SSE.content("Done."),
            SSE.content("Still done."),
        ]))
        var options = CLIOptions()
        options.mode = .fullAuto
        options.mcp = false
        options.sandbox = .never
        let session = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        _ = try await session.send("Fix the title.")
        try Data("new\n".utf8).write(to: ws.root.appending(path: "NOTES.md"))     // one more file in git status
        _ = try await session.send("Anything else?")
        func system(_ body: Data) throws -> String? {
            guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: body),
                  case .array(let msgs)? = o["messages"], case .object(let first)? = msgs.first,
                  case .string(let text)? = first["content"] else { return nil }
            return text
        }
        let bodies = MockServer.requestBodies(host)
        #expect(bodies.count == 3)
        let first = try #require(try system(bodies[0]))
        #expect(first.contains("Uncommitted changes (7 files)"))
        #expect(try system(bodies[2]) == first)
    }

    @Test func runSettingsReadTheAppsKeysWithItsDefaults() throws {
        let d = try #require(UserDefaults(suiteName: "kk-run-\(UUID().uuidString.prefix(8))"))
        var s = RunSettings(defaults: d)
        #expect(s.maxTokens == 8192 && s.maxSteps == 100 && s.detectRepetition && s.summarizerModel == nil)
        let e = UUID()
        d.set(4096, forKey: RunSettings.Key.maxTokens)
        d.set(false, forKey: RunSettings.Key.detectRepetition)
        d.set("\(e.uuidString)|qwen/qwen3-coder-30b", forKey: RunSettings.Key.summarizerModel)
        d.set(" /tmp/a \n\n/tmp/b", forKey: RunSettings.Key.sandboxWritable)
        s = RunSettings(defaults: d)
        #expect(s.maxTokens == 4096 && !s.detectRepetition && s.sandboxWritable == ["/tmp/a", "/tmp/b"])
        #expect(s.summarizerModel == ModelRef(endpointID: e, model: "qwen/qwen3-coder-30b"))
        // The session's own model never counts as a separate summarizer.
        #expect(s.summarizer(excluding: e, "qwen/qwen3-coder-30b") == nil)
        #expect(s.summarizer(excluding: UUID(), "qwen/qwen3-coder-30b") != nil)
        var p = ModelProfile.defaults(endpointID: e, model: "m")
        p.maxOutputTokens = 1000
        #expect(s.limits(for: p).maxTokens == 1000 && !s.limits(for: p).detectRepetition)
    }

    @Test func frozenPromptChangesOnlyWithModeSandboxOrAddendum() async throws {
        let ws = try makeProject()
        let prompt = FrozenSystemPrompt()
        let a = await prompt.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        try Data("changed".utf8).write(to: ws.root.appending(path: "AGENTS.md"))
        #expect(await prompt.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "") == a)
        let plan = await prompt.text(workspace: ws, tools: AllTools.all, mode: .plan, sandbox: nil, userPrompt: "", addendum: "")
        #expect(plan != a && plan.contains("changed"))
        let chat = FrozenSystemPrompt()
        #expect(await chat.text(workspace: nil, tools: [], mode: .ask, sandbox: nil, userPrompt: "Be brief.", addendum: "No emoji.")
                == "Be brief.\n\nNo emoji.")
    }

    @Test func leanPromptKeepsTheRulesThatMatter() async throws {
        let ws = try makeProject(git: true)
        var b = SystemPromptBuilder(workspace: ws, tools: AllTools.all, mode: .acceptEdits)
        let detailed = await b.build()
        b.style = .lean
        let lean = await b.build()
        #expect(detailed.contains("grep for its name") && !lean.contains("grep for its name"))
        for kept in ["Ground what you say about files", "todo_write", "edit_file", "The user approves or denies", "- Date: ",
                     "Always answer in haiku."] {
            #expect(lean.contains(kept), "lean prompt lacks \(kept)")
        }
        #expect(lean.utf8.count < detailed.utf8.count)
        #expect(RunSettings().style(for: .anthropic) == .lean && RunSettings().style(for: .openai) == .detailed)
        // The style is part of what a session's prompt is frozen for.
        let p = FrozenSystemPrompt()
        let a = await p.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        #expect(await p.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "", style: .lean) != a)
    }

    @Test func aResumedSessionKeepsItsPromptAndIsToldTheNewFacts() async throws {
        let ws = try makeProject(git: true)
        func text(_ p: FrozenSystemPrompt, mode: PermissionMode = .ask, recorded: RecordedPrompt?, now: Date) async -> String {
            await p.text(workspace: ws, tools: AllTools.all, mode: mode, sandbox: nil, userPrompt: "", addendum: "",
                         recorded: recorded, now: now)
        }
        let day1 = Date(timeIntervalSince1970: 1_790_000_000)
        let first = FrozenSystemPrompt()
        let a = await text(first, recorded: nil, now: day1)
        let r = try #require(first.takeRecord())
        #expect(r.text == a && a.contains(r.facts) && r.facts.contains("Git branch"))
        #expect(first.takeRecord() == nil && first.takeNote() == nil)

        // Another process, nothing changed: the same prompt, nothing to record or tell.
        let same = FrozenSystemPrompt()
        #expect(await text(same, recorded: r, now: day1) == a)
        #expect(same.takeRecord() == nil && same.takeNote() == nil)

        // A day later, after the agent changed a file: still the same prompt (the server's cache holds), and a note.
        try Data("changed".utf8).write(to: ws.root.appending(path: "README.md"))
        let later = FrozenSystemPrompt()
        #expect(await text(later, recorded: r, now: day1.addingTimeInterval(86_400)) == a)
        #expect(later.takeRecord() == nil)
        let note = try #require(later.takeNote())
        let day2 = day1.addingTimeInterval(86_400).formatted(date: .complete, time: .omitted)
        #expect(note.contains("- Date: " + day2) && !a.contains(day2) && note.contains("README.md"))
        #expect(later.takeNote() == nil)
        #expect(FrozenSystemPrompt.noteMessage(note).contextNote == true)

        // Another mode, or new instructions: a new prompt, to record.
        let plan = FrozenSystemPrompt()
        #expect(await text(plan, mode: .plan, recorded: r, now: day1) != a)
        #expect(plan.takeRecord() != nil)
        try Data("Use tabs.".utf8).write(to: ws.root.appending(path: "AGENTS.md"))
        let edited = FrozenSystemPrompt()
        #expect(await text(edited, recorded: r, now: day1).contains("Use tabs."))
        #expect(edited.takeRecord() != nil && edited.takeNote() == nil)
    }
}

@Suite struct LineEditorTests {
    @Test func historyKeepsWhatAShellWouldAndSurvivesRestarts() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "kk-hist-\(UUID().uuidString.prefix(8))/h.jsonl")
        var h = InputHistory(fileURL: file, limit: 3)
        #expect(h.entries.isEmpty)
        do { let kept = h.add("explain the build"); #expect(kept) }
        do { let kept = h.add("explain the build"); #expect(!kept) }            // a repeat of the last
        do { let kept = h.add("   "); #expect(!kept) }
        do { let kept = h.add(" secret-ish"); #expect(!kept) }                  // leading space: not kept
        do { let kept = h.add("first line\nsecond line"); #expect(kept) }
        do { let kept = h.add("/compact"); #expect(kept) }
        do { let kept = h.add("@README.md fix it"); #expect(kept) }
        #expect(h.entries == ["first line\nsecond line", "/compact", "@README.md fix it"])     // capped at 3
        try h.save()
        #expect(InputHistory(fileURL: file, limit: 3).entries == h.entries)
        // A corrupt line is skipped, not fatal.
        try Data("not json\n\"ok\"\n".utf8).write(to: file)
        #expect(InputHistory(fileURL: file).entries == ["ok"])
    }

    @Test func completesCommandsAndPathsOneFolderAtATime() {
        let complete = LineEditor.completions(commands: { ["compact", "context", "clear", "help"] },
                                              files: { ["README.md", "src/main.swift", "src/util/helpers.swift", "docs/guide.md"] })
        #expect(complete("/co", "/co", 0) == ["/compact", "/context"])
        #expect(complete("/co", "say /co", 4).isEmpty)                 // only at the start of the line
        #expect(complete("", "fix @", 5) == ["README.md", "docs/", "src/"])
        #expect(complete("src/", "fix @src/", 5) == ["src/main.swift", "src/util/"])
        #expect(complete("src", "look at src", 8).isEmpty)              // no @, no paths
    }

    @Test func marksPromptEscapesAsZeroWidth() {
        #expect(LineEditor.markEscapes("\u{1B}[1m›\u{1B}[0m ") == "\u{1}\u{1B}[1m\u{2}›\u{1}\u{1B}[0m\u{2} ")
        #expect(LineEditor.markEscapes("› ") == "› ")
    }

    @Test func parsesExtraEndpoints() throws {
        let o = try CLIOptions.parse(["--endpoint", "mock=http://127.0.0.1:18090/v1", "-m", "mock:m"])
        #expect(o.extraEndpoints == [.init(name: "mock", url: URL(string: "http://127.0.0.1:18090/v1")!)])
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["--endpoint", "nourl"]) }
    }
}

@Suite struct DebugCommandTests {
    final class Out: @unchecked Sendable {
        let lock = NSLock()
        var text = ""
        func add(_ s: String) { lock.withLock { text += s } }
    }

    /// A data folder with one stored session in `ws`: a question, a read, an answer.
    private func setup() async throws -> (AppSettings, Workspace, Session) {
        let ws = try makeProject()
        let support = FileManager.default.temporaryDirectory.appending(path: "kk-dbgcmd-\(UUID().uuidString.prefix(6))")
        let settings = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-dbgcmd-\(UUID().uuidString)")!, environment: [:])
        let store = settings.sessionStore
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m", workspace: ws.root.path)
        try await store.create(header)
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("c1", "read_file", #"{"path":"README.md"}"#), SSE.content("A demo.")]))
        var config = AgentConfig(tools: AllTools.all)
        config.wireLog = WireLog(directory: store.wireDirectory(for: header))
        let ask = ChatMessage.user("What is this?")
        try await store.append(.message(ask), to: header.id)
        final class Box: @unchecked Sendable { var r: [SessionRecord] = [] }
        let box = Box()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [ask], config: config, workspace: ws) { e in
            if case .assistant(let m) = e { box.r.append(.message(m)) }
            if case .toolFinished(let m) = e { box.r.append(.message(m)) }
        }
        for r in box.r { try await store.append(r, to: header.id) }
        return (settings, ws, try #require(try await store.load(header.id)))
    }

    @Test func inspectsAndExportsARecordedSession() async throws {
        let (settings, ws, s) = try await setup()
        let out = Out()
        // "last" in the project folder.
        #expect(await DebugCommands.run(["inspect"], settings: settings, cwd: ws.root) { out.add($0) } == 0)
        #expect(out.text.contains("2 turns · 1 tool calls"))
        #expect(out.text.contains("read_file") && out.text.contains("answer"))
        // One turn in full, by id prefix.
        let prefix = String(s.header.id.uuidString.prefix(6))
        let one = Out()
        #expect(await DebugCommands.run(["inspect", prefix, "--turn", "1"], settings: settings, cwd: URL(fileURLWithPath: "/")) { one.add($0) } == 0)
        #expect(one.text.hasPrefix("Turn 1 · test-model") && one.text.contains("HTTP: 200 · 2 messages sent"))
        #expect(one.text.contains("→ read_file {\"path\":\"README.md\"}") && one.text.contains("  approval: "))
        // JSON for scripts.
        let json = Out()
        #expect(await DebugCommands.run(["inspect", prefix, "--json"], settings: settings, cwd: ws.root) { json.add($0) } == 0)
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: Data(json.text.utf8)),
              case .array(let turns)? = o["turns"] else { Issue.record("not JSON"); return }
        #expect(turns.count == 2)
        // Export to a file.
        let file = FileManager.default.temporaryDirectory.appending(path: "kk-export-\(UUID().uuidString.prefix(6)).md").path
        let ex = Out()
        #expect(await DebugCommands.run(["export", prefix, "-o", file], settings: settings, cwd: ws.root) { ex.add($0) } == 0)
        #expect(try String(contentsOfFile: file, encoding: .utf8).contains("## You\n\nWhat is this?"))
        // A bad turn and an unknown session fail cleanly.
        #expect(await DebugCommands.run(["inspect", prefix, "--turn", "9"], settings: settings, cwd: ws.root) { _ in } == 1)
        #expect(await DebugCommands.run(["inspect", "ffffffff"], settings: settings, cwd: ws.root) { _ in } == 1)
    }
}
