import AgentCore
import SwiftUI

/// The net change of the latest run, a turn or the whole session, from the project's snapshots (C1): every file that
/// changed, however it changed (commands included), with its diff, a revert for the file and for each hunk.
/// Falls back to the files the edit tools changed when the session has no snapshots.
struct TaskChangesPane: View {
    let controller: ChatController
    /// What the list is measured against: the session's snapshots, or the repository.
    private enum Basis: Hashable {
        case snapshots(ProjectSnapshots.Scope)
        case git(GitRepo.DiffBase)
    }
    @State private var basis = Basis.snapshots(.lastRun)
    /// The branch to compare with, when this isn't it.
    @State private var baseBranch: String?
    @Environment(AppModel.self) private var app
    @State private var scope = ProjectSnapshots.Scope.lastRun
    @State private var range: (from: ProjectSnapshots.Snapshot, to: ProjectSnapshots.Snapshot?)?
    @State private var turns: [(id: UUID, label: String)] = []
    @State private var changes: [ProjectSnapshots.Change]?
    @State private var patches: [String: String] = [:]
    /// Files the user changed since the run's end: their hunks aren't the ones shown, so only the whole file reverts.
    @State private var changedSince: Set<String> = []
    @State private var open: String?
    @State private var error: String?
    @State private var busy = false
    @State private var reverting: ProjectSnapshots.Change?
    @State private var points: [RewindPoint] = []
    @State private var showPoints = false
    /// The latest refresh: an older one that finishes later doesn't overwrite it (a scope's label over another's files).
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snaps = controller.snapshots {
                content(snaps)
            } else {
                ChangesPane(files: controller.changedFiles, root: controller.workspace?.root.path)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: controller.session.header.id) {
            baseBranch = await otherBranch()
            #if DEBUG
            // KURTKODE_CHANGES_BASE=uncommitted|branch: start on that (a pop-up can't be pressed from outside);
            // KURTKODE_REVIEW_COMMENT=path|line|text: a comment, as hovering a line and adding one does.
            let env = ProcessInfo.processInfo.environment
            if env["KURTKODE_CHANGES_BASE"] == "uncommitted" { basis = .git(.uncommitted) }
            if env["KURTKODE_CHANGES_BASE"] == "branch", let baseBranch { basis = .git(.branch(baseBranch)) }
            if let spec = env["KURTKODE_REVIEW_COMMENT"], controller.reviewComments.isEmpty {
                let f = spec.split(separator: "|", maxSplits: 2).map(String.init)
                if f.count == 3 { controller.reviewComments = [ReviewComment(path: f[0], line: Int(f[1]), quote: "+quoted line", text: f[2])] }
            }
            #endif
            await refresh()
        }
        .onChange(of: controller.isGenerating) { if !controller.isGenerating { Task { await refresh() } } }
        .onChange(of: basis) {
            if case .snapshots(let s) = basis { scope = s }
            Task { await refresh() }
        }
        .confirmationDialog("Revert \(reverting?.path ?? "")?", isPresented: Binding(get: { reverting != nil }, set: { if !$0 { reverting = nil } })) {
            Button(reverting?.kind == .added ? "Delete File" : "Revert File", role: .destructive) {
                if let c = reverting, let from = range?.from {
                    let session = controller.session.header.id
                    act { _ = try await controller.snapshots?.restore(c.paths, to: from.commit, session: session) }
                }
            }
        } message: {
            Text(reverting?.kind == .added
                 ? "It wasn't in the snapshot from before, so it's deleted."
                 : "The file goes back to how it was before \(scopeName). Changes made to it since are lost too.")
        }
    }

    private var scopeName: String {
        switch scope {
        case .lastRun: "the latest run"
        case .session: "this session"
        case .turn: "that turn"
        }
    }

    @ViewBuilder private func content(_ snaps: ProjectSnapshots) -> some View {
        HStack {
            Picker("", selection: $basis) {
                Text("Latest run").tag(Basis.snapshots(.lastRun))
                Text("Session").tag(Basis.snapshots(.session))
                if repo != nil {
                    Divider()
                    Text("Uncommitted").tag(Basis.git(.uncommitted))
                    if let baseBranch { Text("Branch vs \(baseBranch)").tag(Basis.git(.branch(baseBranch))) }
                }
                if !turns.isEmpty {
                    Divider()
                    ForEach(turns, id: \.id) { t in Text(t.label).tag(Basis.snapshots(.turn(t.id))) }
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            if busy || controller.reviewing { ProgressView().controlSize(.small) }
            Button("Review") { controller.startReview(scope) }
                .buttonStyle(.borderless)
                .disabled(controller.reviewing || controller.isGenerating || changes?.isEmpty != false || usingGit)
                .help("Have another vendor's model from the pool review this change")
            Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh")
        }
        if let r = controller.review { reviewBox(r) }
        if !controller.reviewComments.isEmpty { commentsBar }
        if let changes {
            if !usingGit, range == nil {
                Text("No snapshots yet: they're taken when a run starts and ends.").font(.callout).foregroundStyle(.secondary)
            } else if changes.isEmpty {
                Text("No files changed\(!usingGit && range?.to == nil ? " so far" : "").").font(.callout).foregroundStyle(.secondary)
            } else {
                let add = changes.compactMap(\.additions).reduce(0, +), del = changes.compactMap(\.deletions).reduce(0, +)
                Text("\(changes.count) file\(changes.count == 1 ? "" : "s") changed, +\(add) −\(del)"
                     + (!usingGit && range?.to == nil ? ", up to now" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(changes) { row($0, snaps) }
            }
            if !usingGit, let skipped = (range?.to ?? range?.from)?.skipped, !skipped.isEmpty {
                Text("Not captured (too large): " + skipped.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3).help(skipped.joined(separator: "\n"))
            }
        } else {
            ProgressView().controlSize(.small)
        }
        if !points.isEmpty { checkpoints }
    }

    /// The comments waiting to go, and the button that sends them.
    private var commentsBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
            Text("\(controller.reviewComments.count) comment\(controller.reviewComments.count == 1 ? "" : "s")").font(.callout)
            Spacer()
            Button("Clear") { controller.reviewComments = [] }.buttonStyle(.borderless)
            Button("Send") { controller.sendReviewComments() }
                .help("Send them to \(controller.session.model) as one message; during a run it's queued for the next step")
        }
        .padding(8)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var usingGit: Bool { if case .git = basis { true } else { false } }

    private var repo: GitRepo? {
        guard let root = controller.workspace?.root else { return nil }
        let r = GitRepo(root: root)
        return r.exists ? r : nil
    }

    /// The repository's default branch, unless that's what's checked out.
    private func otherBranch() async -> String? {
        guard let repo, let name = await repo.defaultBranch() else { return nil }
        return (try? await repo.status().branch) == name ? nil : name
    }

    /// The latest review: its verdict, findings, and a button that hands them to the session's model.
    private func reviewBox(_ r: CodeReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: r.verdict == .looksRight ? "checkmark.seal" : r.verdict == nil ? "questionmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(r.verdict == .looksRight ? .green : r.verdict == nil ? .secondary : .orange)
                Text(r.verdict.map { "Review: \($0.label)" } ?? "Review: no verdict").fontWeight(.medium)
                Spacer()
                Text(r.reviewer.split(separator: "/").last.map(String.init) ?? r.reviewer).font(.caption).foregroundStyle(.secondary)
                Button { controller.review = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Dismiss")
            }
            if let s = r.summary, !s.isEmpty { Text(s).font(.callout) }
            if r.verdict == nil { Text(r.problem ?? "").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(r.findings.enumerated()), id: \.offset) { _, f in
                Text("• " + f.line1).font(.caption).textSelection(.enabled)
            }
            if !r.findings.isEmpty {
                Button("Fix These") { controller.fixReviewFindings() }
                    .disabled(controller.isGenerating)
                    .help("Send the findings to \(controller.session.model) to check and fix")
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Each request, with the files its runs changed and a rewind to just before it (C3).
    private var checkpoints: some View {
        DisclosureGroup("Checkpoints (\(points.count))", isExpanded: $showPoints) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points.reversed(), id: \.message) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(p.number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.text.isEmpty ? "(no text)" : p.text).font(.callout).lineLimit(1).truncationMode(.tail)
                            Text([p.date.map { $0.formatted(date: .omitted, time: .shortened) },
                                  p.files.map { "\($0) file\($0 == 1 ? "" : "s") changed" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("Rewind…") { controller.rewindRequest = p.message }
                            .buttonStyle(.borderless).font(.caption)
                            .disabled(controller.isGenerating)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .padding(.top, 6)
    }

    private func row(_ c: ProjectSnapshots.Change, _ snaps: ProjectSnapshots) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            DisclosureGroup(isExpanded: Binding(get: { open == c.path }, set: { expanded in
                open = expanded ? c.path : nil
                if expanded { Task { await loadPatch(c) } }
            })) {
                if let p = patches[c.path] { hunks(c, p) } else { ProgressView().controlSize(.small) }
            } label: {
                HStack(spacing: 6) {
                    Text(c.kind.rawValue).font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(color(c).opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(color(c))
                    Text(c.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                        .help(c.oldPath.map { "\($0) → \(c.path)" } ?? c.path)
                    Spacer(minLength: 4)
                    Text(c.additions.map { "+\($0) −\(c.deletions ?? 0)" } ?? "binary")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .contextMenu {
                    if !usingGit { Button(c.kind == .added ? "Delete File…" : "Revert File…", role: .destructive) { reverting = c } }
                    if c.kind != .deleted {
                        Button("Open") { app.openInEditor(snaps.project.appending(path: c.path)) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([snaps.project.appending(path: c.path)]) }
                    }
                }
            }
            .accessibilityActions {
                if !usingGit { Button(c.kind == .added ? "Delete File…" : "Revert File…") { reverting = c } }
            }
            if !usingGit {
                Button { reverting = c } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .disabled(controller.isGenerating)
                    .help(c.kind == .added ? "Delete the new file" : "Revert the file")
                    .accessibilityLabel("Revert " + c.path)
            }
        }
    }

    @ViewBuilder private func hunks(_ c: ProjectSnapshots.Change, _ patch: String) -> some View {
        let parts = UnifiedDiff.split(patch).hunks
        if parts.isEmpty {
            Text(c.additions == nil ? "Binary file." : "No text changes.").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !usingGit, changedSince.contains(c.path) {
                    Text("Changed again since then: revert the whole file, or look at it in the Session view.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(parts.enumerated()), id: \.offset) { i, lines in
                    VStack(alignment: .trailing, spacing: 2) {
                        if !usingGit, parts.count > 1, !changedSince.contains(c.path), c.kind == .modified {
                            Button("Revert This Part") { revertHunk(c, lines) }
                                .buttonStyle(.borderless).font(.caption)
                                .disabled(controller.isGenerating || busy)
                        }
                        ReviewHunk(controller: controller, path: c.path, lines: lines, maxHeight: 220) { line in
                            if let root = controller.workspace?.root { app.openInEditor(root.appending(path: c.path), line: line) }
                        }
                    }
                }
            }
        }
    }

    private func color(_ c: ProjectSnapshots.Change) -> Color {
        switch c.kind {
        case .added: .green
        case .deleted: .red
        case .renamed: .purple
        default: .blue
        }
    }

    private func revertHunk(_ c: ProjectSnapshots.Change, _ lines: [Substring]) {
        guard let from = range?.from, let snaps = controller.snapshots else { return }
        let session = controller.session.header.id
        act { try await snaps.revertHunk(session: session, from: from.commit, change: c, hunk: lines) }
    }

    private func loadPatch(_ c: ProjectSnapshots.Change) async {
        let mine = generation
        if case .git(let base) = basis {
            guard let repo else { return }
            do {
                let p = try await repo.patch(base, change: c)
                if mine == generation { patches[c.path] = p }
            } catch { patches[c.path] = ""; self.error = error.localizedDescription }
            return
        }
        guard let snaps = controller.snapshots, let range else { return }
        do {
            let p = try await snaps.patch(session: controller.session.header.id, from: range.from.commit, to: range.to?.commit, change: c)
            if mine == generation { patches[c.path] = p }
        } catch { patches[c.path] = ""; self.error = error.localizedDescription }
    }

    private func refresh() async {
        generation += 1
        let mine = generation
        if case .git(let base) = basis {
            guard let repo else { return }
            do {
                let found = try await repo.changes(base)
                guard mine == generation else { return }
                patches = [:]
                changes = found
                changedSince = []
                error = nil
                if let open, let c = found.first(where: { $0.path == open }) { await loadPatch(c) }
            } catch {
                changes = []
                self.error = error.localizedDescription
            }
            return
        }
        guard let snaps = controller.snapshots else { return }
        let session = controller.session.header.id
        do {
            let list = try await snaps.list(session: session)
            let newPoints = await RewindPoint.list(messages: controller.session.messages, runs: controller.session.runs,
                                                   snapshots: snaps, session: session)
            let newRange = ProjectSnapshots.range(list, scope)
            var found: [ProjectSnapshots.Change] = []
            var since = Set<String>()
            if let r = newRange {
                found = try await snaps.changes(session: session, from: r.from.commit, to: r.to?.commit)
                if let end = r.to { for c in found where !(try await snaps.unchanged(c.path, since: end.commit)) { since.insert(c.path) } }
            }
            guard mine == generation else { return }
            turns = Self.turns(list, messages: controller.session.messages)
            points = newPoints
            range = newRange
            patches = [:]
            guard range != nil else { changes = []; return }
            changes = found
            changedSince = since
            error = nil
            if let open, let c = found.first(where: { $0.path == open }) { await loadPatch(c) }
        } catch {
            changes = []
            self.error = error.localizedDescription
        }
    }

    /// The session's turns that have snapshots, newest first, labeled by their request.
    static func turns(_ list: [ProjectSnapshots.Snapshot], messages: [ChatMessage]) -> [(id: UUID, label: String)] {
        var seen = Set<UUID>(), out: [(UUID, String)] = []
        for s in list.reversed() where s.phase == .start {
            guard let t = s.turn, seen.insert(t).inserted, let m = messages.first(where: { $0.id == t }) else { continue }
            let text = m.content.split(separator: "\n").first.map(String.init) ?? ""
            out.append((t, "Turn: " + (text.count > 40 ? text.prefix(40) + "…" : text)))
        }
        return out
    }

    /// Runs a revert, then refreshes; the failure's message shows.
    private func act(_ op: @escaping @MainActor () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
            await refresh()
        }
    }
}

/// A hunk of a change you can comment on: hover a line for a button that opens a comment under it, and another that opens
/// the file there. Comments wait in the controller until they're sent together.
struct ReviewHunk: View {
    let controller: ChatController
    let path: String
    let lines: [Substring]
    var maxHeight: CGFloat = 260
    let open: (Int?) -> Void
    @State private var hovered: Int?
    @State private var writing: Int?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shown = lines.filter { !$0.hasPrefix("--- ") && !$0.hasPrefix("+++ ") }.prefix(DiffView.maxLines)
        let numbers = UnifiedDiff.newLineNumbers(Array(shown))
        CodeScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, line in
                    row(i, line, number: numbers[i])
                    ForEach(comments(line, number: numbers[i])) { c in
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble").foregroundStyle(.secondary)
                            Text(c.text).font(.caption).fixedSize()
                            Button { controller.reviewComments.removeAll { $0.id == c.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.borderless).help("Remove this comment")
                        }
                        .padding(.horizontal, 26).padding(.vertical, 3)
                    }
                    if writing == i { editor(line, number: numbers[i]) }
                }
            }
            .padding(.vertical, 6)
        }
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func comments(_ line: Substring, number: Int?) -> [ReviewComment] {
        controller.reviewComments.filter { $0.path == path && $0.line == number && $0.quote == String(line) }
    }

    private func row(_ i: Int, _ line: Substring, number: Int?) -> some View {
        HStack(spacing: 4) {
            // The buttons keep their room, so the text doesn't move under the pointer.
            Group {
                if hovered == i, !line.hasPrefix("@@") {
                    Button { writing = i; text = ""; focused = true } label: { Image(systemName: "plus.bubble") }
                        .buttonStyle(.borderless).help("Comment on this line")
                        .accessibilityLabel("Comment on this line")
                } else { Color.clear }
            }
            .frame(width: 16)
            Text(line.isEmpty ? " " : String(line))
                .font(.caption.monospaced())
                .foregroundStyle(line.hasPrefix("@@") ? Color.blue : .primary)
                .fixedSize()
                .textSelection(.enabled)
            if hovered == i, let number {
                Button { open(number) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).help("Open at line \(number)")
                    .accessibilityLabel("Open at line \(number)")
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.hasPrefix("+") ? Color.green.opacity(0.15) : line.hasPrefix("-") ? Color.red.opacity(0.13) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
    }

    private func editor(_ line: Substring, number: Int?) -> some View {
        HStack(spacing: 6) {
            TextField("Comment for the model", text: $text)
                .textFieldStyle(.roundedBorder).font(.caption)
                .focused($focused)
                .frame(width: 260)
                .onSubmit { save(line, number: number) }
                .onExitCommand { writing = nil }
            Button("Add") { save(line, number: number) }.font(.caption)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 26).padding(.vertical, 4)
    }

    private func save(_ line: Substring, number: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        controller.reviewComments.append(ReviewComment(path: path, line: number, quote: String(line), text: trimmed))
        writing = nil
    }
}
