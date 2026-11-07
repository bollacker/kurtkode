import AgentCore
import Foundation

/// What the command line shares with the app: its data folder (endpoints, profiles, sessions, MCP
/// approvals) and its preferences (read from the app's defaults domain; the app's defaults apply when unset).
public struct AppSettings: @unchecked Sendable {
    public static let appDomain = "org.mlcommons.kurt.kurtkode"

    public let support: URL
    public let defaults: UserDefaults
    public var endpoints: [Endpoint]
    public var profiles: [String: ModelProfile]
    let environment: [String: String]
    /// Where saved keys are read: the Keychain (tests put a stand-in here, to see that nothing reads it).
    var keychain: @Sendable (UUID) -> String? = { KeychainStore().apiKey(for: $0) }

    public init(support: URL? = nil, defaults: UserDefaults? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let root = support ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "kurtkode")
        self.support = root
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appDomain) ?? .standard
        endpoints = EndpointStore(fileURL: root.appending(path: "endpoints.json")).load()
        profiles = ProfileStore(fileURL: root.appending(path: "profiles.json")).load()
        self.environment = environment
    }

    public var sessionStore: SessionStore { SessionStore(root: support.appending(path: "sessions")) }
    /// The model pool (`pool.json`, else the shipped one).
    public var poolURL: URL { support.appending(path: "pool.json") }
    public var pool: ModelPool { ModelPool.load(poolURL) }
    public var mcpApprovals: MCPApprovals { MCPApprovals(fileURL: support.appending(path: "mcp-approvals.json")) }

    /// A variable of the environment this process was given.
    func environmentValue(_ name: String) -> String? { environment[name].flatMap { $0.isEmpty ? nil : $0 } }

    func string(_ key: String) -> String? { defaults.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 } }

    /// Limits, sandbox, system prompt text, summarizer and subagent models: read the way the app reads them.
    public var run: RunSettings { RunSettings(defaults: defaults) }
    public var defaultModel: String { string("defaultModel") ?? "qwen/qwen3-coder-30b" }
    public var defaultMode: PermissionMode { string("defaultPermissionMode").flatMap(PermissionMode.init(rawValue:)) ?? .ask }

    public var defaultEndpoint: Endpoint {
        let id = string("defaultEndpointID").flatMap(UUID.init(uuidString:))
        return endpoints.first { $0.id == id } ?? endpoints.first ?? .localLMStudio
    }

    public func endpoint(_ id: UUID) -> Endpoint? { endpoints.first { $0.id == id } }

    /// By name (case-insensitive; spaces may be written as dashes), or "lmstudio"/"local" for this Mac.
    public func endpoint(named name: String) -> Endpoint? {
        let key = name.lowercased()
        // The app calls it "This Mac (LM Studio)": that name, or "This Mac", is the local server too (it fell through to
        // the default endpoint, a keyed one here, and read its key).
        if ["lmstudio", "local", "this mac", Endpoint.localLMStudio.name.lowercased()].contains(key) {
            return endpoints.first { $0.id == Endpoint.localLMStudio.id } ?? .localLMStudio
        }
        return endpoints.first { $0.name.lowercased() == key || $0.name.lowercased().replacingOccurrences(of: " ", with: "-") == key }
    }

    /// Adds endpoints given at launch (`--endpoint NAME=URL`). A name that already means an endpoint (a saved one, an
    /// earlier `--endpoint`, or "lmstudio"/"local") is refused: `endpoint(named:)` would pick the other one, and the
    /// run would go to a server the user didn't name.
    public mutating func addLaunchEndpoints(_ extra: [Endpoint]) throws {
        for e in extra {
            if let taken = endpoint(named: e.name) {
                throw CLIOptions.ParseError(message: "--endpoint \(e.name): that name is taken by \(taken.name) (\(taken.baseURL.absoluteString)); "
                                            + "give the launch endpoint another name")
            }
            endpoints.append(e)
        }
    }

    public func profile(_ endpointID: UUID, _ model: String) -> ModelProfile {
        profiles[ModelProfile.key(endpointID, model)] ?? ModelProfile.defaults(endpointID: endpointID, model: model)
    }

    /// `KURTKODE_API_KEY_<ENDPOINT>` from the environment, else the key the app saved in the Keychain.
    public func apiKey(for e: Endpoint) -> String? {
        guard e.usesAPIKey else { return nil }
        let envName = "KURTKODE_API_KEY_" + e.name.uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        if let k = environment[envName], !k.isEmpty { return k }
        for name in e.kind.standardKeyVariables { if let k = environment[name], !k.isEmpty { return k } }
        // KURTKODE_NO_KEYCHAIN=1, as for the app: no Keychain reads (a fresh build's read puts a prompt on the screen).
        if environment["KURTKODE_NO_KEYCHAIN"] == "1" { return nil }
        return keychain(e.id)
    }
}
