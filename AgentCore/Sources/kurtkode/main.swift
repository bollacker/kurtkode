import AgentCore
import AppKit
import Darwin
import Foundation
import KurtkodeCLI

// kurtkode: the agent in a terminal. See CLIOptions.usage.

setvbuf(stdout, nil, _IONBF, 0)
// A reader that goes away (`kurtkode -p … | head -3`) makes writes fail with EPIPE instead of killing the program on
// the spot: the renderer's writes then exit, so `atexit` stops running commands and MCP servers.
signal(SIGPIPE, SIG_IGN)

/// Messages to stderr, checked when it's a terminal (an MCP server's or an endpoint's error text can carry escapes).
let writeErr = Renderer.write(to: .standardError)
@Sendable func warn(_ message: String) { writeErr("kurtkode: \(message)\n") }

func fail(_ message: String, code: Int32 = 1) -> Never {
    warn(message)
    exit(code)
}

// kurtkode inspect | replay | export: the Debug window's views of a recorded session (no agent run).
// A subcommand after leading options (`kurtkode -C ~/proj inspect`) counts too: it isn't a prompt.
let rawArguments = CLIOptions.subcommandFirst(Array(CommandLine.arguments.dropFirst()), names: SetupCommands.names.union(DebugCommands.names))
    ?? Array(CommandLine.arguments.dropFirst())
if let first = rawArguments.first, SetupCommands.names.contains(first) {
    exit(await SetupCommands.run(rawArguments, settings: AppSettings()) { Renderer.write(to: .standardOutput)($0) })
}
if let first = rawArguments.first, DebugCommands.names.contains(first) {
    var dir = FileManager.default.currentDirectoryPath
    if let i = rawArguments.firstIndex(where: { $0 == "-C" || $0 == "--cwd" }), i + 1 < rawArguments.count {
        dir = (rawArguments[i + 1] as NSString).expandingTildeInPath
    }
    exit(await DebugCommands.run(rawArguments, settings: AppSettings(), cwd: URL(fileURLWithPath: dir)) { Renderer.write(to: .standardOutput)($0) })
}

let options: CLIOptions
do { options = try CLIOptions.parse(rawArguments) }
catch { fail("\(error)", code: 2) }
if options.help { print(CLIOptions.usage); exit(0) }
if options.version { print("kurtkode 0.1"); exit(0) }

var startFolder = URL(fileURLWithPath: options.cwd.map { ($0 as NSString).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath)
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: startFolder.path, isDirectory: &isDir), isDir.boolValue else { fail("\(startFolder.path) isn't a folder", code: 2) }
if let name = options.worktree {
    do { startFolder = URL(fileURLWithPath: try await GitRepo(root: startFolder).addWorktree(name: name).path, isDirectory: true) }
    catch { fail("couldn't make the worktree: \(error.localizedDescription)") }
}
let cwd = startFolder

var settings = AppSettings()
do { try settings.addLaunchEndpoints(options.extraEndpoints.map { Endpoint.launchOnly(name: $0.name, url: $0.url) }) }
catch { fail("\(error)", code: 2) }
let interactive = !options.printMode
let session: CLISession
do { session = try await CLISession(settings: settings, workspace: cwd, options: options) }
catch { fail("\(error)") }

if options.listSessions {
    let list = (try? await session.sessions()) ?? []
    if list.isEmpty { print("No sessions in \(cwd.path).") }
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm"
    for s in list { print(TerminalText.visible("\(s.id.uuidString.prefix(8).lowercased())  \(fmt.string(from: s.updatedAt))  \(s.messageCount) msgs  \(s.title)")) }
    exit(0)
}

/// Project files for @ completion, listed in the background (refreshed after each turn).
final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String] = []
    var all: [String] { lock.withLock { files } }
    func refresh(_ workspace: Workspace) { Task { let f = await workspace.files(limit: 20_000); lock.withLock { files = f } } }
}
let fileIndex = FileIndex()
fileIndex.refresh(session.workspace)
let useLiveScreen = interactive && !options.plain && TerminalUI.available
let historyFile = settings.support.appending(path: "cli-history.jsonl")
let commandNames = SlashCommands.all(workspace: cwd, builtinSkills: session.builtinSkills).map(\.name) + CLICommands.names
let editor = LineEditor(history: interactive ? InputHistory(fileURL: settings.support.appending(path: "cli-history.jsonl")) : nil,
                        completer: LineEditor.completions(commands: { commandNames }, files: { fileIndex.all }))

/// The live screen, once it's started: output and questions go through it, so nothing lands in the middle of the frame.
final class Live: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TerminalUI?
    var ui: TerminalUI? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
let live = Live()

let writeOut = Renderer.write(to: .standardOutput)

/// Output, wherever it's going now.
@Sendable func emit(_ text: String) {
    if let ui = live.ui { ui.put(text) } else { writeOut(text) }
}
@Sendable func say(_ text: String) { emit(text + "\n") }

/// Reads an entry off the cooperative pool (reading blocks). Answers to questions aren't kept in the history.
@Sendable func ask(_ prompt: String, card: String = "", remember: Bool = false, choices: QuestionChoices? = nil) async -> String? {
    if let ui = live.ui { return await ui.ask(prompt, card: card, choices: choices) }
    if !card.isEmpty { emit(card) }
    return await withCheckedContinuation { cont in
        DispatchQueue.global().async { cont.resume(returning: editor.read(prompt: prompt, remember: remember)) }
    }
}

/// Whether a question or an approval is being read (Ctrl-C then ends the read, so the next line typed isn't taken
/// as its answer).
final class PromptReading: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    var isActive: Bool { lock.withLock { active > 0 } }
    func read(_ prompt: String, card: String = "", choices: QuestionChoices? = nil) async -> String? {
        lock.withLock { active += 1 }
        defer { lock.withLock { active -= 1 } }
        return await ask(prompt, card: card, choices: choices)
    }
}
let promptReading = PromptReading()

// MARK: Approvals at the terminal

let tty = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
@Sendable func bold(_ s: String) -> String { tty ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
@Sendable func colorDiff(_ line: Substring) -> String {
    guard tty else { return String(line) }
    if line.hasPrefix("+"), !line.hasPrefix("+++") { return "\u{1B}[32m\(line)\u{1B}[0m" }
    if line.hasPrefix("-"), !line.hasPrefix("---") { return "\u{1B}[31m\(line)\u{1B}[0m" }
    if line.hasPrefix("@@") { return "\u{1B}[36m\(line)\u{1B}[0m" }
    return String(line)
}

/// One approval prompt at a time: subagents running in parallel could ask together.
actor PromptTurns {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func take() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func give() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}
let promptTurns = PromptTurns()

if interactive {
    let bell = settings.run.notify ? "\u{7}" : ""      // an approval waits: ring the terminal's bell
    let askOne: @Sendable (ApprovalRequest) async -> ApprovalDecision = { request in
        var card = bell + "\n" + bold("? " + TerminalText.visible(request.summary)) + "\n"
        if let reason = request.reason { card += "  (asking because \(TerminalText.visible(reason)))\n" }
        switch request.preview {
        case .diff(let path, let unified, let isNew):
            card += "  " + (isNew ? "new file " : "") + TerminalText.visible(path) + "\n"
            let lines = TerminalText.visible(unified).split(separator: "\n", omittingEmptySubsequences: false)
            card += lines.prefix(80).map { "  " + colorDiff($0) }.joined(separator: "\n") + "\n"
            if lines.count > 80 { card += "  … \(lines.count - 80) more lines\n" }
        case .command(let command, let cwd):
            card += "  $ \(TerminalText.visible(command))\n  (in \(cwd == "." ? "the project root" : TerminalText.visible(cwd)))\n"
        case .call(let title, let arguments):
            card += "  \(TerminalText.visible(title))\n" + TerminalText.visible(arguments).split(separator: "\n").map { "  " + $0 }.joined(separator: "\n") + "\n"
        case nil:
            card += "  \(TerminalText.visible(request.call.arguments))\n"
        }
        let always = request.suggestedRule.map { "  [a] always allow \($0.displayName)" } ?? ""
        // Without the live screen a line typed ahead (or an Enter pressed while the reply streamed) sits in the
        // terminal's buffer and would answer this card unseen: drop it. The live screen reads keys itself.
        if live.ui == nil { ApprovalPrompt.flushTypedAhead() }
        // An empty answer asks again in every mode, and the end of input or Ctrl-C denies.
        return await ApprovalPrompt.decide(card: card + "  [y] yes  [n] no\(always)  or type what to do instead\n",
                                           suggestedRule: request.suggestedRule) { prompt, card in
            await promptReading.read(prompt, card: card)
        }
    }
    session.approve = { request in
        await promptTurns.take()
        let answer = await askOne(request)
        await promptTurns.give()
        return answer
    }
    /// One question at the prompt: on the live screen its options are a list under the composer, otherwise numbered.
    @Sendable func answer(to question: UserQuestion, place: String) async -> String? {
        var card = bell + "\n" + bold("? " + TerminalText.plain((question.header.isEmpty ? "" : "[\(question.header)] ") + question.question)) + place + "\n"
        let choices = live.ui != nil && !question.options.isEmpty ? QuestionChoices(question) : nil
        if choices == nil {
            for (i, option) in question.options.enumerated() {
                card += "  [\(i + 1)] \(TerminalText.oneLine(option.label))" + (i == question.recommended ? " (recommended)" : "") + "\n"
                if !option.description.isEmpty { card += "      \(TerminalText.oneLine(option.description))\n" }
            }
            card += question.options.isEmpty ? "  Type your answer.\n"
                : question.multiple ? "  Pick one or more (1,3), or type your own answer.\n" : "  Pick one, or type your own answer.\n"
        }
        var answer: String?
        while answer == nil, !Task.isCancelled, let typed = await promptReading.read("  › ", card: card, choices: choices) {
            card = ""
            answer = question.answer(fromTyped: typed)
        }
        // The list goes with the question: the scrollback keeps what was picked.
        if let answer, live.ui != nil { say("  → " + answer) }
        return answer
    }
    session.askUser = { questions in
        await promptTurns.take()
        var answers: [String?] = []
        for (i, question) in questions.enumerated() {
            // Skipping one skips the rest, like the app's card.
            guard let answer = await answer(to: question, place: questions.count > 1 ? "  (\(i + 1) of \(questions.count))" : "") else { break }
            answers.append(answer)
        }
        await promptTurns.give()
        return answers + Array(repeating: nil, count: questions.count - answers.count)
    }
    session.presentPlan = { proposal in
        await promptTurns.take()
        var card = bell + "\n" + bold("Plan") + (proposal.file.map { "  (saved in \($0.path))" } ?? "") + "\n\n" + TerminalText.plain(proposal.plan) + "\n\n"
        card += "  [1] approve, accept edits   [2] approve, full auto   [3] revise (say what to change)   [4] reject\n"
        var decision: PlanDecision?
        while decision == nil, !Task.isCancelled, let typed = await promptReading.read("  › ", card: card) {
            card = ""
            decision = PlanDecision.parse(typed)
            if case .revise(let feedback)? = decision, feedback.isEmpty {
                say("  What should change?")
                let more = await promptReading.read("  › ")?.trimmingCharacters(in: .whitespaces) ?? ""
                decision = more.isEmpty ? nil : .revise(more)
            }
        }
        await promptTurns.give()
        return decision ?? .reject(nil)
    }
}

// OpenRouter's records of earlier replies (they lag by minutes): checked in the background, quietly.
if interactive {
    let store = settings.sessionStore, s = settings
    Task.detached(priority: .utility) {
        await CostReconciler.run(store: store, since: Date().addingTimeInterval(-30 * 86_400), client: { id in
            s.endpoint(id).flatMap { e in s.apiKey(for: e).map { ChatClient(endpoint: e, apiKey: $0) } }
        })
    }
}

// MARK: MCP servers

if options.mcp {
    let waiting = await session.startMCP()
    for s in waiting {
        if interactive {
            print(TerminalText.visible("This project's .mcp.json wants to start the MCP server \"\(s.entry.name)\": \(s.entry.config.displayCommand)"))
            for line in s.entry.config.approvalDetails { print(TerminalText.visible("  " + line)) }
            print(s.entry.config.isHTTP
                  ? "It's a remote server: the agent's calls to its tools would send their arguments to \(URL(string: s.entry.config.url ?? "")?.host() ?? "it")."
                  : "It would run as a program on this Mac, outside the sandbox.")
            if let a = await ask("Start it? [y/N] "), ["y", "yes"].contains(a.lowercased()) {
                do { try await session.approveMCP(s.entry.name) } catch { print("  couldn't start it: \(error.localizedDescription)") }
            }
        } else {
            warn("skipping the project's MCP server \(s.entry.name) (not approved yet; approve it in the app or in an interactive kurtkode)")
        }
    }
    if let hub = session.hub {
        for s in await hub.statusList {
            if case .failed(let why) = s.state { warn("MCP server \(s.entry.name) failed: \(why)") }
        }
    }
}

// MARK: Hooks

_ = session.loadHooks()
if let problem = session.hookProblem { warn(problem) }
if let pending = session.pendingHooks {
    if interactive {
        print("This project's .kurtkode/settings.json has hooks, commands that would run outside the sandbox as the agent works:")
        for c in pending.commands { print(TerminalText.visible("  \(c)")) }
        if let a = await ask("Allow them? [y/N] "), ["y", "yes"].contains(a.lowercased()) {
            do { try session.approveHooks() } catch { print("  couldn't save that: \(error.localizedDescription)") }
        }
    } else {
        warn("skipping the project's hooks (not approved yet; approve them in the app or an interactive kurtkode)")
    }
}

// MARK: Permission rules

_ = session.loadPermissionRules()
if let problem = session.rulesProblem { warn(problem) }
if let pending = session.pendingRules {
    if interactive {
        print("This project's settings allow these without asking (its deny and ask rules already apply):")
        for r in pending.rules { print(TerminalText.visible("  \(r)")) }
        if let a = await ask("Allow them? [y/N] "), ["y", "yes"].contains(a.lowercased()) {
            do { try session.approveRules() } catch { print("  couldn't save that: \(error.localizedDescription)") }
        }
    } else {
        warn("not using the project's allow rules (not approved yet; approve them in the app or an interactive kurtkode)")
    }
}

// MARK: Ctrl-C stops the running turn

final class Running: @unchecked Sendable {
    let lock = NSLock()
    var task: Task<Void, Never>?
    var lastInterrupt = Date.distantPast
    /// When Ctrl-C last stopped a subagent: another within 2 s stops everything.
    var lastSubagentStop = Date.distantPast
}
let running = Running()
// Commands still running and MCP servers shouldn't outlive kurtkode, however it ends (short of SIGKILL).
atexit {
    RunningCommands.stopAll()
    StdioTransport.terminateAll()
}
let endSignals = [SIGTERM, SIGHUP].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { exit(128 + sig) }
    source.resume()
    return source
}
/// Ctrl-C: as a signal in plain mode, as a key on the live screen (raw mode sends it as one).
@Sendable func interrupted() {
    let task = running.lock.withLock { running.task }
    // While a subagent runs, the first Ctrl-C stops only it (the main agent carries on); the next stops everything.
    let subagents = session.subagentControl.running
    let now = Date()
    if task != nil, !subagents.isEmpty, now.timeIntervalSince(running.lock.withLock { running.lastSubagentStop }) > 2 {
        running.lock.withLock { running.lastSubagentStop = now }
        for id in subagents { session.subagentControl.stop(id) }
        say("\n(stopped the subagent; the agent carries on. Ctrl-C again stops everything.)")
    } else if let task {
        task.cancel()
        // A question or approval waiting at the prompt: end its read too.
        if promptReading.isActive {
            if let ui = live.ui { ui.cancelQuestion() } else { editor.interrupt() }
        }
    } else if interactive {
        let again = running.lock.withLock { () -> Bool in
            defer { running.lastInterrupt = now }
            return now.timeIntervalSince(running.lastInterrupt) < 2
        }
        if again {
            live.ui?.stop()
            print("")
            exit(130)
        }
        say("\n(Ctrl-C again to quit, or /exit)")
    } else {
        exit(130)
    }
}
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { interrupted() }
sigint.resume()

/// A mode picked during a run takes effect after it (a run keeps the mode it started with). An approved plan changes the
/// run's mode as it goes: that's where the next pick starts from, and one made before it is over.
final class ModePick: @unchecked Sendable {
    let lock = NSLock()
    var next: PermissionMode?
    var running: PermissionMode?
}
let pick = ModePick()
/// Shift-Tab between runs.
let modeCycle = ModeCycle { try? await session.setMode($0) }

/// Runs a send with Ctrl-C able to cancel it.
func runTurn(_ renderer: Renderer, _ work: @escaping @Sendable () async throws -> AgentStop?) async -> AgentStop? {
    session.onEvent = { event in
        if case .modeChanged(let mode) = event {
            pick.lock.withLock {
                pick.next = nil
                pick.running = mode
            }
        }
        renderer.handle(event)
        live.ui?.observe(event)
    }
    final class Result: @unchecked Sendable { var stop: AgentStop?; var error: Error? }
    let result = Result()
    let task = Task {
        do { result.stop = try await work() } catch { result.error = error }
    }
    running.lock.withLock { running.task = task }
    await task.value
    running.lock.withLock { running.task = nil }
    pick.lock.withLock { pick.running = nil }
    if let e = result.error {
        renderer.fail(e)
        if live.ui != nil { say("kurtkode: \(e)") } else { warn("\(e)") }
    }
    return result.stop ?? (task.isCancelled ? .cancelled : nil)
}

/// Holds what a stoppable piece of work returned.
final class Outcome<T>: @unchecked Sendable { var value: T? }

/// Runs work that isn't a send (/compact, /review, the escalation offer's review, /model's loading) with Esc and Ctrl-C
/// able to stop it, as `runTurn` does for a send. Nil when it was stopped.
func stoppable<T>(_ work: @escaping @Sendable () async -> T) async -> T? {
    let outcome = Outcome<T>()
    let task = Task { outcome.value = await work() }
    running.lock.withLock { running.task = task }
    await task.value
    running.lock.withLock { running.task = nil }
    return task.isCancelled ? nil : outcome.value
}

// MARK: -p: one prompt, then exit

if !interactive {
    var prompt = options.prompt ?? ""
    // Piped input joins the prompt: a pipe or a file is read to its end, however slowly it comes; a socket or a
    // device only if something arrives soon (a script or CI job can leave one open without ever writing to it).
    if let piped = PipedInput.read(fd: STDIN_FILENO, promptGiven: options.prompt != nil, note: { writeErr($0 + "\n") }) {
        prompt = prompt.isEmpty ? piped : prompt + "\n\n" + piped
    }
    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("-p needs a prompt (an argument or stdin)", code: 2) }
    let renderer = Renderer(style: .print(options.output), showThinking: options.showThinking)
    let fullPrompt = prompt
    let stop = await runTurn(renderer) { try await session.send(fullPrompt) }
    renderer.finish(session: session.session.header.id, model: session.model)
    await session.hub?.shutdown()
    switch stop {
    case .completed?: exit(0)
    case .cancelled?: exit(130)
    default: exit(1)
    }
}

// MARK: Interactive

do {
    if let note = try await session.prepareModel() { print(note) }
} catch { fail("\(error)\n`kurtkode doctor` checks this setup; `kurtkode endpoint add` adds a server; -m chooses a model.") }
let toolCount = (await session.hub?.allTools.count) ?? 0
print(bold("kurtkode") + " · \(session.model) on \(session.endpoint.name) · \(cwd.lastPathComponent) · \(session.mode.displayName)"
      + (toolCount > 0 ? " · \(toolCount) MCP tools" : "")
      + session.session.folders.map { " · +\($0.displayPath)\($0.writable ? "" : " (read-only)")" }.joined() + (session.session.messages.isEmpty ? "" : " · resumed (\(session.session.messages.count) messages)"))
print(useLiveScreen
      ? "Type a message, or /help for commands. @ attaches a file, ! runs a command, # remembers a fact. Esc stops a run."
      : "Type a message, /help for commands, @path to attach a file, !command to run one. Ctrl-C stops a reply "
        + "(during a subagent, first just the subagent).")
if [.anthropic, .gemini].contains(session.endpoint.kind), let stale = PriceList.staleness() { print(stale) }
// A resumed session whose prompt cache has expired: what the next message costs, before it's typed (caching plan 1.7).
if interactive, let cold = CacheLedger.coldResumeNote(last: session.session.lastReplyCost) { print(cold) }

@Sendable func allCommands() -> [SlashCommand] { SlashCommands.all(workspace: cwd, builtinSkills: session.builtinSkills) + CLICommands.all }

func makeRenderer() -> Renderer {
    guard let ui = live.ui else { return Renderer(style: .interactive, showThinking: options.showThinking) }
    return Renderer(style: .interactive, showThinking: options.showThinking, rich: true, live: { ui.setLive($0) }, out: { ui.put($0) })
}

/// The live screen's half of the program: keys and the clock keep going while `act(on:)` runs.
@MainActor func runLiveScreen() async {
    let order: [PermissionMode] = [.ask, .acceptEdits, .plan, .fullAuto]
    let history = HistoryKeeper(InputHistory(fileURL: historyFile))
    let color = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    let style = TerminalStyle(on: color)
    let root = session.root, skills = session.builtinSkills, files = fileIndex, store = settings.sessionStore
    let commands = allCommands()
    let ui = TerminalUI(history: history.entries, color: color, handlers: .init(
        immediately: { text, status in
            // "# fact": kept at once, as at the prompt, not sent to the model at its next step.
            if let note = Memory.note(in: text) {
                do { return "Remembered (\(try Memory.remember(note, root: root).path))." }
                catch { return "Couldn't save it: \(error)" }
            }
            guard let (name, _) = SlashCommands.parse(text), SlashCommands.answersWhileRunning.contains(name) else { return nil }
            switch name {
            case "help":
                return commands.map { "/\($0.name)\($0.argumentHint.isEmpty ? "" : " " + $0.argumentHint)  \($0.description)" }.joined(separator: "\n")
            case "context":
                guard let used = status.contextUsed, let limit = status.contextLimit, limit > 0 else { return "The context use isn't known yet." }
                return "Context: about \(used / 1000)k of \(limit / 1000)k tokens (\(used * 100 / limit)%)."
            case "skills": return Skills.listing(root: root, builtin: skills)
            case "memory": return Memory.listing(root: root)
            case "agents":
                Task { say(await session.agentsSummary()) }
                return ""
            case "btw":
                let question = SlashCommands.parse(text)?.arguments ?? ""
                guard !question.isEmpty else { return "Give the question: /btw <question>." }
                Task { say(style.dim("On the side: ") + (await session.askOnTheSide(question))) }
                return style.dim("Asking on the side…")
            default: return nil
            }
        },
        refuse: { text in
            guard let (name, _) = SlashCommands.parse(text), !commands.contains(where: { $0.name == name }),
                  !["exit", "quit"].contains(name) else { return nil }
            return "There's no /\(name) command. /help lists them."
        },
        completions: { kind, typed in
            if kind == "/" {
                return SlashCommands.matching(typed, in: commands).map {
                    Completion(text: $0.name, detail: ($0.argumentHint.isEmpty ? "" : $0.argumentHint + "  ") + $0.description,
                               runs: $0.runsWithoutArguments && $0.argumentHint.isEmpty)
                }
            }
            return Mentions.completions(typed, files: files.all, limit: 6).map { Completion(text: $0) }
        },
        // Not on the UI's queue: quitting stops the UI, which waits for that queue.
        interrupt: { DispatchQueue.main.async { interrupted() } },
        stop: { running.lock.withLock { running.task }?.cancel() },
        cycleMode: {
            let busy = running.lock.withLock { running.task } != nil
            if busy {
                let now = pick.lock.withLock { pick.next ?? pick.running } ?? modeCycle.pendingMode ?? session.mode
                let next = order[((order.firstIndex(of: now) ?? 0) + 1) % order.count]
                pick.lock.withLock { pick.next = next }
                live.ui?.update { $0.nextMode = next.displayName }
            } else {
                // Steps on from the last press, and applies the presses in order (`ModeCycle`).
                let next = modeCycle.step(from: session.mode, order: order)
                live.ui?.update { $0.mode = next.displayName }
            }
        },
        showRewind: {
            Task { @MainActor in
                if let list = await slash("rewind", "", allCommands()) { say(list) }
            }
        },
        attachImage: {
            let board = NSPasteboard.general
            guard let data = board.data(forType: .png) ?? board.data(forType: .tiff) else { return nil }
            return try? ImageStore.save(data, in: store.imagesDirectory(for: session.session.header))
        },
        saveHistory: { history.add($0) }))
    live.ui = ui
    session.takeQueued = { ui.takeMessages() }
    @Sendable func sync() {
        let model = session.model, mode = session.mode.displayName, limit = session.contextLimit
        let used = session.session.messages.last(where: { $0.meta?.usage != nil })?.meta?.usage?.totalTokens
        ui.update {
            $0.model = model
            $0.mode = mode
            $0.nextMode = nil
            $0.contextLimit = limit
            if let used { $0.contextUsed = used }
        }
        ui.setSpent(CostSummary(session.session.costs))
    }
    sync()
    ui.start()
    /// What goes in the scrollback for what was just sent; the composer is empty again.
    func echo(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var shown = lines.prefix(6).map { style.bold("› " + $0) }.joined(separator: "\n")
        if lines.count > 6 { shown += "\n" + style.dim("  … \(lines.count - 6) more lines") }
        ui.put("\n" + shown + "\n")
    }
    var first = options.prompt
    var stopped = false
    while true {
        let text: String
        if let f = first {
            first = nil
            text = f
        } else {
            guard let typed = await ui.next(stopped: stopped) else { break }
            text = typed
        }
        echo(text)
        // A Shift-Tab just before sending: the run starts in the mode the status line shows.
        await modeCycle.settled()
        ui.setBusy(true)
        session.pendingImages = ui.takeImages()
        let stop = await act(on: text)
        stopped = !(stop == nil || stop == .completed || stop == .truncated)
        if let mode = pick.lock.withLock({ () -> PermissionMode? in defer { pick.next = nil }; return pick.next }) {
            try? await session.setMode(mode)
        }
        ui.setBusy(false)
        sync()
    }
    ui.stop()
}

/// Shows an escalation offer and asks; the hand-over message to send on yes. For a run that changed files the first
/// choice is a review of the change on the offer's model (decision 4); after it, the findings can go to the session's
/// model to fix, or the request to the stronger model.
func askEscalation(_ offer: EscalationOffer) async -> String? {
    say("This may need a stronger model: \(offer.reasonText).")
    if offer.canReview {
        let first = await ask("r: \(offer.reviewTitle); e: \(offer.buttonTitle); or neither? [r/e/N] ")
        if PromptWord.says(first, "e", "escalate") { return await session.decide(offer, accept: true) }
        guard PromptWord.says(first, "r", "review") else { return await session.decide(offer, accept: false) }
        say("Reviewing on \(offer.toLabel)…")
        guard let (text, review) = await stoppable({ await session.reviewForEscalation(offer) }) else {
            say("(stopped)")
            return nil
        }
        say(text)
        guard let review, review.verdict != .looksRight else { return nil }
        // Handing over is listed first only when the review found the change wrong (`CodeReview.escalates`).
        let fix = review.findings.isEmpty ? "" : "f: send the findings to \(session.model) to fix; "
        let up = "e: \(offer.buttonTitle); "
        let then = await ask((review.escalates ? up + fix : fix + up) + "or neither? [\(fix.isEmpty ? "" : "f/")e/N] ")
        if PromptWord.says(then, "f", "fix"), !review.findings.isEmpty { return review.fixRequest }
        guard PromptWord.says(then, "e", "escalate") else { return nil }
        return await session.decide(offer, accept: true)
    }
    let yes = PromptWord.yes(await ask(offer.buttonTitle + "? [y/N] "))
    return await session.decide(offer, accept: yes)
}

@MainActor @Sendable func slash(_ name: String, _ arguments: String, _ commands: [SlashCommand]) async -> String? {
    switch name {
    case "exit", "quit":
        live.ui?.stop()
        await session.hub?.shutdown()
        exit(0)
    case "help":
        return (commands.map { "/\($0.name)\($0.argumentHint.isEmpty ? "" : " " + $0.argumentHint)  \($0.description)" }
                + ["/exit  Quit"]).joined(separator: "\n")
    case "clear":
        session.clear()
        return "New session."
    case "compact":
        return await stoppable {
            do { return try await session.compact(focus: arguments) }
            catch { return "Couldn't summarize: \(error)" }
        } ?? "Stopped: the conversation stays as it was."
    case "context":
        return session.contextSummary
    case "agents":
        return await session.agentsSummary()
    case "skills":
        return Skills.listing(root: cwd, builtin: session.builtinSkills)
    case "memory":
        return Memory.listing(root: session.workspace.root)
    case "good", "bad":
        return await session.rateLatestRun(up: name == "good", note: arguments)
    case "diff":
        return await session.diff(arguments)
    case "rewind":
        let points = await session.rewindPoints()
        guard !points.isEmpty else { return "Nothing to rewind to yet." }
        let words = arguments.split(separator: " ").map(String.init)
        guard let n = words.first.flatMap(Int.init) else {
            return "Requests (/rewind N goes back to just before request N; add files or chat to take back only that):\n"
                + points.map { p in
                    "  \(p.number). " + (p.date.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) + "  " } ?? "")
                        + p.text + (p.files.map { "  (\($0) file\($0 == 1 ? "" : "s"))" } ?? "")
                }.joined(separator: "\n")
        }
        guard let point = points.first(where: { $0.number == n }) else { return "There's no request \(n) (1–\(points.count))." }
        let word = words.dropFirst().first?.lowercased() ?? ""
        let choice: RewindChoice = word.hasPrefix("f") ? .files : (word.hasPrefix("c") || word.hasPrefix("conv")) ? .conversation : .both
        let plan = await session.rewindPlan(to: point.message)
        say(plan.summary(choice, root: session.root.path))
        guard PromptWord.yes(await ask("Rewind? [y/N] ")) else { return "Not rewound." }
        do {
            let (restored, request) = try await session.rewind(to: point.message, choice: choice)
            var out = choice.restoresFiles ? "Restored \(restored.count) file\(restored.count == 1 ? "" : "s")." : "Files left as they are."
            if let request { out += " The conversation now ends before request \(n), which was:\n" + request }
            else if choice == .files { out += " The model is told on your next message." }
            return out
        } catch { return "Rewind failed: \(error.localizedDescription)" }
    case "model":
        guard !arguments.isEmpty else { return "This session uses \(session.model) on \(session.endpoint.name). /model <model> or <endpoint>:<model>." }
        // Loading a model on LM Studio can take minutes: Esc or Ctrl-C stops the wait.
        return await stoppable {
            do {
                let cost = try await session.setModel(arguments)
                let line = (try await session.prepareModel()) ?? "The next reply uses \(session.model) on \(session.endpoint.name)."
                return line + (cost.map { " " + $0 } ?? "")
            } catch { return "\(error)" }
        } ?? "Stopped. The next reply uses \(session.model) on \(session.endpoint.name)."
    case "btw":
        return arguments.isEmpty ? "Give the question: /btw <question>." : "On the side: " + (await session.askOnTheSide(arguments))
    case "status":
        return session.statusReport
    case "worktrees":
        return (try? await SetupCommands.describeWorktrees(GitRepo(root: session.root))) ?? "This project isn't a git repository."
    case "rename":
        guard !arguments.isEmpty else { return "Give the new title: /rename <title>." }
        do {
            try await session.rename(arguments)
            return "Renamed."
        } catch { return "\(error)" }
    case "copy":
        guard let reply = session.session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.content else {
            return "There's no reply to copy yet."
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply, forType: .string)
        return "Copied the last reply (\(reply.count) characters)."
    case "export":
        let name = arguments.isEmpty ? "kurtkode-\(session.session.header.id.uuidString.prefix(8).lowercased()).md" : arguments
        let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath, relativeTo: cwd)
        do {
            try session.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            return "Saved \(url.path)."
        } catch { return "Couldn't save it: \(error.localizedDescription)" }
    case "resume":
        let list = (try? await session.sessions()) ?? []
        guard !list.isEmpty else { return "There are no other sessions in this project." }
        guard !arguments.isEmpty else {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d HH:mm"
            return "Sessions in this project (/resume N):\n" + list.prefix(20).enumerated().map { i, s in
                "  \(i + 1). \(fmt.string(from: s.updatedAt))  \(s.title)  (\(s.messageCount) messages)"
                    + (s.id == session.session.header.id ? "  ← this one" : "")
            }.joined(separator: "\n")
        }
        let pick = Int(arguments).flatMap { list.indices.contains($0 - 1) ? list[$0 - 1] : nil }
            ?? list.first { $0.id.uuidString.lowercased().hasPrefix(arguments.lowercased()) }
        guard let pick else { return "There's no session \(arguments) here: /resume lists them." }
        do {
            try await session.resume(pick.id)
            _ = try? await session.prepareModel()
            return "Resumed \"\(pick.title)\" (\(pick.messageCount) messages) on \(session.model). Mode stays \(session.mode.displayName)."
                + (CacheLedger.coldResumeNote(last: session.session.lastReplyCost).map { "\n" + $0 } ?? "")
        } catch { return "\(error)" }
    case "mode":
        let modes: [String: PermissionMode] = ["ask": .ask, "edits": .acceptEdits, "plan": .plan, "auto": .fullAuto]
        guard let m = modes[arguments.lowercased()] else { return "Mode: \(session.mode.displayName). /mode ask, edits, plan, or auto." }
        try? await session.setMode(m)
        return "Mode: \(m.displayName)."
    default:
        return nil
    }
}

/// Does what was typed: a `!command`, a note, a /command, or a message and whatever it leads to. Returns how the last run
/// ended, when there was one.
@MainActor @discardableResult
func act(on text: String) async -> AgentStop? {
    let renderer = makeRenderer()
    if let command = UserShell.command(in: text) {
        // Its output streams as it runs; Ctrl-C stops it.
        let stop = await runTurn(renderer) {
            let m = try await session.runUserCommand(command) { emit($0) }
            if let code = m.userCommand?.exitCode, code != 0 { say("(exit \(code))") }
            return nil
        }
        fileIndex.refresh(session.workspace)
        return stop
    }
    // "# fact": kept in the project's memory, not sent (B6).
    if let note = Memory.note(in: text) {
        do { say("Remembered (\(try Memory.remember(note, root: session.workspace.root).path)).") }
        catch { say("Couldn't save it: \(error)") }
        return nil
    }
    var message = PastedText.withoutMark(text)
    if let (name, arguments) = SlashCommands.parse(text) {
        let commands = allCommands()
        guard let command = commands.first(where: { $0.name == name }) ?? (["exit", "quit"].contains(name) ? SlashCommand(name: name, description: "") : nil) else {
            say("There's no /\(name) command. /help lists them.")
            return nil
        }
        switch command.kind {
        case .custom(let template, _):
            message = SlashCommands.expand(template, arguments: arguments)
        case .builtIn:
            if name == "init" { message = SlashCommands.initPrompt }
            else if name == "retry" {
                return await runTurn(renderer) { try await session.retry() }
            }
            else if name == "bad", settings.run.escalationOffers {
                say(await session.rateLatestRun(up: false, note: arguments))
                guard let offer = await session.escalationOffer(reasons: ["you marked the reply wrong"], source: "user"),
                      let handOver = await askEscalation(offer) else { return nil }
                message = handOver
            }
            else if name == "escalate" {
                guard let offer = await session.escalationOffer(reasons: ["you asked to escalate" + (arguments.isEmpty ? "" : ": " + arguments)],
                                                                source: "asked", unknownTier: .standard),
                      let handOver = await session.decide(offer, accept: true) else {
                    say("There's no stronger main model in the pool to escalate \(session.model) to (`kurtkode pool`).")
                    return nil
                }
                say("Escalating to \(offer.toLabel)…")
                message = handOver
            }
            else if name == "review" {
                say("Reviewing…")
                guard let (text, review) = await stoppable({ await session.review(arguments) }) else {
                    say("(stopped)")
                    return nil
                }
                say(text)
                guard let review, !review.findings.isEmpty,
                      PromptWord.yes(await ask("Send the findings to \(session.model) to fix? [y/N] ")) else { return nil }
                message = review.fixRequest
            }
            else {
                if let reply = await slash(name, arguments, commands) { say(reply) }
                return nil
            }
        }
    }
    var next: String? = message
    var last: AgentStop?
    while let toSend = next {
        next = nil
        let turnStarted = Date()
        last = await runTurn(makeRenderer()) { try await session.send(toSend) }
        // A long run ended: ring the terminal's bell, so a user in another window hears it.
        if settings.run.notify, Date().timeIntervalSince(turnStarted) > 30 { _ = try? FileHandle.standardError.write(contentsOf: Data("\u{7}".utf8)) }
        fileIndex.refresh(session.workspace)
        // A4: a run that looks wrong earns an offer of the next tier's model; nothing happens without a yes.
        if settings.run.escalationOffers, let offer = await session.escalationOffer() {
            next = await askEscalation(offer)
        } else if let review = session.reviewToFix {
            // The automatic review found problems, not a wrong change: its findings, to fix on this model.
            say(review.text)
            if !review.findings.isEmpty,
               PromptWord.yes(await ask("Send the findings to \(session.model) to fix? [y/N] ")) {
                next = review.fixRequest
            }
        }
    }
    return last
}

if useLiveScreen {
    await runLiveScreen()
} else {
    var first = options.prompt
    while true {
        print("")
        // Plain: libedit moves a prompt's escape sequences (the › came out after the bold was reset).
        let line: String
        if let f = first {
            first = nil
            line = f
        } else {
            guard let typed = await ask("› ", remember: true) else { break }
            line = typed
        }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { continue }
        await act(on: text)
    }
}
await session.hub?.shutdown()
