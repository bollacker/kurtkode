import AgentCore
import Darwin
import Foundation

/// The commands only the terminal has, beside the shared `SlashCommands.builtIns`.
public enum CLICommands {
    public static let all: [SlashCommand] = [
        SlashCommand(name: "status", description: "Show the session, model, mode, context and spending"),
        SlashCommand(name: "resume", description: "List this project's sessions, or go on with one", argumentHint: "[N | id]"),
        SlashCommand(name: "copy", description: "Copy the last reply to the clipboard"),
        SlashCommand(name: "export", description: "Save the conversation as Markdown", argumentHint: "[file]"),
        SlashCommand(name: "worktrees", description: "List this project's worktrees"),
    ]

    public static var names: [String] { all.map(\.name) + ["exit"] }
}

/// `kurtkode endpoint` and `kurtkode doctor`: setting up without the app.
public enum SetupCommands {
    public static let names: Set<String> = ["endpoint", "doctor", "worktree"]

    static let endpointUsage = """
        kurtkode endpoint list
        kurtkode endpoint add NAME URL [--key-env VARIABLE | --no-key]
        kurtkode endpoint remove NAME

        add saves a server the app and the command line share. Its API key is read from VARIABLE, or asked for at the
        terminal without showing it, and kept in the Keychain; never on the command line. A local server needs --no-key.
        """

    public static func run(_ arguments: [String], settings: AppSettings, readKey: (String) -> String? = readHidden,
                           saveKey: (String, UUID) throws -> Void = { try KeychainStore().setAPIKey($0, for: $1) },
                           out: (String) -> Void) async -> Int32 {
        switch arguments.first {
        case "doctor": return await doctor(settings: settings, out: out)
        case "worktree": return await worktree(Array(arguments.dropFirst()), folder: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), out: out)
        default: return endpoint(Array(arguments.dropFirst()), settings: settings, readKey: readKey, saveKey: saveKey, out: out)
        }
    }

    // MARK: worktree

    static let worktreeUsage = """
        kurtkode worktree list
        kurtkode worktree remove NAME [--force] [--delete-branch]

        Sessions start in a worktree with kurtkode -w NAME. remove refuses a worktree with uncommitted files unless --force.
        Its branch stays, with its commits, unless --delete-branch.
        """

    static func worktree(_ args: [String], folder: URL, out: (String) -> Void) async -> Int32 {
        let repo = GitRepo(root: folder)
        do {
            switch args.first {
            case "list":
                out(try await describeWorktrees(repo) + "\n")
                return 0
            case "remove":
                let words = args.dropFirst().filter { !$0.hasPrefix("--") }
                guard words.count == 1 else {
                    out(worktreeUsage + "\n")
                    return 2
                }
                guard let w = try await repo.worktrees().first(where: { $0.name == words[0] && !$0.isMain }) else {
                    out("There's no worktree called \(words[0]).\n")
                    return 1
                }
                let state = try await repo.worktreeState(w)
                let delete = args.contains("--delete-branch")
                if delete, state.unmerged > 0, !args.contains("--force") {
                    out("\(w.branch ?? w.name) has \(state.unmerged) commit\(state.unmerged == 1 ? "" : "s") on no other branch. Add --force to delete them.\n")
                    return 1
                }
                try await repo.removeWorktree(w, force: args.contains("--force"), deleteBranch: delete)
                out("Removed \(w.name)." + (delete ? "\n" : " Its branch \(w.branch ?? "") stays.\n"))
                return 0
            default:
                out(worktreeUsage + "\n")
                return args.first == "--help" || args.first == "-h" ? 0 : 2
            }
        } catch {
            out("\(error.localizedDescription)\n")
            return 1
        }
    }

    /// One line a worktree, with what it holds.
    public static func describeWorktrees(_ repo: GitRepo) async throws -> String {
        var lines: [String] = []
        for w in try await repo.worktrees() where !w.isMain {
            let s = try await repo.worktreeState(w)
            var notes: [String] = []
            if s.uncommitted > 0 { notes.append("\(s.uncommitted) uncommitted") }
            if s.ignored > 0 { notes.append("\(s.ignored) ignored") }
            if s.unmerged > 0 { notes.append("\(s.unmerged) unmerged") }
            lines.append("\(w.name)  \(w.branch ?? "detached")" + (notes.isEmpty ? "" : "  " + notes.joined(separator: ", ")))
        }
        return lines.isEmpty ? "No worktrees." : lines.joined(separator: "\n")
    }

    // MARK: endpoint

    static func endpoint(_ args: [String], settings: AppSettings, readKey: (String) -> String?,
                         saveKey: (String, UUID) throws -> Void, out: (String) -> Void) -> Int32 {
        let store = EndpointStore(fileURL: settings.support.appending(path: "endpoints.json"))
        let loaded = store.loadChecked()
        var list = loaded.value
        // A file that can't be read isn't saved over: saving the list read from it would drop every endpoint it holds.
        if loaded.unreadable, args.first == "add" || args.first == "remove", let problem = loaded.problem {
            out("Nothing changed: \(problem). Fix it, or move it aside to start over, then try again.\n")
            return 1
        }
        switch args.first {
        case "list":
            if let problem = loaded.problem { out("Note: \(problem).\n") }
            for e in list {
                out("\(e.name)  \(e.baseURL.absoluteString)  \(e.kind.rawValue)\(e.usesAPIKey ? "  key" : "")\n")
            }
            return 0
        case "add":
            var words: [String] = [], keyEnv: String?, noKey = false
            var rest = args.dropFirst()
            while let a = rest.popFirst() {
                if a == "--key-env" { keyEnv = rest.popFirst() }
                else if a == "--no-key" { noKey = true }
                else { words.append(a) }
            }
            guard words.count == 2, let url = URL(string: words[1]), url.scheme?.hasPrefix("http") == true else {
                out(endpointUsage + "\n")
                return 2
            }
            guard !list.contains(where: { $0.name.lowercased() == words[0].lowercased() }) else {
                out("There's already an endpoint called \(words[0]).\n")
                return 1
            }
            var key: String?
            if let keyEnv {
                key = settings.environmentValue(keyEnv)
                guard key != nil else {
                    out("\(keyEnv) isn't set.\n")
                    return 1
                }
            } else if !noKey {
                key = readKey("API key for \(words[0]) (not shown; Enter for none): ")
            }
            var e = Endpoint(name: words[0], kind: Endpoint.detectedKind(url), baseURL: Endpoint.normalizedBaseURL(url))
            e.usesAPIKey = key?.isEmpty == false
            if let key, !key.isEmpty {
                do { try saveKey(key, e.id) } catch {
                    out("Couldn't save the key: \(error.localizedDescription)\n")
                    return 1
                }
            }
            list.append(e)
            do { try store.save(list) } catch {
                out("Couldn't save: \(error.localizedDescription)\n")
                return 1
            }
            out("Added \(e.name). Use it with -m \(e.name):MODEL.\n")
            return 0
        case "remove":
            guard args.count == 2, let i = list.firstIndex(where: { $0.name.lowercased() == args[1].lowercased() }) else {
                out(args.count == 2 ? "There's no endpoint called \(args[1]).\n" : endpointUsage + "\n")
                return args.count == 2 ? 1 : 2
            }
            guard list[i].id != Endpoint.localLMStudio.id else {
                out("This Mac's server stays on the list.\n")
                return 1
            }
            list.remove(at: i)
            do { try store.save(list) } catch {
                out("Couldn't save: \(error.localizedDescription)\n")
                return 1
            }
            out("Removed \(args[1]). Its Keychain entry, if any, stays until the app's Settings removes it.\n")
            return 0
        default:
            out(endpointUsage + "\n")
            return args.first == "--help" || args.first == "-h" ? 0 : 2
        }
    }

    /// Reads a line without showing it; nil without a terminal.
    public static func readHidden(_ prompt: String) -> String? {
        guard isatty(STDIN_FILENO) == 1 else { return nil }
        _ = try? FileHandle.standardError.write(contentsOf: Data(prompt.utf8))
        var saved = termios()
        tcgetattr(STDIN_FILENO, &saved)
        var quiet = saved
        quiet.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &quiet)
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &saved)
            _ = try? FileHandle.standardError.write(contentsOf: Data("\n".utf8))
        }
        return readLine()
    }

    // MARK: doctor

    struct Check {
        var ok: Bool?                   // nil: only a note
        var text: String
    }

    /// What can be looked at without spending anything or reading a key from the Keychain (which would put up a prompt).
    static func doctor(settings: AppSettings, out: (String) -> Void) async -> Int32 {
        var checks: [Check] = []
        let fm = FileManager.default
        for tool in ["/usr/bin/sandbox-exec", "/usr/bin/git"] {
            checks.append(Check(ok: fm.isExecutableFile(atPath: tool), text: tool))
        }
        let support = settings.support
        checks.append(Check(ok: fm.fileExists(atPath: support.path) ? fm.isWritableFile(atPath: support.path) : true,
                            text: "data folder \(support.path)"))
        let term = ProcessInfo.processInfo.environment["TERM"] ?? "none"
        checks.append(Check(ok: nil, text: "terminal \(term); live screen \(TerminalUI.available ? "available" : "off (--plain)")"))
        for e in settings.endpoints {
            checks.append(await reach(e))
        }
        checks.append(Check(ok: nil, text: "default model \(settings.defaultModel) on \(settings.defaultEndpoint.name)"))
        if let stale = PriceList.staleness() { checks.append(Check(ok: nil, text: stale)) }
        var problems = 0
        for c in checks {
            let mark = c.ok == nil ? "·" : c.ok == true ? "✓" : "✗"
            if c.ok == false { problems += 1 }
            out("\(mark) \(c.text)\n")
        }
        out(problems == 0 ? "All good.\n" : "\(problems) problem\(problems == 1 ? "" : "s").\n")
        return problems == 0 ? 0 : 1
    }

    /// A server answers at all: its model list, read without a key. A refusal still means it's there.
    static func reach(_ e: Endpoint) async -> Check {
        var request = URLRequest(url: e.baseURL.appending(path: "models"))
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Check(ok: true, text: "\(e.name) answers (HTTP \(code))\(e.usesAPIKey ? "; key not checked" : "")")
        } catch {
            // A local server that's off is normal when hosted models are used.
            return Check(ok: e.isLocal ? nil : false, text: "\(e.name) doesn't answer: \(error.localizedDescription)")
        }
    }
}
