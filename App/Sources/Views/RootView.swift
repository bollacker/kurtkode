import AgentCore
import SwiftUI

/// One window: sessions on the left, the selected chat on the right.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: UUID?
    @State private var controller: ChatController?
    @State private var choosingFolder = false
    @State private var welcoming = false
    /// Where this window's typing goes: the cards' shortcuts and Escape-stops keep out of other fields.
    @State private var textFocus: CardKeys.Focus = .none
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        NavigationSplitView {
            SidebarView(selection: $selection, newChat: newChat, openFolder: { choosingFolder = true },
                        newChatIn: { ws in newChat(in: ws) })
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
        } detail: {
            if let controller {
                ChatView(controller: controller)
                    .id(controller.id)
            } else {
                ContentUnavailableView {
                    Label("No chat selected", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Open a project folder to let the agent read its files, or start a plain chat.")
                } actions: {
                    Button("Open Folder…") { choosingFolder = true }.keyboardShortcut(.defaultAction)
                    Button("New Chat", action: newChat)
                }
            }
        }
        .environment(\.textFocus, textFocus)
        .background(FirstResponderReader { textFocus = $0 })
        .focusedSceneValue(\.newChat, newChat)
        .focusedSceneValue(\.openFolder, { choosingFolder = true })
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { newChat(in: url.path) }
        }
        .focusedSceneValue(\.stopGenerating, stopAction)
        .sheet(isPresented: $welcoming) {
            WelcomeSheet { welcoming = false; Pref.d.set(true, forKey: Pref.welcomed) }
                .environment(app)
        }
        .task {
            // Once, for someone with nothing here yet: a person with chats needs no introduction.
            try? await Task.sleep(for: .milliseconds(800))
            if !Pref.d.bool(forKey: Pref.welcomed), app.sessions.isEmpty { welcoming = true }
            else { Pref.d.set(true, forKey: Pref.welcomed) }
        }
        .task(id: selection) {
            // A slower load of an earlier pick can finish after a later one: only the current pick may set the chat.
            guard let id = await select(selection) else { return }
            Notifier.shared.clear(session: id)
            app.existingController(id)?.unread = false
        }
        .onChange(of: app.trashedSessions) { _, trashed in
            // Moved to the Trash in this window or another: stop showing it here.
            if let selection, trashed.contains(selection) { self.selection = nil }
        }
        .onAppear {
            // A notification's click opens its session here.
            Notifier.shared.open = { id in app.requestedSelection = id }
        }
        .onChange(of: app.requestedSelection) { _, id in
            // /clear in this window's chat opens its replacement here.
            if let id, app.sessions.contains(where: { $0.id == id }) {
                selection = id
                app.requestedSelection = nil
            }
        }
        #if DEBUG
        .task { await autosendForTesting() }
        #endif
    }

    #if DEBUG
    /// Development hook: `open --env KURTKODE_AUTOSEND="text" [--env KURTKODE_WORKSPACE=/path] kurtkode.app`
    /// starts a chat (in that project, if given) and sends the text once the model catalog has loaded.
    /// Lets the app be exercised end to end without UI scripting. Runs once per launch: `.task` runs again
    /// whenever the view reappears (a reopened window re-sent the request hours later).
    @MainActor private static var autosendDone = false

    /// "endpoint|model" (or just a model on the default endpoint): switch to it, loading it if it's local.
    private func switchModelForTesting(_ c: ChatController, _ spec: String) async {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        let ep = parts.count == 2 ? (app.endpoints.first { $0.name.lowercased() == parts[0].lowercased() } ?? app.defaultEndpoint) : app.defaultEndpoint
        let model = parts.last ?? spec
        Log.app.notice("autosend: switching to \(model, privacy: .public) on \(ep.name, privacy: .public)")
        c.setModel(model, endpointID: ep.id)
        if ep.kind == .lmstudio, ep.isLocal, app.catalogs[ep.id]?.entry(model)?.isLoaded != true {
            do { try await app.loadModel(model, on: ep.id, contextLength: 32768) }
            catch { Log.app.error("autosend: load failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func autosendForTesting() async {
        // KURTKODE_OPEN_WINDOW=models: open that window at launch.
        if !Self.autosendDone, let id = ProcessInfo.processInfo.environment["KURTKODE_OPEN_WINDOW"] {
            if id == "settings" { openSettings() } else { openWindow(id: id) }
        }
        // KURTKODE_OPEN_SESSION=<uuid>: show that session at launch (and send KURTKODE_AUTOSEND into it, if set).
        let openID = ProcessInfo.processInfo.environment["KURTKODE_OPEN_SESSION"].flatMap(UUID.init(uuidString:))
        if !Self.autosendDone, let openID, ProcessInfo.processInfo.environment["KURTKODE_AUTOSEND"] == nil {
            Self.autosendDone = true
            for _ in 0..<40 where !app.sessions.contains(where: { $0.id == openID }) { try? await Task.sleep(for: .milliseconds(250)) }
            Log.app.notice("autosend: opening session \(openID.uuidString, privacy: .public)")
            selection = openID
            return
        }
        guard !Self.autosendDone, let text = ProcessInfo.processInfo.environment["KURTKODE_AUTOSEND"], !text.isEmpty else { return }
        Self.autosendDone = true
        Log.app.notice("autosend: waiting for the model list")
        for _ in 0..<40 where app.catalogs[app.defaultEndpoint.id] == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let workspace = ProcessInfo.processInfo.environment["KURTKODE_WORKSPACE"]
        Log.app.notice("autosend: catalog ready=\(app.catalogs[app.defaultEndpoint.id] != nil), creating a session in \(workspace ?? "-", privacy: .public)")
        let id: UUID
        if let openID {
            for _ in 0..<40 where !app.sessions.contains(where: { $0.id == openID }) { try? await Task.sleep(for: .milliseconds(250)) }
            id = openID
        } else {
            guard let new = try? await app.newSession(workspace: workspace) else { Log.app.error("autosend: newSession failed"); return }
            id = new
        }
        selection = id
        guard let c = await app.controller(for: id) else { Log.app.error("autosend: no controller"); return }
        Log.app.notice("autosend: sending; blocker=\(c.sendBlocker ?? "none", privacy: .public)")
        let env = ProcessInfo.processInfo.environment
        if let mode = env["KURTKODE_MODE"].flatMap(PermissionMode.init(rawValue:)) { c.setPermissionMode(mode) }
        // KURTKODE_MCP_APPROVE=1: approve the project's MCP servers (what the banner's Start does).
        if env["KURTKODE_MCP_APPROVE"] != nil, let ws = workspace.map(AppModel.mcpKey) {
            app.mcpHub(for: ws)
            for _ in 0..<50 where app.mcpStatus[ws] == nil { try? await Task.sleep(for: .milliseconds(100)) }
            for s in app.mcpStatus[ws] ?? [] where s.state == .needsApproval { try? await app.approveMCP(ws, s.entry.name) }
        }
        // KURTKODE_MODEL=endpoint|model: use (and load, if local) this model for the first message.
        if let first = env["KURTKODE_MODEL"] { await switchModelForTesting(c, first) }
        // KURTKODE_IMAGE=path[,path]: attach these images to the first message.
        for path in (env["KURTKODE_IMAGE"] ?? "").split(separator: ",") {
            if let data = FileManager.default.contents(atPath: String(path)) { c.attachImage(data) }
        }
        c.draft = text
        c.send()
        // KURTKODE_QUEUE=text [KURTKODE_QUEUE_AFTER=seconds]: type this while the run is going (queued input).
        if let queued = env["KURTKODE_QUEUE"] {
            try? await Task.sleep(for: .seconds(env["KURTKODE_QUEUE_AFTER"].flatMap(Double.init) ?? 2))
            Log.app.notice("autosend: queueing while generating=\(c.isGenerating)")
            c.draft = queued
            c.send()
        }
        // KURTKODE_DRAFT=text: leave this in the composer unsent (to see the command list, for example).
        if let draft = env["KURTKODE_DRAFT"] { c.draft = draft }
        // KURTKODE_FORK=1: once the run ends, fork at its last request (what a message's Fork does).
        if env["KURTKODE_FORK"] != nil {
            while c.isGenerating { try? await Task.sleep(for: .milliseconds(250)) }
            if let m = c.session.messages.last(where: { $0.role == .user }) { _ = try? await app.forkSession(c.session, before: m.id) }
        }
        // KURTKODE_THEN_MODEL=endpoint|model and KURTKODE_THEN_SEND=text: after the first run, switch model
        // (loading it if it's local) and send a follow-up: a two-model session end to end.
        if let then = env["KURTKODE_THEN_MODEL"], let text2 = env["KURTKODE_THEN_SEND"] {
            while c.isGenerating { try? await Task.sleep(for: .milliseconds(250)) }
            await switchModelForTesting(c, then)
            Log.app.notice("autosend: follow-up; blocker=\(c.sendBlocker ?? "none", privacy: .public); \(app.lastLoadReport ?? "", privacy: .public)")
            c.draft = text2
            c.send()
        }
        // KURTKODE_REWIND_AFTER=seconds: once the run ends, wait, then rewind the whole exchange.
        if let delay = env["KURTKODE_REWIND_AFTER"].flatMap(Double.init), let first = c.session.messages.first?.id {
            while c.isGenerating { try? await Task.sleep(for: .milliseconds(250)) }
            try? await Task.sleep(for: .seconds(delay))
            let choice = env["KURTKODE_REWIND_CHOICE"].flatMap(RewindChoice.init(rawValue:)) ?? .both
            let restored = (try? await c.rewind(to: first, choice: choice)) ?? []
            print("KURTKODE_REWOUND \(restored.map(\.path))")
        }
    }
    #endif

    private var stopAction: (@MainActor () -> Void)? {
        guard let controller, controller.isGenerating else { return nil }
        return { controller.stop() }
    }

    /// Shows the chat for `id`, unless the selection moved on while it loaded. Returns the id it showed, if any.
    private func select(_ id: UUID?) async -> UUID? {
        guard let id else {
            controller = nil
            return nil
        }
        let c = await app.controller(for: id)
        guard !Task.isCancelled, selection == id else { return nil }
        app.lastSelectedSession = id
        controller = c
        return id
    }

    /// New chat in the same project as the selected one (a plain chat if none).
    private func newChat() {
        newChat(in: app.workspace(of: selection))
    }

    private func newChat(in workspace: String?) {
        Task {
            if let id = try? await app.newSession(workspace: workspace) { selection = id }
        }
    }

}

/// The first thing a new install shows: which model servers answer, and a way to start with one.
private struct WelcomeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    let done: () -> Void

    /// The first model that can answer now: a loaded local one, else the first on a server that lists any.
    private var ready: (endpoint: Endpoint, model: String)? {
        for e in app.endpoints {
            if let m = app.catalogs[e.id]?.entries.first(where: \.isLoaded) { return (e, m.id) }
        }
        for e in app.endpoints {
            if let m = app.catalogs[e.id]?.entries.first { return (e, m.id) }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to kurtkode").font(.title2).fontWeight(.semibold)
            Text("An agent that works in your project folders, on local or hosted models.").foregroundStyle(.secondary)
            ForEach(app.endpoints) { e in
                let entries = app.catalogs[e.id]?.entries ?? []
                Label(e.name + (entries.isEmpty ? ": not answering yet" : ": \(entries.count) model\(entries.count == 1 ? "" : "s")"),
                      systemImage: entries.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(entries.isEmpty ? Color.secondary : Color.green)
            }
            if ready == nil {
                Text("Start LM Studio with a model loaded, or add a hosted service with its API key in Settings → Endpoints.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Add a Server…") {
                    openSettings()
                    done()
                }
                Spacer()
                Button("Later", action: done)
                if let ready {
                    Button("Use \(ready.model.split(separator: "/").last.map(String.init) ?? ready.model)") {
                        Pref.d.set(ready.model, forKey: Pref.defaultModel)
                        Pref.d.set(ready.endpoint.id.uuidString, forKey: Pref.defaultEndpointID)
                        done()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// What a chat in the sidebar needs: it's waiting for the user, running, or finished unseen. Its own view, so a run's
/// changes redraw this and not the list.
private struct SessionBadge: View {
    @Environment(AppModel.self) private var app
    let id: UUID

    var body: some View {
        if let c = app.existingController(id) {
            if c.pendingApproval != nil || c.pendingQuestion != nil || c.pendingPlan != nil {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .help("Waiting for you").accessibilityLabel("Waiting for you")
            } else if c.isGenerating {
                ProgressView().controlSize(.mini).help("Running").accessibilityLabel("Running")
            } else if c.unread {
                Circle().fill(.tint).frame(width: 7, height: 7)
                    .help("Finished; not read yet").accessibilityLabel("Finished, not read yet")
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: UUID?
    let newChat: () -> Void
    let openFolder: () -> Void
    let newChatIn: (String?) -> Void
    @State private var renaming: SessionSummary?
    @State private var newTitle = ""
    /// The project a new worktree goes in, and its name as typed.
    @State private var worktreeProject: String?
    @State private var worktreeName = ""
    /// A worktree about to be removed, with what that would lose.
    @State private var removing: (worktree: GitRepo.Worktree, repo: GitRepo, state: GitRepo.WorktreeState)?
    @State private var worktreeError: String?
    /// What's typed in the search field, and the chats whose conversations hold it, with the words around it.
    @State private var query = ""
    @State private var found: [UUID: String] = [:]
    @FocusState private var searchFocused: Bool

    /// Copies a chat as it is into a new one, shown here.
    private func fork(_ s: SessionSummary) {
        Task {
            var session = app.existingController(s.id)?.session
            if session == nil { session = try? await app.sessionStore.load(s.id) }
            if let session { _ = try? await app.forkSession(session, before: nil) }
        }
    }

    private func isWorktree(_ workspace: String?) -> Bool {
        workspace.map { GitRepo(root: URL(fileURLWithPath: $0)).isLinkedWorktree } ?? false
    }

    private func prepareRemoval(_ workspace: String) {
        let repo = GitRepo(root: URL(fileURLWithPath: workspace))
        Task {
            do {
                let real = Workspace(path: workspace).root.path
                guard let w = try await repo.worktrees().first(where: { Workspace(path: $0.path).root.path == real }) else { return }
                let main = GitRepo(root: try await repo.mainRoot())
                removing = (w, main, try await main.worktreeState(w))
            } catch { worktreeError = error.localizedDescription }
        }
    }

    /// What removing the worktree loses: the files, named, and the commits on no other branch.
    static func removalMessage(_ s: GitRepo.WorktreeState) -> String {
        var text = ""
        if s.uncommitted > 0 { text += "\(s.uncommitted) file\(s.uncommitted == 1 ? " isn't" : "s aren't") committed. " }
        if s.ignored > 0 { text += "\(s.ignored) ignored file\(s.ignored == 1 ? "" : "s") would be deleted too. " }
        if !s.lostFiles.isEmpty { text += "Lost: \(s.lostNames()). " }
        if s.unmerged > 0 { text += "\(s.unmerged) commit\(s.unmerged == 1 ? " is" : "s are") on no other branch: its branch stays. " }
        return text + "Chats there stay in the list, but can't go on."
    }

    private func remove(_ r: (worktree: GitRepo.Worktree, repo: GitRepo, state: GitRepo.WorktreeState), deleteBranch: Bool) {
        Task {
            do {
                if let now = try await r.repo.removeWorktree(r.worktree, told: r.state, deleteBranch: deleteBranch) {
                    removing = (r.worktree, r.repo, now)
                    return
                }
                await app.refreshSessions()
            } catch { worktreeError = error.localizedDescription }
        }
    }

    private func matches(_ s: SessionSummary) -> Bool {
        guard !query.isEmpty else { return true }
        return found[s.id] != nil || [s.title, s.model, s.workspace ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        let groups = groups
        List(selection: $selection) {
            // Sections are identified by folder path, never by title: two folders can share a name, and a
            // duplicate id corrupts the sidebar's NSOutlineView (it stopped taking clicks).
            ForEach(groups) { group in
                Section {
                    ForEach(group.sessions) { s in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).lineLimit(1)
                                Text(found[s.id] ?? s.model.split(separator: "/").last.map(String.init) ?? s.model)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            SessionBadge(id: s.id)
                        }
                        .tag(s.id)
                        .help(s.workspace ?? "Plain chat, no project folder")
                        .contextMenu {
                            Button("Rename…") { newTitle = s.title; renaming = s }
                            Button("Fork") { fork(s) }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                if selection == s.id { selection = nil }
                                Task { await app.trash(s.id) }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label(group.title, systemImage: group.workspace == nil ? "bubble.left" : isWorktree(group.workspace) ? "arrow.triangle.branch" : "folder")
                        Spacer()
                        if let ws = group.workspace, GitRepo(root: URL(fileURLWithPath: ws)).exists {
                            Button { worktreeName = ""; worktreeProject = ws } label: { Image(systemName: "arrow.triangle.branch") }
                                .buttonStyle(.borderless)
                                .help("New chat in a worktree: its own branch and files, beside this one's")
                                .accessibilityLabel("New chat in a worktree of \(group.title)")
                        }
                        Button { newChatIn(group.workspace) } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .help(group.workspace.map { "New chat in \($0)" } ?? "New plain chat")
                    }
                    .contextMenu {
                        if let ws = group.workspace, isWorktree(ws) {
                            Button("Remove Worktree…") { prepareRemoval(ws) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search chats", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand { query = ""; searchFocused = false }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear search")
                }
            }
            .font(.callout)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .focusedSceneValue(\.searchChats, { searchFocused = true })
        .task(id: query) {
            guard !query.isEmpty else { found = [:]; return }
            // Titles match as typed; the conversations once typing pauses.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let hits = try? await app.sessionStore.search(query), !Task.isCancelled else { return }
            found = Dictionary(hits.map { ($0.id, $0.snippet) }, uniquingKeysWith: { first, _ in first })
        }
        .toolbar {
            ToolbarItem {
                Button(action: openFolder) { Label("Open Folder", systemImage: "folder.badge.plus") }
                    .help("Open a project folder (⌘O)")
            }
            ToolbarItem {
                Button(action: newChat) { Label("New Chat", systemImage: "square.and.pencil") }
                    .help("New chat in the current project (⌘N)")
            }
        }
        .alert("New Worktree", isPresented: Binding(get: { worktreeProject != nil }, set: { if !$0 { worktreeProject = nil } })) {
            TextField("Name", text: $worktreeName)
            Button("Create") {
                if let project = worktreeProject {
                    let name = worktreeName
                    Task {
                        do { try await app.newWorktreeSession(project: project, name: name) }
                        catch { worktreeError = error.localizedDescription }
                    }
                }
                worktreeProject = nil
            }
            Button("Cancel", role: .cancel) { worktreeProject = nil }
        } message: {
            Text("A separate checkout of the project on a branch kk/name, from what's committed now. Chats there don't touch this one's files.")
        }
        .confirmationDialog("Remove the worktree \(removing?.worktree.name ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let r = removing {
                Button(r.state.uncommitted > 0 ? "Remove and Lose Uncommitted Files" : r.state.ignored > 0 ? "Remove and Lose Ignored Files" : "Remove",
                       role: .destructive) { remove(r, deleteBranch: false) }
                if r.state.unmerged == 0 { Button("Remove It and Its Branch", role: .destructive) { remove(r, deleteBranch: true) } }
            }
        } message: {
            if let r = removing { Text(Self.removalMessage(r.state)) }
        }
        .alert("Worktree", isPresented: Binding(get: { worktreeError != nil }, set: { if !$0 { worktreeError = nil } })) {
        } message: { Text(worktreeError ?? "") }
        .alert("Rename Chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                if let s = renaming, !newTitle.isEmpty { Task { await app.rename(s.id, to: newTitle) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .overlay {
            if app.sessions.isEmpty {
                Text("No chats yet").foregroundStyle(.secondary)
            } else if groups.isEmpty {
                Text("No chats match").foregroundStyle(.secondary)
            }
        }
    }

    private struct Group: Identifiable {
        let title: String
        let workspace: String?
        let sessions: [SessionSummary]
        var id: String { workspace ?? "" }
    }

    /// One section per project folder, most recently used first; plain chats under "Chats". Paths are
    /// resolved first, so sessions saved as /tmp/x and /private/tmp/x share one section. Folders with the
    /// same name get their parent folder added to the title.
    private var groups: [Group] {
        var order: [String?] = []
        var byWorkspace: [String?: [SessionSummary]] = [:]
        var seen = Set<UUID>()
        for s in app.sessions where matches(s) && seen.insert(s.id).inserted {     // already newest first; each session once
            let ws = s.workspace.map { Workspace(path: $0).root.path }
            if byWorkspace[ws] == nil { order.append(ws) }
            byWorkspace[ws, default: []].append(s)
        }
        let names = order.compactMap { $0.map { URL(fileURLWithPath: $0).lastPathComponent } }
        return order.map { ws in
            var title = "Chats"
            if let ws {
                let url = URL(fileURLWithPath: ws)
                title = url.lastPathComponent
                if names.filter({ $0 == title }).count > 1 {
                    title += " (\(url.deletingLastPathComponent().lastPathComponent))"
                }
            }
            return Group(title: title, workspace: ws, sessions: byWorkspace[ws] ?? [])
        }
    }
}
