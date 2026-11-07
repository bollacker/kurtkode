import Foundation

/// What a rewind takes back (GAP_ANALYSIS.md C3): the files and the conversation (the message and everything after it
/// go, and its text goes back in the composer), the files only (the conversation stays, with a note telling the model),
/// or the conversation only (the files stay as they are).
public enum RewindChoice: String, CaseIterable, Sendable {
    case both, files, conversation

    public var restoresFiles: Bool { self != .conversation }
    public var removesMessages: Bool { self != .files }
}

/// The files a rewind to a user message would restore, worked out from the runs' snapshots (C1) when every run since
/// has them, so changes made by commands are restored too; otherwise from the edit tools' checkpoints, as before.
/// Only files kurtkode's runs changed are restored; of those, files the user also changed by hand between or after the
/// runs are left alone and named.
public struct RewindPlan: Sendable {
    /// The user messages from the target on.
    public var turns: Set<UUID>
    /// Absolute paths to restore.
    public var files: [String]
    /// Absolute paths the runs changed that the user changed too: left as they are.
    public var keptUserEdits: [String]
    /// Absolute paths only the edit tools' checkpoints have (extra folders, ignored or oversized files the snapshots leave
    /// out): restored from those, as before snapshots.
    public var checkpointFiles: [String] = []
    /// The snapshot to restore from (the start of the target's first run); nil: the checkpoints.
    public var base: String?
    /// Absolute paths the runs added that were in the project before them, outside the snapshots (ignored by git then,
    /// or over a size): left as they are, since restoring would delete the user's file.
    public var keptOutside: [String] = []
    /// The session whose chain records the restore.
    public var session: UUID?
    /// Whether changes made by commands are covered (every run since has its snapshots).
    public var coversCommands: Bool { base != nil }

    public static func make(target: UUID, messages: [ChatMessage], runs: [AgentRunRecord], snapshots: ProjectSnapshots?,
                            session: UUID, checkpoints: CheckpointStore) async -> RewindPlan {
        guard let idx = messages.firstIndex(where: { $0.id == target }) else {
            return RewindPlan(turns: [], files: [], keptUserEdits: [], base: nil)
        }
        let turns = Set(messages[idx...].filter { $0.role == .user }.map(\.id))
        let mine = runs.filter { $0.agent == "main" && $0.userMessage.map(turns.contains) == true }.sorted { $0.started < $1.started }
        if let snaps = snapshots, !mine.isEmpty, mine.allSatisfy({ $0.snapshots != nil }),
           var plan = try? await fromSnapshots(snaps, turns: turns, session: session) {
            let covered = Set(plan.files + plan.keptUserEdits + plan.keptOutside)
            plan.checkpointFiles = await checkpoints.changedFiles(inTurns: turns).filter { !covered.contains($0) }
            return plan
        }
        return RewindPlan(turns: turns, files: await checkpoints.changedFiles(inTurns: turns), keptUserEdits: [], base: nil)
    }

    /// From the session's chain of snapshots, not the run records: a run that crashed or quit wrote no record, but its
    /// start snapshot is on the chain, and the base must be the first start of the rewound turns. Nil when a run's end
    /// is missing (the run crashed, or is still going), since what it changed can't be told from the user's edits.
    static func fromSnapshots(_ snaps: ProjectSnapshots, turns: Set<UUID>, session: UUID) async throws -> RewindPlan? {
        let chain = try await snaps.list(session: session)
        guard let first = chain.firstIndex(where: { $0.phase == .start && $0.turn.map(turns.contains) == true }) else { return nil }
        let tail = Array(chain[first...])
        var changed = Set<String>(), byUser = Set<String>()
        for (i, s) in tail.enumerated() {
            let next: ProjectSnapshots.Snapshot? = i + 1 < tail.count ? tail[i + 1] : nil
            switch s.phase {
            case .start:
                // A run's own changes, from its start to its end.
                guard let next, next.phase == .end, next.run == s.run else { return nil }
                for c in try await snaps.changes(session: session, from: s.commit, to: next.commit) { changed.formUnion(c.paths) }
            case .end, .restore:
                // From a run's end (or kurtkode's own restore) to the next snapshot, or now: the user's doing, except
                // when the next one is kurtkode's restore (a rewind of files, a revert in the Changes tab).
                if next?.phase == .restore { continue }
                for c in try await snaps.changes(session: session, from: s.commit, to: next?.commit) { byUser.formUnion(c.paths) }
            }
        }
        let base = tail[0].commit
        let files = changed.subtracting(byUser)
        let outside = Set(try await snaps.heldOutside(Array(files), at: base, session: session))
        let root = snaps.project.path
        func abs(_ rel: String) -> String { root + "/" + rel }
        return RewindPlan(turns: turns, files: files.subtracting(outside).sorted().map(abs),
                          keptUserEdits: changed.intersection(byUser).sorted().map(abs), base: base,
                          keptOutside: outside.sorted().map(abs), session: session)
    }

    /// Restores the files; the checkpoints of the rewound turns are forgotten either way (their snapshots in the session
    /// file stay, harmless).
    public func restoreFiles(snapshots: ProjectSnapshots?, checkpoints: CheckpointStore) async throws -> [CheckpointStore.Restored] {
        guard let base, let snaps = snapshots else { return try await checkpoints.restore(turns: turns) }
        let rel = files.map { $0.hasPrefix(snaps.project.path + "/") ? String($0.dropFirst(snaps.project.path.count + 1)) : $0 }
        var restored = try await snaps.restore(rel, to: base, session: session)
        restored += try await checkpoints.restore(turns: turns, only: Set(checkpointFiles))      // forgets the turns too
        return restored
    }

    /// The confirmation's text: what goes, what's restored, what's kept.
    public func summary(_ choice: RewindChoice, root: String?) -> String {
        func names(_ paths: [String]) -> String {
            let shown = paths.prefix(8).map { p in root.map { p.hasPrefix($0 + "/") ? String(p.dropFirst($0.count + 1)) : p } ?? p }
            return shown.joined(separator: ", ") + (paths.count > 8 ? ", …" : "")
        }
        var s = choice.removesMessages ? "This message and everything after it will be removed, and its text put back in the composer."
            : "The conversation stays as it is; the model is told the files were restored."
        if choice.restoresFiles {
            let all = files + checkpointFiles
            s += all.isEmpty ? " No files were changed since then." : " These files will be restored: \(names(all))."
            if !keptUserEdits.isEmpty { s += " Left as they are, because you changed them too: \(names(keptUserEdits))." }
            if !keptOutside.isEmpty { s += " Left as they are, because they were there before, outside the snapshots (ignored by git then): \(names(keptOutside))." }
            if !coversCommands { s += " Changes made by commands can't be undone (no snapshots for these turns)." }
        } else {
            s += " Files stay as they are."
        }
        return s
    }

    /// The note the model gets after a files-only rewind.
    public func note(request: String, root: String?) -> String {
        let shown = (files + checkpointFiles).map { p in root.map { p.hasPrefix($0 + "/") ? String(p.dropFirst($0.count + 1)) : p } ?? p }
        let line = request.split(separator: "\n").first.map { $0.count > 80 ? $0.prefix(80) + "…" : String($0) } ?? ""
        return "[kurtkode: the user restored these files to how they were before the request \"\(line)\", undoing the changes "
            + "made since then: \(shown.joined(separator: ", ")). The conversation above still describes those changes; read the "
            + "files again before relying on their contents.]"
    }
}

/// One row of the checkpoint list (`/rewind`, the Changes tab): a user message that started runs.
public struct RewindPoint: Sendable, Hashable {
    /// 1 for the session's first request.
    public var number: Int
    public var message: UUID
    public var date: Date?
    /// The request's first line.
    public var text: String
    /// Files its runs changed (from their snapshots); nil without them.
    public var files: Int?

    /// The session's requests, oldest first, with how many files their runs changed.
    public static func list(messages: [ChatMessage], runs: [AgentRunRecord], snapshots: ProjectSnapshots?,
                            session: UUID) async -> [RewindPoint] {
        var out: [RewindPoint] = []
        for m in messages where m.role == .user && m.contextNote != true {
            let mine = runs.filter { $0.agent == "main" && $0.userMessage == m.id }
            var files: Int?
            if let snaps = snapshots, !mine.isEmpty, mine.allSatisfy({ $0.snapshots != nil }) {
                var set = Set<String>()
                for r in mine { if let s = r.snapshots, let c = try? await snaps.changes(session: session, from: s.start, to: s.end) { c.forEach { set.formUnion($0.paths) } } }
                files = set.count
            }
            let line = m.content.split(separator: "\n").first.map(String.init) ?? ""
            out.append(RewindPoint(number: out.count + 1, message: m.id, date: mine.map(\.started).min(),
                                   text: line.count > 70 ? String(line.prefix(70)) + "…" : line, files: files))
        }
        return out
    }
}
