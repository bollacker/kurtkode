import Foundation

/// Editing the model pool in place (Settings → Pool), rather than by hand in pool.json: what an entry may be, and the
/// changes the editor makes. Every change keeps the retry ladder's rungs numbered 0, 1, 2… in their order.
extension PoolEntry {
    /// The kinds of endpoint an entry can name instead of a saved endpoint's id, with what each means.
    public static let endpointKinds: [(id: String, label: String)] = [
        ("openrouter", "OpenRouter"),
        ("anthropic", "Anthropic API"),
        ("gemini", "Gemini API"),
        ("claude", "Claude (Anthropic API, else OpenRouter)"),
    ]

    /// The models the "claude" endpoint kind takes.
    public static let claudeAliases = ["haiku", "sonnet", "opus"]

    /// A new entry for the editor: a cheap OpenRouter subagent, enabled, off the ladder.
    public static var blank: PoolEntry {
        PoolEntry(endpoint: "openrouter", model: "", providers: ProviderRouting(dataCollection: "deny"), tier: .cheap,
                  roles: [.subagent])
    }
}

extension ModelPool {
    /// Why `entry` can't be saved at `index` (nil: as a new entry), or an empty list. An entry needs an endpoint and a
    /// model, and no other entry may have the same endpoint, model and reasoning (the pool tells entries apart by them).
    public func problems(_ entry: PoolEntry, at index: Int?) -> [String] {
        var out: [String] = []
        if entry.endpoint.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Choose an endpoint.") }
        if entry.model.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Enter a model.") }
        if entry.endpoint.lowercased() == "claude", !entry.model.isEmpty, !ModelAlias.isAlias(entry.model) {
            out.append("The Claude endpoint takes haiku, sonnet or opus.")
        }
        if let other = entries.indices.first(where: { $0 != index && entries[$0].id == entry.id }) {
            out.append("Entry \(other + 1) already has this endpoint, model and reasoning.")
        }
        return out
    }

    /// What may be wrong with `entry` but doesn't stop it being saved.
    public func warnings(_ entry: PoolEntry, endpoints: [Endpoint]) -> [String] {
        var out: [String] = []
        if entry.roles.isEmpty { out.append("With no role, nothing picks this entry.") }
        if entry.ladder != nil, !entry.roles.contains(.subagent) {
            out.append("Only subagent entries are retried on: give it the subagent role, or take it off the ladder.")
        }
        if !entry.model.isEmpty, Self.resolve(entry, endpoints: endpoints) == nil {
            out.append("No endpoint set up here serves it, so it's skipped until one is.")
        }
        return out
    }

    /// Saves `entry` over the one at `index`, or adds it at the end (nil). `rung` is its place on the retry ladder
    /// (0 first), which moves the rungs at and after it down one; nil takes it off the ladder. Throws the first problem.
    public mutating func put(_ entry: PoolEntry, at index: Int?, rung: Int?) throws {
        if let problem = problems(entry, at: index).first { throw PoolEditError(description: problem) }
        var e = entry
        e.model = e.model.trimmingCharacters(in: .whitespaces)
        e.endpoint = e.endpoint.trimmingCharacters(in: .whitespaces)
        e.ladder = nil
        let i: Int
        if let index, entries.indices.contains(index) { entries[index] = e; i = index } else { entries.append(e); i = entries.count - 1 }
        setRung(of: i, to: rung)
    }

    /// Puts the entry at `index` at place `rung` on the retry ladder (clamped to the ladder's length), or takes it off.
    public mutating func setRung(of index: Int, to rung: Int?) {
        guard entries.indices.contains(index) else { return }
        var order = rungOrder().filter { $0 != index }
        if let rung { order.insert(index, at: min(max(rung, 0), order.count)) }
        for i in entries.indices { entries[i].ladder = nil }
        for (n, i) in order.enumerated() { entries[i].ladder = n }
    }

    /// The indices of the entries on the ladder, lowest rung first (ties in pool order).
    public func rungOrder() -> [Int] {
        entries.indices.filter { entries[$0].ladder != nil }.sorted { (entries[$0].ladder!, $0) < (entries[$1].ladder!, $1) }
    }

    /// How many entries are on the ladder.
    public var rungCount: Int { entries.lazy.filter { $0.ladder != nil }.count }

    public mutating func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        renumberRungs()
    }

    /// Moves the entry at `index` up (-1) or down (+1) in pool order, which decides which judge, reviewer or summarizer
    /// is tried first.
    public mutating func move(_ index: Int, by offset: Int) {
        let to = index + offset
        guard entries.indices.contains(index), entries.indices.contains(to) else { return }
        entries.swapAt(index, to)
    }

    /// Rungs back to 0, 1, 2… in their order, as hand-written pools may leave gaps.
    public mutating func renumberRungs() {
        let order = rungOrder()
        for (n, i) in order.enumerated() { entries[i].ladder = n }
    }

    /// Copies an unreadable pool.json aside (pool.json.unreadable-<time>) before it's saved over, so hand edits that
    /// broke it aren't lost. Returns the copy, or nil when there's nothing unreadable there.
    @discardableResult
    public static func backUpUnreadable(_ url: URL, now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path), loadChecked(url).problem != nil else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let copy = url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".unreadable-" + f.string(from: now))
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
}

public struct PoolEditError: Error, CustomStringConvertible, Sendable {
    public let description: String
}
