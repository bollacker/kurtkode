import Darwin
import Foundation

/// A folder outside the project that a session may also use: readable, and writable when the user said so.
public struct ExtraFolder: Codable, Sendable, Hashable, Identifiable {
    /// Standardized, symlink-resolved absolute path.
    public var path: String
    public var writable: Bool
    public var id: String { path }

    public init(path: String, writable: Bool) {
        self.path = Workspace.canonical(URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)).path
        self.writable = writable
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The path with the home folder as ~, for showing.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    func contains(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p == path || p.hasPrefix(path == "/" ? "/" : path + "/")
    }
}

/// The folder an agent works in (a project, or a chat's working folder), plus any extra folders, and the rules
/// for touching files in them. Relative paths are relative to `root`; extra folders are used by absolute path.
public struct Workspace: Sendable, Hashable {
    /// Standardized, symlink-resolved absolute path.
    public let root: URL
    public var folders: [ExtraFolder]
    /// Files whose contents a run on a third-party model may not read or change (set by the loop for such a model).
    public var withheld: WithheldFiles?
    /// The run's permission rules, when they deny reading some files: a search over a folder skips those files.
    public var readDenied: PermissionRules?

    public init(root: URL, folders: [ExtraFolder] = []) {
        self.root = Self.canonical(root)
        self.folders = folders
    }

    /// Standardized and symlink-resolved, with macOS's /private firmlinks spelled the short way. Foundation drops
    /// "/private" from /private/tmp, /private/var, /private/etc only for paths that exist, so a new file written as
    /// /private/tmp/… wouldn't otherwise match a folder known as /tmp/….
    ///
    /// The part of the path that exists is resolved with realpath and the rest appended as named. Foundation's
    /// `resolvingSymlinksInPath()` resolves nothing when the whole path doesn't exist yet, so a new file under a linked
    /// folder (`tools -> .git/hooks`, `docs -> ../..`) kept the link's spelling and passed every check made on it. A
    /// dangling link is followed by name, so a write through it is checked where it would land.
    static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL.path
        var missing: [String] = []
        var resolved = "/"
        var links = 0
        while true {
            if let real = realpath(existing) { resolved = real; break }
            if links < 32, let target = try? FileManager.default.destinationOfSymbolicLink(atPath: existing) {
                links += 1
                let base = (existing as NSString).deletingLastPathComponent
                existing = URL(fileURLWithPath: target.hasPrefix("/") ? target : base + "/" + target).standardizedFileURL.path
                continue
            }
            guard existing != "/", !existing.isEmpty else { break }
            missing.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        var p = resolved
        for name in missing { p = (p as NSString).appendingPathComponent(name) }
        for short in ["/tmp", "/var", "/etc"] where p == "/private" + short || p.hasPrefix("/private" + short + "/") {
            p = String(p.dropFirst("/private".count))
        }
        return URL(fileURLWithPath: p, isDirectory: url.hasDirectoryPath)
    }

    /// The path with every symlink resolved, or nil when it doesn't exist (or can't be read).
    private static func realpath(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(path, &buf) != nil else { return nil }
        return SandboxPolicy.string(buf)
    }

    public init(path: String, folders: [ExtraFolder] = []) {
        self.init(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true), folders: folders)
    }

    /// Directories skipped when walking a folder that isn't a git repository.
    public static let defaultIgnores: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData", ".swiftpm", "Pods", "__pycache__",
        ".venv", "venv", ".tox", ".mypy_cache", ".pytest_cache", "dist", "target", ".next", ".idea", ".DS_Store",
    ]

    /// Resolves a model-supplied path. Relative paths are relative to the root; absolute paths and `~` are
    /// allowed but must land inside the root or an extra folder after resolving `..` and symlinks.
    public func resolve(_ path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed.isEmpty ? "." : trimmed as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : root.appending(path: expanded)
        let resolved = Self.canonical(url)
        // Standardizing removed every "..", and realpath returns none: one left would let a containment check by prefix
        // pass for a path that leaves the root.
        guard !resolved.pathComponents.contains("..") else { throw ToolFailure("\(path) can't be resolved to a file in the workspace.") }
        // Both: `.env` may be a link to a file with an ordinary name, and an ordinary name a link to a withheld file.
        if let w = withheld, w.matches(resolved) || w.matches(url.standardizedFileURL) {
            throw ToolFailure("\(trimmed) is withheld from remote models (Settings → Generation → Privacy): its contents "
                              + "aren't sent to \(w.host). Ask the user if you need something from it.")
        }
        guard contains(resolved) || folder(containing: resolved) != nil else {
            let others = folders.isEmpty ? "" : " or one of the other folders (\(folders.map(\.path).joined(separator: ", ")))"
            throw ToolFailure("\(path) is outside the workspace (\(root.path)). Use a path inside it\(others).")
        }
        return resolved
    }

    /// Like `resolve`, for a file about to be written: refuses read-only extra folders, and anything inside a `.git`
    /// folder. Hooks and config there run code later, outside the sandbox and any approval (the sandbox keeps commands
    /// out of them for that reason); the file tools mustn't be the way around it, in Full Auto or Accept Edits.
    public func resolveForWriting(_ path: String) throws -> URL {
        let url = try resolve(path)
        // Any case: the file system ignores it (".GIT/hooks" is ".git/hooks").
        if url.pathComponents.contains(where: { $0.lowercased() == ".git" }) {
            throw ToolFailure("\(path) is inside a .git folder, which kurtkode's file tools don't change: its hooks and "
                              + "config run code outside the sandbox. Use git commands, or ask the user to make the change.")
        }
        guard isWritable(url) else {
            throw ToolFailure("\(path) is in a read-only folder (\(folder(containing: url)?.path ?? "")). The user can make it "
                              + "writable, or you can write somewhere in \(root.path).")
        }
        return url
    }

    /// Inside the root itself (not an extra folder).
    public func contains(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p == root.path || p.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    /// The innermost extra folder holding `url`, when it isn't inside the root.
    public func folder(containing url: URL) -> ExtraFolder? {
        guard !contains(url) else { return nil }
        return folders.filter { $0.contains(url) }.max { $0.path.count < $1.path.count }
    }

    public func isWritable(_ url: URL) -> Bool { contains(url) || folder(containing: url)?.writable == true }

    /// The file a listed path names: listed paths are relative to the root, or absolute in an extra folder.
    public func url(ofListed path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path)
    }

    /// Path relative to the root, for showing to the model and the user.
    public func relative(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        if p == root.path { return "." }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : p
    }

    public var isGitRepository: Bool { Self.isGitRepository(root) }

    static func isGitRepository(_ base: URL) -> Bool {
        FileManager.default.fileExists(atPath: base.appending(path: ".git").path)
    }

    /// Files under `directory`, honoring .gitignore when in a git repository and the default ignores otherwise.
    /// Paths are relative to the root, or absolute for files in an extra folder. Stops after `limit` files.
    public func files(under directory: URL? = nil, limit: Int = 50_000) async -> [String] {
        let dir = directory ?? root
        if let extra = folder(containing: dir) {
            // An extra folder is listed on its own (its own .gitignore, if it's a repository), by absolute path.
            let inner = Workspace(root: extra.url)
            return await inner.files(under: dir, limit: limit).map { extra.url.appending(path: $0).path }
        }
        if isGitRepository, let listed = await gitFiles(under: dir) {
            return Array(listed.prefix(limit))
        }
        return walk(dir, limit: limit)
    }

    private func gitFiles(under dir: URL) async -> [String]? {
        let rel = relative(dir)
        var args = ["-C", root.path] + GitRepo.safeConfig + ["ls-files", "--cached", "--others", "--exclude-standard", "-z"]
        if rel != "." { args += ["--", rel] }
        guard let out = try? await runProcess("/usr/bin/git", args) else { return nil }
        let fm = FileManager.default
        return out.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
            // ls-files lists deleted-but-tracked files too.
            .filter { fm.fileExists(atPath: root.appending(path: $0).path) }
            .sorted()
    }

    private func walk(_ dir: URL, limit: Int) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                    options: [.skipsPackageDescendants]) else { return [] }
        for case let url as URL in e {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if Self.defaultIgnores.contains(name) { e.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, name != ".DS_Store" else { continue }
            out.append(relative(url))
            if out.count >= limit { break }
        }
        return out.sorted()
    }

    /// Current branch and a short status, for the system prompt.
    public func gitSummary() async -> String? {
        guard isGitRepository else { return nil }
        let branch = (try? await runProcess("/usr/bin/git", ["-C", root.path] + GitRepo.safeConfig + ["branch", "--show-current"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (try? await runProcess("/usr/bin/git", ["-C", root.path] + GitRepo.safeConfig + ["status", "--short"])) ?? ""
        let lines = status.split(separator: "\n")
        var s = "Git branch: \(branch?.isEmpty == false ? branch! : "(detached)")"
        if lines.isEmpty { s += "\nWorking tree clean." }
        else {
            s += "\nUncommitted changes (\(lines.count) files):\n" + lines.prefix(20).joined(separator: "\n")
            if lines.count > 20 { s += "\n…" }
        }
        return s
    }
}

/// True if the data looks binary (has a NUL byte in its first 8 KB).
func looksBinary(_ data: Data) -> Bool {
    data.prefix(8192).contains(0)
}

/// Runs a process to completion and returns stdout. Reads while running so a full pipe can't stall it.
func runProcess(_ executable: String, _ arguments: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            let exited: DispatchSemaphore
            do { exited = try p.startWithExitSignal() } catch { cont.resume(throwing: error); return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let status = p.waitForExit(exited, timeout: 120)
            if status == 0 { cont.resume(returning: String(decoding: data, as: UTF8.self)) }
            else { cont.resume(throwing: ToolFailure("\(executable) exited with \(status)")) }
        }
    }
}

extension Process {
    /// Starts it with a signal for its end. `waitUntilExit()` sometimes never returned for a process that had exited
    /// (once in about 4,000 rg runs: an eval stuck for 5 hours with no child left); the termination handler, set before
    /// the start, always comes.
    func startWithExitSignal() throws -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        terminationHandler = { _ in done.signal() }
        try run()
        return done
    }

    /// Its exit status once `exited` (from `startWithExitSignal`) fires; past `timeout` seconds it's stopped, and -1
    /// if even that doesn't end it.
    func waitForExit(_ exited: DispatchSemaphore, timeout: Double) -> Int32 {
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { return -1 }
        }
        return terminationStatus
    }
}

/// Files whose contents aren't sent to a third-party model: secrets that sit in projects (`.env`, private keys,
/// credentials). Patterns match a file's name (`*.pem`), or its path when they contain a slash. Templates
/// (`.env.example`, `*.sample`, `*.template`) are allowed: models often need them and they hold no secrets.
public struct WithheldFiles: Sendable, Hashable {
    public var patterns: [String]
    /// Where the contents would go, for the refusal's wording.
    public var host: String

    public init(patterns: [String], host: String) {
        self.patterns = patterns
        self.host = host
    }

    public static let defaults = [".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "id_rsa*", "id_ecdsa*", "id_ed25519*",
                                  ".netrc", ".npmrc", ".pypirc", "*.keystore", "*.jks", "credentials*", "secrets.*"]

    public func matches(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        for suffix in [".example", ".sample", ".template", ".dist"] where name.hasSuffix(suffix) { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        return patterns.contains { p in
            guard p.contains("/") else { return fnmatch(p, name, FNM_PERIOD | FNM_CASEFOLD) == 0 }
            // A folder pattern ("secrets/", "secrets/*", "secrets/**") covers everything under the folder, at any depth.
            for suffix in ["/**", "/*", "/"] where p.hasSuffix(suffix) {
                let folder = String(p.dropLast(suffix.count))
                guard !folder.isEmpty else { continue }
                return (0..<max(0, parts.count - 1)).contains { last in
                    (0...last).contains { first in
                        fnmatch(folder, parts[first...last].joined(separator: "/"), FNM_PATHNAME | FNM_CASEFOLD) == 0
                    }
                }
            }
            // A path pattern matches the path's end ("config/prod/*.yml" matches …/project/config/prod/db.yml).
            return parts.indices.contains { i in fnmatch(p, parts[i...].joined(separator: "/"), FNM_PATHNAME | FNM_CASEFOLD) == 0 }
        }
    }
}
