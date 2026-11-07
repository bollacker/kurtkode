import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

/// A second folder outside the project, with a file and a subfolder.
private func makeOther(git: Bool = false) throws -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "kurtkode-other-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
    try fm.createDirectory(at: root.appending(path: "notes"), withIntermediateDirectories: true)
    try Data("Budget: 42 walruses\n".utf8).write(to: root.appending(path: "notes/budget.md"))
    try Data("top\n".utf8).write(to: root.appending(path: "top.txt"))
    if git {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "init", "-q"]
        try p.run()
        p.waitUntilExit()
    }
    return root
}

private func call(_ tool: any Tool, _ args: [String: JSONValue], _ ws: Workspace) async -> ToolOutput {
    do { return try await tool.run(ToolArguments(args), context: ToolContext(workspace: ws)) }
    catch let f as ToolFailure { return .error(f.message) }
    catch { return .error(error.localizedDescription) }
}

@Suite struct ExtraFolderTests {
    @Test func pathsInExtraFoldersResolveAndOthersDont() throws {
        let other = try makeOther()
        let ws = Workspace(root: try makeProject().root, folders: [ExtraFolder(path: other.path, writable: false)])
        #expect(try ws.resolve(other.path + "/notes/budget.md").path == other.path + "/notes/budget.md")
        #expect(try ws.resolve(other.path + "/notes/../top.txt").path == other.path + "/top.txt")
        #expect(try ws.resolve("README.md") == ws.root.appending(path: "README.md"))
        // Outside both: refused, and the message names the other folder.
        #expect(throws: ToolFailure.self) { try ws.resolve("/etc/hosts") }
        do { _ = try ws.resolve("/etc/hosts") } catch let f as ToolFailure { #expect(f.message.contains(other.path)) }
        // A symlink inside the extra folder that points out of it is refused too.
        try FileManager.default.createSymbolicLink(at: other.appending(path: "out"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        #expect(throws: ToolFailure.self) { try ws.resolve(other.path + "/out/hosts") }
        // A sibling whose name starts the same isn't inside.
        #expect(throws: ToolFailure.self) { try ws.resolve(other.path + "-evil/x") }
    }

    @Test func readOnlyFoldersRefuseWritesAndWritableOnesTakeThem() async throws {
        let ro = try makeOther(), rw = try makeOther()
        let ws = Workspace(root: try makeProject().root,
                           folders: [ExtraFolder(path: ro.path, writable: false), ExtraFolder(path: rw.path, writable: true)])
        let read = await call(ReadFileTool(), ["path": .string(ro.path + "/notes/budget.md")], ws)
        #expect(read.text.contains("42 walruses"))
        let refused = await call(WriteFileTool(), ["path": .string(ro.path + "/new.md"), "content": "x"], ws)
        #expect(refused.isError && refused.text.contains("read-only folder"))
        #expect(!FileManager.default.fileExists(atPath: ro.path + "/new.md"))
        let edit = await call(EditFileTool(), ["path": .string(ro.path + "/top.txt"), "old_string": "top", "new_string": "changed"], ws)
        #expect(edit.isError)
        let wrote = await call(WriteFileTool(), ["path": .string(rw.path + "/new.md"), "content": "hello\n"], ws)
        #expect(!wrote.isError)
        #expect(try String(contentsOf: rw.appending(path: "new.md"), encoding: .utf8) == "hello\n")
        // A nested writable folder inside a read-only one wins for its own files.
        let nested = Workspace(root: ws.root, folders: [ExtraFolder(path: ro.path, writable: false),
                                                        ExtraFolder(path: ro.path + "/notes", writable: true)])
        #expect(nested.isWritable(ro.appending(path: "notes/budget.md")) && !nested.isWritable(ro.appending(path: "top.txt")))
    }

    @Test func privateFirmlinkPathsMatchForNewFilesToo() async throws {
        // /tmp is /private/tmp: a folder added as one must take new files named the other way.
        let dir = URL(fileURLWithPath: "/tmp/kk-firm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(root: try makeProject().root, folders: [ExtraFolder(path: "/private" + dir.path, writable: true)])
        #expect(ws.folders[0].path == dir.path)
        let wrote = await call(WriteFileTool(), ["path": .string("/private" + dir.path + "/new.md"), "content": "x\n"], ws)
        #expect(!wrote.isError)
        #expect(FileManager.default.fileExists(atPath: dir.path + "/new.md"))
        #expect(try ws.resolve(dir.path + "/later.md").path == dir.path + "/later.md")
    }

    @Test func listingToolsWorkInExtraFoldersWithAbsolutePaths() async throws {
        let other = try makeOther(git: true)
        try Data("ignored.md\n".utf8).write(to: other.appending(path: ".gitignore"))
        try Data("Budget too\n".utf8).write(to: other.appending(path: "ignored.md"))
        let ws = Workspace(root: try makeProject().root, folders: [ExtraFolder(path: other.path, writable: false)])
        let glob = await call(GlobTool(), ["pattern": "**/*.md", "path": .string(other.path)], ws)
        #expect(glob.text.contains(other.path + "/notes/budget.md"))
        #expect(!glob.text.contains("ignored.md"))                    // the extra folder's own .gitignore
        let grep = await call(GrepTool(), ["pattern": "Budget", "path": .string(other.path)], ws)
        #expect(grep.text.contains(other.path + "/notes/budget.md:1: Budget: 42 walruses"))
        // The project's own listing is unchanged (relative paths).
        let local = await call(GrepTool(), ["pattern": "greet", "glob": "*.swift"], ws)
        #expect(local.text.contains("src/main.swift:12:"))
    }

    @Test func thePromptListsTheFoldersAndChangesWithThem() async throws {
        let other = try makeOther()
        let project = try makeProject()
        var builder = SystemPromptBuilder(workspace: Workspace(root: project.root, folders: [ExtraFolder(path: other.path, writable: true)]),
                                          tools: AllTools.all, mode: .fullAuto)
        builder.sandbox = SandboxPolicy()
        let text = await builder.build()
        #expect(text.contains("- Other folder: \(other.path) (read and write)"))
        #expect(text.contains("used by absolute path"))
        #expect(text.contains("Commands may also write in the other folders marked read and write."))
        // Without folders, the project prompt is as before.
        let plain = await SystemPromptBuilder(workspace: project, tools: AllTools.all, mode: .ask).build()
        #expect(!plain.contains("Other folder") && plain.contains("- Project root: "))
        // The frozen prompt is rebuilt when the folders change, and not otherwise.
        let frozen = FrozenSystemPrompt()
        let a = await frozen.text(workspace: project, tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        let b = await frozen.text(workspace: Workspace(root: project.root, folders: [ExtraFolder(path: other.path, writable: false)]),
                                  tools: AllTools.all, mode: .ask, sandbox: nil, userPrompt: "", addendum: "")
        #expect(a != b && b.contains("(read-only)"))
    }

    @Test func aChatsPromptSaysWorkingFolder() async throws {
        var builder = SystemPromptBuilder(workspace: try makeProject(), tools: AllTools.all, mode: .ask)
        builder.isChat = true
        let text = await builder.build()
        #expect(text.contains("an assistant on the user's Mac") && text.contains("- Working folder: "))
        #expect(!text.contains("coding agent") && !text.contains("Project root"))
    }

    @Test func sessionsKeepTheirFolders() async throws {
        let store = SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-folders-\(UUID().uuidString.prefix(8))"))
        let header = SessionHeader(endpointID: UUID(), model: "m", workspace: "/tmp/p")
        try await store.create(header)
        try await store.append(.folders([ExtraFolder(path: "/tmp/a", writable: true)]), to: header.id)
        try await store.append(.folders([ExtraFolder(path: "/tmp/a", writable: false), ExtraFolder(path: "/tmp/b", writable: true)]),
                               to: header.id)
        let loaded = try #require(try await store.load(header.id))
        #expect(loaded.folders.map(\.writable) == [false, true])
        #expect(loaded.folders.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["a", "b"])
    }

    @Test func cliFoldersMergeAndPersist() throws {
        let a = ExtraFolder(path: "/tmp/a", writable: true), b = ExtraFolder(path: "/tmp/b", writable: true)
        let merged = CLISession.merged([a, b], [ExtraFolder(path: "/tmp/a", writable: false)])
        #expect(merged.map(\.writable) == [true, false] && merged.last?.path == a.path)
        let other = try makeOther()
        let o = try CLIOptions.parse(["--add-dir", other.path, "--read-dir", other.path + "/notes"])
        #expect(o.folders == [ExtraFolder(path: other.path, writable: true), ExtraFolder(path: other.path + "/notes", writable: false)])
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.parse(["--add-dir", "/no/such/folder"]) }
    }
}

@Suite(.enabled(if: SandboxPolicy.isAvailable)) struct ExtraFolderSandboxTests {
    @Test func writableFoldersAreWritableInTheSandboxButTheirGitHooksArent() async throws {
        let rw = try makeOther(git: true), ro = try makeOther()
        let ws = Workspace(root: try makeProject().root,
                           folders: [ExtraFolder(path: rw.path, writable: true), ExtraFolder(path: ro.path, writable: false)])
        // SessionRun is what adds the writable folders to the sandbox.
        let session = Session(header: SessionHeader(endpointID: UUID(), model: "m", workspace: ws.root.path), messages: [], model: "m")
        let run = SessionRun(session: session, store: SessionStore(root: FileManager.default.temporaryDirectory.appending(path: "kk-s")),
                             settings: RunSettings(), profile: ModelProfile(endpointID: UUID(), model: "m"), endpointID: UUID(),
                             mode: .fullAuto, rules: [], tools: [BashTool()], workspace: ws, shell: ShellState(cwd: ws.root),
                             contextLimit: nil, sandbox: SandboxPolicy(), turn: TurnKey(UUID()),
                             checkpoints: CheckpointStore(directory: FileManager.default.temporaryDirectory.appending(path: "kk-c")),
                             approve: { _ in .allow }, hooks: nil, subagentModel: nil)
        #expect(run.config.sandbox?.extraWritable == [rw.path] && run.config.sandbox?.readOnly == [ro.path])
        func bash(_ command: String) async -> ToolOutput {
            let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(["command": .string(command)])), as: UTF8.self)
            return await AgentLoop.execute(ToolCall(id: "t", name: "bash", arguments: json), tools: ["bash": BashTool()],
                                           config: run.config, workspace: ws)
        }
        let ok = await bash("echo made > '\(rw.path)/made.txt'")
        #expect(ok.exitCode == 0 && FileManager.default.fileExists(atPath: rw.path + "/made.txt"))
        let hook = await bash("echo 'echo pwned' > '\(rw.path)/.git/hooks/pre-commit'")
        #expect(hook.exitCode != 0 && !FileManager.default.fileExists(atPath: rw.path + "/.git/hooks/pre-commit"))
        let config = await bash("git -C '\(rw.path)' config core.hooksPath /tmp/elsewhere")
        #expect(config.exitCode != 0)
        let readOnly = await bash("echo no > '\(ro.path)/no.txt'")
        #expect(readOnly.exitCode != 0 && !FileManager.default.fileExists(atPath: ro.path + "/no.txt"))
    }
}
