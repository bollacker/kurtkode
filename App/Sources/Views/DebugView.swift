import AgentCore
import AppKit
import SwiftUI

/// The Debug window: a session's model turns and tool calls as a timeline, with each turn's exact request, raw
/// response, reasoning, and what the agent loop did, and each call's arguments, checks, approval, and result.
struct DebugView: View {
    @Environment(AppModel.self) private var app
    @State private var follow = true
    @State private var chosen: UUID?
    /// A session with no live controller, read from its file.
    @State private var loaded: Session?
    @State private var selectedRow: String?
    /// A subagent run shown in place of its session (drill-in), and the row to return to.
    @State private var run: UUID?
    @State private var child: Session?
    @State private var parentRow: String?
    /// The session's subagent runs, for its totals.
    @State private var runs: [Session] = []
    @State private var problemsOnly = false
    @State private var toolFilter = ""
    @State private var mode: Mode = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KURTKODE_DEBUG_MODE"] == "journal" { return .journal }
        #endif
        return .timeline
    }()

    enum Mode: String, CaseIterable { case timeline = "Timeline", journal = "Journal" }

    private var sessionID: UUID? { follow ? app.lastSelectedSession : chosen }
    /// The tool calls the session is running now (live sessions only; several when subagents run in parallel).
    private var runningCallIDs: Set<String> { sessionID.flatMap { app.existingController($0)?.runningToolIDs } ?? [] }
    /// Each `task` call's run, by call id: a running call has no result (and no link) yet.
    private var runByCall: [String: UUID] {
        Dictionary(runs.compactMap { r in r.header.parentCallID.map { ($0, r.header.id) } }, uniquingKeysWith: { _, b in b })
    }
    private var session: Session? {
        guard let id = sessionID else { return nil }
        return app.existingController(id)?.session ?? (loaded?.header.id == id ? loaded : nil)
    }

    /// What the window shows: the session, or the subagent run drilled into.
    private var shown: Session? { run == nil ? session : child }
    /// The shown session's cost records by the reply they're for.
    private var costsByReply: [UUID: CostEntry] {
        Dictionary((shown?.costs ?? []).map { ($0.reply, $0) }, uniquingKeysWith: { _, b in b })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let session, run != nil {
                breadcrumb(session)
                Divider()
            }
            if run != nil, child == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let shown, mode == .journal {
                JournalView(session: shown, wire: app.sessionStore.wireDirectory(for: shown.header),
                            contextLimit: run == nil ? app.existingController(shown.header.id)?.contextLimit : nil,
                            openSubagent: run == nil ? { openRun($0) } : nil)
                    .id(shown.header.id)
            } else if let shown {
                let items = SessionTimeline.items(shown)
                StatsStrip(stats: stats(shown))
                Divider()
                HSplitView {
                    timeline(rows(items))
                        .frame(minWidth: 320, idealWidth: 420)
                    detail(shown, items)
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("No session", systemImage: "ladybug",
                                       description: Text(follow ? "Select a chat in the main window." : "Choose a session above."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: sessionID) { await load() }
        .onChange(of: sessionID) { closeRun(restore: false) }
        // The session's runs, for its totals (again as it grows).
        .task(id: "\(sessionID?.uuidString ?? "")-\(session?.messages.count ?? 0)-\(runningCallIDs.sorted().joined())") {
            guard let header = session?.header else { runs = []; return }
            let store = app.sessionStore
            runs = await store.subagentRuns(of: header)
            // A task call that just started creates its run's file a moment later: look again until it's there.
            let runningTasks = Set((sessionID.flatMap { app.existingController($0)?.runningTools } ?? [])
                .filter { $0.name == "task" }.map(\.id))
            while !Task.isCancelled, !runningTasks.isSubset(of: Set(runs.compactMap(\.header.parentCallID))) {
                try? await Task.sleep(for: .milliseconds(500))
                runs = await store.subagentRuns(of: header)
            }
            #if DEBUG
            // KURTKODE_DEBUG_SUBAGENT=N: open the session's Nth subagent run.
            if run == nil, let n = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_SUBAGENT"].flatMap(Int.init),
               n >= 1, n <= runs.count { openRun(runs[n - 1].header.id) }
            #endif
        }
        // A task card's "Open in Debug".
        .task(id: app.debugFocus) {
            guard let f = app.debugFocus else { return }
            app.debugFocus = nil
            if f.session != app.lastSelectedSession || !follow {
                follow = false
                chosen = f.session
            }
            await load()
            openRun(f.run)
        }
        // The run drilled into, followed while it runs.
        .task(id: run) {
            guard let id = run, let header = session?.header else { child = nil; return }
            let store = app.sessionStore
            while !Task.isCancelled {
                child = await store.subagentRun(id, of: header)
                guard child != nil, child?.subagentEnd == nil else { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #if DEBUG
        // KURTKODE_DEBUG_TURN=N (and KURTKODE_DEBUG_TAB=overview|steps|request|response|diff): select turn N.
        .task(id: session?.messages.count) {
            guard let n = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_TURN"].flatMap(Int.init), let session else { return }
            if let t = SessionTimeline.items(session).lazy.compactMap({ if case .turn(let t) = $0, t.number == n { t } else { nil } }).first {
                // KURTKODE_DEBUG_CALL=1: the turn's first tool call instead.
                selectedRow = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_CALL"] != nil && !t.calls.isEmpty
                    ? "call-" + t.calls[0].id : t.id.uuidString
            }
        }
        #endif
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            Toggle("Follow the main window", isOn: $follow)
            if !follow {
                Picker("Session", selection: $chosen) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(app.sessions) { s in
                        Text("\(s.title.prefix(60)) · \(shortName(s.model))").tag(UUID?.some(s.id))
                    }
                }
                .frame(maxWidth: 420)
            }
            Spacer()
            if mode == .timeline {
                Toggle("Problems only", isOn: $problemsOnly)
                Picker("Tool", selection: $toolFilter) {
                    Text("All tools").tag("")
                    ForEach(toolNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 200)
            }
            Button { Task { await load(force: true) } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                .help("Read the session file again (a session open in a window updates by itself)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var toolNames: [String] {
        guard let shown else { return [] }
        return Array(Set(shown.messages.flatMap { $0.toolCalls.map(\.name) })).sorted()
    }

    private func stats(_ s: Session) -> SessionStats {
        var stats = SessionStats(s)
        if run == nil { stats.add(subagents: runs, of: s.header) }
        return stats
    }

    // MARK: Subagent drill-in

    private func openRun(_ id: UUID) {
        if run == nil { parentRow = selectedRow }
        selectedRow = nil
        child = nil
        run = id
    }

    private func closeRun(restore: Bool = true) {
        guard run != nil else { return }
        run = nil
        child = nil
        selectedRow = restore ? parentRow : nil
        parentRow = nil
    }

    /// `Session title › turn 7 · explore: Find the parser`, with the way back.
    private func breadcrumb(_ session: Session) -> some View {
        let callID = child?.header.parentCallID
        let turn = SessionTimeline.items(session).lazy
            .compactMap { if case .turn(let t) = $0, t.calls.contains(where: { $0.call.id == callID }) { t.number } else { nil } }.first
        return HStack(spacing: 6) {
            Button { closeRun() } label: { Label(String(session.displayTitle.prefix(60)), systemImage: "chevron.left") }
                .buttonStyle(.link)
                .help("Back to the session")
            Text("›").foregroundStyle(.secondary)
            Text([turn.map { "turn \($0)" }, child.map { "\($0.header.agent ?? "subagent"): \($0.displayTitle)" }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.callout.weight(.medium))
            if let c = child {
                Text(c.subagentEnd == nil ? "running" : SubagentSection.stateText(c.subagentEnd!.stop))
                    .font(.caption).foregroundStyle(.secondary)
                Text("on \(shortName(c.model))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }

    private func load(force: Bool = false) async {
        // Reload also picks up what another kurtkode (the command line) added to a session open in a main window.
        if force, let id = sessionID, let c = app.existingController(id) { await c.reloadIfChangedElsewhere() }
        guard let id = sessionID, force || app.existingController(id) == nil else { return }
        if !force, loaded?.header.id == id { return }
        let store = app.sessionStore
        loaded = try? await store.load(id)
    }

    // MARK: Rows

    enum Row: Identifiable {
        case user(ChatMessage)
        case command(ChatMessage)
        case turn(TurnEntry)
        case call(TurnEntry, CallEntry)
        case compaction(Compaction)

        var id: String {
            switch self {
            case .user(let m), .command(let m): m.id.uuidString
            case .turn(let t): t.id.uuidString
            case .call(_, let c): "call-" + c.id
            case .compaction(let c): "compaction-" + c.lastSummarizedID.uuidString
            }
        }
    }

    private func callHasProblem(_ c: CallEntry) -> Bool {
        guard let info = c.result?.toolResult else { return true }
        return info.isError || !(info.argumentProblems ?? []).isEmpty || info.notes != nil || info.denied == true
    }

    private func rows(_ items: [TimelineItem]) -> [Row] {
        var out: [Row] = []
        for item in items {
            switch item {
            case .user(let m): if !problemsOnly && toolFilter.isEmpty { out.append(.user(m)) }
            case .userCommand(let m): if !problemsOnly && toolFilter.isEmpty { out.append(.command(m)) }
            case .compaction(let c): if toolFilter.isEmpty { out.append(.compaction(c)) }
            case .turn(let t):
                var calls = t.calls
                if !toolFilter.isEmpty { calls = calls.filter { $0.call.name == toolFilter } }
                if problemsOnly { calls = calls.filter(callHasProblem) }
                let turnShown = (toolFilter.isEmpty || !calls.isEmpty)
                    && (!problemsOnly || !t.flags.isEmpty || t.reply.meta?.notes != nil || !calls.isEmpty)
                guard turnShown else { continue }
                out.append(.turn(t))
                out += calls.map { .call(t, $0) }
            }
        }
        return out
    }

    private func timeline(_ rows: [Row]) -> some View {
        List(rows, selection: $selectedRow) { row in
            RowView(row: row, runningCallIDs: run == nil ? runningCallIDs : [], costs: costsByReply).tag(row.id)
        }
        .listStyle(.inset)
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ session: Session, _ items: [TimelineItem]) -> some View {
        let turns = items.compactMap { if case .turn(let t) = $0 { t } else { nil } }
        let wire = app.sessionStore.wireDirectory(for: session.header)
        if let id = selectedRow {
            if let t = turns.first(where: { $0.id.uuidString == id }) {
                let previous = turns.last { $0.number < t.number }
                TurnDetail(turn: t, previous: previous, wire: wire, endpointName: t.reply.meta?.endpointID.flatMap { app.endpoint($0)?.name },
                           session: session)
                    .id(t.id)
            } else if id.hasPrefix("call-"), let (t, c) = turns.lazy.compactMap({ t in t.calls.first { "call-" + $0.id == id }.map { (t, $0) } }).first {
                CallDetail(turn: t, entry: c, parent: session.header, runID: c.result?.toolResult?.subagentRun ?? runByCall[c.id],
                           running: run == nil && runningCallIDs.contains(c.id), openRun: run == nil ? { openRun($0) } : nil).id(id)
            } else if let m = session.messages.first(where: { $0.id.uuidString == id }) {
                MessageDetail(message: m)
            } else if let c = session.compactions.first(where: { "compaction-" + $0.lastSummarizedID.uuidString == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compaction: about \(c.tokensBefore / 1000)k tokens down to \(max(1, c.tokensAfter / 1000))k").font(.headline)
                        if let ids = c.summaryRequests { SummaryRequestsView(ids: ids, wire: wire) }
                        Text(c.modelText).textSelection(.enabled).font(.body.monospaced())
                    }.padding()
                }
            }
        } else {
            ContentUnavailableView("Select a turn or a tool call", systemImage: "list.bullet.rectangle")
        }
    }
}

/// One line in the timeline.
private struct RowView: View {
    let row: DebugView.Row
    var runningCallIDs: Set<String> = []
    var costs: [UUID: CostEntry] = [:]

    var body: some View {
        switch row {
        case .user(let m):
            Label(firstLine(m.content), systemImage: "person").foregroundStyle(.secondary)
        case .command(let m):
            Label("!" + (m.userCommand?.command ?? ""), systemImage: "terminal").foregroundStyle(.secondary)
        case .compaction(let c):
            Label("Summarized: \(c.tokensBefore / 1000)k → \(max(1, c.tokensAfter / 1000))k tokens", systemImage: "rectangle.compress.vertical")
                .foregroundStyle(.secondary)
        case .turn(let t) where t.number == 0:
            Label("Attached with @: " + t.calls.map { firstLine($0.call.arguments) }.joined(separator: ", "), systemImage: "paperclip")
                .foregroundStyle(.secondary)
        case .turn(let t):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(t.number)").monospacedDigit().foregroundStyle(.secondary)
                    Text(shortName(t.reply.meta?.reportedModel ?? t.reply.meta?.requestedModel ?? "?")).fontWeight(.medium)
                    if let p = t.reply.meta?.provider { Text(p).foregroundStyle(.secondary) }
                    if t.reply.reasoning != nil {
                        Image(systemName: "brain").foregroundStyle(.purple).help("Has reasoning").accessibilityLabel("Has reasoning")
                    }
                    Spacer()
                    ForEach(t.flags, id: \.self) { Badge(text: $0) }
                }
                Text(turnLine(t)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .call(_, let c):
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(c.call.name).font(.body.monospaced())
                Text(firstLine(c.call.arguments)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let info = c.result?.toolResult {
                    if !(info.argumentProblems ?? []).isEmpty { Badge(text: "arguments") }
                    if info.denied == true { Badge(text: "denied") }
                    if info.notes?.contains(where: { $0.hasPrefix("Not run") }) == true { Badge(text: "not run") }
                    if info.isError { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                    Text(String(format: "%.1f s", info.duration)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if runningCallIDs.contains(c.id) {
                    ProgressView().controlSize(.mini)
                    Text("running").font(.caption).foregroundStyle(.secondary)
                } else {
                    Badge(text: "no result")
                }
            }
            .padding(.leading, 18)
        }
    }

    /// ", 15% shown" for a reply whose reasoning was billed and partly shown (summaries); empty otherwise.
    private func shownNote(_ m: ChatMessage) -> String {
        guard let share = ReasoningShown(m).shownShare, share < 0.95 else { return "" }
        return String(format: ", %.0f%% shown", share * 100)
    }

    private func turnLine(_ t: TurnEntry) -> String {
        guard let m = t.reply.meta else { return "" }
        var parts: [String] = []
        if let u = m.usage {
            parts.append("\(u.promptTokens) in" + (u.cachedShare.map { String(format: " (%.0f%% cached)", $0 * 100) } ?? "")
                         + " · \(u.completionTokens) out" + (u.reasoningTokens > 0 ? " (\(u.reasoningTokens) reasoning" + shownNote(t.reply) + ")" : ""))
        }
        if let c = costs[t.reply.id]?.spentText(digits: 4) { parts.append(c) }
        if let ttft = m.timeToFirstToken { parts.append(String(format: "first token %.1f s", ttft)) }
        parts.append(String(format: "%.1f s", m.duration))
        parts.append(t.calls.isEmpty ? "answer" : "\(t.calls.count) call\(t.calls.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

private func firstLine(_ s: String) -> String {
    let line = s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? s
    return line.count > 140 ? String(line.prefix(140)) + "…" : line
}

private struct Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch text {
        case "error", "lost", "failed", "denied", "no result": .red
        case "recovered", "nudged", "arguments", "bad arguments", "not run", "cut off", "other model": .orange
        default: .secondary
        }
    }
}

private struct StatsStrip: View {
    let stats: SessionStats
    var body: some View {
        HStack(spacing: 16) {
            stat("Turns", "\(stats.turns)")
            stat("Tool calls", "\(stats.toolCalls)")
            stat("Errors", "\(stats.errors)", warn: stats.errors > 0)
            stat("Bad arguments", "\(stats.badArguments)", warn: stats.badArguments > 0)
            stat("Not run", "\(stats.notRun)", warn: stats.notRun > 0)
            stat("Lost replies", "\(stats.lostReplies)", warn: stats.lostReplies > 0)
            stat("Nudges", "\(stats.nudges)", warn: stats.nudges > 0)
            stat("Recovered calls", "\(stats.recoveredTextCalls)")
            stat("Compactions", "\(stats.compactions)")
            if stats.subagents > 0 {
                stat("Subagents", "\(stats.subagents) · \(stats.subagentToolCalls) calls · "
                     + "\(tokens(stats.subagentPromptTokens)) in · \(tokens(stats.subagentCompletionTokens)) out"
                     + (stats.subagentCost > 0 ? String(format: " · $%.4f", stats.subagentCost) : ""))
            }
            stat("Tokens", "\(tokens(stats.promptTokens)) in · \(tokens(stats.completionTokens)) out"
                 + (stats.reasoningTokens > 0 ? " (\(tokens(stats.reasoningTokens)) reasoning)" : ""))
            if stats.reasoningBilledTokens > 0 {
                stat("Reasoning shown", String(format: "%.0f%% of %@ tokens",
                                               Double(stats.reasoningShownTokens) / Double(stats.reasoningBilledTokens) * 100,
                                               tokens(stats.reasoningBilledTokens)))
            }
            if stats.cacheReportedPromptTokens > 0 {
                stat("Cache", String(format: "%.0f%% of the prompt read from it · %@ written",
                                     Double(stats.cacheReadTokens) / Double(stats.cacheReportedPromptTokens) * 100,
                                     tokens(stats.cacheWriteTokens)))
            }
            if !stats.cost.isEmpty {
                let summaries = (stats.cost.byPurpose[.summary] ?? 0) + (stats.cost.byPurpose[.summaryAttempt] ?? 0)
                stat("Cost", stats.cost.spentText() + (summaries > 0 ? String(format: " (summaries $%.4f)", summaries) : "") + " · "
                     + stats.costByProvider.sorted { $0.value > $1.value }.map { String(format: "%@ $%.4f", $0.key, $0.value) }.joined(separator: ", "))
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .help(stats.callsByTool.sorted { $0.value > $1.value }.map { "\($0.key): \($0.value)" + ((stats.errorsByTool[$0.key] ?? 0) > 0 ? " (\(stats.errorsByTool[$0.key]!) errors)" : "") }
            .joined(separator: "\n"))
    }

    private func tokens(_ n: Int) -> String { n < 10_000 ? "\(n)" : String(format: "%.1fk", Double(n) / 1000) }

    private func stat(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(warn ? .orange : .primary)
        }
    }
}

// MARK: - Turn detail

private struct TurnDetail: View {
    @Environment(AppModel.self) private var app
    let turn: TurnEntry
    let previous: TurnEntry?
    let wire: URL
    let endpointName: String?
    /// The session (or subagent run) shown, for forking.
    let session: Session
    @State private var replays: [ReplayRecord] = []
    @State private var replaying = false
    @State private var actionNote: String?
    @State private var tab: Tab = {
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_TAB"].map({ $0 == "reasoning" ? "steps" : $0 }),
           let tab = Tab.allCases.first(where: { $0.rawValue.lowercased() == t }) { return tab }
        #endif
        return .overview
    }()
    @State private var record: WireRecord?
    @State private var previousRecord: WireRecord?
    @State private var retries: [WireRecord] = []
    @State private var loading = true

    enum Tab: String, CaseIterable {
        case overview = "Overview", steps = "Steps", request = "Request", response = "Response", diff = "Diff", replays = "Replays"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in Text(t == .replays && !replays.isEmpty ? "Replays (\(replays.count))" : t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 10).padding(.top, 10)
            actions
            Divider()
            switch tab {
            case .overview: overview
            case .steps: ReplyStepsView(reply: turn.reply)
            case .request: wireText { prettyJSON($0.request) }
            case .response: wireText { r in
                var s = "HTTP " + r.statuses.map(String.init).joined(separator: " → ") + "\n"
                if let e = r.errorBody { s += "Error body: " + e + "\n" }
                s += "\n" + r.lines.joined(separator: "\n")
                if r.linesTruncated == true { s += "\n[…the rest wasn't kept: the stream was over 4 MB]" }
                return s
            }
            case .diff: diffView
            case .replays: ReplaysList(original: turn.reply, replays: replays)
            }
        }
        // Tabs stay at the top whatever the tab shows (a short "No wire record" view centered the whole stack).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $replaying) {
            if let record {
                ReplaySheet(record: record, original: turn.reply, wire: wire) { r in replays.append(r); tab = .replays }
            }
        }
        .task {
            let wire = wire, id = turn.reply.id, prev = previous?.reply.id, retryIDs = turn.reply.meta?.retryRequests ?? []
            let (r, p, rs) = await Task.detached {
                (WireLog.read(wire, replyID: id), prev.flatMap { WireLog.read(wire, replyID: $0) },
                 retryIDs.compactMap { WireLog.read(wire, replyID: $0) })
            }.value
            record = r
            previousRecord = p
            retries = rs
            replays = await Task.detached { Replay.load(wire, sourceReply: id) }.value
            loading = false
            #if DEBUG
            await debugActions()
            #endif
        }
    }

    /// Replay…, Copy as cURL, Fork: what can be done with this turn's request.
    private var actions: some View {
        HStack(spacing: 10) {
            Button { replaying = true } label: { Label("Replay…", systemImage: "arrow.counterclockwise") }
                .disabled(record == nil)
                .help("Send this turn's recorded request again, on this or another model, and compare the replies")
            Button { copyCurl() } label: { Label("Copy as cURL", systemImage: "terminal") }
                .disabled(record == nil)
                .help("A shell command that sends this request; the key is a placeholder ($KURTKODE_API_KEY)")
            Menu {
                Button("From Before This Turn") { fork(after: false) }
                Button("From After This Turn") { fork(after: true) }
            } label: { Label("Fork", systemImage: "arrow.triangle.branch") }
                .fixedSize()
                .disabled(turn.number == 0 || session.header.isSubagent)
                .help("A new session with this session's messages up to this turn (before it, to run it again; after it, "
                      + "to carry on). Files on disk aren't changed.")
            if let actionNote { Text(actionNote).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func copyCurl() {
        guard let record else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Replay.curl(record), forType: .string)
        actionNote = "Copied. Set KURTKODE_API_KEY first for a server that needs a key."
    }

    private func fork(after: Bool) {
        let session = session, turn = turn
        Task {
            do {
                try await app.forkSession(session, atReply: turn.reply.id, turn: turn.number, after: after)
                actionNote = "Forked: the new session is open in the main window."
            } catch {
                actionNote = "Couldn't fork: \(error.localizedDescription)"
            }
        }
    }

    #if DEBUG
    /// KURTKODE_DEBUG_REPLAY="Endpoint name|model": replay this turn on that model, then show the Replays tab.
    /// KURTKODE_DEBUG_FORK=before|after: fork at this turn. KURTKODE_DEBUG_CURL=path: write the cURL command there.
    private func debugActions() async {
        // Once per launch: a fork opens the new session, the window follows it, and this view loads again.
        guard !DebugOnce.done else { return }
        DebugOnce.done = true
        let env = ProcessInfo.processInfo.environment
        if let path = env["KURTKODE_DEBUG_CURL"], let record { try? Replay.curl(record).write(toFile: path, atomically: true, encoding: .utf8) }
        if let f = env["KURTKODE_DEBUG_FORK"] { fork(after: f == "after") }
        if env["KURTKODE_DEBUG_REPLAY_SHEET"] != nil { replaying = true }
        guard let spec = env["KURTKODE_DEBUG_REPLAY"], let record, replays.isEmpty,
              let bar = spec.firstIndex(of: "|"), let e = app.endpoints.first(where: { $0.name == String(spec[..<bar]) }) else { return }
        let client = ChatClient(endpoint: e, apiKey: await app.apiKey(for: e))
        let r = await Replay.run(record, client: client, endpointName: e.name, endpointID: e.id,
                                 options: ReplayOptions(model: String(spec[spec.index(after: bar)...])))
        try? Replay.save(r, wire: wire)
        replays.append(r)
        tab = .replays
    }
    #endif

    @ViewBuilder private func wireText(_ make: @escaping (WireRecord) -> String) -> some View {
        if let record { PlainTextView(text: make(record)) }
        else if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { noWire }
    }

    private var noWire: some View {
        ContentUnavailableView("No wire record", systemImage: "antenna.radiowaves.left.and.right.slash",
                               description: Text("Requests are recorded from this version on, while Settings → Generation → "
                                                 + "\"Record requests and responses\" is on."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overview: some View {
        let m = turn.reply.meta
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(metaRows, id: \.0) { k, v in row(k, v) }
                }
                if let notes = m?.notes, !notes.isEmpty {
                    section("What the loop did") {
                        ForEach(notes, id: \.self) { Label($0, systemImage: "wrench.and.screwdriver").foregroundStyle(.orange) }
                    }
                }
                if !retries.isEmpty {
                    section("Retries that produced no reply") {
                        ForEach(retries, id: \.replyID) { r in
                            Text("HTTP " + r.statuses.map(String.init).joined(separator: " → ") + (r.errorBody.map { ": " + $0.prefix(300) } ?? ""))
                                .font(.callout.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                section("Reply") {
                    Text(turn.reply.content.isEmpty ? "(no text)" : turn.reply.content).textSelection(.enabled)
                        .foregroundStyle(turn.reply.content.isEmpty ? .secondary : .primary)
                }
                if let raw = m?.rawContent {
                    section("As it arrived, before tool calls were recovered from it") {
                        Text(raw).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
                if !turn.calls.isEmpty {
                    section("Tool calls") {
                        ForEach(turn.calls) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.call.name + "  " + c.call.id).font(.callout.monospaced().weight(.medium))
                                Text(prettyArguments(c.call.arguments)).font(.caption.monospaced()).textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var diffView: some View {
        if let record, let previousRecord {
            let d = WireDiff(previous: previousRecord, current: record)
            VStack(alignment: .leading, spacing: 0) {
                Text("Compared with turn #\(previous!.number): " + d.summary).padding(10).textSelection(.enabled)
                Divider()
                PlainTextView(text: record.messages.dropFirst(d.commonPrefix).map(prettyJSON).joined(separator: "\n\n"))
            }
        } else if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if record == nil {
            noWire
        } else {
            ContentUnavailableView("Nothing to compare", systemImage: "arrow.left.arrow.right",
                                   description: Text("This is the first recorded request of the session."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The reply's facts as (label, value) lines; built apart from the view (one expression was too much for the type checker).
    private var metaRows: [(String, String)] {
        guard let m = turn.reply.meta else { return [] }
        var rows: [(String, String)] = []
        var model = m.reportedModel ?? m.requestedModel
        if m.modelMismatch { model += " (asked for \(m.requestedModel))" }
        rows.append(("Model", model))
        if let e = endpointName { rows.append(("Endpoint", e)) }
        if let p = m.provider { rows.append(("Provider", p)) }
        if let u = m.usage {
            rows.append(("Tokens", "\(u.promptTokens) prompt · \(u.completionTokens) completion · \(u.reasoningTokens) reasoning"))
            if let c = u.cacheDetail { rows.append(("Cache", c)) }
        }
        if let e = session.costs.last(where: { $0.reply == turn.reply.id }) {
            if let c = e.spentText() { rows.append(("Cost", c)) } else if let why = e.unpricedReason { rows.append(("Cost", "none: " + why)) }
            if let b = e.listPrice {
                func d(_ x: Double) -> String { String(format: "$%.6f", x) }
                var price = d(b.total) + ": input " + d(b.uncachedInput)
                price += " · cache read " + d(b.cacheRead)
                price += " · cache write " + d(b.cacheWrite5m + b.cacheWrite1h)
                price += " · output " + d(b.output)
                if b.reasoning > 0 { price += " (thinking " + d(b.reasoning) + ")" }
                if b.searches > 0 { price += " · searches " + d(b.searches) }
                if let u = b.unpriced { price += " · not priced: " + u.joined(separator: ", ") }
                rows.append(("List price", price))
                let r = b.rates
                var rates = String(format: "per million: input $%.3f · output $%.3f", r.input, r.output)
                rates += String(format: " · cache read $%.3f · write $%.3f / $%.3f", r.cacheRead, r.cacheWrite5m, r.cacheWrite1h)
                rates += " · \(b.tier) tier · \(b.source), \(b.priceList)"
                rows.append(("Rates", rates))
            }
            if let r = e.reconciled {
                var record = r.charged.map { String(format: "charged $%.6f", $0) } ?? "no charge given"
                if let n = r.nativePromptTokens { record += " · native tokens \(n) in" }
                if let n = r.nativeCompletionTokens { record += ", \(n) out" }
                if let p = r.provider { record += " · " + p }
                rows.append(("Provider's record", record))
            }
            if e.billing != .reported { rows.append(("Billing", e.billing == .partial ? "the reply ended early: the usage is what had arrived" : "no usage reported")) }
            if let ids = e.requestIDs { rows.append(("Request ids", ids.joined(separator: ", "))) }
        }
        let first = m.timeToFirstToken.map { String(format: "%.2f s", $0) } ?? "—"
        rows.append(("Timing", "first token \(first) · " + String(format: "%.2f s in all", m.duration)))
        rows.append(("Ended", m.stopReason.rawValue + (m.finishReason.map { " (finish: \($0.rawValue))" } ?? "")))
        if let e = m.error { rows.append(("Error", e)) }
        if let r = record { rows.append(("HTTP", r.statuses.map(String.init).joined(separator: " → ") + " · " + r.url)) }
        return rows
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}

private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        content()
    }
}

// MARK: - Call and message detail

private struct CallDetail: View {
    let turn: TurnEntry
    let entry: CallEntry
    let parent: SessionHeader
    /// The subagent run a `task` call started (from its result, or found by call id while it runs).
    let runID: UUID?
    let running: Bool
    let openRun: ((UUID) -> Void)?

    var body: some View {
        let info = entry.result?.toolResult
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.call.name).font(.title3.monospaced().weight(.semibold))
                Text("Call \(entry.call.id) in turn #\(turn.number)").foregroundStyle(.secondary)
                section("Arguments") {
                    Text(prettyArguments(entry.call.arguments)).font(.callout.monospaced()).textSelection(.enabled)
                }
                if let problems = info?.argumentProblems, !problems.isEmpty {
                    section("Checked against the tool's schema") {
                        ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
                if let id = runID {
                    SubagentSection(runID: id, parent: parent, open: openRun)
                }
                if let a = info?.approval {
                    section("Approval") { Label(a.summary, systemImage: a.allowed ? "checkmark.shield" : "xmark.shield") }
                }
                if let notes = info?.notes, !notes.isEmpty {
                    section("What the loop did") {
                        ForEach(notes, id: \.self) { Label($0, systemImage: "wrench.and.screwdriver").foregroundStyle(.orange) }
                    }
                }
                if let r = entry.result {
                    section("Result" + (info.map { $0.isError ? " (error)" : "" } ?? "")) {
                        if let info {
                            Text([String(format: "%.2f s", info.duration), info.exitCode.map { "exit \($0)" }, info.truncated ? "truncated for the model" : nil]
                                .compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                        }
                        Text(r.content).font(.callout.monospaced()).textSelection(.enabled)
                            .foregroundStyle(info?.isError == true ? .red : .primary)
                        if let path = info?.fullOutputPath {
                            Button("Open Full Output") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        }
                    }
                } else if running {
                    Label("Running…", systemImage: "hourglass").foregroundStyle(.secondary)
                } else {
                    Text("No result: the run stopped before this call ran.").foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MessageDetail: View {
    let message: ChatMessage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(message.userCommand == nil ? "User message" : "Command you ran").font(.headline)
                Text(message.content).textSelection(.enabled).font(.body.monospaced())
                if let n = message.images?.count, n > 0 { Text("\(n) image\(n == 1 ? "" : "s") attached").foregroundStyle(.secondary) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helpers

private func prettyJSON(_ v: JSONValue) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? enc.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? ""
}

private func prettyArguments(_ s: String) -> String {
    guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) else { return s.isEmpty ? "(none)" : s }
    return prettyJSON(v)
}

/// Read-only text in an NSTextView: long requests and streams in a SwiftUI Text would lay out slowly.
struct PlainTextView: NSViewRepresentable {
    let text: String
    var monospaced = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.font = monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 13)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }
}

/// A compaction's summary requests from the wire log: how each went (the second is the plain-transcript fallback).
private struct SummaryRequestsView: View {
    let ids: [UUID]
    let wire: URL
    @State private var records: [WireRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(records.enumerated()), id: \.offset) { i, r in
                Text(line(i, r)).font(.callout).foregroundStyle(.secondary)
            }
        }
        .task {
            let ids = ids, wire = wire
            records = await Task.detached { ids.compactMap { WireLog.read(wire, replyID: $0) } }.value
        }
    }

    /// "Summary request: HTTP 200 · 26.3 s · 612 output tokens" (built apart: too much for the type checker inline).
    private func line(_ i: Int, _ r: WireRecord) -> String {
        var tokens: String?
        for p in r.payloads {
            guard case .object(let o) = p else { continue }
            // OpenAI's `usage.completion_tokens`, Anthropic's `usage.output_tokens`, Gemini's `usageMetadata`.
            if case .object(let u)? = o["usage"], case .number(let c)? = u["completion_tokens"] ?? u["output_tokens"] {
                tokens = "\(Int(c)) output tokens"
            }
            if case .object(let u)? = o["usageMetadata"], case .number(let c)? = u["candidatesTokenCount"] {
                let thoughts: Double = if case .number(let t)? = u["thoughtsTokenCount"] { t } else { 0 }
                tokens = "\(Int(c + thoughts)) output tokens"
            }
        }
        let kind = i == 0 ? "Summary request" : "Fallback request"
        let http = r.statuses.map(String.init).joined(separator: " → ")
        return kind + ": HTTP " + http + String(format: " · %.1f s", r.duration) + (tokens.map { " · " + $0 } ?? "")
    }
}

#if DEBUG
@MainActor private enum DebugOnce { static var done = false }
#endif
