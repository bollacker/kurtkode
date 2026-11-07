import AgentCore
import Foundation

/// Shift-Tab's mode changes between runs. Each press steps on from the mode the last press picked, not from the
/// session's mode, which a change still being applied hasn't reached yet; the changes are applied one after another in
/// the order of the presses, so the last one picked is the one that holds. `settled()` waits for them: a message sent
/// right after a press runs in the mode it shows.
public final class ModeCycle: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: PermissionMode?
    private var picks = 0
    private var chain: Task<Void, Never>?
    private let apply: @Sendable (PermissionMode) async -> Void

    public init(apply: @escaping @Sendable (PermissionMode) async -> Void) {
        self.apply = apply
    }

    /// The mode picked and not yet applied, if any.
    public var pendingMode: PermissionMode? { lock.withLock { pending } }

    /// One press: the mode after `current` (or after the pending pick) in `order`, queued to be applied. Returns it.
    @discardableResult
    public func step(from current: PermissionMode, order: [PermissionMode]) -> PermissionMode {
        lock.withLock {
            let now = pending ?? current
            let next = order[((order.firstIndex(of: now) ?? 0) + 1) % order.count]
            pending = next
            picks += 1
            let number = picks, previous = chain, apply = apply
            chain = Task { [weak self] in
                await previous?.value
                await apply(next)
                guard let self else { return }
                self.lock.withLock { if self.picks == number { self.pending = nil } }
            }
            return next
        }
    }

    /// Waits until every pick so far is applied.
    public func settled() async {
        await lock.withLock { chain }?.value
    }
}
