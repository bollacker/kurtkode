import AgentCore
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: ChatController
    /// Follow new output while the view is scrolled to the bottom; stop when the user scrolls up.
    @State private var followBottom = true
    /// A find scrolled away from the end: closing it goes back.
    @State private var followBeforeFind = false
    /// Scrolls by edge, not by a view's id: in a lazy stack a marker view's position is an estimate until it's drawn,
    /// and after a long reply finished the transcript was left past its end (blank) or short of it.
    @State private var position = ScrollPosition(edge: .bottom)
    @AppStorage("showInspector") private var showInspector = false
    @AppStorage("inspectorTab") private var inspectorTab = "Todos"
    /// When the transcript last scrolled to follow a streaming reply.
    @State private var lastFollow = Date.distantPast
    @State private var followPending = false
    @Environment(\.openWindow) private var openWindow
    @State private var rewindTarget: RewindTarget?
    @State private var rewindError: String?
    /// Find in this chat: the bar, what's typed, the rows that match, and the one shown.
    @State private var findOpen = false
    @State private var findQuery = ""
    @State private var findHits: [UUID] = []
    @State private var findIndex = 0
    @FocusState private var findFocused: Bool
    /// The card on screen while others wait (`CardKeys.shown`).
    @State private var shownCard: CardKeys.Card?
    /// Where the transcript is scrolled to. Not state that redraws: it changes with every frame of a scroll.
    @State private var scrollOffset = ScrollOffset()

    final class ScrollOffset { var y: CGFloat = 0 }

    struct RewindTarget: Identifiable {
        let messageID: UUID
        let plan: RewindPlan
        var id: UUID { messageID }
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        VStack(spacing: 0) {
            if findOpen {
                findBar
                Divider()
            }
            transcript
            Divider()
            if let ws = controller.session.header.workspace {
                MCPApprovalBanner(workspace: ws)
            }
            if let pending = controller.pendingProjectHooks {
                HookApprovalBanner(controller: controller, config: pending)
            }
            if let pending = controller.pendingProjectRules {
                RulesApprovalBanner(controller: controller, rules: pending.rules)
            }
            if let offer = controller.escalation, controller.sendBlocker == nil {
                EscalationCard(controller: controller, offer: offer)
            }
            if let blocker = controller.sendBlocker {
                BlockerBanner(controller: controller, message: blocker)
            } else if let notice = controller.switchNotice, !controller.isGenerating {
                Label(notice, systemImage: "arrow.left.arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.quaternary.opacity(0.3))
            }
            TodoStrip(controller: controller)
            ComposerBar(controller: controller, findOpen: findOpen)
        }
        .focusedSceneValue(\.findInChat, openFind)
        .navigationTitle(controller.session.displayTitle)
        .inspector(isPresented: $showInspector) {
            InspectorView(controller: controller)
                .inspectorColumnWidth(min: 240, ideal: 350, max: 460)
        }
        .confirmationDialog("Rewind to this message?", isPresented: Binding(get: { rewindTarget != nil },
                                                                           set: { if !$0 { rewindTarget = nil } }),
                            presenting: rewindTarget) { target in
            let files = target.plan.files.count + target.plan.checkpointFiles.count
            Button(files == 0 ? "Rewind" : "Restore \(files) File\(files == 1 ? "" : "s") and Rewind", role: .destructive) { rewind(target, .both) }
            if files > 0 {
                Button("Restore Files Only") { rewind(target, .files) }
                Button("Rewind Conversation Only") { rewind(target, .conversation) }
            }
        } message: { target in
            Text(rewindMessage(target))
        }
        .onChange(of: controller.rewindRequest) {
            guard let id = controller.rewindRequest else { return }
            controller.rewindRequest = nil
            if let m = controller.session.messages.first(where: { $0.id == id }) { rewindAction(for: m)?() }
        }
        .alert("Rewind failed", isPresented: Binding(get: { rewindError != nil }, set: { if !$0 { rewindError = nil } })) {
        } message: { Text(rewindError ?? "") }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let ws = controller.workspace {
                    FoldersButton(controller: controller, workspace: ws)
                    PermissionModePicker(controller: controller)
                }
                // Buttons, so they're reachable by keyboard and VoiceOver, and lead somewhere useful.
                // Only once there's something to show: an empty one was an unnamed button in the toolbar.
                if let used = controller.contextUsed, let limit = controller.contextLimit, limit > 0 {
                    Button {
                        inspectorTab = "Context"
                        showInspector = true
                    } label: { ContextMeter(used: used, limit: limit) }
                        .buttonStyle(.plain)
                }
                if let cost = controller.sessionCost {
                    CostReadout(dollars: cost.dollars, estimate: cost.estimate, own: cost.own, subagents: cost.subagents)
                }
                Button { openWindow(id: "models") } label: { MemoryGauge(memory: app.memory) }
                    .buttonStyle(.plain)
                ModelPicker(controller: controller)
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Todos, changed files, and context (⌥⌘I)")
            }
        }
    }

    /// A compaction whose boundary is a tool result sits after that result's assistant message.
    private func toolBoundary(_ m: ChatMessage, _ dividers: [UUID: Compaction]) -> Compaction? {
        guard m.role == .assistant, !m.toolCalls.isEmpty else { return nil }
        let ids = Set(m.toolCalls.map(\.id))
        return controller.session.messages.last { $0.role == .tool && ids.contains($0.toolCallID ?? "") && dividers[$0.id] != nil }
            .flatMap { dividers[$0.id] }
    }

    private func rewindAction(for m: ChatMessage) -> (() -> Void)? {
        guard m.role == .user, controller.workspace != nil, !controller.isGenerating else { return nil }
        let c = controller
        return {
            Task { rewindTarget = RewindTarget(messageID: m.id, plan: await c.rewindPlan(to: m.id)) }
        }
    }

    /// A new conversation with what comes before this request, which waits in its composer.
    private func forkAction(before m: ChatMessage) -> (() -> Void)? {
        guard m.role == .user, m.contextNote != true else { return nil }
        let session = controller.session, app = app, c = controller
        return {
            Task {
                do { try await app.forkSession(session, before: m.id) } catch { c.notice = error.localizedDescription }
            }
        }
    }

    /// A new conversation that carries on from a final reply.
    private func forkAction(after m: ChatMessage) -> (() -> Void)? {
        guard m.role == .assistant, m.toolCalls.isEmpty else { return nil }
        let session = controller.session, app = app, c = controller
        let turn = (session.messages.filter { $0.role == .assistant }.firstIndex { $0.id == m.id } ?? 0) + 1
        return {
            Task {
                do { try await app.forkSession(session, atReply: m.id, turn: turn, after: true) }
                catch { c.notice = error.localizedDescription }
            }
        }
    }

    private func rewind(_ target: RewindTarget, _ choice: RewindChoice) {
        Task {
            do { try await controller.rewind(to: target.messageID, choice: choice) }
            catch { rewindError = error.localizedDescription }
        }
    }

    private func rewindMessage(_ t: RewindTarget) -> String {
        var s = t.plan.summary(.both, root: controller.workspace?.root.path)
        if !(t.plan.files + t.plan.checkpointFiles).isEmpty {
            s += "\n\nRestore Files Only keeps the conversation (the model is told); Rewind Conversation Only keeps the files."
        }
        return s
    }

    private var retryAction: (() -> Void)? {
        if controller.isGenerating { return nil }
        let c = controller
        return { c.retry() }
    }

    // MARK: Find

    private func openFind() {
        findOpen = true
        findFocused = true
        refreshFind()
    }

    private func closeFind() {
        findOpen = false
        findHits = []
        if followBeforeFind {
            followBeforeFind = false
            followBottom = true
            position.scrollTo(edge: .bottom)
        }
    }

    /// The rows that hold the text. A group's messages count as its row.
    private func refreshFind() {
        let messages = TranscriptSearch.hits(controller.session.messages, query: findQuery)
        guard !messages.isEmpty else {
            findHits = []
            return
        }
        var rowOf: [UUID: UUID] = [:]
        for row in rows() { for m in row.messages { rowOf[m.id] = row.id } }
        var hits: [UUID] = []
        for id in messages { if let row = rowOf[id], hits.last != row { hits.append(row) } }
        let keep = findHits.indices.contains(findIndex) ? hits.firstIndex(of: findHits[findIndex]) : nil
        findHits = hits
        findIndex = keep ?? (hits.count - 1)        // the newest first, like the transcript's own end
    }

    private func step(by n: Int) {
        guard !findHits.isEmpty else { return }
        findIndex = (findIndex + n + findHits.count) % findHits.count
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in this chat", text: $findQuery)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { step(by: -1) }
                .onExitCommand { closeFind() }
            if !findQuery.isEmpty {
                Text(findHits.isEmpty ? "No matches" : "\(findIndex + 1) of \(findHits.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { step(by: -1) } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(findHits.isEmpty)
                .help("Previous match (⇧⌘G, or Return)").accessibilityLabel("Previous match")
            Button { step(by: 1) } label: { Image(systemName: "chevron.down") }
                .keyboardShortcut("g", modifiers: .command).disabled(findHits.isEmpty)
                .help("Next match (⌘G)").accessibilityLabel("Next match")
            Button("Done", action: closeFind)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .onChange(of: findQuery) { findIndex = 0; findHits = []; refreshFind() }
        .onChange(of: controller.session.messages.count) { refreshFind() }
    }

    /// How a row shows in a find: 0 no match, 1 a match, 2 the one being shown.
    private func findLevel(_ row: UUID) -> Int {
        guard findOpen, findHits.contains(row) else { return 0 }
        return findHits[findIndex] == row ? 2 : 1
    }

    private var compactionDividers: [UUID: Compaction] {
        Dictionary(controller.session.compactions.map { ($0.lastSummarizedID, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func rows(_ results: [UUID: [String: ChatMessage]]? = nil, dividers: [UUID: Compaction]? = nil) -> [TranscriptRow] {
        let messages = controller.session.messages
        let dividers = dividers ?? compactionDividers
        return TranscriptRow.rows(messages, results: results ?? ChatMessage.resultsByReply(messages)) {
            dividers[$0.id] != nil || toolBoundary($0, dividers) != nil
        }
    }

    /// Changes whenever the transcript grows, to trigger following.
    private var growth: Int {
        var n = controller.session.messages.count * 1_000_000
        n += controller.streaming?.content.count ?? 0
        n += controller.streaming?.reasoning.count ?? 0
        if controller.runningTool != nil { n += 1 }
        if controller.pendingApproval != nil { n += 2 }
        if controller.isCompacting { n += 4 }
        n += controller.session.compactions.count * 8
        for text in controller.liveOutput.values { n += text.count }
        return n
    }

    /// The kinds of card waiting for an answer.
    private var waitingCards: Set<CardKeys.Card> {
        var waiting: Set<CardKeys.Card> = []
        if controller.pendingApproval != nil { waiting.insert(.approval) }
        if controller.pendingQuestion != nil { waiting.insert(.question) }
        if controller.pendingPlan != nil { waiting.insert(.plan) }
        return waiting
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                let results = ChatMessage.resultsByReply(controller.session.messages)
                let lastAssistant = controller.session.messages.last(where: { $0.role == .assistant })?.id
                let replyRuns = controller.session.replyRuns
                let dividers = compactionDividers
                ForEach(rows(results, dividers: dividers)) { row in
                    let find = findLevel(row.id)
                    switch row {
                    case .message(let m):
                        MessageView(message: m, isLast: m.id == lastAssistant, retry: retryAction,
                                    toolResults: results[m.id] ?? [:], running: controller.runningSince,
                                    liveOutput: controller.liveOutput, awaitingApprovalID: controller.pendingApproval?.id,
                                    rewind: rewindAction(for: m), fork: forkAction(before: m) ?? forkAction(after: m),
                                    thumbs: replyRuns[m.id].flatMap { controller.session.thumbs($0) },
                                    rate: replyRuns[m.id].map { run in { up in controller.rateRun(run, up: up) } })
                            .modifier(FindMark(level: find))
                    case .tools(let replies):
                        ToolGroupRow(replies: replies, results: results, running: controller.runningSince,
                                     liveOutput: controller.liveOutput, awaitingApprovalID: controller.pendingApproval?.id,
                                     forceOpen: find > 0)
                            .modifier(FindMark(level: find))
                    }
                    if let m = row.messages.last, let c = dividers[m.id] ?? toolBoundary(m, dividers) {
                        CompactionDivider(compaction: c)
                    }
                }
                if controller.isCompacting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Summarizing the conversation to free context…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let notice = controller.notice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if let snap = controller.streaming {
                    StreamingMessageView(snapshot: snap, startedAt: controller.streamStartedAt ?? Date(),
                                         runStartedAt: controller.runStartedAt, model: controller.session.model, stop: controller.stop)
                }
                // One card at a time, so two never share ⌘↩ and Escape; the others wait their turn.
                let waiting = waitingCards
                switch CardKeys.shown(current: shownCard, waiting: waiting) {
                case .approval?:
                    if let pending = controller.pendingApproval {
                        ApprovalCard(pending: pending, answer: controller.answer).id(pending.id)
                    }
                case .question?:
                    if let pending = controller.pendingQuestion {
                        QuestionCard(pending: pending, answer: controller.answerQuestion).id(pending.id)
                    }
                case .plan?:
                    if let pending = controller.pendingPlan {
                        PlanCard(pending: pending, decide: controller.decidePlan).id(pending.id)
                    }
                case nil:
                    EmptyView()
                }
                if waiting.count > 1 {
                    Label("Another request is waiting: it shows once this one is answered.", systemImage: "tray.full")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.lastStop == .stepLimit, !controller.isGenerating {
                    StepLimitBanner(continueRun: controller.continueRun)
                }
                if controller.lastStop == .costLimit, !controller.isGenerating {
                    CostLimitBanner(spent: controller.sessionCost?.dollars, note: controller.costLimitNote, continueRun: controller.continueRun)
                }
                if controller.lastStop == .denied, !controller.isGenerating {
                    DeniedBanner()
                }
                if controller.interruptedRun {
                    InterruptedBanner(controller: controller)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
            .environment(\.chatSessionID, controller.session.header.id)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onChange(of: waitingCards, initial: true) { _, waiting in
            shownCard = CardKeys.shown(current: shownCard, waiting: waiting)
        }
        // Only the user's own scrolling changes whether we follow. Content growing past the window also
        // changes the geometry, and must not count as "scrolled away".
        .onScrollPhaseChange { old, new, context in
            guard new == .idle, old == .interacting || old == .decelerating else { return }
            let g = context.geometry
            followBottom = g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 60
        }
        .onChange(of: growth) {
            guard followBottom else { return }
            // While a reply streams, at most twice a second: each scroll lays out the transcript to find the bottom.
            // A skipped one is put off to the end of the half second, so the newest text is always followed.
            let wait = controller.streaming == nil ? 0 : 0.5 - Date().timeIntervalSince(lastFollow)
            guard !followPending else { return }
            followPending = true
            Task { @MainActor in
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                // After the next layout pass, so newly added views (like an approval card) are measured.
                try? await Task.sleep(for: .milliseconds(30))
                followPending = false
                lastFollow = Date()
                guard followBottom else { return }
                position.scrollTo(edge: .bottom)
            }
        }
        // A lazy stack estimates the height of rows it hasn't drawn. A long chat could open short of its end, or past it
        // with nothing to see, and asking for the bottom changes nothing while the view thinks it's there. A real move
        // up one screen has the rows there measured; then the end is the true one.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in scrollOffset.y = y }
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            guard followBottom, scrollOffset.y > 0 else { return }
            position.scrollTo(y: max(0, scrollOffset.y - 800))
            for wait in [60, 200, 400] {
                try? await Task.sleep(for: .milliseconds(wait))
                if followBottom { position.scrollTo(edge: .bottom) }
            }
        }
        .task(id: findOpen && !findHits.isEmpty ? findHits[min(findIndex, findHits.count - 1)] : nil) {
            guard findOpen, findHits.indices.contains(findIndex) else { return }
            let row = findHits[findIndex]
            if followBottom { followBeforeFind = true }
            followBottom = false
            for wait in [0, 80, 200, 400] {
                try? await Task.sleep(for: .milliseconds(wait))
                proxy.scrollTo(row, anchor: .top)
            }
        }
        .onChange(of: controller.session.messages.last?.role) { _, role in
            // Sending always jumps to the bottom.
            if role == .user {
                followBottom = true
                position.scrollTo(edge: .bottom)
            }
        }
        .overlay {
            if controller.session.messages.isEmpty && controller.streaming == nil {
                if let ws = controller.workspace, controller.isChat, !controller.tools.isEmpty {
                    ContentUnavailableView("Ask anything", systemImage: "text.bubble",
                                           description: Text("\(controller.session.model) can use files in \(ExtraFolder(path: ws.root.path, writable: true).displayPath) "
                                                             + "and run commands there. " + PermissionModePicker.explanation(controller.permissionMode)))
                } else if let ws = controller.workspace, !controller.isChat {
                    ContentUnavailableView("Work on \(ws.root.lastPathComponent)", systemImage: "folder",
                                           description: Text("\(controller.session.model) works in \(ws.root.path). "
                                                             + PermissionModePicker.explanation(controller.permissionMode)))
                } else {
                    ContentUnavailableView("Ask anything", systemImage: "text.bubble",
                                           description: Text("Chatting with \(controller.session.model)"))
                }
            }
        }
        }
    }
}

/// A row's mark in a find. Lazy-stack rows can be several views (see MarkdownPieces): each gets it.
struct FindMark: ViewModifier {
    let level: Int

    func body(content: Content) -> some View {
        content.background(Color.yellow.opacity(level == 2 ? 0.28 : level == 1 ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The agent's todo list, above the composer while there's work left: how far along, and the step it's on. Click for
/// the whole list.
struct TodoStrip: View {
    let controller: ChatController
    @State private var expanded = false

    var body: some View {
        let items = controller.todos
        let done = items.filter { $0.status == .completed }.count
        if !items.isEmpty, done < items.count {
            VStack(alignment: .leading, spacing: 6) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(done), total: Double(items.count))
                            .progressViewStyle(.circular).controlSize(.mini)
                        Text("\(done) of \(items.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if let current = items.first(where: { $0.status == .inProgress }) ?? items.first(where: { $0.status == .pending }) {
                            Text(current.content).font(.callout).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Todo list: \(done) of \(items.count) done")
                if expanded {
                    ForEach(items) { TodoRow(item: $0) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))
        }
    }
}

/// Explains why sending is blocked, with the fix when there is one.
/// A4's offer: why the run looks wrong, and one click to hand the request to the next tier's model.
struct EscalationCard: View {
    let controller: ChatController
    let offer: EscalationOffer

    private var from: String { offer.fromModel.split(separator: "/").last.map(String.init) ?? offer.fromModel }

    private var detail: String {
        if let r = controller.escalationReview {
            return "The review on \(offer.toLabel) found it \(r.verdict?.label ?? "unclear")"
                + (r.findings.first.map { ": " + $0.problem } ?? "") + (r.findings.count > 1 ? " (+\(r.findings.count - 1) more in Changes)" : "") + "."
        }
        var s = "\(offer.toLabel) gets the conversation and \(from)'s changes, and picks up from there"
        if let e = offer.estimate { s += " (≈" + TypicalTask.money(e) + ": reading the conversation and a typical task)" }
        if offer.canReview { s += ". Or first have \(offer.toLabel) only review the change" }
        return s + "."
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "arrow.up.forward.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("This may need a stronger model: " + offer.reasonText + ".").lineLimit(3)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            if let r = controller.escalationReview {
                // Decision 4, after the review: fix on the session's model, or hand over; handing over comes first only
                // when the review found the change wrong (`CodeReview.escalates`).
                if !r.findings.isEmpty {
                    if r.escalates {
                        Button("Fix on \(from)") { controller.fixEscalationFindings() }
                            .disabled(controller.isGenerating)
                    } else {
                        Button("Fix on \(from)") { controller.fixEscalationFindings() }
                            .buttonStyle(.borderedProminent)
                            .disabled(controller.isGenerating)
                    }
                }
                if r.escalates {
                    Button(offer.buttonTitle) { controller.acceptEscalation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isGenerating)
                } else {
                    Button(offer.buttonTitle) { controller.acceptEscalation() }
                        .disabled(controller.isGenerating)
                }
            } else if offer.canReview {
                // Decision 4: one read-only review first, a fraction of a re-run's cost.
                Button(offer.reviewTitle) { controller.reviewEscalation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isGenerating || controller.reviewing)
                Button(offer.buttonTitle) { controller.acceptEscalation() }
                    .disabled(controller.isGenerating || controller.reviewing)
            } else {
                Button(offer.buttonTitle) { controller.acceptEscalation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isGenerating)
            }
            Button("Not Now") { controller.declineEscalation() }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.blue.opacity(0.07))
    }
}

struct BlockerBanner: View {
    @Environment(AppModel.self) private var app
    let controller: ChatController
    let message: String
    @AppStorage(Pref.defaultContextLength) private var contextLength = 32768
    @State private var error: String?

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                if let report = app.lastLoadReport { Text(report).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let e = controller.endpoint, e.kind == .lmstudio, e.isLocal {
                if app.loading != nil {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                } else if case .unreachable = app.catalogs[e.id]?.reachability {
                    Button("Start LM Studio Server") { run { try await app.startLocalServer() } }
                } else if controller.modelEntry?.isLoaded == false {
                    Button("Load with \(contextLength / 1024)k context") {
                        run { try await app.loadModel(controller.session.model, on: e.id, contextLength: contextLength) }
                    }
                    .help("Unloads other models first, then loads with one parallel slot.")
                }
            }
            Button { Task { await app.refreshModels(controller.session.endpointID) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Check again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }

    private func run(_ op: @escaping @MainActor () async throws -> Void) {
        error = nil
        Task { do { try await op() } catch { self.error = error.localizedDescription } }
    }
}

/// A row in the composer's completion list: a slash command, or a path for `@`.
enum Suggestion: Identifiable {
    case command(SlashCommand)
    case path(String)

    var id: String {
        switch self {
        case .command(let c): "/" + c.name
        case .path(let p): "@" + p
        }
    }
}

struct ComposerBar: View {
    @Bindable var controller: ChatController
    /// The chat's find bar is open: Escape belongs to it.
    var findOpen = false
    @State private var selected = 0
    /// The draft when the list was dismissed with Escape; it stays hidden until the draft changes.
    @State private var dismissedAt: String?
    /// Going through earlier prompts with ↑ and ↓, and the one last put in the draft.
    @State private var recall: PromptRecall?
    @State private var recalled: String?

    /// Where the window's typing goes: Escape in the sidebar's search or a review comment is that field's own.
    @Environment(\.textFocus) private var textFocus

    /// Escape stops the run, unless something on screen is asking and takes it for itself.
    private var escapeStops: Bool {
        controller.isGenerating && !findOpen && controller.pendingApproval == nil && controller.pendingQuestion == nil
            && controller.pendingPlan == nil
    }

    /// Pastes the draft holds as tokens.
    private var heldPastes: [PastedText] { controller.pastes.filter { controller.draft.contains($0.token) } }

    /// The `@` token being typed at the end of the draft, if any.
    private var mentionToken: Substring? {
        let d = controller.draft
        guard let last = d.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@"), !last.contains("\n") else { return nil }
        let before = d.dropLast(last.count)
        return before.isEmpty || before.last?.isWhitespace == true ? last : nil
    }

    /// Commands while the draft is just "/name"; paths while an `@` token is being typed.
    private var suggestions: [Suggestion] {
        let d = controller.draft
        guard d != dismissedAt else { return [] }
        if d.hasPrefix("/"), !d.contains(where: \.isWhitespace) {
            return SlashCommands.matching(String(d.dropFirst()), in: controller.commands).map(Suggestion.command)
        }
        if let token = mentionToken, controller.workspace != nil {
            let partial = token.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return Mentions.completions(partial, files: controller.fileIndex).map(Suggestion.path)
        }
        return []
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        let suggestions = suggestions
        VStack(alignment: .leading, spacing: 6) {
            if !controller.queued.isEmpty {
                QueuedMessages(controller: controller)
            }
            if !controller.pendingImages.isEmpty {
                PendingImages(controller: controller)
            }
            let held = heldPastes
            if !held.isEmpty {
                PendingPastes(controller: controller, pastes: held)
            }
            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions, selected: min(selected, suggestions.count - 1), pick: pick)
            }
            composer(suggestions)
        }
        .padding(12)
        // For focus outside the composer (a selection in the transcript, say); in it, the key arrives at `handle`.
        .background {
            if escapeStops, suggestions.isEmpty, CardKeys.escapeStopsRun(focus: textFocus) {
                Button("") { controller.stop() }.keyboardShortcut(.escape, modifiers: []).hidden()
            }
        }
        .onChange(of: controller.draft) {
            selected = 0
            if mentionToken != nil { controller.refreshFileIndex() }
        }
        .onAppear { controller.refreshFileIndex() }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            for p in providers {
                if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                              let data = try? Data(contentsOf: url) else { return }
                        Task { @MainActor in controller.attachImage(data) }
                    }
                } else {
                    p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        guard let data else { return }
                        Task { @MainActor in controller.attachImage(data) }
                    }
                }
            }
            return true
        }
    }

    /// A command that needs nothing more runs at once; otherwise it's filled in for its arguments. A path
    /// replaces the `@` token (a folder stays open, so its contents can be completed next).
    private func pick(_ s: Suggestion) {
        switch s {
        case .command(let c):
            if c.runsWithoutArguments && c.argumentHint.isEmpty {
                controller.draft = "/" + c.name
                controller.send()
            } else {
                controller.draft = "/" + c.name + " "
            }
        case .path(let p):
            fill(p)
        }
    }

    private func fill(_ s: Suggestion) {
        switch s {
        case .command(let c): controller.draft = "/" + c.name + " "
        case .path(let p): fill(p)
        }
    }

    private func fill(_ path: String) {
        guard let token = mentionToken else { return }
        let mention = path.contains(" ") ? "@\"\(path)\"" : "@" + path
        controller.draft = String(controller.draft.dropLast(token.count)) + mention + (path.hasSuffix("/") ? "" : " ")
    }

    private func handle(_ key: ComposerKey, atEdge: Bool, _ suggestions: [Suggestion]) -> Bool {
        guard !suggestions.isEmpty else {
            switch key {
            case .up, .down: return recallPrompt(older: key == .up, atEdge: atEdge)
            case .escape:
                if escapeStops { controller.stop() }
                // Not for the text view: it would open its word completions. A card asking keeps its own Escape.
                return controller.pendingApproval == nil && controller.pendingQuestion == nil && controller.pendingPlan == nil
            default: return false
            }
        }
        let current = suggestions[min(selected, suggestions.count - 1)]
        switch key {
        case .up: selected = (min(selected, suggestions.count - 1) + suggestions.count - 1) % suggestions.count
        case .down: selected = (min(selected, suggestions.count - 1) + 1) % suggestions.count
        case .tab: fill(current)
        case .submit: pick(current)
        case .escape: dismissedAt = controller.draft
        }
        return true
    }

    /// ↑ at the top of an empty draft takes back what's queued, then goes through earlier prompts; ↓ comes back. Once
    /// a prompt is in the draft, the arrows go on through them wherever the caret is, until it's edited.
    private func recallPrompt(older: Bool, atEdge: Bool) -> Bool {
        let walking = recall?.isWalking == true && controller.draft == recalled
        guard atEdge || walking else { return false }
        if older, !walking, controller.draft.isEmpty, controller.takeBackQueued() { return true }
        if !walking { recall = PromptRecall(entries: controller.session.prompts) }
        guard let next = older ? recall?.older(draft: controller.draft) : recall?.newer() else { return false }
        recalled = next
        controller.draft = next
        return true
    }

    private func composer(_ suggestions: [Suggestion]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: chooseImages) { Image(systemName: "paperclip").font(.title3) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Attach Images")
                .help(controller.acceptsImages ? "Attach images (or paste or drop them)"
                                               : "Attach images (\(shortName) can't see images)")
            ComposerTextView(text: $controller.draft,
                             placeholder: controller.isGenerating
                                ? "Add a message: it goes to \(shortName) at its next step"
                                : "Message \(shortName) — Return to send, ⇧Return for a new line, / for commands, @ for files, ! to run a command",
                             onSubmit: {
                                 controller.send(keeping: recall?.waiting ?? "")
                                 recall = nil
                             }, onKey: { handle($0, atEdge: $1, suggestions) },
                             onPasteImages: { for d in $0 { controller.attachImage(d) } },
                             onPasteLongText: { controller.holdPaste($0) })
                .frame(minHeight: 22, maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
            if controller.isGenerating {
                Button(action: controller.stop) {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stop")
                .help("Stop (⌘.)")
            } else {
                Button { controller.send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Send")
                .disabled((controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.pendingImages.isEmpty)
                          || (controller.sendBlocker != nil && SlashCommands.parse(controller.draft) == nil
                              && UserShell.command(in: controller.draft) == nil))
                .help("Send (Return)")
            }
        }
    }

    private var shortName: String {
        controller.session.model.split(separator: "/").last.map(String.init) ?? controller.session.model
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Images to attach to your next message"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let d = try? Data(contentsOf: url) { controller.attachImage(d) } }
    }
}

/// Images waiting to go with the next message; each can be removed.
struct PendingImages: View {
    let controller: ChatController

    var body: some View {
        HStack(spacing: 8) {
            ForEach(controller.pendingImages) { image in
                ZStack(alignment: .topTrailing) {
                    ImageThumbnail(image: image, size: 64)
                    Button {
                        controller.pendingImages.removeAll { $0.id == image.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.borderless)
                    .offset(x: 5, y: -5)
                }
            }
            if !controller.acceptsImages {
                Label("This model can't see images", systemImage: "eye.slash").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// A small preview of an attached image; click to open it in Preview.
struct ImageThumbnail: View {
    let image: ImageAttachment
    var size: CGFloat = 96

    var body: some View {
        // The whole image, scaled to fit: `size` tall, up to twice as wide.
        let aspect = image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 1
        let width = min(size * 2, max(size / 2, size * aspect))
        Group {
            if let ns = NSImage(contentsOfFile: image.path) {
                Image(nsImage: ns).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: width / aspect)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: image.path)) }
        .help("\(image.width)×\(image.height) — click to open")
    }
}

/// Long pastes the draft holds: each can be opened up in the draft, or removed.
struct PendingPastes: View {
    let controller: ChatController
    let pastes: [PastedText]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pastes) { paste in
                HStack(spacing: 5) {
                    Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
                    Text("Pasted text #\(paste.id)")
                    Text("\(paste.lineCount) line\(paste.lineCount == 1 ? "" : "s")").foregroundStyle(.secondary)
                    Button("Show") {
                        controller.draft = controller.draft.replacingOccurrences(of: paste.token, with: paste.text)
                    }
                    .buttonStyle(.link)
                    .help("Put the text in the composer")
                    Button {
                        controller.draft = controller.draft.replacingOccurrences(of: paste.token, with: "")
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .help("Remove this paste")
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .help(String(paste.text.prefix(400)))
            }
        }
    }
}

/// What was typed while the agent works: messages wait for its next step, commands for its end. Each can be taken
/// back, or taken back to edit.
struct QueuedMessages: View {
    let controller: ChatController

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.isGenerating ? "Queued: the agent reads messages at its next step; commands run when it's done"
                                         : "Queued")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(controller.queued.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: SlashCommands.parse(text) != nil || UserShell.command(in: text) != nil ? "terminal" : "clock")
                        .foregroundStyle(.secondary)
                    Text(text).lineLimit(3)
                    Spacer(minLength: 8)
                    Button {
                        controller.editQueued(at: i)
                    } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .help("Take this back to edit it")
                    Button {
                        if i < controller.queued.count { controller.queued.remove(at: i) }
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .help("Don't send this")
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// Completions for what's typed: ↑↓ to choose, Tab to fill in, Return to run or fill in, Escape to hide.
struct SuggestionList: View {
    let suggestions: [Suggestion]
    let selected: Int
    let pick: (Suggestion) -> Void

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, s in
                        Button { pick(s) } label: {
                            row(s)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(i == selected ? Color.accentColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(s.id)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: min(CGFloat(suggestions.count) * 29 + 8, 240))
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .onChange(of: selected) { proxy.scrollTo(suggestions[min(selected, suggestions.count - 1)].id) }
        }
    }

    @ViewBuilder private func row(_ s: Suggestion) -> some View {
        switch s {
        case .command(let c):
            HStack(spacing: 8) {
                Text("/" + c.name).font(.body.monospaced()).fontWeight(.medium)
                if !c.argumentHint.isEmpty {
                    Text(c.argumentHint).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(c.description).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if !c.isBuiltIn { Text("custom").font(.caption2).foregroundStyle(.tertiary) }
            }
        case .path(let p):
            HStack(spacing: 8) {
                Image(systemName: p.hasSuffix("/") ? "folder" : "doc.text").foregroundStyle(.secondary)
                Text(p).font(.body.monospaced()).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The session's project folder. Click to show it in Finder.
/// The folders the agent may use: the project (or a chat's working folder) and the session's extra folders.
struct FoldersButton: View {
    let controller: ChatController
    let workspace: Workspace
    @State private var showing = false

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        Button { showing.toggle() } label: {
            Label(workspace.root.lastPathComponent + (workspace.folders.isEmpty ? "" : " +\(workspace.folders.count)"),
                  systemImage: controller.isChat ? "tray" : "folder")
                .labelStyle(.titleAndIcon)
        }
        .help(controller.tools.isEmpty ? "\(workspace.root.path): this model doesn't support tools"
              : "Folders the agent can use: \(([workspace.root.path] + workspace.folders.map(\.path)).joined(separator: ", "))")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            FoldersPanel(controller: controller)
        }
        #if DEBUG
        // KURTKODE_OPEN_SHEET=folders: open this panel once, a few seconds after launch.
        .task {
            guard !Self.debugShown, ProcessInfo.processInfo.environment["KURTKODE_OPEN_SHEET"] == "folders" else { return }
            Self.debugShown = true
            try? await Task.sleep(for: .seconds(3))
            NSApp.activate()            // a popover in an inactive app closes at once
            showing = true
        }
        #endif
    }

    #if DEBUG
    nonisolated(unsafe) static var debugShown = false
    #endif
}

struct FoldersPanel: View {
    let controller: ChatController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ws = controller.workspace {
                Text(controller.isChat ? "Working folder" : "Project").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: controller.isChat ? "tray" : "folder")
                    Text(ExtraFolder(path: ws.root.path, writable: true).displayPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([ws.root]) }.buttonStyle(.link)
                }
                Divider()
                Text("Other folders").font(.caption).foregroundStyle(.secondary)
                if ws.folders.isEmpty {
                    Text("None. The agent can only use \(controller.isChat ? "the working folder" : "the project").")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(ws.folders) { f in
                    HStack {
                        Image(systemName: "folder")
                        Text(f.displayPath).lineLimit(1).truncationMode(.middle).help(f.path)
                        Spacer()
                        Toggle("Read and write", isOn: Binding(get: { f.writable }, set: { controller.setWritable(f, $0) }))
                            .toggleStyle(.switch).controlSize(.mini)
                            .help("Off: the agent can read this folder but not change it")
                        Button { controller.removeFolder(f) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove")
                    }
                }
                Button("Add Folder…") { choose() }
                Text("Edits and commands in these folders follow the permission mode, like the "
                     + "\(controller.isChat ? "working folder" : "project"). New folders are read-only until you switch them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { controller.addFolder(url, writable: false) }
    }
}

/// Asks about MCP servers a project's .mcp.json wants to run: they're commands from the repository, so each
/// needs a yes once (for its exact command).
struct MCPApprovalBanner: View {
    @Environment(AppModel.self) private var app
    let workspace: String
    @State private var dismissed: Set<String> = []
    @State private var error: String?

    var body: some View {
        let waiting = (app.mcpStatus[workspace] ?? []).filter { $0.state == .needsApproval && !dismissed.contains($0.entry.name) }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("This project's .mcp.json wants to start \(waiting.count == 1 ? "an MCP server" : "\(waiting.count) MCP servers"). "
                      + "Command servers run as programs on your Mac, outside the sandbox; remote (URL) servers receive "
                      + "the arguments of every call to their tools. Start only ones you trust.",
                      systemImage: "puzzlepiece.extension")
                    .font(.callout)
                ForEach(waiting) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Text(s.entry.name).fontWeight(.medium)
                        // All of what Start approves: the whole command (not truncated), its environment and headers.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.entry.config.displayCommand)
                            ForEach(s.entry.config.approvalDetails, id: \.self) { Text($0) }
                        }
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Not Now") { dismissed.insert(s.entry.name) }
                        Button("Start") {
                            Task {
                                do { try await app.approveMCP(workspace, s.entry.name) }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.orange.opacity(0.08))
        }
    }
}

/// Asks about a project's allow rules (its settings files allow commands or edits without asking): a repository
/// could otherwise grant itself whatever it likes. Its deny and ask rules already apply.
struct RulesApprovalBanner: View {
    let controller: ChatController
    let rules: [String]
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 6) {
                Label("This project's settings allow these without asking you. Allow them only if you trust this project "
                      + "(its deny and ask rules already apply).", systemImage: "checkmark.shield")
                    .font(.callout)
                ForEach(rules, id: \.self) { Text($0).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    Spacer()
                    Button("Not Now") { dismissed = true }
                    Button("Allow Rules") { controller.approveProjectRules() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.orange.opacity(0.08))
        }
    }
}

/// Asks about the hooks in a project's .kurtkode/settings.json: commands from the repository that would run
/// at points in the agent's work, so they need a yes once (again whenever they change).
struct HookApprovalBanner: View {
    let controller: ChatController
    let config: HookConfig
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 6) {
                Label("This project's .kurtkode/settings.json has hooks: commands that would run on your Mac, outside the "
                      + "sandbox, as the agent works. Allow them only if you trust this project.", systemImage: "link")
                    .font(.callout)
                ForEach(config.commands, id: \.self) { Text($0).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    Spacer()
                    Button("Not Now") { dismissed = true }
                    Button("Allow Hooks") { controller.approveProjectHooks() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.orange.opacity(0.08))
        }
    }
}
