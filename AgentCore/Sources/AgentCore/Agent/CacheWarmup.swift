import Foundation

/// Holds back the subagents of one fan-out (several `task` calls in one reply) until the first of each kind has started
/// its first reply. Runs of one kind on one model send the same system prompt and tools, and a server's cache entry
/// can be read only once the response that writes it has started (Anthropic's documentation; Claude Code holds a
/// workflow's agents up to 5 s for the same reason): started together, each would write that prefix again
/// (CACHING_PLAN.md 1.4).
public actor CacheWarmup {
    private var leaders: Set<String> = []
    private var warm: Set<String> = []

    public init() {}

    /// Returns at once for the first run with `key`, which writes the cache; a later one returns when that run's first
    /// reply has started (`warmed`) or after `limit`.
    public func admit(_ key: String, limit: Duration = .seconds(5)) async {
        if leaders.insert(key).inserted || warm.contains(key) { return }
        let deadline = ContinuousClock.now + limit
        while !warm.contains(key), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The first run with `key` has started replying (or ended): its prefix is in the server's cache now.
    public func warmed(_ key: String) { warm.insert(key) }
}
