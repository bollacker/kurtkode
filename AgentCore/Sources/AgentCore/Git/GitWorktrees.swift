import Foundation

/// Worktrees: a second checkout of the repository on its own branch, so a session or a subagent can change files without
/// touching the ones another is using. kurtkode's live in `<repository>/.worktrees/<name>`, on a branch `kk/<name>`,
/// and git is told to ignore the folder (in `.git/info/exclude`, so no tracked file changes).
extension GitRepo {
    public static let worktreeFolder = ".worktrees"
    public static let branchPrefix = "kk/"

    public struct Worktree: Sendable, Hashable, Identifiable {
        public var path: String
        public var branch: String?
        public var head: String
        /// The repository's main checkout.
        public var isMain: Bool
        public var id: String { path }
        public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    /// `git worktree list --porcelain`: blocks of `worktree`, `HEAD`, `branch refs/heads/x` or `detached`. The first is
    /// the main checkout.
    static func parseWorktrees(_ text: String) -> [Worktree] {
        var out: [Worktree] = []
        for block in text.components(separatedBy: "\n\n") {
            var path: String?, head = "", branch: String?
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
                else if line.hasPrefix("branch ") { branch = line.dropFirst(7).replacingOccurrences(of: "refs/heads/", with: "") }
            }
            if let path { out.append(Worktree(path: path, branch: branch, head: head, isMain: out.isEmpty)) }
        }
        return out
    }

    public func worktrees() async throws -> [Worktree] {
        Self.parseWorktrees(try await git(["worktree", "list", "--porcelain"]))
    }

    /// This checkout is a worktree of another, not the repository's main one.
    public var isLinkedWorktree: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.appending(path: ".git").path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// The main checkout, from it or from any of its worktrees.
    public func mainRoot() async throws -> URL {
        guard let first = try await worktrees().first else { throw Failure(message: "This isn't a git repository.") }
        return URL(fileURLWithPath: first.path, isDirectory: true)
    }

    /// A name that's safe as a folder and a branch: letters, digits, `-`, `_`, `.`; spaces become dashes. Nil if nothing's left.
    public static func worktreeName(_ typed: String) -> String? {
        var name = typed.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        name = String(name.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        while let f = name.first, ".-".contains(f) { name.removeFirst() }
        while let l = name.last, ".-".contains(l) { name.removeLast() }
        name = name.replacingOccurrences(of: "..", with: ".")
        return name.isEmpty ? nil : name
    }

    /// The worktree called `name`, made from `base` (default: what's checked out here) if it isn't there yet.
    public func addWorktree(name typed: String, base: String? = nil) async throws -> Worktree {
        guard let name = Self.worktreeName(typed) else { throw Failure(message: "\(typed) can't be a worktree's name.") }
        let main = GitRepo(root: try await mainRoot())
        let folder = main.root.appending(path: Self.worktreeFolder).appending(path: name)
        if let found = try await main.worktrees().first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == folder.standardizedFileURL.path }) {
            return found
        }
        try main.excludeWorktrees()
        let branch = Self.branchPrefix + name
        let exists = (try? await main.git(["rev-parse", "--verify", "--quiet", "refs/heads/" + branch])) != nil
        // HEAD here, which may be a worktree's: it runs in the main checkout, where "HEAD" would be that one's.
        var start = base
        if start == nil { start = try await git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) }
        _ = try await main.git(["worktree", "add", "--quiet"] + (exists ? [folder.path, branch] : ["-b", branch, folder.path, start ?? "HEAD"]))
        guard let made = try await main.worktrees().first(where: { $0.branch == branch }) else {
            throw Failure(message: "git made no worktree for \(branch).")
        }
        return made
    }

    /// Keeps the worktrees folder out of `git status`, without changing a tracked file.
    func excludeWorktrees() throws {
        let info = root.appending(path: ".git/info")
        let file = info.appending(path: "exclude")
        let line = "/\(Self.worktreeFolder)/"
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard !text.split(whereSeparator: \.isNewline).contains(where: { $0 == line }) else { return }
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try (text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + line + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// What's in a worktree that its removal could lose: files not committed, files git ignores (a copied `.env`, a
    /// local database: `worktree remove --force` deletes them without a word), and commits on no other branch. Compared
    /// whole, not by counts, so a change since the user was told is seen.
    public struct WorktreeState: Sendable, Hashable {
        /// Paths of the status entries (modified, untracked, …).
        public var uncommittedFiles: [String]
        /// Paths of the ignored files, an ignored folder as one entry ("node_modules/").
        public var ignoredFiles: [String]
        /// The commits reachable from the worktree's branch (or detached HEAD) and from no branch.
        public var unmergedCommits: [String]

        public var uncommitted: Int { uncommittedFiles.count }
        public var ignored: Int { ignoredFiles.count }
        public var unmerged: Int { unmergedCommits.count }
        /// Everything removal deletes, uncommitted files first.
        public var lostFiles: [String] { uncommittedFiles + ignoredFiles }

        /// Up to `limit` of the lost files' names, for a confirmation.
        public func lostNames(limit: Int = 8) -> String {
            lostFiles.prefix(limit).joined(separator: ", ") + (lostFiles.count > limit ? ", …" : "")
        }
    }

    public func worktreeState(_ w: Worktree) async throws -> WorktreeState {
        let repo = GitRepo(root: URL(fileURLWithPath: w.path, isDirectory: true))
        let files = try await repo.status().files.map(\.path)
        let ignored = try await repo.git(["ls-files", "-z", "-o", "-i", "--exclude-standard", "--directory"])
            .split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        // A detached HEAD's commits are on no branch at all.
        let others = try await git(["for-each-ref", "--format=%(refname)", "refs/heads"]).split(separator: "\n")
            .filter { w.branch == nil || $0 != "refs/heads/" + w.branch! }.map { "^" + $0 }
        let commits = try await git(["rev-list", w.branch ?? w.head] + others).split(separator: "\n").map(String.init)
        return WorktreeState(uncommittedFiles: files, ignoredFiles: ignored, unmergedCommits: commits)
    }

    /// Removal once the user has been told `told` about it: if the worktree has changed since, nothing happens and what
    /// it holds now comes back, to ask again. Their yes was to losing what they saw.
    public func removeWorktree(_ w: Worktree, told: WorktreeState, deleteBranch: Bool) async throws -> WorktreeState? {
        guard let now = try await worktrees().first(where: { $0.path == w.path }) else { return nil }
        let state = try await worktreeState(now)
        guard state == told else { return state }
        try await removeWorktree(now, force: true, deleteBranch: deleteBranch)
        return nil
    }

    /// Takes the worktree away. Git refuses if it has uncommitted files, unless `force`; so does this for files git
    /// ignores, which git would delete without a word. Its branch can go with it.
    public func removeWorktree(_ w: Worktree, force: Bool = false, deleteBranch: Bool = false) async throws {
        guard !w.isMain else { throw Failure(message: "The main checkout isn't a worktree to remove.") }
        if !force {
            let state = try await worktreeState(w)
            if state.ignored > 0 {
                throw Failure(message: "\(w.name) has \(state.ignored) ignored file\(state.ignored == 1 ? "" : "s") that removing would delete: "
                              + state.lostNames() + ". Add --force to lose \(state.ignored == 1 ? "it" : "them").")
            }
        }
        let main = GitRepo(root: try await mainRoot())
        _ = try await main.git(["worktree", "remove"] + (force ? ["--force"] : []) + [w.path])
        if deleteBranch, let b = w.branch { _ = try await main.git(["branch", "-D", b]) }
    }

    // MARK: Branches

    public struct Branch: Sendable, Hashable, Identifiable {
        public var name: String
        public var isCurrent: Bool
        public var upstream: String?
        public var id: String { name }
    }

    /// Local branches, most recently committed first.
    public func branches() async throws -> [Branch] {
        let out = try await git(["for-each-ref", "--sort=-committerdate", "--format=%(HEAD)%00%(refname:short)%00%(upstream:short)", "refs/heads"])
        return out.split(separator: "\n").map { line in
            let f = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            return Branch(name: f.count > 1 ? f[1] : "", isCurrent: f.first == "*", upstream: f.count > 2 && !f[2].isEmpty ? f[2] : nil)
        }
    }

    public func switchBranch(_ name: String) async throws { _ = try await git(["switch", "--quiet", name]) }
    public func createBranch(_ name: String) async throws { _ = try await git(["switch", "--quiet", "-c", name]) }

    /// `origin`'s default branch, else `main` or `master` if there is one.
    public func defaultBranch() async -> String? {
        if let head = try? await git(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]) {
            let name = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name.split(separator: "/", maxSplits: 1).last.map(String.init) }
        }
        for name in ["main", "master"] where (try? await git(["rev-parse", "--verify", "--quiet", "refs/heads/" + name])) != nil {
            return name
        }
        return nil
    }

    /// Merges `branch` into what's checked out here, which must be `expected` if that's given: a button's label comes from
    /// its last refresh. If it can't be done cleanly nothing is left half done: the merge is undone and the reason thrown.
    /// A merge already open is the user's, with their resolutions in it, so that's left alone and nothing starts.
    public func merge(_ branch: String, into expected: String? = nil) async throws {
        if let expected {
            let now = try await status().branch
            guard now == expected else { throw Failure(message: "The main checkout is on \(now ?? "no branch") now, not \(expected). Nothing was merged.") }
        }
        guard (try? await git(["rev-parse", "--verify", "--quiet", "MERGE_HEAD"])) == nil else {
            throw Failure(message: "A merge is already open there. Finish it or abort it first.")
        }
        do { _ = try await git(["merge", "--no-edit", branch]) } catch {
            _ = try? await git(["merge", "--abort"])
            throw error
        }
    }

    // MARK: Stash

    public struct Stash: Sendable, Hashable, Identifiable {
        /// Its position, as `stash@{1}`: a new stash moves every other one along.
        public var ref: String
        public var hash: String
        public var message: String
        public var id: String { hash }
    }

    public func stashes() async throws -> [Stash] {
        try await git(["stash", "list", "--format=%gd%x00%H%x00%s"]).split(separator: "\n").map { line in
            let f = line.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            return Stash(ref: f[0], hash: f.count > 1 ? f[1] : "", message: f.count > 2 ? f[2] : "")
        }
    }

    /// Where the stash is now. Another session can stash between the list being shown and the click.
    private func position(of s: Stash) async throws -> String {
        guard let found = try await stashes().first(where: { $0.hash == s.hash }) else { throw Failure(message: "That stash is gone.") }
        return found.ref
    }

    /// Puts the changes aside, new files too.
    public func stash(message: String = "") async throws {
        _ = try await git(["stash", "push", "--quiet", "--include-untracked"] + (message.isEmpty ? [] : ["-m", message]), literalPaths: false)
    }

    public func stashPop(_ s: Stash) async throws { _ = try await git(["stash", "pop", "--quiet", try await position(of: s)]) }
    /// Applies the stash and keeps it (`stashPop` drops it once it applies).
    public func stashApply(_ s: Stash) async throws { _ = try await git(["stash", "apply", "--quiet", try await position(of: s)]) }
    public func stashDrop(_ s: Stash) async throws { _ = try await git(["stash", "drop", "--quiet", try await position(of: s)]) }

    // MARK: Remotes

    public func pull() async throws { _ = try await git(["pull", "--ff-only", "--quiet"]) }

    /// Pushes the branch, setting its upstream the first time.
    public func push(_ s: Status) async throws {
        guard let branch = s.branch else { throw Failure(message: "A detached HEAD has no branch to push.") }
        _ = try await git(s.upstream == nil ? ["push", "--quiet", "--set-upstream", "origin", branch] : ["push", "--quiet"])
    }

    public func remoteURL() async -> String? {
        (try? await git(["remote", "get-url", "origin"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The page that opens a pull request for `branch` on GitHub, or a merge request on GitLab. Nil for other remotes.
    /// Anything between the scheme and the host (a token in the URL) stays out of what's opened.
    public static func compareURL(remote: String, branch: String, base: String?) -> URL? {
        var host: String, path: String
        if remote.contains("://"), let u = URL(string: remote), let h = u.host() {
            host = h
            path = u.path()
        } else if let at = remote.firstIndex(of: "@"), let colon = remote.firstIndex(of: ":"), at < colon {
            host = String(remote[remote.index(after: at)..<colon])
            path = String(remote[remote.index(after: colon)...])
        } else {
            return nil
        }
        host = host.lowercased()
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !path.isEmpty else { return nil }
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        if host.contains("github") {
            return URL(string: "https://\(host)/\(path)/compare/\(base.map { $0 + "..." } ?? "")\(encoded)?expand=1")
        }
        if host.contains("gitlab") {
            return URL(string: "https://\(host)/\(path)/-/merge_requests/new?merge_request%5Bsource_branch%5D=\(encoded)")
        }
        return nil
    }

    // MARK: Diffs

    /// What a change is measured against.
    public enum DiffBase: Hashable, Sendable {
        /// The last commit: everything not committed yet, new files included.
        case uncommitted
        /// Where this branch left `name`: all its work, committed or not.
        case branch(String)
    }

    private func ref(_ base: DiffBase) async throws -> String {
        switch base {
        case .uncommitted: return "HEAD"
        case .branch(let name):
            return try await git(["merge-base", "HEAD", name]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The files that differ from `base` in the working tree, with their line counts.
    public func changes(_ base: DiffBase) async throws -> [ProjectSnapshots.Change] {
        let target = try await ref(base)
        let names = try await git(["diff", "--no-ext-diff", "-M", "-z", "--name-status", target]).split(separator: "\0").map(String.init)
        var out: [ProjectSnapshots.Change] = []
        var i = 0
        while i + 1 < names.count {
            let status = names[i]
            if status.hasPrefix("R"), i + 2 < names.count {
                out.append(.init(path: names[i + 2], oldPath: names[i + 1], kind: .renamed))
                i += 3
                continue
            }
            let kind: ProjectSnapshots.Change.Kind = switch status.first {
            case "A": .added
            case "D": .deleted
            case "T": .typeChanged
            default: .modified
            }
            out.append(.init(path: names[i + 1], oldPath: nil, kind: kind))
            i += 2
        }
        for k in out.indices {
            let line = try await git(["diff", "--no-ext-diff", "-M", "--numstat", target, "--"] + out[k].paths)
            let f = line.split(whereSeparator: \.isNewline).last?.split(separator: "\t", maxSplits: 2).map(String.init) ?? []
            if f.count >= 2 {
                out[k].additions = Int(f[0])
                out[k].deletions = Int(f[1])
            }
        }
        let untracked = try await git(["ls-files", "--others", "--exclude-standard", "-z"]).split(separator: "\0").map(String.init)
        for path in untracked {
            let lines = (try? String(contentsOf: root.appending(path: path), encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: false).count
            out.append(.init(path: path, oldPath: nil, kind: .added, additions: lines.map { max(0, $0 - 1) }, deletions: lines == nil ? nil : 0))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// One file's unified diff against `base`; a new file's as all added.
    public func patch(_ base: DiffBase, change: ProjectSnapshots.Change) async throws -> String {
        let target = try await ref(base)
        let tracked = (try? await git(["ls-files", "--error-unmatch", "--", change.path])) != nil
        if !tracked, change.kind == .added {
            return try await git(["diff", "--no-index", "--", "/dev/null", change.path], okStatuses: [0, 1])
        }
        return try await git(["diff", "--no-ext-diff", "--no-color", "-M", target, "--"] + change.paths)
    }

    /// The whole change against `base`, for a commit message or a report; new files included.
    public func patch(_ base: DiffBase) async throws -> String {
        var parts: [String] = []
        for c in try await changes(base) { parts.append(try await patch(base, change: c)) }
        return parts.joined(separator: "\n")
    }

    /// The staged change, for a commit message.
    public func stagedDiff() async throws -> String { try await git(["diff", "--cached", "--no-ext-diff", "--no-color"]) }
}

/// A subagent's own worktree: a branch for its work, kept when it changed something and dropped when it didn't. The
/// worktree itself always goes when it's done, so they don't pile up; the branch holds what it did.
public struct IsolatedRun: Sendable {
    public let repo: GitRepo
    public let worktree: GitRepo.Worktree
    let start: String

    public var root: URL { URL(fileURLWithPath: worktree.path, isDirectory: true) }

    /// Fails without a repository with a commit: there's nothing to branch from.
    public static func start(from project: URL, id: UUID) async throws -> IsolatedRun {
        let repo = GitRepo(root: project)
        guard repo.exists else { throw GitRepo.Failure(message: "isolation needs the project to be a git repository") }
        let w = try await repo.addWorktree(name: "task-" + id.uuidString.prefix(8).lowercased())
        return IsolatedRun(repo: repo, worktree: w, start: w.head)
    }

    /// What the subagent is told about where it works.
    public var note: String {
        "[You work in your own git worktree, \(worktree.path), on the branch \(worktree.branch ?? "?"): a copy of the project at its "
            + "last commit, without any uncommitted changes. Use paths relative to it. Your changes are kept on that branch.]"
    }

    /// Commits what's left, takes the worktree away, and says what the parent can do with the branch. Git's hooks don't
    /// run: nothing here should run code the model may have written. Work that can't be kept on a branch keeps its
    /// worktree instead: removing one is the only step here that can lose anything.
    public func finish(title: String) async -> String {
        let here = GitRepo(root: root)
        let branch = worktree.branch ?? ""
        if (try? await here.status())?.files.isEmpty == false {
            _ = try? await here.git(["add", "-A"])
            let who = (try? await here.git(["config", "user.email"]))?.isEmpty == false ? [] : ["-c", "user.name=kurtkode", "-c", "user.email=kurtkode@localhost"]
            _ = try? await here.git(who + ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "--quiet", "--no-verify",
                                           "-m", title.isEmpty ? "Subagent work" : title])
        }
        let kept = "\n\n[Its work is still in its worktree, \(worktree.path): "
        guard let status = try? await here.status(), status.files.isEmpty else {
            return kept + "it couldn't be committed. Look at it there; `git worktree remove --force` drops it.]"
        }
        func revision(_ name: String) async -> String? {
            (try? await here.git(["rev-parse", "--verify", "--quiet", name]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let head = await revision("HEAD"), var tip = await revision("refs/heads/" + branch) else {
            return kept + "its branch \(branch) couldn't be read.]"
        }
        // Commits made on a detached HEAD belong on the branch, when that only moves it forward.
        if status.branch == nil, head != tip, (try? await here.git(["merge-base", "--is-ancestor", tip, head])) != nil,
           (try? await here.git(["update-ref", "refs/heads/" + branch, head, tip])) != nil { tip = head }
        let reachable = (try? await here.git(["for-each-ref", "--contains", head, "--format=%(refname)"]))?.isEmpty == false
        guard reachable else { return kept + "HEAD, \(head.prefix(8)), is on no branch.]" }
        let elsewhere = status.branch.flatMap { $0 != branch && head != start ? $0 : nil }
        let commits = (try? await here.git(["rev-list", "--count", start + ".." + tip]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = commits != "0"
        let stat = (try? await here.git(["diff", "--shortstat", start, tip]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? await repo.removeWorktree(worktree, force: true, deleteBranch: !changed)
        let also = elsewhere.map { " It also left commits on \($0)." } ?? ""
        guard changed else {
            return elsewhere.map { "\n\n[Its work is on the branch \($0), not merged. See it with `git diff HEAD...\($0)`.]" }
                ?? "\n\n[It worked in its own worktree and changed nothing, so that's gone.]"
        }
        return "\n\n[Its work is on the branch \(branch), not merged\(stat.isEmpty ? "" : ": " + stat). See it with `git diff HEAD...\(branch)`; bring it in "
            + "with `git merge \(branch)`, or drop it with `git branch -D \(branch)`. It started from the last commit, so it "
            + "doesn't have uncommitted changes.\(also)]"
    }
}

/// The review of a change, line by line, to send to the model.
public struct ReviewComment: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var path: String
    /// The line in the new file; nil for a removed line.
    public var line: Int?
    /// The line of the diff it's about.
    public var quote: String
    public var text: String

    public init(path: String, line: Int?, quote: String, text: String) {
        self.path = path
        self.line = line
        self.quote = quote
        self.text = text
    }

    /// A message for the model: each comment with where it's about, in file order.
    public static func message(_ comments: [ReviewComment]) -> String {
        var out = ["Review comments on the change. Look at each one and act on it:"]
        for c in comments.sorted(by: { ($0.path, $0.line ?? 0) < ($1.path, $1.line ?? 0) }) {
            out.append("\n\(c.path)" + (c.line.map { ":\($0)" } ?? " (a removed line)"))
            out.append("  > " + c.quote)
            out.append("  " + c.text.replacingOccurrences(of: "\n", with: "\n  "))
        }
        return out.joined(separator: "\n")
    }
}

extension UnifiedDiff {
    /// For each line of a hunk (its `@@` line first): the line's number in the new file. Nil for the header and removed lines.
    public static func newLineNumbers(_ hunk: [Substring]) -> [Int?] {
        var next: Int?
        return hunk.map { line in
            if line.hasPrefix("@@") {
                if let plus = line.split(separator: " ").first(where: { $0.hasPrefix("+") }) {
                    next = Int(plus.dropFirst().split(separator: ",").first ?? "")
                }
                return nil
            }
            guard let n = next, !line.hasPrefix("-"), !line.hasPrefix("\\") else { return nil }
            next = n + 1
            return n
        }
    }
}
