import Foundation

/// What a settings file held when it was read, and what's wrong with it, if anything.
public struct ConfigLoad<Value: Sendable>: Sendable {
    public var value: Value
    /// Shown to the user: why the file, or some of its entries, couldn't be read. Nil when all is well.
    public var problem: String?
    /// The file exists but isn't a JSON list: nothing is saved over it until the user fixes or replaces it.
    public var unreadable: Bool
}

/// A settings file can't be read, so saving over it would lose what it holds.
public struct ConfigFileUnreadable: LocalizedError, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// A settings file that holds a JSON list (endpoints, model profiles), read and written entry by entry so one entry
/// this build can't read (a `kind` a newer build wrote) doesn't lose the others, and isn't lost itself when the list is
/// saved: entries that don't decode are written back as they were. A file that isn't a JSON list at all is copied aside
/// and never saved over until the user fixes it or chooses to replace it.
struct ConfigListFile<Item: Codable> {
    let fileURL: URL

    struct Contents {
        var items: [Item] = []
        /// The raw JSON of each entry that didn't decode.
        var kept: [Data] = []
        var problems: [String] = []
        /// The file exists but isn't a JSON list; `problems` says why.
        var unreadable = false
        var exists = false
    }

    func read() -> Contents {
        var c = Contents()
        guard let data = try? Data(contentsOf: fileURL) else { return c }
        c.exists = true
        // An empty file (an editor's new file) is an empty list, not a broken one.
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return c }
        let list: [Any]
        do {
            guard let l = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] else {
                c.unreadable = true
                c.problems = ["it isn't a list"]
                return c
            }
            list = l
        } catch {
            c.unreadable = true
            c.problems = [((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription]
            return c
        }
        for entry in list {
            guard let raw = try? JSONSerialization.data(withJSONObject: entry, options: [.fragmentsAllowed, .sortedKeys]) else { continue }
            do { c.items.append(try JSONDecoder().decode(Item.self, from: raw)) }
            catch {
                c.kept.append(raw)
                c.problems.append(Self.describe(error))
            }
        }
        return c
    }

    /// The problem to show for what `read` found, naming the backup for an unreadable file.
    func problem(_ c: Contents, backup: URL?) -> String? {
        let name = fileURL.lastPathComponent
        if c.unreadable {
            return "\(name) can't be read (\(c.problems.first ?? "unknown error")), so changes aren't saved to it until it's "
                + "fixed or replaced" + (backup.map { "; a copy is at \($0.path)" } ?? "")
        }
        guard !c.kept.isEmpty else { return nil }
        let n = c.kept.count
        return "\(n) entr\(n == 1 ? "y" : "ies") in \(name) can't be read by this version (\(c.problems.first ?? "unknown error")); "
            + "\(n == 1 ? "it's" : "they're") kept in the file but not shown"
    }

    /// Copies the file aside as `<name>.bad-<date>`, unless a copy with the same contents is already there.
    @discardableResult
    func backUp() -> URL? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dir = fileURL.deletingLastPathComponent(), prefix = fileURL.lastPathComponent + ".bad-"
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(prefix) {
            if (try? Data(contentsOf: dir.appending(path: name))) == data { return dir.appending(path: name) }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appending(path: prefix + f.string(from: Date()))
        do { try data.write(to: url, options: .withoutOverwriting) } catch { return nil }
        return url
    }

    /// Saves `items`, writing back the entries the file holds that this build can't read. Throws `ConfigFileUnreadable`
    /// when the file isn't a JSON list, unless `replacingUnreadable` (then it's copied aside first).
    func write(_ items: [Item], replacingUnreadable: Bool = false) throws {
        let current = read()
        if current.unreadable {
            guard replacingUnreadable else {
                throw ConfigFileUnreadable(message: problem(current, backup: backUp()) ?? fileURL.lastPathComponent + " can't be read")
            }
            guard backUp() != nil else {
                throw ConfigFileUnreadable(message: "\(fileURL.lastPathComponent) couldn't be copied aside, so it wasn't replaced")
            }
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try enc.encode(items)
        if !current.unreadable, !current.kept.isEmpty {
            // Each entry on its own, so ours keep the encoder's formatting and the others their content.
            let entries = try items.map { String(decoding: try enc.encode($0), as: UTF8.self) }
                + current.kept.map { String(decoding: $0, as: UTF8.self) }
            data = Data(("[\n" + entries.joined(separator: ",\n") + "\n]\n").utf8)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c):
            return c.debugDescription + (c.codingPath.isEmpty ? "" : " at " + c.codingPath.map(\.stringValue).joined(separator: "."))
        case DecodingError.keyNotFound(let k, _): return "missing \"\(k.stringValue)\""
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
            return "wrong value at " + c.codingPath.map(\.stringValue).joined(separator: ".")
        default: return error.localizedDescription
        }
    }
}
