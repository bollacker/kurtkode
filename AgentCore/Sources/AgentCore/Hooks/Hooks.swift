import CryptoKit
import Darwin
import Foundation

/// Hooks: the user's commands that run at points in the agent's work, in Claude Code's format, from the
/// `"hooks"` section of `~/.kurtkode/settings.json` (trusted) and `<project>/.kurtkode/settings.json` (the
/// project's commands, which need the user's approval once, like MCP servers).
///
///     {"hooks": {"PreToolUse": [{"matcher": "bash|Edit", "hooks": [{"type": "command", "command": "…", "timeout": 30}]}]}}
///
/// A hook gets the event as JSON on stdin. Exit 0 is success (stdout may be JSON with a decision); exit 2
/// blocks, and its stderr goes to the model; any other exit is a non-blocking error the user sees.
public enum HookEvent: String, Codable, Sendable, CaseIterable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case sessionStart = "SessionStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case notification = "Notification"
}

public struct HookCommand: Codable, Sendable, Hashable {
    public var type: String?
    public var command: String
    public var timeout: Double?
}

public struct HookMatcher: Codable, Sendable, Hashable {
    /// A regular expression over the tool name (either kurtkode's or Claude Code's name for it); empty or
    /// "*" matches every tool. Ignored for events without a tool.
    public var matcher: String?
    public var hooks: [HookCommand]

    /// `server`: the MCP server a resource tool is acting for, so a matcher on that server's tools finds it.
    func matches(_ tool: String?, server: String? = nil) -> Bool {
        guard let tool, let m = matcher?.trimmingCharacters(in: .whitespaces), !m.isEmpty, m != "*" else { return true }
        var names = [tool] + (Hooks.claudeNames[tool].map { [$0] } ?? [])
        if let server { names.append(MCPTool.exposedName(server: server, tool: String(tool.dropFirst("mcp_".count)))) }
        guard let re = try? NSRegularExpression(pattern: "^(?:\(m))$") else { return names.contains(m) }
        return names.contains { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }
}

/// One settings file's hooks.
public struct HookConfig: Codable, Sendable, Hashable {
    public var hooks: [String: [HookMatcher]]?

    public var isEmpty: Bool { (hooks ?? [:]).values.allSatisfy { $0.allSatisfy { $0.hooks.isEmpty } } }

    /// What a project approval covers: every event, matcher, and command. Any change asks again.
    public var fingerprint: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? enc.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }

    /// Every command, for showing the user what they'd approve.
    public var commands: [String] { (hooks ?? [:]).sorted { $0.key < $1.key }.flatMap { e in e.value.flatMap { $0.hooks.map { "\(e.key): \($0.command)" } } } }

    public static func userFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".kurtkode/settings.json")
    }

    public static func projectFile(_ workspace: URL) -> URL { workspace.appending(path: ".kurtkode/settings.json") }

    public static func load(_ url: URL) throws -> HookConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(HookConfig.self, from: data) }
        catch { throw MCPError.config("\(url.path) isn't valid: \(error.localizedDescription)") }
    }
}

/// Which projects' hooks the user approved (project path + fingerprint).
public struct HookApprovals: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    static func key(_ workspace: URL, _ config: HookConfig) -> String { "\(workspace.standardizedFileURL.path)|\(config.fingerprint)" }

    public func isApproved(_ config: HookConfig, workspace: URL) -> Bool { load().contains(Self.key(workspace, config)) }

    public func approve(_ config: HookConfig, workspace: URL) throws {
        var set = load()
        set.insert(Self.key(workspace, config))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(set.sorted()).write(to: fileURL, options: .atomic)
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }
}

/// The hooks that apply to a run, and what they decide.
public struct Hooks: Sendable {
    public var matchers: [HookEvent: [HookMatcher]]
    public var sessionID: String
    public var cwd: URL
    public var transcriptPath: String?

    /// kurtkode's tool names → Claude Code's, so matchers written for Claude Code work.
    static let claudeNames = ["bash": "Bash", "edit_file": "Edit", "write_file": "Write", "read_file": "Read", "web_fetch": "WebFetch",
                              "glob": "Glob", "grep": "Grep", "list_dir": "LS", "todo_write": "TodoWrite", "task": "Task",
                              "skill": "Skill", "ask_user": "AskUserQuestion",
                              "bash_output": "BashOutput", "kill_shell": "KillShell"]

    public init(matchers: [HookEvent: [HookMatcher]], sessionID: String, cwd: URL, transcriptPath: String? = nil) {
        self.matchers = matchers
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
    }

    public var isEmpty: Bool { matchers.values.allSatisfy(\.isEmpty) }

    /// The user's hooks, plus the project's when approved. Also returns the project's hooks when they're
    /// waiting for approval, for the frontend to ask about.
    public static func load(workspace: URL, approvals: HookApprovals, sessionID: String, transcriptPath: String? = nil,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> (hooks: Hooks, pending: HookConfig?, problem: String?) {
        var configs: [HookConfig] = []
        var pending: HookConfig?
        var problem: String?
        do { if let user = try HookConfig.load(HookConfig.userFile(home: home)) { configs.append(user) } }
        catch { problem = error.localizedDescription }
        do {
            if let project = try HookConfig.load(HookConfig.projectFile(workspace)), !project.isEmpty {
                if approvals.isApproved(project, workspace: workspace) { configs.append(project) } else { pending = project }
            }
        } catch { problem = error.localizedDescription }
        var matchers: [HookEvent: [HookMatcher]] = [:]
        for c in configs {
            for (name, list) in c.hooks ?? [:] {
                guard let event = HookEvent(rawValue: name) else { continue }
                matchers[event, default: []] += list
            }
        }
        return (Hooks(matchers: matchers, sessionID: sessionID, cwd: workspace, transcriptPath: transcriptPath), pending, problem)
    }

    // MARK: Results

    public enum Permission: String, Sendable { case allow, deny, ask }

    /// What the hooks for one event decided, combined: any block or deny wins, then ask, then allow.
    public struct Outcome: Sendable, Equatable {
        public var blocked = false
        /// For the model (a block) or the user.
        public var reason: String?
        public var permission: Permission?
        /// Text to add for the model (stdout of UserPromptSubmit, or additionalContext).
        public var context: [String] = []
        /// Non-blocking failures, for the user.
        public var errors: [String] = []
    }

    struct Run: Sendable { var status: Int32; var stdout: String; var stderr: String; var timedOut: Bool }

    public func run(_ event: HookEvent, tool: String? = nil, input extra: [String: JSONValue] = [:]) async -> Outcome {
        var server: String?
        if case .object(let args)? = extra["tool_input"], case .string(let s)? = args["server"], MCPHub.resourceTools.contains(tool ?? "") { server = s }
        let commands = (matchers[event] ?? []).filter { $0.matches(tool, server: server) }.flatMap(\.hooks)
        var outcome = Outcome()
        guard !commands.isEmpty else { return outcome }
        var input: [String: JSONValue] = ["session_id": .string(sessionID), "cwd": .string(cwd.path),
                                          "hook_event_name": .string(event.rawValue)]
        if let transcriptPath { input["transcript_path"] = .string(transcriptPath) }
        if let tool { input["tool_name"] = .string(tool) }
        for (k, v) in extra { input[k] = v }
        let payload = TextToolCalls.encode(.object(input))
        for command in commands {
            let r = await Self.execute(command.command, stdin: payload, cwd: cwd, timeout: command.timeout ?? 60)
            let label = command.command.count > 60 ? String(command.command.prefix(57)) + "…" : command.command
            if r.timedOut { outcome.errors.append("\(event.rawValue) hook timed out: \(label)"); continue }
            switch r.status {
            case 0:
                apply(r.stdout, event: event, to: &outcome)
            case 2:
                outcome.blocked = true
                let why = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                outcome.reason = [outcome.reason, why.isEmpty ? "(the hook gave no reason)" : why].compactMap { $0 }.joined(separator: "\n")
                if event == .preToolUse { outcome.permission = .deny }
            default:
                let why = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                outcome.errors.append("\(event.rawValue) hook failed (exit \(r.status)): \(label)" + (why.isEmpty ? "" : ": " + String(why.prefix(300))))
            }
        }
        return outcome
    }

    /// Exit 0: stdout is JSON with a decision, or plain text (context for UserPromptSubmit).
    func apply(_ stdout: String, event: HookEvent, to outcome: inout Outcome) {
        let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.hasPrefix("{"), case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
            if event == .userPromptSubmit || event == .sessionStart { outcome.context.append(text) }
            return
        }
        if o["continue"] == .bool(false) {
            outcome.blocked = true
            outcome.reason = o["stopReason"]?.stringValue ?? outcome.reason
        }
        if o["decision"]?.stringValue == "block" {
            outcome.blocked = true
            outcome.reason = [outcome.reason, o["reason"]?.stringValue].compactMap { $0 }.joined(separator: "\n")
        }
        // Before a tool call, a block (Claude Code's older form) or `continue: false` stops the call, as exit 2 does.
        if outcome.blocked, event == .preToolUse { outcome.permission = .deny }
        if case .object(let specific)? = o["hookSpecificOutput"] {
            if let p = specific["permissionDecision"]?.stringValue.flatMap(Permission.init(rawValue:)) {
                outcome.permission = Self.stricter(outcome.permission, p)
                if let r = specific["permissionDecisionReason"]?.stringValue { outcome.reason = r }
                if p == .deny { outcome.blocked = true }
            }
            if let ctx = specific["additionalContext"]?.stringValue { outcome.context.append(ctx) }
        }
    }

    static func stricter(_ a: Permission?, _ b: Permission) -> Permission {
        let rank: [Permission: Int] = [.allow: 0, .ask: 1, .deny: 2]
        guard let a else { return b }
        return rank[a]! >= rank[b]! ? a : b
    }

    /// Runs a hook command with zsh in the project, the event on stdin, and KURTKODE_PROJECT_DIR (and
    /// CLAUDE_PROJECT_DIR, for hooks written for Claude Code) set. Not sandboxed: it's the user's own command.
    /// The hook runs in its own process group, so the timeout stops what it started too (a child holding stdout would
    /// otherwise keep the loop waiting), and stdin is written from a thread of its own after the watchdog is armed: a
    /// hook that never reads a large payload used to block the write, and so the loop, for as long as it ran.
    static func execute(_ command: String, stdin: String, cwd: URL, timeout: TimeInterval) async -> Run {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: executeBlocking(command, stdin: stdin, cwd: cwd, timeout: timeout))
            }
        }
    }

    private static func executeBlocking(_ command: String, stdin: String, cwd: URL, timeout: TimeInterval) -> Run {
        var inFDs: [Int32] = [0, 0], outFDs: [Int32] = [0, 0], errFDs: [Int32] = [0, 0]
        guard pipe(&inFDs) == 0 else { return Run(status: 127, stdout: "", stderr: "couldn't run: no pipe (errno \(errno))", timedOut: false) }
        guard pipe(&outFDs) == 0 else {
            inFDs.forEach { close($0) }
            return Run(status: 127, stdout: "", stderr: "couldn't run: no pipe (errno \(errno))", timedOut: false)
        }
        guard pipe(&errFDs) == 0 else {
            (inFDs + outFDs).forEach { close($0) }
            return Run(status: 127, stdout: "", stderr: "couldn't run: no pipe (errno \(errno))", timedOut: false)
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inFDs[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outFDs[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errFDs[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd.path)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // New process group (pgid = pid); close every descriptor not set up above.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        // Without kurtkode's API keys: a project's hooks are the repository's code, approved once by
        // fingerprint, and the user's own run under `zsh -l`, where their profile's exports come back.
        var env = ChildEnvironment.inherited
        env["PATH"] = LoginShell.path()
        env["KURTKODE_PROJECT_DIR"] = cwd.path
        env["CLAUDE_PROJECT_DIR"] = cwd.path
        let argv = ["/bin/zsh", "-lc", command]
        let cArgs = argv.map { strdup($0) } + [nil]
        let cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (cArgs + cEnv).forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, argv[0], &actions, &attr, cArgs, cEnv)
        close(inFDs[0]); close(outFDs[1]); close(errFDs[1])
        guard rc == 0 else {
            close(inFDs[1]); close(outFDs[0]); close(errFDs[0])
            return Run(status: 127, stdout: "", stderr: "couldn't run: \(String(cString: strerror(rc)))", timedOut: false)
        }
        // The watchdog first: SIGTERM to the whole group, then SIGKILL to what ignores it.
        let timedOut = AtomicFlag()
        let killer = DispatchWorkItem { kill(-child, SIGKILL) }
        let watchdog = DispatchWorkItem {
            timedOut.set()
            kill(-child, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: killer)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // stdin on its own thread, non-blocking, so a hook that doesn't read it can't hold the loop; a hook that has
        // gone (EPIPE) or is done (`finished`) ends the write.
        let finished = AtomicFlag()
        let writeFD = inFDs[1]
        _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)
        _ = fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK)
        let payload = Array(stdin.utf8)
        Thread.detachNewThread {
            var offset = 0
            while offset < payload.count, !finished.isSet {
                let n = payload[offset...].withUnsafeBufferPointer { write(writeFD, $0.baseAddress, $0.count) }
                if n > 0 { offset += Int(n); continue }
                if n < 0, errno == EAGAIN || errno == EINTR {
                    var fd = pollfd(fd: writeFD, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&fd, 1, 100)
                    continue
                }
                break
            }
            close(writeFD)
        }
        let stdout = Drain(outFDs[0]), stderr = Drain(errFDs[0])
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 && errno == EINTR {}
        watchdog.cancel()
        // Children the hook left behind (`sleep 100 &`) may still hold its output: a moment, then the group goes.
        if !stdout.wait(seconds: 1) || !stderr.wait(seconds: 1) {
            kill(-child, SIGKILL)
            _ = stdout.wait(seconds: 2)
            _ = stderr.wait(seconds: 2)
        }
        killer.cancel()
        finished.set()
        let signal = status & 0x7F
        let code: Int32 = signal == 0 ? (status >> 8) & 0xFF : 128 + signal
        return Run(status: code, stdout: String(decoding: stdout.data.prefix(65_536), as: UTF8.self),
                   stderr: String(decoding: stderr.data.prefix(65_536), as: UTF8.self), timedOut: timedOut.isSet)
    }

    /// Reads a descriptor to EOF on a thread of its own; `wait` says whether EOF came in time.
    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private var collected = Data()
        private let done = DispatchSemaphore(value: 0)
        private var signalled = false

        init(_ fd: Int32) {
            Thread.detachNewThread { [self] in
                var buf = [UInt8](repeating: 0, count: 16_384)
                while true {
                    let n = read(fd, &buf, buf.count)
                    if n > 0 { lock.withLock { collected.append(contentsOf: buf[0..<Int(n)]) } }
                    else if n < 0 && errno == EINTR { continue }
                    else { break }
                }
                close(fd)
                done.signal()
            }
        }

        /// True once EOF has come (within `seconds` of this call).
        func wait(seconds: TimeInterval) -> Bool {
            if lock.withLock({ signalled }) { return true }
            guard done.wait(timeout: .now() + seconds) == .success else { return false }
            lock.withLock { signalled = true }
            return true
        }

        var data: Data { lock.withLock { collected } }
    }

    // MARK: Events

    public func preToolUse(_ call: ToolCall) async -> Outcome {
        await run(.preToolUse, tool: call.name, input: ["tool_input": Self.arguments(call)])
    }

    public func postToolUse(_ call: ToolCall, output: ToolOutput) async -> Outcome {
        await run(.postToolUse, tool: call.name, input: [
            "tool_input": Self.arguments(call),
            "tool_response": ["output": .string(output.text), "is_error": .bool(output.isError)],
        ])
    }

    public func userPromptSubmit(_ prompt: String) async -> Outcome {
        await run(.userPromptSubmit, input: ["prompt": .string(prompt)])
    }

    public func stop(active: Bool) async -> Outcome {
        await run(.stop, input: ["stop_hook_active": .bool(active)])
    }

    /// A new session's first run. Its output goes to the model, as UserPromptSubmit's does.
    public func sessionStart(source: String = "startup") async -> Outcome { await run(.sessionStart, input: ["source": .string(source)]) }

    public func subagentStop(agent: String, report: String) async -> Outcome {
        await run(.subagentStop, input: ["agent": .string(agent), "report": .string(String(report.prefix(4000)))])
    }

    public func preCompact(trigger: String, instructions: String = "") async -> Outcome {
        await run(.preCompact, input: ["trigger": .string(trigger), "custom_instructions": .string(instructions)])
    }

    /// The agent is waiting for the user.
    public func notification(_ message: String) async -> Outcome { await run(.notification, input: ["message": .string(message)]) }

    static func arguments(_ call: ToolCall) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))) ?? .object([:])
    }
}
