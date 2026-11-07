import AgentCore
import SwiftUI

/// Which subagent run the Debug window should show (set by a task card's "Open in Debug").
struct DebugFocus: Equatable {
    var session: UUID
    var run: UUID
}

private struct ChatSessionIDKey: EnvironmentKey { static let defaultValue: UUID? = nil }

extension EnvironmentValues {
    /// The session a chat transcript shows, for views inside it (a task card opening its run in the Debug window).
    var chatSessionID: UUID? {
        get { self[ChatSessionIDKey.self] }
        set { self[ChatSessionIDKey.self] = newValue }
    }
}

/// A subagent run at a glance: agent, model, how it went, and a way in. Follows a running run.
struct SubagentSection: View {
    @Environment(AppModel.self) private var app
    let runID: UUID
    let parent: SessionHeader
    let open: ((UUID) -> Void)?
    @State private var summary: SubagentRunSummary?
    @State private var missing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subagent").font(.subheadline.weight(.semibold))
            if let s = summary {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    ForEach(rows(s), id: \.0) { label, value in
                        GridRow {
                            Text(label).foregroundStyle(.secondary)
                            Text(value).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
                if let open {
                    Button("Open Subagent") { open(runID) }
                        .help("Show this run's own Timeline and Journal (a breadcrumb leads back)")
                }
            } else if missing {
                Text("Its record isn't there (moved or deleted).").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: runID) {
            let store = app.sessionStore
            while !Task.isCancelled {
                let run = await store.subagentRun(runID, of: parent)
                summary = run.map { SubagentRunSummary($0) }
                missing = run == nil
                guard summary?.isRunning == true else { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func rows(_ s: SubagentRunSummary) -> [(String, String)] {
        var r: [(String, String)] = [
            ("Agent", "\(s.agent) · \(s.title)"),
            ("Model", s.model),
            ("State", Self.stateText(s.state)),
            ("Steps", "\(s.steps) turns · \(s.toolCalls) tool calls"),
            ("Tokens", "\(s.promptTokens) in · \(s.completionTokens) out"),
            ("Time", String(format: "%.1f s%@", s.seconds, s.isRunning ? " so far" : "")),
        ]
        if !s.flags.isEmpty {
            r.append(("Problems", s.flags.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")))
        }
        return r
    }

    nonisolated static func stateText(_ state: String) -> String {
        switch state {
        case "running": "Running"
        case "completed": "Completed"
        case "stepLimit": "Stopped at its step limit"
        case "costLimit": "Stopped at the cost limit"
        case "cancelled": "Stopped by the user"
        case "denied": "Stopped: an action was denied"
        case "truncated": "Its report was cut off"
        default: state
        }
    }
}

/// One subagent run as the inspector lists it: from its record, then from live events while it runs.
struct SubagentRow: Identifiable, Equatable {
    var id: UUID
    var agent: String
    var title: String
    var model: String
    var started: Date
    var steps = 0
    var toolCalls = 0
    var promptTokens = 0
    var completionTokens = 0
    /// What its replies cost (reported or at list price); 0 for local models.
    var cost = 0.0
    var waiting = false
    var waitingForSlot = false
    var end: SubagentEnd?
    /// Recorded without an end and not running now: the app quit or crashed during it.
    var interrupted = false
    /// How it was judged: the automatic checks, the agent's rating, a grader's, the user's.
    var judgments: [RunJudgment] = []

    var isRunning: Bool { end == nil && !interrupted }

    init(_ info: SubagentInfo) {
        id = info.id
        agent = info.agent
        title = info.title
        model = info.model
        started = info.started
    }

    init(_ s: SubagentRunSummary, interrupted: Bool) {
        id = s.id
        agent = s.agent
        title = s.title
        model = s.model
        started = s.started
        steps = s.steps
        toolCalls = s.toolCalls
        promptTokens = s.promptTokens
        completionTokens = s.completionTokens
        cost = s.cost
        if !s.isRunning {
            end = SubagentEnd(stop: s.state, steps: s.steps, toolCalls: s.toolCalls, promptTokens: s.promptTokens,
                              completionTokens: s.completionTokens, seconds: s.seconds, report: s.report ?? "")
        }
        self.interrupted = interrupted
    }

    mutating func update(_ p: SubagentProgress) {
        steps = p.steps
        toolCalls = p.toolCalls
        promptTokens = p.promptTokens
        completionTokens = p.completionTokens
        waiting = p.waitingForApproval
        waitingForSlot = p.waitingForSlot
        cost = p.cost
    }

    mutating func finish(_ e: SubagentEnd) {
        end = e
        waiting = false
        waitingForSlot = false
        steps = e.steps
        toolCalls = e.toolCalls
        promptTokens = e.promptTokens
        completionTokens = e.completionTokens
    }

    var stateText: String {
        if interrupted { return "Cut off (no end recorded)" }
        if let end { return SubagentSection.stateText(end.stop) }
        return waiting ? "Waiting for your approval" : waitingForSlot ? "Waiting for a free slot" : "Running"
    }
}

/// The inspector's Agents tab: the session's subagent runs, newest first, with Stop for a running one.
struct SubagentsPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let controller: ChatController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.subagents.isEmpty {
                Text("No subagents yet. The agent hands a self-contained job to one with the task tool.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(controller.subagents.reversed()) { row in
                SubagentRowView(row: row,
                                stop: row.isRunning ? { controller.stopSubagent(row.id) } : nil,
                                judge: row.isRunning ? nil : { controller.judgeSubagent(row.id, verdict: $0) },
                                openInDebug: {
                                    app.debugFocus = DebugFocus(session: controller.session.header.id, run: row.id)
                                    openWindow(id: "debug")
                                })
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubagentRowView: View {
    let row: SubagentRow
    let stop: (() -> Void)?
    let judge: ((Int) -> Void)?
    let openInDebug: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if row.isRunning { ProgressView().controlSize(.mini) }
                else { Image(systemName: icon).foregroundStyle(color) }
                Text(row.agent).font(.callout.weight(.semibold))
                Text(row.title).font(.callout).lineLimit(1).truncationMode(.tail)
                Spacer()
            }
            Text(row.stateText + " · " + shortName(row.model)).font(.caption).foregroundStyle(row.waiting ? .orange : .secondary)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(stats).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(row.judgments.latestByJudge) { j in
                Text(judgmentText(j)).font(.caption).foregroundStyle(j.label.map { $0 < 0.5 } ?? false ? .orange : .secondary)
                    .lineLimit(2).help(j.note ?? "")
            }
            HStack(spacing: 12) {
                if let judge {
                    Menu("Rate") {
                        ForEach([3, 2, 1, 0], id: \.self) { v in
                            Button("\(v): " + RunJudgment.verdictMeanings[v]!) { judge(v) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize().font(.caption)
                    .accessibilityLabel("Rate \(row.agent) run \"\(row.title)\"")
                    .help("Your judgment of this run; it counts more than the agent's own rating")
                }
                if let stop { Button("Stop", role: .destructive, action: stop).controlSize(.small)
                    .accessibilityLabel("Stop \(row.agent) run \"\(row.title)\"")
                    .help("Stop this subagent only; the main agent carries on without its report") }
                Button("Open in Debug", action: openInDebug).buttonStyle(.link).font(.caption)
                    .accessibilityLabel("Open \(row.agent) run \"\(row.title)\" in Debug")
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var stats: String {
        let seconds = row.end?.seconds ?? Date().timeIntervalSince(row.started)
        return "\(row.steps) turns · \(row.toolCalls) calls · \(row.promptTokens) in · \(row.completionTokens) out · "
            + String(format: "%.0f s", seconds) + (row.cost > 0 ? String(format: " · ≈$%.4f", row.cost) : "")
    }

    private func judgmentText(_ j: RunJudgment) -> String {
        switch j.judge {
        case .checks: return "Checks: " + (j.checks.map { $0.problems.isEmpty ? "no problems" : $0.problems.joined(separator: "; ") } ?? "–")
        case .parent: return "Agent's rating: \(j.verdict ?? 0)/3" + (j.issues.isEmpty ? "" : " (" + j.issues.joined(separator: ", ") + ")")
            + (j.checkedConfirmed == false ? " · says it checked, but made no check after the report" : "")
        case .grader: return "Grader (\(shortName(j.judgeModel ?? "?"))): \(j.verdict ?? 0)/3" + (j.issues.isEmpty ? "" : " (" + j.issues.joined(separator: ", ") + ")")
        case .reviewer:
            let verdict = j.verdict.map { $0 == 3 ? "looks right" : $0 == 0 ? "wrong" : "has problems" } ?? "no verdict"
            return "Review (\(shortName(j.judgeModel ?? "?"))): \(verdict)" + (j.evidence.map { "\n" + $0.joined(separator: "\n") } ?? "")
        case .user: return "Your rating: \(j.verdict ?? 0)/3"
        case .implicit: return "You " + (j.note ?? "redid it")
        case .recheck:
            let exit = j.checks?.verifyExitCode
            return "Check run again: " + (exit.map { $0 == 0 ? "passed" : "FAILED (exit \($0))" } ?? "couldn't run")
        }
    }

    private var icon: String {
        switch row.end?.stop {
        case "completed": "checkmark.circle"
        case "cancelled": "stop.circle"
        default: "exclamationmark.circle"
        }
    }

    private var color: Color { row.end?.stop == "completed" ? .green : .orange }
}

/// A background subagent's report, delivered into the conversation as a message (the model reads it as the
/// report it asked for, not the user's words).
struct SubagentReportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.chatSessionID) private var sessionID
    let text: String
    let run: UUID
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.2").foregroundStyle(.secondary)
                    Text(heading).fontWeight(.medium)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(body(of: text)).textSelection(.enabled).font(.callout)
                .lineLimit(expanded ? nil : 4)
            if let sessionID {
                Button("Open in Debug") {
                    app.debugFocus = DebugFocus(session: sessionID, run: run)
                    openWindow(id: "debug")
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }

    /// "Report from the explore subagent: Find the parser" from the delivery's first line.
    private var heading: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        if let r = first.range(of: "Report from the "), let end = first.range(of: " you started") {
            let agent = first[r.upperBound..<end.lowerBound]
            let title = first.split(separator: "\"").dropFirst().first.map(String.init) ?? ""
            return "Report from the \(agent)" + (title.isEmpty ? "" : ": " + title)
        }
        return "Report from a background subagent"
    }

    /// The report without the delivery line and the closing note to the model.
    private func body(of text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines = lines.dropFirst() }
        var out = lines.joined(separator: "\n")
        if let note = out.range(of: "\n\n[This is the ", options: .backwards) { out = String(out[..<note.lowerBound]) }
        return out
    }
}
