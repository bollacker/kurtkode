import AgentCore
import Darwin
import Foundation

/// Writes agent events to the terminal. Interactive: the reply streams to stdout with tool calls between.
/// `-p` text: only the final answer goes to stdout; progress goes to stderr when it's a terminal.
/// JSON: one object at the end; stream-json: one object per event.
public final class Renderer: @unchecked Sendable {
    public enum Style { case interactive, print(CLIOptions.Output) }

    let style: Style
    let showThinking: Bool
    let color: Bool
    let errColor: Bool
    let out: (String) -> Void
    let err: (String) -> Void
    /// A live screen shows this reply: Markdown line by line, the unfinished line given to `live`, and commands' output
    /// left to the screen while they run.
    let rich: Bool
    let live: ((String) -> Void)?
    private var markdown: MarkdownLines
    private var replyLine = ""
    private let lock = NSLock()
    private var printed = 0          // characters of the current turn's content already written
    private var thought = 0
    private var finalText = ""
    private var toolCalls = 0
    private var promptTokens = 0, completionTokens = 0
    private var cacheRead: Int?, cacheWrite: Int?
    private var cost: Double?
    /// The run's billed requests (`AgentEvent.cost`; a later record of one replaces it).
    private var entries: [CostEntry] = []
    /// The subagents of the last run that ended: what they spent and their list price (their own cost records are in
    /// their child sessions).
    private var childSpent = 0.0, childList = 0.0, childPriced = false
    private var stop: AgentStop?
    private var lastError: String?
    /// What the run threw, when it ended that way (no `.finished` event comes then).
    private var thrown: String?

    public init(style: Style, showThinking: Bool = false, rich: Bool = false, live: ((String) -> Void)? = nil,
                out: @escaping (String) -> Void = Renderer.write(to: .standardOutput),
                err: @escaping (String) -> Void = Renderer.write(to: .standardError)) {
        self.style = style
        self.showThinking = showThinking
        let noColor = ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        color = !noColor && isatty(STDOUT_FILENO) == 1
        errColor = !noColor && isatty(STDERR_FILENO) == 1
        self.out = out
        self.err = err
        self.rich = rich
        self.live = live
        markdown = MarkdownLines(style: TerminalStyle(on: color))
    }

    /// What's written to a terminal is checked; to a file or a pipe it stays as it is. When the reader has gone
    /// (`kurtkode -p … | head -3`; SIGPIPE is ignored, so the write fails with EPIPE) `closed` runs: by default the
    /// program exits, so its `atexit` cleanup stops running commands and MCP servers.
    public static func write(to file: FileHandle, closed: @escaping @Sendable () -> Void = { exit(128 + SIGPIPE) }) -> (String) -> Void {
        let terminal = isatty(file.fileDescriptor) == 1
        return { if !put(Data((terminal ? TerminalText.safe($0) : $0).utf8), to: file) { closed() } }
    }

    /// Writes `data`; false only when the reading end is closed (EPIPE). The throwing write: the older `write(_:)`
    /// raises an Objective-C exception on any failure, which can't be caught.
    static func put(_ data: Data, to file: FileHandle) -> Bool {
        do {
            try file.write(contentsOf: data)
            return true
        } catch {
            func isPipe(_ e: NSError) -> Bool {
                (e.domain == NSPOSIXErrorDomain && e.code == Int(EPIPE))
                    || (e.userInfo[NSUnderlyingErrorKey] as? NSError).map(isPipe) ?? false
            }
            return !isPipe(error as NSError)
        }
    }

    /// The reply so far: its finished lines go out rendered, the rest waits on the live line.
    private func feedReply(_ content: String) {
        replyLine += content.dropFirst(printed)
        printed = content.count
        while let newline = replyLine.firstIndex(of: "\n") {
            out(markdown.render(TerminalText.plain(String(replyLine[..<newline]))) + "\n")
            replyLine = String(replyLine[replyLine.index(after: newline)...])
        }
        live?(replyLine)
    }

    private func finishReply() {
        if !replyLine.isEmpty { out(markdown.render(TerminalText.plain(replyLine)) + "\n") }
        replyLine = ""
        live?("")
        markdown.reset()
    }

    /// What a finished tool leaves in the scrollback: an edit's diff, the end of a command's output.
    private func showResult(_ m: ChatMessage, _ c: Bool) {
        guard let info = m.toolResult, !info.isError else { return }
        let style = TerminalStyle(on: c)
        if AllTools.named(info.toolName)?.risk == .write, let diff = info.display {
            for line in DiffPreview.lines(TerminalText.visible(diff), limit: 24, style: style) { out("    " + line + "\n") }
        } else if info.toolName == "bash" {
            let lines = TerminalText.plain(info.display ?? m.content).split(separator: "\n").map(String.init)
                .filter { !$0.contains(BashTool.marker) && !$0.hasPrefix("[Exit code") }
            guard !lines.isEmpty else { return }
            for line in lines.suffix(3) { out("    " + style.dim(line) + "\n") }
            if lines.count > 3 { out("    " + style.dim("… \(lines.count) lines in all; ctrl+o shows them") + "\n") }
        }
    }

    var interactive: Bool { if case .interactive = style { true } else { false } }
    var format: CLIOptions.Output { if case .print(let f) = style { f } else { .text } }

    /// Where progress (narration, tool lines) goes: stdout when interactive; stderr for -p text if it's a
    /// terminal; nowhere for JSON (it would corrupt the output) unless stderr is a terminal.
    private func progress(_ s: String) {
        if interactive { out(s) } else if isatty(STDERR_FILENO) == 1 { err(s) }
    }

    /// Why a run failed: like progress, but -p writes it to stderr even when that isn't a terminal (a script must
    /// be able to see why it got exit 1).
    private func problem(_ s: String) {
        if interactive { out(s) } else { err(s) }
    }

    func dim(_ s: String, _ on: Bool) -> String { on ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
    func cyan(_ s: String, _ on: Bool) -> String { on ? "\u{1B}[36m\(s)\u{1B}[0m" : s }
    func red(_ s: String, _ on: Bool) -> String { on ? "\u{1B}[31m\(s)\u{1B}[0m" : s }
    var progressColor: Bool { interactive ? color : errColor }

    public func handle(_ event: AgentEvent) {
        if format == .streamJSON { streamJSON(event) }
        lock.withLock { apply(event) }
    }

    private func apply(_ event: AgentEvent) {
        let c = progressColor
        switch event {
        case .streaming(let snap):
            if showThinking, snap.reasoning.count > thought {
                progress(dim(String(snap.reasoning.dropFirst(thought)), c))
                thought = snap.reasoning.count
            }
            if rich {
                if snap.content.count > printed { feedReply(snap.content) }
            } else if interactive, snap.content.count > printed {
                out(String(snap.content.dropFirst(printed)))
                printed = snap.content.count
            }
        case .assistant(let m):
            if rich {
                feedReply(m.content)
                finishReply()
            } else if interactive {
                if m.content.count > printed { out(String(m.content.dropFirst(printed))) }
                if !m.content.isEmpty { out("\n") }
            } else if !m.toolCalls.isEmpty, !m.content.isEmpty, format == .text {
                progress(dim(m.content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", c))
            }
            printed = 0
            thought = 0
            for call in m.toolCalls {
                toolCalls += 1
                progress(cyan("  → " + Self.summary(call) + "\n", c))
            }
            if let u = m.meta?.usage {
                promptTokens += u.promptTokens
                completionTokens += u.completionTokens
                if let x = u.cost { cost = (cost ?? 0) + x }
                if let r = u.cacheReadTokens { cacheRead = (cacheRead ?? 0) + r }
                if let w = u.cacheWriteTokens { cacheWrite = (cacheWrite ?? 0) + w }
            }
            if m.toolCalls.isEmpty, !m.content.isEmpty { finalText = m.content }
            if let error = m.meta?.error {
                lastError = error
                problem(red("  ! " + error + "\n", c))
            }
        case .toolProgress(_, let text):
            if interactive, !rich { out(dim(text, color)) }
        case .toolFinished(let m):
            // A call a PreToolUse hook blocked was already reported by the hook's notice line.
            let hookBlocked = m.toolResult?.approval.map { $0.decider == .hook && !$0.allowed } ?? false
            if let info = m.toolResult, info.isError, !hookBlocked {
                let first = m.content.split(separator: "\n").first.map(String.init) ?? m.content
                progress(red("    ✗ " + String(first.prefix(200)) + "\n", c))
            }
            if rich { showResult(m, c) }
        case .hookNotice(let text):
            progress(dim("  (hook: \(text))\n", c))
        case .retrying(let text):
            progress(dim("  (\(text))\n", c))
        case .status(let text):
            progress(dim("  (\(text))\n", c))
        case .injected(let m) where m.subagentReport != nil:
            progress(dim("  ⤶ a background subagent reported\n", c))
        case .subagentStarted(let i):
            progress(dim("  ⤷ \(i.agent) subagent: \(i.title) (on \(i.model))\n", c))
        case .subagentFinished(_, let end):
            progress(dim("  ⤶ subagent \(end.stop) · \(end.steps) turns, \(end.toolCalls) calls · "
                         + String(format: "%.1f s", end.seconds) + "\n", c))
        case .cost(let e):
            // (`apply` runs under the lock.)
            if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = e } else { entries.append(e) }
        case .runEnded(let r):
            // What the run cost, when anything in it had a price: the charge where the server said it, else list price.
            let s = CostSummary(entries.filter { $0.run == r.id })
            let priced = r.children.filter { $0.spent != nil || $0.listPrice != nil }
            childPriced = !priced.isEmpty
            childSpent = priced.compactMap { $0.spent ?? $0.listPrice }.reduce(0, +)
            childList = priced.compactMap(\.listPrice).reduce(0, +)
            if !s.isEmpty || childPriced {
                let summaries = (s.byPurpose[.summary] ?? 0) + (s.byPurpose[.summaryAttempt] ?? 0)
                let children = childSpent
                progress(dim("  (" + s.spentText() + " this run · \(s.requests) requests"
                             + (summaries > 0 ? String(format: ", summaries $%.4f", summaries) : "")
                             + (children > 0 ? String(format: " · subagents ≈$%.4f", children) : "")
                             + (s.estimated ? " · ≈ list price" : "") + ")\n", c))
            }
        case .judged(let j) where j.judge != .checks || !(j.checks?.problems.isEmpty ?? true):
            progress(dim("  ✎ \(j.summary)\n", c))
        case .compacted(let comp):
            progress(dim("  (summarized the conversation: \(comp.tokensBefore / 1000)k → \(max(1, comp.tokensAfter / 1000))k tokens)\n", c))
        case .finished(let s):
            stop = s
            switch s {
            case .completed: break
            case .stepLimit: progress(dim("  (paused at the step limit; send \"continue\" to go on)\n", c))
            case .costLimit:
                problem(red("  (paused at a cost limit from the app's Settings → Generation → Spending; at a run or session "
                            + "limit, send \"continue\" to allow another run's worth, or raise the limit)\n", c))
            case .denied: progress(dim("  (stopped: an action was denied)\n", c))
            case .cancelled: progress(dim("  (stopped)\n", c))
            case .truncated: progress(dim("  (the reply was cut off at the output limit)\n", c))
            case .turnStopped(let why): problem(red("  (the model's turn stopped: \(why))\n", c))
            }
        case .modeChanged(let m):
            progress(dim("  (plan approved: mode is now \(m.displayName))\n", c))
        default:
            break
        }
    }

    /// The run threw instead of ending: `finish` reports it (`"stop": "error"` and `"error"` in JSON); stream-json
    /// gets an error event now.
    public func fail(_ error: Error) {
        let text = "\(error)"
        lock.withLock { thrown = text }
        if format == .streamJSON { out(Self.json(["type": "error", "message": .string(text)]) + "\n") }
    }

    /// Call at the end of a -p run: prints the answer (text) or the result object (json, stream-json).
    public func finish(session: UUID, model: String) {
        let (text, calls, pt, ct, cost, stop, error) = lock.withLock {
            (finalText, toolCalls, promptTokens, completionTokens, self.cost, self.stop, thrown ?? lastError)
        }
        let threw = lock.withLock { thrown != nil }
        let (cacheRead, cacheWrite) = lock.withLock { (self.cacheRead, self.cacheWrite) }
        let costs = CostSummary(lock.withLock { entries })
        let (childSpent, childList, childPriced) = lock.withLock { (self.childSpent, self.childList, self.childPriced) }
        switch format {
        case .text:
            if !interactive { out(text + (text.hasSuffix("\n") ? "" : "\n")) }
        case .json, .streamJSON:
            var o: [String: JSONValue] = [
                "type": "result", "result": .string(text), "session": .string(session.uuidString), "model": .string(model),
                "stop": .string(stop.map(Self.name) ?? (threw ? "error" : "none")), "tool_calls": .number(Double(calls)),
                "usage": ["prompt_tokens": .number(Double(pt)), "completion_tokens": .number(Double(ct))],
            ]
            if cacheRead != nil || cacheWrite != nil, case .object(var u)? = o["usage"] {
                u["cache_read_tokens"] = .number(Double(cacheRead ?? 0))
                u["cache_write_tokens"] = .number(Double(cacheWrite ?? 0))
                o["usage"] = .object(u)
            }
            // Every billed request of the run (summaries and retried attempts too): the charge where known, else list
            // price; the list price apart, for comparing models.
            // Subagents' spending is included, and also given apart.
            if !costs.isEmpty || childPriced {
                o["cost_usd"] = .number(costs.spent + childSpent)
                o["list_price_usd"] = .number(costs.listPrice.total + childList)
                o["cost_is_estimate"] = .bool(costs.estimated || childSpent > 0)
                if childPriced { o["subagents_cost_usd"] = .number(childSpent) }
            } else if let cost {
                o["cost_usd"] = .number(cost)
            }
            if costs.requests > 0 { o["requests"] = .number(Double(costs.requests)) }
            if let error, stop != .completed || threw { o["error"] = .string(error) }
            out(Self.json(.object(o)) + "\n")
        }
    }

    /// One JSON object per event, for scripts. Streaming snapshots are left out (too many).
    private func streamJSON(_ event: AgentEvent) {
        let o: JSONValue?
        switch event {
        case .assistant(let m): o = ["type": "assistant", "message": Self.encode(m)]
        case .toolStarted(let c): o = ["type": "tool_started", "id": .string(c.id), "name": .string(c.name), "arguments": .string(c.arguments)]
        case .toolFinished(let m): o = ["type": "tool_result", "message": Self.encode(m)]
        case .compacted(let c): o = ["type": "compacted", "tokens_before": .number(Double(c.tokensBefore)), "tokens_after": .number(Double(c.tokensAfter))]
        case .retrying(let text): o = ["type": "retrying", "message": .string(text)]
        case .cost(let e):
            o = ["type": "cost", "entry": Self.json(encoding: e)]
        case .runEnded(let r):
            o = ["type": "run", "record": Self.json(encoding: r)]
        case .judged(let j):
            o = ["type": "judgment", "judgment": Self.json(encoding: j)]
        case .status(let text): o = ["type": "status", "message": .string(text)]
        case .injected(let m) where m.subagentReport != nil:
            o = ["type": "subagent_report", "id": .string(m.subagentReport!.uuidString), "message": Self.encode(m)]
        case .subagentStarted(let i):
            o = ["type": "subagent_started", "id": .string(i.id.uuidString), "call_id": .string(i.callID ?? ""),
                 "agent": .string(i.agent), "title": .string(i.title), "model": .string(i.model)]
        case .subagentFinished(let id, let end):
            o = ["type": "subagent_finished", "id": .string(id.uuidString), "stop": .string(end.stop),
                 "steps": .number(Double(end.steps)), "tool_calls": .number(Double(end.toolCalls)), "seconds": .number(end.seconds)]
        case .finished(let s): o = ["type": "finished", "stop": .string(Self.name(s))]
        case .modeChanged(let m): o = ["type": "mode_changed", "mode": .string(m.rawValue)]
        default: o = nil
        }
        if let o { out(Self.json(o) + "\n") }
    }

    static func name(_ s: AgentStop) -> String {
        switch s {
        case .completed: "completed"
        case .stepLimit: "step_limit"
        case .costLimit: "cost_limit"
        case .turnStopped(let r): "turn_stopped:\(r)"
        case .truncated: "truncated"
        case .cancelled: "cancelled"
        case .denied: "denied"
        }
    }

    static func summary(_ call: ToolCall) -> String {
        let args = (try? ToolArguments(json: call.arguments)) ?? ToolArguments()
        if let tool = AllTools.named(call.name) { return tool.summary(args) }
        return TaskTool.summary(forCallNamed: call.name, arguments: call.arguments)
            ?? MCPTool.summary(forCallNamed: call.name, arguments: call.arguments) ?? call.name
    }

    static func json(encoding value: some Encodable) -> JSONValue {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(value)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
    }

    static func encode(_ m: ChatMessage) -> JSONValue {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(m)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
    }

    static func json(_ v: JSONValue) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
