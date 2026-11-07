import Foundation

/// Reads a pipe to its end on a background thread, so a process writing to it can't stall on a full pipe
/// while another of its pipes is being read. `wait()` returns everything read.
final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global().async { [self] in
            let d = handle.readDataToEndOfFile()
            lock.withLock { data = d }
            done.signal()
        }
    }

    func wait() -> Data {
        done.wait()
        return lock.withLock { data }
    }

    /// Everything read, waiting at most `timeout` seconds for the end (nil: no limit); nil when it hasn't ended by then
    /// (another process still holds the pipe open).
    func wait(timeout: Double?) -> Data? {
        guard let timeout else { return wait() }
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { data }
    }
}

/// A flag set on one thread and read on another.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
