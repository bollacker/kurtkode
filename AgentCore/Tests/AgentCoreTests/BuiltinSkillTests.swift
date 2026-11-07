import Foundation
import Testing
@testable import AgentCore

private func tempHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-home-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return Workspace.canonical(url)
}

private func makeRun(_ ws: Workspace, settings: RunSettings, tools: [any Tool] = AllTools.all) -> SessionRun {
    let session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path), messages: [], model: "m")
    return SessionRun(session: session, store: SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-s")),
                      settings: settings, profile: ModelProfile(endpointID: UUID(), model: "m"), endpointID: UUID(),
                      mode: .ask, rules: [], tools: tools, workspace: ws, shell: ShellState(cwd: ws.root),
                      contextLimit: nil, sandbox: nil, turn: TurnKey(UUID()),
                      checkpoints: CheckpointStore(directory: FileManager.default.temporaryDirectory.appending(path: "kk-c")),
                      approve: { _ in .allow }, hooks: nil, subagentModel: nil)
}

/// kurtkode's built-in skills (the library in skilllib/, shipped as the `BuiltinSkills` resource) and the system
/// prompt's line about skills.
@Suite struct BuiltinSkillTests {
    @Test func theLibraryShipsAndEverySkillLoads() throws {
        let folder = try #require(Skills.builtinFolder)
        let skills = Skills.load(root: nil, home: tempHome(), builtin: folder)
        #expect(skills.count == 30)
        for name in ["systematic-debugging", "code-review", "fix-flaky-tests", "verify-before-done", "write-skills"] {
            #expect(skills.contains { $0.name == name }, "missing \(name)")
        }
        // Portable front matter: only name and description, the name matching the folder, a short trigger description.
        for s in skills {
            let text = try String(contentsOf: s.file, encoding: .utf8)
            let (meta, body) = SlashCommands.frontMatter(text)
            #expect(Set(meta.keys) == ["name", "description"], "\(s.name): \(meta.keys.sorted())")
            #expect(s.folder.lastPathComponent == s.name && s.modelInvocable)
            #expect(s.description.hasPrefix("Use when") && s.description.count <= 230, "\(s.name)")
            #expect(body.split(separator: "\n", omittingEmptySubsequences: false).count <= 150, "\(s.name)")
        }
        // The whole list stays inside Codex's 8,000-character budget, so the library is portable as it is.
        var listed = 0
        for s in skills { listed += s.name.count + s.description.count + 4 }
        #expect(listed < 8000)
    }

    @Test func projectAndUserSkillsReplaceBuiltInOnesByName() throws {
        let ws = try makeProject()
        let home = tempHome()
        try FileManager.default.createDirectory(at: ws.root.appending(path: ".claude/skills/code-review"), withIntermediateDirectories: true)
        try "---\nname: code-review\ndescription: Our own review rules.\n---\nReview our way.\n"
            .write(to: ws.root.appending(path: ".claude/skills/code-review/SKILL.md"), atomically: true, encoding: .utf8)
        let skills = Skills.load(root: ws.root, home: home, builtin: Skills.builtinFolder)
        let review = try #require(skills.first { $0.name == "code-review" })
        #expect(review.description == "Our own review rules." && review.folder.path.hasPrefix(ws.root.path))
        #expect(skills.count == 30)
        // /skills says which ones are built in.
        let listing = Skills.listing(root: ws.root, home: home, builtin: Skills.builtinFolder)
        #expect(listing.contains("/systematic-debugging") && listing.contains("(built-in)"))
        #expect(!listing.components(separatedBy: "\n").contains { $0.hasPrefix("/code-review") && $0.contains("(built-in)") })
    }

    @Test func runsOfferBuiltInSkillsUnlessTurnedOff() throws {
        let ws = try makeProject()
        var on = RunSettings()
        #expect(on.builtinSkills)                                         // on by default
        #expect(makeRun(ws, settings: on).config.skills.count >= 30)
        on.builtinSkills = false
        #expect(makeRun(ws, settings: on).config.skills.isEmpty)
        #expect(makeRun(ws, settings: RunSettings(), tools: []).config.skills.isEmpty)   // a plain chat: no tools, no skills
        let d = UserDefaults(suiteName: "kk-skills-\(UUID().uuidString)")!
        d.set(false, forKey: RunSettings.Key.builtinSkills)
        #expect(!RunSettings(defaults: d).builtinSkills)
    }

    @Test func builtInSkillsAreSlashCommands() throws {
        let names = SlashCommands.all(workspace: nil, home: tempHome(), builtinSkills: Skills.builtinFolder).map(\.name)
        #expect(names.contains("systematic-debugging") && names.contains("compact"))
        #expect(!SlashCommands.all(workspace: nil, home: tempHome()).map(\.name).contains("systematic-debugging"))
    }

    @Test func thePromptTellsTheModelToCheckSkillsOnlyWhenOffered() async throws {
        let ws = try makeProject()
        var b = SystemPromptBuilder(workspace: ws, tools: AllTools.all, mode: .ask)
        b.templates = PromptTemplates(overrides: [])
        let without = await b.build()
        b.skills = true
        let detailed = await b.build()
        b.style = .lean
        let lean = await b.build()
        let line = "Before you start a task, compare it with that list; if one matches, load that skill first and follow it."
        #expect(!without.contains("Skills:") && detailed.contains(line) && lean.contains(line))
        #expect(b.templateNames.contains("skills"))
        // The line sits with the working rules, on its own line, with no blank line left behind.
        #expect(detailed.contains("as soon as it's done.\n- Skills: the skill tool lists"))
        // Skills on is a different prompt: its key says so.
        let frozen = FrozenSystemPrompt()
        _ = await frozen.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "", skills: true)
        #expect(frozen.takeRecord()?.key == "ask||||skills")
    }
}
