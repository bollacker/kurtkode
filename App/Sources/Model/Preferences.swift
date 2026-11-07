import AgentCore
import Foundation

/// User preferences, stored in UserDefaults. Views bind to the same keys with `@AppStorage`.
enum Pref {
    static let maxTokens = RunSettings.Key.maxTokens
    static let wallClockSeconds = RunSettings.Key.wallClockSeconds
    static let defaultContextLength = RunSettings.Key.defaultContextLength
    static let systemPrompt = RunSettings.Key.systemPrompt
    static let defaultModel = "defaultModel"
    static let defaultEndpointID = "defaultEndpointID"
    static let detectRepetition = RunSettings.Key.detectRepetition
    static let defaultPermissionMode = "defaultPermissionMode"
    static let maxSteps = RunSettings.Key.maxSteps
    /// ModelRef key of the model that writes compaction summaries; empty means the session's own model.
    static let summarizerModel = RunSettings.Key.summarizerModel
    /// Let the model think before writing a summary (default on; off asks for no reasoning).
    static let summaryThinking = RunSettings.Key.summaryThinking
    /// How long Anthropic keeps the prompt cache: auto (an hour for what you're watching), 5m or 1h.
    static let promptCacheTTL = RunSettings.Key.promptCacheTTL
    /// Dollars a run may spend before pausing (0: no limit; default 2).
    static let runCostLimit = RunSettings.Key.runCostLimit
    /// File patterns whose contents aren't sent to third-party models, one per line.
    static let withheldFromRemote = RunSettings.Key.withheldFromRemote
    /// Let Claude and Gemini search the web (off by default; billed per search).
    static let webSearch = RunSettings.Key.webSearch
    /// Ask before destructive commands in every mode (default on).
    static let guardDangerous = RunSettings.Key.guardDangerous
    /// Notify when a run finishes or needs approval while kurtkode is in the background (default on; the CLI rings the bell).
    static let notify = RunSettings.Key.notify
    /// System prompt style: "" automatic, "detailed", or "lean".
    static let promptStyle = RunSettings.Key.promptStyle
    /// Output tokens and time limit for Claude and Gemini replies (defaults 32,768 and 30 minutes).
    static let nativeMaxTokens = RunSettings.Key.nativeMaxTokens
    static let nativeWallClockSeconds = RunSettings.Key.nativeWallClockSeconds
    /// Dollars a session may spend in all (0: no limit, the default).
    static let sessionCostLimit = RunSettings.Key.sessionCostLimit
    /// ModelRef key of the model subagents use when their definition doesn't name one; empty: the main model.
    static let subagentModel = RunSettings.Key.subagentModel
    static let graderModel = RunSettings.Key.graderModel
    static let delegationAdvice = RunSettings.Key.delegationAdvice
    static let delegationForce = RunSettings.Key.delegationForce
    /// Offer kurtkode's built-in skills and mention skills in the system prompt (default on).
    static let builtinSkills = RunSettings.Key.builtinSkills
    /// SkillRouting raw value: auto (OpenAI-compatible servers), on, off.
    static let skillRouting = RunSettings.Key.skillRouting
    /// How many subagents may run at once on an endpoint other than this Mac's LM Studio.
    static let subagentParallel = RunSettings.Key.subagentParallel
    /// ModelRef key of the model that takes a turn whose tool call the server lost; empty: none.
    static let fallbackModel = RunSettings.Key.fallbackModel
    /// SandboxUse raw value: when commands run in the sandbox.
    static let sandboxUse = RunSettings.Key.sandboxUse
    static let sandboxNetwork = RunSettings.Key.sandboxNetwork
    /// More writable directories for sandboxed commands, one per line.
    static let sandboxWritable = RunSettings.Key.sandboxWritable

    /// The first-run sheet has been shown.
    static let welcomed = "welcomed"
    /// `Editor` raw value: where a changed file opens.
    static let editor = "editor"
    /// Have a chat's model title it after its first exchange (default on; requests whose first line reads as a title
    /// keep that, at no cost).
    static let autoTitles = "autoTitles"

    /// Whether plain chats get the file and command tools, and the folder they work in.
    static let chatTools = "chatTools"
    static let chatFolderPath = "chatFolder"
    /// A plain chat's working folder, or nil when chats don't get tools.
    static var chatFolder: URL? {
        guard d.bool(forKey: chatTools) else { return nil }
        let path = d.string(forKey: chatFolderPath).flatMap { $0.isEmpty ? nil : $0 } ?? defaultChatFolder
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
    static let defaultChatFolder = "~/kurtkode"
    /// Keep each model request and its raw response with the session, for the Debug window.
    static let recordWire = RunSettings.Key.recordWire
    /// Snapshot the project's files around each run, so command-made changes show and can be undone (C1).
    static let snapshots = RunSettings.Key.snapshots
    /// A4: offer to escalate to the next tier's model, and review cheaper models' changes first.
    static let escalationOffers = RunSettings.Key.escalationOffers
    static let escalationReview = RunSettings.Key.escalationReview
    /// D3: retry a subagent run that failed outright on the next rung (off by default since the cost audit).
    static let subagentRetry = RunSettings.Key.subagentRetry
    /// What an hour of waiting is worth, for the Spending window's time cost (0 hides it).
    static let hourlyRate = RunSettings.Key.hourlyRate

    /// The run settings (limits, sandbox, prompt text, summarizer and subagent models), as the command line reads them too.
    static var run: RunSettings { RunSettings(defaults: d) }

    /// The sandbox for a run in `mode`, or nil.
    static func sandbox(for mode: PermissionMode) -> SandboxPolicy? { run.sandbox(for: mode) }

    static func register() {
        UserDefaults.standard.register(defaults: [
            maxTokens: 8192,
            wallClockSeconds: 600,
            defaultContextLength: 32768,
            systemPrompt: "",
            defaultModel: "qwen/qwen3-coder-30b",
            detectRepetition: true,
            defaultPermissionMode: PermissionMode.ask.rawValue,
            maxSteps: 100,
            sandboxUse: SandboxUse.fullAuto.rawValue,
            sandboxNetwork: false,
            sandboxWritable: "",
            chatTools: true,
            recordWire: true,
            chatFolderPath: defaultChatFolder,
        ])
    }

    static var d: UserDefaults { .standard }
}
