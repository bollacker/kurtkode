import Foundation
import Testing
@testable import AgentCore

private let folder: URL = {
    let f = FileManager.default.temporaryDirectory.appending(path: "kk-router-skills-\(UUID().uuidString.prefix(8))")
    for name in ["code-review", "respond-to-review", "fix-flaky-tests", "systematic-debugging", "deploy", "review"] {
        let d = f.appending(path: name)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? "---\nname: \(name)\ndescription: Use when …\n---\n# \(name)\nStep one for \(name).\n"
            .write(to: d.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    }
    return f
}()

private func skill(_ name: String, _ description: String = "Use when …", invocable: Bool = true) -> Skill {
    Skill(name: name, description: description, folder: folder.appending(path: name), modelInvocable: invocable)
}

private let library = [skill("code-review"), skill("respond-to-review"), skill("fix-flaky-tests"),
                       skill("systematic-debugging"), skill("deploy", invocable: false)]

private func reply(_ text: String, calls: [ToolCall] = []) -> ChatMessage {
    var m = ChatMessage(role: .assistant, content: text)
    m.toolCalls = calls
    return m
}

private func json(_ body: Data?) -> [String: JSONValue] {
    guard let body, case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: body) else { return [:] }
    return o
}

private final class Costs: @unchecked Sendable {
    let lock = NSLock()
    var items: [CostEntry] = []
    func add(_ e: CostEntry) { lock.withLock { items.append(e) } }
}

@Suite struct SkillRouterTests {
    @Test func thePickIsTheToolCallOrTheLastNameMentioned() {
        #expect(SkillRouter.pick(reply("fix-flaky-tests"), among: library)?.name == "fix-flaky-tests")
        #expect(SkillRouter.pick(reply("Not code-review: this is respond-to-review."), among: library)?.name == "respond-to-review")
        // A name inside a longer one is not that name.
        #expect(SkillRouter.pick(reply("respond-to-review"), among: [skill("review"), skill("respond-to-review")])?.name
                == "respond-to-review")
        #expect(SkillRouter.pick(reply("none"), among: library) == nil)
        #expect(SkillRouter.pick(reply("deploy"), among: library) == nil)                       // not offered to the model
        let call = ToolCall(id: "1", name: "skill", arguments: #"{"name":"Systematic-Debugging"}"#)
        #expect(SkillRouter.pick(reply("", calls: [call]), among: library)?.name == "systematic-debugging")
    }

    @Test func onlyANewRequestFromTheUserIsRouted() {
        let ask = ChatMessage.user("test_eur fails one CI run in five")
        #expect(SkillRouter.request(in: [ask]) == "test_eur fails one CI run in five")
        #expect(SkillRouter.request(in: [ask, reply("Done.")]) == nil)                        // nothing new
        #expect(SkillRouter.request(in: [ask, FrozenSystemPrompt.noteMessage("[a note]")]) == nil)
        #expect(SkillRouter.request(in: [.user("Load the skill \"code-review\" with the skill tool and follow it.")]) == nil)
        #expect(SkillRouter.request(in: [.user(String(repeating: "x", count: 9000))])?.count == SkillRouter.maxRequestCharacters)
    }

    @Test func routingIsOnForOpenAICompatibleServersByDefault() {
        #expect(SkillRouting.auto.applies(to: .openai) && !SkillRouting.auto.applies(to: .anthropic)
                && !SkillRouting.auto.applies(to: .gemini))
        #expect(SkillRouting.on.applies(to: .anthropic) && !SkillRouting.off.applies(to: .openai))
        #expect(RunSettings().skillRouting == .auto)
    }

    @Test func theRouterAsksOnceAndTheAgentIsToldToLoadTheSkill() async throws {
        let (client, host) = MockServer.client(.init(turns: [SSE.content("fix-flaky-tests")]))
        let costs = Costs()
        let note = await SkillRouter.route(history: [.user("test_eur fails one CI run in five, never alone")], skills: library,
                                           client: client, model: "m", templates: PromptTemplates(overrides: []),
                                           limits: TurnLimits(),
                                           costs: CostSink(scope: CostScope(run: UUID(), agent: "main"), endpointID: nil, emit: costs.add))
        let m = try #require(note)
        #expect(m.role == .user && m.contextNote == true && m.content.contains("loaded the \"fix-flaky-tests\" skill"))
        #expect(m.content.contains("Step one for fix-flaky-tests."))                         // the instructions themselves
        // One short question: no tools, no thinking, the request and the offered skills in it.
        let body = json(MockServer.requestBody(host))
        #expect(body["tools"] == nil || body["tools"] == .array([]))
        #expect(body["reasoning_effort"] == .string("none"))
        let sent = String(decoding: MockServer.requestBody(host) ?? Data(), as: UTF8.self)
        #expect(sent.contains("never alone") && sent.contains("- fix-flaky-tests:") && !sent.contains("- deploy:"))
        #expect(costs.items.map(\.purpose) == [.routing])
    }

    @Test func noNoteForNoneOrASkillAlreadyLoaded() async throws {
        let (none, _) = MockServer.client(.init(turns: [SSE.content("none")]))
        #expect(await SkillRouter.route(history: [.user("What does git rebase --onto do?")], skills: library, client: none,
                                        model: "m", templates: PromptTemplates(overrides: []), limits: TurnLimits()) == nil)
        var loaded = reply("")
        loaded.toolCalls = [ToolCall(id: "1", name: "skill", arguments: #"{"name":"code-review"}"#)]
        let (again, _) = MockServer.client(.init(turns: [SSE.content("code-review")]))
        var toolResult = ChatMessage(role: .tool, content: "Skill code-review …")
        toolResult.toolCallID = "1"
        let history: [ChatMessage] = [.user("Review my diff"), loaded, toolResult,
                                      reply("Found two bugs."), .user("Review the next commit too")]
        #expect(await SkillRouter.route(history: history, skills: library, client: again, model: "m",
                                        templates: PromptTemplates(overrides: []), limits: TurnLimits()) == nil)
        // Nor when the router loaded it earlier in the session.
        let (third, _) = MockServer.client(.init(turns: [SSE.content("code-review")]))
        let routed = FrozenSystemPrompt.noteMessage(try #require(SkillRouter.note(skill("code-review"))))
        #expect(await SkillRouter.route(history: [.user("Review my diff"), routed, reply("Done."), .user("And this one")],
                                        skills: library, client: third, model: "m", templates: PromptTemplates(overrides: []),
                                        limits: TurnLimits()) == nil)
    }

    @Test func theRunRoutesOnlyWhenTheSettingAppliesToTheServer() async throws {
        let ws = try makeProject()
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path),
                              messages: [.user("This test fails sometimes in CI")], model: "m")
        func run(_ api: WireAPI) -> SessionRun {
            SessionRun(session: session, store: SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-s")),
                       settings: RunSettings(), profile: ModelProfile(endpointID: UUID(), model: "m"), endpointID: UUID(), api: api,
                       mode: .ask, rules: [], tools: AllTools.all, workspace: ws, shell: ShellState(cwd: ws.root),
                       contextLimit: nil, sandbox: nil, turn: TurnKey(UUID()),
                       checkpoints: CheckpointStore(directory: FileManager.default.temporaryDirectory.appending(path: "kk-c")),
                       approve: { _ in .allow }, hooks: nil, subagentModel: nil)
        }
        let (local, localHost) = MockServer.client(.init(turns: [SSE.content("fix-flaky-tests")]))
        let note = await run(.openai).routeSkill(client: local, model: "m", routing: .auto, project: ws.root) { _ in }
        #expect(note?.content.contains("fix-flaky-tests") == true && MockServer.requestBodies(localHost).count == 1)
        let (claude, claudeHost) = MockServer.client(.init(turns: [SSE.content("fix-flaky-tests")]), api: .anthropic)
        #expect(await run(.anthropic).routeSkill(client: claude, model: "m", routing: .auto, project: ws.root) { _ in } == nil)
        #expect(MockServer.requestBodies(claudeHost).isEmpty)                                 // not even asked
        let (off, offHost) = MockServer.client(.init(turns: [SSE.content("fix-flaky-tests")]))
        #expect(await run(.openai).routeSkill(client: off, model: "m", routing: .off, project: ws.root) { _ in } == nil)
        #expect(MockServer.requestBodies(offHost).isEmpty)
    }
}
