import AgentCore
import SwiftUI

/// Side pane for the current session: the agent's todo list, files it changed, and context use.
struct InspectorView: View {
    let controller: ChatController
    @AppStorage("inspectorTab") private var tab = Tab.todos.rawValue

    enum Tab: String, CaseIterable {
        case todos = "Todos", changes = "Changes", agents = "Agents", git = "Git", context = "Context"

        var symbol: String {
            switch self {
            case .todos: "checklist"
            case .changes: "doc.badge.ellipsis"
            case .agents: "person.2"
            case .git: "arrow.triangle.branch"
            case .context: "gauge.with.dots.needle.33percent"
            }
        }
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        VStack(spacing: 0) {
            // Five names need about 330 points; a narrower pane clipped the first and last ("odos", "Contex"), so it
            // gets icons (with the names as tooltips and for VoiceOver) instead.
            ViewThatFits(in: .horizontal) {
                tabPicker { Text($0.rawValue) }
                tabPicker { Image(systemName: $0.symbol).help($0.rawValue).accessibilityLabel($0.rawValue) }
            }
            .padding(10)
            Divider()
            ScrollView {
                switch Tab(rawValue: tab) ?? .todos {
                case .todos: TodoPane(items: controller.todos)
                case .changes: TaskChangesPane(controller: controller)
                case .agents: SubagentsPane(controller: controller)
                case .git:
                    if let root = controller.workspace?.root {
                        GitPane(repo: GitRepo(root: root), isGenerating: controller.isGenerating, controller: controller)
                    } else {
                        Text("Git needs a project folder.").font(.callout).foregroundStyle(.secondary).padding(12)
                    }
                case .context: ContextPane(controller: controller)
                }
            }
        }
        .frame(minWidth: 240)
    }

    private func tabPicker(@ViewBuilder _ label: @escaping (Tab) -> some View) -> some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.rawValue) { label($0).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct TodoPane: View {
    let items: [TodoWriteTool.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("No todo list yet. The agent makes one for work with several steps.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let done = items.filter { $0.status == .completed }.count
                ProgressView(value: Double(done), total: Double(items.count)) {
                    Text("\(done) of \(items.count) done").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(items) { TodoRow(item: $0) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodoRow: View {
    let item: TodoWriteTool.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch item.status {
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .inProgress: Image(systemName: "circle.dotted.circle").foregroundStyle(.orange)
            case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Text(item.content)
                .strikethrough(item.status == .completed)
                .foregroundStyle(item.status == .completed ? .secondary : .primary)
                .fontWeight(item.status == .inProgress ? .semibold : .regular)
        }
        .font(.callout)
    }
}

struct ChangesPane: View {
    let files: [(path: String, diffs: [String])]
    let root: String?
    @State private var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if files.isEmpty {
                Text("The agent hasn't changed any files in this session.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(files, id: \.path) { file in
                DisclosureGroup(isExpanded: Binding(get: { open == file.path }, set: { open = $0 ? file.path : nil })) {
                    ForEach(Array(file.diffs.enumerated()), id: \.offset) { _, d in DiffView(diff: d, maxHeight: 220) }
                } label: {
                    HStack {
                        Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Text(stats(file.diffs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        if let root {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root).appending(path: file.path)])
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stats(_ diffs: [String]) -> String {
        var add = 0, rem = 0
        for d in diffs {
            for l in d.split(separator: "\n") {
                if l.hasPrefix("+"), !l.hasPrefix("+++") { add += 1 }
                if l.hasPrefix("-"), !l.hasPrefix("---") { rem += 1 }
            }
        }
        return "+\(add) −\(rem)"
    }
}

struct ContextPane: View {
    let controller: ChatController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let limit = controller.contextLimit {
                let used = controller.contextUsed ?? 0
                ProgressView(value: min(1, Double(used) / Double(limit))) {
                    Text("\(ContextMeter.tokens(used)) of \(ContextMeter.tokens(limit)) tokens")
                        .font(.caption).monospacedDigit()
                }
                .tint(Double(used) / Double(limit) > 0.7 ? .orange : .accentColor)
                Text("The conversation is summarized automatically at 70% (after leaving room for the reply). "
                     + "Type /compact to summarize now; add words after it to say what to keep.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This endpoint doesn't report a context length. Set one in Settings → Endpoints.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Compact Now") { controller.compactNow() }
                .disabled(controller.isGenerating || controller.session.messages.isEmpty)

            if !controller.session.compactions.isEmpty {
                Divider()
                Text("Summaries").font(.headline)
                ForEach(Array(controller.session.compactions.enumerated().reversed()), id: \.offset) { _, c in
                    CompactionDetail(compaction: c)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactionDetail: View {
    let compaction: Compaction
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(compaction.summary).font(.caption).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("\(compaction.date.formatted(date: .omitted, time: .shortened)): "
                 + "\(ContextMeter.tokens(compaction.tokensBefore)) → \(ContextMeter.tokens(compaction.tokensAfter)) tokens")
                .font(.callout).monospacedDigit()
        }
    }
}

/// Marks where the conversation was summarized. Everything above it is out of the model's context.
struct CompactionDivider: View {
    let compaction: Compaction
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack { Divider() }
                Button { expanded.toggle() } label: {
                    Label("Earlier conversation summarized (\(ContextMeter.tokens(compaction.tokensBefore)) → "
                          + "\(ContextMeter.tokens(compaction.tokensAfter)) tokens)", systemImage: "rectangle.compress.vertical")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                VStack { Divider() }
            }
            if expanded {
                MarkdownView(markdown: compaction.summary)
                    .padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .help("The model no longer sees the messages above; it has this summary instead.")
    }
}

/// The project's git state: branch, changed files with their diffs, staging, discarding, and committing.
/// Refreshes when shown and after each agent run.
struct GitPane: View {
    let repo: GitRepo
    let isGenerating: Bool
    let controller: ChatController
    @State private var status: GitRepo.Status?
    @State private var branches: [GitRepo.Branch] = []
    @State private var stashes: [GitRepo.Stash] = []
    @State private var newBranch: String?
    /// In a worktree: the main checkout, and the branch it's on.
    @State private var mainRepo: GitRepo?
    @State private var mainBranch: String?
    @State private var dropping: GitRepo.Stash?
    @State private var remote: String?
    @State private var defaultBranch: String?
    @State private var writingMessage = false
    @State private var showStashes = false
    @State private var lastCommit: String?
    @State private var open: String?
    @State private var diffs: [String: String] = [:]
    @State private var message = ""
    @State private var error: String?
    @State private var busy = false
    @State private var discarding: GitRepo.FileChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !repo.exists {
                Text("This project isn't a git repository.").font(.callout).foregroundStyle(.secondary)
            } else if let status {
                header(status)
                let staged = status.files.filter(\.isStaged)
                let unstaged = status.files.filter { $0.isUnstaged || $0.isConflicted }
                let untracked = status.files.filter(\.isUntracked)
                if status.files.isEmpty {
                    Text("No changes.").font(.callout).foregroundStyle(.secondary)
                }
                group("Staged", staged, status)
                group("Changes", unstaged, status)
                group("Untracked", untracked, status)
                commitBox(status, stagedCount: staged.count)
                actions(status)
                stashBox(status)
            } else {
                ProgressView().controlSize(.small)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: repo.root) { await refresh() }
        .onChange(of: isGenerating) { if !isGenerating { Task { await refresh() } } }
        .alert("New Branch", isPresented: Binding(get: { newBranch != nil }, set: { if !$0 { newBranch = nil } })) {
            TextField("Name", text: Binding(get: { newBranch ?? "" }, set: { newBranch = $0 }))
            Button("Create") {
                if let name = newBranch { act { try await repo.createBranch(name.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                newBranch = nil
            }
            Button("Cancel", role: .cancel) { newBranch = nil }
        } message: { Text("Starts from what's checked out, and keeps your uncommitted changes.") }
        .confirmationDialog("Discard changes to \(discarding?.path ?? "")?",
                            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
            Button(discarding?.isUntracked == true ? "Delete File" : "Discard Changes", role: .destructive) {
                if let f = discarding { act { try await repo.discard(f) } }
            }
        } message: {
            Text(discarding?.isUntracked == true
                 ? "The file isn't tracked by git, so it's deleted. This can't be undone."
                 : "The file goes back to its last committed version. This can't be undone.")
        }
    }

    private func header(_ s: GitRepo.Status) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Menu(s.branch ?? "detached HEAD") {
                    ForEach(branches.filter { !$0.isCurrent }) { b in
                        Button(b.name) { act { try await repo.switchBranch(b.name) } }
                    }
                    if !branches.isEmpty { Divider() }
                    Button("New Branch…") { newBranch = "" }
                }
                .menuStyle(.borderlessButton).fixedSize().fontWeight(.medium)
                .disabled(isGenerating)
                .help(isGenerating ? Self.whileRunning : "Switch branch, or start a new one")
                if s.ahead > 0 { Text("↑\(s.ahead)").foregroundStyle(.secondary).help("\(s.ahead) commits not pushed") }
                if s.behind > 0 { Text("↓\(s.behind)").foregroundStyle(.secondary).help("\(s.behind) commits to pull") }
                Spacer()
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
            }
            if let lastCommit {
                Text(lastCommit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if s.isNewRepository {
                Text("No commits yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ files: [GitRepo.FileChange], _ s: GitRepo.Status) -> some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(title) (\(files.count))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if title == "Staged" {
                        Button("Unstage All") { act { try await repo.unstage(files.map(\.path), isNewRepository: s.isNewRepository) } }
                            .buttonStyle(.borderless).font(.caption)
                            .disabled(isGenerating).help(isGenerating ? Self.whileRunning : "")
                    } else {
                        Button("Stage All") { act { try await repo.stage(files.map(\.path)) } }
                            .buttonStyle(.borderless).font(.caption)
                            .disabled(isGenerating).help(isGenerating ? Self.whileRunning : "")
                    }
                }
                ForEach(files, id: \.id) { f in row(f, staged: title == "Staged", s) }
            }
        }
    }

    private func row(_ f: GitRepo.FileChange, staged: Bool, _ s: GitRepo.Status) -> some View {
        let key = (staged ? "S:" : "W:") + f.path
        let toggle = { act { staged ? try await repo.unstage([f.path], isNewRepository: s.isNewRepository) : try await repo.stage([f.path]) } }
        // The stage button sits beside the disclosure, not in its label: inside the label, accessibility (VoiceOver,
        // automation) reached only the disclosure triangle, so a single file couldn't be staged that way.
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            DisclosureGroup(isExpanded: Binding(get: { open == key }, set: { expanded in
                open = expanded ? key : nil
                if expanded { Task { await loadDiff(f, key: key, s) } }
            })) {
                if let d = diffs[key] {
                    if d.isEmpty { Text("No text changes.").font(.caption).foregroundStyle(.secondary) }
                    else { DiffView(diff: d, maxHeight: 260) }
                } else {
                    ProgressView().controlSize(.small)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(f.kind).font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(color(f).opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(color(f))
                    Text(f.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                        .help(f.originalPath.map { "\($0) → \(f.path)" } ?? f.path)
                    Spacer(minLength: 4)
                }
                .contextMenu {
                    Button(staged ? "Unstage" : "Stage") { toggle() }.disabled(isGenerating)
                    Button(f.isUntracked ? "Delete File…" : "Discard Changes…", role: .destructive) { discarding = f }
                        .disabled(isGenerating)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([repo.root.appending(path: f.path)])
                    }
                }
            }
            // The context menu's Discard, for VoiceOver and automation too (a context menu isn't reachable there).
            .accessibilityAction(named: Text(f.isUntracked ? "Delete File…" : "Discard Changes…")) {
                if isGenerating { error = Self.whileRunning } else { discarding = f }
            }
            Button { toggle() } label: { Image(systemName: staged ? "minus.circle" : "plus.circle") }
                .buttonStyle(.borderless)
                .disabled(isGenerating)
                .help(isGenerating ? Self.whileRunning : staged ? "Unstage" : "Stage")
                .accessibilityLabel((staged ? "Unstage " : "Stage ") + f.path)
        }
    }

    private func commitBox(_ s: GitRepo.Status, stagedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            TextField("Commit message", text: $message, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Commit \(stagedCount) File\(stagedCount == 1 ? "" : "s")") {
                    let text = message
                    act {
                        let made = try await repo.commit(message: text)
                        message = ""
                        lastCommit = made
                    }
                }
                .disabled(stagedCount == 0 || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || isGenerating)
                .help(isGenerating ? Self.whileRunning : "")
                Button("Write Message") { writeMessage() }
                    .disabled(stagedCount == 0 || writingMessage || busy)
                    .help("Have \(controller.session.model.split(separator: "/").last.map(String.init) ?? controller.session.model) write it from the staged change: one short request, in the session's spending")
                if busy || writingMessage { ProgressView().controlSize(.small) }
            }
        }
    }

    private func writeMessage() {
        writingMessage = true
        error = nil
        Task {
            do {
                let diff = try await repo.stagedDiff()
                if let text = await controller.writeCommitMessage(diff: diff) { message = text }
                else { error = "The model didn't write a message." }
            } catch { self.error = error.localizedDescription }
            writingMessage = false
        }
    }

    /// Sharing the branch: push and pull, its pull request's page, and merging a worktree's work back.
    @ViewBuilder private func actions(_ s: GitRepo.Status) -> some View {
        HStack(spacing: 8) {
            if remote != nil, s.branch != nil {
                Button(s.upstream == nil ? "Publish Branch" : "Push") { act(touchesTree: false) { try await repo.push(s) } }
                    .disabled(busy || (s.upstream != nil && s.ahead == 0))
                    .help("git push: this sends the branch to origin")
                if s.upstream != nil {
                    Button("Pull") { act { try await repo.pull() } }
                        .disabled(busy || s.behind == 0 || isGenerating)
                        .help(isGenerating ? Self.whileRunning : "git pull --ff-only")
                }
                if s.upstream != nil, let remote, let branch = s.branch, branch != defaultBranch,
                   let url = GitRepo.compareURL(remote: remote, branch: branch, base: defaultBranch) {
                    Link("Pull Request", destination: url).help("Opens the page that starts one")
                }
            }
            if let mainRepo, let mainBranch, let branch = s.branch {
                Button("Merge into \(mainBranch)") { act { try await mainRepo.merge(branch, into: mainBranch) } }
                    .disabled(busy || !s.files.isEmpty || isGenerating)
                    .help(isGenerating ? Self.whileRunning
                          : s.files.isEmpty ? "git merge in the main checkout; if it can't be done cleanly, nothing changes"
                                          : "Commit first: uncommitted files aren't part of a merge")
            }
        }
        .font(.callout)
    }

    @ViewBuilder private func stashBox(_ s: GitRepo.Status) -> some View {
        DisclosureGroup("Stashes (\(stashes.count))", isExpanded: $showStashes) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Stash Changes") { act { try await repo.stash() } }
                    .disabled(s.files.isEmpty || busy || isGenerating)
                    .help(isGenerating ? Self.whileRunning : "Puts uncommitted changes aside, new files too")
                ForEach(stashes) { item in
                    HStack(spacing: 6) {
                        Text(item.message).font(.caption).lineLimit(1).truncationMode(.middle).help(item.ref)
                        Spacer(minLength: 4)
                        Button("Apply") { act { try await repo.stashApply(item) } }.buttonStyle(.borderless).font(.caption)
                            .disabled(isGenerating).help(isGenerating ? Self.whileRunning : "")
                        Button("Drop") { dropping = item }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .confirmationDialog("Drop this stash? Its changes go for good.",
                            isPresented: Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } }), presenting: dropping) { item in
            Button("Drop", role: .destructive) { act(touchesTree: false) { try await repo.stashDrop(item) } }
        } message: { Text($0.message) }
    }

    private func color(_ f: GitRepo.FileChange) -> Color {
        switch f.kind {
        case "new", "added": .green
        case "deleted": .red
        case "conflict": .orange
        default: .blue
        }
    }

    private func loadDiff(_ f: GitRepo.FileChange, key: String, _ s: GitRepo.Status) async {
        do { diffs[key] = try await repo.diff(f, isNewRepository: s.isNewRepository) }
        catch { diffs[key] = ""; self.error = error.localizedDescription }
    }

    private func refresh() async {
        guard repo.exists else { return }
        do {
            status = try await repo.status()
            lastCommit = try await repo.lastCommit()
            branches = try await repo.branches()
            stashes = try await repo.stashes()
            remote = await repo.remoteURL()
            defaultBranch = await repo.defaultBranch()
            if repo.isLinkedWorktree, let root = try? await repo.mainRoot() {
                let main = GitRepo(root: root)
                mainRepo = main
                mainBranch = try? await main.status().branch
            }
            diffs = [:]
            if let open, let s = status {
                let path = String(open.dropFirst(2))
                if let f = s.files.first(where: { $0.path == path }) { await loadDiff(f, key: open, s) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Runs a git action, then refreshes; git's own message shows if it fails.
    /// Why the actions that change the files, the index or HEAD are off: the agent's edits would be stashed, switched
    /// away or committed half-made, and the run's snapshots would count the change as the agent's.
    static let whileRunning = "Not while the agent is working: wait for the run to end, or stop it"

    /// Runs a git action. One that changes the working tree, the index or HEAD (`touchesTree`) is refused during a run,
    /// even from a dialog opened before it began.
    private func act(touchesTree: Bool = true, _ op: @escaping @MainActor () async throws -> Void) {
        if touchesTree, isGenerating { error = Self.whileRunning; return }
        busy = true
        error = nil
        Task {
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
            await refresh()
        }
    }
}
