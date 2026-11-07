import Foundation

/// Runs shell commands (D8): a fresh `zsh -l` per call in the session's working directory, which persists across
/// calls, as do the variables commands export (B2). `run_in_background` starts a command and returns at once.
public struct BashTool: Tool {
    public init() {}
    public let name = "bash"
    public let description = """
        Run a shell command with zsh in the project. Each call starts a fresh shell in the current working \
        directory; cd and exported variables (export X=…, source venv/bin/activate) carry over to later calls. \
        Commands cannot read input, so use non-interactive flags (for example -y). Long output is shortened to its \
        start and end, and the whole of it is saved to a file the result names, which you can read or grep. \
        Default timeout 120 seconds, maximum 600. For a server, a watcher or a build longer than that, set \
        run_in_background: it returns at once with an id; read its output with bash_output, stop it with kill_shell.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "command": ["type": "string", "description": "The command to run."],
            "timeout": ["type": "integer", "description": "Seconds before the command is stopped. Default 120, max 600."],
            "run_in_background": ["type": "boolean",
                                  "description": "Start it and return at once (servers, long builds). Default false."],
        ],
        "required": ["command"],
    ]
    public let risk = ToolRisk.execute
    public static let marker = "__KURTKODE_CWD_7f3a__"

    public func summary(_ args: ToolArguments) -> String {
        let cmd = (args.string("command") ?? "?").split(separator: "\n").first.map(String.init) ?? ""
        return (args.bool("run_in_background") == true ? "Start in the background: " : "Run ")
            + (cmd.count > 90 ? String(cmd.prefix(87)) + "…" : cmd)
    }

    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? {
        let command = try args.require("command")
        return .command(command, cwd: displayCWD(context))
    }

    func displayCWD(_ context: ToolContext) -> String {
        let cwd = context.shell.cwd
        return context.workspace.contains(cwd) ? context.workspace.relative(cwd) : cwd.path
    }

    /// The environment every command starts with. No editor can open (stdin is closed): `git commit` without -m stops
    /// at once with "empty message" instead of waiting out the timeout, and `git merge` / `rebase --continue` keep
    /// their default messages.
    static var environment: [String: String] {
        var env = ChildEnvironment.inherited      // kurtkode's API keys stay out of commands
        for (k, v) in ["PAGER": "cat", "GIT_PAGER": "cat", "TERM": "dumb", "NO_COLOR": "1",
                       "GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true", "EDITOR": "true", "VISUAL": "true",
                       "KURTKODE": "1"] { env[k] = v }
        // The bundled ripgrep, last on PATH (an installed one wins): models reach for rg in commands too.
        if let rg = Ripgrep.executable?.deletingLastPathComponent().path {
            env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + rg
        }
        return env
    }

    /// `environment`, plus what a sandboxed command needs (`SandboxPolicy.cacheVariables`).
    static func environment(_ sandbox: SandboxPolicy?) -> [String: String] {
        let env = environment
        return sandbox == nil ? env : env.merging(SandboxPolicy.cacheVariables(for: env)) { old, _ in old }
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let command = try args.require("command")
        let timeout = TimeInterval(min(600, max(1, args.int("timeout") ?? 120)))
        var cwd = context.shell.cwd
        if !FileManager.default.fileExists(atPath: cwd.path) { cwd = context.workspace.root }
        if args.bool("run_in_background") == true { return try await runInBackground(command, cwd: cwd, context: context) }

        // The variables earlier commands exported are set again (after the login profile); the command runs as
        // written; the environment is written down before and after it, so what it exports carries over; then the
        // shell reports its directory so `cd` carries over too.
        let shell = context.shell
        try? FileManager.default.createDirectory(at: shell.envFolder, withIntermediateDirectories: true)
        let envID = UUID().uuidString.prefix(8)
        let envBefore = shell.envFolder.appending(path: "\(envID)-before"), envAfter = shell.envFolder.appending(path: "\(envID)-after")
        defer { for u in [envBefore, envAfter] { try? FileManager.default.removeItem(at: u) } }
        // /usr/bin/env by path: a command that breaks PATH mustn't break the snapshot (an empty one read as "everything
        // was unset" and broke every later call).
        let sandboxed = context.sandbox != nil
        let (prelude, held) = context.cleanShell ? ("", []) : shell.prelude(sandboxed: sandboxed)
        let script = prelude + "/usr/bin/env -0 > \(ShellState.quote(envBefore.path)) 2>/dev/null\n"
            + "\(command)\n__kk_status=$?\n/usr/bin/env -0 > \(ShellState.quote(envAfter.path)) 2>/dev/null\n"
            + "printf '\\n%s%s\\n' '\(Self.marker)' \"$PWD\"\nexit $__kk_status\n"
        let env = Self.environment(context.sandbox)

        let collector = OutputCollector()
        let progress = context.progress
        // Everything also goes to a file, kept only if the output turns out too long to send.
        let fullFile: FileHandle? = context.fullOutputURL.flatMap { url in
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return FileManager.default.createFile(atPath: url.path, contents: nil) ? try? FileHandle(forWritingTo: url) : nil
        }
        var argv = ["/bin/zsh", "-l", "-c", script]
        let tag = "kurtkode-sbx-" + UUID().uuidString.prefix(12).lowercased()
        if let sandbox = context.sandbox { argv = sandbox.wrap(argv, workspace: context.workspace.root, tag: tag) }
        let started = Date()
        let result = try await Subprocess.run(argv, cwd: cwd.path, environment: env,
                                              timeout: timeout) { chunk in
            collector.append(chunk)
            try? fullFile?.write(contentsOf: chunk)
            progress?(Self.hidingMarker(String(decoding: chunk, as: UTF8.self)))
        }
        try? fullFile?.close()

        let (headData, tailData, dropped) = collector.parts()
        var head = String(decoding: headData, as: UTF8.self)
        var tail = String(decoding: tailData, as: UTF8.self)
        // Pull out the directory report, which is at the very end.
        func extract(_ s: inout String) -> String? {
            guard let r = s.range(of: "\n" + Self.marker, options: .backwards) ?? s.range(of: Self.marker, options: .backwards) else { return nil }
            let rest = s[r.upperBound...]
            let path = rest.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            s.removeSubrange(r.lowerBound..<(rest.firstIndex(of: "\n").map { s.index(after: $0) } ?? s.endIndex))
            return path
        }
        let newCWD = extract(&tail) ?? extract(&head)

        var envNote: String?
        if !context.cleanShell, let before = try? Data(contentsOf: envBefore), let after = try? Data(contentsOf: envAfter),
           !before.isEmpty, !after.isEmpty {
            let (set, unset) = shell.absorb(before: ShellState.parseEnv(before), after: ShellState.parseEnv(after), sandboxed: sandboxed)
            var parts: [String] = []
            if !set.isEmpty { parts.append("Exported for later commands: " + set.joined(separator: ", ") + ".") }
            if !unset.isEmpty { parts.append("Unset for later commands: " + unset.joined(separator: ", ") + ".") }
            if !parts.isEmpty { envNote = parts.joined(separator: " ") }
        }
        if !held.isEmpty {
            envNote = (envNote.map { $0 + " " } ?? "") + ShellState.heldNote(held)
        }

        var cwdNote: String?
        if let newCWD, !newCWD.isEmpty {
            let url = URL(fileURLWithPath: newCWD)
            if url.standardizedFileURL.path != context.shell.cwd.standardizedFileURL.path {
                context.shell.cwd = url
                cwdNote = context.workspace.contains(url)
                    ? "Working directory is now \(context.workspace.relative(url))."
                    : "Working directory is now \(newCWD), outside the project."
            }
        }

        var output = dropped > 0 ? head + "\n[… \(dropped) bytes omitted …]\n" + tail : head + tail
        output = output.trimmingCharacters(in: .newlines)
        let (capped, truncated) = Self.capHeadTail(output, maxBytes: context.maxOutputBytes)

        var notes: [String] = []
        if result.timedOut {
            notes.append("Timed out after \(Int(timeout)) seconds; the command was stopped before it finished, so this "
                         + "output is incomplete. To let it finish, run it again with a longer timeout (up to 600) or with "
                         + "run_in_background: true and then bash_output with wait.")
        }
        else if result.cancelled { notes.append("Stopped by the user.") }
        else if let code = result.exitCode { notes.append("Exit code \(code).") }
        else if let sig = result.signal { notes.append("Killed by signal \(sig).") }
        if result.killedStragglers { notes.append("Background processes it started were stopped.") }
        if let cwdNote { notes.append(cwdNote) }
        if let envNote { notes.append(envNote) }
        if let sandbox = context.sandbox, result.exitCode != 0, !result.cancelled {
            if let note = await Self.sandboxNote(sandbox, tag: tag, since: started, output: output) { notes.append(note) }
        }

        var savedPath: String?
        if let url = context.fullOutputURL {
            if truncated || dropped > 0 {
                savedPath = url.path
                // The model can read it: the session's output folder is a read-only folder of the run (`AgentLoop.run`).
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
                notes.append("The whole output\(size.map { " (\($0) bytes)" } ?? "") is saved in \(url.path): read parts of "
                             + "it with read_file (offset, limit) or search it with grep instead of running the command again.")
            } else { try? FileManager.default.removeItem(at: url) }
        }
        // What the cut hid: the error-looking lines in it, listed. A pointer to the saved file isn't enough for small
        // models (Gemma 4 26B, given the note three times, used it never, and called a 40,000-line log with one FAIL in
        // its middle "all passed" from the tail).
        var hidden = ""
        if truncated || dropped > 0 {
            let full = savedPath.flatMap { Self.readSmall(URL(fileURLWithPath: $0)) } ?? output
            hidden = "\n\n" + Self.hiddenErrorsNote(full: Self.hidingMarker(full), shown: capped)
        }
        let text = (capped.isEmpty ? "(no output)" : capped) + hidden + "\n\n[" + notes.joined(separator: " ") + "]"
        return ToolOutput(text: text, isError: result.timedOut, truncated: truncated || dropped > 0,
                          display: output.isEmpty ? "(no output)" : output, exitCode: result.exitCode,
                          fullOutputPath: savedPath)
    }

    /// Starts the command in the background and returns its first moments: an id, what it printed in the first
    /// second or so (or how it ended, if it ended that soon), and where the rest goes.
    func runInBackground(_ command: String, cwd: URL, context: ToolContext) async throws -> ToolOutput {
        let shell = context.shell
        let output = context.fullOutputURL
            ?? FileManager.default.temporaryDirectory.appending(path: "kurtkode-bg-\(UUID().uuidString.prefix(8)).txt")
        let (prelude, held) = context.cleanShell ? ("", []) : shell.prelude(sandboxed: context.sandbox != nil)
        var argv = ["/bin/zsh", "-l", "-c", prelude + command]
        let tag = "kurtkode-sbx-" + UUID().uuidString.prefix(12).lowercased()
        if let sandbox = context.sandbox { argv = sandbox.wrap(argv, workspace: context.workspace.root, tag: tag) }
        let job = try shell.jobs.start(argv, command: command, cwd: cwd.path, environment: Self.environment(context.sandbox),
                                       output: output)
        let now = await shell.jobs.wait(job.id, seconds: 1.5) ?? job
        let (shown, skipped, all) = shell.jobs.takeNew(job.id, max: max(1000, context.maxOutputBytes - 1500))
        var text = shown.trimmingCharacters(in: .newlines)
        if skipped > 0 { text = "[… \(skipped) bytes not shown …]\n" + text + "\n\n" + Self.hiddenErrorsNote(full: all, shown: shown) }
        let head: String
        if now.isRunning {
            head = "Started in the background as \(job.id). " + (text.isEmpty ? "No output yet." : "Output so far:")
        } else {
            head = "It ended at once (\(job.id): \(now.state)). " + (text.isEmpty ? "No output." : "Output:")
        }
        let tail = now.isRunning
            ? "[\(job.id) is running. Its output goes to \(output.path). Read what's new with bash_output (id \"\(job.id)\", wait "
                + "for it to finish with wait), stop it with kill_shell.]"
            : "[Its output is in \(output.path).]"
        return ToolOutput(text: head + (text.isEmpty ? "" : "\n" + text) + "\n\n" + tail + (held.isEmpty ? "" : "\n[" + ShellState.heldNote(held) + "]"),
                          isError: !now.isRunning && now.exitCode != 0, exitCode: now.exitCode, fullOutputPath: output.path)
    }

    /// Tells the model what the sandbox blocked, so it can say so instead of working around it. Nil when the
    /// sandbox had nothing to do with the failure (a failing test run shouldn't get a sandbox lecture).
    static func sandboxNote(_ sandbox: SandboxPolicy, tag: String, since: Date, output: String) async -> String? {
        var blocked = await SandboxPolicy.denials(tag: tag, since: since)
        if blocked.isEmpty, output.localizedCaseInsensitiveContains("not permitted") {   // log lines can lag a little
            try? await Task.sleep(for: .milliseconds(600))
            blocked = await SandboxPolicy.denials(tag: tag, since: since)
        }
        let nested = output.contains("sandbox_apply: Operation not permitted")
        guard !blocked.isEmpty || nested else { return nil }
        var note = "This command ran in the sandbox: it can write only inside the project and temp directories"
            + (sandbox.allowNetwork ? "." : ", and has no network.")
        if !blocked.isEmpty {
            note += " The sandbox blocked: " + blocked.prefix(8).joined(separator: "; ")
                + (blocked.count > 8 ? "; and \(blocked.count - 8) more." : ".")
        }
        if nested {
            note += " A tool tried to start its own sandbox, which can't run inside this one (for swift build and "
                + "swift test, add --disable-sandbox)."
        }
        return note + " Don't work around the sandbox; if the task needs more access, tell the user."
    }

    /// Live output without the working-directory report the script prints at the end (it's stripped from
    /// the result, but it would flash by in live output).
    static func hidingMarker(_ text: String) -> String {
        guard let r = text.range(of: marker) else { return text }
        var start = r.lowerBound
        if start > text.startIndex, text[text.index(before: start)] == "\n" { start = text.index(before: start) }
        let end = text[r.upperBound...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
        return String(text[..<start]) + text[end...]
    }

    /// A saved output file's text, when it's small enough to scan (64 MB); nil otherwise.
    static func readSmall(_ url: URL) -> String? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size <= 64_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Words that mark a line as reporting a problem (whole words, any case).
    static let errorWords = try! NSRegularExpression(
        pattern: #"\b(fail(ed|ure|ures|s|ing)?|errors?|traceback|panic(ked)?|fatal|exception|assert(ion)?|segmentation fault|abort(ed)?)\b"#,
        options: [.caseInsensitive])

    /// How many hidden error lines are listed.
    static let maxHiddenErrors = 8

    /// What the shortened output left out, for the model: the lines among those not shown that look like errors, with
    /// their line numbers in the full output (up to `maxHiddenErrors`, and how many more), or that none of them do.
    static func hiddenErrorsNote(full: String, shown: String) -> String {
        let shownLines = Set(shown.split(separator: "\n", omittingEmptySubsequences: false))
        var hiddenCount = 0
        var found: [(Int, Substring)] = []
        var more = 0
        for (i, line) in full.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !shownLines.contains(line) {
            hiddenCount += 1
            let text = String(line)
            guard errorWords.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { continue }
            if found.count < maxHiddenErrors { found.append((i + 1, line)) } else { more += 1 }
        }
        guard hiddenCount > 0 else { return "" }
        guard !found.isEmpty else {
            return "[None of the \(hiddenCount) lines not shown above contain FAIL, ERROR, Traceback, panic, exception or "
                + "assertion.]"
        }
        let listed = found.map { n, line in "  line \(n): " + (line.count > 300 ? String(line.prefix(300)) + "…" : String(line)) }
        return "[Lines not shown above that look like errors (of \(hiddenCount) lines not shown):\n" + listed.joined(separator: "\n")
            + (more > 0 ? "\n  … and \(more) more such lines." : "") + "]"
    }

    /// Keeps the first third and last two thirds of the budget: errors and summaries are usually at the end.
    static func capHeadTail(_ s: String, maxBytes: Int) -> (String, Bool) {
        let bytes = Array(s.utf8)
        guard bytes.count > maxBytes else { return (s, false) }
        let headN = maxBytes / 3, tailN = maxBytes - headN
        let head = String(decoding: bytes.prefix(headN), as: UTF8.self)
        let tail = String(decoding: bytes.suffix(tailN), as: UTF8.self)
        return (head + "\n[… \(bytes.count - headN - tailN) bytes omitted …]\n" + tail, true)
    }
}
