import AgentCore
import Charts
import SwiftUI

/// The Debug window's Journal: a session's whole life in one stream (what the user sent, the model's reasoning and
/// replies, tool uses, what the loop did, compactions, changes), with a lens that shows what any one turn's request
/// held, each entry's lifetime in the context, the context budget per turn, and where a tool call's values came from.
struct JournalView: View {
    let session: Session
    let wire: URL
    let contextLimit: Int?
    /// Opens a task call's subagent run (the Debug window's drill-in); nil inside a run.
    var openSubagent: ((UUID) -> Void)? = nil
    @State private var contexts: [ContextSnapshot] = []
    /// Thinking the server dropped from requests (read from the wire log).
    @State private var dropped: [UUID: [UUID: String]] = [:]
    @State private var lens: Int? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KURTKODE_DEBUG_LENS"].flatMap(Int.init)
        #else
        return nil
        #endif
    }()
    @State private var selected: String?
    @State private var jump: String?
    @State private var showBudget = true
    @State private var filter: SessionJournal.Filter = {
        var f = SessionJournal.Filter()
        #if DEBUG
        // KURTKODE_DEBUG_SEARCH=text, KURTKODE_DEBUG_GROUPS=reasoning,tools (by Group raw value's first word).
        let env = ProcessInfo.processInfo.environment
        if let q = env["KURTKODE_DEBUG_SEARCH"] { f.query = q }
        if let g = env["KURTKODE_DEBUG_GROUPS"] {
            let want = Set(g.lowercased().split(separator: ",").map(String.init))
            f.groups = Set(SessionJournal.Entry.Group.allCases.filter { want.contains(String($0.rawValue.lowercased().split(separator: " ")[0])) })
        }
        #endif
        return f
    }()
    @State private var hitIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let journal = SessionJournal(session: session, contexts: contexts, droppedThinking: dropped)
        let statuses = lens.map { journal.statuses(inTurn: $0) } ?? [:]
        let shown = journal.visible(effectiveFilter, statuses: statuses)
        let hits = journal.hits(filter.query, in: shown)
        VStack(spacing: 0) {
            if journal.turnCount > 0, contexts.isEmpty {
                Label("This session has no context index: it was recorded before this version, or with Record requests and "
                      + "responses off. The journal shows what happened; the lens needs the index.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).padding(10)
                Divider()
            }
            if showBudget, !journal.budget.isEmpty {
                BudgetChart(budget: journal.budget, limit: contextLimit, summaryCost: journal.summaryCost, lens: $lens)
                    .frame(height: 150)
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            lensBar(journal)
            filterBar(journal, shown: shown.count, hits: hits)
            Divider()
            HSplitView {
                entries(shown, statuses, hits: hits)
                    .frame(minWidth: 420, idealWidth: 640)
                Group {
                    if let id = selected, let e = journal.entries.first(where: { $0.id == id }) {
                        EntryInspector(entry: e, journal: journal, lens: lens, wire: wire, parent: session.header,
                                       fallbackSystem: session.systemPrompt, openSubagent: openSubagent) { target in
                            selected = target
                            jump = target
                        }
                        .id(e.id)
                    } else {
                        ContentUnavailableView("Select an entry", systemImage: "text.alignleft",
                                               description: Text("Its lifetime in the context, its full text, and for a tool use, "
                                                                 + "where its values came from."))
                    }
                }
                .frame(minWidth: 320, idealWidth: 420, maxHeight: .infinity)
            }
        }
        .task(id: session.messages.count) {
            let wire = wire
            let session = session
            (contexts, dropped) = await Task.detached {
                (WireLog.contexts(wire), SessionJournal.droppedThinking(session: session, wire: wire))
            }.value
            #if DEBUG
            // KURTKODE_DEBUG_SELECT=N: select turn N's first tool use (or first entry) and scroll to it.
            if let n = ProcessInfo.processInfo.environment["KURTKODE_DEBUG_SELECT"].flatMap(Int.init) {
                let j = SessionJournal(session: session, contexts: contexts, droppedThinking: dropped)
                let pick = j.entries.first { if case .toolUse = $0.kind { $0.turn == n } else { false } } ?? j.entries.first { $0.turn == n }
                if let pick { selected = pick.id; try? await Task.sleep(for: .milliseconds(300)); jump = pick.id }
            }
            if ProcessInfo.processInfo.environment["KURTKODE_DEBUG_SEARCH"] != nil {
                let j = SessionJournal(session: session, contexts: contexts, droppedThinking: dropped)
                if let first = j.hits(filter.query, in: j.visible(effectiveFilter, statuses: [:])).first {
                    try? await Task.sleep(for: .milliseconds(300))
                    jump = first
                }
            }
            #endif
        }
    }

    private func lensBar(_ journal: SessionJournal) -> some View {
        HStack(spacing: 10) {
            Text("Context lens").font(.headline)
            Picker("Context lens", selection: $lens) {
                Text("Off").tag(Int?.none)
                ForEach(journal.contexts.keys.sorted(), id: \.self) { Text("Turn \($0)").tag(Int?.some($0)) }
            }
            .labelsHidden().frame(width: 110)
            if let n = lens {
                Button { lens = max(1, n - 1) } label: { Image(systemName: "chevron.left") }.disabled(n <= 1)
                    .accessibilityLabel("Lens on the previous turn")
                Button { lens = min(journal.turnCount, n + 1) } label: { Image(systemName: "chevron.right") }.disabled(n >= journal.turnCount)
                    .accessibilityLabel("Lens on the next turn")
                if let s = journal.contexts[n] {
                    Text("turn \(n)'s request held \(s.refs.count) messages, " + Self.promptSize(journal, turn: n, snapshot: s))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Legend()
            Toggle("Budget", isOn: $showBudget).toggleStyle(.button)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: Search and filters

    private func filterBar(_ journal: SessionJournal, shown: Int, hits: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search everything, reasoning included", text: $filter.query)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search the journal")
                        .focused($searchFocused)
                        .onSubmit { step(hits, by: 1) }
                    if !filter.query.isEmpty {
                        Text(hits.isEmpty ? "no matches" : "\(min(hitIndex, hits.count - 1) + 1) of \(hits.count)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Button { filter.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                            .accessibilityLabel("Clear the search")
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 380)
                Button { step(hits, by: -1) } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(hits.isEmpty).help("Previous match (⇧⌘G)")
                    .accessibilityLabel("Previous match")
                Button { step(hits, by: 1) } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut("g", modifiers: .command).disabled(hits.isEmpty).help("Next match (⌘G, or Return)")
                    .accessibilityLabel("Next match")
                Toggle("Only matches", isOn: $filter.onlyMatches).disabled(filter.query.isEmpty)
                Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden().frame(width: 0)
                Spacer()
                Text("showing \(shown) of \(journal.entries.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !filter.isEmpty {
                    Button("Clear Filters") { filter = SessionJournal.Filter(); hitIndex = 0 }
                }
            }
            HStack(spacing: 6) {
                ForEach(SessionJournal.Entry.Group.allCases, id: \.self) { g in
                    Toggle(isOn: Binding(get: { filter.groups.contains(g) },
                                         set: { if $0 { filter.groups.insert(g) } else { filter.groups.remove(g) } })) {
                        Label(Self.shortName(g), systemImage: Self.icon(g))
                    }
                    .toggleStyle(.button).controlSize(.small).help(g.rawValue)
                }
                Divider().frame(height: 16)
                Picker("Tool", selection: $filter.tool) {
                    Text("All tools").tag(String?.none)
                    ForEach(toolNames, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 180).controlSize(.small)
                Picker("Lens", selection: $filter.lens) {
                    ForEach(SessionJournal.Filter.Lens.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 300).controlSize(.small)
                .disabled(lens == nil).help(lens == nil ? "Pick a lens turn first" : "What turn \(lens!)'s request held, or left out")
                Divider().frame(height: 16)
                Toggle("Turns", isOn: Binding(get: { filter.turns != nil },
                                              set: { filter.turns = $0 ? 1...max(1, journal.turnCount) : nil }))
                    .controlSize(.small)
                if let range = filter.turns {
                    let last = max(1, journal.turnCount)
                    Stepper("\(range.lowerBound)", value: Binding(get: { range.lowerBound },
                                                                  set: { filter.turns = min($0, range.upperBound)...range.upperBound }),
                            in: 1...last).controlSize(.small).monospacedDigit()
                    Text("to").foregroundStyle(.secondary)
                    Stepper("\(range.upperBound)", value: Binding(get: { range.upperBound },
                                                                  set: { filter.turns = range.lowerBound...max($0, range.lowerBound) }),
                            in: 1...last).controlSize(.small).monospacedDigit()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
        .onChange(of: filter.query) { _, _ in
            hitIndex = 0
            if let first = hits.first { jump = first }
        }
    }

    /// The filter as applied: the lens filter needs a lens turn.
    private var effectiveFilter: SessionJournal.Filter {
        var f = filter
        if lens == nil { f.lens = .all }
        return f
    }

    private var toolNames: [String] { Array(Set(session.messages.flatMap { $0.toolCalls.map(\.name) })).sorted() }

    /// Moves to the next (or previous) match, selecting it and scrolling there.
    private func step(_ hits: [String], by d: Int) {
        guard !hits.isEmpty else { return }
        hitIndex = ((min(hitIndex, hits.count - 1) + d) % hits.count + hits.count) % hits.count
        selected = hits[hitIndex]
        jump = hits[hitIndex]
    }

    static func shortName(_ g: SessionJournal.Entry.Group) -> String {
        switch g {
        case .turns: "Prompts & replies"
        case .reasoning: "Reasoning"
        case .tools: "Tools"
        case .loop: "Loop"
        case .context: "System & summaries"
        case .events: "Changes"
        }
    }

    static func icon(_ g: SessionJournal.Entry.Group) -> String {
        switch g {
        case .turns: "text.bubble"
        case .reasoning: "brain"
        case .tools: "hammer"
        case .loop: "wrench.and.screwdriver"
        case .context: "gearshape"
        case .events: "arrow.triangle.swap"
        }
    }

    private func entries(_ shown: [SessionJournal.Entry], _ statuses: [String: SessionJournal.Status], hits: [String]) -> some View {
        let hitSet = Set(hits)
        let current = hits.isEmpty ? nil : hits[min(hitIndex, hits.count - 1)]
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if shown.isEmpty {
                        Text("Nothing matches these filters.").foregroundStyle(.secondary).padding()
                    }
                    ForEach(shown) { e in
                        EntryRow(entry: e, status: lens == nil ? nil : statuses[e.id], selected: selected == e.id,
                                 query: hitSet.contains(e.id) ? filter.query : "", current: current == e.id)
                            .id(e.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = e.id }
                    }
                }
                .padding(10)
            }
            .onChange(of: jump) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                jump = nil
            }
        }
    }
}

// MARK: - Rows

private struct EntryRow: View {
    let entry: SessionJournal.Entry
    let status: SessionJournal.Status?
    let selected: Bool
    /// The search, when this entry matches it (its text is highlighted).
    var query = ""
    /// The match the search is on.
    var current = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(gutter).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                header
                content
                if case .notSent(let why)? = status, !why.isEmpty {
                    Text("Not in this request: \(why)").font(.caption).foregroundStyle(.secondary)
                } else if status == .trimmed {
                    Text("In this request, shortened").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : current ? Color.yellow : .clear, lineWidth: 2))
        .opacity(status == .later ? 0.35 : 1)
    }

    private var gutter: Color {
        switch status {
        case .inContext?: .green
        case .trimmed?: .yellow
        case .notSent?: .gray.opacity(0.5)
        case .thisTurn?: .blue
        default: .clear
        }
    }

    private var background: Color {
        switch entry.kind {
        case .reasoning: .purple.opacity(0.07)
        case .user, .command, .attachment: .accentColor.opacity(0.07)
        case .toolUse: .secondary.opacity(0.07)
        case .loop: .orange.opacity(0.07)
        default: .clear
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(iconColor)
            Text(title).font(.callout.weight(.medium))
            Spacer()
            if let t = entry.turn, t > 0 { Text("turn \(t)").font(.caption).foregroundStyle(.secondary) }
            Text(entry.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            if entry.bytes > 0 { Text("~\(max(1, entry.bytes / 4)) tok").font(.caption).foregroundStyle(.tertiary).monospacedDigit() }
        }
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .system(let summary):
            Text("The system prompt\(summary ? ", with a compaction summary" : ""). Select to read it.").foregroundStyle(.secondary)
        case .user(let m), .output(let m):
            Text(marked(clip(m.content.isEmpty ? "(no text)" : m.content))).lineLimit(selected ? nil : 12).textSelection(.enabled)
                .foregroundStyle(m.content.isEmpty ? .secondary : .primary)
        case .command(let m):
            Text(clip("!" + (m.userCommand?.command ?? "") + "\n" + (m.userCommand?.output ?? ""))).font(.callout.monospaced()).lineLimit(selected ? nil : 8)
        case .reasoning(let m):
            Text(marked(clip(m.reasoning ?? ""))).italic().foregroundStyle(.secondary).lineLimit(selected ? nil : 8).textSelection(.enabled)
        case .attachment(let c, let r), .toolUse(let c, _, let r):
            VStack(alignment: .leading, spacing: 2) {
                Text(marked(c.name + " " + oneLine(c.arguments))).font(.callout.monospaced()).lineLimit(2)
                if let r {
                    Text(marked(clip(r.content))).font(.caption.monospaced()).lineLimit(selected ? 30 : 6)
                        .foregroundStyle(r.toolResult?.isError == true ? .red : .secondary)
                } else {
                    Text("(no result)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .loop(let note, _):
            Text(marked(note)).foregroundStyle(.orange)
        case .compaction(let c):
            Text(marked(clip(c.modelText))).font(.callout).lineLimit(selected ? nil : 6).foregroundStyle(.secondary)
        case .event(let e):
            Text(e.text).foregroundStyle(.secondary)
        }
    }

    /// The text with the search's matches highlighted.
    private func marked(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return a }
        var from = text.startIndex
        while let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            if let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) {
                a[lo..<hi].backgroundColor = .yellow.opacity(0.55)
            }
            from = r.upperBound
        }
        return a
    }

    private var title: String {
        switch entry.kind {
        case .system: "System prompt"
        case .user: "You"
        case .command: "Command you ran"
        case .attachment: "Attached"
        case .reasoning: "Reasoning"
        case .output(let m): shortName(m.meta?.reportedModel ?? m.meta?.requestedModel ?? "Model")
        case .toolUse(let c, _, let r):
            (TaskTool.summary(forCallNamed: c.name, arguments: c.arguments) ?? c.name) + (r?.toolResult?.isError == true ? " (error)" : "")
        case .loop: "The loop"
        case .compaction(let c): "Summarized: \(c.tokensBefore / 1000)k → \(max(1, c.tokensAfter / 1000))k tokens"
        case .event(let e):
            switch e.kind {
            case .model: "Model changed"
            case .mode: "Permission mode changed"
            case .folders: "Folders changed"
            case .title: "Renamed"
            }
        }
    }

    private var icon: String {
        switch entry.kind {
        case .system: "gearshape"
        case .user: "person"
        case .command: "terminal"
        case .attachment: "paperclip"
        case .reasoning: "brain"
        case .output: "text.bubble"
        case .toolUse: "hammer"
        case .loop: "wrench.and.screwdriver"
        case .compaction: "rectangle.compress.vertical"
        case .event: "arrow.triangle.swap"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .reasoning: .purple
        case .loop: .orange
        case .toolUse(_, _, let r) where r?.toolResult?.isError == true: .red
        default: .secondary
        }
    }
}

private func clip(_ s: String, _ n: Int = 4000) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
private func oneLine(_ s: String) -> String {
    let flat = s.replacingOccurrences(of: "\n", with: " ")
    return flat.count > 160 ? String(flat.prefix(160)) + "…" : flat
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 8) {
            item(.green, "in the request")
            item(.yellow, "shortened")
            item(.gray.opacity(0.5), "not sent")
            item(.blue, "this turn")
        }
        .font(.caption)
    }
    private func item(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 3) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8); Text(s).foregroundStyle(.secondary) }
    }
}

// MARK: - Budget

extension JournalView {
    /// "3,852 prompt tokens" as the server reported them, else "about 1.2k tokens" from the messages' size (without the
    /// system prompt and tools, which aren't in the index).
    static func promptSize(_ journal: SessionJournal, turn n: Int, snapshot s: ContextSnapshot) -> String {
        if let b = journal.budget.first(where: { $0.turn == n }), journal.reportedPrompt(turn: n) {
            return "\(b.promptTokens.formatted()) prompt tokens"
        }
        return String(format: "about %.1fk tokens of messages", Double(s.refs.reduce(0) { $0 + $1.bytes }) / 4000)
    }
}

private struct BudgetChart: View {
    let budget: [SessionJournal.Budget]
    let limit: Int?
    /// What the session's summaries cost (no turn of their own); in the session's total, not a turn's.
    var summaryCost = 0.0
    @Binding var lens: Int?

    static let order = ["system", "summary", "user", "assistant", "tool"]
    static let labels = ["system": "System", "summary": "Summary", "user": "User", "assistant": "Model", "tool": "Tools"]

    /// One bar segment: a turn's tokens from one part.
    struct Segment: Identifiable {
        let turn: Int
        let part: String
        let tokens: Int
        var id: String { "\(turn)-\(part)" }
    }

    private var maxPrompt: Int { budget.map(\.promptTokens).max() ?? 0 }

    private var segments: [Segment] {
        budget.flatMap { b in Self.order.map { Segment(turn: b.turn, part: Self.labels[$0] ?? $0, tokens: b.parts[$0] ?? 0) } }
    }

    private func bar(_ s: Segment) -> some ChartContent {
        BarMark(x: .value("Turn", s.turn), y: .value("Tokens", s.tokens))
            .foregroundStyle(by: .value("Part", s.part))
            .opacity(lens == nil || lens == s.turn ? 1.0 : 0.45)
    }

    private let colors: KeyValuePairs<String, Color> = [
        "System": .gray, "Summary": .orange, "User": .accentColor, "Model": .green, "Tools": .brown,
    ]

    /// Turns whose server said what it read from its cache.
    private var cached: [SessionJournal.Budget] { budget.filter { $0.cachedTokens != nil } }

    /// "Read from the cache: 57% of prompt tokens · cost ≈$0.0022 (list price)", or one turn's figures under the lens.
    private var caption: String? {
        let rows = lens.map { n in budget.filter { $0.turn == n } } ?? budget
        var parts: [String] = []
        let reporting = rows.filter { $0.cachedTokens != nil }
        let prompt = reporting.map(\.promptTokens).reduce(0, +)
        if prompt > 0 {
            let read = reporting.compactMap(\.cachedTokens).reduce(0, +)
            parts.append(String(format: "read from the cache: %.0f%% of prompt tokens", Double(read) / Double(prompt) * 100))
        }
        let costs = rows.compactMap(\.cost)
        let summaries = lens == nil ? summaryCost : 0
        if !costs.isEmpty || summaries > 0 {
            let estimate = rows.contains { $0.cost != nil && $0.costIsEstimate } || summaries > 0
            parts.append(String(format: "cost %@$%.4f", estimate ? "≈" : "", costs.reduce(0, +) + summaries)
                         + (summaries > 0 ? String(format: " (summaries $%.4f)", summaries) : "") + (estimate ? " (list price where not charged)" : ""))
        }
        guard !parts.isEmpty else { return nil }
        let s = parts.joined(separator: " · ")
        return (lens.map { "Turn \($0): " } ?? "Session: ") + s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            chart
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).padding(.leading, 4) }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { bar($0) }
            // How much of each prompt the server read from its cache (where it says): a line over the bars.
            ForEach(cached, id: \.turn) { b in
                LineMark(x: .value("Turn", b.turn), y: .value("Tokens", b.cachedTokens ?? 0), series: .value("Series", "cache"))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                PointMark(x: .value("Turn", b.turn), y: .value("Tokens", b.cachedTokens ?? 0))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .symbolSize(14)
            }
            // The limit only when it's near the bars: a 262k line would flatten 9k prompts to nothing.
            if let limit, limit <= maxPrompt * 2 {
                RuleMark(y: .value("Context", limit))
                    .foregroundStyle(Color.red.opacity(0.6))
                    .lineStyle(StrokeStyle(dash: [4, 3]))
            }
        }
        .chartForegroundStyleScale(colors)
        .chartXAxisLabel("Turn")
        .chartYAxisLabel(limit.map { $0 > maxPrompt * 2 ? "Prompt tokens (context limit \($0 / 1000)k)" : "Prompt tokens" } ?? "Prompt tokens")
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        if let turn: Int = proxy.value(atX: x) {
                            let nearest = budget.min { abs($0.turn - turn) < abs($1.turn - turn) }?.turn
                            lens = nearest == lens ? nil : nearest
                        }
                    }
            }
        }
        .help("Each turn's prompt, by what filled it; the dotted line is what the server read from its cache. Click a turn to "
              + "see what its request held.")
    }
}

// MARK: - Inspector

private struct EntryInspector: View {
    let entry: SessionJournal.Entry
    let journal: SessionJournal
    let lens: Int?
    let wire: URL
    let parent: SessionHeader
    /// A subagent run's recorded system prompt, when its wire record isn't there.
    let fallbackSystem: String?
    let openSubagent: ((UUID) -> Void)?
    let jumpTo: (String) -> Void
    @State private var systemText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(heading).font(.headline)
                if !isEvent {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lifetime in the context").font(.subheadline.weight(.semibold))
                        LifetimeStrip(entry: entry, journal: journal, lens: lens)
                        Text(journal.lifetimeSummary(entry)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if case .toolUse(_, _, let r) = entry.kind, let run = r?.toolResult?.subagentRun {
                    SubagentSection(runID: run, parent: parent, open: openSubagent)
                }
                if case .toolUse(let call, _, _) = entry.kind {
                    provenance(call)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text").font(.subheadline.weight(.semibold))
                    Text(fullText).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            guard case .system = entry.kind, let turn = entry.turn,
                  let reply = journal.turnOfReply.first(where: { $0.value == turn })?.key else { return }
            let wire = wire
            let record = await Task.detached { WireLog.read(wire, replyID: reply) }.value
            if case .object(let o)? = record?.messages.first, case .string(let s)? = o["content"] { systemText = s }
            else { systemText = fallbackSystem ?? "(no wire record)" }
        }
    }

    private var isEvent: Bool { if case .event = entry.kind { true } else { false } }

    private var heading: String {
        switch entry.kind {
        case .system: "System prompt from turn \(entry.turn ?? 0)"
        case .toolUse(let c, _, _): "\(c.name) in turn \(entry.turn ?? 0)"
        default: (entry.turn.map { $0 > 0 ? "Turn \($0) · " : "" } ?? "") + entry.date.formatted(date: .abbreviated, time: .standard)
        }
    }

    private var fullText: String {
        switch entry.kind {
        case .system: return systemText ?? "(loading from the wire record…)"
        case .toolUse(let c, _, let r), .attachment(let c, let r):
            return "Arguments:\n" + c.arguments + "\n\nResult:\n" + (r?.content ?? "(none)")
        default: return entry.text
        }
    }

    private func provenance(_ call: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where did these values come from?").font(.subheadline.weight(.semibold))
            let values = SessionJournal.values(call)
            if values.isEmpty { Text("No text values to trace.").foregroundStyle(.secondary) }
            ForEach(values, id: \.self) { v in
                HStack {
                    Text(v).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let origin = journal.origin(of: v, before: entry.id) {
                        Button(originLabel(origin)) { jumpTo(origin.id) }.buttonStyle(.link)
                    } else {
                        Text("not seen earlier").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func originLabel(_ e: SessionJournal.Entry) -> String {
        let what: String
        switch e.kind {
        case .user: what = "your message"
        case .attachment: what = "an attachment"
        case .reasoning: what = "reasoning"
        case .output: what = "a reply"
        case .toolUse(let c, _, _): what = "\(c.name) result"
        case .compaction: what = "a summary"
        default: what = "earlier"
        }
        return "from \(what)" + (e.turn.map { $0 > 0 ? ", turn \($0)" : "" } ?? "")
    }
}

/// One cell per turn: green where the entry was in the request, yellow where shortened, grey where not.
private struct LifetimeStrip: View {
    let entry: SessionJournal.Entry
    let journal: SessionJournal
    let lens: Int?

    var body: some View {
        let n = journal.turnCount
        HStack(spacing: 1) {
            ForEach(1...max(1, n), id: \.self) { t in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(journal.status(entry, inTurn: t)))
                    .frame(width: max(3, min(14, 300 / CGFloat(max(1, n)))), height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 1).stroke(t == lens ? Color.primary : .clear, lineWidth: 1))
                    .help("Turn \(t)")
            }
        }
    }

    private func color(_ s: SessionJournal.Status) -> Color {
        switch s {
        case .inContext: .green
        case .trimmed: .yellow
        case .thisTurn: .blue
        case .later, .none: .clear
        case .notSent: .gray.opacity(0.35)
        }
    }
}
