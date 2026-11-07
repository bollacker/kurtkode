import Foundation
import Testing
@testable import AgentCore

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.withLock { items.append(e) } }
    var all: [AgentEvent] { lock.withLock { items } }
    var results: [ChatMessage] { all.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } }
}

private func tools(_ body: Data) -> [String: String] {
    guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: body), case .array(let ts)? = o["tools"] else { return [:] }
    var out: [String: String] = [:]
    for case .object(let t) in ts {
        guard case .object(let f)? = t["function"], case .string(let n)? = f["name"] else { continue }
        if case .string(let d)? = f["description"] { out[n] = d } else { out[n] = "" }
    }
    return out
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func tempHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-home-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return Workspace.canonical(url)
}

/// A project with one skill, and a home folder with two more (one shadowed by the project's).
private func skillSetup() throws -> (Workspace, URL) {
    let ws = try makeProject()
    let home = tempHome()
    try write("---\nname: release\ndescription: \"Cut a release: bump the version, tag, write notes.\"\n---\n# Release\nRun scripts/bump.sh first.\n",
              to: ws.root.appending(path: ".claude/skills/release/SKILL.md"))
    try write("echo bump\n", to: ws.root.appending(path: ".claude/skills/release/scripts/bump.sh"))
    try write("---\nname: release\ndescription: the user's release skill\n---\nIgnored.\n",
              to: home.appending(path: ".agents/skills/release/SKILL.md"))
    try write("---\nname: pdf\ndescription: >\n  Fill and read PDF forms,\n  with the bundled script.\n---\nUse forms.py.\n",
              to: home.appending(path: ".kurtkode/skills/pdf/SKILL.md"))
    try write("print('form')\n", to: home.appending(path: ".kurtkode/skills/pdf/forms.py"))
    try write("---\ndescription: Deploy to production\ndisable-model-invocation: true\n---\nDeploy.\n",
              to: home.appending(path: ".claude/skills/deploy/SKILL.md"))
    try write("no front matter\n", to: home.appending(path: ".claude/skills/broken/SKILL.md"))
    try write("---\ndescription: not a skill folder\n---\n", to: home.appending(path: ".claude/skills/stray.md"))
    return (ws, home)
}

@Suite struct SkillTests {
    @Test func loadsSkillsProjectFirst() throws {
        let (ws, home) = try skillSetup()
        let skills = Skills.load(root: ws.root, home: home)
        #expect(skills.map(\.name) == ["deploy", "pdf", "release"])
        let release = try #require(skills.first { $0.name == "release" })
        #expect(release.description == "Cut a release: bump the version, tag, write notes.")
        #expect(release.folder.path.hasPrefix(ws.root.path))                   // the project's, not the user's
        #expect(skills.first { $0.name == "pdf" }?.description == "Fill and read PDF forms, with the bundled script.")
        #expect(skills.first { $0.name == "deploy" }?.modelInvocable == false)    // named after its folder
        #expect(skills.filter(\.modelInvocable).map(\.name) == ["pdf", "release"])
    }

    @Test func skillsAreCommandsAfterCustomOnes() throws {
        let (ws, home) = try skillSetup()
        try write("Do the pdf thing: $ARGUMENTS\n", to: ws.root.appending(path: ".kurtkode/commands/pdf.md"))
        let commands = SlashCommands.all(workspace: ws.root, home: home)
        #expect(commands.contains { $0.name == "skills" && $0.isBuiltIn })
        guard case .custom(let pdf, _)? = commands.first(where: { $0.name == "pdf" })?.kind else { Issue.record("no pdf"); return }
        #expect(pdf.hasPrefix("Do the pdf thing"))                               // the command wins over the skill
        let release = try #require(commands.first { $0.name == "release" })
        guard case .custom(let template, let source) = release.kind else { Issue.record("not custom"); return }
        #expect(source.lastPathComponent == "SKILL.md")
        #expect(SlashCommands.expand(template, arguments: "v2.1") == "Load the skill \"release\" with the skill tool and follow it.\n\nv2.1")
        #expect(Skills.listing(root: ws.root, home: home).contains("/deploy  Deploy to production\n    ~/.claude/skills/deploy  (only when asked for)"))
    }

    @Test func theModelLoadsASkillAndReadsItsFilesButCantWriteThem() async throws {
        let (ws, home) = try skillSetup()
        let pdf = home.appending(path: ".kurtkode/skills/pdf")
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "skill", #"{"name":"PDF"}"#),
            SSE.toolCall("c2", "read_file", "{\"path\":\"\(pdf.appending(path: "forms.py").path)\"}"),
            SSE.toolCall("c3", "write_file", "{\"path\":\"\(pdf.appending(path: "x.py").path)\",\"content\":\"x\"}"),
            SSE.toolCall("c4", "skill", #"{"name":"nope"}"#),
            SSE.content("Done."),
        ]))
        var config = AgentConfig(tools: AllTools.all)
        config.skills = Skills.load(root: ws.root, home: home)
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Fill the form")],
                            config: config, workspace: ws) { events.add($0) }

        let offered = tools(try #require(MockServer.requestBodies(host).first))
        let description = try #require(offered["skill"])
        #expect(description.contains("- pdf: Fill and read PDF forms, with the bundled script.\n- release: Cut a release"))
        #expect(!description.contains("deploy"))
        #expect(offered["ask_user"] == nil)                                      // nobody to ask

        let r = events.results
        #expect(r.count == 4)
        #expect(r[0].content.hasPrefix("Skill pdf (\(pdf.path)):\n\nUse forms.py."))
        #expect(r[0].content.contains("- \(pdf.appending(path: "forms.py").path)"))
        #expect(r[1].content.contains("print('form')"))
        #expect(r[2].toolResult?.isError == true && r[2].content.contains("read-only"))
        #expect(!FileManager.default.fileExists(atPath: pdf.appending(path: "x.py").path))
        #expect(r[3].toolResult?.isError == true && r[3].content.contains("Available: pdf, release"))
    }

    @Test func aDisabledSkillStillLoadsByName() async throws {
        let (ws, home) = try skillSetup()
        let out = try await SkillTool(skills: Skills.load(root: ws.root, home: home))
            .run(ToolArguments(["name": "deploy"]), context: ToolContext(workspace: ws))
        #expect(out.text.hasSuffix(":\n\nDeploy."))
    }
}

@Suite struct AskUserTests {
    @Test func theModelAsksAndGetsTheAnswer() async throws {
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "ask_user", #"{"question":"Which database?","options":["SQLite","Postgres"]}"#),
            SSE.content("Using Postgres."),
        ]))
        let asked = Box<UserQuestion?>(nil)
        var config = AgentConfig(tools: AllTools.all)
        config.askUser = { questions in asked.value = questions[0]; return [questions[0].answer(fromTyped: "2")] }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("Set up storage")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(tools(try #require(MockServer.requestBodies(host).first))["ask_user"] != nil)
        #expect(asked.value == UserQuestion(question: "Which database?", options: ["SQLite", "Postgres"], callID: "c1"))
        #expect(events.results.first?.content == "The user answered: Postgres")
    }

    @Test func questionsAskedTogetherComeTogetherAndTheAnswersGoBack() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("c1", "ask_user", #"{"questions":[{"question":"First?"},{"question":"Second?"}]}"#),
            SSE.content("Done."),
        ]))
        let asked = Box<[[UserQuestion]]>([])
        var config = AgentConfig(tools: AllTools.all)
        config.askUser = { questions in asked.value.append(questions); return ["Yes", "No"] }
        let events = Events()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("go")],
                            config: config, workspace: ws) { events.add($0) }
        #expect(asked.value == [[UserQuestion(question: "First?", callID: "c1"), UserQuestion(question: "Second?", callID: "c1")]])
        #expect(events.results.first?.content == "The user answered:\n- First? → Yes\n- Second? → No")
    }

    @Test func withoutSomeoneToAskTheModelDecides() async throws {
        let tool = AskUserTool()
        let ws = try makeProject()
        let alone = try await tool.run(ToolArguments(["question": "Which?"]), context: ToolContext(workspace: ws))
        #expect(alone.text.hasPrefix("Nobody is available to answer"))
        var context = ToolContext(workspace: ws)
        context.askUser = { _ in [nil] }
        let skipped = try await tool.run(ToolArguments(["question": "Which?", "options": .string(#"["a","b"]"#)]), context: context)
        #expect(skipped.text.hasPrefix("The user chose not to answer"))
    }

    @Test func typedAnswersPickOptions() {
        let one = UserQuestion(question: "?", options: ["Red", "Green", "Blue"])
        #expect(one.answer(fromTyped: " 2 ") == "Green")
        #expect(one.answer(fromTyped: "1,3") == "1,3")                           // only one may be picked
        #expect(one.answer(fromTyped: "4") == "4")
        #expect(one.answer(fromTyped: "purple") == "purple")
        #expect(one.answer(fromTyped: "  ") == nil)
        let several = UserQuestion(question: "?", options: ["Red", "Green", "Blue"], multiple: true)
        #expect(several.answer(fromTyped: "1, 3") == "Red; Blue")
        #expect(UserQuestion(question: "?").answer(fromTyped: "2") == "2")
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
