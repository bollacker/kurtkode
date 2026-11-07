import Foundation
import Testing
@testable import AgentCore

// Bug hunt 2026-11-02, item 39: bash_output, grep and diffs that held whole outputs or files in memory.

private func scratch(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-bh-mem-\(tag)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A background job that writes `bytes` of numbered lines and ends.
private func chattyJob(_ jobs: BackgroundCommands, bytes: Int, in dir: URL) async throws -> BackgroundCommands.Job {
    let script = "i=0; while [ $i -lt \(bytes / 50) ]; do printf 'line %08d of a chatty server writing its log......\\n' $i; i=$((i+1)); done"
    let job = try jobs.start(["/bin/sh", "-c", script], command: "chatty", cwd: dir.path, environment: ["PATH": "/usr/bin:/bin"],
                             output: dir.appending(path: "out.log"))
    _ = await jobs.wait(job.id, seconds: 60)
    return try #require(jobs.job(job.id))
}

@Suite(.serialized) struct BugHuntToolsMemoryTests {
    @Test func bashOutputReadsOnlyAWindowFromTheEnd() async throws {
        let dir = try scratch("window")
        defer { try? FileManager.default.removeItem(at: dir) }
        let jobs = BackgroundCommands()
        jobs.readWindow = 20_000
        let job = try await chattyJob(jobs, bytes: 400_000, in: dir)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: job.output.path)[.size] as? Int)
        #expect(size > 300_000)
        let (shown, skipped, all) = jobs.takeNew(job.id, max: 2000)
        #expect(all.utf8.count <= 20_000)
        #expect(shown.utf8.count <= 2000)
        #expect(shown.hasSuffix("......\n"))
        #expect(skipped + shown.utf8.count == size)                   // everything not shown is counted as skipped
        let again = jobs.takeNew(job.id, max: 2000)
        #expect(again.shown.isEmpty && again.skipped == 0)
    }

    @Test func aLongOutputFileIsCutToItsEnd() async throws {
        let dir = try scratch("trim")
        defer { try? FileManager.default.removeItem(at: dir) }
        let jobs = BackgroundCommands()
        jobs.trimAbove = 100_000
        jobs.keepBytes = 30_000
        let job = try await chattyJob(jobs, bytes: 200_000, in: dir)
        let lastLine = try String(contentsOf: job.output, encoding: .utf8).split(separator: "\n").last.map(String.init)
        jobs.trim(job.id)
        let text = try String(contentsOf: job.output, encoding: .utf8)
        #expect(text.utf8.count < 31_000)
        #expect(text.hasPrefix("[kurtkode cut the first "))
        #expect(text.split(separator: "\n").last.map(String.init) == lastLine)
        let (shown, _, _) = jobs.takeNew(job.id, max: 1000)
        #expect(shown.split(separator: "\n").last.map(String.init) == lastLine)
    }

    @Test func grepKeepsAPageOfLinesAndCountsTheRest() async throws {
        let dir = try scratch("grep")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(root: dir)
        let text = (1...20_000).map { "match \($0)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: dir.appending(path: "a.txt"))
        try Data(text.utf8).write(to: dir.appending(path: "b.txt"))
        for rg in [Ripgrep.locate([:]), nil] {
            let (hits, complete) = try await GrepEngine.search(["b.txt", "a.txt"], root: dir, query: GrepQuery(pattern: "match"),
                                                               rg: rg, keepLines: 30)
            #expect(complete)
            #expect(hits.map(\.path) == ["a.txt", "b.txt"])
            #expect(hits.reduce(0) { $0 + $1.lines.count } == 30)        // only the page, from the first file in path order
            #expect(hits[0].lines.first?.text == "match 1")
            #expect(hits.reduce(0) { $0 + $1.omittedLines } == 39_970)
            #expect(hits.reduce(0) { $0 + $1.count } == 40_000)
            let out = try await GrepTool(rg: rg).run(ToolArguments(["pattern": "match", "head_limit": 5, "offset": 20_001]),
                                                    context: ToolContext(workspace: ws))
            #expect(out.text.hasPrefix("b.txt:2: match 2\n"))
            #expect(out.text.contains("[Showing lines 20002–20006 of 40000 (40000 matching lines in 2 files). Use offset=20006"))
        }
    }

    @Test func grepStopsReadingRipgrepPastItsLimit() async throws {
        let rg = try #require(Ripgrep.locate([:]))
        let dir = try scratch("grepcap")
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = (1...20_000).map { "match \($0)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: dir.appending(path: "a.txt"))
        let (hits, complete) = try await GrepEngine.search(["a.txt"], root: dir, query: GrepQuery(pattern: "match"), rg: rg,
                                                           keepLines: 10, jsonLimit: 100_000)
        #expect(!complete)
        #expect(hits.first?.lines.count == 10)
        #expect((hits.first?.count ?? 0) < 20_000)
    }

    @Test func aLargeRewriteIsSummarizedPromptly() async throws {
        let old = (1...40_000).map { "old line \($0)" }.joined(separator: "\n") + "\n"
        let new = (1...40_000).map { "new line \($0)" }.joined(separator: "\n") + "\n"
        let started = Date()
        let c = LineDiff.compare(old: old, new: new)
        #expect(c.ops == nil)
        #expect(LineDiff.unified(c, path: "big.txt").contains("File rewritten: 40000 lines → 40000 lines"))
        #expect(LineDiff.stats(c) == (40_000, 40_000))
        #expect(LineDiff.changedRegions(c).isEmpty)
        #expect(Date().timeIntervalSince(started) < 5)

        // One changed line in a big file is still a real diff: the common start and end aren't diffed.
        let edited = old.replacingOccurrences(of: "old line 20000\n", with: "edited line\n")
        let small = LineDiff.unified(old: old, new: edited, path: "big.txt")
        #expect(small.contains("-old line 20000\n+edited line\n"))
        #expect(small.contains("@@ -19997,7 +19997,7 @@"))

        // Through write_file: it returns with the summary.
        let dir = try scratch("diff")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(old.utf8).write(to: dir.appending(path: "big.txt"))
        let out = try await WriteFileTool().run(ToolArguments(["path": "big.txt", "content": .string(new)]),
                                                context: ToolContext(workspace: Workspace(root: dir)))
        #expect(out.text.contains("+40000 −40000"))
        #expect(out.display?.contains("File rewritten") == true)
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
