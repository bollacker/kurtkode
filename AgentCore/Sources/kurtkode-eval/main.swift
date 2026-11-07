import AgentCore
import EvalKit
import Foundation

// kurtkode-eval: run agent scenarios against models and report how they do. Usage: `usage` below (--help prints it).

let usage = """
kurtkode-eval: run agent scenarios against models and report how they do.

  swift run -c release kurtkode-eval --models lmstudio:qwen/qwen3-coder-30b,openrouter:qwen/qwen3-coder \\
      [--scenarios all|delegation|phase1|fix-tests,long-doc] [--trials 2] [--context 32768] [--out results.json] [--no-load]
  swift run kurtkode-eval --switch 'lmstudio:A>lmstudio:B' --scenarios fix-tests [--switch-after 3]
  swift run kurtkode-eval --list
  ... [--max-cost 2]   stop starting trials once the run has spent this many USD
  ... [--skills builtin|none]   bank runs: general agents get kurtkode's built-in skills, as in sessions (default none)
  ... [--own-cost]   the cap counts only this process's runs, not the key's usage (other processes share the key)
  ... [--key-limit 1234.5]   stop starting runs once a key's total usage, as its server reports it, reaches this
  ... [--sandbox fullAuto|always|never]   when commands run in the sandbox (default: fullAuto, as the app)
  ... [--endpoint proxy=http://127.0.0.1:18080/v1]   an extra OpenAI-compatible endpoint for this run (no key)
  ... [--fallback endpoint:model]   where a turn goes when the server loses the model's tool call
  ... [--providers-ignore A,B]   OpenRouter providers never to use (the profile's provider preferences otherwise)
  ... [--key-from openrouter]   --endpoint servers use that saved endpoint's key (a proxy in front of it)
  ... [--prompt-style NAME]   the system prompt's working rules: detailed, lean, or a style-NAME.md template
      (default: lean for Claude and Gemini)
  ... [--subagent-pool [both]] subagents on the shipped model pool with its retry ladder (a hosted parent only); both:
      each target also runs with subagents on its own model, in the same process;
  ... [--subagent-model E:M] subagents run on that model; [--force-delegation] the request tells the parent to delegate
  ... [--kk-delegation on|off|both] A7: at the delegation threshold kurtkode makes the next step a task call (default off)
  ... [--delegation-tokens N] the note to delegate also after N tokens of reads in a row, any context (default 30000; 0 off)
  ... [--subagents on|off|both]   the task tool on the same model (default off); both runs each scenario twice
  ... [--prompt-dir DIR]   prompt templates that override the defaults (personal and project ones are never read)


  swift run kurtkode-eval --bank all|hard|real|real:SET|ID,ID [--max-tokens N] --models E:M[,E:M] [--judges E:M[,E:M]] [--judge-paths parent,grader] [--degrade]
      The task bank (SUBAGENT_ROUTING_DESIGN.md): small delegations run directly on each model as a subagent, each
      checked against gold; each judge then rates every run the way a parent does at the end of a run (parent) or
      as the grader does (grader), and a calibration table compares their verdicts with gold. --degrade also judges
      a copy of each passing run made wrong on purpose (its digits changed, a change task's work undone): known
      failures, so the table can say how many failures each judge catches.

  Record once, judge many (EVAL_PLAN.md E1), in eval-results/runs/SET/ (or SET as a path):
  swift run kurtkode-eval --bank all --models E:M,… --trials 3 --record SET [--degrade] [--parallel N] [--parallel-remote N]
  swift run kurtkode-eval --judge SET --judges E:M,… [--judge-paths parent,grader] [--judge-trials 1|all] [--parallel N]
      --sample N judges a fixed, balanced subset: every real failure, then degraded copies and passing runs half
      and half, chosen by a hash of the run id (the same subset for every judge). --rejudge-missing judges again
      where a judge gave no verdict (the new judgment is added; the latest counts).
  ... [--models-file F] one E:M per line (a "#off" suffix: reasoning off); [--no-train] OpenRouter providers that
      don't train on prompts and take every parameter; [--models-at-once K] models run K at a time in the given
      order; [--stop-after-failures N] a model stops after N gold failures (or N infrastructure failures);
      [--max-cost USD] no run starts once this process's list price or the key's usage, plus the expected cost
      of the runs in flight and of the new one (each model's mean so far), would pass it.
  swift run kurtkode-eval --report SET [--out FILE.md]
  swift run kurtkode-eval --bank IDS --models CHEAP --cascade STRONG --record SET [--trials N] [--max-cost USD]
      The live cascade: each task a main run on CHEAP in a CLI session (the project's tests named, as 11b runs them);
      when the session offers escalation, the offer is taken and STRONG picks up through the product's hand-over.
      Gold after each stage; one run.json per task and trial in SET.
  swift run kurtkode-eval --regold SET [--degrade]   score stored runs again with the current gold (no model runs)
  swift run kurtkode-eval --retry-sim SET [--out FILE.jsonl]   the D3 retry trigger on stored runs, with citations
  swift run kurtkode-eval --review-sim SET --reviewers E:M,… [--per-group 12] [--out ROWS.jsonl] [--max-cost USD]
      A6: each reviewer reviews a sample of stored runs (every real failure that touches code, up to N of each
      file-touching degradation, 2N passing code runs); the diff is rebuilt from the saved fixture. Resumes from --out.
      resolved again in each run's fixture: one line per run (task, trial, model, gold, the hard failures, whether
      the retry would fire, what it was charged), for simulating the retry ladder (no model runs)
      Recording skips runs already recorded and judging skips verdicts already given, so both resume. --degrade
      records the degraded copies of trial 1's passing runs. Models (and judges) run at the same time; --parallel
      is how many runs of one local model at once, --parallel-remote of one remote model.

--switch runs each scenario starting on model A, which stops after --switch-after steps, then model B
continues the same conversation (the multi-model session case). --no-profiles sends history as-is.

Endpoints come from kurtkode's endpoints.json (by name, case-insensitive); "lmstudio" is this Mac.
API keys: KURTKODE_API_KEY_<ENDPOINT> (e.g. KURTKODE_API_KEY_OPENROUTER) from your shell, else the
Keychain entry kurtkode saved (macOS may ask you to allow access). Keys are never taken as arguments.
Local LM Studio models are loaded one at a time with --parallel 1 and an explicit context, and only
when at least 30% of memory is free.

KURTKODE_NO_KEYCHAIN=1: no Keychain reads (endpoints with a key in the environment still run).
"""


setvbuf(stdout, nil, _IOLBF, 0)

struct Options {
    var models: [String] = []
    var scenarios: [String] = ["all"]
    var trials = 1
    var context = 32_768
    /// Output tokens a turn may produce on bank runs (default 4096; native Anthropic gets at least 16384 either way).
    var maxTokens: Int?
    var out: String?
    var manageLMS = true
    var list = false
    var switches: [(String, String)] = []
    var switchAfter = 3
    var profiles = true
    var transcripts: String?
    var maxCost: Double?
    var ownCost = false
    var keyLimit: Double?
    var extraEndpoints: [Endpoint] = []
    var sandbox = SandboxUse.fullAuto
    var fallback: String?
    var promptStyle: PromptStyle?
    var promptDir: URL?
    var skills = false
    var providersIgnore: [String]?
    /// The saved endpoint whose key the --endpoint servers send (read like any key: env, else Keychain).
    var keyFrom: String?
    var bank: [String]?
    var subagents: [Bool] = [false]
    var judges: [String] = []
    var judgePaths: Set<String> = ["parent", "grader"]
    var degrade = false
    var record: String?
    /// --cascade E:M with --bank, --record and one --models: the live cascade (Cascade.swift), the model escalated to.
    var cascade: String?
    /// --regold-cascade SET: gold again for a cascade store's runs that failed, from their saved diffs.
    var regoldCascade: String?
    var judgeSet: String?
    var reportSet: String?
    var regoldSet: String?
    var retrySimSet: String?
    /// --trigger-sim SET[,SET]: A4's escalation triggers on stored runs (precision, recall), per model; --ladder
    /// "SET|E:M>SET|E:M[>…]" replays the cascade up those models (repeatable); --only-model S: --judge only runs of models
    /// whose label contains S.
    var triggerSimSets: [String] = []
    var ladders: [String] = []
    var onlyModel: String?
    /// --kk-delegation on|off|both: A7, kurtkode makes the next step a task call at the delegation threshold.
    var kkDelegation: [Bool] = [false]
    /// --review-sim SET --reviewers E:M,… [--per-group N]: A6's reviewers on stored bank runs.
    var reviewSimSet: String?
    var reviewers: [String] = []
    var perGroup = 12
    /// --subagent-pool [both]: subagents on the shipped pool ([true]), or each target run both ways ([false, true]).
    var subagentPool: [Bool] = [false]
    var sample: Int?
    var rejudgeMissing = false
    var noTrain = false
    var subagentModel: String?
    var forceDelegation = false
    var delegationTokens: Int?
    var modelsAtOnce = 0
    var stopAfterFailures = 0
    var judgeTrials = "1"
    var parallel = 1
    var parallelRemote = 4
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func value() -> String { args.isEmpty ? "" : args.removeFirst() }
    if args.contains("--help") || args.contains("-h") {
        print(usage)
        exit(0)
    }
    while !args.isEmpty {
        switch args.removeFirst() {
        case "--models": o.models = value().split(separator: ",").map(String.init)
        case "--scenarios": o.scenarios = value().split(separator: ",").map(String.init)
        case "--trials": o.trials = max(1, Int(value()) ?? 1)
        case "--context": o.context = Int(value()) ?? 32_768
        case "--max-tokens": o.maxTokens = Int(value())
        case "--out": o.out = value()
        case "--no-load": o.manageLMS = false
        case "--no-profiles": o.profiles = false
        case "--transcripts": o.transcripts = value()
        case "--max-cost": o.maxCost = Double(value())
        case "--own-cost": o.ownCost = true
        case "--key-limit": o.keyLimit = Double(value())
        case "--sandbox":
            guard let s = SandboxUse(rawValue: value()) else { print("--sandbox wants fullAuto, always, or never"); exit(2) }
            o.sandbox = s
        case "--endpoint":
            let kv = value().split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let url = URL(string: kv[1]) else { print("--endpoint wants name=URL"); exit(2) }
            o.extraEndpoints.append(Endpoint.launchOnly(name: kv[0], url: Endpoint.normalizedBaseURL(url)))
        case "--switch-after": o.switchAfter = max(1, Int(value()) ?? 3)
        case "--switch":
            o.switches = value().split(separator: ",").compactMap { pair in
                let ab = pair.split(separator: ">").map(String.init)
                return ab.count == 2 ? (ab[0], ab[1]) : nil
            }
        case "--list": o.list = true
        case "--fallback": o.fallback = value()
        case "--prompt-style":
            guard let s = PromptStyle(rawValue: value()) else { print("--prompt-style wants a style name (detailed, lean, …)"); exit(2) }
            o.promptStyle = s
        case "--prompt-dir": o.promptDir = URL(filePath: (value() as NSString).expandingTildeInPath)
        case "--skills":
            switch value() {
            case "builtin": o.skills = true
            case "none": o.skills = false
            default: print("--skills wants builtin or none"); exit(2)
            }
        case "--providers-ignore": o.providersIgnore = value().split(separator: ",").map(String.init)
        case "--key-from": o.keyFrom = value()
        case "--subagents":
            switch value() {
            case "on": o.subagents = [true]
            case "off": o.subagents = [false]
            case "both": o.subagents = [false, true]
            default: print("--subagents wants on, off, or both"); exit(2)
            }
        case "--bank": o.bank = value().split(separator: ",").map(String.init)
        case "--judges": o.judges = value().split(separator: ",").map(String.init)
        case "--degrade": o.degrade = true
        case "--record": o.record = value()
        case "--cascade": o.cascade = value()
        case "--regold-cascade": o.regoldCascade = value()
        case "--judge": o.judgeSet = value()
        case "--report": o.reportSet = value()
        case "--regold": o.regoldSet = value()
        case "--retry-sim": o.retrySimSet = value()
        case "--review-sim": o.reviewSimSet = value()
        case "--trigger-sim": o.triggerSimSets = value().split(separator: ",").map(String.init)
        case "--ladder": o.ladders.append(value())
        case "--only-model": o.onlyModel = value()
        case "--kk-delegation":
            switch value() {
            case "on": o.kkDelegation = [true]
            case "off": o.kkDelegation = [false]
            case "both": o.kkDelegation = [false, true]
            default: print("--kk-delegation wants on, off, or both"); exit(2)
            }
        case "--reviewers": o.reviewers = value().split(separator: ",").map(String.init)
        case "--per-group": o.perGroup = max(1, Int(value()) ?? 12)
        case "--subagent-pool":
            if args.first == "both" { _ = args.removeFirst(); o.subagentPool = [false, true] } else { o.subagentPool = [true] }
        case "--sample": o.sample = Int(value())
        case "--rejudge-missing": o.rejudgeMissing = true
        case "--no-train": o.noTrain = true
        case "--subagent-model": o.subagentModel = value()
        case "--force-delegation": o.forceDelegation = true
        case "--delegation-tokens": o.delegationTokens = max(0, Int(value()) ?? 30_000)
        case "--models-at-once": o.modelsAtOnce = max(1, Int(value()) ?? 1)
        case "--stop-after-failures": o.stopAfterFailures = max(1, Int(value()) ?? 2)
        case "--models-file":
            let path = (value() as NSString).expandingTildeInPath
            o.models += ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        case "--judge-trials": o.judgeTrials = value()
        case "--parallel": o.parallel = max(1, Int(value()) ?? 1)
        case "--parallel-remote": o.parallelRemote = max(1, Int(value()) ?? 4)
        case "--judge-paths": o.judgePaths = Set(value().split(separator: ",").map(String.init))
        case let other: print("unknown option \(other)"); exit(2)
        }
    }
    return o
}

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "kurtkode")
let opts = parse()
let saved = EndpointStore(fileURL: support.appending(path: "endpoints.json")).load()
let keySource = opts.keyFrom.flatMap { name in saved.first { $0.name.lowercased() == name.lowercased() } }
if opts.keyFrom != nil, keySource == nil { print("no saved endpoint named \(opts.keyFrom!) for --key-from"); exit(2) }
let extraIDs = Set(opts.extraEndpoints.map(\.id))
let endpoints = saved + opts.extraEndpoints.map { e in var e = e; e.usesAPIKey = e.usesAPIKey || keySource != nil; return e }

func endpoint(named name: String) -> Endpoint? {
    let key = name.lowercased()
    if key == "lmstudio" || key == "local" { return .localLMStudio }
    return endpoints.first { $0.name.lowercased() == key || $0.name.lowercased().replacingOccurrences(of: " ", with: "-") == key }
}

/// Keys read once per endpoint (hundreds of OpenRouter targets share one).
nonisolated(unsafe) var keyCache: [UUID: String?] = [:]

func apiKey(for e: Endpoint) -> String? {
    if let cached = keyCache[e.id] { return cached }
    let k = readKey(for: e)
    keyCache[e.id] = k
    return k
}

func readKey(for e: Endpoint) -> String? {
    guard e.usesAPIKey else { return nil }
    if extraIDs.contains(e.id), let source = keySource { return readKey(for: source) }
    let envName = "KURTKODE_API_KEY_" + e.name.uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    if let k = ProcessInfo.processInfo.environment[envName], !k.isEmpty { return k }
    for name in e.kind.standardKeyVariables { if let k = ProcessInfo.processInfo.environment[name], !k.isEmpty { return k } }
    // As for the app and the CLI: no Keychain read (a fresh build's read puts a permission prompt on the screen).
    if ProcessInfo.processInfo.environment["KURTKODE_NO_KEYCHAIN"] == "1" { return nil }
    return KeychainStore().apiKey(for: e.id)
}

func fmt(_ x: Double, _ digits: Int = 0) -> String { String(format: "%.\(digits)f", x) }

if opts.list {
    print("Scenarios:")
    for s in Scenarios.all { print("  \(s.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(s.summary) [\(s.mode.rawValue)]") }
    print("Phase 1 (--scenarios phase1, or by name):")
    for s in Scenarios.phase1 { print("  \(s.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(s.summary) [\(s.mode.rawValue)]") }
    print("Task bank (--bank):")
    for t in TaskBank.all {
        print("  \(t.id.padding(toLength: 20, withPad: " ", startingAt: 0)) \(t.summary) [\(t.agent), \(t.card.kind?.rawValue ?? "-")"
              + (t.card.verify == nil ? "" : ", verify") + "]")
    }
    print("Endpoints:")
    for e in endpoints { print("  \(e.name) (\(e.kind.rawValue)) \(e.baseURL.absoluteString)") }
    if let models = try? await LMStudioService().models() {
        print("Local LM Studio models:")
        for m in models where m.isChatModel { print("  lmstudio:\(m.id)\(m.state == .loaded ? "  (loaded)" : "")") }
    }
    exit(0)
}

/// A run set's folder: a name under the repository's eval-results/runs (`EvalPaths.root`, wherever the process
/// runs from inside it), or a path.
func runStore(_ name: String) -> RunStore {
    RunStore(root: name.contains("/") ? URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
                                     : EvalPaths.root.appending(path: "eval-results/runs").appending(path: name))
}

if let set = opts.regoldSet {
    let store = runStore(set)
    print("kurtkode-eval regold: \(store.runs().count) runs in \(store.root.path)" + (opts.degrade ? ", adding degraded copies" : ""))
    let changed = await Runner.regold(store, degrade: opts.degrade, sandbox: opts.sandbox, log: { print($0) })
    for c in changed { print("  \(c.id): \(c.was ? "pass" : "fail") → \(c.now ? "pass" : "fail")") }
    print("\(changed.count) runs changed")
    exit(0)
}

if let set = opts.regoldCascade {
    let root = runStore(set).root
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
    let folders = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
    var changed = 0
    for f in folders {
        let url = f.appending(path: "run.json")
        guard let data = try? Data(contentsOf: url), var r = try? dec.decode(CascadeRun.self, from: data), !r.finalPassed,
              let task = TaskBank.every.first(where: { $0.id == r.task }) else { continue }
        guard let gold = Cascade.regold(r, task: task) else { print("  \(r.task) #\(r.trial): couldn't rebuild"); continue }
        let was = r.finalPassed
        if r.strongGold != nil { r.strongGold = gold } else { r.cheapGold = gold }
        if r.finalPassed != was { changed += 1; print("  \(r.task) #\(r.trial): fail → pass") }
        if let out = try? enc.encode(r) { try? out.write(to: url) }
    }
    print("\(changed) runs changed")
    exit(0)
}

if let set = opts.retrySimSet {
    let store = runStore(set)
    var lines: [String] = []
    var fired = 0, firedOnFailures = 0, failures = 0
    for run in store.runs() where run.degradation == nil && run.infra == nil {
        var checks = run.checks
        if let dir = try? store.restore(run) {
            checks = checks.resolvingCitations(report: run.report, in: Workspace(root: dir))
            try? FileManager.default.removeItem(at: dir)
        }
        let retry = !checks.retryableFailures.isEmpty
        if !run.gold.passed { failures += 1 }
        if retry { fired += 1; if !run.gold.passed { firedOnFailures += 1 } }
        let row: JSONValue = ["task": .string(run.task), "trial": .number(Double(run.trial)), "model": .string(run.model),
                              "passed": .bool(run.gold.passed), "hard": .array(checks.hardFailures.map(JSONValue.string)),
                              "wasHard": .array(run.checks.hardFailures.map(JSONValue.string)), "retry": .bool(retry),
                              "charged": run.runRecord?.totals.charged.map(JSONValue.number) ?? .null]
        lines.append(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))
    }
    if let out = opts.out { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: out)) }
    print("\(lines.count) runs, \(failures) gold failures; the retry fires on \(fired), \(firedOnFailures) of them gold failures")
    exit(0)
}

if !opts.triggerSimSets.isEmpty {
    var signals: [String: [TriggerSim.Signals]] = [:]     // "SET|model" → the model's real runs in that set; "SET|*" all of them
    for set in opts.triggerSimSets {
        let store = runStore(set)
        // Reviews from --review-sim of this set, when there are some (their rows name the runs they reviewed).
        let rows = EvalPaths.root.appending(path: "eval-results/review-sim/\(set)-rows.jsonl")
        let reviews: [ReviewSim.Row] = ((try? String(contentsOf: rows, encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { try? JSONDecoder().decode(ReviewSim.Row.self, from: Data($0.utf8)) }
        for run in store.runs() where run.degradation == nil && run.infra == nil {
            let s = TriggerSim.signals(run, store: store, reviews: reviews)
            signals["\(set)|\(run.model)", default: []].append(s)
            signals["\(set)|*", default: []].append(s)
        }
    }
    var md = "## Escalation triggers on stored runs (\(opts.triggerSimSets.joined(separator: ", ")))\n\n"
    for key in signals.keys.sorted() where opts.onlyModel.map({ key.contains($0) }) != false {
        md += TriggerSim.table(signals[key]!, title: key) + "\n"
    }
    for spec in opts.ladders {
        let levels = spec.split(separator: ">").map { signals[String($0)] ?? [] }
        if levels.contains(where: \.isEmpty) { md += "### \(spec)\n\n(a level has no runs: \(spec.split(separator: ">").filter { signals[String($0)] == nil }))\n\n"; continue }
        md += TriggerSim.ladderTable(levels, title: spec) + "\n"
    }
    if let out = opts.out { try md.write(toFile: out, atomically: true, encoding: .utf8); print("wrote \(out)") } else { print(md) }
    exit(0)
}

if let set = opts.reviewSimSet {
    let store = runStore(set)
    let sample = ReviewSim.sample(store.runs(), perGroup: opts.perGroup)
    let out = URL(fileURLWithPath: opts.out ?? "review-sim-\(set).jsonl")
    let dec = JSONDecoder()
    var rows: [ReviewSim.Row] = ((try? String(contentsOf: out, encoding: .utf8)) ?? "").split(separator: "\n")
        .compactMap { try? dec.decode(ReviewSim.Row.self, from: Data($0.utf8)) }
    final class Spent: @unchecked Sendable { let lock = NSLock(); var usd = 0.0 }
    let spent = Spent()
    spent.usd = rows.compactMap { $0.charged ?? $0.listPrice }.reduce(0, +)
    let reviewers = opts.reviewers.map(target)
    print("kurtkode-eval review-sim: \(sample.count) runs × \(reviewers.count) reviewers; \(rows.count) rows already in \(out.path)")
    var built: [String: String] = [:]
    for run in sample {
        do { built[run.id] = try ReviewSim.diff(run, store: store) } catch { print("  \(run.id): no diff (\(error.localizedDescription))") }
    }
    let diffs = built
    if reviewers.isEmpty {
        // No reviewers: the diffs' sizes by group, to check the rebuilt diffs before paying for reviews.
        for run in sample { print("  \(ReviewSim.group(run))\t\(run.kind)\t\(diffs[run.id]?.utf8.count ?? -1)\t\(run.id)") }
        if let id = ProcessInfo.processInfo.environment["KK_SHOW_DIFF"] { print(diffs[id] ?? "(not in the sample)") }
        exit(0)
    }
    final class Rows: @unchecked Sendable { let lock = NSLock(); var all: [ReviewSim.Row] = [] }
    let found = Rows()
    found.all = rows
    for reviewer in reviewers {
        let label = reviewer.label
        let todo = sample.filter { r in diffs[r.id] != nil && !rows.contains { $0.run == r.id && $0.reviewer == label } }
        print("  \(label): \(todo.count) to review")
        await forEach(todo, limit: slots(reviewer)) { run in
            if let cap = opts.maxCost, spent.lock.withLock({ spent.usd >= cap }) { return }
            let row = await ReviewSim.review(run, diff: diffs[run.id] ?? "", reviewer: reviewer)
            let line = String(decoding: (try? JSONEncoder().encode(row)) ?? Data(), as: UTF8.self) + "\n"
            found.lock.withLock {
                found.all.append(row)
                spent.usd += row.charged ?? row.listPrice ?? 0
                if let h = try? FileHandle(forWritingTo: out) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
                else { try? Data(line.utf8).write(to: out) }
            }
            print("  [\(label)] \(run.id) (\(ReviewSim.group(run))): \(row.verdict ?? "no verdict: " + (row.problem ?? "?")) · \(Int(row.seconds)) s")
        }
    }
    rows = found.lock.withLock { found.all }
    print("\n" + ReviewSim.report(rows) + String(format: "\nspent: $%.4f", spent.usd))
    exit(0)
}

if let set = opts.reportSet {
    let md = EvalReport.markdown(runStore(set))
    if let out = opts.out {
        try md.write(toFile: out, atomically: true, encoding: .utf8)
        let csv = (out as NSString).deletingPathExtension + "-frontier.csv"
        try EvalReport.frontierCSV(runStore(set)).write(toFile: csv, atomically: true, encoding: .utf8)
        print("wrote \(out) and \(csv)")
    } else { print(md) }
    exit(0)
}

/// Runs `work` for each item, at most `limit` at a time.
func forEach<T: Sendable>(_ items: [T], limit: Int, _ work: @escaping @Sendable (T) async -> Void) async {
    await withTaskGroup(of: Void.self) { group in
        var next = 0
        for _ in 0..<min(limit, items.count) {
            let item = items[next]; next += 1
            group.addTask { await work(item) }
        }
        while await group.next() != nil, next < items.count {
            let item = items[next]; next += 1
            group.addTask { await work(item) }
        }
    }
}

func slots(_ t: ModelTarget) -> Int { t.endpoint.kind == .lmstudio ? opts.parallel : opts.parallelRemote }

let currentCommit: String = {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["rev-parse", "--short", "HEAD"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}()

/// The options that shape a recorded run beyond its model and task (`StoredRun.config`).
let configFingerprint = "context=\(opts.context) max-tokens=\(opts.maxTokens ?? 4096) skills=\(opts.skills) "
    + "style=\(opts.promptStyle?.rawValue ?? "auto") prompt-dir=\(opts.promptDir?.path ?? "-") sandbox=\(opts.sandbox) "
    + "providers-ignore=\(opts.providersIgnore?.joined(separator: ",") ?? "-") no-train=\(opts.noTrain)"

if let set = opts.judgeSet {
    let store = runStore(set)
    let judges = opts.judges.map(target)
    guard !judges.isEmpty else { print("--judge needs --judges E:M,…"); exit(2) }
    let trialRuns = store.runs().filter { run in (opts.judgeTrials == "all" || run.trial == Int(opts.judgeTrials) ?? 1)
        && (opts.onlyModel.map { run.model.contains($0) } ?? true) }
    let all = opts.sample.map { Runner.sample(trialRuns, $0) } ?? trialRuns
    print("kurtkode-eval judge: \(all.count) runs × \(judges.count) judges × \(opts.judgePaths.count) paths in \(store.root.path)")
    final class Spent: @unchecked Sendable { let lock = NSLock(); var usd = 0.0 }
    let judgeSpent = Spent()
    let judging = SpendReservation(prior: 0.05)
    await withTaskGroup(of: Void.self) { group in
        for judge in judges {
            group.addTask {
                let label = judge.label
                let todo = all.flatMap { r in opts.judgePaths.sorted().map { (r, $0) } }.filter { r, path in
                    !store.judgments(of: r.id).contains { $0.outcome.judge == label && $0.outcome.path == path
                        && (!opts.rejudgeMissing || $0.outcome.verdict != nil) }
                }
                print("  \(label): \(todo.count) to judge")
                final class Count: @unchecked Sendable { let lock = NSLock(); var n = 0 }
                let done = Count()
                await forEach(todo.map { ($0.0.id, $0.1) }, limit: slots(judge)) { id, path in
                    guard let run = all.first(where: { $0.id == id }) else { return }
                    // --max-cost: no judgment starts that could take this process's judgments past it (list price),
                    // counting the judgments in flight (`SpendReservation`).
                    if let cap = opts.maxCost {
                        guard judging.tryStart(label, cap: cap, spent: judgeSpent.lock.withLock({ judgeSpent.usd })) else { return }
                    } else { judging.started(label) }
                    let o = await Runner.judgeStored(run, store: store, judge: judge, path: path, sandbox: opts.sandbox)
                    judging.finished(label, listPrice: o?.listPrice)
                    judgeSpent.lock.withLock { judgeSpent.usd += o?.listPrice ?? 0 }
                    let n = done.lock.withLock { done.n += 1; return done.n }
                    print("  [\(label) \(n)/\(todo.count)] \(id) (\(path)): " + (o?.verdict.map { "\($0)/3" } ?? "no verdict")
                          + " · gold \(run.gold.passed ? "pass" : "fail")")
                }
            }
        }
    }
    print("\n" + EvalReport.markdown(store) + String(format: "\njudgments' list price: $%.4f", judgeSpent.usd))
    exit(0)
}

guard !opts.models.isEmpty || !opts.switches.isEmpty else { print("give --models endpoint:model[,...] or --switch A>B (see --list)"); exit(2) }
let scenarios = Scenarios.named(opts.scenarios)
guard !scenarios.isEmpty else { print("no matching scenarios"); exit(2) }
if let style = opts.promptStyle, !PromptTemplates(overrides: opts.promptDir.map { [$0] } ?? []).has(style: style) {
    print("no style-\(style.rawValue).md template (in the defaults\(opts.promptDir.map { " or " + $0.path } ?? ""))"); exit(2)
}

func target(_ given: String) -> ModelTarget {
    // "#off": the same model with reasoning turned off (OpenRouter's reasoning.enabled = false).
    let off = given.hasSuffix("#off")
    let spec = off ? String(given.dropLast(4)) : given
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    let (epName, model) = parts.count == 2 ? (parts[0], parts[1]) : ("lmstudio", parts[0])
    guard let e = endpoint(named: epName) else { print("no endpoint named \(epName) (see --list)"); exit(2) }
    var t = ModelTarget(endpoint: e, model: model, apiKey: apiKey(for: e))
    if !opts.profiles { t.profile = ModelProfile(endpointID: e.id, model: model) }
    t.promptStyle = opts.promptStyle
    t.promptDir = opts.promptDir
    t.skills = opts.skills
    if let ignore = opts.providersIgnore { t.profile.providers = ProviderRouting(ignore: ignore) }
    if off { t.reasoning = ["enabled": false] }
    // Only providers that don't train on prompts, and that take every parameter sent (tools).
    if opts.noTrain, e.baseURL.host()?.contains("openrouter") == true {
        var p = t.profile.providers ?? ProviderRouting()
        p.dataCollection = "deny"
        p.requireParameters = true
        t.profile.providers = p
    }
    if let spec = opts.fallback {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let (fe, fm) = parts.count == 2 ? (parts[0], parts[1]) : ("lmstudio", parts[0])
        guard let f = endpoint(named: fe) else { print("no endpoint named \(fe) for --fallback"); exit(2) }
        t.fallback = .init(endpoint: f, model: fm, apiKey: apiKey(for: f))
    }
    return t
}
var targets: [ModelTarget] = opts.models.map(target).flatMap { t in
    opts.subagents.flatMap { on in
        (on ? opts.subagentPool : [false]).flatMap { pooled in
            (on ? opts.kkDelegation : [false]).map { kk in
                var t = t
                t.subagents = on
                // Subagents on another model, and a parent told to delegate (cost-floor stage 4): with subagents on only.
                if on, let spec = opts.subagentModel { t.subagentTarget = SubagentTargetBox(target(spec)) }
                // The pool on the parent's own endpoint and key (Claude through OpenRouter, say): one key, read once.
                if pooled { let key = t.apiKey; t.subagentPool = SubagentPoolBox(pool: .shipped, endpoints: [t.endpoint], key: { _ in key }) }
                if on { t.forceDelegation = opts.forceDelegation; t.delegationTokens = opts.delegationTokens }
                t.kurtkodeDelegation = kk
                return t
            }
        }
    }
}


/// Makes a target ready: for a local LM Studio model, unload the others and load it (memory permitting).
/// Returns nil when it can't be used.
struct Loader: Sendable {
    let context: Int
    let manage: Bool

    func prepare(_ t: ModelTarget) async -> ModelTarget? {
        var t = t
        guard t.endpoint.kind == .lmstudio, t.endpoint.isLocal else {
            t.contextLength = t.endpoint.manualContextLength ?? context
            return t
        }
        let info = (try? await LMStudioService(endpoint: t.endpoint).models())?.first { $0.id == t.model }
        guard let info else { print("  \(t.model) not found on LM Studio"); return nil }
        let ctx = min(context, info.maxContextLength ?? context)
        if manage {
            let lms = LMSCLI()
            try? await lms.unloadAll()
            try? await Task.sleep(for: .seconds(2))
            let free = MemoryStatus.current().freePercent
            guard free >= 30 else { print("  only \(free)% memory free; not loading \(t.model)"); return nil }
            print("  loading \(t.model) with \(ctx) context, 1 slot (free memory \(free)%)")
            do { try await lms.load(t.model, contextLength: ctx, parallel: 1) }
            catch { print("  load failed: \(error.localizedDescription)"); return nil }
        }
        t.contextLength = ctx
        return t
    }
}
let loader = Loader(context: opts.context, manage: opts.manageLMS)
var results: [TrialResult] = []

/// What this run has spent on paid endpoints. The server's own account of a key's usage (OpenRouter's
/// GET /key) is the authority; the costs reported with each reply are the fallback, and miss compaction.
actor Spend {
    private var start: [UUID: Double] = [:]
    private var latest: [UUID: Double] = [:]
    private var names: [UUID: String] = [:]

    /// Credits used so far on the key, or nil when the server doesn't say.
    static func keyUsage(_ t: ModelTarget) async -> Double? {
        guard let key = t.apiKey else { return nil }
        var request = URLRequest(url: t.endpoint.baseURL.appending(path: "key"), timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let d)? = o["data"], case .number(let used)? = d["usage"] else { return nil }
        return used
    }

    private var lastRefresh = Date.distantPast

    /// At most every 30 seconds, once per endpoint.
    func refreshSoon(_ targets: [ModelTarget]) async {
        guard Date().timeIntervalSince(lastRefresh) >= 30 else { return }
        lastRefresh = Date()
        var seen = Set<UUID>()
        await refresh(targets.filter { seen.insert($0.endpoint.id).inserted })
    }

    func refresh(_ targets: [ModelTarget]) async {
        for t in targets where t.apiKey != nil {
            guard let used = await Spend.keyUsage(t) else { continue }
            if start[t.endpoint.id] == nil { start[t.endpoint.id] = used }
            latest[t.endpoint.id] = used
            names[t.endpoint.id] = t.endpoint.name
        }
    }

    /// USD spent since the run started, by endpoint name.
    func byEndpoint() -> [String: Double] {
        Dictionary(start.map { (id, s) in (names[id] ?? "?", (latest[id] ?? s) - s) }, uniquingKeysWith: +)
    }
    func total() -> Double { byEndpoint().values.reduce(0, +) }
    /// Each key's total usage as last read, by endpoint name.
    func usage() -> [String: Double] { Dictionary(latest.map { (names[$0.key] ?? "?", $0.value) }, uniquingKeysWith: max) }
    func overKeyLimit(_ limit: Double?) -> Bool { limit.map { l in latest.values.contains { $0 >= l } } ?? false }
}
let spend = Spend()
let paidTargets: [ModelTarget] = {
    var seen = Set<UUID>()
    return (targets + opts.switches.flatMap { [target($0.0), target($0.1)] } + opts.judges.map(target))
        .filter { $0.apiKey != nil && seen.insert($0.endpoint.id).inserted }
}()
await spend.refresh(paidTargets)
for (name, used) in await spend.usage().sorted(by: { $0.key < $1.key }) { print("key usage at start: \(name) $\(fmt(used, 4))") }

/// True when the cap is reached, by the server's account or the per-reply costs, whichever is higher.
func overBudget(_ done: [TrialResult]) async -> Bool {
    await spend.refresh(paidTargets)
    if await spend.overKeyLimit(opts.keyLimit) { print("  a key's usage reached the $\(fmt(opts.keyLimit ?? 0, 2)) limit; not starting more trials"); return true }
    guard let cap = opts.maxCost else { return false }
    let reported = done.compactMap(\.reportedCost).reduce(0, +)
    let spent = opts.ownCost ? reported : max(await spend.total(), reported)
    if spent >= cap { print("  spend $\(fmt(spent, 4)) reached the $\(fmt(cap, 2)) cap; not starting more trials") }
    return spent >= cap
}
// The live cascade (REAL_TASKS_PLAN.md "Cascade, live"): each task a main run on the one --models target in a CLI
// session; when the session offers escalation, the offer is taken and --cascade's model picks the request up.
if let spec = opts.cascade, let ids = opts.bank, let set = opts.record {
    let tasks = TaskBank.named(ids)
    guard let cheap = targets.first, targets.count == 1, !tasks.isEmpty else { print("--cascade needs one --models target and bank tasks"); exit(2) }
    if !TaskBank.unknown(ids).isEmpty { print("no bank tasks named \(TaskBank.unknown(ids).joined(separator: ", ")) (see --list)"); exit(2) }
    let strong = target(spec)
    let root = runStore(set).root
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let support = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash/kurtkode-test-cascade-\(UUID().uuidString.prefix(8))")
    let userSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "kurtkode")
    do { try Cascade.makeSupport(at: support, userSupport: userSupport, cheap: cheap, strong: strong) }
    catch { print("cascade setup failed: \(error)"); exit(1) }
    @Sendable func folder(_ task: String, _ trial: Int) -> URL { root.appending(path: "\(task)__t\(trial)") }
    let todo = tasks.flatMap { t in (1...opts.trials).map { (t.id, $0) } }
        .filter { !FileManager.default.fileExists(atPath: folder($0.0, $0.1).appending(path: "run.json").path) }
    print("kurtkode-eval cascade: \(cheap.label) → \(strong.label), \(todo.count) runs to record into \(root.path); sessions in \(support.path)")
    final class Tally: @unchecked Sendable { let lock = NSLock(); var spent = 0.0, inFlight = 0, n = 0, cheapPass = 0, finalPass = 0, offers = 0, capped = false }
    let tally = Tally()
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    await forEach(todo, limit: max(1, opts.parallelRemote)) { id, trial in
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        // Each run in flight is expected to cost what the runs so far did on average (or $0.30 before any).
        let over: Bool = tally.lock.withLock {
            guard let cap = opts.maxCost else { return false }
            let mean = tally.n > 0 ? tally.spent / Double(tally.n) : 0.30
            if tally.capped || tally.spent + mean * Double(tally.inFlight + 1) > cap { tally.capped = true; return true }
            tally.inFlight += 1
            return false
        }
        if over { return }
        let r = await Cascade.run(task, cheap: cheap, strong: strong, trial: trial, support: support, commit: currentCommit,
                                  contextLength: opts.context, maxTokens: opts.maxTokens ?? 16_384, log: { _ in })
        let line: String = tally.lock.withLock {
            tally.inFlight -= 1
            tally.spent += r.listPrice
            tally.n += 1
            if r.cheapGold.passed { tally.cheapPass += 1 }
            if r.finalPassed { tally.finalPass += 1 }
            if !r.reasons.isEmpty { tally.offers += 1 }
            return "  [\(tally.n)/\(todo.count), cheap \(tally.cheapPass), final \(tally.finalPass), \(tally.offers) offers, $\(fmt(tally.spent, 2))] "
        }
        let f = folder(id, trial)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        if let data = try? enc.encode(r) { try? data.write(to: f.appending(path: "run.json"), options: .atomic) }
        print(line + "\(id) #\(trial): " + (r.infra.map { "INFRA (\($0.prefix(100)))" } ?? "")
              + "\(r.cheapGold.passed ? "PASS" : "FAIL") \(r.cheapStop) \(r.cheapSteps) steps $\(fmt(r.cheapListPrice ?? 0, 4))"
              + (r.reasons.isEmpty ? "" : " → \(r.reasons.joined(separator: "; ").prefix(120)) → "
                 + "\(r.strongGold?.passed == true ? "PASS" : "FAIL") \(r.strongStop ?? "-") \(r.strongSteps ?? 0) steps $\(fmt(r.strongListPrice ?? 0, 4))"))
    }
    if tally.capped { print("  spending cap $\(fmt(opts.maxCost ?? 0, 2)) reached: not every run started") }
    await spend.refresh(paidTargets)
    for (name, used) in await spend.usage().sorted(by: { $0.key < $1.key }) { print("key usage at end: \(name) $\(fmt(used, 4))") }
    exit(0)
}
if let ids = opts.bank, let set = opts.record {
    let tasks = TaskBank.named(ids)
    guard !tasks.isEmpty else { print("no matching bank tasks (see --list)"); exit(2) }
    if !TaskBank.unknown(ids).isEmpty { print("no bank tasks named \(TaskBank.unknown(ids).joined(separator: ", ")) (see --list)"); exit(2) }
    let store = runStore(set)
    try? FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
    let stored = store.runs()
    let known = Set(stored.map(\.id))
    // Resuming a set: its runs must have been recorded with these options, or the set would mix configurations
    // (BUG_HUNT_2026-11-02.md item 47). Runs from before fingerprints are assumed to match, with a note.
    let fingerprint = configFingerprint
    let mismatched = stored.filter { $0.config != nil && $0.config != fingerprint }
    if let first = mismatched.first {
        print("\(mismatched.count) runs in \(store.root.path) were recorded with other options:\n  theirs: \(first.config!)\n  these:  \(fingerprint)\n"
              + "record into a new set, or give the same options")
        exit(2)
    }
    let unmarked = stored.filter { $0.config == nil && $0.degradation == nil }.count
    if unmarked > 0 { print("  \(unmarked) runs predate option fingerprints; resuming assumes they used these options") }
    // Two labels that make the same folder name would read each other's runs as done.
    for t in targets {
        let other = stored.first { $0.model != t.label && RunStore.id(task: $0.task, model: t.label, trial: $0.trial) == $0.id }
        if let other { print("\(t.label) and \(other.model) share run folder names in \(store.root.path); record them apart"); exit(2) }
    }
    print("kurtkode-eval record: \(targets.count) models × \(tasks.count) tasks × \(opts.trials) trials into \(store.root.path)")
    /// What this process has recorded, at list price (the key's usage is the other measure; the higher counts).
    final class Spent: @unchecked Sendable { let lock = NSLock(); var list = 0.0 }
    let spentHere = Spent()
    let flight = SpendReservation()
    /// Starts a run of `model` unless it could take spending past the cap: what was spent, plus the expected cost of
    /// the runs in flight and of this one, checked and reserved in one step (`SpendReservation.tryStart`). False: not
    /// started.
    @Sendable func admit(_ model: String) async -> Bool {
        await spend.refreshSoon(paidTargets)
        if await spend.overKeyLimit(opts.keyLimit) { return false }
        guard let cap = opts.maxCost else { flight.started(model); return true }
        let mine = spentHere.lock.withLock { spentHere.list }
        let spent = opts.ownCost ? mine : max(await spend.total(), mine)
        return flight.tryStart(model, cap: cap, spent: spent)
    }
    final class Stop: @unchecked Sendable { let lock = NSLock(); var capped = false }
    let stop = Stop()
    // Cheapest first (the models file's order), a few models at a time.
    let ordered = targets
    await forEach(ordered.map(\.label), limit: opts.modelsAtOnce > 0 ? opts.modelsAtOnce : max(1, ordered.count)) { label in
        guard let base = ordered.first(where: { $0.label == label }) else { return }
            do {
                guard let target = await loader.prepare(base) else { return }
                let todo = tasks.flatMap { t in (1...opts.trials).map { (t, $0) } }
                    .filter { !known.contains(RunStore.id(task: $0.0.id, model: target.label, trial: $0.1)) }
                print("  \(target.label): \(todo.count) runs to record")
                final class Count: @unchecked Sendable { let lock = NSLock(); var n = 0, pass = 0, fails = 0, infra = 0 }
                let done = Count()
                await forEach(todo.map { ($0.0.id, $0.1) }, limit: slots(target)) { id, trial in
                    guard let task = tasks.first(where: { $0.id == id }) else { return }
                    // Screening: a model that has failed enough to be out isn't run further.
                    if opts.stopAfterFailures > 0, done.lock.withLock({ done.fails >= opts.stopAfterFailures || done.infra >= opts.stopAfterFailures }) { return }
                    if stop.lock.withLock({ stop.capped }) { return }
                    guard await admit(target.label) else {
                        if !stop.lock.withLock({ defer { stop.capped = true }; return stop.capped }) {
                            print("  spending cap $\(fmt(opts.maxCost ?? 0, 2)) or key limit reached: no more runs start")
                        }
                        return
                    }
                    let rs = await Runner.recordBank(task, on: target, trial: trial, store: store, degrade: opts.degrade && trial == 1,
                                                     commit: currentCommit, config: fingerprint,
                                                     limits: TurnLimits(maxTokens: opts.maxTokens ?? 4096, wallClock: 300),
                                                     sandbox: opts.sandbox)
                    flight.finished(target.label, listPrice: rs.first?.listPrice)
                    guard let r = rs.first else { print("  [\(target.label)] \(id) #\(trial): not recorded"); return }
                    spentHere.lock.withLock { spentHere.list += r.listPrice ?? 0 }
                    let (n, p) = done.lock.withLock {
                        done.n += 1
                        if r.infra != nil { done.infra += 1 } else if r.gold.passed { done.pass += 1 } else { done.fails += 1 }
                        return (done.n, done.pass)
                    }
                    print("  [\(target.label) \(n)/\(todo.count), \(p) passed] \(id) #\(trial): "
                          + (r.infra != nil ? "INFRA (\(r.infra!.prefix(80)))" : r.gold.passed ? "PASS" : "FAIL") + " "
                          + String(format: "%.0fs", r.seconds) + " \(r.steps) steps" + (r.listPrice.map { String(format: " $%.4f", $0) } ?? "")
                          + (rs.count > 1 ? " · \(rs.count - 1) degraded" : ""))
                }
            }
    }
    print("\n" + EvalReport.markdown(store))
    exit(0)
}

if let ids = opts.bank {
    let tasks = TaskBank.named(ids)
    guard !tasks.isEmpty else { print("no matching bank tasks (see --list)"); exit(2) }
    if !TaskBank.unknown(ids).isEmpty { print("no bank tasks named \(TaskBank.unknown(ids).joined(separator: ", ")) (see --list)"); exit(2) }
    let judges = opts.judges.map(target)
    print("kurtkode-eval bank: \(targets.count) models × \(tasks.count) tasks × \(opts.trials) trials; judges: "
          + (judges.isEmpty ? "none" : judges.map(\.label).joined(separator: ", ") + " (" + opts.judgePaths.sorted().joined(separator: ", ") + ")"))
    var bank: [BankResult] = []
    for base in targets {
        print("\n=== \(base.label)")
        guard let target = await loader.prepare(base) else { continue }
        for task in tasks {
            for trial in 1...opts.trials {
                if let cap = opts.maxCost {
                    let spent = bank.compactMap(\.listPrice).reduce(0, +) + bank.flatMap(\.judges).compactMap(\.listPrice).reduce(0, +)
                    if spent >= cap { print("  list price $\(fmt(spent, 4)) reached the $\(fmt(cap, 2)) cap; not starting more"); break }
                }
                print("  [\(task.id) #\(trial)]")
                let r = await Runner.runBank(task, on: target, trial: trial, judges: judges, paths: opts.judgePaths, degrade: opts.degrade,
                                             sandbox: opts.sandbox, log: { print($0) })
                bank.append(r)
                print("  \(r.gold.passed ? "PASS" : "FAIL") · \(fmt(r.seconds))s · \(r.steps) steps · \(r.toolCalls) calls · stop \(r.stop)"
                      + (r.checks.problems.isEmpty ? "" : " · checks: " + r.checks.problems.joined(separator: "; ")))
                for n in r.gold.notes { print("    - \(n)") }
            }
        }
    }
    print("\n=== Gold passes by model and kind")
    let kinds = Array(Set(bank.map(\.kind))).sorted()
    print("model".padding(toLength: 40, withPad: " ", startingAt: 0) + kinds.map { $0.padding(toLength: 12, withPad: " ", startingAt: 0) }.joined() + "all")
    for m in Array(Set(bank.map(\.model))).sorted() {
        var row = m.padding(toLength: 40, withPad: " ", startingAt: 0)
        for k in kinds {
            let rs = bank.filter { $0.model == m && $0.kind == k }
            row += (rs.isEmpty ? "-" : "\(rs.filter(\.gold.passed).count)/\(rs.count)").padding(toLength: 12, withPad: " ", startingAt: 0)
        }
        let all = bank.filter { $0.model == m }
        print(row + "\(all.filter(\.gold.passed).count)/\(all.count)")
    }
    let calibration = JudgeCalibrationRow.rows(bank)
    print("\n=== Judges against gold (agreement · failures caught · passes failed · claimed unchecked checks)")
    func pct(_ x: Double?) -> String { x.map { fmt($0 * 100) + "%" } ?? "–" }
    for c in calibration {
        print("  " + "\(c.judge) (\(c.path))".padding(toLength: 52, withPad: " ", startingAt: 0)
              + "\(c.verdicts)/\(c.runs) verdicts · agree \(pct(c.agreement)) · caught \(pct(c.failureRecall)) · "
              + "false alarms \(pct(c.falseAlarms)) · unconfirmed \(c.unconfirmedClaims)"
              + (c.listPrice.map { " · $\(fmt($0, 4))" } ?? ""))
    }
    if let out = opts.out {
        struct BankReport: Encodable { let date: Date; let results: [BankResult]; let calibration: [JudgeCalibrationRow] }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let slim = opts.transcripts == nil ? bank.map { var r = $0; r.transcript = nil; return r } : bank
        try enc.encode(BankReport(date: Date(), results: slim, calibration: calibration)).write(to: URL(fileURLWithPath: out))
        print("\nwrote \(out)")
    }
    exit(bank.isEmpty ? 1 : 0)
}

print("kurtkode-eval: \(targets.count) models × \(scenarios.count) scenarios × \(opts.trials) trials")

for base in targets {
    print("\n=== \(base.label)  [history: \(base.profile.history.toolCallIDs.rawValue)\(base.profile.history.mergeConsecutive ? ", merge" : "")]")
    guard let target = await loader.prepare(base) else { continue }

    for scenario in scenarios {
        for trial in 1...opts.trials {
            if await overBudget(results) { break }
            print("  [\(scenario.id) #\(trial)]")
            let r = await Runner.run(scenario, on: target, trial: trial, sandbox: opts.sandbox, log: { print($0) })
            results.append(r)
            print("  \(r.check.passed ? "PASS" : "FAIL") score \(fmt(r.check.score, 2)) · \(fmt(r.seconds))s · \(r.steps) steps · "
                  + "\(r.toolCalls) calls · \(r.toolErrors) errors · \(r.compactions) compactions · peak \(r.peakPromptTokens) tok · "
                  + "stop \(r.stop) · min free \(r.minFreeMemoryPercent)% · \(r.promptTokens ?? 0)+\(r.completionTokens ?? 0) tok"
                  + (r.reportedCost.map { " · $\(fmt($0, 4))" } ?? ""))
            for n in r.check.notes { print("    - \(n)") }
            if !r.check.passed, !r.finalExcerpt.isEmpty {
                print("    final: " + r.finalExcerpt.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(300))
            }
        }
    }
}

// Switches: A starts, B finishes, in one conversation.
for (a, b) in opts.switches {
    let first = target(a), second = target(b)
    print("\n=== switch \(first.label) → \(second.label), after \(opts.switchAfter) steps")
    for scenario in scenarios {
        for trial in 1...opts.trials {
            if await overBudget(results) { break }
            print("  [\(scenario.id) #\(trial)]")
            guard let firstReady = await loader.prepare(first) else { continue }
            let r = await Runner.runSwitch(scenario, first: firstReady, second: second, switchAfter: opts.switchAfter,
                                           trial: trial, sandbox: opts.sandbox, between: { t in await loader.prepare(t) }, log: { print($0) })
            results.append(r)
            print("  \(r.check.passed ? "PASS" : "FAIL") score \(fmt(r.check.score, 2)) · \(fmt(r.seconds))s · \(r.steps) steps · "
                  + "\(r.toolCalls) calls · \(r.toolErrors) errors · \(r.compactions) compactions · stop \(r.stop) · "
                  + "\(r.promptTokens ?? 0)+\(r.completionTokens ?? 0) tok" + (r.reportedCost.map { " · $\(fmt($0, 4))" } ?? ""))
            for n in r.check.notes { print("    - \(n)") }
            if !r.check.passed, !r.finalExcerpt.isEmpty {
                print("    final: " + r.finalExcerpt.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(300))
            }
        }
    }
}

// Summary table: pass rate per model × scenario.
print("\n=== Summary (passes / trials, mean score, mean seconds)")
let models = Array(Set(results.map(\.model))).sorted()
let header = "model".padding(toLength: 44, withPad: " ", startingAt: 0) + scenarios.map { $0.id.padding(toLength: 22, withPad: " ", startingAt: 0) }.joined()
print(header)
for m in models {
    var row = m.padding(toLength: 44, withPad: " ", startingAt: 0)
    for s in scenarios {
        let rs = results.filter { $0.model == m && $0.scenario == s.id }
        guard !rs.isEmpty else { row += "-".padding(toLength: 22, withPad: " ", startingAt: 0); continue }
        let cell = "\(rs.filter(\.check.passed).count)/\(rs.count) \(fmt(rs.map(\.check.score).reduce(0, +) / Double(rs.count), 2)) \(fmt(rs.map(\.seconds).reduce(0, +) / Double(rs.count)))s"
        row += cell.padding(toLength: 22, withPad: " ", startingAt: 0)
    }
    print(row)
}

// Delegation decisions: how often each model delegated, against what a good parent does (EVAL_PLAN.md E6).
if scenarios.contains(where: { $0.expectDelegation != nil }) {
    print("\n=== Delegation (runs that delegated / trials; expected in brackets)")
    print("model".padding(toLength: 44, withPad: " ", startingAt: 0)
          + scenarios.map { $0.id.padding(toLength: 22, withPad: " ", startingAt: 0) }.joined())
    for m in models {
        var row = m.padding(toLength: 44, withPad: " ", startingAt: 0)
        for s in scenarios {
            let rs = results.filter { $0.model == m && $0.scenario == s.id }
            let cell = rs.isEmpty ? "-" : "\(rs.filter { ($0.subagentRuns ?? 0) > 0 }.count)/\(rs.count)"
                + (s.expectDelegation.map { $0 ? " [yes]" : " [no]" } ?? "")
            row += cell.padding(toLength: 22, withPad: " ", startingAt: 0)
        }
        print(row)
    }
}

// Give the server a moment to account for the last requests.
if !paidTargets.isEmpty { try? await Task.sleep(for: .seconds(5)) }
await spend.refresh(paidTargets)
let spentByEndpoint = await spend.byEndpoint()
let reportedTotal = results.compactMap(\.reportedCost).reduce(0, +)
if !paidTargets.isEmpty {
    print("\n=== Spend")
    for (name, usd) in spentByEndpoint.sorted(by: { $0.key < $1.key }) { print("  \(name): $\(fmt(usd, 4)) (key usage)") }
    print("  reported with replies: $\(fmt(reportedTotal, 4)) (excludes compaction summaries)")
}

if let dir = opts.transcripts {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    for r in results {
        let name = "\(r.scenario)__\(r.model)__\(r.trial)".map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        try? enc.encode(r.transcript ?? []).write(to: URL(fileURLWithPath: dir).appending(path: String(name) + ".json"))
    }
    print("wrote transcripts to \(dir)")
}
results = results.map { var r = $0; r.transcript = nil; return r }

if let out = opts.out {
    struct Report: Encodable {
        let date: Date; let commit: String; let context: Int
        let spendByEndpoint: [String: Double]; let reportedCost: Double
        let results: [TrialResult]
    }
    let commit = (try? String(contentsOfFile: ".git/HEAD", encoding: .utf8)).map { _ in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["rev-parse", "--short", "HEAD"]
        let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } ?? "unknown"
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    try enc.encode(Report(date: Date(), commit: commit, context: opts.context,
                          spendByEndpoint: spentByEndpoint, reportedCost: reportedTotal, results: results))
        .write(to: URL(fileURLWithPath: out))
    print("\nwrote \(out)")
}
