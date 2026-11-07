import Darwin
import Foundation

/// The command sandbox (D9): `sandbox-exec` with a seatbelt profile. Reads are allowed everywhere; writes
/// only inside the project, the temp directories, and the per-user cache directory. Inside the project,
/// `.git/hooks` and `.git/config` stay read-only: a hook (or `core.hooksPath`) written there would run
/// later, outside the sandbox, the next time the user commits. So do the files that say which repository a checkout
/// belongs to, and `.worktrees`, which is other sessions' work. Network is off unless allowed, which also
/// blocks Unix sockets (a Docker socket would be a way out). A worktree kurtkode made keeps its index and objects in
/// the repository's `.git`, so what it needs of that is writable too, and no more (`LinkedGit`).
///
/// A guard names a path, so renaming a folder above it would get round the guard: the guarded folders and everything
/// above them can't be renamed or removed (a rename is `file-write-unlink` on the old name, which also refuses a hard link).
///
/// The profile allows by default, so the file rules don't reach what a daemon writes on a command's behalf: cfprefsd
/// writes preferences, and `defaults write org.mlcommons.kurt.kurtkode sandboxUse never` would turn the sandbox off
/// for the next run. Preference writes and Apple events (`osascript` driving Terminal) are denied outright; reading
/// preferences still works, and the toolchains (swift, xcodebuild, git, python, npm, brew) ran unchanged under the
/// denial. LaunchServices and launchd (`open`, `launchctl`) stay reachable: closing them needs a deny-default
/// `mach-lookup` with an allow list, which is design work (BUG_HUNT_2026-11-02.md Part 2, item 1).
public struct SandboxPolicy: Codable, Sendable, Hashable {
    public var allowNetwork: Bool
    /// More directories commands may write to (for example a toolchain's cache).
    public var extraWritable: [String]
    /// Directories commands may not write to even where they otherwise could (a read-only extra folder in /tmp).
    public var readOnly: [String] = []
    /// Files commands may not read, as withheld-file patterns (`WithheldFiles`): Plan mode's commands on a remote
    /// model (B1). Templates (`.example`, `.sample`, `.template`, `.dist`) stay readable, as for the file tools.
    public var unreadable: [String] = []

    public init(allowNetwork: Bool = false, extraWritable: [String] = []) {
        self.allowNetwork = allowNetwork
        self.extraWritable = extraWritable
    }

    static let executable = "/usr/bin/sandbox-exec"
    public static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable) }

    /// A withheld-file pattern as a seatbelt regex over the whole path, case-insensitive by letter classes; nil for a
    /// pattern with characters that aren't plainly a file name or path (it can't be spliced into the profile safely).
    static func readDenyRegex(_ pattern: String) -> String? {
        guard !pattern.isEmpty, pattern.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-*?/ ".contains($0)) }) else { return nil }
        func glob(_ g: String) -> String {
            var out = ""
            for c in g {
                switch c {
                case "*": out += "[^/]*"
                case "?": out += "[^/]"
                case ".": out += "\\."
                case " ", "-", "_", "/": out += String(c)
                default:
                    if c.isLetter { out += "[\(c.lowercased())\(c.uppercased())]" } else { out += String(c) }
                }
            }
            return out
        }
        for suffix in ["/**", "/*", "/"] where pattern.hasSuffix(suffix) {
            let folder = String(pattern.dropLast(suffix.count))
            return folder.isEmpty ? nil : "/" + glob(folder) + "/"
        }
        return "/" + glob(pattern) + "$"
    }

    /// What stays read-only of a checkout at `root`, an expression in the profile.
    private static func repositoryGuards(_ root: String) -> String {
        func path(_ tail: String) -> String { #"(string-append \#(root) "\#(tail)")"# }
        return ["/.git", "/.git/config", "/.git/config.worktree", "/.git/commondir"].map { "(literal \(path($0)))" }.joined(separator: " ")
            + ["/.git/hooks", "/.git/worktrees", "/" + GitRepo.worktreeFolder].map { " (subpath \(path($0)))" }.joined()
    }

    /// The profile. Paths come in as parameters (never spliced into the text), already resolved: the
    /// sandbox sees real paths, so /var/folders must be given as /private/var/folders. Unreadable patterns are spliced
    /// in as regexes, only from plain names (`readDenyRegex`).
    static func profile(extraCount: Int, readOnlyCount: Int = 0, pinnedCount: Int = 0, allowNetwork: Bool, unreadable: [String] = [],
                        linkedGit: Bool = false) -> String {
        let readDenies = unreadable.compactMap(readDenyRegex).map { #"(regex #"\#($0)")"# }.joined(separator: " ")
        let unreadableRules = readDenies.isEmpty ? "" : """

            (deny file-read* (with message (param "TAG")) \(readDenies))
            (allow file-read* (regex #"\\.([eE][xX][aA][mM][pP][lL][eE]|[sS][aA][mM][pP][lL][eE]|[tT][eE][mM][pP][lL][aA][tT][eE]|[dD][iI][sS][tT])$"))
            """
        let readOnly = (0..<readOnlyCount).map { #"(subpath (param "READONLY\#($0)"))"# }.joined(separator: " ")
        let extras = (0..<extraCount).map { #"(subpath (param "EXTRA\#($0)"))"# }.joined(separator: " ")
        // A writable extra folder can be a repository too: its hooks and config stay read-only, like the project's.
        let gitGuards = (0..<extraCount).map { repositoryGuards(#"(param "EXTRA\#($0)")"#) }.joined(separator: " ")
        let pinned = (0..<pinnedCount).map { #"(literal (param "PINNED\#($0)"))"# }.joined(separator: " ")
        // Only what git writes for a worktree: its own folder, and what all worktrees share. The repository's HEAD, its
        // config and hooks, and the other worktrees' folders stay out of reach.
        let linkedAllow = linkedGit ? #"""
            (subpath (param "GITDIR"))
                (subpath (string-append (param "COMMONGIT") "/objects"))
                (subpath (string-append (param "COMMONGIT") "/refs"))
                (subpath (string-append (param "COMMONGIT") "/logs"))
                (subpath (string-append (param "COMMONGIT") "/lfs"))
                (subpath (string-append (param "COMMONGIT") "/rr-cache"))
            """# + ["packed-refs", "packed-refs.lock", "packed-refs.new", "shallow", "shallow.lock", "gc.pid", "gc.pid.lock", "gc.log", "gc.log.lock"]
                .map { #" (literal (string-append (param "COMMONGIT") "/\#($0)"))"# }.joined() : ""
        // Where git would look for hooks and config if these were redirected.
        let linkedDeny = linkedGit ? #"""
            (literal (string-append (param "GITDIR") "/config.worktree"))
                (literal (string-append (param "GITDIR") "/commondir"))
                (literal (string-append (param "GITDIR") "/gitdir"))
                (subpath (string-append (param "COMMONGIT") "/objects/info"))
                (subpath (string-append (param "COMMONGIT") "/objects/pack"))
            """# : ""
        // The shared objects are the repository's contents, and git trusts their names: a loose object or a pack replaced
        // under its name changes what main holds with no ref moved and nothing in the reflog. So a worktree's command
        // may add loose objects (a commit writes `tmp_obj_*` and links or renames it into place; `maintenance.lock` is
        // git's own) and nothing else: no unlinking, overwriting or renaming over what's there, no symlinks planted
        // under an object's name, and (above) nothing in `pack` or `info`, since a new pack is searched before the
        // old ones and `info/alternates` would point git elsewhere. `git repack`, `gc` and `prune` fail there and say so.
        let objectDeny = linkedGit ? #"""
            (deny file-write-unlink file-write-data file-write-mode file-write-owner file-write-times file-write-xattr file-write-flags file-write-setugid (with message (param "TAG"))
                (require-all (subpath (string-append (param "COMMONGIT") "/objects")) (require-not (regex #"/(tmp_obj_[^/]*|maintenance\.lock)$"))))
            (deny file-write-create (with message (param "TAG"))
                (require-all (subpath (string-append (param "COMMONGIT") "/objects")) (vnode-type SYMLINK)))
            """# : ""
        return """
            (version 1)
            (allow default)
            (deny file-write* (with message (param "TAG")))
            (allow file-write*
                (subpath (param "WORKSPACE"))
                \(linkedAllow)
                (subpath (param "TMPDIR"))
                (subpath (param "CACHEDIR"))
                (subpath "/private/tmp")
                (subpath "/private/var/tmp")
                \(extras)
                (literal "/dev/null") (literal "/dev/zero") (literal "/dev/tty") (literal "/dev/dtracehelper")
                (regex #"^/dev/fd/[0-9]+$") (regex #"^/dev/ttys[0-9]+$"))
            (deny file-write* (with message (param "TAG"))
                \(repositoryGuards(#"(param "WORKSPACE")"#))
                \(linkedDeny)
                \(gitGuards) \(readOnly))
            (deny file-write-unlink (with message (param "TAG")) \(linkedGit ? #"(literal (param "GITDIR"))"# : "") \(pinned))
            \(objectDeny)
            (deny user-preference-write (with message (param "TAG")))
            (deny appleevent-send (with message (param "TAG")))
            \(allowNetwork ? "" : #"(deny network* (with message (param "TAG")))"#)\(unreadableRules)
            """
    }

    /// `path` and every folder above it.
    static func withAncestors(_ path: String) -> [String] {
        var out = [path], p = path as NSString
        while p.length > 1 {
            p = p.deletingLastPathComponent as NSString
            out.append(p as String)
        }
        return out
    }

    /// `argv` wrapped to run in the sandbox. `tag` marks this command's denials in the system log.
    public func wrap(_ argv: [String], workspace: URL, tag: String) -> [String] {
        let extras = extraWritable.map { Self.realPath(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
        var params: [(String, String)] = [
            ("WORKSPACE", Self.realPath(workspace)),
            ("TMPDIR", Self.realPath(URL(fileURLWithPath: Self.darwinDir(_CS_DARWIN_USER_TEMP_DIR) ?? NSTemporaryDirectory()))),
            ("CACHEDIR", Self.realPath(URL(fileURLWithPath: Self.darwinDir(_CS_DARWIN_USER_CACHE_DIR) ?? NSTemporaryDirectory()))),
            ("TAG", tag),
        ]
        for (i, p) in extras.enumerated() { params.append(("EXTRA\(i)", p)) }
        let readOnlyPaths = readOnly.map { Self.realPath(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
        for (i, p) in readOnlyPaths.enumerated() { params.append(("READONLY\(i)", p)) }
        // Plan mode's project is read-only, so its repository must be too.
        let linked = readOnlyPaths.contains(Self.realPath(workspace)) ? nil : LinkedGit.of(workspace)
        if let linked { params += [("COMMONGIT", linked.common), ("GITDIR", linked.gitDir)] }
        let pinned = Set(([Self.realPath(workspace)] + extras + readOnlyPaths).flatMap(Self.withAncestors)).sorted()
        for (i, p) in pinned.enumerated() { params.append(("PINNED\(i)", p)) }
        return [Self.executable, "-p", Self.profile(extraCount: extras.count, readOnlyCount: readOnlyPaths.count, pinnedCount: pinned.count,
                                                         allowNetwork: allowNetwork, unreadable: unreadable, linkedGit: linked != nil)]
            + params.flatMap { ["-D", "\($0.0)=\($0.1)"] } + argv
    }

    /// Variables a sandboxed command needs added to `env`: a toolchain cache whose default home the sandbox can't
    /// write, pointed into the per-user cache folder it can, unless `env` already sets it. Go keeps its build cache in
    /// ~/Library/Caches/go-build and stops at once without it ("failed to initialize build cache"). It isn't shared
    /// with the user's own cache, which their unsandboxed builds would then trust.
    public static func cacheVariables(for env: [String: String]) -> [String: String] {
        guard let cache = darwinDir(_CS_DARWIN_USER_CACHE_DIR) else { return [:] }
        let base = URL(fileURLWithPath: realPath(URL(fileURLWithPath: cache))).appending(path: "kurtkode")
        var add: [String: String] = [:]
        if env["GOCACHE"] == nil { add["GOCACHE"] = base.appending(path: "go-build").path }
        return add
    }

    /// The path with every symlink resolved (URL's own resolving drops /private, which the sandbox needs).
    static func realPath(_ url: URL) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buf) != nil else { return url.standardizedFileURL.path }
        return string(buf)
    }

    static func darwinDir(_ name: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buf, buf.count) > 0 else { return nil }
        return string(buf)
    }

    /// A NUL-terminated C buffer as a String.
    static func string(_ buf: [CChar]) -> String {
        String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// What the sandbox blocked for the command tagged `tag`, from the system log, as short lines
    /// ("write ~/Library/Caches/x", "network"). Device writes (/dev/…) are left out: shells probe those.
    public static func denials(tag: String, since start: Date) async -> [String] {
        let fmt = DayFormat.formatter("yyyy-MM-dd HH:mm:ss", zone: .current)
        let args = ["show", "--start", fmt.string(from: start.addingTimeInterval(-1)), "--style", "compact",
                    "--predicate", "eventMessage CONTAINS \"\(tag)\""]
        let collector = OutputCollector(headLimit: 200_000, tailLimit: 0)
        _ = try? await Subprocess.run(["/usr/bin/log"] + args, cwd: "/", environment: ["PATH": "/usr/bin:/bin"],
                                      timeout: 15) { collector.append($0) }
        return parseDenials(String(decoding: collector.parts().0, as: UTF8.self))
    }

    static func parseDenials(_ log: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var seen = Set<String>(), out: [String] = []
        for line in log.split(separator: "\n") {
            guard let r = line.range(of: "deny(1) ") else { continue }
            let rest = line[r.upperBound...].split(separator: " ", maxSplits: 1).map(String.init)
            guard let op = rest.first else { continue }
            var item: String
            if op.hasPrefix("file-write") {
                guard rest.count > 1 else { continue }
                var path = rest[1].trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("/dev/") { continue }
                if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
                item = "write " + path
            } else if op.hasPrefix("network") {
                item = "network"
            } else {
                item = op
            }
            if seen.insert(item).inserted { out.append(item) }
        }
        return out
    }
}

/// The repository folders a worktree kurtkode made needs to write. Found from where the worktree is, not from what its
/// `.git` file says: commands in the sandbox can write that file, and it mustn't be able to name a folder to open up.
/// So only `<repository>/.worktrees/<name>` qualifies, and it gets only `<repository>/.git`, with the link checked both ways.
struct LinkedGit: Equatable {
    var common: String
    var gitDir: String

    static func of(_ workspace: URL) -> LinkedGit? {
        let path = SandboxPolicy.realPath(workspace)
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let parent = root.deletingLastPathComponent()
        guard parent.lastPathComponent == GitRepo.worktreeFolder else { return nil }
        let common = parent.deletingLastPathComponent().appending(path: ".git").path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: common, isDirectory: &isDir), isDir.boolValue,
              let pointer = try? String(contentsOfFile: path + "/.git", encoding: .utf8), pointer.hasPrefix("gitdir: ") else { return nil }
        let named = pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDir = SandboxPolicy.realPath(URL(fileURLWithPath: named))
        guard gitDir.hasPrefix(SandboxPolicy.realPath(URL(fileURLWithPath: common)) + "/worktrees/"),
              let back = try? String(contentsOfFile: gitDir + "/gitdir", encoding: .utf8),
              SandboxPolicy.realPath(URL(fileURLWithPath: back.trimmingCharacters(in: .whitespacesAndNewlines))) == path + "/.git" else { return nil }
        return LinkedGit(common: SandboxPolicy.realPath(URL(fileURLWithPath: common)), gitDir: gitDir)
    }
}

/// When commands run in the sandbox (a setting).
public enum SandboxUse: String, Codable, Sendable, CaseIterable {
    case fullAuto, always, never

    public var displayName: String {
        switch self {
        case .fullAuto: "In Full Auto"
        case .always: "Always"
        case .never: "Never"
        }
    }

    /// The policy for a run in `mode`, or nil for no sandbox (also when sandbox-exec is missing).
    public func policy(for mode: PermissionMode, _ policy: SandboxPolicy) -> SandboxPolicy? {
        guard SandboxPolicy.isAvailable else { return nil }
        switch self {
        case .never: return nil
        case .always: return policy
        case .fullAuto: return mode == .fullAuto ? policy : nil
        }
    }
}

extension SandboxPolicy {
    /// What the model is told about the sandbox, in the system prompt.
    public var promptText: String {
        "Commands run in a sandbox: they can write only inside the project and temp directories"
            + (allowNetwork ? "" : ", and have no network (so no package installs or downloads)")
            + ". If a task needs more than that, tell the user instead of working around it."
    }
}
