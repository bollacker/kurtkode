import Foundation

/// Commands that destroy work no checkpoint can bring back: they're always asked about, even in Full Auto (where the
/// sandbox keeps commands inside the project, not from wiping it) and even under an "always allow" for their first
/// words. A user's own allow rule naming the command (`Bash(git reset --hard:*)`) still lets it through.
public enum DangerousCommands {
    /// Why `command` is dangerous, in words, or nil. `roots`: the folders the agent works in (deleting inside them is
    /// ordinary; deleting the folder itself, the home folder, or `/` isn't). `allowed`: whether a command in the line
    /// (its words as `ShellSplit` gives them) is let through despite these reasons, by a rule naming them.
    public static func reason(_ command: String, roots: [String] = [],
                              allowed: (_ words: [String], _ reasons: [String]) -> Bool = { _, _ in false }) -> String? {
        let whole = command.lowercased()
        // Downloading a script and running it.
        if whole.range(of: #"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z|da|fi)?sh\b"#, options: .regularExpression) != nil {
            return "runs a downloaded script"
        }
        // Every command the line runs (inside `$( )`, `sh -c '…'` and the like too), without wrappers or a path. After
        // a `cd` out of the project, a relative path is outside it too.
        var away: String?
        for words in ShellSplit.commands(command) {
            let found = reasons(words, roots: roots, after: away)
            if let first = found.first, !allowed(words, found) { return first }
            away = afterCD(ShellSplit.unwrap(words), roots: roots, away: away)
        }
        return nil
    }

    /// Every reason one simple command (as `ShellSplit.commands` gives it) is dangerous, most telling first. `after`:
    /// the `cd` target, when an earlier command on the line left the project.
    static func reasons(_ words: [String], roots: [String], after away: String? = nil) -> [String] {
        // What can't be read is asked about: it could be anything.
        if let why = ShellSplit.opaqueReason(words) { return ["runs something kurtkode can't check: \(why)"] }
        var found: [String] = []
        let real = ShellSplit.unwrap(words)
        if words.prefix(max(0, words.count - real.count)).contains(where: { ["sudo", "doas"].contains(ShellSplit.basename($0)) }) {
            found.append("runs as root (sudo)")
        }
        guard let cmd = real.first else { return found }
        let args = Array(real.dropFirst())
        if let why = gitReason(cmd, args) { found.append(why) }
        found += deleteReasons(cmd, args, roots: roots, after: away)
        switch cmd {
        case "dd" where args.contains { $0.hasPrefix("of=") }: found.append("writes raw data to a file or device (dd)")
        case "mkfs", "newfs", "fdisk": found.append("formats or partitions a disk")
        case "diskutil" where args.contains { ["erasedisk", "erasevolume", "partitiondisk", "zerodisk"].contains($0.lowercased()) }:
            found.append("erases or partitions a disk")
        case "shutdown", "reboot", "halt": found.append("shuts down or restarts the Mac")
        case "find" where args.contains("-delete") || ShellSplit.findCommands(real).contains { ["rm", "rmdir", "unlink", "shred", "srm"].contains(ShellSplit.unwrap($0).first ?? "") }:
            found.append("deletes the files find matches")
        case let c where (c == "chmod" || c == "chown") && args.contains("-R") && targetsOutside(args, roots: roots):
            found.append("changes permissions recursively outside the project")
        default: break
        }
        return found
    }

    /// Where a line is after `words`: the `cd` target that left the project, nil while inside it.
    static func afterCD(_ words: [String], roots: [String], away: String?) -> String? {
        guard let cmd = words.first, cmd == "cd" || cmd == "pushd" else { return away }
        let target = words.dropFirst().first { !$0.hasPrefix("-") || $0 == "-" } ?? "~"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = (target.replacingOccurrences(of: "${HOME}", with: home).replacingOccurrences(of: "$HOME", with: home)
                        as NSString).expandingTildeInPath
        if target == "-" || expanded.contains("$") || expanded.contains("`") { return target }   // can't tell where
        if expanded.hasPrefix("/") {
            return isTemporary(expanded + "/") || roots.contains(where: { expanded == $0 || expanded.hasPrefix($0 + "/") }) ? nil : target
        }
        return away ?? (climbs(expanded) ? target : nil)
    }

    /// Whether a relative path leads above where it starts (`..`, `build/../..`), or is that folder itself (`a/..`).
    static func climbs(_ path: String, orStays: Bool = false) -> Bool {
        var depth = 0
        for part in path.split(separator: "/") where part != "." {
            depth += part == ".." ? -1 : 1
            if depth < 0 { return true }
        }
        return orStays && depth == 0
    }

    /// Why deleting with `cmd args` is dangerous: each target that's the home folder, `/`, the project or outside it
    /// (also a relative one after a `cd` out of the project), or, deleted recursively, computed when the command runs.
    static func deleteReasons(_ cmd: String, _ args: [String], roots: [String], after away: String? = nil) -> [String] {
        guard cmd == "rm" || cmd == "rmdir" || cmd == "trash" else { return [] }
        let flags = args.filter { $0.hasPrefix("-") }.joined()
        let recursive = cmd == "rm" && (flags.contains("r") || flags.contains("R") || args.contains("--recursive"))
        let targets = args.filter { !$0.hasPrefix("-") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [String] = []
        for t in targets {
            let bare = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if ["/", "/*", "~", "~/", "~/*", "$HOME", "$HOME/", "${HOME}", "*", ".", "./", "..", "../", "/Users", "/System", "/Applications"]
                .contains(bare) || bare.hasPrefix("../") {
                found.append("deletes \(bare)")
                continue
            }
            guard recursive else { continue }
            let expanded = (bare.replacingOccurrences(of: "${HOME}", with: home).replacingOccurrences(of: "$HOME", with: home)
                            as NSString).expandingTildeInPath
            if expanded.contains("$") || expanded.contains("`") {
                found.append("deletes a path computed when it runs (\(bare))")
            } else if expanded.hasPrefix("/") {
                if roots.contains(expanded) { found.append("deletes the project folder") }
                else if !isTemporary(expanded), !roots.contains(where: { expanded.hasPrefix($0 + "/") }) {
                    found.append("deletes a folder outside the project (\(bare))")
                }
            } else if let away {
                found.append("deletes a folder outside the project (\(bare), after cd \(away))")
            } else if climbs(expanded, orStays: true) {
                found.append("deletes \(bare)")
            }
        }
        return found
    }

    /// Whether an allow rule names a dangerous command itself (`Bash(git reset --hard:*)`): only such a rule lets one
    /// run without asking; a broad one (`Bash(git:*)`) doesn't.
    public static func ruleNamesDanger(_ specifier: String) -> Bool { !reasons(named: specifier).isEmpty }

    /// Every reason the command an allow rule names (`git reset --hard:*`) is dangerous.
    static func reasons(named specifier: String, roots: [String] = []) -> [String] {
        var s = specifier
        if s.hasSuffix(":*") { s = String(s.dropLast(2)) }
        s = s.replacingOccurrences(of: "*", with: " ")
        var found: [String] = []
        if let whole = reason(s, roots: roots), whole == "runs a downloaded script" { found.append(whole) }
        var away: String?
        for words in ShellSplit.commands(s) {
            found += reasons(words, roots: roots, after: away)
            away = afterCD(ShellSplit.unwrap(words), roots: roots, away: away)
        }
        return found
    }

    static func gitReason(_ cmd: String, _ args: [String]) -> String? {
        guard cmd == "git" else { return nil }
        // Skip global options (`git -C dir …`).
        var rest = args[...]
        while let a = rest.first, a.hasPrefix("-") {
            rest = rest.dropFirst()
            if ["-C", "-c", "--git-dir", "--work-tree"].contains(a) { rest = rest.dropFirst() }
        }
        guard let sub = rest.first else { return nil }
        let opts = Array(rest.dropFirst())
        switch sub {
        case "reset" where opts.contains("--hard"): return "discards uncommitted changes (git reset --hard)"
        case "clean" where opts.contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("f") } || opts.contains("--force"):
            return "deletes untracked files (git clean)"
        case "checkout" where opts.contains("--") || opts.contains(".") || opts.contains("-f") || opts.contains("--force"):
            return "discards changes to files (git checkout)"
        case "restore" where !opts.contains("--staged") || opts.contains("--worktree"): return "discards changes to files (git restore)"
        case "push" where opts.contains { ["-f", "--force", "--force-with-lease", "--mirror", "--delete", "-d"].contains($0)
                                         || $0.hasPrefix("--force") || $0.hasPrefix("+") || $0.hasPrefix(":") }:
            return "rewrites or deletes history on the remote (git push --force / --delete)"
        case "branch" where opts.contains("-D") || (opts.contains("-d") && opts.contains("--force")): return "deletes a branch (git branch -D)"
        case "stash" where opts.first == "drop" || opts.first == "clear": return "deletes stashed changes (git stash \(opts[0]))"
        case "filter-branch", "filter-repo": return "rewrites the repository's history"
        case "update-ref" where opts.contains("-d"): return "deletes a reference (git update-ref -d)"
        case "rebase" where opts.contains("--onto") && opts.contains("--root"): return "rewrites the whole history (git rebase --root)"
        default: return nil
        }
    }

    static func targetsOutside(_ args: [String], roots: [String]) -> Bool {
        args.filter { !$0.hasPrefix("-") }.dropFirst().contains { a in
            let p = (a as NSString).expandingTildeInPath
            return p.hasPrefix("/") && !roots.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) || a == "~" || a == "/"
        }
    }

    static func isTemporary(_ path: String) -> Bool {
        ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"].contains { path.hasPrefix($0) }
            || path.hasPrefix(NSTemporaryDirectory())
    }
}
