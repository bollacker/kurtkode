import Foundation
import Testing
@testable import AgentCore

@Suite struct MentionTests {
    @Test func findsFilesAndFoldersButNotEmails() throws {
        let ws = try makeProject()
        try Data("x".utf8).write(to: ws.root.appending(path: "my notes.txt"))
        let found = Mentions.find(in: "Compare @src/main.swift with @src/util/, see @README.md. Mail a@b.com, "
                                  + "@\"my notes.txt\", @missing.txt, and @src/main.swift again.", workspace: ws)
        #expect(found.map(\.path) == ["src/main.swift", "src/util", "README.md", "my notes.txt"])
        #expect(found.map(\.isDirectory) == [false, true, false, false])
        #expect(Mentions.find(in: "@../../etc/passwd", workspace: ws).isEmpty)       // outside the project
    }

    @Test func attachesThemAsToolCallsAndResults() async throws {
        let ws = try makeProject()
        let msgs = await Mentions.messages(for: Mentions.find(in: "Explain @src/main.swift and @src/util", workspace: ws),
                                           workspace: ws)
        #expect(msgs.map(\.role) == [.assistant, .tool, .tool])
        #expect(msgs[0].toolCalls.map(\.name) == ["read_file", "list_dir"])
        #expect(msgs[0].toolCalls[0].arguments == #"{"path":"src/main.swift"}"#)
        #expect(msgs[1].toolCallID == msgs[0].toolCalls[0].id)
        #expect(msgs[1].content.contains("12\tfunc greet()"))
        #expect(msgs[2].content.contains("helpers.swift"))
        // A history with them is valid to send: every call has its result.
        #expect(AgentLoop.sendable([.user("Explain")] + msgs).count == 4)
    }

    @Test func completesPaths() {
        let files = ["src/main.swift", "src/util/helpers.swift", "README.md", "docs/guide.md", "Sources/Main.swift"]
        let main = Mentions.completions("main", files: files)
        #expect(main.prefix(2).sorted() == ["Sources/Main.swift", "src/main.swift"])
        #expect(Mentions.completions("util", files: files).first == "src/util/")
        #expect(Mentions.completions("guide", files: files) == ["docs/guide.md"])
        #expect(Mentions.completions("zzz", files: files).isEmpty)
    }

    @Test func userCommandsRunInTheSessionDirectory() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        #expect(UserShell.command(in: "!ls -1 src") == "ls -1 src")
        #expect(UserShell.command(in: "!") == nil)
        #expect(UserShell.command(in: "hi!") == nil)
        let m = await UserShell.run("cd src && ls -1", workspace: ws, shell: shell)
        #expect(m.role == .user)
        #expect(m.content.hasPrefix("I ran `cd src && ls -1` in the project myself."))
        #expect(m.content.contains("main.swift"))
        #expect(m.content.contains("Exit code 0."))
        #expect(shell.cwd.lastPathComponent == "src")                  // cd carries over, as for the agent
        let fenced = UserShell.message(command: "cat x.md", output: "```swift\nlet a = 1\n```")
        #expect(fenced.contains("````\n```swift"))
    }
}
