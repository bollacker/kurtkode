import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit

// Phase 1 of GAP_ANALYSIS.md (agentic core): B4 grep on ripgrep, …

private func grep(_ args: [String: JSONValue], in ws: Workspace, rg: URL?, maxBytes: Int = 16_000) async -> ToolOutput {
    let tool = GrepTool(rg: rg)
    return await AgentLoop.execute(ToolCall(id: "t", name: tool.name,
                                            arguments: String(decoding: try! JSONEncoder().encode(JSONValue.object(args)), as: UTF8.self)),
                                   tools: [tool.name: tool], config: AgentConfig(tools: [tool], maxToolOutputBytes: maxBytes),
                                   workspace: ws)
}

private func put(_ text: String, _ path: String, in ws: Workspace) throws {
    let url = ws.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// Both engines: the bundled ripgrep and the built-in search. Each test runs on both and must give the same text.
private let engines: [String] = ["rg", "builtin"]
private func engine(_ name: String) -> URL? {
    name == "rg" ? Ripgrep.locate([:]) : nil
}

@Suite struct GrepB4Tests {
    @Test func theBundledRipgrepIsFound() throws {
        let rg = try #require(Ripgrep.locate([:]))
        #expect(rg.path.hasSuffix("Bin/rg"))
        #expect(Ripgrep.locate(["KURTKODE_RG": "none"]) == nil)
        #expect(Ripgrep.locate(["KURTKODE_RG": "/no/such/rg"]) == nil)
        #expect(Ripgrep.locate(["KURTKODE_RG": rg.path]) == rg)
    }

    @Test(arguments: engines) func countModeGivesPerFileCountsAndATotal(_ e: String) async throws {
        let ws = try makeProject(git: true)
        try put((1...40).map { $0 % 4 == 0 ? "warning: unused \($0)" : "ok \($0)" }.joined(separator: "\n") + "\n", "build.log", in: ws)
        try put("warning: one\nwarning: two\n", "src/more.log", in: ws)
        let out = await grep(["pattern": "^warning:", "output_mode": "count"], in: ws, rg: engine(e))
        #expect(out.text == "build.log: 10\nsrc/more.log: 2\nTotal: 12 matching lines in 2 files.", "\(e): \(out.text)")
    }

    @Test(arguments: engines) func contextLinesAndGroupSeparators(_ e: String) async throws {
        let ws = try makeProject()
        try put((1...20).map { $0 == 5 || $0 == 15 ? "HIT \($0)" : "line \($0)" }.joined(separator: "\n") + "\n", "a.txt", in: ws)
        let out = await grep(["pattern": "HIT", "context": 1], in: ws, rg: engine(e))
        #expect(out.text == "a.txt-4- line 4\na.txt:5: HIT 5\na.txt-6- line 6\n--\na.txt-14- line 14\na.txt:15: HIT 15\na.txt-16- line 16",
                "\(e): \(out.text)")
        let after = await grep(["pattern": "HIT", "-A": 2, "glob": "a.txt"], in: ws, rg: engine(e))
        #expect(after.text.hasPrefix("a.txt:5: HIT 5\na.txt-6- line 6\na.txt-7- line 7\n--\na.txt:15:"), "\(e): \(after.text)")
        // Overlapping context merges into one group.
        let near = await grep(["pattern": "HIT", "context": 5], in: ws, rg: engine(e))
        #expect(!near.text.contains("--"), "\(e): \(near.text)")
    }

    @Test(arguments: engines) func filesModeAndTypeFilter(_ e: String) async throws {
        let ws = try makeProject(git: true)
        try put("def greet(): pass\n", "tools/greet.py", in: ws)
        let files = await grep(["pattern": "greet", "output_mode": "files_with_matches"], in: ws, rg: engine(e))
        #expect(files.text == "docs/guide.md\nsrc/main.swift\ntools/greet.py", "\(e): \(files.text)")
        let py = await grep(["pattern": "greet", "type": "python"], in: ws, rg: engine(e))
        #expect(py.text == "tools/greet.py:1: def greet(): pass", "\(e): \(py.text)")
        // The old parameter still works.
        let old = await grep(["pattern": "greet", "files_only": true], in: ws, rg: engine(e))
        #expect(old.text == files.text)
        // An unknown type is taken as an extension, and the result says so.
        try put("greet\n", "logs/app.log", in: ws)
        let log = await grep(["pattern": "greet", "type": "log"], in: ws, rg: engine(e))
        #expect(log.text == "logs/app.log:1: greet", "\(e): \(log.text)")
        let ext = await grep(["pattern": "greet", "type": "cobol"], in: ws, rg: engine(e))
        #expect(ext.text.hasPrefix("No matches") && ext.text.contains("isn't a known type; searched *.cobol files"))
        let bad = await grep(["pattern": "greet", "type": "*.{a,b}"], in: ws, rg: engine(e))
        #expect(bad.isError && bad.text.contains("unknown file type") && bad.text.contains("swift"))
    }

    @Test(arguments: engines) func paging(_ e: String) async throws {
        let ws = try makeProject()
        try put((1...30).map { "item \($0)" }.joined(separator: "\n") + "\n", "list.txt", in: ws)
        let first = await grep(["pattern": "item", "head_limit": 10], in: ws, rg: engine(e))
        #expect(first.truncated)
        #expect(first.text.hasSuffix("list.txt:10: item 10\n[Showing lines 1–10 of 30 (30 matching lines in 1 file). Use offset=10 for more, or narrow with glob, type or path.]"),
                "\(e): \(first.text)")
        let last = await grep(["pattern": "item", "head_limit": 10, "offset": 25], in: ws, rg: engine(e))
        #expect(last.text.hasPrefix("list.txt:26: item 26"))
        #expect(last.text.hasSuffix("[Showing lines 26–30 of 30 (30 matching lines in 1 file).]"), "\(e): \(last.text)")
        #expect(!last.truncated)
        let past = await grep(["pattern": "item", "offset": 99], in: ws, rg: engine(e))
        #expect(past.text.contains("past the end: there are 30 results"))
    }

    @Test(arguments: engines) func multilineMatchesSpanLines(_ e: String) async throws {
        let ws = try makeProject()
        try put("struct A {\n    let x: Int\n}\nstruct B {}\n", "m.swift", in: ws)
        let out = await grep(["pattern": "struct A \\{.*?\\}", "multiline": true], in: ws, rg: engine(e))
        #expect(out.text == "m.swift:1: struct A {\nm.swift:2:     let x: Int\nm.swift:3: }", "\(e): \(out.text)")
        let count = await grep(["pattern": "struct \\w+ \\{.*?\\}", "multiline": true, "output_mode": "count"], in: ws, rg: engine(e))
        #expect(count.text.hasSuffix("Total: 2 matches in 1 file."), "\(e): \(count.text)")
    }

    @Test(arguments: engines) func lookAroundAndBadPatterns(_ e: String) async throws {
        let ws = try makeProject()
        let look = await grep(["pattern": "(?<=func )greet", "glob": "*.swift"], in: ws, rg: engine(e))
        #expect(look.text == "src/main.swift:12: func greet() { print(\"Hello\") }", "\(e): \(look.text)")
        let bad = await grep(["pattern": "(unclosed"], in: ws, rg: engine(e))
        #expect(bad.isError && bad.text.contains("invalid regular expression"), "\(e): \(bad.text)")
    }

    @Test(arguments: engines) func binaryFilesAndCRLFLines(_ e: String) async throws {
        let ws = try makeProject()
        try Data("abc\0def greet\n".utf8).write(to: ws.root.appending(path: "blob.dat"))
        try put("greet windows\r\nnext\r\n", "win.txt", in: ws)
        let out = await grep(["pattern": "greet"], in: ws, rg: engine(e))
        #expect(!out.text.contains("blob.dat"), "\(e)")
        #expect(out.text.contains("win.txt:1: greet windows\n") || out.text.hasSuffix("win.txt:1: greet windows"), "\(e): \(out.text)")
    }

    @Test(arguments: engines) func withheldAndDeniedFilesNeverReachTheEngine(_ e: String) async throws {
        var ws = try makeProject(git: true)
        try put("API_KEY=sk-live-1\n", ".env", in: ws)
        try put("API_KEY=from-config\n", "config/app.txt", in: ws)
        ws.withheld = WithheldFiles(patterns: WithheldFiles.defaults, host: "api.example.com")
        let out = await grep(["pattern": "API_KEY", "output_mode": "count"], in: ws, rg: engine(e))
        #expect(!out.text.contains(".env"), "\(e): \(out.text)")
        #expect(out.text.contains("config/app.txt: 1"))
        #expect(out.text.contains("[1 file withheld from remote models weren't searched.]"))
    }

    @Test func bothEnginesAgreeOnTheProject() async throws {
        let ws = try makeProject(git: true)
        for args: [String: JSONValue] in [["pattern": "greet"], ["pattern": "GREET", "case_insensitive": true],
                                          ["pattern": "line \\d+", "output_mode": "count"], ["pattern": "^// line 1[0-9]$", "context": 2]] {
            let a = await grep(args, in: ws, rg: engine("rg")), b = await grep(args, in: ws, rg: nil)
            #expect(a.text == b.text, "\(args)")
        }
    }

    @Test func globListsNewestFirst() async throws {
        let ws = try makeProject()
        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: ws.root.appending(path: "src/main.swift").path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: ws.root.appending(path: "src/util/helpers.swift").path)
        let out = try await GlobTool().run(ToolArguments(["pattern": "*.swift"]), context: ToolContext(workspace: ws))
        #expect(out.text == "src/util/helpers.swift\nsrc/main.swift")
    }
}

@Suite struct Phase1ScenarioTests {
    @Test func warnCountChecksTheNumberNotTheTrap() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-warn-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let prompt = try Scenarios.warnCount.prepare(dir)
        #expect(prompt.contains("build.log"))
        let n = Fixtures.buildLogWarnings(dir)
        let text = try String(contentsOf: dir.appending(path: "build.log"), encoding: .utf8)
        let loose = text.components(separatedBy: "\n").filter { $0.contains("warning") }.count
        #expect(n > 300 && loose > n)
        func record(_ answer: String) -> RunRecord {
            var r = RunRecord()
            r.messages = [.user(prompt), ChatMessage(role: .assistant, content: answer)]
            return r
        }
        #expect(Scenarios.warnCount.check(dir, record("There are \(n) warnings.")).passed)
        #expect(!Scenarios.warnCount.check(dir, record("There are \(loose) warnings.")).passed)
        #expect(Scenarios.named(["phase1"]).map(\.id) == ["warn-count", "nested-rules"])
        #expect(Scenarios.named(["warn-count"]).count == 1)
    }
}

/// A history where the model read `path` (a read_file call and its result), then the user asks `then`.
func historyHavingRead(_ path: String, then request: String) -> [ChatMessage] {
    let call = ToolCall(id: "seed_read", name: "read_file", arguments: #"{"path":"\#(path)"}"#)
    return [.user("look first"), ChatMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatMessage(role: .tool, content: "(contents)", toolCallID: "seed_read",
                        toolResult: ToolResultInfo(toolName: "read_file", isError: false, truncated: false, duration: 0)),
            .user(request)]
}

// MARK: B5 edit tooling

private func tool(_ t: some Tool, _ args: [String: JSONValue], in ws: Workspace, reads: FileReads? = nil) async -> ToolOutput {
    var context = ToolContext(workspace: ws)
    context.reads = reads
    do { return try await t.run(ToolArguments(args), context: context) }
    catch let f as ToolFailure { return .error(f.message) }
    catch { return .error("\(error)") }
}

private func text(_ ws: Workspace, _ path: String) -> String {
    (try? String(contentsOf: ws.root.appending(path: path), encoding: .utf8)) ?? ""
}

@Suite struct EditB5Tests {
    @Test func severalEditsInOneCallAllOrNone() async throws {
        let ws = try makeProject()
        try put("a = 1\nb = 2\nc = 3\n", "v.py", in: ws)
        let ok = await tool(EditFileTool(), ["path": "v.py", "edits": [["old_string": "a = 1", "new_string": "a = 10"],
                                                                       ["old_string": "c = 3", "new_string": "c = 30"]]], in: ws)
        #expect(!ok.isError, "\(ok.text)")
        #expect(text(ws, "v.py") == "a = 10\nb = 2\nc = 30\n")
        #expect(ok.text.contains("2 replacements"))
        #expect(ok.text.contains("1\ta = 10") && ok.text.contains("3\tc = 30"))
        // The second edit fails: nothing is written.
        let bad = await tool(EditFileTool(), ["path": "v.py", "edits": [["old_string": "b = 2", "new_string": "b = 20"],
                                                                        ["old_string": "zzz", "new_string": "y"]]], in: ws)
        #expect(bad.isError && bad.text.contains("edit 2 of 2: ") && bad.text.contains("Nothing was changed."))
        #expect(text(ws, "v.py") == "a = 10\nb = 2\nc = 30\n")
        // Edits apply in order: the second sees the first's result. A JSON string of edits works too.
        let chained = await tool(EditFileTool(), ["file_path": "v.py",
                                                  "edits": #"[{"old_string":"b = 2","new_string":"b = 3"},{"old_string":"b = 3","new_string":"b = 4"}]"#], in: ws)
        #expect(!chained.isError, "\(chained.text)")
        #expect(text(ws, "v.py").contains("b = 4\n"))
        // The path inside the edits (Gemma 4 did this live), and affectedFiles agrees (it named the folder before).
        let inner = ToolArguments(["edits": [["path": "v.py", "old_string": "b = 4", "new_string": "b = 5"]], "replace_all": true])
        #expect(try EditFileTool().affectedFiles(inner, context: ToolContext(workspace: ws)).map(\.lastPathComponent) == ["v.py"])
        let placed = await tool(EditFileTool(), inner.values, in: ws)
        #expect(!placed.isError && text(ws, "v.py").contains("b = 5\n"), "\(placed.text)")
        let none = ToolArguments(["edits": [["old_string": "a", "new_string": "b"]]])
        #expect(throws: ToolFailure.self) { try EditFileTool().affectedFiles(none, context: ToolContext(workspace: ws)) }
        let twoFiles = await tool(EditFileTool(), ["edits": [["path": "v.py", "old_string": "a", "new_string": "b"],
                                                            ["path": "w.py", "old_string": "a", "new_string": "b"]]], in: ws)
        #expect(twoFiles.isError && twoFiles.text.contains("one file per call"))
        #expect(EditFileTool().summary(ToolArguments(["path": "v.py", "edits": [["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d"]]])) == "Edit v.py (2 changes)")
    }

    @Test func aLooseMatchIsUsedWhenItIsUnique() async throws {
        let ws = try makeProject()
        try put("def f():\n    if x:\n        return 1\n    return 2\n", "f.py", in: ws)
        // Indentation lost (the model wrote it flush left): matched, and the new text gets the file's indentation.
        let out = await tool(EditFileTool(), ["path": "f.py", "old_string": "if x:\n    return 1", "new_string": "if x:\n    return 10"], in: ws)
        #expect(!out.isError, "\(out.text)")
        #expect(text(ws, "f.py") == "def f():\n    if x:\n        return 10\n    return 2\n")
        #expect(out.text.contains("only after ignoring indentation and trailing whitespace") && out.text.contains("file's indentation"))
        // Trailing whitespace in the file.
        try put("x = 1   \ny = 2\n", "t.py", in: ws)
        let trail = await tool(EditFileTool(), ["path": "t.py", "old_string": "x = 1\ny = 2", "new_string": "x = 1\ny = 3"], in: ws)
        #expect(!trail.isError && text(ws, "t.py") == "x = 1\ny = 3\n", "\(trail.text)")
        #expect(trail.text.contains("ignoring trailing whitespace"))
        // Two loose places: refused, with where they are.
        try put("  a()\n  b\n    a()\n    b\n", "two.py", in: ws)
        let two = await tool(EditFileTool(), ["path": "two.py", "old_string": "a()\nb", "new_string": "c()\nb"], in: ws)
        #expect(two.isError && two.text.contains("matches 2 places (lines 1, 3)"), "\(two.text)")
        // CRLF files keep their line ends.
        try Data("if x:\r\n    go()\r\n".utf8).write(to: ws.root.appending(path: "w.py"))
        let crlf = await tool(EditFileTool(), ["path": "w.py", "old_string": "if x:\ngo()", "new_string": "if x:\nstop()"], in: ws)
        #expect(!crlf.isError, "\(crlf.text)")
        #expect(text(ws, "w.py") == "if x:\r\n    stop()\r\n")
    }

    @Test func editsNeedAReadAndAFreshOne() async throws {
        let ws = try makeProject()
        let reads = FileReads()
        let unread = await tool(EditFileTool(), ["path": "README.md", "old_string": "A demo", "new_string": "The demo"], in: ws, reads: reads)
        #expect(unread.isError && unread.text.contains("hasn't been read"))
        _ = await tool(ReadFileTool(), ["path": "README.md", "limit": 1], in: ws, reads: reads)     // a partial read counts
        let edited = await tool(EditFileTool(), ["path": "README.md", "old_string": "A demo", "new_string": "The demo"], in: ws, reads: reads)
        #expect(!edited.isError, "\(edited.text)")
        // Its own edit keeps the file fresh: a second edit needs no read.
        let again = await tool(EditFileTool(), ["path": "README.md", "old_string": "The demo", "new_string": "Our demo"], in: ws, reads: reads)
        #expect(!again.isError, "\(again.text)")
        // Changed by someone else: refused until read again.
        try await Task.sleep(for: .milliseconds(20))
        try put("# Demo\n\nChanged by the user.\n", "README.md", in: ws)
        let stale = await tool(EditFileTool(), ["path": "README.md", "old_string": "Changed", "new_string": "Edited"], in: ws, reads: reads)
        #expect(stale.isError && stale.text.contains("changed since you last read it"))
        // write_file: replacing an unread file is refused, creating or appending isn't.
        let over = await tool(WriteFileTool(), ["path": "docs/guide.md", "content": "new\n"], in: ws, reads: reads)
        #expect(over.isError && over.text.contains("hasn't been read"))
        #expect(!(await tool(WriteFileTool(), ["path": "docs/guide.md", "content": "more\n", "append": true], in: ws, reads: reads)).isError)
        #expect(!(await tool(WriteFileTool(), ["path": "docs/new.md", "content": "x\n"], in: ws, reads: reads)).isError)
    }

    @Test func theLogIsSeededFromTheHistory() async throws {
        let ws = try makeProject()
        let reads = FileReads.seeded(from: historyHavingRead("README.md", then: "go"), workspace: ws)
        #expect(reads.hasRead(ws.root.appending(path: "README.md")))
        #expect(!reads.hasRead(ws.root.appending(path: "docs/guide.md")))
        // A file changed after that read (its result's time) needs another.
        try await Task.sleep(for: .milliseconds(20))
        try put("# Demo\nnew\n", "README.md", in: ws)
        #expect(throws: ToolFailure.self) { try reads.check(ws.root.appending(path: "README.md"), path: "README.md") }
        // A failed read doesn't count.
        var h = historyHavingRead("docs/guide.md", then: "go")
        h[2].toolResult?.isError = true
        #expect(!FileReads.seeded(from: h, workspace: ws).hasRead(ws.root.appending(path: "docs/guide.md")))
    }

    @Test func theLoopRefusesAnUnreadEditAndTheModelRecovers() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("e1", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"A fixed project."}"#),
            SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#),
            SSE.toolCall("e2", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"A fixed project."}"#),
            SSE.content("done"),
        ]))
        let config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto))
        let results = Results()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("fix it")], config: config,
                            workspace: ws) { if case .toolFinished(let m) = $0 { results.add(m) } }
        #expect(results.all.map { $0.toolResult?.isError == true } == [true, false, false])
        #expect(text(ws, "README.md").contains("A fixed project."))
    }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ChatMessage] = []
    func add(_ m: ChatMessage) { lock.withLock { items.append(m) } }
    var all: [ChatMessage] { lock.withLock { items } }
}

@Suite struct ApplyPatchB5Tests {
    @Test func v4aUpdatesAddsDeletesAndMoves() async throws {
        let ws = try makeProject()
        try put("def a():\n    return 1\n\n\ndef b():\n    return 2\n", "m.py", in: ws)
        try put("old\n", "gone.txt", in: ws)
        try put("keep\n", "src/move.txt", in: ws)
        let patch = """
            *** Begin Patch
            *** Update File: m.py
            @@ def b():
            -    return 2
            +    return 20
            *** Add File: docs/new.md
            +# New
            +text
            *** Delete File: gone.txt
            *** Update File: src/move.txt
            *** Move to: src/moved.txt
            @@
            -keep
            +kept
            *** End Patch
            """
        let reads = FileReads()
        for p in ["m.py", "src/move.txt", "gone.txt"] { reads.record(ws.root.appending(path: p)) }
        let out = await tool(ApplyPatchTool(), ["patch": .string(patch)], in: ws, reads: reads)
        #expect(!out.isError, "\(out.text)")
        #expect(text(ws, "m.py") == "def a():\n    return 1\n\n\ndef b():\n    return 20\n")
        #expect(text(ws, "docs/new.md") == "# New\ntext\n")
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "gone.txt").path))
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "src/move.txt").path))
        #expect(text(ws, "src/moved.txt") == "kept\n")
        #expect(out.text.contains("Updated m.py (+1 −1).") && out.text.contains("Added docs/new.md (2 lines).") && out.text.contains("Deleted gone.txt."))
        #expect(out.display?.contains("+    return 20") == true)
    }

    @Test func unifiedDiffsAndLooseContext() async throws {
        let ws = try makeProject()
        try put("one\ntwo\nthree\nfour\n", "n.txt", in: ws)
        let diff = """
            --- a/n.txt
            +++ b/n.txt
            @@ -1,4 +1,4 @@
             one
            -two
            +2
             three
             four
            """
        let out = await tool(ApplyPatchTool(), ["patch": .string(diff)], in: ws)
        #expect(!out.isError, "\(out.text)")
        #expect(text(ws, "n.txt") == "one\n2\nthree\nfour\n")
        // Context with the wrong indentation still lands, with a note.
        try put("class A:\n    def f(self):\n        pass\n", "a.py", in: ws)
        let loose = "*** Begin Patch\n*** Update File: a.py\n def f(self):\n-    pass\n+    return 1\n*** End Patch"
        let lo = await tool(ApplyPatchTool(), ["patch": .string(loose)], in: ws)
        #expect(!lo.isError, "\(lo.text)")
        #expect(lo.text.contains("only after ignoring indentation"))
        #expect(text(ws, "a.py").contains("    return 1\n"))
    }

    @Test func aPatchThatDoesntApplyChangesNothing() async throws {
        let ws = try makeProject()
        try put("x\n", "ok.txt", in: ws)
        let patch = "*** Begin Patch\n*** Update File: ok.txt\n-x\n+y\n*** Update File: README.md\n-not in the file\n+z\n*** End Patch"
        let out = await tool(ApplyPatchTool(), ["patch": .string(patch)], in: ws)
        #expect(out.isError && out.text.contains("doesn't match the file") && out.text.contains("not in the file"))
        #expect(text(ws, "ok.txt") == "x\n")
        let unread = await tool(ApplyPatchTool(), ["patch": "*** Begin Patch\n*** Update File: ok.txt\n-x\n+y\n*** End Patch"], in: ws, reads: FileReads())
        #expect(unread.isError && unread.text.contains("hasn't been read"))
        let exists = await tool(ApplyPatchTool(), ["patch": "*** Begin Patch\n*** Add File: ok.txt\n+y\n*** End Patch"], in: ws)
        #expect(exists.isError && exists.text.contains("already exists"))
        let junk = await tool(ApplyPatchTool(), ["patch": "please change x to y"], in: ws)
        #expect(junk.isError && junk.text.contains("no file headers"))
        #expect(try ApplyPatchTool().affectedFiles(ToolArguments(["patch": "*** Begin Patch\n*** Update File: ok.txt\n*** Move to: b.txt\n*** End Patch"]),
                                                   context: ToolContext(workspace: ws)).map(\.lastPathComponent) == ["ok.txt", "b.txt"])
    }

    @Test func endPatchLinesBetweenSectionsAreTolerated() async throws {
        // gpt-oss-120b (OpenRouter, live) closed each file's section with its own "*** End Patch".
        let ws = try makeProject()
        try put("a\n", "one.txt", in: ws)
        try put("b\n", "two.txt", in: ws)
        let patch = "*** Begin Patch\n*** Update File: one.txt\n@@\n-a\n+A\n*** End Patch\n*** Update File: two.txt\n@@\n-b\n+B\n"
            + "*** End Patch\n*** Add File: three.txt\n+c\n*** End Patch\n*** End Patch"
        let out = await tool(ApplyPatchTool(), ["patch": .string(patch)], in: ws)
        #expect(!out.isError, "\(out.text)")
        #expect(text(ws, "one.txt") == "A\n" && text(ws, "two.txt") == "B\n" && text(ws, "three.txt") == "c\n")
    }

    @Test func offeredToGPTFamiliesByProfile() {
        let ep = UUID()
        #expect(ModelProfile.defaults(endpointID: ep, model: "openai/gpt-oss-120b").offersPatchTool)
        #expect(ModelProfile.defaults(endpointID: ep, model: "gpt-5.1-codex").offersPatchTool)
        #expect(ModelProfile.defaults(endpointID: ep, model: "openai/o4-mini").offersPatchTool)
        #expect(!ModelProfile.defaults(endpointID: ep, model: "google/gemma-4-26b-a4b-qat").offersPatchTool)
        var p = ModelProfile.defaults(endpointID: ep, model: "qwen/qwen3-coder-30b")
        p.patchTool = true
        #expect(p.offersPatchTool)
        // gpt-oss keeps its own history shape (its row comes after GPT's).
        #expect(ModelProfile.defaults(endpointID: ep, model: "openai/gpt-oss-120b").history.sendReasoning)
    }
}

@Suite struct EditRulesB5Tests {
    @Test func editRulesSeeEveryPathACallNames() throws {
        let root = URL(fileURLWithPath: "/tmp/kk-rules-proj")
        let rules = PermissionRules(rules: [
            PermissionRule(action: .deny, tool: "Edit", specifier: "secrets/**", source: "test"),
            PermissionRule(action: .allow, tool: "Edit", specifier: "src/**", source: "test"),
        ], root: root)
        func decide(_ tool: String, _ args: [String: JSONValue]) -> PermissionRule.Action? { rules.decision(toolName: tool, args: ToolArguments(args))?.action }
        #expect(decide("edit_file", ["path": "secrets/key.txt", "old_string": "a", "new_string": "b"]) == .deny)
        #expect(decide("edit_file", ["file_path": "secrets/key.txt", "old_string": "a", "new_string": "b"]) == .deny)
        #expect(decide("edit_file", ["edits": [["path": "secrets/key.txt", "old_string": "a", "new_string": "b"]]]) == .deny)
        let patch = { (paths: [String]) -> JSONValue in
            .string("*** Begin Patch\n" + paths.map { "*** Update File: \($0)\n-a\n+b\n" }.joined() + "*** End Patch") }
        #expect(decide("apply_patch", ["patch": patch(["src/a.swift", "secrets/key.txt"])]) == .deny)   // any path for deny
        #expect(decide("apply_patch", ["patch": patch(["src/a.swift", "src/b.swift"])]) == .allow)
        #expect(decide("apply_patch", ["patch": patch(["src/a.swift", "README.md"])]) == nil)           // all paths for allow
    }
}

// MARK: B2 background commands and shell env

private func bash(_ args: [String: JSONValue], in ws: Workspace, shell: ShellState, maxBytes: Int = 16_000) async -> ToolOutput {
    let context = ToolContext(workspace: ws, maxOutputBytes: maxBytes, shell: shell)
    do { return try await BashTool().run(ToolArguments(args), context: context) }
    catch let f as ToolFailure { return .error(f.message) }
    catch { return .error("\(error)") }
}

private func call(_ t: some Tool, _ args: [String: JSONValue], in ws: Workspace, shell: ShellState) async -> ToolOutput {
    do { return try await t.run(ToolArguments(args), context: ToolContext(workspace: ws, shell: shell)) }
    catch let f as ToolFailure { return .error(f.message) }
    catch { return .error("\(error)") }
}

@Suite struct ShellEnvB2Tests {
    @Test func exportedVariablesCarryOverAndUnsetsToo() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        let first = await bash(["command": "export KK_GREETING='it'\\''s here'; export KK_OTHER=2"], in: ws, shell: shell)
        #expect(first.text.contains("Exported for later commands: KK_GREETING, KK_OTHER."), "\(first.text)")
        let second = await bash(["command": "echo \"[$KK_GREETING] [$KK_OTHER]\""], in: ws, shell: shell)
        #expect(second.text.hasPrefix("[it's here] [2]"), "\(second.text)")
        #expect(!second.text.contains("Exported"))                     // nothing new
        let gone = await bash(["command": "unset KK_OTHER"], in: ws, shell: shell)
        #expect(gone.text.contains("Unset for later commands: KK_OTHER."))
        #expect(await bash(["command": "echo \"[${KK_OTHER:-none}]\""], in: ws, shell: shell).text.hasPrefix("[none]"))
        // A PATH a command set is kept as it was, not prepended to again by each login shell.
        _ = await bash(["command": "export PATH=\"$PWD/tools:$PATH\""], in: ws, shell: shell)
        let p1 = await bash(["command": "echo $PATH"], in: ws, shell: shell)
        let p2 = await bash(["command": "echo $PATH"], in: ws, shell: shell)
        #expect(p1.text.hasPrefix(ws.root.path + "/tools:") || p1.text.hasPrefix("/private" + ws.root.path + "/tools:"), "\(p1.text)")
        #expect(p1.text == p2.text)
        // A subagent's shell starts with them.
        let child = ShellState(cwd: ws.root, exported: shell.exported, unset: shell.unset)
        #expect(await bash(["command": "echo $KK_GREETING"], in: ws, shell: child).text.hasPrefix("it's here"))
    }

    @Test func aCommandThatExitsEarlyKeepsTheOldEnvironment() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        _ = await bash(["command": "export KK_A=1"], in: ws, shell: shell)
        let out = await bash(["command": "export KK_B=2; exit 3"], in: ws, shell: shell)
        #expect(out.exitCode == 3)
        #expect(shell.exported["KK_A"] == "1" && shell.exported["KK_B"] == nil)
    }
}

@Suite struct BackgroundB2Tests {
    @Test func startReadWaitAndFinish() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        // Sleeps long enough that the start's own short wait can't see the end, even on a loaded machine.
        let started = await bash(["command": "echo begin; sleep 6; echo middle; sleep 1; echo end", "run_in_background": true],
                                 in: ws, shell: shell)
        #expect(started.text.hasPrefix("Started in the background as bg1. Output so far:\nbegin"), "\(started.text)")
        #expect(started.text.contains("bash_output") && started.text.contains("kill_shell"))
        // Only what's new; then wait for the end.
        let none = await call(BashOutputTool(), ["id": "bg1"], in: ws, shell: shell)
        #expect(none.text.hasPrefix("(no new output)") && none.text.contains("bg1 (echo begin; sleep 6; echo middle; sleep 1; echo end): running"), "\(none.text)")
        let done = await call(BashOutputTool(), ["wait": 30], in: ws, shell: shell)       // the only job: no id needed
        #expect(done.text.hasPrefix("middle\nend"), "\(done.text)")
        #expect(done.text.contains("exited with code 0"))
        #expect(done.exitCode == 0)
        // Its file has the whole output.
        let file = try #require(shell.jobs.job("bg1")?.output)
        #expect(try String(contentsOf: file, encoding: .utf8) == "begin\nmiddle\nend\n")
    }

    @Test func killStopsTheGroupAndAQuickFailureIsReported() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        _ = await bash(["command": "sleep 300 & sleep 300; echo never", "run_in_background": true], in: ws, shell: shell)
        let pid = try #require(shell.jobs.job("bg1")?.pid)
        let killed = await call(KillShellTool(), ["id": "1"], in: ws, shell: shell)
        #expect(killed.text.hasPrefix("Stopped bg1"), "\(killed.text)")
        #expect(shell.jobs.job("bg1")?.isRunning == false)
        try await Task.sleep(for: .milliseconds(300))
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "pid,ppid,pgid,stat,comm", "-g", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try ps.run(); ps.waitUntilExit()
        #expect(kill(-pid, 0) != 0, "\(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")  // the whole group is gone
        #expect(await call(KillShellTool(), ["id": "bg1"], in: ws, shell: shell).text.contains("had already ended"))
        let bad = await bash(["command": "echo oops >&2; exit 4", "run_in_background": true], in: ws, shell: shell)
        #expect(bad.isError && bad.text.hasPrefix("It ended at once (bg2: exited with code 4") && bad.text.contains("oops"), "\(bad.text)")
        let which = await call(BashOutputTool(), [:], in: ws, shell: shell)
        #expect(which.isError && which.text.contains("which background command") && which.text.contains("bg1") && which.text.contains("bg2"))
        #expect(await call(BashOutputTool(), ["id": "bg9"], in: ws, shell: shell).text.contains("no background command"))
    }

    @Test func longNewOutputShowsItsEndAndHiddenErrors() async throws {
        let ws = try makeProject()
        let shell = ShellState(cwd: ws.root)
        _ = await bash(["command": "sleep 6; for i in $(seq 1 3000); do if [ $i = 40 ]; then echo \"FAIL: case $i\"; else echo \"ok $i\"; fi; done",
                        "run_in_background": true], in: ws, shell: shell)
        let out = await call(BashOutputTool(), ["id": "bg1", "wait": 40], in: ws, shell: shell)
        #expect(out.truncated)
        #expect(out.text.contains("ok 3000"))
        #expect(out.text.contains("line 40: FAIL: case 40"), "\(out.text.suffix(600))")
    }

    @Test func offeredWithBashOnly() async throws {
        let ws = try makeProject()
        for (mode, offered) in [(PermissionMode.fullAuto, true), (.ask, true)] {
            let (client, host) = MockServer.client(.init(turns: [SSE.content("hi")]))
            let config = AgentConfig(tools: PermissionPolicy(mode: mode).offered(AllTools.all), policy: PermissionPolicy(mode: mode))
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("hi")], config: config, workspace: ws) { _ in }
            let body = String(decoding: MockServer.requestBodies(host)[0], as: UTF8.self)
            #expect(body.contains("\"bash_output\"") == offered && body.contains("\"kill_shell\"") == offered, "\(mode)")
        }
    }
}

// MARK: B1 plan workflow

private final class PlanLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AgentEvent] = []
    private var _proposals: [PlanProposal] = []
    func add(_ e: AgentEvent) { lock.withLock { events.append(e) } }
    func proposed(_ p: PlanProposal) -> Int { lock.withLock { _proposals.append(p); return _proposals.count - 1 } }
    var proposals: [PlanProposal] { lock.withLock { _proposals } }
    var results: [ChatMessage] { lock.withLock { events.compactMap { if case .toolFinished(let m) = $0 { m } else { nil } } } }
    var modes: [PermissionMode] { lock.withLock { events.compactMap { if case .modeChanged(let m) = $0 { m } else { nil } } } }
    var stop: AgentStop? { lock.withLock { events.compactMap { if case .finished(let s) = $0 { s } else { nil } }.last } }
}

private func planRun(_ turns: [[Data]], ws: Workspace, decisions: [PlanDecision]) async -> (PlanLog, String) {
    let (client, host) = MockServer.client(.init(turns: turns))
    let log = PlanLog()
    var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan), approve: { _ in .deny(feedback: nil) })
    config.outputDirectory = ws.root.appending(path: ".outputs")
    config.presentPlan = { p in decisions[min(log.proposed(p), decisions.count - 1)] }
    await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("rename the greeting")], config: config,
                        workspace: ws) { log.add($0) }
    return (log, host)
}

private func toolNamesSent(_ host: String, _ i: Int) -> [String] {
    guard case .object(let o) = try? JSONDecoder().decode(JSONValue.self, from: MockServer.requestBodies(host)[i]),
          case .array(let tools) = o["tools"] else { return [] }
    return tools.compactMap { t in
        if case .object(let d) = t, case .object(let f) = d["function"], case .string(let n) = f["name"] { n } else { nil }
    }
}

@Suite struct PlanB1Tests {
    @Test func approvingSwitchesModeAndTheRunCarriesOn() async throws {
        let ws = try makeProject()
        let (log, host) = await planRun([
            SSE.toolCall("p1", "present_plan", ##"{"plan":"# Rename\n1. Change A demo project. to A renamed project. in README.md"}"##),
            SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#),
            SSE.toolCall("e1", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"A renamed project."}"#),
            SSE.content("Done."),
        ], ws: ws, decisions: [.approve(.acceptEdits)])
        #expect(log.stop == .completed)
        #expect(log.modes == [.acceptEdits])
        #expect(log.results[0].content.hasPrefix("The user approved the plan. You are now in Accept Edits mode"))
        #expect(log.results[0].toolResult?.notes?.contains("The user approved the plan: the mode is now Accept Edits.") == true)
        #expect(log.results[2].toolResult?.isError == false, "\(log.results[2].content)")      // the edit ran without asking
        #expect(try String(contentsOf: ws.root.appending(path: "README.md"), encoding: .utf8).contains("A renamed project."))
        // The plan was saved, and the tools stayed the same through the switch (CACHING_PLAN.md 1.2): the server reads the
        // whole session from its cache after the approval.
        let file = try #require(log.proposals.first?.file)
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("# Rename"))
        #expect(toolNamesSent(host, 0).contains("present_plan") && toolNamesSent(host, 0).contains("edit_file"))
        #expect(toolNamesSent(host, 1) == toolNamesSent(host, 0))
        #expect(MockServer.requestBodies(host).count == 4)
    }

    @Test func reviseKeepsPlanModeAndRejectStops() async throws {
        let ws = try makeProject()
        let (log, _) = await planRun([
            SSE.toolCall("p1", "present_plan", #"{"plan":"v1"}"#),
            SSE.toolCall("p2", "present_plan", #"{"plan":"v2"}"#),
            SSE.content("never"),
        ], ws: ws, decisions: [.revise("also update the docs"), .reject("not now")])
        #expect(log.results[0].content.contains("The user wants changes to the plan: also update the docs"))
        #expect(log.results[1].content.contains("The user rejected the plan: not now"))
        #expect(log.modes.isEmpty)
        #expect(log.stop == .denied)
        #expect(log.proposals.map(\.plan) == ["v1", "v2"])
    }

    @Test func notOfferedWithoutSomeoneToDecide() async throws {
        let ws = try makeProject()
        // Offered in every mode when someone can decide, so the tool list doesn't change with the mode (1.2).
        for (mode, presenter, offered) in [(PermissionMode.plan, false, false), (.acceptEdits, true, true), (.plan, true, true)] {
            let (client, host) = MockServer.client(.init(turns: [SSE.content("hi")]))
            var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: mode))
            if presenter { config.presentPlan = { _ in .reject(nil) } }
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("hi")], config: config, workspace: ws) { _ in }
            #expect(toolNamesSent(host, 0).contains("present_plan") == offered, "\(mode) \(presenter)")
        }
    }

    @Test func presentingAPlanOutsidePlanModeIsRefused() async throws {
        let ws = try makeProject()
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("p1", "present_plan", #"{"plan":"v1"}"#), SSE.content("ok")]))
        var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .acceptEdits))
        final class Asked: @unchecked Sendable { var n = 0 }
        let asked = Asked()
        config.presentPlan = { _ in asked.n += 1; return .reject(nil) }
        final class Results: @unchecked Sendable { var list: [ChatMessage] = []; let lock = NSLock() }
        let results = Results()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("hi")], config: config, workspace: ws) { e in
            if case .toolFinished(let m) = e { results.lock.withLock { results.list.append(m) } }
        }
        #expect(asked.n == 0)
        #expect(results.list.first?.content.contains("you're not in plan mode") == true)
    }

    @Test func planModeRunsReadOnlyCommandsOnly() async throws {
        let ws = try makeProject(git: true)
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("b1", "bash", #"{"command":"git status --short && ls src | head -5"}"#),
            SSE.toolCall("b2", "bash", #"{"command":"touch made.txt"}"#),
            SSE.toolCall("b3", "bash", #"{"command":"echo hi > made.txt"}"#),
            SSE.content("planned"),
        ]))
        let log = PlanLog()
        let config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .plan))
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("look")], config: config,
                            workspace: ws) { log.add($0) }
        #expect(log.results[0].toolResult?.isError == false && log.results[0].content.contains("main.swift"), "\(log.results[0].content)")
        #expect(log.results[1].content.contains("plan mode runs only commands that read"))
        #expect(log.results[2].content.contains("plan mode runs only commands that read"))
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "made.txt").path))
    }

    @Test func thePlanSandboxBlocksWritesInTheProject() async throws {
        guard SandboxPolicy.isAvailable else { return }
        let ws = try makeProject()
        var context = ToolContext(workspace: ws)
        context.sandbox = AgentLoop.planSandbox(ws, nil)
        let out = try await BashTool().run(ToolArguments(["command": "touch inside.txt; echo done"]), context: context)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "inside.txt").path), "\(out.text)")
        #expect(out.text.contains("done"))           // temp files (the shell's environment notes) still work
    }

    @Test func readOnlyCommands() {
        for c in ["git log --oneline -20", "git -C sub diff HEAD~1 -- a.swift", "git blame -L 10,20 x.py", "git status",
                  "git show HEAD:README.md | head -40", "ls -la src && cat README.md", "grep -rn TODO . | wc -l",
                  "rg -n 'fn main' --type rust", "find . -name '*.swift' -newer Package.swift", "sed -n '10,40p' a.py",
                  "git branch -a", "git stash list", "python3 --version", "git config --get user.name", "cd src && ls 2>/dev/null"] {
            #expect(PermissionPolicy.readOnly(c), "\(c)")
        }
        for c in ["git commit -m x", "git checkout main", "git branch -D old", "git -c alias.x='!rm -rf /' x", "rm a",
                  "find . -name '*.o' -delete", "find . -exec rm {} \\;", "sed -i '' 's/a/b/' f", "ls > files.txt",
                  "cat a | tee b", "swift build", "npm test", "git diff --output=patch.txt", "python3 script.py",
                  "echo $(rm -rf x)", "git push", "sort -o out.txt in.txt", "sed -n 'w out.txt' f"] {
            #expect(!PermissionPolicy.readOnly(c), "\(c)")
        }
    }

    @Test func decisionsFromTypedText() {
        #expect(PlanDecision.parse("1") == .approve(.acceptEdits))
        #expect(PlanDecision.parse("2") == .approve(.fullAuto))
        #expect(PlanDecision.parse("3") == .revise(""))
        #expect(PlanDecision.parse("3 also the docs") == .revise("also the docs"))
        #expect(PlanDecision.parse("4") == .reject(nil))
        #expect(PlanDecision.parse("reject too risky") == .reject("too risky"))
        #expect(PlanDecision.parse("use a struct instead") == .revise("use a struct instead"))
        #expect(PlanDecision.parse("  ") == nil)
    }

    @Test func aFencedPlanIsUnwrapped() {
        #expect(PlanProposal(plan: "```markdown\n# Plan\n- a\n```\n\nOnce you approve it, I'll start.").plan == "# Plan\n- a\n\nOnce you approve it, I'll start.")
        #expect(PlanProposal(plan: "# Plan\n```swift\nlet x = 1\n```").plan == "# Plan\n```swift\nlet x = 1\n```")   // code stays code
    }
}

@Suite struct PlanFallbackB1Tests {
    @Test func aPlanWrittenAsAnAnswerGoesToTheUserAnyway() async throws {
        let ws = try makeProject()
        let plan = "# Plan: rename\n\n1. Read README.md\n2. Change the title line\n3. Check it with cat README.md\n\nThat's all it needs, nothing else changes."
        let (log, host) = await planRun([
            SSE.content(plan),
            SSE.toolCall("r1", "read_file", #"{"path":"README.md"}"#),
            SSE.toolCall("e1", "edit_file", #"{"path":"README.md","old_string":"A demo project.","new_string":"A renamed project."}"#),
            SSE.content("Done."),
        ], ws: ws, decisions: [.approve(.acceptEdits)])
        #expect(log.proposals.map(\.plan) == [plan])
        #expect(log.modes == [.acceptEdits])
        #expect(log.stop == .completed)
        #expect(try String(contentsOf: ws.root.appending(path: "README.md"), encoding: .utf8).contains("A renamed project."))
        // The decision went back as the user's message, and the tools changed for the next request.
        let second = String(decoding: MockServer.requestBodies(host)[1], as: UTF8.self)
        #expect(second.contains("I approve this plan. You are now in Accept Edits mode"))
        #expect(toolNamesSent(host, 1).contains("edit_file"))
    }

    @Test func aShortAnswerIsntTakenForAPlan() async throws {
        let ws = try makeProject()
        let (log, _) = await planRun([SSE.content("The title is \"Demo\"; it's on line 1 of README.md.")], ws: ws, decisions: [.reject(nil)])
        #expect(log.proposals.isEmpty)
        #expect(log.stop == .completed)
        #expect(AgentLoop.looksLikePlan("## Approach\n1. Use a dictionary keyed by path, filled once at start-up.\n2. Look up each request in it; clear it when the config changes."))
        // A heading with prose and no steps, or steps with no heading, isn't one (Round 5, R5-19).
        #expect(!AgentLoop.looksLikePlan("## Approach\nUse a dictionary keyed by path, filled once at start-up, and look up each request in it; the cache is cleared when the config file changes on disk."))
        #expect(!AgentLoop.looksLikePlan("Line 12 of main.swift defines greet(); it prints Hello. Nothing else in the project calls it, so removing it is safe if you want to."))
    }
}

// MARK: B6 instruction files and memory

private func tree(_ files: [String: String]) throws -> URL {
    let base = FileManager.default.temporaryDirectory.appending(path: "kk-b6-\(UUID().uuidString.prefix(8))")
    for (path, text) in files {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    return base
}

@Suite struct InstructionsB6Tests {
    @Test func userParentProjectAndLocalFilesInOrderWithImportsAndDedupe() throws {
        let home = try tree([
            ".kurtkode/AGENTS.md": "kurtkode personal\n",
            ".claude/CLAUDE.md": "claude personal\n",
            ".claude/extra.md": "extra from home\n",
            "work/mono/AGENTS.md": "monorepo rules\n",
            "work/mono/app/AGENTS.md": "app rules\nSee @docs/style.md and @~/.claude/extra.md.\n`@not/an/import.md` and @missing.md\n```\n@docs/fenced.md\n```\n",
            "work/mono/app/CLAUDE.md": "app rules\nSee @docs/style.md and @~/.claude/extra.md.\n`@not/an/import.md` and @missing.md\n```\n@docs/fenced.md\n```\n",
            "work/mono/app/CLAUDE.local.md": "my local notes\n",
            "work/mono/app/docs/style.md": "style guide; also @deeper.md\n",
            "work/mono/app/docs/deeper.md": "deeper\n",
            "work/mono/app/docs/fenced.md": "should not load\n",
        ])
        let root = home.appending(path: "work/mono/app")
        try Memory.remember("use pnpm, not npm", root: root, home: home)
        let files = InstructionFiles(root: root, home: home).load()
        let labels = files.map(\.label)
        #expect(labels.map { $0.components(separatedBy: " (").first! } == [
            "~/.kurtkode/AGENTS.md", "~/.claude/CLAUDE.md", "~/work/AGENTS.md", "~/work/mono/AGENTS.md", "AGENTS.md",
            "docs/style.md", "docs/deeper.md", "~/.claude/extra.md", "CLAUDE.local.md", "memory",
        ].filter { $0 != "~/work/AGENTS.md" }, "\(labels)")
        #expect(labels.contains { $0.hasPrefix("AGENTS.md (project instructions), the same as CLAUDE.md") })
        #expect(labels.contains("docs/style.md (imported by AGENTS.md)"))
        #expect(labels.contains("docs/deeper.md (imported by docs/style.md)"))
        #expect(!files.contains { $0.text.contains("should not load") })
        #expect(files.last?.text.contains("- use pnpm, not npm (") == true)
        // The eval's way: only ~/.kurtkode/AGENTS.md's stand-in and the project's own files.
        var plain = InstructionFiles(root: root, home: home, global: home.appending(path: ".none"))
        plain.userFiles = false
        #expect(plain.load().map { $0.label.components(separatedBy: " (").first! } == ["AGENTS.md", "docs/style.md", "docs/deeper.md", "~/.claude/extra.md"])
    }

    @Test func subfolderFilesGoWithTheFirstResultThatTouchesThem() async throws {
        let ws = try makeProject()
        try put("pkg rules\n", "pkg/AGENTS.md", in: ws)
        try put("sub rules\n", "pkg/sub/CLAUDE.md", in: ws)
        try put("let x = 1\n", "pkg/sub/x.swift", in: ws)
        let nested = NestedInstructions(root: ws.root, history: [])
        let call = ToolCall(id: "1", name: "read_file", arguments: #"{"path":"pkg/sub/x.swift"}"#)
        let note = try #require(nested.take(for: call, workspace: ws)?.text)
        #expect(note.hasPrefix("[kurtkode: instructions from pkg/AGENTS.md, which apply to files under pkg/:]\npkg rules"))
        #expect(note.contains("[kurtkode: instructions from pkg/sub/CLAUDE.md, which apply to files under pkg/sub/:]\nsub rules"))
        #expect(!note.contains("haiku"))                                              // the root's AGENTS.md is in the prompt
        #expect(nested.take(for: call, workspace: ws) == nil)                         // once
        #expect(nested.take(for: ToolCall(id: "2", name: "grep", arguments: #"{"pattern":"x","path":"pkg"}"#), workspace: ws) == nil)
        // A history that already has them (as their own message): not again. Quoted in a tool result: that isn't sending.
        #expect(NestedInstructions(root: ws.root, history: [.user(note)]).take(for: call, workspace: ws) == nil)
        #expect(NestedInstructions(root: ws.root, history: [ChatMessage(role: .tool, content: note, toolCallID: "1")])
            .take(for: call, workspace: ws) != nil)
        // In the loop: a message after the read's result.
        let (client, _) = MockServer.client(.init(turns: [SSE.toolCall("r1", "read_file", #"{"path":"pkg/sub/x.swift"}"#), SSE.content("ok")]))
        let injected = Results()
        await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("look")],
                            config: AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .fullAuto)), workspace: ws) {
            if case .injected(let m) = $0 { injected.add(m) }
        }
        #expect(injected.all.first?.content.hasPrefix("[kurtkode: instructions from pkg/AGENTS.md") == true)
    }

    @Test func memoryRememberNotesAndListing() async throws {
        let home = try tree([:])
        let ws = try makeProject()
        #expect(Memory.listing(root: ws.root, home: home).hasPrefix("No memory for this project yet."))
        var context = ToolContext(workspace: ws)
        context.memoryHome = home
        let out = try await RememberTool().run(ToolArguments(["memory": "tests run with\nswift test --disable-sandbox"]), context: context)
        #expect(out.text.hasPrefix("Saved to this project's memory"))
        try Memory.remember("the user prefers tabs", root: ws.root, home: home)
        let text = try #require(Memory.text(root: ws.root, home: home))
        #expect(text.hasPrefix("# Memory for "))
        #expect(text.contains("- tests run with swift test --disable-sandbox (") && text.contains("- the user prefers tabs ("))
        #expect(Memory.listing(root: ws.root, home: home).contains("the user prefers tabs"))
        #expect(Memory.note(in: "# always run make lint") == "always run make lint")
        #expect(Memory.note(in: "# Title\nand a body") == nil)
        #expect(Memory.note(in: "#hashtag") == nil)
        // Offered only when the run has somewhere to keep it.
        for (home, offered) in [(home, true), (nil, false)] as [(URL?, Bool)] {
            let (client, host) = MockServer.client(.init(turns: [SSE.content("hi")]))
            var config = AgentConfig(tools: AllTools.all, policy: PermissionPolicy(mode: .ask))
            config.memoryHome = home
            await AgentLoop.run(client: client, model: "m", systemPrompt: "S", history: [.user("hi")], config: config, workspace: ws) { _ in }
            #expect(toolNamesSent(host, 0).contains("remember") == offered)
        }
    }
}

@Suite struct NestedRulesScenarioTests {
    @Test func checksTheDocstringPrefix() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-nested-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try Scenarios.nestedRules.prepare(dir)
        let file = dir.appending(path: "pkg/mathutil.py")
        try Data("def add(a, b):\n    return a + b\n\ndef double(x):\n    \"\"\"ZEBRA: twice x.\"\"\"\n    return 2 * x\n".utf8).write(to: file)
        #expect(Scenarios.nestedRules.check(dir, RunRecord()).passed)
        try Data("def add(a, b):\n    return a + b\n\ndef double(x):\n    \"\"\"Twice x.\"\"\"\n    return 2 * x\n".utf8).write(to: file)
        #expect(!Scenarios.nestedRules.check(dir, RunRecord()).passed)
    }
}

// MARK: B7 compaction summary

@Suite struct CompactionB7Tests {
    @Test func theTemplateHasItsSectionsAndALengthForTheContext() {
        let t = Compactor.summaryInstruction(words: 550)
        for section in ["### Requests", "### Done", "### Current step", "### Decisions and constraints", "### Errors and fixes",
                        "### Tests and checks", "### Next step"] { #expect(t.contains(section), "\(section)") }
        #expect(t.contains("under 550 words") && t.contains("word for word") && t.contains(###"line "## Summary""###))
        #expect(Compactor.summaryWords(limit: 16_384) == 400 && Compactor.summaryWords(limit: 32_768) == 550)
        #expect(Compactor.summaryWords(limit: 200_000) == 900 && Compactor.summaryWords(limit: nil) == 400)
        #expect(Compactor.summaryReserveBytes(words: 400) == 2600)
    }

    @Test func checkCommands() {
        for c in ["python3 -m pytest -q tests", "swift test --filter Foo 2>&1 | tail -30", "npm run build", "npm test", "make",
                  "make -j4 all", "python3 test_wordcount.py", "set -o pipefail; ./build.sh 2>&1 | tee build.log",
                  "cd pkg && cargo test", "go vet ./...", "xcodebuild -scheme App build", "bash ci.sh", "ruff check .",
                  "timeout 300 pytest -x", "pnpm run typecheck"] {
            #expect(SessionFacts.isCheck(c), "\(c)")
        }
        for c in ["cat test_x.py", "ls tests", "git commit -m 'fix build'", "echo make", "grep -rn test .", "python3 script.py",
                  "vim build.sh", "open ./build"] {
            #expect(!SessionFacts.isCheck(c), "\(c)")
        }
    }

    @Test func pathsAreNormalized() {
        let root = "/Users/k/proj"
        #expect(SessionFacts.normalize("./src/a.swift", root: root) == "src/a.swift")
        #expect(SessionFacts.normalize("/Users/k/proj/src/a.swift", root: root) == "src/a.swift")
        #expect(SessionFacts.normalize("src/../src/./a.swift", root: root) == "src/a.swift")
        #expect(SessionFacts.normalize("/Users/k/other/b.md", root: root) == "/Users/k/other/b.md")
        #expect(SessionFacts.normalize("src//a.swift", root: nil) == "src/a.swift")
    }

    @Test func factsKeepTheLastCheckAndNormalizedPaths() {
        func turn(_ id: String, _ name: String, _ args: String, result: String, error: Bool = false, exit: Int32? = nil) -> [ChatMessage] {
            var info = ToolResultInfo(toolName: name, isError: error, truncated: false, duration: 0)
            info.exitCode = exit
            return [ChatMessage(role: .assistant, content: "", toolCalls: [ToolCall(id: id, name: name, arguments: args)]),
                    ChatMessage(role: .tool, content: result, toolCallID: id, toolResult: info)]
        }
        var messages: [ChatMessage] = [.user("go")]
        messages += turn("1", "read_file", #"{"path":"./src/a.swift"}"#, result: "1\tx")
        messages += turn("2", "read_file", #"{"path":"/Users/k/proj/src/a.swift"}"#, result: "1\tx")
        messages += turn("3", "edit_file", #"{"edits":[{"path":"src/a.swift","old_string":"x","new_string":"y"}]}"#, result: "Edited")
        messages += turn("4", "apply_patch", #"{"patch":"*** Begin Patch\n*** Update File: src/b.swift\n-a\n+b\n*** End Patch"}"#, result: "Updated")
        messages += turn("5", "bash", #"{"command":"swift test 2>&1 | tail -20"}"#, result: "2 failed\n\n[Exit code 1.]", exit: 1)
        messages += turn("6", "bash", #"{"command":"git status"}"#, result: "clean", exit: 0)
        messages += turn("7", "bash", #"{"command":"npm run build","run_in_background":true}"#, result: "Started", exit: nil)
        var facts = SessionFacts()
        facts.absorb(messages, root: "/Users/k/proj")
        #expect(facts.filesRead == ["src/a.swift"])
        #expect(facts.changeOrder == ["src/a.swift", "src/b.swift"])
        #expect(facts.lastCheck == SessionFacts.Check(command: "swift test 2>&1 | tail -20", exitCode: 1))
        #expect(facts.rendered().contains("Last test or build command: `swift test 2>&1 | tail -20` → exit 1 (failed)"))
        // A timeout.
        var later = facts
        later.absorb(turn("8", "bash", #"{"command":"make"}"#, result: "…\n\n[Timed out after 120 seconds; …]", error: true), root: "/Users/k/proj")
        #expect(later.rendered().contains("`make` → timed out"))
        // Facts saved before B7 still decode.
        let old = #"{"filesRead":["a"],"filesChanged":{},"changeOrder":[],"todos":[]}"#
        #expect((try? JSONDecoder().decode(SessionFacts.self, from: Data(old.utf8)))?.filesRead == ["a"])
    }
}
