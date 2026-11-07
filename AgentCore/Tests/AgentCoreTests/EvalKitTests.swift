import AgentCore
@testable import EvalKit
import Foundation
import Testing

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "kk-evaltest-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func run(reading paths: [String], final: String, compactions: Int = 0) -> RunRecord {
    var r = RunRecord()
    let calls = paths.enumerated().map { ToolCall(id: "c\($0.offset)", name: "read_file", arguments: #"{"path":"\#($0.element)"}"#) }
    r.messages = [ChatMessage(role: .assistant, content: "", toolCalls: calls), ChatMessage(role: .assistant, content: final)]
    r.compactions = (0..<compactions).map { _ in Compaction(summary: "s", lastSummarizedID: UUID(), continuation: nil, tokensBefore: 2, tokensAfter: 1) }
    return r
}

@Suite struct EvalKitTests {
    @Test func fixTestsCheckNeedsPassingTestsAndOnlyCalcChanged() throws {
        let dir = try tempDir()
        _ = try Scenarios.fixTests.prepare(dir)
        #expect(!Scenarios.fixTests.check(dir, RunRecord()).passed)          // untouched: tests fail
        var calc = try String(contentsOf: dir.appending(path: "calc.py"), encoding: .utf8)
        calc = calc.replacingOccurrences(of: "def sub(a, b):\n    return a + b", with: "def sub(a, b):\n    return a - b")
            .replacingOccurrences(of: "(len(values) - 1)", with: "len(values)")
        try Data(calc.utf8).write(to: dir.appending(path: "calc.py"))
        #expect(Scenarios.fixTests.check(dir, RunRecord()).passed)
        // Editing the tests to pass is not a fix.
        try Data("print('x')\n".utf8).write(to: dir.appending(path: "test_calc.py"))
        #expect(!Scenarios.fixTests.check(dir, RunRecord()).passed)
    }

    @Test func findDefinitionCheckComputesTheRealLine() throws {
        let dir = try tempDir()
        _ = try Scenarios.findDefinition.prepare(dir)
        let src = try String(contentsOf: dir.appending(path: "inventory/storage.py"), encoding: .utf8)
        let line = (src.components(separatedBy: "\n").firstIndex { $0.contains("def reserve_stock") } ?? 0) + 1
        let good = run(reading: ["inventory/storage.py"], final: "It's at inventory/storage.py:\(line). It raises InsufficientStock.")
        #expect(Scenarios.findDefinition.check(dir, good).passed)
        let prose = run(reading: ["inventory/storage.py"], final: "It is defined in `inventory/storage.py` at line \(line). It raises InsufficientStock.")
        #expect(Scenarios.findDefinition.check(dir, prose).passed)
        let wrongLine = run(reading: [], final: "inventory/storage.py:\(line + 9), raises InsufficientStock")
        #expect(!Scenarios.findDefinition.check(dir, wrongLine).passed)
    }

    @Test func longDocCheckCatchesGuessesAndInventions() throws {
        let dir = try tempDir()
        _ = try Scenarios.longDoc.prepare(dir)
        let expected = try Fixtures.documentation(at: try tempDir(), count: Scenarios.longDocCount, seed: 42)
        #expect(Set(expected.values).count == Scenarios.longDocCount)       // unique, unguessable names
        let good = expected.sorted { $0.key < $1.key }.map { "`\($0.key)` — `\($0.value)` — a part." }.joined(separator: "\n")
        try Data(good.utf8).write(to: dir.appending(path: "FILES.md"))
        #expect(Scenarios.longDoc.check(dir, run(reading: Array(expected.keys), final: "done", compactions: 2)).passed)
        #expect(!Scenarios.longDoc.check(dir, run(reading: Array(expected.keys), final: "done", compactions: 0)).passed)
        // Guessing class names from file names fails.
        let guessed = expected.keys.sorted().map { "`\($0)` — `Part` — a part." }.joined(separator: "\n")
        try Data(guessed.utf8).write(to: dir.appending(path: "FILES.md"))
        #expect(!Scenarios.longDoc.check(dir, run(reading: [], final: "done", compactions: 2)).passed)
        // A line for a file that doesn't exist fails even if the rest is right.
        try Data((good + "\n`src/part99.py` — `Ghost` — made up.").utf8).write(to: dir.appending(path: "FILES.md"))
        let r = Scenarios.longDoc.check(dir, run(reading: Array(expected.keys), final: "done", compactions: 2))
        #expect(!r.passed)
        #expect(r.notes.contains { $0.contains("part99") })
    }

    @Test func explainRepoWantsSpecificsAndReading() throws {
        let dir = try tempDir()
        _ = try Scenarios.explainRepo.prepare(dir)
        let text = "models.py defines Item; storage.py has SqliteStore and InsufficientStock; pricing adds tax; "
            + "api.py exposes HTTP handlers; cli.py is the command line; tests cover storage."
        #expect(Scenarios.explainRepo.check(dir, run(reading: ["a", "b", "c"], final: text)).passed)
        #expect(!Scenarios.explainRepo.check(dir, run(reading: [], final: text)).passed)        // didn't read anything
        #expect(!Scenarios.explainRepo.check(dir, run(reading: ["a", "b", "c"], final: "It's a Python project.")).passed)
    }

    @Test func denyFeedbackApprovalDeniesOnlyCalcEdits() {
        func request(_ path: String, risk: ToolRisk) -> ApprovalRequest {
            ApprovalRequest(call: ToolCall(id: "x", name: "edit_file", arguments: "{}"), summary: "", risk: risk,
                            preview: .diff(path: path, unified: "", isNewFile: false), suggestedRule: nil)
        }
        if case .deny(let feedback) = Scenarios.denyFeedback.approve(request("calc.py", risk: .write), 0) {
            #expect(feedback?.contains("NOTES.md") == true)
        } else { Issue.record("calc.py edit should be denied") }
        #expect(Scenarios.denyFeedback.approve(request("NOTES.md", risk: .write), 1) == .allow)
    }
}

@Suite struct SummaryRecordTests {
    @Test func resultsKeepEachSummaryWithItsTime() async throws {
        let big = (1...400).map { "let value\($0) = compute(\($0)) // some explanatory text to take up room" }.joined(separator: "\n")
        let (client, _) = MockServer.client(.init(turns: [
            SSE.toolCall("r1", "read_file", #"{"path":"A.swift"}"#),
            SSE.toolCall("r2", "read_file", #"{"path":"B.swift"}"#),
            SSE.content("## Summary\nRead A.swift and B.swift; each defines 400 computed values. Next: answer."),
            SSE.content("Done."),
        ]))
        let ep = Endpoint(name: "M", kind: .openai, baseURL: client.baseURL)
        let scenario = Scenario(id: "summary-test", summary: "", mode: .fullAuto, maxSteps: 6, contextCap: 12_000,
                                prepare: { dir in
                                    for f in ["A.swift", "B.swift"] { try Data(big.utf8).write(to: dir.appending(path: f)) }
                                    return "read A.swift and B.swift" },
                                check: { _, run in CheckResult(passed: run.finalText == "Done.", score: 1) })
        let r = await Runner.run(scenario, on: ModelTarget(endpoint: ep, model: "m", contextLength: 32_768), trial: 1,
                                 makeClient: { ChatClient(baseURL: $0.endpoint.baseURL, session: MockServer.session) })
        #expect(r.check.passed)
        let s = try #require(r.summaries?.first)
        #expect(r.summaries?.count == 1)
        #expect(s.summary.hasPrefix("## Summary"))
        #expect(s.tokensAfter < s.tokensBefore)
        #expect(s.seconds != nil)
        // One planned skip, free (no summary request was sent): after the first read, the prompt was over the threshold
        // but all of it was the unread result, which a compaction keeps whole (bug hunt 2026-11-02, item 16), so a
        // summary could only have replaced the user's line. The compaction came after the second read.
        #expect(r.compactionsSkipped == 1)
    }
}

@Suite struct SwitchTests {
    @Test func secondModelContinuesTheConversationInItsOwnShape() async throws {
        let (a, hostA) = MockServer.client(.init(turns: [SSE.toolCall("call_A-1", "read_file", #"{"path":"calc.py"}"#)]))
        let (b, hostB) = MockServer.client(.init(turns: [SSE.content("B finished the job.")]))
        let epA = Endpoint(name: "A", kind: .openai, baseURL: a.baseURL)
        let epB = Endpoint(name: "B", kind: .openai, baseURL: b.baseURL)
        let first = ModelTarget(endpoint: epA, model: "qwen-ish", contextLength: 32_768)
        let second = ModelTarget(endpoint: epB, model: "devstral-ish", contextLength: 16_384,
                                 profile: ModelProfile(endpointID: epB.id, model: "devstral-ish",
                                                       history: HistoryShape(toolCallIDs: .alphanumeric9)))
        let scenario = Scenario(id: "switch-test", summary: "", mode: .fullAuto, maxSteps: 5,
                                prepare: { dir in try Fixtures.calc(at: dir); return "look at calc.py" },
                                check: { _, run in CheckResult(passed: run.finalText == "B finished the job.", score: 1) })
        // MockServer routes by host, so each target's ChatClient reaches its own mock via the URL.
        let r = await Runner.runSwitch(scenario, first: first, second: second, switchAfter: 1, trial: 1,
                                       makeClient: { ChatClient(baseURL: $0.endpoint.baseURL, session: MockServer.session) })
        #expect(r.check.passed)
        #expect(MockServer.requestBodies(hostA).count == 1)
        let bFirst = String(decoding: try #require(MockServer.requestBodies(hostB).first), as: UTF8.self)
        #expect(bFirst.contains("look at calc.py"))
        #expect(bFirst.contains(HistoryShaper.alphanumeric9("call_A-1")))    // A's call, in B's id format
        #expect(!bFirst.contains("call_A-1"))
        #expect(bFirst.contains("A tiny calculator library"))                // A's tool result carried over
    }
}
