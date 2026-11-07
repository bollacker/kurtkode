import Darwin
import Foundation

/// Runs a process in its own process group, so a timeout or Stop can kill everything it started.
/// stdin is /dev/null (commands can't wait for input); stdout and stderr are merged.
final class Subprocess: @unchecked Sendable {
    struct Result: Sendable {
        var exitCode: Int32?        // nil when killed by a signal
        var signal: Int32?
        var timedOut: Bool
        var cancelled: Bool
        /// Background processes still holding the output open were stopped after the command exited.
        var killedStragglers: Bool
    }

    private let lock = NSLock()
    private var pid: pid_t = 0

    /// Process groups of the commands running now, so quitting can stop them (they'd outlive the app otherwise).
    static let groupsLock = NSLock()
    nonisolated(unsafe) static var groups: Set<pid_t> = []

    /// SIGTERM to every running command's group, then SIGKILL to what's left after a short wait. For quitting.
    /// `only` picks some groups (tests run commands in parallel; one mustn't stop another's).
    static func terminateAll(grace: TimeInterval = 0.5, only: ((pid_t) -> Bool)? = nil) {
        let all = groupsLock.withLock { groups }.filter { only?($0) ?? true }
        guard !all.isEmpty else { return }
        for g in all { kill(-g, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, all.contains(where: { kill(-$0, 0) == 0 }) { usleep(20_000) }
        for g in all where kill(-g, 0) == 0 { kill(-g, SIGKILL) }
    }
    private var cancelled = false
    private var timedOut = false
    private var exited = false

    static func run(_ argv: [String], cwd: String, environment: [String: String], timeout: TimeInterval,
                    onOutput: @escaping @Sendable (Data) -> Void) async throws -> Result {
        let proc = Subprocess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { cont.resume(returning: try proc.execute(argv, cwd: cwd, environment: environment,
                                                                 timeout: timeout, onOutput: onOutput)) }
                    catch { cont.resume(throwing: error) }
                }
            }
        } onCancel: {
            proc.stop(cancel: true)
        }
    }

    /// Blocking: spawns, streams output until EOF, waits for exit.
    private func execute(_ argv: [String], cwd: String, environment: [String: String], timeout: TimeInterval,
                         onOutput: @escaping @Sendable (Data) -> Void) throws -> Result {
        // Stopped before it started (Stop came while this was on its way to a thread): don't start it.
        if lock.withLock({ cancelled }) {
            return Result(exitCode: nil, signal: nil, timedOut: false, cancelled: true, killedStragglers: false)
        }
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ToolFailure("could not create a pipe (errno \(errno))") }
        let readFD = fds[0], writeFD = fds[1]

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeFD, 1)
        posix_spawn_file_actions_adddup2(&actions, writeFD, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // New process group (pgid = pid); close every descriptor not set up above.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attr, &defaults)

        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (cArgs + cEnv).forEach { free($0) } }

        var child: pid_t = 0
        let rc = posix_spawn(&child, argv[0], &actions, &attr, cArgs, cEnv)
        close(writeFD)
        guard rc == 0 else {
            close(readFD)
            throw ToolFailure("could not start \(argv[0]): \(String(cString: strerror(rc)))")
        }
        // A Stop between the check above and here found no pid to signal: it's this process group's turn now.
        if lock.withLock({ pid = child; return cancelled }) { stop(cancel: true) }
        _ = Self.groupsLock.withLock { Self.groups.insert(child) }
        defer { _ = Self.groupsLock.withLock { Self.groups.remove(child) } }
        let watchdog = DispatchWorkItem { [self] in
            lock.withLock { timedOut = true }
            stop(cancel: false)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Reader: until EOF, which comes when every process holding the pipe has exited.
        let eof = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 16_384)
            while true {
                let n = read(readFD, &buf, buf.count)
                if n > 0 { onOutput(Data(buf[0..<n])) }
                else if n < 0 && errno == EINTR { continue }
                else { break }
            }
            eof.signal()
        }

        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 && errno == EINTR {}
        lock.withLock { exited = true }
        watchdog.cancel()

        // Background jobs the command started may still hold the pipe; give them a moment, then stop them.
        var stragglers = false
        if eof.wait(timeout: .now() + 1) == .timedOut {
            stragglers = true
            kill(-child, SIGKILL)
            _ = eof.wait(timeout: .now() + 2)
        }
        close(readFD)

        let sig = status & 0x7F
        let (isTimedOut, isCancelled) = lock.withLock { (timedOut, cancelled) }
        return Result(exitCode: sig == 0 ? (status >> 8) & 0xFF : nil,
                      signal: sig == 0 ? nil : sig,
                      timedOut: isTimedOut, cancelled: isCancelled, killedStragglers: stragglers)
    }

    /// SIGTERM to the whole group, then SIGKILL if it's still around after 2 seconds.
    func stop(cancel: Bool) {
        let target: pid_t = lock.withLock {
            if cancel { cancelled = true }
            return pid
        }
        guard target > 0 else { return }
        kill(-target, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            if !lock.withLock({ exited }) { kill(-target, SIGKILL) }
        }
    }
}

/// The commands the agent and the user (`!command`) are running.
public enum RunningCommands {
    /// Stops them all (their whole process groups): call when the app quits or the command line exits.
    public static func stopAll() { Subprocess.terminateAll() }
}

/// Keeps the start and end of a long output, and counts what was dropped in between.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let headLimit: Int
    private let tailLimit: Int
    private var head = Data()
    private var tail = Data()
    private(set) var total = 0

    init(headLimit: Int = 64_000, tailLimit: Int = 64_000) {
        self.headLimit = headLimit
        self.tailLimit = tailLimit
    }

    func append(_ d: Data) {
        lock.withLock {
            total += d.count
            if head.count < headLimit {
                let take = min(headLimit - head.count, d.count)
                head.append(d.prefix(take))
                if take < d.count { tail.append(d.dropFirst(take)) }
            } else {
                tail.append(d)
            }
            if tail.count > tailLimit * 2 { tail = Data(tail.suffix(tailLimit)) }
        }
    }

    /// (head, tail, bytes dropped between them)
    func parts() -> (Data, Data, Int) {
        lock.withLock {
            let t = Data(tail.suffix(tailLimit))
            return (head, t, total - head.count - t.count)
        }
    }
}

extension Pipe {
    /// The end to write a child's stdin to. If the child has already gone, a write then fails; otherwise it's a SIGPIPE,
    /// which ends this whole process. Set on this pipe only: ignoring the signal would pass to every command run.
    var inputForChild: FileHandle {
        let handle = fileHandleForWriting
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        return handle
    }
}
