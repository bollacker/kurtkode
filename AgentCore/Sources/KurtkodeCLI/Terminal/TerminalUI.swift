import AgentCore
import Darwin
import Foundation

/// The interactive terminal: a composer that's live whether or not a run is going, with a status line, over a normal
/// scrolling terminal. Keys, agent events and the clock all come through one queue, which owns the state; the drawing
/// goes through `LiveScreen`, and everything that decides anything is in `InputState`, `Frame` and the `Key` decoder.
public final class TerminalUI: @unchecked Sendable {
    /// What the rest of the program does for it. Called on the UI's queue, so they mustn't wait on it.
    public struct Handlers: Sendable {
        /// Typed during a run: a command that answers at once, or nil to queue it.
        public var immediately: @Sendable (String, StatusInfo) -> String?
        /// A message for typed text that can't be queued, or nil.
        public var refuse: @Sendable (String) -> String?
        public var completions: @Sendable (Character, String) -> [Completion]
        public var interrupt: @Sendable () -> Void
        public var stop: @Sendable () -> Void
        public var cycleMode: @Sendable () -> Void
        public var showRewind: @Sendable () -> Void
        public var attachImage: @Sendable () -> ImageAttachment?
        public var saveHistory: @Sendable (String) -> Void

        public init(immediately: @escaping @Sendable (String, StatusInfo) -> String?, refuse: @escaping @Sendable (String) -> String?,
                    completions: @escaping @Sendable (Character, String) -> [Completion], interrupt: @escaping @Sendable () -> Void,
                    stop: @escaping @Sendable () -> Void, cycleMode: @escaping @Sendable () -> Void,
                    showRewind: @escaping @Sendable () -> Void, attachImage: @escaping @Sendable () -> ImageAttachment?,
                    saveHistory: @escaping @Sendable (String) -> Void) {
            self.immediately = immediately
            self.refuse = refuse
            self.completions = completions
            self.interrupt = interrupt
            self.stop = stop
            self.cycleMode = cycleMode
            self.showRewind = showRewind
            self.attachImage = attachImage
            self.saveHistory = saveHistory
        }
    }

    private let queue = DispatchQueue(label: "kurtkode.terminal")
    private let handlers: Handlers
    private let style: TerminalStyle
    private var input: InputState
    private var screen = LiveScreen()
    private var status = StatusInfo()
    /// The unfinished line of what's being written, and a running command's last lines.
    private var live = ""
    private var tail: [String] = []
    private var unfinished = ""
    private var commit = ""
    private var redrawScheduled = false
    private var width = 80, height = 24
    private var started = false
    private var running = true
    private var waiting: CheckedContinuation<String?, Never>?
    private var answering: CheckedContinuation<String?, Never>?
    private var costs: [UUID: CostEntry] = [:]
    private var baseSpent: Double?
    private var baseEstimate = false
    private var lastOutput = ""
    private var ticker: DispatchSourceTimer?
    private var resize: DispatchSourceSignal?
    private var reader: Thread?

    nonisolated(unsafe) private static var saved = termios()
    nonisolated(unsafe) private static var raw = false

    public init(history: [String], color: Bool, handlers: Handlers) {
        input = InputState(history: history)
        style = TerminalStyle(on: color)
        self.handlers = handlers
    }

    /// Whether this process can draw here: both ends are a terminal that takes cursor movement.
    public static var available: Bool {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { return false }
        let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
        return !term.isEmpty && term != "dumb"
    }

    // MARK: Start and stop

    public func start() {
        enterRaw()
        atexit { TerminalUI.leaveRaw() }
        measure()
        let winch = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
        signal(SIGWINCH, SIG_IGN)
        winch.setEventHandler { [weak self] in
            self?.measure()
            self?.flush()
        }
        winch.resume()
        resize = winch
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, self.input.busy else { return }
            self.flush()
        }
        timer.resume()
        ticker = timer
        let thread = Thread { [weak self] in self?.readKeys() }
        thread.stackSize = 1 << 18
        thread.start()
        reader = thread
        queue.async {
            self.started = true
            self.flush()
        }
    }

    public func stop() {
        queue.sync {
            guard started else { return }
            started = false
            running = false
            ticker?.cancel()
            write(screen.clear() + commitTail())
        }
        Self.leaveRaw()
    }

    /// A crash skips `atexit`. Only what's safe in a signal handler: the terminal goes back, then the crash goes on.
    private static func restoreOnCrash() {
        for s in [SIGILL, SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGQUIT] {
            signal(s) { n in
                if TerminalUI.raw {
                    tcsetattr(STDIN_FILENO, TCSANOW, &TerminalUI.saved)
                    let reset = "\u{1B}[?2004l\u{1B}[?25h\r\n"
                    _ = reset.withCString { Darwin.write(STDOUT_FILENO, $0, strlen($0)) }
                }
                signal(n, SIG_DFL)
                raise(n)
            }
        }
    }

    private func enterRaw() {
        Self.restoreOnCrash()
        var t = termios()
        tcgetattr(STDIN_FILENO, &t)
        Self.saved = t
        t.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        t.c_iflag &= ~tcflag_t(ICRNL | INLCR | IXON)
        tcsetattr(STDIN_FILENO, TCSANOW, &t)
        Self.raw = true
        fputs("\u{1B}[?2004h", stdout)                  // pastes arrive marked, not as typing
    }

    private static func leaveRaw() {
        guard raw else { return }
        raw = false
        fputs("\u{1B}[?2004l\u{1B}[?25h", stdout)
        tcsetattr(STDIN_FILENO, TCSANOW, &saved)
    }

    private func measure() {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            width = Int(size.ws_col)
            height = Int(size.ws_row)
        }
    }

    private func readKeys() {
        var decoder = KeyDecoder()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var fds = [pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)]
        var held = false
        while true {
            let ready = poll(&fds, 1, held ? 30 : 500)
            if ready == 0 {
                if held {
                    held = false
                    deliver(decoder.flush())
                }
                if queue.sync(execute: { !running }) { return }
                continue
            }
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            let n = read(STDIN_FILENO, &buffer, buffer.count)
            if n <= 0 {
                if n < 0, errno == EINTR { continue }
                queue.async { self.act(.quit) }
                return
            }
            deliver(decoder.feed(buffer[..<n]))
            held = buffer[n - 1] == 0x1B
        }
    }

    private func deliver(_ keys: [Key]) {
        guard !keys.isEmpty else { return }
        queue.async {
            for key in keys {
                if let action = self.input.handle(key) { self.act(action) }
            }
            self.refreshCompletions()
            self.scheduleRedraw()
        }
    }

    private func refreshCompletions() {
        guard input.canCompleteNow, let (kind, text) = input.completionToken else {
            input.setCompletions([])
            return
        }
        input.setCompletions(handlers.completions(kind, text))
    }

    private func act(_ action: InputAction) {
        switch action {
        case .submit(let text):
            handlers.saveHistory(text)
            if let waiting {
                self.waiting = nil
                input.busy = true
                waiting.resume(returning: text)
            } else if let message = handlers.refuse(text) {
                input.restore(text)
                line(style.yellow(message))
            } else if let answer = handlers.immediately(text, status) {
                if !answer.isEmpty { line(answer) }
            } else {
                input.enqueue(text)
            }
        case .answer(let text):
            let answering = self.answering
            self.answering = nil
            input.endQuestion()
            answering?.resume(returning: text)
        case .stop: handlers.stop()
        case .interrupt:
            if input.question != nil {
                let answering = self.answering
                self.answering = nil
                input.endQuestion()
                answering?.resume(returning: nil)
            } else if !input.busy, !input.buffer.isEmpty {
                input.buffer = TextBuffer()         // as at a shell: the line goes, the program stays
            } else {
                handlers.interrupt()
            }
        case .quit:
            // Not during a run: Ctrl-D only ever means the session is over when nothing is going.
            let waiting = self.waiting
            self.waiting = nil
            waiting?.resume(returning: nil)
        case .cycleMode: handlers.cycleMode()
        case .showOutput:
            line(lastOutput.isEmpty ? style.dim("No tool output yet.") : style.dim(String(lastOutput.prefix(200_000))))
        case .showRewind: handlers.showRewind()
        case .suspend: suspend()
        case .attachImage:
            if let image = handlers.attachImage() { input.addImage(image) } else { line(style.dim("There's no image on the clipboard.")) }
        case .note(let text): line(style.dim(text))
        }
    }

    /// Ctrl-Z, which raw mode doesn't turn into a signal.
    private func suspend() {
        write(screen.clear())
        Self.leaveRaw()
        kill(getpid(), SIGTSTP)
        enterRaw()
        measure()
        flush()
    }

    // MARK: Output

    private func write(_ s: String) {
        var rest = Substring(s).utf8
        while !rest.isEmpty {
            let n = rest.withContiguousStorageIfAvailable { Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) } ?? -1
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            rest = rest.dropFirst(n)
        }
    }

    private func scheduleRedraw() {
        guard started, !redrawScheduled else { return }
        redrawScheduled = true
        queue.asyncAfter(deadline: .now() + 0.016) {
            self.redrawScheduled = false
            self.flush()
        }
    }

    private func flush() {
        guard started else { return }
        let frame = Frame.make(input: input, status: status, live: live + unfinished, tail: tail, width: width, height: height, style: style)
        write(screen.update(commit: commit, frame: frame))
        commit = ""
    }

    private func commitTail() -> String {
        defer {
            commit = ""
            unfinished = ""
        }
        return commit + (unfinished.isEmpty ? "" : unfinished + "\n")
    }

    private func append(_ s: String) {
        unfinished += TerminalText.safe(s)
        guard let last = unfinished.lastIndex(of: "\n") else { return }
        commit += unfinished[...last]
        unfinished = String(unfinished[unfinished.index(after: last)...])
    }

    /// Output: whole lines go above the frame and into the scrollback, an unfinished one waits in the frame.
    public func put(_ s: String) {
        queue.async {
            self.append(s)
            self.scheduleRedraw()
        }
    }

    /// A line of output from the UI's own queue.
    private func line(_ s: String) {
        append(s.hasSuffix("\n") ? s : s + "\n")
        scheduleRedraw()
    }

    /// The reply's unfinished line.
    public func setLive(_ s: String) {
        queue.async {
            self.live = s
            self.scheduleRedraw()
        }
    }

    // MARK: Status

    public func update(_ change: @escaping @Sendable (inout StatusInfo) -> Void) {
        queue.async {
            change(&self.status)
            self.scheduleRedraw()
        }
    }

    /// What the session has spent so far (`CostSummary`); a run's costs are added to it as they arrive.
    public func setSpent(_ summary: CostSummary) {
        queue.async {
            self.costs = [:]
            self.baseSpent = summary.isEmpty ? nil : summary.spent
            self.baseEstimate = summary.estimated
            self.status.spent = self.baseSpent
            self.status.spentIsEstimate = summary.estimated
            self.scheduleRedraw()
        }
    }

    /// An event of the run, for the status line and the running command's lines.
    public func observe(_ event: AgentEvent) {
        queue.async {
            self.apply(event)
            self.scheduleRedraw()
        }
    }

    private func apply(_ event: AgentEvent) {
        let now = Date()
        func doing(_ text: String?) {
            guard status.activity != text else { return }
            status.activity = text
            status.activitySince = now
        }
        switch event {
        case .streaming(let snap):
            doing(snap.isThinking ? "Thinking" : snap.content.isEmpty ? "Waiting for the model" : "Writing")
        case .assistant(let m):
            status.steps += 1
            if let used = m.meta?.usage?.totalTokens { status.contextUsed = used }
            doing(nil)
        case .toolStarted(let call):
            tail = []
            doing(Renderer.summary(call))
        case .toolProgress(_, let text):
            for piece in text.split(separator: "\n") where !piece.contains(BashTool.marker) { tail.append(String(piece)) }
            if tail.count > 4 { tail.removeFirst(tail.count - 4) }
        case .toolFinished(let m):
            tail = []
            lastOutput = m.toolResult?.display ?? m.content
            doing(nil)
        case .promptSize(let tokens): status.contextUsed = tokens
        case .compacting: doing("Summarizing the conversation")
        case .compacted(let c): status.contextUsed = c.tokensAfter
        case .subagentStarted(let info): doing("\(info.agent) subagent: \(info.title)")
        case .modeChanged(let mode):
            status.mode = mode.displayName
            status.nextMode = nil
        case .cost(let e):
            costs[e.id] = e
            let run = CostSummary(Array(costs.values))
            status.spent = (baseSpent ?? 0) + run.spent
            status.spentIsEstimate = baseEstimate || run.estimated
        default: break
        }
    }

    public func setBusy(_ busy: Bool) {
        queue.async {
            self.input.busy = busy
            if busy {
                self.status.runStarted = Date()
                self.status.steps = 0
            } else {
                self.status.runStarted = nil
                self.status.activity = nil
                self.live = ""
                self.tail = []
            }
            self.scheduleRedraw()
        }
    }

    // MARK: Input

    /// The next thing to act on: what's queued, or what's typed; nil to quit. With `stopped`, the run just ended by
    /// being stopped, so what's queued goes back to the draft instead.
    public func next(stopped: Bool) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                if stopped { self.input.unqueue() }
                if let text = self.input.nextQueued() {
                    self.input.busy = true
                    cont.resume(returning: text)
                } else {
                    self.input.busy = false
                    self.waiting = cont
                }
                self.scheduleRedraw()
            }
        }
    }

    /// Asks in the composer's place, keeping what was being typed. Nil if it's dismissed. `card` goes in the output in the
    /// same step, so no key can land between seeing the question and it being open.
    public func ask(_ prompt: String, card: String = "", choices: QuestionChoices? = nil) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                self.append(card)
                // One at a time (the program takes turns), so a second can't be waiting here.
                self.answering = cont
                self.input.beginQuestion(prompt, choices: choices)
                self.scheduleRedraw()
            }
        }
    }

    /// Ends a question that's open (the run it belongs to stopped).
    public func cancelQuestion() {
        queue.async { if self.input.question != nil { self.act(.answer(nil)) } }
    }

    /// Messages typed during the run, for its next step.
    public func takeMessages() -> [String] {
        queue.sync {
            defer { scheduleRedraw() }
            let messages = input.takeQueuedMessages().map(PastedText.withoutMark)
            // They leave the queue here, so this is the scrollback's only record of them.
            for m in messages { line(style.bold("› " + (m.split(whereSeparator: \.isNewline).first.map(String.init) ?? m))) }
            return messages
        }
    }

    /// The images typed with the message that's just been submitted.
    public func takeImages() -> [ImageAttachment] { queue.sync { input.takeImages() } }

    /// Puts text in the composer, to be edited and sent.
    public func setDraft(_ text: String) {
        queue.async {
            self.input.restore(text)
            self.scheduleRedraw()
        }
    }
}
