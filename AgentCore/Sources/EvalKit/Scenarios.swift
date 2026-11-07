import AgentCore
import Foundation

/// What a check concluded about one trial.
public struct CheckResult: Codable, Sendable {
    public var passed: Bool
    /// 0...1, for partial credit.
    public var score: Double
    public var notes: [String]

    public init(passed: Bool, score: Double, notes: [String] = []) {
        self.passed = passed
        self.score = score
        self.notes = notes
    }
}

/// Everything recorded about one agent run, for checks and reports.
public struct RunRecord: Sendable {
    public var messages: [ChatMessage] = []
    public var stop: AgentStop?
    public var compactions: [Compaction] = []
    /// How long each compaction's summary took (from "compacting" to "compacted"), in order.
    public var summarySeconds: [Double] = []
    public var peakPromptTokens = 0
    /// Every billed request (`AgentEvent.cost`), summaries included.
    public var costs: [CostEntry] = []
    /// The run's record (`AgentEvent.runEnded`).
    public var runRecord: AgentRunRecord?
    public var approvalsAsked = 0
    public var duration: TimeInterval = 0
    /// Subagent runs started, and their judgments (checks, the parent's ratings).
    public var subagentRuns = 0
    public var judgments: [RunJudgment] = []

    public var assistantMessages: [ChatMessage] { messages.filter { $0.role == .assistant } }
    public var finalText: String { assistantMessages.last(where: { $0.toolCalls.isEmpty })?.content ?? "" }
    public var toolCalls: [ToolCall] { assistantMessages.flatMap(\.toolCalls) }
    public var toolErrors: Int { messages.filter { $0.role == .tool && $0.toolResult?.isError == true && $0.toolResult?.denied != true }.count }

    /// Paths passed to read_file, in order.
    public var filesRead: [String] {
        toolCalls.filter { $0.name == "read_file" }.compactMap { (try? ToolArguments(json: $0.arguments))?.string("path") }
    }
}

public struct Scenario: Sendable {
    public let id: String
    public let summary: String
    public var mode: PermissionMode = .fullAuto
    public var maxSteps = 60
    /// Caps the context budget below the model's real context, so compaction is exercised on every model.
    public var contextCap: Int?
    public var wallClock: TimeInterval = 900
    /// For delegation scenarios (EVAL_PLAN.md E6): whether a good parent hands the work to a subagent; nil: no view.
    public var expectDelegation: Bool?
    /// Builds the fixture in the directory and returns the user's request.
    public let prepare: @Sendable (URL) throws -> String
    /// Answers approval requests (Ask mode); the Int counts earlier requests in this run.
    public var approve: @Sendable (ApprovalRequest, Int) -> ApprovalDecision = { _, _ in .allow }
    public let check: @Sendable (URL, RunRecord) -> CheckResult
}

public enum Scenarios {
    public static let all: [Scenario] = [explainRepo, findDefinition, fixTests, denyFeedback, longDoc, survey]

    public static func named(_ ids: [String]) -> [Scenario] {
        if ids == ["delegation"] { return delegation }
        if ids == ["phase1"] { return phase1 }
        return ids.isEmpty || ids == ["all"] ? all : (all + delegation + phase1).filter { ids.contains($0.id) }
    }

    /// Scenarios for Phase 1 of GAP_ANALYSIS.md (agentic core), one per item that has one.
    public static let phase1: [Scenario] = [warnCount, nestedRules]

    /// The delegation-decision set (EVAL_PLAN.md E6), each labeled with what a good parent does.
    public static let delegation: [Scenario] = {
        var s = survey
        s.expectDelegation = true
        return [s, logSweep, twoQuestions, tinyLookup, smallFix]
    }()

    // MARK: explain-repo

    public static let explainRepo = Scenario(
        id: "explain-repo",
        summary: "Explain a small Python service's structure (read-only)",
        mode: .plan, maxSteps: 30,
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Explain how this project is organized: its main parts, what each does, and how they connect. "
                + "Be specific: name the modules and key classes."
        },
        check: { _, run in
            let text = run.finalText.lowercased()
            let parts: [(String, [String])] = [
                ("models / Item", ["models.py", "item"]), ("storage / SqliteStore", ["storage.py", "sqlitestore"]),
                ("pricing", ["pricing"]), ("api", ["api.py", "api module", "http"]), ("cli", ["cli.py", "command line", "cli"]),
                ("tests", ["test"]), ("InsufficientStock", ["insufficientstock"]),
            ]
            let found = parts.filter { _, keys in keys.contains { text.contains($0) } }
            let read = Set(run.filesRead).count
            var notes = ["mentions \(found.count)/\(parts.count): " + found.map(\.0).joined(separator: ", ")]
            notes.append("read \(read) files")
            let score = Double(found.count) / Double(parts.count)
            return CheckResult(passed: found.count >= 6 && read >= 3, score: score, notes: notes)
        })

    // MARK: find-definition

    public static let findDefinition = Scenario(
        id: "find-definition",
        summary: "Locate a function by path:line and explain an error path (read-only)",
        mode: .plan, maxSteps: 20,
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "Where is `reserve_stock` defined, and what happens when there isn't enough stock? "
                + "Give the location as path:line."
        },
        check: { dir, run in
            let text = run.finalText
            let src = (try? String(contentsOf: dir.appending(path: "inventory/storage.py"), encoding: .utf8)) ?? ""
            let line = (src.components(separatedBy: "\n").firstIndex { $0.contains("def reserve_stock") } ?? -2) + 1
            // Correctness, not format: "storage.py:31", "storage.py (line 31)", "storage.py` at line 31".
            let cited = text.matches(of: /storage\.py[`'"]?(?::|[^\n]{0,40}?\blines?\s+)(\d+)/).compactMap { Int($0.1) }
            let locOK = cited.contains { abs($0 - line) <= 1 }
            let errOK = text.contains("InsufficientStock")
            return CheckResult(passed: locOK && errOK, score: (locOK ? 0.6 : 0) + (errOK ? 0.4 : 0),
                               notes: ["expected storage.py:\(line), cited \(cited)", errOK ? "names InsufficientStock" : "no InsufficientStock"])
        })

    // MARK: fix-tests

    public static let fixTests = Scenario(
        id: "fix-tests",
        summary: "Fix two bugs so the tests pass, without touching the tests",
        mode: .fullAuto, maxSteps: 40,
        prepare: { dir in
            try Fixtures.calc(at: dir)
            return "The tests are failing. Run them with `python3 -m unittest -v`, fix the bugs in calc.py, "
                + "and run the tests again to confirm they pass."
        },
        check: { dir, _ in
            let pass = shell("cd \(q(dir.path)) && python3 -m unittest 2>&1").status == 0
            let changed = shell("git -C \(q(dir.path)) status --porcelain --untracked-files=no").output
                .split(separator: "\n").map { String($0.dropFirst(3)) }
            let onlyCalc = changed == ["calc.py"]
            return CheckResult(passed: pass && onlyCalc, score: (pass ? 0.7 : 0) + (onlyCalc ? 0.3 : 0),
                               notes: [pass ? "tests pass" : "tests fail", "changed: \(changed)"])
        })

    // MARK: deny-feedback

    public static let denyFeedback = Scenario(
        id: "deny-feedback",
        summary: "After a denied edit, follow the user's feedback instead",
        mode: .ask, maxSteps: 30,
        prepare: { dir in
            try Fixtures.calc(at: dir)
            return "The tests are failing. Run them with `python3 -m unittest -v`, then fix the bugs in calc.py."
        },
        approve: { request, _ in
            guard request.risk == .write else { return .allow }
            if case .diff(let path, _, _)? = request.preview, path == "calc.py" {
                return .deny(feedback: "Don't modify calc.py. Instead create NOTES.md with one line per bug you "
                             + "found, naming the function and the fix.")
            }
            return .allow
        },
        check: { dir, _ in
            let calcUnchanged = shell("git -C \(q(dir.path)) diff --quiet -- calc.py").status == 0
            let notes = (try? String(contentsOf: dir.appending(path: "NOTES.md"), encoding: .utf8))?.lowercased() ?? ""
            let namesBoth = notes.contains("sub") && notes.contains("mean")
            return CheckResult(passed: calcUnchanged && namesBoth,
                               score: (calcUnchanged ? 0.5 : 0) + (notes.isEmpty ? 0 : 0.2) + (namesBoth ? 0.3 : 0),
                               notes: [calcUnchanged ? "calc.py untouched" : "calc.py changed",
                                       notes.isEmpty ? "no NOTES.md" : (namesBoth ? "NOTES.md names both bugs" : "NOTES.md incomplete")])
        })

    // MARK: long-doc

    public static let longDocCount = 14

    public static let longDoc = Scenario(
        id: "long-doc",
        summary: "Document \(longDocCount) modules with unguessable facts; context capped to force compaction",
        mode: .fullAuto, maxSteps: 100, contextCap: 16_384, wallClock: 1500,
        prepare: { dir in
            _ = try Fixtures.documentation(at: dir, count: longDocCount, seed: 42)
            return "Document this package in FILES.md. For every Python file under src, read the file, then add one "
                + "line: `path` — `ClassName` — a one-sentence description, where ClassName is the class the file "
                + "declares. Keep a todo list as you go."
        },
        check: { dir, run in
            let expected = (try? Fixtures.documentation(at: FileManager.default.temporaryDirectory
                .appending(path: "kk-eval-expected-\(UUID().uuidString.prefix(6))"), count: longDocCount, seed: 42)) ?? [:]
            let doc = (try? String(contentsOf: dir.appending(path: "FILES.md"), encoding: .utf8)) ?? ""
            let lines = doc.split(separator: "\n").map(String.init)
            var correct = 0, listed = 0
            for (path, cls) in expected {
                guard let line = lines.first(where: { $0.contains(path) }) else { continue }
                listed += 1
                if line.contains(cls) { correct += 1 }
            }
            let mentioned = Set(doc.matches(of: /src\/[A-Za-z0-9_]+\.py/).map { String($0.0) })
            let invented = mentioned.subtracting(expected.keys).sorted()
            let unread = Set(expected.keys).subtracting(run.filesRead).count
            let score = Double(correct) / Double(max(1, expected.count)) - 0.1 * Double(invented.count)
            return CheckResult(passed: correct >= expected.count - 1 && invented.isEmpty && !run.compactions.isEmpty,
                               score: max(0, score),
                               notes: ["\(correct)/\(expected.count) correct, \(listed) listed", "compactions: \(run.compactions.count)",
                                       invented.isEmpty ? "no invented files" : "invented: \(invented)",
                                       unread == 0 ? "read every file" : "\(unread) files never read"])
        })
}

extension Scenarios {
    // MARK: survey (for delegation: broad reading, a short answer)

    /// Reading every note is the only way to the answer (each postponement is worded differently, so no one search
    /// finds them), and the answer is short: what a subagent is for. The context is capped so doing it all in the main
    /// context costs compactions. Run with `--subagents both` to compare. (A first version asked about class names,
    /// and a model answered it with one grep.)
    public static let survey = Scenario(
        id: "survey",
        summary: "Find which of 16 meeting notes postponed something (broad reading, short answer)",
        mode: .plan, maxSteps: 60, contextCap: 16_384, wallClock: 1500,
        prepare: { dir in
            try Fixtures.meetingNotes(at: dir)
            return "The notes/ folder has one file per team meeting. In which meetings was something postponed or "
                + "pushed to a later date? List those files and, for each, what was postponed. Nothing else."
        },
        check: { _, run in
            let text = run.finalText
            let found = Fixtures.postponed.filter { text.contains($0) }
            let wrong = Fixtures.meetingFiles.filter { !Fixtures.postponed.contains($0) && text.contains($0) }
            return CheckResult(passed: found.count == Fixtures.postponed.count && wrong.isEmpty,
                               score: max(0, Double(found.count) / Double(Fixtures.postponed.count) - 0.1 * Double(wrong.count)),
                               notes: ["\(found.count)/\(Fixtures.postponed.count) right", wrong.isEmpty ? "none wrong" : "wrong: \(wrong)",
                                       "subagent runs: \(run.subagentRuns)", "peak prompt \(run.peakPromptTokens) tokens"])
        })
}

extension Scenarios {
    // MARK: delegation decisions

    /// Five long logs; the answer is three counts.
    public static let logSweep = Scenario(
        id: "log-sweep", summary: "Count the kinds of error across five long logs (delegate: one big read, a short answer)",
        mode: .plan, maxSteps: 60, contextCap: 16_384, wallClock: 1500, expectDelegation: true,
        prepare: { dir in
            try Fixtures.manyLogs(at: dir)
            return "The logs/ folder has five service logs. What kinds of ERROR appear in them, and how many times each "
                + "in all? Answer with the counts only."
        },
        check: { _, run in
            let t = run.finalText.lowercased()
            let found = Fixtures.errorCounts.filter { kind, n in
                t.components(separatedBy: "\n").contains { $0.contains(kind) && $0.contains(String(n)) }
            }
            return CheckResult(passed: found.count == Fixtures.errorCounts.count, score: Double(found.count) / 3,
                               notes: ["\(found.count)/3 counts right", "subagent runs: \(run.subagentRuns)",
                                       "peak prompt \(run.peakPromptTokens) tokens"])
        })

    /// Two unrelated questions about one project.
    public static let twoQuestions = Scenario(
        id: "two-questions", summary: "Answer two independent questions (delegate: both at once)",
        mode: .plan, maxSteps: 40, expectDelegation: true,
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            _ = try Fixtures.documentation(at: dir.appending(path: "parts"), count: 10, seed: 7)
            return "Two independent questions about this repository: (1) Where is reserve_stock defined, as path:line? "
                + "(2) Which class does parts/src/part04.py declare?"
        },
        check: { dir, run in
            let t = run.finalText
            let line = TaskBank.lineOf(dir, "inventory/storage.py", "def reserve_stock")
            let one = GroundedChecks.citations(in: t).contains { $0.path.hasSuffix("storage.py") && abs($0.line - line) <= 1 }
            let name = TaskBank.read(dir, "parts/src/part04.py").firstMatch(of: /class (\w+):/).map { String($0.1) } ?? "?"
            let two = t.contains(name)
            return CheckResult(passed: one && two, score: (one ? 0.5 : 0) + (two ? 0.5 : 0),
                               notes: [one ? "✓ storage.py:\(line)" : "✗ storage.py:\(line)", two ? "✓ \(name)" : "✗ \(name)",
                                       "subagent runs: \(run.subagentRuns)"])
        })

    /// One grep's worth: delegating only adds cost.
    public static let tinyLookup = Scenario(
        id: "tiny-lookup", summary: "Look up one constant (don't delegate: one grep)",
        mode: .plan, maxSteps: 20, expectDelegation: false,
        prepare: { dir in
            try Fixtures.inventory(at: dir)
            return "What value does TAX_RATE have?"
        },
        check: { _, run in
            let ok = run.finalText.contains("0.0825") || run.finalText.contains("8.25")
            return CheckResult(passed: ok, score: ok ? 1 : 0, notes: [ok ? "✓ 0.0825" : "✗ 0.0825", "subagent runs: \(run.subagentRuns)"])
        })

    /// A one-line fix with the failing test named: the parent has all it needs.
    public static let smallFix = Scenario(
        id: "small-fix", summary: "Fix one obvious bug (don't delegate: the parent has the context)",
        mode: .fullAuto, maxSteps: 30, expectDelegation: false,
        prepare: { dir in
            try Fixtures.calc(at: dir)
            return "test_sub fails because sub() in calc.py adds instead of subtracting. Fix sub() and run `python3 -m "
                + "unittest test_calc.CalcTests.test_sub` to confirm."
        },
        check: { dir, run in
            let ok = shell("cd \(q(dir.path)) && python3 -m unittest test_calc.CalcTests.test_sub 2>&1").status == 0
            return CheckResult(passed: ok, score: ok ? 1 : 0, notes: [ok ? "✓ test_sub passes" : "✗ test_sub fails",
                                                                   "subagent runs: \(run.subagentRuns)"])
        })
}

func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Runs a zsh command synchronously (for checks), without the user's startup files (`-f`): the eval's own environment
/// and PATH decide what runs, so a profile can't change gold's results (BUG_HUNT_2026-11-02.md item 44; before
/// 2026-11-03 this was a login shell).
func shell(_ command: String) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-f", "-c", command]
    var env = ProcessInfo.processInfo.environment
    if (env["PATH"] ?? "").isEmpty { env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin" }
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

extension Scenarios {
    // MARK: Phase 1

    /// B4: a log too long to read, where counting needs grep's count mode, and a trap (lines that say "warning" but
    /// aren't warnings).
    public static let warnCount = Scenario(
        id: "warn-count", summary: "Count the warnings in a 6,000-line build log (grep count mode; a trap)",
        mode: .plan, maxSteps: 20,
        prepare: { dir in
            try Fixtures.buildLog(at: dir)
            return "How many compiler warnings are in build.log? Give the exact number."
        },
        check: { dir, run in
            let n = Fixtures.buildLogWarnings(dir)
            let numbers = run.finalText.matches(of: /\b(\d[\d,]*)\b/).compactMap { Int($0.1.replacingOccurrences(of: ",", with: "")) }
            let counted = run.toolCalls.filter { c in
                c.name == "grep" && (try? ToolArguments(json: c.arguments))?.string("output_mode") == "count"
            }.count
            return CheckResult(passed: numbers.contains(n), score: numbers.contains(n) ? 1 : 0,
                               notes: [numbers.contains(n) ? "✓ \(n)" : "✗ \(n), said \(numbers.prefix(5))",
                                       "grep count calls: \(counted)", "tool calls: \(run.toolCalls.count)"])
        })
}

extension Scenarios {
    /// B6: a rule that lives in a subfolder's AGENTS.md (not the root's), which the model sees only when it touches
    /// that folder.
    public static let nestedRules = Scenario(
        id: "nested-rules", summary: "Follow a subfolder's AGENTS.md rule (a docstring prefix) when adding a function",
        mode: .fullAuto, maxSteps: 30,
        prepare: { dir in
            try Fixtures.write(dir, [
                "AGENTS.md": "A small Python utilities project. Check it with python3 -c 'import pkg.mathutil'.\n",
                "pkg/__init__.py": "",
                "pkg/AGENTS.md": "# Rules for pkg/\n\nEvery new function in this package needs a docstring whose first word is "
                    + "\"ZEBRA:\" (our doc tool collects those).\n",
                "pkg/mathutil.py": "def add(a, b):\n    return a + b\n",
            ])
            try Fixtures.commitAll(dir)
            return "Add a function double(x) to pkg/mathutil.py that returns 2*x."
        },
        check: { dir, run in
            let text = (try? String(contentsOf: dir.appending(path: "pkg/mathutil.py"), encoding: .utf8)) ?? ""
            let defined = text.contains("def double(")
            let after = text.components(separatedBy: "def double(").dropFirst().first ?? ""
            let docOK = after.range(of: #"^[^\n]*\n\s*("""|''')\s*ZEBRA:"#, options: .regularExpression) != nil
            let sent = run.messages.contains { $0.content.contains("[kurtkode: instructions from pkg/AGENTS.md") }
            return CheckResult(passed: defined && docOK, score: (defined ? 0.5 : 0) + (docOK ? 0.5 : 0),
                               notes: [defined ? "✓ double defined" : "✗ no double", docOK ? "✓ ZEBRA: docstring" : "✗ no ZEBRA: docstring",
                                       sent ? "pkg/AGENTS.md was sent" : "pkg/AGENTS.md never sent"])
        })
}

extension Fixtures {
    /// A 6,000-line compiler log: about 7% warning lines ("file:line:col: warning: …") and some notes that mention
    /// warnings without being one.
    public static func buildLog(at root: URL) throws {
        var rng = SplitMix(seed: 11)
        var lines: [String] = []
        for i in 1...6000 {
            let r = rng.next() % 1000
            let mod = 1 + rng.next() % 40
            if r < 70 {
                lines.append("src/mod\(mod).c:\(1 + rng.next() % 900):5: warning: unused variable 'x\(i)' [-Wunused-variable]")
            } else if r < 75 {
                lines.append("note: in expansion of macro 'CHECK' (warning suppressed elsewhere)")
            } else {
                lines.append(String(format: "[%05d] CC src/mod%d.o", i, mod))
            }
        }
        try write(root, ["build.log": lines.joined(separator: "\n") + "\n", "README.md": "# firmware\n"])
        try commitAll(root)
    }

    public static func buildLogWarnings(_ dir: URL) -> Int {
        let text = (try? String(contentsOf: dir.appending(path: "build.log"), encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.count
    }
}
