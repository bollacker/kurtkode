import Foundation

/// Live tool output, batched: text that arrives in many small pieces (a build printing thousands of lines a
/// second) is passed on at most every `interval`, in order. Sending each piece on its own kept the app's main
/// thread fully busy for as long as such a command ran, and separate tasks per piece could arrive out of order.
final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var pending: Task<Void, Never>?
    private let interval: Duration
    private let send: @Sendable (String) async -> Void

    init(interval: Duration = .milliseconds(100), send: @escaping @Sendable (String) async -> Void) {
        self.interval = interval
        self.send = send
    }

    /// Adds text; called from any thread.
    func add(_ text: String) {
        lock.withLock {
            buffer += text
            guard pending == nil else { return }
            pending = Task { [interval] in
                try? await Task.sleep(for: interval)
                let batch = lock.withLock { () -> String in
                    defer { buffer = ""; pending = nil }
                    return buffer
                }
                if !batch.isEmpty { await send(batch) }
            }
        }
    }

    /// Sends whatever is left, after any batch already on its way. Call when the tool has finished.
    func flush() async {
        let inFlight = lock.withLock { pending }
        await inFlight?.value
        let rest = lock.withLock { () -> String in defer { buffer = "" }; return buffer }
        if !rest.isEmpty { await send(rest) }
    }
}
