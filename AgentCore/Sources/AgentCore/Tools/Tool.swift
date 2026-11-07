import Foundation

/// What a tool can do, which decides whether it needs approval (Phase 3).
public enum ToolRisk: String, Sendable, Codable {
    case read, write, execute
}

/// Everything a tool may touch.
public struct ToolContext: Sendable {
    public var workspace: Workspace
    /// Largest tool result sent to the model. Local models have small contexts: 16 KB is ~4k tokens.
    public var maxOutputBytes: Int
    /// The session's shell state (working directory), shared across bash calls.
    public var shell: ShellState
    /// Live output for the UI while a tool runs (bash).
    public var progress: (@Sendable (String) -> Void)?
    /// Where to save the complete output when it's too long to send.
    public var fullOutputURL: URL?
    /// When set, commands run in this sandbox (D9).
    public var sandbox: SandboxPolicy?
    /// The call being run (a subagent run records which `task` call started it).
    public var callID: String?
    /// Asks the user (`ask_user`), an answer for each question, nil where there's none; nil when nobody is there to answer.
    public var askUser: (@Sendable ([UserQuestion]) async -> [String?])?
    /// The files this run has read: edits of others are refused (B5). Nil: no such check.
    public var reads: FileReads?
    /// Run commands without the variables earlier ones exported, and keep none they export (Plan mode).
    public var cleanShell = false
    /// The home folder the project's memory is under (`remember`); nil: the user's.
    public var memoryHome: URL?
    /// Shows the user a plan and waits for their decision (`present_plan`); nil when nobody is there to decide.
    public var presentPlan: (@Sendable (PlanProposal) async -> PlanDecision)?
    /// Where images a tool reads go, and whether the model can see them.
    public var imagesDirectory: URL?
    public var acceptsImages = false
    /// A fan-out's warm-up: set when one reply starts several subagents, so siblings of one kind read the first one's
    /// cache instead of each writing it (`CacheWarmup`).
    public var cacheWarmup: CacheWarmup?

    public init(workspace: Workspace, maxOutputBytes: Int = 16_000, shell: ShellState? = nil,
                progress: (@Sendable (String) -> Void)? = nil) {
        self.workspace = workspace
        self.maxOutputBytes = maxOutputBytes
        self.shell = shell ?? ShellState(cwd: workspace.root)
        self.progress = progress
    }
}

/// The session's shell: the working directory and the variables its commands exported, carried across bash calls
/// (D8, B2), and the commands it runs in the background.
public final class ShellState: @unchecked Sendable {
    private let lock = NSLock()
    private var _cwd: URL
    private var _exported: [String: String]
    private var _unset: Set<String>
    /// The exported names set by commands that ran in the sandbox. They aren't applied to a command that runs outside
    /// it: `export PATH=$PWD/.bin:$PATH` in Full Auto, then an approved `git push` in Ask, would run `./.bin/git`
    /// unsandboxed, and the approval card shows the command, not the environment.
    private var _sandboxed: Set<String>
    /// Commands started with `run_in_background`.
    public let jobs = BackgroundCommands()
    /// Where each command's environment is written down, before and after it runs.
    let envFolder = FileManager.default.temporaryDirectory.appending(path: "kurtkode-env-\(UUID().uuidString.prefix(8))")

    public init(cwd: URL, exported: [String: String] = [:], unset: Set<String> = [], sandboxed: Set<String> = []) {
        _cwd = cwd
        _exported = exported
        _unset = unset
        _sandboxed = sandboxed
    }

    deinit { try? FileManager.default.removeItem(at: envFolder) }

    public var cwd: URL {
        get { lock.withLock { _cwd } }
        set { lock.withLock { _cwd = newValue } }
    }

    /// Variables earlier commands set or changed (exported), and ones they unset.
    public var exported: [String: String] { lock.withLock { _exported } }
    public var unset: Set<String> { lock.withLock { _unset } }
    /// The exported names that commands in the sandbox set (see `_sandboxed`).
    public var sandboxed: Set<String> { lock.withLock { _sandboxed } }

    /// Lines that put the exported variables back, run after the login profile (so a PATH a command set wins over
    /// the profile's, without growing each time), for a command that runs in the sandbox or not. Outside it, the
    /// variables commands in the sandbox exported are held back and named.
    func prelude(sandboxed: Bool) -> (text: String, held: [String]) {
        let (set, unset, tainted) = lock.withLock { (_exported, _unset, _sandboxed) }
        var out = "", held: [String] = []
        for k in set.keys.sorted() {
            if !sandboxed, tainted.contains(k) { held.append(k); continue }
            out += "export \(k)=\(Self.quote(set[k]!))\n"
        }
        for k in unset.sorted() { out += "unset \(k)\n" }
        return (out, held)
    }

    /// What the model is told when exports were held back from a command outside the sandbox.
    static func heldNote(_ held: [String]) -> String {
        "Not applied to this command, which ran outside the sandbox: " + held.joined(separator: ", ")
            + " (exported by commands in it). Set them in the command itself if it needs them."
    }

    /// Variables a shell has of its own, never carried.
    static let ignored: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_", "__kk_status"]

    /// Takes in what a command changed: `before` and `after` are its environment as it started and ended; `sandboxed`
    /// says whether it ran in the sandbox. Returns the names it set and unset.
    @discardableResult
    func absorb(before: [String: String], after: [String: String], sandboxed: Bool = false) -> (set: [String], unset: [String]) {
        func carried(_ k: String) -> Bool {
            !Self.ignored.contains(k) && !k.hasPrefix("__kk") && k.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
        }
        let set = after.filter { carried($0.key) && before[$0.key] != $0.value && $0.value.utf8.count <= 65_536 }
        let gone = before.keys.filter { carried($0) && after[$0] == nil }
        lock.withLock {
            for (k, v) in set {
                _exported[k] = v; _unset.remove(k)
                if sandboxed { _sandboxed.insert(k) } else { _sandboxed.remove(k) }
            }
            for k in gone { _exported[k] = nil; _unset.insert(k); _sandboxed.remove(k) }
        }
        return (set.keys.sorted(), gone.sorted())
    }

    /// `env -0` output as a dictionary.
    static func parseEnv(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        for item in data.split(separator: 0) {
            let s = String(decoding: item, as: UTF8.self)
            guard let eq = s.firstIndex(of: "="), eq != s.startIndex else { continue }
            out[String(s[..<eq])] = String(s[s.index(after: eq)...])
        }
        return out
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// What an approval card shows before a tool runs.
public enum ToolPreview: Sendable, Hashable {
    /// Unified diff of the change; `isNewFile` when the file doesn't exist yet.
    case diff(path: String, unified: String, isNewFile: Bool)
    /// A shell command and the directory it will run in.
    case command(String, cwd: String)
    /// A call to an outside tool (MCP): who runs it, and the arguments as JSON.
    case call(title: String, arguments: String)
}

/// A tool's result. `text` goes to the model; errors are results too, so the model can recover.
public struct ToolOutput: Sendable, Hashable {
    public var text: String
    public var isError: Bool
    public var truncated: Bool
    /// What the UI shows instead of `text`, e.g. a unified diff for an edit.
    public var display: String?
    /// For commands.
    public var exitCode: Int32?
    /// The complete output on disk, when `text` had to be shortened.
    public var fullOutputPath: String?
    /// The subagent run a `task` call started (its session id).
    public var subagentRun: UUID?
    /// The run switches to this mode once the call returns (an approved plan).
    public var newMode: PermissionMode?
    /// The run stops after this turn's calls, waiting for the user (a rejected plan).
    public var endsRun = false
    /// Images for the model: they follow the turn's results, in a message of their own.
    public var images: [ImageAttachment] = []

    public init(text: String, isError: Bool = false, truncated: Bool = false, display: String? = nil,
                exitCode: Int32? = nil, fullOutputPath: String? = nil) {
        self.text = text
        self.isError = isError
        self.truncated = truncated
        self.display = display
        self.exitCode = exitCode
        self.fullOutputPath = fullOutputPath
    }

    public static func error(_ message: String) -> ToolOutput { ToolOutput(text: "Error: \(message)", isError: true) }
}

/// Stored on a tool-result message for the UI; not sent to the model.
public struct ToolResultInfo: Codable, Sendable, Hashable {
    public var toolName: String
    public var isError: Bool
    public var truncated: Bool
    public var duration: Double
    /// UI rendering of the result, e.g. a diff.
    public var display: String?
    /// Set when the user denied the call.
    public var denied: Bool?
    public var exitCode: Int32?
    public var fullOutputPath: String?
    /// Who let the call run (or refused it), and how long it waited.
    public var approval: ApprovalRecord?
    /// What's wrong with the arguments, checked against the tool's schema.
    public var argumentProblems: [String]?
    /// Anything else the loop did: not run (a repeat, over the turn's output budget), hook feedback.
    public var notes: [String]?
    /// The subagent run a `task` call started: a session in the parent's `.subagents/` folder.
    public var subagentRun: UUID?

    public init(toolName: String, isError: Bool, truncated: Bool, duration: Double, display: String? = nil,
                denied: Bool? = nil, exitCode: Int32? = nil, fullOutputPath: String? = nil) {
        self.toolName = toolName
        self.isError = isError
        self.truncated = truncated
        self.duration = duration
        self.display = display
        self.denied = denied
        self.exitCode = exitCode
        self.fullOutputPath = fullOutputPath
    }
}

/// A thrown error the tool wants shown to the model as-is.
public struct ToolFailure: Error, Sendable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON Schema for the arguments object.
    var parameters: JSONValue { get }
    var risk: ToolRisk { get }
    func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput
    /// One line for the tool card, e.g. "Read src/main.swift".
    func summary(_ args: ToolArguments) -> String
    /// What the approval card shows. Throws ToolFailure when the call can't succeed, so the error goes
    /// straight back to the model without bothering the user.
    func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview?
    /// Files the call will change, snapshotted first so the turn can be undone.
    func affectedFiles(_ args: ToolArguments, context: ToolContext) throws -> [URL]
}

extension Tool {
    public var definition: ToolDefinition { ToolDefinition(name: name, description: description, parameters: parameters) }
    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? { nil }
    public func affectedFiles(_ args: ToolArguments, context: ToolContext) throws -> [URL] { [] }
}

/// Decoded tool-call arguments with lenient accessors: models send "10" for 10 and so on.
public struct ToolArguments: Sendable {
    public let values: [String: JSONValue]

    public init(_ values: [String: JSONValue] = [:]) { self.values = values }

    /// Parses the raw arguments string. Empty means no arguments.
    public init(json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { self.init(); return }
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)) else {
            throw ToolFailure("the arguments were not valid JSON: \(trimmed.prefix(200))")
        }
        guard case .object(let o) = v else { throw ToolFailure("the arguments must be a JSON object") }
        self.init(o)
    }

    public func string(_ key: String) -> String? {
        switch values[key] {
        case .string(let s): s
        case .number(let n): Int(exactly: n).map(String.init) ?? String(n)
        case .bool(let b): String(b)
        default: nil
        }
    }

    /// The largest number a tool gets: tools add these to line numbers and offsets, which mustn't overflow either.
    static let largestInt = 1 << 53

    /// Nil for what isn't a number, and for a model's `1e20`.
    public func int(_ key: String) -> Int? {
        let n: Int? = switch values[key] {
        case .number(let d): Int(json: d)
        case .string(let s): Int(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
        return n.flatMap { (-Self.largestInt...Self.largestInt).contains($0) ? $0 : nil }
    }

    public func bool(_ key: String) -> Bool? {
        switch values[key] {
        case .bool(let b): b
        case .string(let s): ["true", "yes", "1"].contains(s.lowercased()) ? true : ["false", "no", "0"].contains(s.lowercased()) ? false : nil
        case .number(let n): n != 0
        default: nil
        }
    }

    public func require(_ key: String) throws -> String {
        guard let s = string(key), !s.isEmpty else { throw ToolFailure("missing required argument \"\(key)\"") }
        return s
    }
}

/// Keeps output under a byte budget, cutting at a line boundary and saying so.
func capOutput(_ text: String, maxBytes: Int, hint: String) -> (String, Bool) {
    guard text.utf8.count > maxBytes else { return (text, false) }
    var cut = text.utf8.prefix(maxBytes)
    if let nl = cut.lastIndex(of: 0x0A) { cut = cut[..<nl] }
    let kept = String(decoding: cut, as: UTF8.self)
    return (kept + "\n\n[Output truncated at \(maxBytes / 1000) KB. \(hint)]", true)
}
