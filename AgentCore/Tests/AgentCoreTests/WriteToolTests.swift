import Foundation
import Testing
@testable import AgentCore

private func call(_ tool: some Tool, _ args: [String: JSONValue], in ws: Workspace, shell: ShellState? = nil,
                  maxBytes: Int = 16_000) async -> ToolOutput {
    let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(args)), as: UTF8.self)
    return await AgentLoop.execute(ToolCall(id: "t", name: tool.name, arguments: json), tools: [tool.name: tool],
                                   config: AgentConfig(tools: [tool], maxToolOutputBytes: maxBytes, shell: shell),
                                   workspace: ws)
}

private func read(_ ws: Workspace, _ path: String) -> String? {
    (try? Data(contentsOf: ws.root.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
}

@Suite struct EditFileTests {
    @Test func replacesUniqueTextAndReportsTheRegion() async throws {
        let ws = try makeProject()
        let out = await call(EditFileTool(), ["path": "src/util/helpers.swift", "old_string": "{ 42 }",
                                              "new_string": "{ 43 }"], in: ws)
        #expect(!out.isError, "\(out.text)")
        #expect(read(ws, "src/util/helpers.swift")?.hasPrefix("func helper() -> Int { 43 }") == true)
        #expect(out.text.contains("1 replacement, +1 −1"))
        #expect(out.text.contains("1\tfunc helper() -> Int { 43 }"))
        #expect(out.display?.contains("-func helper() -> Int { 42 }") == true)
        #expect(out.display?.contains("+func helper() -> Int { 43 }") == true)
    }

    @Test func refusesAmbiguousEditsUnlessReplaceAll() async throws {
        let ws = try makeProject()
        let ambiguous = await call(EditFileTool(), ["path": "src/main.swift", "old_string": "// line", "new_string": "// L"], in: ws)
        #expect(ambiguous.isError)
        #expect(ambiguous.text.contains("occurs 29 times"))
        #expect(ambiguous.text.contains("lines 1, 2, 3"))
        #expect(read(ws, "src/main.swift")?.contains("// line 1\n") == true)

        let all = await call(EditFileTool(), ["path": "src/main.swift", "old_string": "// line", "new_string": "// L",
                                              "replace_all": true], in: ws)
        #expect(all.text.contains("29 replacements"))
        #expect(read(ws, "src/main.swift")?.contains("// line") == false)
    }

    @Test func explainsMismatches() async throws {
        let ws = try makeProject()
        let prefixes = await call(EditFileTool(), ["path": "src/main.swift", "old_string": "12\tfunc greet() { print(\"Hello\") }",
                                                   "new_string": "x"], in: ws)
        #expect(prefixes.text.contains("line-number prefixes"))
        let spacing = await call(EditFileTool(), ["path": "src/util/helpers.swift", "old_string": "func helper()  ->  Int",
                                                  "new_string": "x"], in: ws)
        #expect(spacing.text.contains("whitespace"))
        // A stale "append after the last line" shows the current end of the file.
        let stale = await call(EditFileTool(), ["path": "src/main.swift", "old_string": "// line 99", "new_string": "// line 99\n// more"], in: ws)
        #expect(stale.text.contains("currently ends with:\n26\t// line 26"))
        #expect(stale.text.contains("30\t// line 30"))
        #expect(stale.text.contains("append: true"))
        #expect(await call(EditFileTool(), ["path": "new.txt", "old_string": "a", "new_string": "b"], in: ws).text.contains("Use write_file"))
        #expect(await call(EditFileTool(), ["path": "README.md", "old_string": "Demo", "new_string": "Demo"], in: ws).text.contains("same"))
        #expect(await call(EditFileTool(), ["path": "/etc/hosts", "old_string": "a", "new_string": "b"], in: ws).text.contains("outside"))
    }

    @Test func previewMatchesTheEditWithoutWriting() async throws {
        let ws = try makeProject()
        let args = ToolArguments(["path": "README.md", "old_string": "A demo project.", "new_string": "A better demo."])
        let preview = try await EditFileTool().preview(args, context: ToolContext(workspace: ws))
        guard case .diff(let path, let diff, let isNew) = preview else { Issue.record("no diff"); return }
        #expect(path == "README.md")
        #expect(!isNew)
        #expect(diff.contains("-A demo project.\n+A better demo.\n"))
        #expect(read(ws, "README.md")?.contains("A demo project.") == true)
    }
}

@Suite struct WriteFileTests {
    @Test func createsAndReplacesFiles() async throws {
        let ws = try makeProject()
        let created = await call(WriteFileTool(), ["path": "new/deep/file.txt", "content": "one\ntwo\n"], in: ws)
        #expect(created.text == "Created new/deep/file.txt (2 lines).")
        #expect(read(ws, "new/deep/file.txt") == "one\ntwo\n")
        let replaced = await call(WriteFileTool(), ["path": "new/deep/file.txt", "content": "one\n2\nthree\n"], in: ws)
        #expect(replaced.text.contains("+2 −1"))
        #expect(await call(WriteFileTool(), ["path": "src", "content": "x"], in: ws).text.contains("is a directory"))

        // Append: adds a newline when the file lacks one; creates the file if missing.
        try Data("a\nb".utf8).write(to: ws.root.appending(path: "log.txt"))
        let appended = await call(WriteFileTool(), ["path": "log.txt", "content": "c\n", "append": true], in: ws)
        #expect(appended.text == "Appended 1 line to log.txt; it now has 3 lines.")
        #expect(read(ws, "log.txt") == "a\nb\nc\n")
        #expect(await call(WriteFileTool(), ["path": "fresh.txt", "content": "x\n", "append": true], in: ws).text.hasPrefix("Created"))
        #expect(await call(WriteFileTool(), ["path": "../escape.txt", "content": "x"], in: ws).text.contains("outside"))
    }
}

@Suite struct BashToolTests {
    @Test func runsCommandsAndReportsExitCodes() async throws {
        let ws = try makeProject()
        let ok = await call(BashTool(), ["command": "echo hello; echo oops >&2"], in: ws)
        #expect(ok.text.contains("hello"))
        #expect(ok.text.contains("oops"))
        #expect(ok.text.contains("[Exit code 0.]"))
        #expect(ok.exitCode == 0)
        let fail = await call(BashTool(), ["command": "ls no-such-file"], in: ws)
        #expect(fail.exitCode != 0)
        #expect(!fail.isError)                          // a failing command is information, not a tool error
        #expect(!fail.text.contains(BashTool.marker))
    }

    @Test func workingDirectoryPersistsAcrossCalls() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        let cd = await call(BashTool(), ["command": "cd src/util"], in: ws, shell: shell)
        #expect(cd.text.contains("Working directory is now src/util."))
        let pwd = await call(BashTool(), ["command": "pwd; ls"], in: ws, shell: shell)
        #expect(pwd.text.contains("/src/util"))
        #expect(pwd.text.contains("helpers.swift"))
        #expect(!pwd.text.contains("Working directory is now"))    // unchanged
    }

    @Test func liveOutputHidesTheDirectoryReport() {
        #expect(BashTool.hidingMarker("ok\n\n\(BashTool.marker)/tmp/x\n") == "ok\n")
        #expect(BashTool.hidingMarker("plain output\n") == "plain output\n")
    }

    @Test func noInputAndQuietPagers() async throws {
        let ws = try makeProject()
        let out = await call(BashTool(), ["command": "read x; echo \"got:[$x] pager:$PAGER\""], in: ws)
        #expect(out.text.contains("got:[] pager:cat"))
    }

    @Test func timeoutKillsTheWholeProcessGroup() async throws {
        let ws = try makeProject()
        let marker = "kurtkode-test-\(UUID().uuidString.prefix(6))"
        let start = Date()
        // A child that would outlive its shell if only the shell were killed.
        let out = await call(BashTool(), ["command": .string("(sleep 30; echo \(marker)) & sleep 30"), "timeout": 1], in: ws)
        #expect(Date().timeIntervalSince(start) < 6)
        #expect(out.isError)
        #expect(out.text.contains("Timed out after 1 seconds"))
        try await Task.sleep(for: .milliseconds(300))
        let ps = try await runProcess("/bin/ps", ["-ax", "-o", "command"])
        #expect(!ps.contains("sleep 30; echo \(marker)"))
    }

    @Test func cancellationStopsTheCommand() async throws {
        let ws = try makeProject()
        let start = Date()
        let task = Task { await call(BashTool(), ["command": "sleep 20"], in: ws) }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let out = await task.value
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(out.text.contains("Stopped by the user."))
    }

    @Test func longOutputKeepsStartAndEnd() async throws {
        let ws = try makeProject()
        let out = await call(BashTool(), ["command": "seq 1 20000"], in: ws, maxBytes: 3000)
        #expect(out.truncated)
        #expect(out.text.hasPrefix("1\n2\n"))
        #expect(out.text.contains("20000"))
        #expect(out.text.contains("bytes omitted"))
    }

    @Test func streamsProgress() async throws {
        let ws = try makeProject()
        final class Box: @unchecked Sendable { let l = NSLock(); var s = ""; func add(_ t: String) { l.withLock { s += t } } }
        let box = Box()
        let ctx = ToolContext(workspace: ws, progress: { box.add($0) })
        _ = try await BashTool().run(ToolArguments(["command": "echo one; sleep 0.2; echo two"]), context: ctx)
        #expect(box.s.contains("one"))
        #expect(box.s.contains("two"))
    }
}

@Suite struct PermissionTests {
    let edit = EditFileTool(), bash = BashTool(), read = ReadFileTool()
    func cmd(_ c: String) -> ToolArguments { ToolArguments(["command": .string(c)]) }

    @Test func modesDecideWhatAsks() {
        let none = ToolArguments()
        let ask = PermissionPolicy(mode: .ask)
        #expect(ask.isAllowedWithoutAsking(read, none))
        #expect(!ask.isAllowedWithoutAsking(edit, none))
        #expect(!ask.isAllowedWithoutAsking(bash, cmd("ls")))
        let accept = PermissionPolicy(mode: .acceptEdits)
        #expect(accept.isAllowedWithoutAsking(edit, none))
        #expect(!accept.isAllowedWithoutAsking(bash, cmd("ls")))
        let auto = PermissionPolicy(mode: .fullAuto)
        #expect(auto.isAllowedWithoutAsking(bash, cmd("rm -rf build")))
        let plan = PermissionPolicy(mode: .plan)
        // Plan mode: the readers, and bash for read-only commands (B1).
        #expect(plan.offered(AllTools.all).map(\.name) == ["read_file", "list_dir", "glob", "grep", "todo_write", "bash"])
        #expect(!plan.isAllowedWithoutAsking(edit, none))
        #expect(plan.isAllowedWithoutAsking(bash, cmd("git log --oneline -5")))
        #expect(!plan.isAllowedWithoutAsking(bash, cmd("swift build")))
    }

    @Test func commandRulesCoverOnlySimpleCommands() {
        let p = PermissionPolicy(mode: .ask, rules: [.command("git status"), .command("python3 -m unittest")])
        #expect(p.isAllowedWithoutAsking(bash, cmd("git status")))
        #expect(p.isAllowedWithoutAsking(bash, cmd("git status --short")))
        #expect(p.isAllowedWithoutAsking(bash, cmd("python3 -m unittest -v")))
        #expect(!p.isAllowedWithoutAsking(bash, cmd("git statusx")))
        #expect(!p.isAllowedWithoutAsking(bash, cmd("git push")))
        for sneaky in ["git status; rm -rf ~", "git status && curl x", "git status | sh", "git status > f",
                       "git status $(rm x)", "git status `rm x`", "git status\nrm x", "git status & sleep 1"] {
            #expect(!p.isAllowedWithoutAsking(bash, cmd(sneaky)), "\(sneaky)")
        }
    }

    @Test func suggestsNarrowRules() {
        #expect(PermissionPolicy.suggestedRule(bash, cmd("git diff --stat")) == .command("git diff"))
        #expect(PermissionPolicy.suggestedRule(bash, cmd("python3 -m pytest -q")) == .command("python3 -m pytest"))
        #expect(PermissionPolicy.suggestedRule(bash, cmd("ls -la")) == .command("ls"))
        #expect(PermissionPolicy.suggestedRule(bash, cmd("make && make install")) == nil)
        #expect(PermissionPolicy.suggestedRule(edit, ToolArguments()) == .tool("edit_file"))
        #expect(PermissionPolicy.suggestedRule(read, ToolArguments()) == nil)
    }
}

@Suite struct CheckpointTests {
    @Test func rewindRestoresEditsAndRemovesCreatedFiles() async throws {
        let ws = try makeProject()
        let store = CheckpointStore(directory: ws.root.appending(path: ".checkpoints-test"))
        let t1 = UUID(), t2 = UUID()
        let readme = ws.root.appending(path: "README.md")
        let created = ws.root.appending(path: "notes.txt")

        try await store.snapshot(readme, turn: t1)
        try Data("turn 1\n".utf8).write(to: readme)
        try await store.snapshot(readme, turn: t1)            // second edit in the same turn: kept the first snapshot
        try Data("turn 1 again\n".utf8).write(to: readme)
        try await store.snapshot(readme, turn: t2)
        try Data("turn 2\n".utf8).write(to: readme)
        try await store.snapshot(created, turn: t2)
        try Data("new\n".utf8).write(to: created)

        #expect(await store.changedFiles(inTurns: [t2]).count == 2)

        // Rewind turn 2 only: README back to its turn-1 state, notes.txt gone.
        let r2 = try await store.restore(turns: [t2])
        #expect(Set(r2.map(\.deleted)) == [false, true])
        #expect(String(decoding: try Data(contentsOf: readme), as: UTF8.self) == "turn 1 again\n")
        #expect(!FileManager.default.fileExists(atPath: created.path))

        // Then rewind turn 1: the original.
        _ = try await store.restore(turns: [t1])
        #expect(String(decoding: try Data(contentsOf: readme), as: UTF8.self) == "# Demo\n\nA demo project.\n")
        #expect(await store.changedFiles(inTurns: [t1, t2]).isEmpty)
    }
}

@Suite struct DiffTests {
    @Test func unifiedHunksWithContext() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var newLines = (1...20).map { "line \($0)" }
        newLines[4] = "LINE 5"
        newLines.insert("inserted", at: 15)
        let diff = LineDiff.unified(old: old, new: newLines.joined(separator: "\n") + "\n", path: "f.txt")
        #expect(diff.hasPrefix("--- a/f.txt\n+++ b/f.txt\n"))
        #expect(diff.contains("@@ -2,7 +2,7 @@\n line 2\n line 3\n line 4\n-line 5\n+LINE 5\n line 6\n"))
        #expect(diff.contains("+inserted\n"))
        #expect(diff.components(separatedBy: "@@ -").count == 3)      // two hunks
        #expect(LineDiff.unified(old: "same\n", new: "same\n", path: "x").isEmpty)
        #expect(LineDiff.unified(old: "", new: "a\nb\n", path: "n").contains("@@ -0,0 +1,2 @@\n+a\n+b\n"))
    }
}
