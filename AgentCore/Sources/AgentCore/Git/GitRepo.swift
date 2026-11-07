import Foundation

/// The git operations behind the Git panel: status, diffs, staging, discarding, committing. The user
/// runs these (the agent uses bash), so they aren't sandboxed or approved.
public struct GitRepo: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var exists: Bool { FileManager.default.fileExists(atPath: root.appending(path: ".git").path) }

    /// On the command line of every git kurtkode runs itself, outside the sandbox, because a command in the sandbox can make
    /// a repository of its own in the project and `git add` it: git then runs that repository's `core.fsmonitor`, its own
    /// config, to see whether its files changed. A dirty check of a submodule is what starts it, so that's what's turned off.
    /// A folder that looks like a bare repository (no `.git` to find) counts only when it's named.
    static let safeConfig = ["-c", "core.fsmonitor=false", "-c", "diff.ignoreSubmodules=dirty", "-c", "submodule.recurse=false",
                             "-c", "safe.bareRepository=explicit"]

    /// The environment for git kurtkode runs itself. The caller's `GIT_*` variables are removed: a session started from
    /// a git hook or `git rebase -x` inherits `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` aimed at that other
    /// repository, and git would act on it. `keeping` names ones the user sets on purpose. Git never prompts or pages.
    static func environment(keeping: Set<String> = [], _ overrides: [String: String] = [:],
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("GIT_") || keeping.contains($0.key) }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        env.merge(overrides) { $1 }
        return env
    }

    /// What the Git panel's git keeps of the caller's `GIT_*`: how to reach remotes and which config files to read.
    static let keptVariables: Set<String> = ["GIT_SSH", "GIT_SSH_COMMAND", "GIT_SSH_VARIANT", "GIT_ASKPASS",
                                             "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_NOSYSTEM"]

    /// Commands that talk to a remote: they get longer to finish, and ssh mustn't ask for a passphrase.
    static let networkCommands: Set<String> = ["push", "pull", "fetch", "clone", "ls-remote"]

    /// How long a git command may run before it's stopped: a remote can be slow, and commits and merges run the
    /// repository's hooks; everything else is local and quick.
    static func timeout(for arguments: [String]) -> Double {
        let command = arguments.first ?? ""
        if networkCommands.contains(command) { return 120 }
        if ["commit", "merge", "stash"].contains(command) { return 300 }
        return 60
    }

    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// One changed path, from `git status`: X is the index (staged) side, Y the working tree.
    public struct FileChange: Sendable, Hashable, Identifiable {
        public var path: String
        /// The old path of a rename or copy.
        public var originalPath: String?
        public var index: Character
        public var worktree: Character
        public var id: String { path }

        public var isUntracked: Bool { index == "?" }
        public var isConflicted: Bool { index == "U" || worktree == "U" || (index == "A" && worktree == "A") || (index == "D" && worktree == "D") }
        public var isStaged: Bool { !isUntracked && !isConflicted && index != " " }
        public var isUnstaged: Bool { !isUntracked && !isConflicted && worktree != " " }

        /// One word for the change, from the side that matters most.
        public var kind: String {
            if isUntracked { return "new" }
            if isConflicted { return "conflict" }
            let c = worktree != " " ? worktree : index
            switch c {
            case "M": return "modified"
            case "A": return "added"
            case "D": return "deleted"
            case "R": return "renamed"
            case "C": return "copied"
            case "T": return "type changed"
            default: return String(c)
            }
        }
    }

    public struct Status: Sendable, Hashable {
        public var branch: String?
        public var upstream: String?
        public var ahead = 0
        public var behind = 0
        public var files: [FileChange] = []
        /// No commits yet.
        public var isNewRepository = false
    }

    public func status() async throws -> Status {
        let out = try await git(["status", "--porcelain=v1", "--branch", "-z", "--untracked-files=all"])
        return Self.parseStatus(out)
    }

    /// `git status --porcelain=v1 --branch -z`: a `## branch...upstream [ahead N, behind M]` entry, then
    /// `XY path` entries; a rename or copy is followed by its old path as its own entry.
    static func parseStatus(_ text: String) -> Status {
        var status = Status()
        var entries = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            if entry.hasPrefix("## ") {
                var head = String(entry.dropFirst(3))
                if let r = head.range(of: " [") {
                    let info = head[r.upperBound...].dropLast()
                    for part in info.split(separator: ",") {
                        let words = part.split(separator: " ")
                        if words.count == 2, let n = Int(words[1]) {
                            if words[0] == "ahead" { status.ahead = n } else if words[0] == "behind" { status.behind = n }
                        }
                    }
                    head = String(head[..<r.lowerBound])
                }
                if head.hasPrefix("No commits yet on ") {
                    status.isNewRepository = true
                    head = String(head.dropFirst("No commits yet on ".count))
                }
                let parts = head.components(separatedBy: "...")
                status.branch = parts[0] == "HEAD (no branch)" ? nil : parts[0]
                status.upstream = parts.count > 1 ? parts[1] : nil
                continue
            }
            let chars = Array(entry)
            guard chars.count > 3 else { continue }
            var change = FileChange(path: String(chars[3...]), originalPath: nil, index: chars[0], worktree: chars[1])
            if "RC".contains(change.index) || "RC".contains(change.worktree) { change.originalPath = entries.popFirst() }
            status.files.append(change)
        }
        return status
    }

    /// The change as a unified diff: against HEAD for a tracked file (staged and unstaged together); the
    /// whole file as added for an untracked one.
    public func diff(_ file: FileChange, isNewRepository: Bool = false) async throws -> String {
        if file.isUntracked {
            // --no-index exits 1 when the files differ, which here they always do.
            return try await git(["diff", "--no-index", "--", "/dev/null", file.path], okStatuses: [0, 1])
        }
        if isNewRepository {
            let staged = try await git(["diff", "--cached", "--", file.path])
            let unstaged = try await git(["diff", "--", file.path])
            return [staged, unstaged].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        var paths = [file.path]
        if let old = file.originalPath { paths.insert(old, at: 0) }
        return try await git(["diff", "-M", "HEAD", "--"] + paths)
    }

    public func stage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await git(["add", "--"] + paths)
    }

    public func stageAll() async throws {
        _ = try await git(["add", "-A"])
    }

    public func unstage(_ paths: [String], isNewRepository: Bool = false) async throws {
        guard !paths.isEmpty else { return }
        // Before the first commit there's no HEAD to restore from.
        _ = try await git(isNewRepository ? ["rm", "--cached", "-q", "--"] + paths : ["restore", "--staged", "--"] + paths)
    }

    /// Throws away the change: a tracked file goes back to HEAD (index and working tree); an untracked
    /// one is deleted.
    public func discard(_ file: FileChange) async throws {
        if file.isUntracked {
            try FileManager.default.removeItem(at: root.appending(path: file.path))
            return
        }
        if file.isConflicted {
            // Mid-merge: back to HEAD's version, or gone if HEAD doesn't have the file (added by the other side).
            if (try? await git(["cat-file", "-e", "HEAD:" + file.path])) != nil {
                _ = try await git(["restore", "--staged", "--worktree", "--source=HEAD", "--", file.path])
            } else {
                _ = try await git(["rm", "--cached", "-q", "--force", "--", file.path])
                try? FileManager.default.removeItem(at: root.appending(path: file.path))
            }
            return
        }
        if file.index == "A" {
            // Added in the index and not in HEAD: unstage it, then remove the file.
            _ = try await git(["rm", "--cached", "-q", "--", file.path])
            try? FileManager.default.removeItem(at: root.appending(path: file.path))
            return
        }
        var paths = [file.path]
        if let old = file.originalPath { paths.append(old) }
        _ = try await git(["restore", "--staged", "--worktree", "--source=HEAD", "--"] + paths)
    }

    /// Commits what's staged. Returns the new commit as "abc1234 subject".
    @discardableResult
    public func commit(message: String) async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(message: "The commit message is empty.") }
        _ = try await git(["commit", "-q", "-F", "-"], input: text)
        return try await lastCommit() ?? ""
    }

    public func lastCommit() async throws -> String? {
        let out = try? await git(["log", "-1", "--format=%h %s"])
        let line = out?.trimmingCharacters(in: .whitespacesAndNewlines)
        return line?.isEmpty == false ? line : nil
    }

    /// Runs git in the repository. Throws with git's own message (stderr) when it fails, or when it runs past `timeout`
    /// seconds (by default `timeout(for:)`): a remote waiting for a password nobody can type, say.
    func git(_ arguments: [String], input: String? = nil, okStatuses: Set<Int32> = [0], literalPaths: Bool = true,
             timeout: Double? = nil) async throws -> String {
        let root = root
        let limit = timeout ?? Self.timeout(for: arguments)
        var overrides: [String: String] = [:]
        // Paths are file names: `a[1].txt` mustn't also match a1.txt. (Not for `stash -u`, whose clean-up needs its own.)
        if literalPaths { overrides["GIT_LITERAL_PATHSPECS"] = "1" }
        // ssh would ask for a passphrase on the terminal (the CLI's own screen) and wait: make it fail instead, unless
        // the user chose how git runs ssh.
        if Self.networkCommands.contains(arguments.first ?? ""), ProcessInfo.processInfo.environment["GIT_SSH_COMMAND"] == nil,
           ProcessInfo.processInfo.environment["GIT_SSH"] == nil,
           (try? await git(["config", "--get", "core.sshCommand"], okStatuses: [0, 1]))?.isEmpty != false {
            overrides["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        let env = Self.environment(keeping: Self.keptVariables, overrides)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                p.arguments = ["-C", root.path] + Self.safeConfig + ["-c", "color.ui=never", "-c", "core.quotePath=false"] + arguments
                p.environment = env
                let out = Pipe(), err = Pipe(), inp = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = input == nil ? FileHandle.nullDevice : inp
                let exited: DispatchSemaphore
                do { exited = try p.startWithExitSignal() } catch { cont.resume(throwing: error); return }
                if let input {
                    let w = inp.inputForChild
                    DispatchQueue.global().async { try? w.write(contentsOf: Data(input.utf8)); try? w.close() }
                }
                // Both pipes are drained while git runs, so neither can fill up and stall it, and the wait for its exit
                // has a limit. A child git started (ssh) can keep the pipes open after git is stopped, so their reads get
                // only a little longer.
                let stdout = PipeDrain(out.fileHandleForReading), stderr = PipeDrain(err.fileHandleForReading)
                let started = Date()
                let status = p.waitForExit(exited, timeout: limit)
                let timedOut = Date().timeIntervalSince(started) >= limit
                let data = stdout.wait(timeout: timedOut ? 2 : nil) ?? Data()
                let errData = stderr.wait(timeout: timedOut ? 2 : nil) ?? Data()
                if timedOut {
                    let command = arguments.first ?? ""
                    cont.resume(throwing: Failure(message: "git \(command) took longer than \(Int(limit)) seconds and was stopped."
                        + (Self.networkCommands.contains(command) ? " If it was waiting for a password or passphrase, set up a "
                           + "credential helper or ssh-agent: kurtkode can't answer git's prompts." : "")))
                } else if okStatuses.contains(status) {
                    cont.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    let message = String(decoding: errData.isEmpty ? data : errData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: Failure(message: message.isEmpty ? "git \(arguments.first ?? "") failed (\(status))" : message))
                }
            }
        }
    }
}
