import AgentCore
import Foundation

public struct CLIOptions: Sendable, Equatable {
    public enum Output: String, Sendable { case text, json, streamJSON = "stream-json" }

    public var prompt: String?
    /// -p: run once and exit.
    public var printMode = false
    /// "endpoint:model" or "model".
    public var model: String?
    public var mode: PermissionMode?
    public var cwd: String?
    public var continueLast = false
    public var resume: String?
    public var output = Output.text
    public var maxSteps: Int?
    public var mcp = true
    public var subagents = true
    /// Offer kurtkode's built-in skills (the app's setting can turn them off too).
    public var builtinSkills = true
    /// --skill-router: overrides Settings for this process.
    public var skillRouting: SkillRouting?
    public var sandbox: SandboxUse?
    public var showThinking = false
    /// --plain: line-at-a-time prompts instead of the live screen.
    public var plain = false
    /// -w: work in this worktree of the project, making it if it isn't there.
    public var worktree: String?
    /// --reasoning: this process's reasoning setting, over the model profile's ("default" clears it).
    public var reasoning: String?
    public var listSessions = false
    /// Folders outside the project the agent may use (--add-dir: read and write, --read-dir: read-only).
    public var folders: [ExtraFolder] = []
    /// Extra OpenAI-compatible endpoints for this run: (name, base URL). Never saved; no key.
    public var extraEndpoints: [ExtraEndpoint] = []
    public var help = false
    public var version = false

    public init() {}

    public struct ExtraEndpoint: Sendable, Equatable {
        public var name: String
        public var url: URL
    }

    public static let usage = """
        kurtkode: a coding agent for the terminal, sharing the app's endpoints, models, settings, and sessions.

        Usage:
          kurtkode                        interactive session in the current folder
          kurtkode inspect|replay|export  a recorded session's turns, a replay of one, or the whole session
                                          (kurtkode inspect --help)
          kurtkode runs                   every recorded agent run with its cost, for analysis (--csv, --json)
          kurtkode endpoint list|add|remove  the model servers (kurtkode endpoint --help)
          kurtkode worktree list|remove   this project's worktrees (kurtkode worktree --help)
          kurtkode doctor                 check this setup: servers, tools, sandbox, settings
          kurtkode "prompt"               interactive, starting with this prompt
          kurtkode -p "prompt"            run once, print the answer, exit (stdin is added to the prompt)

        Options:
          -p, --print                     run once and exit
          -m, --model SPEC                model, or endpoint:model (endpoints by name; "lmstudio" is this Mac)
              --mode MODE                 ask | edits | plan | auto   (default: the app's setting; -p can't approve,
                                          so actions that need approval are refused unless the mode allows them)
          -C, --cwd DIR                   project folder (default: current folder)
          -w, --worktree NAME             work in a worktree of the project on the branch kk/NAME, making it if needed, so
                                          this session's files are separate from other sessions'
              --add-dir DIR               another folder the agent may read and write (repeatable; kept with the session)
              --read-dir DIR              another folder the agent may only read (repeatable)
          -c, --continue                  continue the latest session in this project
          -r, --resume ID                 resume a session (an id prefix is enough; see --list-sessions)
              --list-sessions             list this project's sessions
              --output FORMAT             text | json | stream-json   (with -p)
              --max-steps N               model turns before pausing (default: the app's setting)
              --sandbox WHEN              fullAuto | always | never   (default: the app's setting)
              --no-mcp                    don't start MCP servers
              --no-subagents              don't offer the task tool
              --no-builtin-skills         offer only the project's and your own skills, not kurtkode's
              --skill-router WHEN         auto | on | off: ask the model which skill fits each request and have the
                                          agent load it (default: the app's setting; auto = on for OpenAI-compatible
                                          servers such as LM Studio)
              --show-thinking             print reasoning as it streams
              --plain                     line-at-a-time prompts instead of the live screen (always so without a terminal)
              --reasoning LEVEL           none (off) | low | medium | high | … | default: how much the model reasons,
                                          over its profile's setting (the app's model settings)
              --endpoint NAME=URL         an OpenAI-compatible server for this run only (no key, not saved);
                                          use it with -m NAME:model
          -h, --help, --version

        In a session: /help for commands, @path to attach a file, !command to run one yourself, # to remember a fact.
        Type at any time: Enter queues during a run (messages go in at the next step, commands when it's done), ↑ takes
        one back. Esc stops a run, Shift-Tab changes the mode, Ctrl-O shows the last tool's output, Ctrl-V attaches an
        image, Ctrl-R searches history, Tab completes /commands and @paths; Ctrl-J, Alt-Enter or a trailing \\ starts
        a new line.
        API keys: KURTKODE_API_KEY_<ENDPOINT> in the environment (for Anthropic and Gemini endpoints also
        ANTHROPIC_API_KEY, GEMINI_API_KEY or GOOGLE_API_KEY), else the key the app stored in the Keychain.
        --endpoint with api.anthropic.com or generativelanguage.googleapis.com speaks their native APIs.
        """

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var o = CLIOptions()
        var args = arguments[...]
        var words: [String] = []
        func value(_ flag: String) throws -> String {
            guard let v = args.popFirst() else { throw ParseError(message: "\(flag) needs a value") }
            return v
        }
        while let a = args.popFirst() {
            switch a {
            case "-p", "--print": o.printMode = true
            case "-m", "--model": o.model = try value(a)
            case "--mode":
                let v = try value(a).lowercased()
                let modes: [String: PermissionMode] = ["ask": .ask, "edits": .acceptEdits, "acceptedits": .acceptEdits,
                                                       "plan": .plan, "auto": .fullAuto, "fullauto": .fullAuto]
                guard let m = modes[v] else { throw ParseError(message: "--mode wants ask, edits, plan, or auto") }
                o.mode = m
            case "-C", "--cwd": o.cwd = try value(a)
            case "--add-dir", "--read-dir":
                let path = (try value(a) as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                    throw ParseError(message: "\(a): \(path) isn't a folder")
                }
                o.folders.append(ExtraFolder(path: path, writable: a == "--add-dir"))
            case "-c", "--continue": o.continueLast = true
            case "-r", "--resume": o.resume = try value(a)
            case "--list-sessions": o.listSessions = true
            case "--output":
                guard let f = Output(rawValue: try value(a)) else { throw ParseError(message: "--output wants text, json, or stream-json") }
                o.output = f
            case "--max-steps":
                guard let n = Int(try value(a)), n > 0 else { throw ParseError(message: "--max-steps wants a positive number") }
                o.maxSteps = n
            case "--sandbox":
                guard let s = SandboxUse(rawValue: try value(a)) else { throw ParseError(message: "--sandbox wants fullAuto, always, or never") }
                o.sandbox = s
            case "--no-mcp": o.mcp = false
            case "--no-subagents": o.subagents = false
            case "--no-builtin-skills": o.builtinSkills = false
            case "--skill-router":
                guard let r = SkillRouting(rawValue: try value(a)) else { throw ParseError(message: "--skill-router wants auto, on, or off") }
                o.skillRouting = r
            case "--show-thinking": o.showThinking = true
            case "--plain": o.plain = true
            case "-w", "--worktree": o.worktree = try value(a)
            case "--reasoning":
                let level = try value(a).lowercased()
                let known = ["default", "none", "off", "minimal", "low", "medium", "high", "xhigh", "max"]
                guard known.contains(level) else { throw ParseError(message: "--reasoning takes " + known.joined(separator: ", ")) }
                o.reasoning = level
            case "--endpoint":
                let kv = try value(a).split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2, !kv[0].isEmpty, let url = URL(string: kv[1]), url.scheme?.hasPrefix("http") == true else {
                    throw ParseError(message: "--endpoint wants NAME=URL, for example mock=http://127.0.0.1:18090/v1")
                }
                o.extraEndpoints.append(ExtraEndpoint(name: kv[0], url: url))
            case "-h", "--help": o.help = true
            case "--version": o.version = true
            case "--": words += args; args = []
            case let flag where flag.hasPrefix("-") && flag.count > 1: throw ParseError(message: "unknown option \(flag) (see --help)")
            default: words.append(a)
            }
        }
        if !words.isEmpty { o.prompt = words.joined(separator: " ") }
        if o.continueLast && o.resume != nil { throw ParseError(message: "--continue and --resume don't go together") }
        return o
    }

    /// "endpoint:model" → (endpoint, model); a bare model uses the default endpoint. Model ids can contain
    /// colons (gemma:free), so only a known endpoint name before the first colon counts as one.
    public static func splitModel(_ spec: String, settings: AppSettings) -> (Endpoint, String) {
        if let colon = spec.firstIndex(of: ":"), let e = settings.endpoint(named: String(spec[..<colon])) {
            return (e, String(spec[spec.index(after: colon)...]))
        }
        return (settings.defaultEndpoint, spec)
    }

    /// `splitModel` for a model the user named, refusing a colon prefix that names no endpoint when it can't be part of
    /// a model id on the default endpoint: a misspelled endpoint (`lmstudo:qwen3`) mustn't send the prompt and the
    /// project's context to the default endpoint, which may be a keyed, remote one. Colons do occur in model ids:
    /// `vendor/model:free` (the part before the colon has a slash), Ollama's `qwen3:8b` (on a local server). So the
    /// whole spec stays a model id when the part before the colon has a slash or the default endpoint already has a
    /// profile for that id; otherwise it's refused when the part before the colon looks like a misspelled endpoint
    /// name, when the part after it looks like a model id of its own (it has a slash), or when the default endpoint is
    /// remote or keyed (whose ids don't take that form).
    public static func resolveModel(_ spec: String, settings: AppSettings) throws -> (Endpoint, String) {
        let (e, model) = splitModel(spec, settings: settings)
        guard let colon = spec.firstIndex(of: ":"), settings.endpoint(named: String(spec[..<colon])) == nil else { return (e, model) }
        let prefix = String(spec[..<colon]), rest = String(spec[spec.index(after: colon)...])
        if prefix.contains("/") || settings.profiles[ModelProfile.key(e.id, spec)] != nil || settings.defaultModel == spec {
            return (e, model)
        }
        let names = settings.endpoints.map(\.name) + (settings.endpoints.contains { $0.id == Endpoint.localLMStudio.id } ? [] : ["lmstudio"])
        let aliases = names + ["lmstudio"]
        let near = aliases.first { Self.editDistance(prefix.lowercased(), $0.lowercased()) <= (prefix.count >= 5 ? 2 : 1) }
        guard near == nil, !rest.contains("/"), !e.isThirdParty, !e.usesAPIKey else {
            throw ParseError(message: "no endpoint named \(prefix)" + (near.map { " (did you mean \($0)?)" } ?? "")
                             + "; endpoints: " + names.joined(separator: ", ") + ". Give endpoint:model, or `kurtkode endpoint list`.")
        }
        return (e, model)
    }

    /// Levenshtein distance, for "did you mean".
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let above = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = above
            }
        }
        return row[b.count]
    }

    /// The flags of the agent's command line that take a value (for finding a subcommand after them).
    static let valueFlags: Set<String> = ["-m", "--model", "--mode", "-C", "--cwd", "--add-dir", "--read-dir", "-r", "--resume",
                                          "--output", "--max-steps", "--sandbox", "--skill-router", "-w", "--worktree",
                                          "--reasoning", "--endpoint"]

    /// The arguments with a subcommand (one of `names`) moved to the front when it is the first word after leading
    /// global flags (`kurtkode -C ~/proj inspect`): it would otherwise be taken as a prompt and start a session.
    /// Nil when there's no subcommand there. `--` ends the flags: `kurtkode -- inspect` asks the model.
    public static func subcommandFirst(_ arguments: [String], names: Set<String>) -> [String]? {
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "--" { return nil }
            if !a.hasPrefix("-") || a.count == 1 {
                guard names.contains(a) else { return nil }
                return [a] + arguments[..<i] + arguments[(i + 1)...]
            }
            i += valueFlags.contains(a) ? 2 : 1
        }
        return nil
    }
}
