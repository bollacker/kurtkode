import AgentCore
import SwiftUI

/// One tool call and its result: a one-line summary that expands to what happened. Edits show their
/// diff; commands show their output, live while running.
struct ToolCallCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.chatSessionID) private var sessionID
    let call: ToolCall
    let result: ChatMessage?
    var running = false
    /// When it started, while it runs.
    var since: Date?
    var liveOutput: String?
    /// Waiting on the user's approval card.
    var awaitingApproval = false
    @State private var expanded = false

    private var tool: (any Tool)? { AllTools.named(call.name) }
    private var args: ToolArguments { (try? ToolArguments(json: call.arguments)) ?? ToolArguments() }
    private var info: ToolResultInfo? { result?.toolResult }
    private var isError: Bool { info?.isError ?? false }
    private var isCommand: Bool { call.name == "bash" }
    /// A subagent's card streams its steps like a command's output.
    private var isTask: Bool { call.name == "task" }
    private var isEdit: Bool { tool?.risk == .write }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(.secondary).frame(width: 14)
                    Text(tool?.summary(args) ?? TaskTool.summary(forCallNamed: call.name, arguments: call.arguments)
                         ?? MCPTool.summary(forCallNamed: call.name, arguments: call.arguments)
                         ?? "\(call.name) \(call.arguments)")
                        .font(isCommand ? .callout.monospaced() : .callout)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let stats = diffStats { Text(stats).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    if let info, info.truncated, !isCommand {
                        Text(call.name == "read_file" ? "partial" : "truncated").font(.caption2).foregroundStyle(.secondary)
                    }
                    status
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            if isError, !expanded, let text = result?.content {
                Text(text.split(separator: "\n").first.map(String.init) ?? text)
                    .font(.caption).foregroundStyle(info?.denied == true ? Color.orange : Color.red).lineLimit(2)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            // Running commands stay open so their output is visible as it arrives.
            if expanded || (running && (isCommand || isTask)) {
                Divider()
                detail
            }
        }
        .background(.quaternary.opacity(expanded ? 0.3 : 0.15), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor))
    }

    @ViewBuilder private var detail: some View {
        if call.name == "todo_write", let items = try? TodoWriteTool.items(from: args) {
            VStack(alignment: .leading, spacing: 4) { ForEach(items) { TodoRow(item: $0) } }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        } else if isEdit, let diff = info?.display, !isError {
            DiffView(diff: diff).padding(6)
        } else if isCommand || isTask {
            CommandOutput(text: running ? (liveOutput ?? "") : (info?.display ?? result?.content ?? ""), live: running)
            if isTask, let run = info?.subagentRun, let sessionID {
                Button("Open in Debug") {
                    app.debugFocus = DebugFocus(session: sessionID, run: run)
                    openWindow(id: "debug")
                }
                .buttonStyle(.link).font(.caption).padding(.horizontal, 10).padding(.bottom, 6)
                .help("The subagent's own Timeline and Journal: every request, reply, and tool call")
            }
            if let path = info?.fullOutputPath {
                Button(isTask ? "Open transcript" : "Open full output") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .buttonStyle(.link).font(.caption).padding(.horizontal, 10).padding(.bottom, 6)
                    .help(isTask ? "The subagent's whole conversation, saved at \(path)"
                                 : "The model saw the start and end; the complete output is saved at \(path)")
            }
        } else {
            CodeScroll {
                Text(result?.content ?? (running ? "Running…" : "No result"))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
    }

    private var borderColor: Color {
        if info?.denied == true { return .orange.opacity(0.5) }
        if isError { return .red.opacity(0.4) }
        return .clear
    }

    private var diffStats: String? {
        guard isEdit, let diff = info?.display, !isError else { return nil }
        var add = 0, rem = 0
        for line in diff.split(separator: "\n") {
            if line.hasPrefix("+"), !line.hasPrefix("+++") { add += 1 }
            if line.hasPrefix("-"), !line.hasPrefix("---") { rem += 1 }
        }
        return "+\(add) −\(rem)"
    }

    @ViewBuilder private var status: some View {
        if awaitingApproval {
            Text("awaiting approval").font(.caption2).foregroundStyle(.orange)
        } else if running {
            if let since {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let seconds = context.date.timeIntervalSince(since)
                    if seconds >= 2 { Text(RunClock.text(seconds)).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            ProgressView().controlSize(.mini)
        } else if let info {
            if info.denied == true {
                Text("denied").font(.caption2).foregroundStyle(.orange)
            } else if info.isError {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            } else if let code = info.exitCode {
                Text("exit \(code)").font(.caption2.monospacedDigit())
                    .foregroundStyle(code == 0 ? Color.secondary : Color.red)
            } else if info.duration >= 0.1 {
                Text(String(format: "%.1fs", info.duration)).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
                .help("No result recorded: it was stopped before it ran or while it was running")
                .accessibilityLabel("No result recorded")
        }
    }

    private var icon: String {
        switch call.name {
        case "read_file": "doc.text"
        case "list_dir": "folder"
        case "glob": "doc.text.magnifyingglass"
        case "grep": "magnifyingglass"
        case "edit_file": "pencil"
        case "write_file": "doc.badge.plus"
        case "bash": "terminal"
        case "todo_write": "checklist"
        case "task": "person.2"
        case "skill": "book"
        case "ask_user": "questionmark.bubble"
        case let n where n.hasPrefix("mcp__"): "puzzlepiece.extension"
        default: "wrench.and.screwdriver"
        }
    }
}

/// Replies that only looked around, as one line ("Read 3 files, searched 2 times"); it opens to their cards.
struct ToolGroupRow: View {
    let replies: [ChatMessage]
    let results: [UUID: [String: ChatMessage]]
    var running: [String: Date] = [:]
    var liveOutput: [String: String] = [:]
    var awaitingApprovalID: String?
    /// Open whatever the user chose: a find landed here.
    var forceOpen = false
    @State private var expanded = false

    private func summary(_ call: ToolCall) -> String {
        let args = (try? ToolArguments(json: call.arguments)) ?? ToolArguments()
        return AllTools.named(call.name)?.summary(args) ?? call.name
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        let calls = replies.flatMap(\.toolCalls)
        let active = calls.last { running[$0.id] != nil }
        let waiting = calls.contains { $0.id == awaitingApprovalID }
        let failed = replies.reduce(0) { n, r in
            n + r.toolCalls.filter { results[r.id]?[$0.id]?.toolResult?.isError == true }.count
        }
        VStack(alignment: .leading, spacing: 3) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary).frame(width: 14)
                    Text(active.map(summary) ?? ToolGroupSummary.text(calls))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if failed > 0 { Text("\(failed) failed").font(.caption2).foregroundStyle(.red) }
                    if active != nil { ProgressView().controlSize(.mini) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            if expanded || forceOpen || waiting {
                ForEach(replies) { reply in
                    if let reasoning = reply.reasoning {
                        ThinkingSection(text: reasoning, tokens: reply.meta?.usage?.reasoningTokens, live: false)
                            .padding(.horizontal, 8)
                    }
                    ForEach(reply.toolCalls) { call in
                        ToolCallCard(call: call, result: results[reply.id]?[call.id], running: running[call.id] != nil,
                                     since: running[call.id], liveOutput: liveOutput[call.id],
                                     awaitingApproval: call.id == awaitingApprovalID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// "12s", "2m 14s", "1h 05m".
enum RunClock {
    static func text(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s / 3600)h \(String(format: "%02d", s / 60 % 60))m"
    }
}

/// Terminal-style output, pinned to the bottom while a command runs.
struct CommandOutput: View {
    let text: String
    let live: Bool

    /// While a command runs only its last lines are shown: laying out and drawing hundreds of lines ten
    /// times a second kept the main thread busy for as long as a chatty command ran. The whole output is in
    /// the card once it finishes.
    var body: some View {
        let shown = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains(BashTool.marker) }
            .suffix(live ? 40 : 400).joined(separator: "\n")
        CodeScroll(maxHeight: 240) {
            Text(shown.isEmpty ? (live ? "Running…" : "(no output)") : shown)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(10)
        }
        .defaultScrollAnchor(.bottom)
        .background(.black.opacity(0.05))
    }
}

/// Shown after a run that hit the step limit.
struct StepLimitBanner: View {
    let continueRun: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle").foregroundStyle(.orange)
            Text("Paused after the step limit (Settings → Generation). The agent may not be finished.")
            Button("Continue", action: continueRun).buttonStyle(.link)
        }
        .font(.callout)
    }
}

/// Shown on a session whose last run never ended: kurtkode quit or crashed during it.
struct InterruptedBanner: View {
    let controller: ChatController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle").foregroundStyle(.orange)
            Text("This run was cut off before it finished, when kurtkode quit or crashed.")
            Button("Continue", action: controller.continueRun).buttonStyle(.link)
                .disabled(controller.sendBlocker != nil)
                .help("The model picks up from here. A call that has no recorded result may or may not have run; it's told so.")
            Button("Dismiss") { controller.interruptDismissed = true }.buttonStyle(.link)
        }
        .font(.callout)
    }
}

struct CostLimitBanner: View {
    let spent: Double?
    /// Which limit (`CostMeter.stopNote`); a daily one can't be continued past.
    var note: String?
    let continueRun: () -> Void

    private var daily: Bool { note?.contains("daily limit") == true }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle").foregroundStyle(.orange)
            Text(note ?? ("Paused at the cost limit (Settings → Generation → Spending)"
                 + (spent.map { String(format: "; this session has spent about $%.2f", $0) } ?? "") + "."))
            if !daily {
                Button("Continue", action: continueRun).buttonStyle(.link)
                    .help("Allow another run's worth. A session limit that's reached stops it again: raise it in Settings.")
            }
        }
        .font(.callout)
    }
}

/// What a session has spent, for the toolbar.
struct CostReadout: View {
    let dollars: Double
    let estimate: Bool
    var own = CostSummary()
    var subagents = 0.0

    var body: some View {
        Text((estimate ? "≈" : "") + String(format: dollars < 1 ? "$%.3f" : "$%.2f", dollars))
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .help(detail)
            .accessibilityLabel(String(format: "Spent in this session: %.2f dollars", dollars))
    }

    /// What the total is made of: by purpose, subagents, the list price by component, and what was charged.
    private var detail: String {
        func d(_ x: Double) -> String { String(format: "$%.4f", x) }
        var lines = ["Spent in this session, subagents and summaries included: the charge where the server said it, "
                     + "list price otherwise (≈)."]
        let purposes: [(CostEntry.Purpose, String)] = [(.reply, "replies"), (.summary, "summaries"), (.summaryAttempt, "summary attempts"),
                                                       (.retryAttempt, "retried attempts"), (.nudgedReply, "empty replies asked again"),
                                                       (.fallbackReply, "fallback model"), (.review, "reviews")]
        let parts = purposes.compactMap { p, name in own.byPurpose[p].flatMap { $0 > 0 ? name + " " + d($0) : nil } }
        if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
        if subagents > 0 { lines.append("subagents " + d(subagents)) }
        let l = own.listPrice
        if l.total > 0 {
            lines.append("List price " + d(l.total) + ": input " + d(l.uncachedInput) + " · cache read " + d(l.cacheRead)
                         + " · cache write " + d(l.cacheWrite5m + l.cacheWrite1h) + " · output " + d(l.output)
                         + (l.reasoning > 0 ? " (thinking " + d(l.reasoning) + ")" : "") + (l.searches > 0 ? " · searches " + d(l.searches) : ""))
        }
        if own.chargedRequests > 0 {
            lines.append("Charged " + d(own.charged) + " on \(own.chargedRequests) request\(own.chargedRequests == 1 ? "" : "s")"
                         + (own.reconciledRequests > 0 ? ", \(own.reconciledRequests) checked against the provider's record" : ""))
        }
        if own.unpricedRequests > 0 { lines.append("\(own.unpricedRequests) request\(own.unpricedRequests == 1 ? "" : "s") without a price (local models count nothing)") }
        if l.total > 0, let stale = PriceList.staleness() { lines.append(stale) }
        lines.append("Limits: Settings → Generation → Spending.")
        return lines.joined(separator: "\n")
    }
}

/// Scrolls both ways, with content left-aligned and at least as wide as the view. (Content in a
/// two-way ScrollView otherwise sizes to fit and ends up centered.)
struct CodeScroll<Content: View>: View {
    var maxHeight: CGFloat = 260
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            content().frame(minWidth: width, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
