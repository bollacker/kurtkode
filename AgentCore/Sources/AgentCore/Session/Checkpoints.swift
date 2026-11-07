import Foundation

/// Pre-edit snapshots, so a turn's file changes can be undone ("rewind").
///
/// Before a write tool first touches a file in a turn, the file's contents (or its absence) are saved,
/// keyed by the turn: the id of the user message that started it. Rewinding to a turn restores, for
/// every file changed in that turn or later, the earliest snapshot. Changes made by shell commands
/// aren't captured.
public actor CheckpointStore {
    public let directory: URL

    struct Entry: Codable, Sendable {
        var turn: UUID
        var path: String            // absolute
        var existed: Bool
        var blob: String?           // file name under directory/blobs
        var date: Date
    }

    public struct Restored: Sendable, Hashable {
        public var path: String
        /// True when the file didn't exist before, so rewinding deleted it.
        public var deleted: Bool
    }

    static let maxSnapshotBytes = 20_000_000

    public init(directory: URL) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appending(path: "index.jsonl") }
    private var blobs: URL { directory.appending(path: "blobs") }

    /// The index as it is on disk now: the app and the command line both add to it (a copy kept in memory went stale,
    /// and saving it erased the other process's entries).
    private func load() -> [Entry] {
        ((try? Data(contentsOf: indexURL)) ?? Data()).split(separator: 0x0A).compactMap { Self.decode(Data($0)) }
    }

    private static func decode(_ line: Data) -> Entry? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Entry.self, from: line)
    }

    private static func encode(_ e: Entry) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(e)
    }

    /// Saves `file` as it is now, unless it was already saved for this turn.
    public func snapshot(_ file: URL, turn: UUID) throws {
        let list = load()
        let path = file.standardizedFileURL.path
        guard !list.contains(where: { $0.turn == turn && $0.path == path }) else { return }
        var entry = Entry(turn: turn, path: path, existed: false, blob: nil, date: Date())
        if FileManager.default.fileExists(atPath: path) {
            let data = try Data(contentsOf: file)
            guard data.count <= Self.maxSnapshotBytes else {
                throw ToolFailure("\(file.lastPathComponent) is too large to snapshot for undo (\(data.count / 1_000_000) MB)")
            }
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            let name = UUID().uuidString
            try data.write(to: blobs.appending(path: name))
            entry.existed = true
            entry.blob = name
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONLines.append(try Self.encode(entry) + [0x0A], to: indexURL, create: true)
    }

    /// Files changed in the given turns, for the rewind confirmation.
    public func changedFiles(inTurns turns: Set<UUID>) -> [String] {
        Array(Set(load().filter { turns.contains($0.turn) }.map(\.path))).sorted()
    }

    /// Forgets the snapshots of `turns` without restoring anything (a rewind that restored from the project's snapshots).
    public func forget(turns: Set<UUID>) {
        let affected = load().filter { turns.contains($0.turn) }
        guard !affected.isEmpty else { return }
        try? JSONLines.rewrite(indexURL) { lines in lines.filter { Self.decode($0).map { !turns.contains($0.turn) } ?? true } }
        for e in affected { if let b = e.blob { try? FileManager.default.removeItem(at: blobs.appending(path: b)) } }
    }

    /// Restores every file changed in `turns` to its state before the earliest of them, then forgets
    /// those snapshots.
    public func restore(turns: Set<UUID>) throws -> [Restored] { try restore(turns: turns, only: nil) }

    /// As `restore(turns:)`, restoring only `paths` (absolute) when given; the turns' snapshots are forgotten either way.
    /// With `within`, an entry naming a file outside those folders fails the whole restore before anything is
    /// touched: the index is trusted, so a store anything else could write to must not reach outside the run's project.
    public func restore(turns: Set<UUID>, only paths: Set<String>?, within roots: [URL]? = nil) throws -> [Restored] {
        let list = load()
        let affected = list.filter { turns.contains($0.turn) }
        guard !affected.isEmpty else { return [] }          // nothing changed (or no index yet): nothing to restore
        var earliest: [String: Entry] = [:]
        for e in affected where earliest[e.path] == nil && paths.map({ $0.contains(e.path) }) != false { earliest[e.path] = e }   // list is in time order
        if let roots {
            let prefixes = roots.map { Workspace.canonical($0).path }.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
            for path in earliest.keys.sorted() {
                let real = Workspace.canonical(URL(fileURLWithPath: path)).path
                guard prefixes.contains(where: { real.hasPrefix($0) }) else {
                    throw ToolFailure("won't restore \(path): it's outside the run's folders (\(roots.map(\.path).joined(separator: ", ")))")
                }
            }
        }
        var restored: [Restored] = []
        let fm = FileManager.default
        for (path, e) in earliest.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: path)
            if e.existed, let blob = e.blob {
                let data = try Data(contentsOf: blobs.appending(path: blob))
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                restored.append(Restored(path: path, deleted: false))
            } else {
                if fm.fileExists(atPath: path) { try fm.removeItem(at: url) }
                restored.append(Restored(path: path, deleted: true))
            }
        }
        // The index first (kept with what another process added since), then the blobs it no longer names.
        try JSONLines.rewrite(indexURL) { lines in lines.filter { Self.decode($0).map { !turns.contains($0.turn) } ?? true } }
        for e in affected { if let b = e.blob { try? fm.removeItem(at: blobs.appending(path: b)) } }
        return restored
    }
}
