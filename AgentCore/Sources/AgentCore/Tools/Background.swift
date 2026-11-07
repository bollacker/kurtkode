import Darwin
import Foundation

/// Commands started with bash's `run_in_background` (B2): each in its own process group, its output going to a file,
/// read in pieces with `bash_output` and stopped with `kill_shell`. One registry per session (in its `ShellState`), so a
/// server started in one turn can be checked in the next. Quitting stops them all (`RunningCommands.stopAll`).
public final class BackgroundCommands: @unchecked Sendable {
    public struct Job: Sendable {
        public var id: String
        public var command: String
        public var pid: pid_t
        public var output: URL
        public var started: Date
        public var ended: Date?
        public var exitCode: Int32?
        public var signal: Int32?
        /// Stopped by kill_shell (or Stop).
        public var stopped = false
        /// Bytes of the output already returned by bash_output.
        var read: UInt64 = 0
        /// Processes it started outlive it (`server &`): its process group is still there.
        public var leftRunning = false

        public var isRunning: Bool { ended == nil }

        /// "running for 42 s", "exited with code 0 after 12 s", "stopped after 3 s".
        public var state: String {
            let secs = Int((ended ?? Date()).timeIntervalSince(started).rounded())
            guard ended != nil else { return "running for \(secs) s" }
            if stopped { return "stopped after \(secs) s" }
            let left = leftRunning ? ", but processes it started are still running (kill_shell stops them)" : ""
            if let exitCode { return "exited with code \(exitCode) after \(secs) s" + left }
            return "killed by signal \(signal ?? 0) after \(secs) s" + left
        }
    }

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private var order: [String] = []
    private var next = 1
    /// Held while an output file is read or trimmed, so a read's offset always means the file it reads.
    private let fileLock = NSLock()
    /// A timer per running job that trims its output file (see `trim`).
    private var trimmers: [String: DispatchSourceTimer] = [:]
    /// An output file past `trimAbove` bytes is cut to its last `keepBytes` (a chatty server left for hours mustn't fill the
    /// disk); `bash_output` reads at most `readWindow` bytes from its end.
    var trimAbove: UInt64 = 75_000_000
    var keepBytes: UInt64 = 50_000_000
    var readWindow = 1_000_000

    public init() {}

    public var all: [Job] { lock.withLock { order.compactMap { jobs[$0] } } }
    public func job(_ id: String) -> Job? { lock.withLock { jobs[id] } }

    /// Starts `argv` in the background; its stdout and stderr go to `output`.
    func start(_ argv: [String], command: String, cwd: String, environment: [String: String], output: URL) throws -> Job {
        let id = lock.withLock { () -> String in
            defer { next += 1 }
            return "bg\(next)"
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Registered before the spawn's waiter can report an exit.
        let started = Date()
        lock.withLock {
            jobs[id] = Job(id: id, command: command, pid: 0, output: output, started: started)
            order.append(id)
        }
        startTrimming(id)          // before the spawn, so a command that ends at once still stops it
        do {
            let pid = try Subprocess.spawnDetached(argv, cwd: cwd, environment: environment, output: output) { [weak self] status in
                self?.finished(id, status: status)
            } groupEnded: { [weak self] in
                self?.lock.withLock { self?.jobs[id]?.leftRunning = false }
                self?.stopTrimming(id)
            }
            return lock.withLock {
                jobs[id]?.pid = pid
                return jobs[id]!
            }
        } catch {
            stopTrimming(id)
            lock.withLock { jobs[id] = nil; order.removeAll { $0 == id } }
            throw error
        }
    }

    private func finished(_ id: String, status: Int32) {
        let sig = status & 0x7F
        lock.withLock {
            jobs[id]?.ended = Date()
            if sig == 0 { jobs[id]?.exitCode = (status >> 8) & 0xFF } else { jobs[id]?.signal = sig }
            if let pid = jobs[id]?.pid, pid > 0 { jobs[id]?.leftRunning = kill(-pid, 0) == 0 }
        }
    }

    /// Stops every job still running, or whose processes are (a subagent's, when it ends).
    public func stopAll() {
        for j in all where j.isRunning || j.leftRunning { stop(j.id) }
    }

    /// SIGTERM to the job's group, SIGKILL two seconds later to whatever of the group is still there (the shell may
    /// be gone while what it started isn't). False: no such job, or it had ended.
    @discardableResult
    public func stop(_ id: String) -> Bool {
        guard let j = job(id), j.isRunning || j.leftRunning, j.pid > 0, kill(-j.pid, 0) == 0 || j.isRunning else { return false }
        lock.withLock { jobs[id]?.stopped = true }
        kill(-j.pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if kill(-j.pid, 0) == 0 { kill(-j.pid, SIGKILL) }
        }
        return true
    }

    /// Whether anything of the job's process group is still running.
    func groupAlive(_ id: String) -> Bool {
        guard let j = job(id), j.pid > 0 else { return false }
        return kill(-j.pid, 0) == 0
    }

    /// Waits until the job ends or `seconds` pass (polling; the job's own thread records the exit).
    public func wait(_ id: String, seconds: Double) async -> Job? {
        let deadline = Date().addingTimeInterval(seconds)
        while let j = job(id), j.isRunning, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return job(id)
    }

    /// The output written since the last call (at most `max` bytes: the end of it), how many earlier new bytes that
    /// left out, and the end of the new part that was read (for the error scan). Only the last `readWindow` bytes are
    /// read: a command polled after hours of output would otherwise be read into memory whole.
    func takeNew(_ id: String, max: Int) -> (shown: String, skipped: Int, all: String) {
        fileLock.withLock {
            guard let j = job(id), let h = try? FileHandle(forReadingFrom: j.output) else { return ("", 0, "") }
            defer { try? h.close() }
            let end = (try? h.seekToEnd()) ?? j.read
            let from = Swift.min(j.read, end)
            let start = Swift.max(from, end > UInt64(readWindow) ? end - UInt64(readWindow) : 0)
            try? h.seek(toOffset: start)
            let data = (try? h.read(upToCount: Int(end - start))) ?? Data()
            lock.withLock { jobs[id]?.read = start + UInt64(data.count) }
            let unread = Int(start - from)
            let all = String(decoding: data, as: UTF8.self)
            guard data.count > max || unread > 0 else { return (all, 0, all) }
            var cut = data.suffix(max)
            if let nl = cut.firstIndex(of: 0x0A) { cut = cut[(nl + 1)...] }
            return (String(decoding: cut, as: UTF8.self), unread + data.count - cut.count, all)
        }
    }

    private func startTrimming(_ id: String) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.trim(id) }
        lock.withLock { trimmers[id] = timer }
        timer.resume()
    }

    private func stopTrimming(_ id: String) {
        lock.withLock { trimmers.removeValue(forKey: id) }?.cancel()
    }

    /// Cuts the job's output file to its last `keepBytes` when it's past `trimAbove`, behind a line saying how much went,
    /// and moves the read offset with it. The command keeps appending (O_APPEND) while this runs: what it writes between
    /// the copy and the truncation is lost.
    func trim(_ id: String) {
        fileLock.withLock {
            guard let j = job(id), let size = (try? FileManager.default.attributesOfItem(atPath: j.output.path))?[.size] as? UInt64,
                  size > trimAbove, let h = try? FileHandle(forUpdating: j.output) else { return }
            defer { try? h.close() }
            let dropped = size - keepBytes
            let tail = FileManager.default.temporaryDirectory.appending(path: "kk-bg-trim-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: tail.path, contents: nil), let t = try? FileHandle(forUpdating: tail) else { return }
            defer { try? t.close(); try? FileManager.default.removeItem(at: tail) }
            // Through a file in pieces, so trimming doesn't hold the kept part in memory.
            try? h.seek(toOffset: dropped)
            while let piece = try? h.read(upToCount: 1 << 20), !piece.isEmpty { try? t.write(contentsOf: piece) }
            let note = Data("[kurtkode cut the first \(dropped) bytes of this output to keep the file small.]\n".utf8)
            try? h.truncate(atOffset: 0)
            try? h.write(contentsOf: note)
            try? t.seek(toOffset: 0)
            while let piece = try? t.read(upToCount: 1 << 20), !piece.isEmpty { try? h.seekToEnd(); try? h.write(contentsOf: piece) }
            lock.withLock {
                let read = jobs[id]?.read ?? 0
                jobs[id]?.read = read > dropped ? read - dropped + UInt64(note.count) : 0
            }
        }
    }
}

extension Subprocess {
    /// Starts a process in its own group with stdin from /dev/null and stdout and stderr appended to `output`, and
    /// returns at once; `onExit` gets its wait status from a thread that waits for it.
    static func spawnDetached(_ argv: [String], cwd: String, environment: [String: String], output: URL,
                              onExit: @escaping @Sendable (Int32) -> Void,
                              groupEnded: @escaping @Sendable () -> Void = {}) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Default handlers and nothing blocked: the spawning thread's mask would be inherited, and a job started from a
        // thread that blocks SIGTERM ignored kill_shell (seen in tests).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attr, &none)

        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (cArgs + cEnv).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, argv[0], &actions, &attr, cArgs, cEnv)
        guard rc == 0 else { throw ToolFailure("could not start \(argv[0]): \(String(cString: strerror(rc)))") }
        _ = groupsLock.withLock { groups.insert(child) }
        let pid = child
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            onExit(status)
            // What it started in its group (`server &`) can outlive it: the group stays known (Quit stops it) until it's
            // empty.
            while kill(-pid, 0) == 0 { usleep(500_000) }
            _ = groupsLock.withLock { groups.remove(pid) }
            groupEnded()
        }
        return pid
    }
}

/// The tools offered with bash for its background commands.
public enum BackgroundTools {
    public static let all: [any Tool] = [BashOutputTool(), KillShellTool()]
}

/// Reads a background command's new output (B2).
public struct BashOutputTool: Tool {
    public init() {}
    public let name = "bash_output"
    public let description = """
        Read the new output of a command started with bash run_in_background, and whether it is still running. Each \
        call returns only what was written since the last one. To wait for it to finish, pass wait (seconds) instead \
        of running sleep.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "id": ["type": "string", "description": "The id bash gave it, e.g. \"bg1\". May be left out when only one runs."],
            "wait": ["type": "integer", "description": "Seconds to wait for it to finish before reading (max 300). Default 0."],
        ],
    ]
    public let risk = ToolRisk.read

    public func summary(_ args: ToolArguments) -> String {
        "Check \(args.string("id") ?? args.string("bash_id") ?? "background command")" + (args.int("wait").map { $0 > 0 ? ", waiting up to \($0) s" : "" } ?? "")
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let jobs = context.shell.jobs
        let id = try BackgroundCommands.pick(args.string("id") ?? args.string("bash_id") ?? args.string("shell_id"), in: jobs)
        let wait = Double(min(300, max(0, args.int("wait") ?? 0)))
        if wait > 0 { _ = await jobs.wait(id, seconds: wait) }
        guard let job = jobs.job(id) else { throw ToolFailure("no background command \(id)") }
        let (shown, skipped, all) = jobs.takeNew(id, max: max(1000, context.maxOutputBytes - 1500))
        var text = shown.trimmingCharacters(in: .newlines)
        if text.isEmpty { text = "(no new output)" }
        if skipped > 0 {
            text = "[… \(skipped) earlier bytes of new output not shown …]\n" + text
            text += "\n\n" + BashTool.hiddenErrorsNote(full: all, shown: shown)
        }
        text += "\n\n[\(id) (\(BackgroundCommands.short(job.command))): \(job.state). Its whole output is in \(job.output.path).]"
        return ToolOutput(text: text, truncated: skipped > 0, exitCode: job.exitCode)
    }
}

/// Stops a background command (B2).
public struct KillShellTool: Tool {
    public init() {}
    public let name = "kill_shell"
    public let description = "Stop a command started with bash run_in_background (and everything it started)."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": ["id": ["type": "string", "description": "The id bash gave it, e.g. \"bg1\"."]],
        "required": ["id"],
    ]
    // It stops only what this session started in the background: no approval, like reading.
    public let risk = ToolRisk.read

    public func summary(_ args: ToolArguments) -> String { "Stop \(args.string("id") ?? args.string("shell_id") ?? "background command")" }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let jobs = context.shell.jobs
        let id = try BackgroundCommands.pick(args.string("id") ?? args.string("shell_id") ?? args.string("bash_id"), in: jobs)
        guard let before = jobs.job(id) else { throw ToolFailure("no background command \(id)") }
        guard jobs.stop(id) else {
            return ToolOutput(text: "\(id) had already ended, with nothing it started still running: \(before.state). Its output "
                              + "is in \(before.output.path).")
        }
        var after = await jobs.wait(id, seconds: 3) ?? before
        // What the shell started may take until the SIGKILL to go.
        let deadline = Date().addingTimeInterval(3)
        while jobs.groupAlive(id), Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        after = jobs.job(id) ?? after
        return ToolOutput(text: "Stopped \(id) (\(BackgroundCommands.short(before.command))): \(after.state). "
                          + "Its output is in \(after.output.path).")
    }
}

extension BackgroundCommands {
    /// The job a call means: the id given, or the only one there is.
    static func pick(_ id: String?, in jobs: BackgroundCommands) throws -> String {
        let all = jobs.all
        if let id, !id.isEmpty {
            let lower = id.lowercased().trimmingCharacters(in: .whitespaces)
            let wanted = lower.hasPrefix("bg") ? lower : "bg" + lower
            if jobs.job(wanted) != nil { return wanted }
            throw ToolFailure("no background command \"\(id)\". " + list(all))
        }
        if all.count == 1 { return all[0].id }
        if let only = all.filter(\.isRunning).first, all.filter(\.isRunning).count == 1 { return only.id }
        throw ToolFailure("which background command? Give id. " + list(all))
    }

    static func list(_ all: [Job]) -> String {
        all.isEmpty ? "None has been started (bash with run_in_background: true starts one)."
            : "They are: " + all.map { "\($0.id) (\(short($0.command)), \($0.state))" }.joined(separator: "; ") + "."
    }

    static func short(_ command: String) -> String {
        let first = command.split(separator: "\n").first.map(String.init) ?? command
        return first.count > 60 ? String(first.prefix(57)) + "…" : first
    }
}
