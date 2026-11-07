import CryptoKit
import Foundation

/// Snapshots of a project's files at the start and end of every main run (GAP_ANALYSIS.md C1, C3), taken with git
/// without touching the project's own repository: a shadow repository per project (its own objects, refs and one index
/// per session) with the project folder as its work tree. Unlike `CheckpointStore` (edit tools only), they catch what
/// commands change. Each snapshot is a commit on one chain per session, `refs/sessions/<session id>`, whose message
/// names the turn, the run and the phase.
///
/// What goes in: in a git project, its tracked files and the untracked ones it doesn't ignore, except untracked folders
/// over a size (build output nobody ignored, data) and files over a size; in a folder that isn't a repository, its
/// files minus the usual dependency and build folders, and nothing at all past a size.
public struct ProjectSnapshots: Sendable {
    public let project: URL
    public let gitDir: URL
    public var limits = Limits()

    public struct Limits: Sendable, Hashable {
        /// An untracked folder of a git project with more files or bytes than this isn't captured.
        public var untrackedFolderFiles = 200
        public var untrackedFolderBytes = 20_000_000
        /// An untracked file (or any file of a folder that isn't a repository) bigger than this isn't captured.
        public var fileBytes = 5_000_000
        /// A tracked file bigger than this isn't captured.
        public var trackedFileBytes = 50_000_000
        /// A folder that isn't a git repository with more than this (after the excludes) gets no snapshots.
        public var folderFiles = 10_000
        public var folderBytes = 200_000_000

        public init() {}
    }

    /// Folders never captured in a folder that isn't a git repository (a git project says what it ignores itself).
    public static let defaultExcludes: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".venv", "venv", "__pycache__", ".build", "build", "DerivedData", "dist",
        "target", ".gradle", ".next", ".cache", ".tox", ".mypy_cache", ".pytest_cache", "Pods", ".idea", ".DS_Store",
    ]

    public struct Snapshot: Sendable, Hashable {
        /// A run's start or end, or kurtkode's own restore of files (a rewind, a revert in the Changes tab), so a later
        /// rewind doesn't take that change for the user's hand edit.
        public enum Phase: String, Sendable { case start, end, restore }
        public var commit: String
        public var tree: String
        public var session: UUID
        /// The user message the run answers.
        public var turn: UUID?
        public var run: UUID?
        public var phase: Phase
        public var date: Date
        /// What wasn't captured: folders and files over the limits ("data/ (3,120 files)").
        public var skipped: [String]
    }

    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// `root/<folder name>-<hash of its path>.git`.
    public init(project: URL, root: URL) {
        // Links resolved, so the app and the command line reaching one folder by two paths share its repository.
        let path = project.resolvingSymlinksInPath().standardizedFileURL.path
        self.project = URL(fileURLWithPath: path, isDirectory: true)
        let hash = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        gitDir = root.appending(path: "\(self.project.lastPathComponent)-\(hash).git")
    }

    /// Whether a folder may get snapshots at all: not the disk's root, /Users, the home folder or its big standard folders.
    public static func allowed(_ folder: URL) -> Bool {
        let p = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
        let refused = ["/", "/Users", home] + ["Documents", "Desktop", "Downloads", "Library", "Pictures", "Movies", "Music"].map { home + "/" + $0 }
        return !refused.contains(p)
    }

    // MARK: Taking

    /// Records the project's files as they are now on the session's chain.
    @discardableResult
    public func take(session: UUID, turn: UUID?, run: UUID?, phase: Snapshot.Phase, now: Date = Date()) async throws -> Snapshot {
        let (tree, skipped) = try await currentTree(session: session)
        let ref = Self.ref(session)
        let parent = try await shadow(["rev-parse", "-q", "--verify", ref], okStatuses: [0, 1]).trimmed
        var message = "kurtkode snapshot\n\nsession: \(session.uuidString)\nphase: \(phase.rawValue)\n"
        if let turn { message += "turn: \(turn.uuidString)\n" }
        if let run { message += "run: \(run.uuidString)\n" }
        if !skipped.isEmpty { message += "skipped: " + skipped.joined(separator: "\u{1F}") + "\n" }
        let stamp = "\(Int(now.timeIntervalSince1970)) +0000"
        let commit = try await shadow(["commit-tree", tree] + (parent.isEmpty ? [] : ["-p", parent]) + ["-F", "-"],
                                      input: Data(message.utf8),
                                      environment: ["GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp]).trimmed
        _ = try await shadow(["update-ref", ref, commit] + (parent.isEmpty ? [] : [parent]))
        return Snapshot(commit: commit, tree: tree, session: session, turn: turn, run: run, phase: phase, date: now, skipped: skipped)
    }

    /// The tree of the project's files as they are now (stored, not committed), and what wasn't captured.
    public func currentTree(session: UUID) async throws -> (tree: String, skipped: [String]) {
        try await ensureRepository()
        let (files, skipped) = try await capturedFiles(session: session)
        let index = ["GIT_INDEX_FILE": gitDir.appending(path: "index-\(session.uuidString)").path]
        let before = Set(try await shadow(["ls-files", "-z"], environment: index).nulSeparated)
        // Stat information first, so only files that changed are read again.
        _ = try await shadow(["update-index", "-q", "--refresh"], okStatuses: [0, 1], environment: index)
        let changed = Set(try await shadow(["diff-files", "--name-only", "-z"], environment: index).nulSeparated)
        let now = Set(files)
        let update = now.subtracting(before).union(changed.intersection(now))
        let remove = before.subtracting(now)
        // Removals first, and --replace: a file that became a folder (or the reverse) otherwise "appears as both" and every
        // later snapshot of the session failed.
        if !remove.isEmpty {
            _ = try await shadow(["update-index", "--force-remove", "-z", "--stdin"], input: Self.nulJoined(remove), environment: index)
        }
        if !update.isEmpty {
            _ = try await shadow(["update-index", "--add", "--remove", "--replace", "-z", "--stdin"], input: Self.nulJoined(update), environment: index)
        }
        let tree = try await shadow(["write-tree"], environment: index).trimmed
        return (tree, skipped)
    }

    /// The files to capture, relative to the project, and what was left out. What a session's snapshot left out once stays
    /// out of its later ones (`skip-<session>`): a folder skipped at a run's start and captured at its end looked "added",
    /// and a revert or rewind deleted it.
    func capturedFiles(session: UUID) async throws -> (files: [String], skipped: [String]) {
        let stickyURL = gitDir.appending(path: "skip-\(session.uuidString)")
        let sticky = ((try? String(contentsOf: stickyURL, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line -> (String, String)? in
            let f = line.split(separator: "\t", maxSplits: 1)
            return f.count == 2 ? (String(f[0]), String(f[1])) : nil
        }
        var (files, skipped) = try await capturedFiles()
        if !sticky.isEmpty {
            let held = sticky.map(\.0)
            files.removeAll { f in held.contains { $0.hasSuffix("/") ? f.hasPrefix($0) : f == $0 } }
            for (path, reason) in sticky where !skipped.contains(where: { $0.hasPrefix(path + " (") }) { skipped.append("\(path) (\(reason))") }
        }
        let new = skipped.compactMap { s -> String? in
            guard let r = s.range(of: " (", options: .backwards) else { return nil }
            let path = String(s[..<r.lowerBound])
            return sticky.contains { $0.0 == path } ? nil : path + "\t" + String(s[r.upperBound...].dropLast())
        }
        if !new.isEmpty {
            try? JSONLines.append(Data((new.joined(separator: "\n") + "\n").utf8), to: stickyURL, create: true)
        }
        try await rememberExcluded(session: session)
        return (files, skipped)
    }

    /// Remembers, for the session, the paths that are in the project but out of its snapshots because git ignores them
    /// (`excluded-<session>`, an ignored folder as one entry). A run that stops ignoring one (or `git add -f`) puts it
    /// in the end snapshot and not the start's, so the diff calls it "added", and a revert or rewind deleted the user's
    /// own file: `heldOutside` keeps those out of a restore's deletions.
    func rememberExcluded(session: UUID) async throws {
        guard try await isGitProject() else { return }
        let url = gitDir.appending(path: "excluded-\(session.uuidString)")
        let known = Set(excludedPaths(session: session))
        let now = try await projectGit(["ls-files", "-z", "-o", "-i", "--exclude-standard", "--directory"]).nulSeparated
        let new = now.filter { !known.contains($0) && !$0.contains("\n") }
        if !new.isEmpty {
            _ = try? JSONLines.append(Data((new.joined(separator: "\n") + "\n").utf8), to: url, create: true)
        }
    }

    /// The paths a session saw in the project but outside its snapshots: ignored by git, or skipped for size (a folder
    /// with a trailing slash).
    func excludedPaths(session: UUID) -> [String] {
        let ignored = ((try? String(contentsOf: gitDir.appending(path: "excluded-\(session.uuidString)"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        let skipped = ((try? String(contentsOf: gitDir.appending(path: "skip-\(session.uuidString)"), encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { $0.split(separator: "\t", maxSplits: 1).first.map(String.init) }
        return ignored + skipped
    }

    /// Of `paths`, those that `base` doesn't have but the session saw in the project outside its snapshots: restoring
    /// them to `base` would delete a file that was there before the run, so a restore leaves them alone.
    public func heldOutside(_ paths: [String], at base: String, session: UUID) async throws -> [String] {
        let held = excludedPaths(session: session)
        guard !held.isEmpty else { return [] }
        var out: [String] = []
        for rel in Set(paths).sorted() where held.contains(where: { $0.hasSuffix("/") ? rel.hasPrefix($0) : rel == $0 }) {
            if try await shadow(["ls-tree", "-z", base, "--", rel]).nulSeparated.isEmpty { out.append(rel) }
        }
        return out
    }

    func capturedFiles() async throws -> (files: [String], skipped: [String]) {
        let fm = FileManager.default
        func size(_ rel: String) -> (exists: Bool, bytes: Int, regularOrLink: Bool) {
            guard let a = try? fm.attributesOfItem(atPath: project.appending(path: rel).path) else { return (false, 0, false) }
            let type = a[.type] as? FileAttributeType
            return (true, (a[.size] as? Int) ?? 0, type == .typeRegular || type == .typeSymbolicLink)
        }
        var files: [String] = [], skipped: [String] = []
        if try await isGitProject() {
            for rel in try await projectGit(["ls-files", "-z"]).nulSeparated {
                let s = size(rel)
                guard s.exists else { continue }                         // deleted
                guard s.regularOrLink else { skipped.append("\(rel)/ (nested repository)"); continue }     // a submodule
                if s.bytes > limits.trackedFileBytes { skipped.append("\(rel) (\(Self.megabytes(s.bytes)))"); continue }
                files.append(rel)
            }
            var keptFolders: [String] = []
            for rel in try await projectGit(["ls-files", "-z", "-o", "--exclude-standard", "--directory", "--no-empty-directory"]).nulSeparated {
                if rel.hasSuffix("/") {
                    // Git lists a repository inside the project as a folder and never looks inside it.
                    if fm.fileExists(atPath: project.appending(path: rel + ".git").path) { skipped.append("\(rel) (nested repository)"); continue }
                    let (count, bytes, over) = Self.measure(project.appending(path: rel), maxFiles: limits.untrackedFolderFiles,
                                                            maxBytes: limits.untrackedFolderBytes)
                    if over { skipped.append("\(rel) (\(count > limits.untrackedFolderFiles ? "over \(limits.untrackedFolderFiles) files" : Self.megabytes(bytes)))") }
                    else if count > 0 { keptFolders.append(rel) }
                    continue
                }
                let s = size(rel)
                guard s.exists, s.regularOrLink else { continue }
                if s.bytes > limits.fileBytes { skipped.append("\(rel) (\(Self.megabytes(s.bytes)))"); continue }
                files.append(rel)
            }
            if !keptFolders.isEmpty {
                for rel in try await projectGit(["ls-files", "-z", "-o", "--exclude-standard", "--"] + keptFolders).nulSeparated {
                    if rel.hasSuffix("/") { skipped.append("\(rel) (nested repository)"); continue }
                    let s = size(rel)
                    guard s.exists, s.regularOrLink else { continue }
                    if s.bytes > limits.fileBytes { skipped.append("\(rel) (\(Self.megabytes(s.bytes)))"); continue }
                    files.append(rel)
                }
            }
        } else {
            try plainFolderFiles(&files, &skipped)
        }
        return (files, skipped)
    }

    /// A folder that isn't a repository: its files minus the default excludes, or a failure past the size cap.
    func plainFolderFiles(_ files: inout [String], _ skipped: inout [String]) throws {
        var total = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: project, includingPropertiesForKeys: keys, options: []) else { return }
        let base = project.path.count + 1
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if Self.defaultExcludes.contains(url.lastPathComponent) {
                if v.isDirectory == true { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true || v.isSymbolicLink == true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base))
            let bytes = v.fileSize ?? 0
            if bytes > limits.fileBytes { skipped.append("\(rel) (\(Self.megabytes(bytes)))"); continue }
            files.append(rel)
            total += bytes
            if files.count > limits.folderFiles || total > limits.folderBytes {
                throw Failure(message: "\(project.lastPathComponent) is too large for snapshots (over \(files.count > limits.folderFiles ? "\(limits.folderFiles) files" : Self.megabytes(limits.folderBytes)), not counting dependency and build folders), so changes made by commands can't be shown or undone")
            }
        }
    }

    /// Files and bytes under a folder (not following links, not into `.git`), stopping once either is over its limit.
    static func measure(_ folder: URL, maxFiles: Int, maxBytes: Int) -> (files: Int, bytes: Int, over: Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: []) else { return (0, 0, false) }
        var files = 0, bytes = 0
        for case let url as URL in e {
            if url.lastPathComponent == ".git" { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            files += 1
            bytes += v.fileSize ?? 0
            if files > maxFiles || bytes > maxBytes { return (files, bytes, true) }
        }
        return (files, bytes, false)
    }

    // MARK: Reading

    /// The session's snapshots, oldest first.
    public func list(session: UUID) async throws -> [Snapshot] {
        guard FileManager.default.fileExists(atPath: gitDir.appending(path: "HEAD").path) else { return [] }
        let ref = Self.ref(session)
        guard !(try await shadow(["rev-parse", "-q", "--verify", ref], okStatuses: [0, 1]).trimmed.isEmpty) else { return [] }
        let out = try await shadow(["log", "-z", "--format=%H%x1f%T%x1f%ct%x1f%B", ref])
        return out.nulSeparated.compactMap { Self.parse($0, session: session) }.reversed()
    }

    static func parse(_ entry: String, session: UUID) -> Snapshot? {
        let parts = entry.components(separatedBy: "\u{1F}")
        guard parts.count >= 4, let seconds = Double(parts[2]) else { return nil }
        var fields: [String: String] = [:]
        // The skipped list is joined with the same separator: the message is everything after the third field.
        for line in parts[3...].joined(separator: "\u{1F}").split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let phase = fields["phase"].flatMap(Snapshot.Phase.init(rawValue:)) else { return nil }
        return Snapshot(commit: parts[0], tree: parts[1], session: session, turn: fields["turn"].flatMap(UUID.init(uuidString:)),
                        run: fields["run"].flatMap(UUID.init(uuidString:)), phase: phase, date: Date(timeIntervalSince1970: seconds),
                        skipped: fields["skipped"].map { $0.components(separatedBy: "\u{1F}").filter { !$0.isEmpty } } ?? [])
    }

    /// One file's change between two snapshots.
    public struct Change: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable { case added, modified, deleted, renamed, typeChanged = "type changed" }
        public var path: String
        /// The old path of a rename.
        public var oldPath: String?
        public var kind: Kind
        /// Lines added and removed; nil for a binary file.
        public var additions: Int?
        public var deletions: Int?
        public var id: String { path }
        /// The paths a revert touches: both sides of a rename.
        public var paths: [String] { [oldPath, path].compactMap { $0 } }

        public init(path: String, oldPath: String?, kind: Kind, additions: Int? = nil, deletions: Int? = nil) {
            self.path = path
            self.oldPath = oldPath
            self.kind = kind
            self.additions = additions
            self.deletions = deletions
        }
    }

    /// What changed from `from` (a commit or tree) to `to` (one, or nil: the files as they are now), file by file.
    public func changes(session: UUID, from: String, to: String?) async throws -> [Change] {
        let target: String
        if let to { target = to } else { target = try await currentTree(session: session).tree }
        let raw = try await shadow(["diff", "--no-ext-diff", "--no-renames", "-z", "--name-status", from, target]).nulSeparated
        var out: [Change] = []
        var i = 0
        while i + 1 < raw.count {
            let status = raw[i], path = raw[i + 1]
            i += 2
            let kind: Change.Kind
            switch status.first {
            case "A": kind = .added
            case "D": kind = .deleted
            case "T": kind = .typeChanged
            default: kind = .modified
            }
            out.append(Change(path: path, oldPath: nil, kind: kind))
        }
        // Renames: an added and a deleted file with the same content, matched by git's own rename detection.
        let renames = try await shadow(["diff", "--no-ext-diff", "-M", "-z", "--name-status", "--diff-filter=R", from, target]).nulSeparated
        var j = 0
        while j + 2 < renames.count {
            let old = renames[j + 1], new = renames[j + 2]
            j += 3
            out.removeAll { $0.path == old && $0.kind == .deleted }
            if let k = out.firstIndex(where: { $0.path == new }) { out[k].oldPath = old; out[k].kind = .renamed }
        }
        let numstat = try await shadow(["diff", "--no-ext-diff", "--no-renames", "-z", "--numstat", from, target]).nulSeparated
        var counts: [String: (Int?, Int?)] = [:]
        for entry in numstat {
            let f = entry.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3 else { continue }
            counts[String(f[2])] = (Int(f[0]), Int(f[1]))
        }
        for k in out.indices {
            if let old = out[k].oldPath {
                // A rename's lines: the new file's against the old one's ("3\t1\t\0old\0new\0" with -z).
                let r = try await shadow(["diff", "--no-ext-diff", "-M", "-z", "--numstat", from, target, "--", old, out[k].path])
                let f = r.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                if f.count == 3 { out[k].additions = Int(f[0]); out[k].deletions = Int(f[1]) }
                continue
            }
            out[k].additions = counts[out[k].path]?.0
            out[k].deletions = counts[out[k].path]?.1
        }
        return out.sorted { $0.path < $1.path }
    }

    /// The unified diff of one change (both paths of a rename), from `from` to `to` (nil: now).
    public func patch(session: UUID, from: String, to: String?, change: Change, context: Int = 3) async throws -> String {
        let target: String
        if let to { target = to } else { target = try await currentTree(session: session).tree }
        return try await shadow(["diff", "--no-ext-diff", "--no-color", "-M", "-U\(context)", from, target, "--"] + change.paths)
    }

    /// The unified diff of everything from `from` to `to` (nil: now), for a reviewer or `/diff`.
    public func patch(session: UUID, from: String, to: String?) async throws -> String {
        let target: String
        if let to { target = to } else { target = try await currentTree(session: session).tree }
        return try await shadow(["diff", "--no-ext-diff", "--no-color", "-M", from, target])
    }

    /// Which changes to show: the latest run's, one turn's (all its runs), or the whole session's.
    public enum Scope: Hashable, Sendable { case lastRun, session, turn(UUID) }

    /// The snapshots a scope spans: from its first start to its last end, or to now (`to` nil) for the session or a run
    /// still going. Nil when there are none.
    public static func range(_ list: [Snapshot], _ scope: Scope) -> (from: Snapshot, to: Snapshot?)? {
        switch scope {
        case .session:
            return list.first.map { ($0, nil) }
        case .lastRun:
            guard let start = list.last(where: { $0.phase == .start }) else { return nil }
            return (start, list.last { $0.phase == .end && $0.run == start.run && $0.date >= start.date })
        case .turn(let id):
            guard let start = list.first(where: { $0.phase == .start && $0.turn == id }) else { return nil }
            return (start, list.last { $0.phase == .end && $0.turn == id })
        }
    }

    /// Whether `path` is now as it was in `snapshot` (a hunk revert needs it: the hunks shown are the snapshots'), so a
    /// file the user changed since isn't reverted by hunk.
    public func unchanged(_ path: String, since snapshot: String) async throws -> Bool {
        let then = try await shadow(["rev-parse", "-q", "--verify", "\(snapshot):\(path)"], okStatuses: [0, 1]).trimmed
        let url = project.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return then.isEmpty }
        let now = try await shadow(["hash-object", "--no-filters", "--", path]).trimmed
        return now == then
    }

    /// `/diff`: what a scope changed, a line per file and then the unified diff (cut at `maxBytes`).
    public func report(session: UUID, scope: Scope, maxBytes: Int = 60_000) async throws -> String {
        let list = try await list(session: session)
        guard let range = Self.range(list, scope) else { return "No snapshots in this session yet: they're taken when a run starts and ends." }
        let changes = try await changes(session: session, from: range.from.commit, to: range.to?.commit)
        let what: String
        switch scope {
        case .lastRun: what = "The latest run"
        case .session: what = "This session"
        case .turn: what = "That turn"
        }
        var out = changes.isEmpty ? "\(what) changed no files" : "\(what) changed \(changes.count) file\(changes.count == 1 ? "" : "s")"
        out += range.to == nil ? " (up to now)" : ""
        out += changes.isEmpty ? "." : ":"
        for c in changes {
            out += "\n  \(c.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(c.oldPath.map { "\($0) → " } ?? "")\(c.path)"
                + (c.additions.map { "  +\($0) −\(c.deletions ?? 0)" } ?? "  (binary)")
        }
        let skipped = (range.to ?? range.from).skipped
        if !skipped.isEmpty { out += "\nNot captured: " + skipped.joined(separator: ", ") }
        guard !changes.isEmpty else { return out }
        var patch = try await patch(session: session, from: range.from.commit, to: range.to?.commit)
        if patch.utf8.count > maxBytes {
            patch = String(decoding: Data(patch.utf8.prefix(maxBytes)), as: UTF8.self) + "\n… (cut; the whole diff is \(patch.utf8.count / 1000) KB)"
        }
        return out + "\n\n" + patch
    }

    // MARK: Reverting

    /// Puts files back as they were in `snapshot` (a commit or tree): written from it, or deleted when it doesn't have
    /// them. With the session given, the restore is recorded on its chain (`Phase.restore`), so a later rewind doesn't
    /// take it for the user's own edit, and a file the session saw outside its snapshots (`heldOutside`) isn't deleted.
    @discardableResult
    public func restore(_ paths: [String], to snapshot: String, session: UUID? = nil) async throws -> [CheckpointStore.Restored] {
        let fm = FileManager.default
        var restored: [CheckpointStore.Restored] = []
        var held: [String] = []
        if let session { held = try await heldOutside(paths, at: snapshot, session: session) }
        var entries: [(rel: String, entry: String?)] = []
        for rel in Set(paths).subtracting(held).sorted() { entries.append((rel, try await shadow(["ls-tree", "-z", snapshot, "--", rel]).nulSeparated.first)) }
        // Deletions before writes: on a case-insensitive disk a case-only rename's two names are one file, and deleting the
        // new name after writing the old one deleted the file.
        entries.sort { ($0.entry == nil ? 0 : 1, $0.rel) < ($1.entry == nil ? 0 : 1, $1.rel) }
        let root = project.resolvingSymlinksInPath().standardizedFileURL.path
        var outside: [String] = []
        for (rel, entry) in entries {
            let url = project.appending(path: rel)
            // Never through a link that leads out of the project (a run that replaced a folder with one).
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            guard parent == root || parent.hasPrefix(root + "/") else { outside.append(rel); continue }
            if let entry, let tab = entry.firstIndex(of: "\t") {
                let meta = entry[..<tab].split(separator: " ")       // mode type object
                guard meta.count == 3, meta[1] == "blob" else { continue }
                let data = try await shadowData(["cat-file", "blob", String(meta[2])])
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil || meta[0] == "120000" { try? fm.removeItem(at: url) }
                if meta[0] == "120000" {
                    try fm.createSymbolicLink(atPath: url.path, withDestinationPath: String(decoding: data, as: UTF8.self))
                } else {
                    try data.write(to: url, options: .atomic)
                    try fm.setAttributes([.posixPermissions: meta[0] == "100755" ? 0o755 : 0o644], ofItemAtPath: url.path)
                }
                restored.append(.init(path: url.path, deleted: false))
            } else if fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil {
                try fm.removeItem(at: url)
                restored.append(.init(path: url.path, deleted: true))
            }
        }
        if let session, !restored.isEmpty { try await take(session: session, turn: nil, run: nil, phase: .restore) }
        var problems: [String] = []
        if !outside.isEmpty { problems.append("Not restored, because a link now leads them out of the project: " + outside.joined(separator: ", ")) }
        if !held.isEmpty {
            problems.append("Not deleted, because " + (held.count == 1 ? "it was" : "they were") + " there before the run, outside its snapshots (ignored by git then): "
                            + held.joined(separator: ", "))
        }
        if !problems.isEmpty {
            throw Failure(message: problems.joined(separator: ". ")
                          + (restored.isEmpty ? "" : ". The other \(restored.count) file\(restored.count == 1 ? " was" : "s were") restored."))
        }
        return restored
    }

    /// Undoes one hunk of a file's change since `from`: the hunk shown (its lines), found again by its content in the
    /// change as it is now (an index went stale when the file changed after the view was drawn, and reverted another
    /// hunk, perhaps the user's own edit). Fails, changing nothing, when it isn't there any more.
    public func revertHunk(session: UUID, from: String, change: Change, hunk: [Substring]) async throws {
        let text = try await patch(session: session, from: from, to: nil, change: change)
        let body = Array(hunk.dropFirst())                       // the lines without the "@@ … @@" header
        guard let i = UnifiedDiff.split(text).hunks.firstIndex(where: { Array($0.dropFirst()) == body }),
              let one = UnifiedDiff.keepingHunk(i, of: text) else {
            throw Failure(message: "That part of the change isn't there any more (the file changed since): refresh and try again.")
        }
        _ = try await shadow(["apply", "-R", "--whitespace=nowarn", "-"], input: Data(one.utf8))
        try await take(session: session, turn: nil, run: nil, phase: .restore)
    }

    // MARK: Housekeeping

    /// Forgets a session's snapshots (its chain and index); git drops the objects later.
    public func drop(session: UUID) async throws {
        guard FileManager.default.fileExists(atPath: gitDir.appending(path: "HEAD").path) else { return }
        _ = try await shadow(["update-ref", "-d", Self.ref(session)], okStatuses: [0, 1])
        try? FileManager.default.removeItem(at: gitDir.appending(path: "index-\(session.uuidString)"))
        try? FileManager.default.removeItem(at: gitDir.appending(path: "skip-\(session.uuidString)"))
        try? FileManager.default.removeItem(at: gitDir.appending(path: "excluded-\(session.uuidString)"))
    }

    /// Forgets sessions whose last snapshot is older than `age`, then lets git pack and prune when it's due.
    public func prune(olderThan age: TimeInterval, now: Date = Date()) async throws {
        guard FileManager.default.fileExists(atPath: gitDir.appending(path: "HEAD").path) else { return }
        let out = try await shadow(["for-each-ref", "--format=%(refname)%09%(committerdate:unix)", "refs/sessions/"])
        for line in out.split(separator: "\n") {
            let f = line.split(separator: "\t")
            guard f.count == 2, let t = Double(f[1]), now.timeIntervalSince1970 - t > age,
                  let id = UUID(uuidString: String(f[0].dropFirst("refs/sessions/".count))) else { continue }
            try await drop(session: id)
        }
        _ = try? await shadow(["gc", "--auto", "--quiet"])
    }

    static func ref(_ session: UUID) -> String { "refs/sessions/\(session.uuidString)" }

    /// Removes the shadow repositories in `root` whose project folder is gone (moved or deleted) and that haven't been
    /// written for `age`: `prune` runs only when a project is used, so these were never cleaned up. A project on a volume
    /// that isn't mounted, or a repository whose `description` doesn't name its project, is left alone. Returns the
    /// repositories removed.
    @discardableResult
    public static func sweepOrphans(root: URL, olderThan age: TimeInterval = 30 * 86_400, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        let prefix = "kurtkode's snapshots of ", suffix = " (GAP_ANALYSIS.md C1)"
        var removed: [URL] = []
        let repos = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for repo in repos where repo.pathExtension == "git" {
            guard let text = try? String(contentsOf: repo.appending(path: "description"), encoding: .utf8) else { continue }
            let line = text.trimmingCharacters(in: .newlines)
            guard line.hasPrefix(prefix), line.hasSuffix(suffix) else { continue }
            let project = String(line.dropFirst(prefix.count).dropLast(suffix.count))
            guard project.hasPrefix("/"), !fm.fileExists(atPath: project) else { continue }
            let parts = project.split(separator: "/", omittingEmptySubsequences: true)
            if parts.first == "Volumes", parts.count >= 2, !fm.fileExists(atPath: "/Volumes/\(parts[1])") { continue }
            guard let modified = (try? repo.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > age else { continue }
            if (try? fm.removeItem(at: repo)) != nil { removed.append(repo) }
        }
        return removed
    }

    func ensureRepository() async throws {
        let fm = FileManager.default
        let attributes = gitDir.appending(path: "info/attributes")
        if !fm.fileExists(atPath: gitDir.appending(path: "HEAD").path) {
            try fm.createDirectory(at: gitDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try await Self.git(["init", "-q", "--bare", gitDir.path], cwd: gitDir.deletingLastPathComponent(), environment: [:])
            try? Data("kurtkode's snapshots of \(project.path) (GAP_ANALYSIS.md C1)\n".utf8).write(to: gitDir.appending(path: "description"))
        }
        // Files stored byte for byte: the project's own attributes (LFS, eol, git-crypt) ran on the way in and never on the
        // way out, so a restore wrote an LFS pointer over the real file, or LF over CRLF.
        if !fm.fileExists(atPath: attributes.path) {
            try fm.createDirectory(at: attributes.deletingLastPathComponent(), withIntermediateDirectories: true)
            // (Not -diff: that makes every file "binary" in diffs.)
            try Data("* -text -filter -ident -eol -working-tree-encoding\n".utf8).write(to: attributes)
        }
    }

    func isGitProject() async throws -> Bool {
        (try? await projectGit(["rev-parse", "--is-inside-work-tree"]))?.trimmed == "true"
    }

    // MARK: Running git

    /// Git in the shadow repository, with the project as its work tree (and the session's index, when given).
    func shadow(_ arguments: [String], input: Data? = nil, okStatuses: Set<Int32> = [0],
                environment: [String: String] = [:]) async throws -> String {
        String(decoding: try await shadowData(arguments, input: input, okStatuses: okStatuses, environment: environment), as: UTF8.self)
    }

    func shadowData(_ arguments: [String], input: Data? = nil, okStatuses: Set<Int32> = [0],
                    environment: [String: String] = [:]) async throws -> Data {
        // The user's global and system config stay out (diff.noprefix broke `apply -R`; textconv drivers changed diffs).
        var env = ["GIT_DIR": gitDir.path, "GIT_WORK_TREE": project.path, "GIT_LITERAL_PATHSPECS": "1",
                   "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
                   "GIT_AUTHOR_NAME": "kurtkode", "GIT_AUTHOR_EMAIL": "kurtkode@localhost",
                   "GIT_COMMITTER_NAME": "kurtkode", "GIT_COMMITTER_EMAIL": "kurtkode@localhost"]
        env.merge(environment) { $1 }
        return try await Self.git(["-c", "core.autocrlf=false", "-c", "core.fsmonitor=false", "-c", "core.quotePath=false",
                                   "-c", "gc.autoDetach=false"] + arguments,
                                  cwd: project, environment: env, input: input, okStatuses: okStatuses)
    }

    /// Git in the project's own repository (read-only uses: listing files).
    func projectGit(_ arguments: [String]) async throws -> String {
        String(decoding: try await Self.git(["-c", "core.quotePath=false"] + arguments, cwd: project,
                                            environment: ["GIT_LITERAL_PATHSPECS": "1", "GIT_OPTIONAL_LOCKS": "0"]), as: UTF8.self)
    }

    /// Runs git with the environment's own `GIT_*` variables removed (a session run from a git hook mustn't aim these at
    /// another repository), stdin written while stdout is read, and the exit waited for by its signal.
    static func git(_ arguments: [String], cwd: URL, environment: [String: String], input: Data? = nil,
                    okStatuses: Set<Int32> = [0]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = GitRepo.safeConfig + arguments
                p.currentDirectoryURL = cwd
                p.environment = GitRepo.environment(environment)
                let out = Pipe(), err = Pipe(), inp = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = input == nil ? FileHandle.nullDevice : inp
                let exited: DispatchSemaphore
                do { exited = try p.startWithExitSignal() } catch { cont.resume(throwing: error); return }
                if let input {
                    let w = inp.inputForChild
                    DispatchQueue.global().async { try? w.write(contentsOf: input); try? w.close() }
                }
                let stderr = PipeDrain(err.fileHandleForReading)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.wait()
                let status = p.waitForExit(exited, timeout: 120)
                if okStatuses.contains(status) { cont.resume(returning: data) }
                else {
                    let message = String(decoding: errData.isEmpty ? data : errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: Failure(message: message.isEmpty ? "git \(arguments.first { !$0.hasPrefix("-") && !$0.contains("=") } ?? "") failed (\(status))" : message))
                }
            }
        }
    }

    static func nulJoined(_ paths: Set<String>) -> Data { Data(paths.sorted().map { $0 + "\0" }.joined().utf8) }

    static func megabytes(_ bytes: Int) -> String { bytes >= 1_000_000 ? "\(bytes / 1_000_000) MB" : "\(bytes / 1000) KB" }
}

/// Hunks of a unified diff.
public enum UnifiedDiff {
    /// The file header and the hunks of a one-file diff.
    public static func split(_ patch: String) -> (header: [Substring], hunks: [[Substring]]) {
        var header: [Substring] = [], hunks: [[Substring]] = []
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { hunks.append([line]) }
            else if hunks.isEmpty { header.append(line) }
            else { hunks[hunks.count - 1].append(line) }
        }
        // The text ends with a newline: the last "line" is empty.
        if var last = hunks.popLast() { if last.last == "" { last.removeLast() }; hunks.append(last) }
        return (header, hunks)
    }

    /// The diff without the files `patterns` withhold from remote models (Settings → Privacy), and their paths.
    public static func withholding(_ patch: String, patterns: [String]) -> (String, [String]) {
        guard !patterns.isEmpty, !patch.isEmpty else { return (patch, []) }
        let rule = WithheldFiles(patterns: patterns, host: "")
        var kept: [Substring] = [], dropped: [String] = [], skipping = false
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                // "diff --git a/X b/Y": both sides count (a rename into or out of a secret).
                let rest = line.dropFirst("diff --git ".count)
                let paths: [String] = rest.range(of: " b/", options: .backwards).map { r in
                    [String(rest[..<r.lowerBound].drop { $0 == "\"" }.dropFirst(2)), String(rest[r.upperBound...])]
                } ?? [String(rest)]
                skipping = paths.contains { rule.matches(URL(fileURLWithPath: "/" + $0)) }
                if skipping { dropped.append(paths.last ?? String(rest)) }
            }
            if !skipping { kept.append(line) }
        }
        return (kept.joined(separator: "\n"), dropped)
    }

    /// The diff with only hunk `n` kept, or nil when there's no such hunk.
    public static func keepingHunk(_ n: Int, of patch: String) -> String? {
        let (header, hunks) = split(patch)
        guard hunks.indices.contains(n) else { return nil }
        return (header + hunks[n]).joined(separator: "\n") + "\n"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nulSeparated: [String] { split(separator: "\0", omittingEmptySubsequences: true).map(String.init) }
}

/// A main run's snapshots: the project's shadow repository and the session and turn they belong to.
public struct RunSnapshots: Sendable {
    public var store: ProjectSnapshots
    public var session: UUID
    public var turn: UUID?

    public init(store: ProjectSnapshots, session: UUID, turn: UUID?) {
        self.store = store
        self.session = session
        self.turn = turn
    }

    /// Takes one; a failure is a notice (once a process for each project and reason), never the run's end. The first
    /// snapshot of a project in a process also forgets sessions whose last snapshot is more than 30 days old.
    func take(_ phase: ProjectSnapshots.Snapshot.Phase, run: UUID?,
              emit: @Sendable (AgentEvent) async -> Void) async -> ProjectSnapshots.Snapshot? {
        do {
            let s = try await store.take(session: session, turn: turn, run: run, phase: phase)
            if Self.once.first("prune|" + store.gitDir.path) {
                let store = store
                Task.detached(priority: .background) { try? await store.prune(olderThan: 30 * 86_400) }
            }
            // Once a process: the repositories of projects that were moved or deleted, which no `prune` reaches.
            let snapshotsRoot = store.gitDir.deletingLastPathComponent()
            if Self.once.first("sweep|" + snapshotsRoot.path) {
                Task.detached(priority: .background) { ProjectSnapshots.sweepOrphans(root: snapshotsRoot) }
            }
            return s
        } catch {
            let why = (error as? ProjectSnapshots.Failure)?.message ?? error.localizedDescription
            if Self.once.first(store.gitDir.path + "|" + why) {
                await emit(.hookNotice("No snapshot of the project's files for this run, so its changes made by commands can't be shown or undone: \(why)"))
            }
            return nil
        }
    }

    static let once = OnceSet()
}

/// Keys seen once in this process.
final class OnceSet: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<String>()
    /// True the first time `key` is given.
    func first(_ key: String) -> Bool { lock.withLock { seen.insert(key).inserted } }
}
