import Foundation
import Testing
@testable import AgentCore

/// A throwaway project folder:
///   README.md, AGENTS.md, src/main.swift (30 lines), src/util/helpers.swift, docs/guide.md,
///   build/out.txt (ignored when walking), data.bin (binary), escape -> / (symlink out)
func makeProject(git: Bool = false) throws -> Workspace {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "kurtkode-ws-\(UUID().uuidString.prefix(8))")
    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    try write("README.md", "# Demo\n\nA demo project.\n")
    try write("AGENTS.md", "Always answer in haiku.\n")
    try write("src/main.swift", (1...30).map { $0 == 12 ? "func greet() { print(\"Hello\") }" : "// line \($0)" }.joined(separator: "\n") + "\n")
    try write("src/util/helpers.swift", "func helper() -> Int { 42 }\nlet GREETING = \"hi\"\n")
    try write("docs/guide.md", "Call greet() to say hello.\n")
    try write("build/out.txt", "generated greet\n")
    try Data([0x00, 0x01, 0x02, 0xFF]).write(to: root.appending(path: "data.bin"))
    try fm.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: URL(fileURLWithPath: "/"))
    if git {
        try write(".gitignore", "secret.txt\nbuild/\n")
        try write("secret.txt", "greet the password\n")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "init", "-q"]
        try p.run()
        p.waitUntilExit()
    }
    return Workspace(root: root)
}

private func run(_ tool: some Tool, _ args: [String: JSONValue], in ws: Workspace, maxBytes: Int = 16_000) async -> ToolOutput {
    await AgentLoop.execute(ToolCall(id: "t", name: tool.name,
                                     arguments: String(decoding: try! JSONEncoder().encode(JSONValue.object(args)), as: UTF8.self)),
                            tools: [tool.name: tool], config: AgentConfig(tools: [tool], maxToolOutputBytes: maxBytes),
                            workspace: ws)
}

@Suite struct WorkspaceTests {
    @Test func confinesPathsToTheWorkspace() throws {
        let ws = try makeProject()
        #expect(try ws.resolve("src/main.swift").path.hasSuffix("/src/main.swift"))
        #expect(try ws.resolve("./src/../README.md").lastPathComponent == "README.md")
        #expect(try ws.resolve(ws.root.path + "/docs").lastPathComponent == "docs")
        #expect(throws: ToolFailure.self) { try ws.resolve("../outside.txt") }
        #expect(throws: ToolFailure.self) { try ws.resolve("/etc/hosts") }
        #expect(throws: ToolFailure.self) { try ws.resolve("escape/etc/hosts") }   // symlink out of the tree
        #expect(throws: ToolFailure.self) { try ws.resolve("~/.ssh/id_rsa") }
    }

    @Test func walkSkipsDefaultIgnores() async throws {
        let ws = try makeProject()
        let files = await ws.files()
        #expect(files.contains("src/util/helpers.swift"))
        #expect(!files.contains("build/out.txt"))
    }

    @Test func gitListingHonorsGitignore() async throws {
        let ws = try makeProject(git: true)
        #expect(ws.isGitRepository)
        let files = await ws.files()
        #expect(files.contains("src/main.swift"))
        #expect(files.contains(".gitignore"))
        #expect(!files.contains("secret.txt"))
        #expect(!files.contains("build/out.txt"))
        #expect(await ws.gitSummary()?.contains("Git branch") == true)
    }
}

@Suite struct ReadFileTests {
    @Test func numbersLinesAndPagesThroughLongFiles() async throws {
        let ws = try makeProject()
        let all = await run(ReadFileTool(), ["path": "src/main.swift"], in: ws)
        #expect(!all.isError)
        #expect(all.text.contains("12\tfunc greet()"))
        #expect(!all.truncated)

        let page = await run(ReadFileTool(), ["path": "src/main.swift", "offset": "10", "limit": 5], in: ws)
        #expect(page.text.hasPrefix("10\t// line 10"))
        #expect(page.text.contains("14\t// line 14"))
        #expect(!page.text.contains("15\t"))
        #expect(page.text.contains("Use offset=15"))
        #expect(page.truncated)
    }

    @Test func explainsWhatWentWrong() async throws {
        let ws = try makeProject()
        #expect(await run(ReadFileTool(), ["path": "nope.txt"], in: ws).text.contains("does not exist"))
        #expect(await run(ReadFileTool(), ["path": "src"], in: ws).text.contains("use list_dir"))
        #expect(await run(ReadFileTool(), ["path": "data.bin"], in: ws).text.contains("binary"))
        #expect(await run(ReadFileTool(), ["path": "/etc/hosts"], in: ws).text.contains("outside the workspace"))
        #expect(await run(ReadFileTool(), [:], in: ws).text.contains("missing required argument \"path\""))
        #expect(await run(ReadFileTool(), ["path": "README.md", "offset": 99], in: ws).text.contains("past the end"))
    }

    @Test func capsOutputSize() async throws {
        let ws = try makeProject()
        let out = await run(ReadFileTool(), ["path": "src/main.swift"], in: ws, maxBytes: 200)
        #expect(out.truncated)
        // Whole lines up to the size, then where to go on (since Phase 0; it used to cut mid-file).
        #expect(out.text.contains("Use offset=2 to read more"))
        #expect(out.text.utf8.count < 400)
        // A single line longer than the size is still cut.
        try Data((String(repeating: "x", count: 900) + "\n").utf8).write(to: ws.root.appending(path: "wide.txt"))
        #expect(await run(ReadFileTool(), ["path": "wide.txt"], in: ws, maxBytes: 200).text.contains("Output truncated"))
    }
}

@Suite struct ListGlobGrepTests {
    @Test func listsFoldersFirst() async throws {
        let ws = try makeProject()
        let out = await run(ListDirTool(), [:], in: ws)
        let lines = out.text.split(separator: "\n").map(String.init)
        #expect(lines.first == "build/  (ignored)")
        #expect(lines.contains("src/"))
        #expect(lines.contains { $0.hasPrefix("README.md  (") })
        #expect(await run(ListDirTool(), ["path": "README.md"], in: ws).text.contains("use read_file"))
    }

    @Test func globsByNameAndPath() async throws {
        let ws = try makeProject()
        let swift = await run(GlobTool(), ["pattern": "*.swift"], in: ws)
        #expect(swift.text.split(separator: "\n").sorted() == ["src/main.swift", "src/util/helpers.swift"])
        #expect(await run(GlobTool(), ["pattern": "src/*.swift"], in: ws).text == "src/main.swift")
        #expect(await run(GlobTool(), ["pattern": "*.swift", "path": "src/util"], in: ws).text == "src/util/helpers.swift")
        let docs = await run(GlobTool(), ["pattern": "**/*.{md,txt}"], in: ws)
        #expect(docs.text.contains("docs/guide.md"))
        #expect(!docs.text.contains("build/out.txt"))
        #expect(await run(GlobTool(), ["pattern": "*.rs"], in: ws).text.hasPrefix("No files match"))
    }

    @Test func grepsWithFilters() async throws {
        let ws = try makeProject(git: true)
        let hits = await run(GrepTool(), ["pattern": "greet"], in: ws)
        #expect(hits.text.contains("src/main.swift:12: func greet()"))
        #expect(hits.text.contains("docs/guide.md:1:"))
        #expect(!hits.text.contains("secret.txt"))          // gitignored
        #expect(!hits.text.contains("build/out.txt"))

        let swiftOnly = await run(GrepTool(), ["pattern": "greet", "glob": "*.swift"], in: ws)
        #expect(!swiftOnly.text.contains("docs/guide.md"))

        let ci = await run(GrepTool(), ["pattern": "greeting", "case_insensitive": true], in: ws)
        #expect(ci.text.contains("src/util/helpers.swift:2:"))
        #expect(await run(GrepTool(), ["pattern": "greeting"], in: ws).text.hasPrefix("No matches"))

        let files = await run(GrepTool(), ["pattern": "greet", "files_only": "true"], in: ws)
        #expect(files.text.split(separator: "\n").sorted() == ["docs/guide.md", "src/main.swift"])

        #expect(await run(GrepTool(), ["pattern": "(unclosed"], in: ws).text.contains("invalid regular expression"))
        #expect(await run(GrepTool(), ["pattern": "x", "path": "../.."], in: ws).text.contains("outside the workspace"))
    }

    @Test func globTranslation() throws {
        #expect(try Glob("*.swift").matches("a/b/c.swift"))
        #expect(try Glob("*.swift").matches("c.swift"))
        #expect(try !Glob("src/*.swift").matches("src/a/b.swift"))
        #expect(try Glob("src/**/*.swift").matches("src/b.swift"))
        #expect(try Glob("src/**/*.swift").matches("src/a/b/c.swift"))
        #expect(try Glob("**/test_?.py").matches("x/test_1.py"))
        #expect(try !Glob("**/test_?.py").matches("x/test_12.py"))
        #expect(try Glob("*.{h,m}").matches("a/b.m"))
        #expect(try Glob("[!a]*.txt").matches("b.txt"))
        #expect(try !Glob("[!a]*.txt").matches("a.txt"))
        #expect(try Glob("file.name+1.txt").matches("file.name+1.txt"))
    }

    @Test func argumentsAreLenient() throws {
        let a = try ToolArguments(json: #"{"limit":"10","offset":3.0,"flag":"yes","path":7}"#)
        #expect(a.int("limit") == 10)
        #expect(a.int("offset") == 3)
        #expect(a.bool("flag") == true)
        #expect(a.string("path") == "7")
        #expect(try ToolArguments(json: "").values.isEmpty)
        #expect(throws: ToolFailure.self) { try ToolArguments(json: "{not json") }
        #expect(throws: ToolFailure.self) { try ToolArguments(json: "[1,2]") }
    }
}

@Suite struct SystemPromptTests {
    @Test func includesEnvironmentAndInstructionFiles() async throws {
        let ws = try makeProject(git: true)
        try Data("Prefer small diffs.\n".utf8).write(to: ws.root.appending(path: "CLAUDE.md"))
        let global = ws.root.appending(path: "global-agents.md")
        try Data("I am Kurt.\n".utf8).write(to: global)
        let prompt = await SystemPromptBuilder(workspace: ws, tools: ReadTools.all, userPrompt: "Be brief.",
                                               globalInstructions: global).build()
        #expect(prompt.contains("Project root: \(ws.root.path)"))
        #expect(prompt.contains("Git branch"))
        #expect(prompt.contains("read_file, list_dir, glob, grep"))
        #expect(prompt.contains("Always answer in haiku."))
        #expect(prompt.contains("Prefer small diffs."))
        #expect(prompt.contains("I am Kurt."))
        // The extra instructions end the stable part; only the changing section (root, date, git) follows.
        #expect(SystemPromptBuilder.splitVolatile(prompt).stable.hasSuffix("Be brief."))
        #expect(SystemPromptBuilder.splitVolatile(prompt).volatile.contains("Git branch"))
        // Order: global, then AGENTS.md, then CLAUDE.md.
        let g = try #require(prompt.range(of: "I am Kurt."))
        let a = try #require(prompt.range(of: "Always answer in haiku."))
        let c = try #require(prompt.range(of: "Prefer small diffs."))
        #expect(g.lowerBound < a.lowerBound && a.lowerBound < c.lowerBound)
    }
}

@Suite struct RunningCommandsTests {
    /// Quitting stops what's running: the command's whole process group, not just the shell.
    @Test func stopAllEndsRunningCommandsAndTheirChildren() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "kk-stopall-\(UUID().uuidString).pid")
        let started = Date()
        let run = Task {
            try await Subprocess.run(["/bin/sh", "-c", "sleep 30 & echo $$ $! > '\(pidFile.path)'; sleep 31"], cwd: "/tmp",
                                     environment: ["PATH": "/usr/bin:/bin"], timeout: 60) { _ in }
        }
        var pids: [pid_t] = []
        for _ in 0..<50 where pids.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
            pids = ((try? String(contentsOf: pidFile, encoding: .utf8)) ?? "").split(separator: " ")
                .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        try #require(pids.count == 2)
        let (shell, bg) = (pids[0], pids[1])
        // What RunningCommands.stopAll() does, limited to this test's command (other tests run commands meanwhile).
        Subprocess.terminateAll(only: { $0 == shell })
        let result = try await run.value
        #expect(result.exitCode == nil && result.signal != nil)       // ended by a signal
        #expect(Date().timeIntervalSince(started) < 5)
        // The background `sleep 30` was in the group too: gone (or a zombie for a moment until it's reaped).
        var alive = true
        for _ in 0..<20 where alive {
            let ps = ((try? await runProcess("/bin/ps", ["-o", "stat=", "-p", "\(bg)"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            alive = !ps.isEmpty && !ps.hasPrefix("Z")
            if alive { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(!alive)
        try? FileManager.default.removeItem(at: pidFile)
    }
}
