import Foundation
import Testing
@testable import AgentCore

private func tempFolder(_ files: [String: String] = [:]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "kk-prompts-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(to: dir.appending(path: name + ".md"), atomically: true, encoding: .utf8) }
    return dir
}

struct PromptTemplateTests {
    @Test func variablesAndSections() throws {
        let t = try PromptTemplate("Hi {{who}}.{{#loud}} LOUD{{/loud}}{{^loud}} quiet{{/loud}} {{nope}}\n")
        #expect(t.render(["who": "you", "loud": "1"]) == "Hi you. LOUD {{nope}}")
        #expect(t.render(["who": "you", "loud": ""]) == "Hi you. quiet {{nope}}")
    }

    @Test func standaloneTagsAndCommentsTakeTheirLines() throws {
        let t = try PromptTemplate("""
            {{! a comment
                over two lines }}
            first
            {{#a}}
            - a
            {{/a}}
              {{^a}}
            - not a
              {{/a}}
            last {{#a}}inline{{/a}}

            """)
        #expect(t.render(["a": "1"]) == "first\n- a\nlast inline")
        #expect(t.render([:]) == "first\n- not a\nlast ")
    }

    @Test func badTemplatesAreRefused() {
        #expect(throws: PromptTemplate.ParseError.self) { try PromptTemplate("{{#a}} open") }
        #expect(throws: PromptTemplate.ParseError.self) { try PromptTemplate("{{#a}}{{/b}}") }
        #expect(throws: PromptTemplate.ParseError.self) { try PromptTemplate("{{/a}}") }
        #expect(throws: PromptTemplate.ParseError.self) { try PromptTemplate("{{a") }
        #expect(throws: PromptTemplate.ParseError.self) { try PromptTemplate("{{two words}}") }
    }

    @Test func theDefaultsShipAndParse() throws {
        let t = PromptTemplates(overrides: [])
        #expect(t.defaults != nil)
        for name in ["intro", "mode", "style-detailed", "style-lean"] {
            let text = try #require(t.defaultText(name))
            _ = try PromptTemplate(text)
        }
        #expect(t.styles == ["detailed", "lean"])
    }

    @Test func projectOverridesUserOverridesDefaults() async throws {
        let project = try tempFolder(["intro": "Project intro."])
        let user = try tempFolder(["intro": "User intro.", "style-terse": "{{intro}}\n{{mode_rules}}\n"])
        var b = SystemPromptBuilder(workspace: try makeProject(), tools: AllTools.all, mode: .ask)
        b.templates = PromptTemplates(overrides: [user])
        #expect(await b.build().hasPrefix("User intro.\n\nHow to work:"))
        b.templates = PromptTemplates(overrides: [project, user])
        #expect(await b.build().hasPrefix("Project intro.\n\nHow to work:"))
        // A style of the user's own, offered beside the shipped ones.
        b.style = try #require(PromptStyle(rawValue: "terse"))
        #expect(b.templates.styles == ["detailed", "lean", "terse"])
        let terse = await b.build()
        #expect(terse.hasPrefix("Project intro.\n- Make changes with edit_file") && !terse.contains("How to work:"))
    }

    @Test func anUnknownStyleOrABrokenOverrideFallsBack() async throws {
        let user = try tempFolder(["intro": "{{#chat}} never closed"])
        var b = SystemPromptBuilder(workspace: try makeProject(), tools: AllTools.all, mode: .ask)
        b.templates = PromptTemplates(overrides: [user])
        b.style = try #require(PromptStyle(rawValue: "missing"))
        #expect(b.resolvedStyle == .detailed)
        let text = await b.build()
        #expect(text.hasPrefix("You are kurtkode, a coding agent") && text.contains("How to work:"))
        #expect(PromptStyle(rawValue: "Bad Name") == nil && PromptStyle(rawValue: "-x") == nil)
    }

    @Test func onlyEditedTemplatesChangeTheFingerprint() throws {
        let defaults = PromptTemplates(overrides: [])
        let names = ["intro", "mode", "style-detailed"]
        #expect(defaults.fingerprint(names).isEmpty)
        // A copy of the default text isn't an edit.
        let copy = try tempFolder(["intro": try #require(defaults.defaultText("intro"))])
        #expect(PromptTemplates(overrides: [copy]).fingerprint(names).isEmpty)
        let edited = try tempFolder(["intro": "Something else."])
        #expect(!PromptTemplates(overrides: [edited]).fingerprint(names).isEmpty)
        #expect(PromptTemplates(overrides: [edited]).fingerprint(["mode"]).isEmpty)
    }

    @Test func anEditedTemplateIsUsedOnTheNextPrompt() async throws {
        let ws = try makeProject()
        let overrides = PromptTemplates.projectFolder(ws.root)
        let frozen = FrozenSystemPrompt()
        let a = await frozen.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        #expect(a.hasPrefix("You are kurtkode, a coding agent"))
        try FileManager.default.createDirectory(at: overrides, withIntermediateDirectories: true)
        try "Edited intro.\n".write(to: overrides.appending(path: "intro.md"), atomically: true, encoding: .utf8)
        let b = await frozen.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        #expect(b.hasPrefix("Edited intro.\n\nHow to work:"))
        // A session recorded with the defaults keeps its prompt's identity: the key has no template part.
        let record = try #require(frozen.takeRecord())
        #expect(record.key.contains("|t:"))
        try FileManager.default.removeItem(at: overrides)
        let fresh = FrozenSystemPrompt()
        _ = await fresh.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        #expect(try #require(fresh.takeRecord()).key == "ask|||")
    }
}

extension PromptTemplateTests {
    @Test func delegationRulesAppearOnlyWithSubagents() async throws {
        let ws = try makeProject()
        var b = SystemPromptBuilder(workspace: ws, tools: AllTools.all, mode: .ask)
        b.templates = PromptTemplates(overrides: [])
        let without = await b.build()
        b.subagents = true
        let detailed = await b.build()
        b.style = .lean
        let lean = await b.build()
        #expect(!without.contains("task tool") && detailed.contains("Subagents (the task tool) work in a fresh context"))
        #expect(lean.contains("Use the task tool for broad reading") && !lean.contains("Subagents (the task tool)"))
        // Turning subagents on is a different prompt: its key says so, and the prompt is rebuilt.
        let frozen = FrozenSystemPrompt()
        let a = await frozen.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        let c = await frozen.text(workspace: ws, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "", subagents: true)
        #expect(a != c && c.contains("rate it with rate_task") && frozen.takeRecord()?.key == "ask||||sub")
    }

    @Test func toolDescriptionsComeFromTemplates() throws {
        let task = TaskTool(agents: AgentDefinition.builtIns) { _, _, _, _, _, _, _ in ToolOutput(text: "") }
        #expect(task.description.hasPrefix("Hand a self-contained task to a subagent, which works with a fresh context and "
                                           + "returns only its final report.")
                && task.description.hasSuffix("Agents: explore (" + AgentDefinition.explore.description + "); general ("
                                              + AgentDefinition.general.description + ")"))
        let user = FileManager.default.temporaryDirectory.appending(path: "kk-tooltpl-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "Delegate. Agents: {{agents}}\n".write(to: user.appending(path: "tool-task.md"), atomically: true, encoding: .utf8)
        var mine = task
        mine.templates = PromptTemplates(overrides: [user])
        #expect(mine.description.hasPrefix("Delegate. Agents: explore ("))
        #expect(RateTaskTool { _, _, _, _, _ in .success("") }.description.hasPrefix("Rate a subagent's work after you've used its report"))
    }
}
