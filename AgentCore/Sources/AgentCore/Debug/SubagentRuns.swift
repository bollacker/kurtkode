import Foundation

/// A subagent run at a glance, for the Debug window: what it was, how it went, and what went wrong in its turns.
public struct SubagentRunSummary: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var agent: String
    public var title: String
    public var model: String
    /// The `task` call that started it.
    public var callID: String?
    /// "running" until its end record; then how it stopped (completed, stepLimit, cancelled, …).
    public var state: String
    public var isRunning: Bool
    public var steps: Int
    public var toolCalls: Int
    public var promptTokens: Int
    public var completionTokens: Int
    /// What it spent (`CostEntry.spent`: charged where known, else list price), summaries included.
    public var cost: Double
    /// Its whole time when finished; the time so far while it runs.
    public var seconds: Double
    public var report: String?
    /// Badges from its turns (lost, error, bad arguments, …) with how many turns had each.
    public var flags: [String: Int]
    public var started: Date

    public init(_ run: Session, now: Date = Date()) {
        id = run.header.id
        agent = run.header.agent ?? "subagent"
        title = run.displayTitle
        model = run.model
        callID = run.header.parentCallID
        started = run.header.createdAt
        let turns = SessionTimeline.items(run).compactMap { if case .turn(let t) = $0 { t } else { nil } }
        var flags: [String: Int] = [:]
        for t in turns { for f in t.flags { flags[f, default: 0] += 1 } }
        self.flags = flags
        cost = CostMeter.spent(run)
        if let end = run.subagentEnd {
            state = end.stop
            isRunning = false
            steps = end.steps
            toolCalls = end.toolCalls
            promptTokens = end.promptTokens
            completionTokens = end.completionTokens
            seconds = end.seconds
            report = end.report
        } else {
            state = "running"
            isRunning = true
            steps = turns.count
            toolCalls = turns.map(\.calls.count).reduce(0, +)
            let usage = turns.compactMap { $0.reply.meta?.usage }
            promptTokens = usage.map(\.promptTokens).reduce(0, +)
            completionTokens = usage.map(\.completionTokens).reduce(0, +)
            seconds = now.timeIntervalSince(run.header.createdAt)
            report = nil
        }
    }
}

extension SubagentRunSummary {
    /// One line for a list: "explore · Find the parser · completed · 4 turns, 3 calls · 22.8 s · gemma-…".
    public var line: String {
        "\(agent) · \(title) · \(state) · \(steps) turns, \(toolCalls) calls · "
            + String(format: "%.1f s", seconds) + (isRunning ? " so far" : "") + " · \(model)"
    }
}

extension SessionStats {
    /// Adds a session's subagent runs to its totals (they're kept apart from the main agent's own). Given the session
    /// they belong to (`parent`), it leaves out a fork's copies of its original's runs: that spending was the original's.
    public mutating func add(subagents runs: [Session], of parent: SessionHeader? = nil) {
        for run in runs {
            if let parent, let owner = run.header.parent, owner != parent.id { continue }
            let s = SessionStats(run)
            subagents += 1
            subagentToolCalls += s.toolCalls
            subagentPromptTokens += s.promptTokens
            subagentCompletionTokens += s.completionTokens
            subagentCost += s.costByProvider.values.reduce(0, +)
        }
    }
}
