import Foundation
import Testing
@testable import AgentCore

@Suite struct SlashCommandTests {
    @Test func parsesCommandsButNotPaths() {
        let compact = SlashCommands.parse("/compact the parser work")
        #expect(compact?.name == "compact")
        #expect(compact?.arguments == "the parser work")
        #expect(SlashCommands.parse("  /HELP  ")?.name == "help")
        #expect(SlashCommands.parse("/frontend:component Button")?.name == "frontend:component")
        #expect(SlashCommands.parse("/usr/bin is on the PATH") == nil)
        #expect(SlashCommands.parse("/") == nil)
        #expect(SlashCommands.parse("what does /compact do?") == nil)
    }

    @Test func expandsArguments() {
        #expect(SlashCommands.expand("Review $ARGUMENTS carefully.", arguments: "calc.py") == "Review calc.py carefully.")
        #expect(SlashCommands.expand("Rename $1 to $2.", arguments: "old new") == "Rename old to new.")
        #expect(SlashCommands.expand("Explain the build.", arguments: "focus on tests") == "Explain the build.\n\nfocus on tests")
        #expect(SlashCommands.expand("Explain the build.", arguments: "") == "Explain the build.")
        #expect(SlashCommands.expand("Fix $1 and $2.", arguments: "a") == "Fix a and .")
    }

    @Test func loadsCustomCommandsWithPrecedence() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "kk-cmds-\(UUID().uuidString.prefix(8))")
        let project = root.appending(path: "project"), home = root.appending(path: "home")
        defer { try? fm.removeItem(at: root) }
        func write(_ url: URL, _ text: String) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write(project.appending(path: ".kurtkode/commands/audit.md"),
                  "---\ndescription: \"Review a file\"\nargument-hint: <file>\n---\nReview $ARGUMENTS for bugs.\n")
        try write(project.appending(path: ".claude/commands/frontend/component.md"), "Make a component named $1.\n")
        try write(home.appending(path: ".kurtkode/commands/audit.md"), "The personal review, shadowed by the project's.\n")
        try write(home.appending(path: ".claude/commands/standup.md"), "Summarize what changed today.\n")
        try write(home.appending(path: ".kurtkode/commands/help.md"), "Can't replace a built-in.\n")
        try write(home.appending(path: ".kurtkode/commands/notes.txt"), "Not a command.\n")

        let all = SlashCommands.all(workspace: project, home: home)
        let custom = all.filter { !$0.isBuiltIn }
        #expect(custom.map(\.name).sorted() == ["audit", "frontend:component", "standup"])
        let review = try #require(all.first { $0.name == "audit" })
        #expect(review.description == "Review a file")
        #expect(review.argumentHint == "<file>")
        guard case .custom(let template, _) = review.kind else { Issue.record("not custom"); return }
        #expect(template == "Review $ARGUMENTS for bugs.")
        #expect(all.first { $0.name == "help" }?.isBuiltIn == true)
        #expect(all.first { $0.name == "standup" }?.description == "Summarize what changed today.")
    }

    @Test func matchesByPrefixThenSubstring() {
        let names = SlashCommands.matching("co", in: SlashCommands.builtIns).map(\.name)
        #expect(names.prefix(2) == ["compact", "context"])
        #expect(SlashCommands.matching("text", in: SlashCommands.builtIns).map(\.name) == ["context"])
        #expect(SlashCommands.matching("", in: SlashCommands.builtIns).count == SlashCommands.builtIns.count)
    }
}
