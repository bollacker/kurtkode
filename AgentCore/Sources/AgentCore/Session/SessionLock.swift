import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Held while a run goes on a session, so the app and the command line (which share sessions) don't both run it at
/// once. Without it each appended to the session file with its own copy of the history, and the conversation split
/// without a word (the reload-before-send check only catches what the other wrote before this run started).
///
/// An advisory `flock` on `locks/<session id>.lock` beside the sessions folder, taken without waiting. The kernel
/// drops it when its process ends, so a crash or a kill never leaves a stale lock; the descriptor is close-on-exec, so
/// commands the run starts don't keep it. The file says who holds it, for the message the other process shows.
public final class SessionLock: @unchecked Sendable {
    public let url: URL
    private var fd: Int32
    private let guardLock = NSLock()

    private init(url: URL, fd: Int32) {
        self.url = url
        self.fd = fd
    }

    deinit { release() }

    public enum Outcome: Sendable {
        case acquired(SessionLock)
        /// Another process (or another window of this one) is running the session; who, as it described itself.
        case held(by: String)
    }

    /// The lock file for a session. Outside the sessions folder, so listings never see it.
    public static func url(forSession id: UUID, sessionsRoot: URL) -> URL {
        sessionsRoot.deletingLastPathComponent().appending(path: "locks/\(id.uuidString).lock")
    }

    /// Takes the lock for `holder` ("the kurtkode app (pid 123)"), or says who has it. When the lock file can't be
    /// opened at all the run goes ahead unlocked (a lock that can't be taken mustn't stop the user's work).
    public static func acquire(_ url: URL, holder: String) -> Outcome {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return .acquired(SessionLock(url: url, fd: -1)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let who = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            close(fd)
            return .held(by: who.isEmpty ? "another kurtkode" : who)
        }
        ftruncate(fd, 0)
        let line = Array((holder + "\n").utf8)
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        return .acquired(SessionLock(url: url, fd: fd))
    }

    /// Who is running the session now, or nil when nobody is. Only looks: it takes no lock and writes nothing, so a
    /// status check (the app makes one per redraw) can't make the other process's `acquire` fail or blank its line.
    /// `F_GETLK` reports `flock` locks on macOS, this process's own included.
    public static func holder(_ url: URL) -> String? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var probe = flock()
        probe.l_type = Int16(F_WRLCK)
        probe.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_GETLK, &probe) == 0, probe.l_type != Int16(F_UNLCK) else { return nil }
        let who = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return who.isEmpty ? "another kurtkode" : who
    }

    /// Runs an operation that adds to or restores a session (a `!command`, a compaction, a retry, a rewind) while
    /// holding the session's lock, so the app and the command line can't interleave records (a command's output landing
    /// between a reply's tool calls and their results). Takes the lock without waiting and throws `SessionBusy` when
    /// another kurtkode holds it; then `reload` picks up what the other wrote before, `body` runs, and the lock goes.
    public static func withLock<T: Sendable>(_ url: URL, holder: String, isolation: isolated (any Actor)? = #isolation,
                                   reload: () async -> Void, _ body: () async throws -> T) async throws -> T {
        switch acquire(url, holder: holder) {
        case .held(let who): throw SessionBusy(who: who)
        case .acquired(let lock):
            defer { lock.release() }
            await reload()
            return try await body()
        }
    }

    /// What to tell the user when the session is busy.
    public static func busyMessage(_ who: String) -> String {
        "This session is running in \(who). Wait for that run to finish, or use another session."
    }

    /// The holder's description for this process.
    public static func describe(_ program: String) -> String { "\(program) (pid \(getpid()))" }

    public func release() {
        guardLock.withLock {
            guard fd >= 0 else { return }
            ftruncate(fd, 0)
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
    }
}

/// A session operation refused because another kurtkode is running the session (`SessionLock.withLock`).
public struct SessionBusy: LocalizedError, Sendable {
    public var who: String
    public var errorDescription: String? { SessionLock.busyMessage(who) }
}
