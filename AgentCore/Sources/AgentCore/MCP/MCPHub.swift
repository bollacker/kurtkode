import CryptoKit
import Foundation

/// A tool from an MCP server, offered to the model as `mcp__<server>__<tool>`. Outside tools can do
/// anything, so they count as actions: they ask in Ask and Accept Edits, and aren't offered in Plan mode.
public struct MCPTool: Tool {
    public let server: String
    public let toolName: String
    /// What the model calls it: `exposedName`, or with a hash of the server and tool when that name is taken (see
    /// `MCPHub.allTools`).
    public private(set) var name: String
    public let description: String
    public let parameters: JSONValue
    public let risk = ToolRisk.execute
    /// The server says it changes nothing (`ToolInfo.readOnly`).
    public let readOnly: Bool
    let client: MCPClient

    init(server: String, info: MCPClient.ToolInfo, client: MCPClient) {
        self.server = server
        readOnly = info.readOnly
        toolName = info.name
        name = Self.exposedName(server: server, tool: info.name)
        description = "[\(server) MCP server] " + (info.description.isEmpty ? info.name : info.description)
        // Models and servers alike expect an object schema; some servers omit the type.
        if case .object(var o) = info.inputSchema {
            if o["type"] == nil { o["type"] = "object" }
            if o["properties"] == nil { o["properties"] = .object([:]) }
            parameters = .object(o)
        } else {
            parameters = ["type": "object", "properties": .object([:])]
        }
        self.client = client
    }

    static func cleanName(_ s: String) -> String { String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }) }

    /// `mcp__server__tool` with only [A-Za-z0-9_-] (what OpenAI-style APIs accept), at most 64 characters.
    static func exposedName(server: String, tool: String) -> String {
        let full = "mcp__\(cleanName(server))__\(cleanName(tool))"
        guard full.count > 64 else { return full }
        let hash = SHA256.hash(data: Data(full.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
        return String(full.prefix(57)) + "_" + hash
    }

    /// Another name for a tool whose exposed name another server's tool already has (`a.b` and `a_b` both clean to
    /// `a_b`): the name cut to 57 characters plus a hash of the exact server and tool names, so it's stable across runs.
    func renamedForCollision(salt: Int = 0) -> MCPTool {
        var copy = self
        let key = "\(server)\u{0}\(toolName)" + (salt == 0 ? "" : "\u{0}\(salt)")
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
        copy.name = String(Self.exposedName(server: server, tool: toolName).prefix(57)) + "_" + hash
        return copy
    }

    public func summary(_ args: ToolArguments) -> String {
        Self.summary(server: server, tool: toolName, args)
    }

    static func summary(server: String, tool: String, _ args: ToolArguments) -> String {
        let json = TextToolCalls.encode(.object(args.values))
        return "\(server): \(tool) " + (json.count > 70 ? String(json.prefix(67)) + "…" : json)
    }

    /// For a stored call whose server may not be running any more: "server: tool {args}" from the name.
    public static func summary(forCallNamed name: String, arguments: String) -> String? {
        guard name.hasPrefix("mcp__") else { return nil }
        let parts = name.dropFirst(5).components(separatedBy: "__")
        guard parts.count >= 2 else { return nil }
        let args = (try? ToolArguments(json: arguments)) ?? ToolArguments()
        return summary(server: parts[0], tool: parts[1...].joined(separator: "__"), args)
    }

    public func preview(_ args: ToolArguments, context: ToolContext) async throws -> ToolPreview? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = (try? enc.encode(JSONValue.object(args.values))).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return .call(title: "\(toolName) on the \(server) MCP server", arguments: json)
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let result = try await client.callTool(toolName, arguments: .object(args.values))
        let (text, truncated) = BashTool.capHeadTail(result.text.isEmpty ? "(no output)" : result.text, maxBytes: context.maxOutputBytes)
        return ToolOutput(text: result.isError ? "Error from \(server): " + text : text, isError: result.isError, truncated: truncated)
    }
}

/// The MCP servers for one project (plus the user's own): reads the config, starts the servers the user
/// trusts, and serves their tools. Project servers wait for approval.
public actor MCPHub {
    /// The tools that read a server's resources: one tool for all the servers, so their names don't say which.
    static let resourceTools = ["mcp_list_resources", "mcp_read_resource"]

    public enum State: Sendable, Hashable {
        case disabled
        case needsApproval
        case starting
        case ready
        case failed(String)
    }

    public struct Status: Sendable, Hashable, Identifiable {
        public var entry: MCPServerEntry
        public var state: State
        public var toolNames: [String] = []
        public var serverInfo: String?
        public var id: String { entry.id }
    }

    public let workspace: URL?
    let home: URL
    let approvals: MCPApprovals
    private var statuses: [String: Status] = [:]
    private var order: [String] = []
    private var clients: [String: MCPClient] = [:]
    /// Bumped by every start and stop of a server, by name: a start that finishes (connecting can take a minute)
    /// after another start, a stop or the server's removal from the config closes its client instead of keeping it.
    private var generations: [String: Int] = [:]
    private var tools: [String: [MCPTool]] = [:]
    private var resourceServers: Set<String> = []
    private var serverInstructions: [String: String] = [:]
    private var configError: String?
    private var changed: (@Sendable () -> Void)?

    /// The token for an HTTP server (from the Keychain, by server name and host).
    let token: @Sendable (MCPServerEntry) -> String?
    let httpSession: URLSession

    public init(workspace: URL?, approvals: MCPApprovals, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                token: @escaping @Sendable (MCPServerEntry) -> String? = MCPHub.keychainToken, httpSession: URLSession = .shared) {
        self.workspace = workspace
        self.approvals = approvals
        self.home = home
        self.token = token
        self.httpSession = httpSession
    }

    public static let keychainToken: @Sendable (MCPServerEntry) -> String? = { entry in
        guard let url = entry.config.url else { return nil }
        return KeychainStore.mcp.secret(account: KeychainStore.mcpAccount(server: entry.name, url: url))
    }

    /// Called (from any thread) whenever a server's state or tools change.
    public func onChange(_ handler: @escaping @Sendable () -> Void) { changed = handler }

    public var statusList: [Status] { order.compactMap { statuses[$0] } }
    public var configProblem: String? { configError }

    /// Every ready server's tools, and the two that read resources when a server has any. Names are unique: cleaning
    /// can make two tools' names the same (`a.b` and `a_b`, or server `x` with tool `y__z` and server `x__y` with tool
    /// `z`), and providers refuse a request that offers two tools by one name. The later one gets a hashed name, and
    /// since each `MCPTool` carries its own client, calling it by that name reaches the right server.
    public var allTools: [any Tool] {
        var taken = Set(Self.resourceTools), seen = Set<String>(), own: [any Tool] = []
        for tool in order.flatMap({ tools[$0] ?? [] }) {
            guard seen.insert("\(tool.server)\u{0}\(tool.toolName)").inserted else { continue }   // a server listing a tool twice
            var unique = tool, salt = 0
            while taken.contains(unique.name) {
                unique = tool.renamedForCollision(salt: salt)
                salt += 1
            }
            taken.insert(unique.name)
            own.append(unique)
        }
        let servers = clients.filter { resourceServers.contains($0.key) }
        return servers.isEmpty ? own : own + [MCPResourceList(servers: servers), MCPResourceRead(servers: servers)]
    }

    /// What servers want the agent told, by server: their `instructions`.
    public var instructions: [(server: String, text: String)] {
        order.compactMap { name in serverInstructions[name].map { (name, $0) } }
    }

    /// A message for the model with what servers say about themselves and it hasn't been told yet, or nil. Marked as theirs:
    /// the user approved the server, not everything it says.
    public func instructionNote(alreadySent messages: [ChatMessage]) -> String? {
        let new = instructions.filter { i in !messages.contains { $0.contextNote == true && $0.content.contains(Self.noteHeader(i.server)) } }
        guard !new.isEmpty else { return nil }
        return new.map { Self.noteHeader($0.server) + "\n" + $0.text }.joined(separator: "\n\n")
    }

    static func noteHeader(_ server: String) -> String { "[What the \(server) MCP server says about using it:]" }

    /// Re-reads the config files: starts new or changed servers that are trusted, stops removed ones.
    public func reload() async {
        let entries: [MCPServerEntry]
        do {
            entries = try MCPConfigFile.load(workspace: workspace, home: home)
            configError = nil
        } catch {
            configError = error.localizedDescription
            changed?()
            return
        }
        let names = Set(entries.map(\.name))
        for name in order where !names.contains(name) { await stop(name, forget: true) }
        order = entries.map(\.name)
        await withTaskGroup(of: Void.self) { group in
            for entry in entries {
                let same = statuses[entry.name]?.entry == entry
                if same, clients[entry.name] != nil || statuses[entry.name]?.state == .starting { continue }
                if !same { await stop(entry.name, forget: false) }
                group.addTask { await self.startIfAllowed(entry) }
            }
        }
        changed?()
    }

    private func startIfAllowed(_ entry: MCPServerEntry) async {
        if entry.config.disabled == true { set(entry, .disabled); return }
        if entry.config.isLegacySSE {
            set(entry, .failed("This server uses MCP's older HTTP+SSE transport, which kurtkode doesn't support. If it also "
                               + "offers Streamable HTTP (often a URL ending in /mcp), use \"type\": \"http\" with that URL."))
            return
        }
        guard approvals.isApproved(entry, workspace: workspace) else { set(entry, .needsApproval); return }
        await start(entry)
    }

    private func start(_ entry: MCPServerEntry) async {
        let generation = (generations[entry.name] ?? 0) + 1
        generations[entry.name] = generation
        set(entry, .starting)
        let transport: MCPTransport
        if entry.config.isHTTP, let raw = entry.config.url {
            guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else {
                set(entry, .failed("\(raw) isn't an http(s) URL."))
                return
            }
            var headers = entry.config.headers ?? [:]
            // The Keychain token, unless the config sets its own Authorization header.
            if !headers.keys.contains(where: { $0.lowercased() == "authorization" }), let token = token(entry), !token.isEmpty {
                headers["Authorization"] = "Bearer \(token)"
            }
            // A token over plain http can be read by anyone on the way, so it goes only to this machine.
            if url.scheme == "http", !HTTPTransport.isLoopback(url), headers.keys.contains(where: { $0.lowercased() == "authorization" }) {
                set(entry, .failed("\(raw) is plain http, and kurtkode won't send this server's token unencrypted to another "
                                   + "machine. Use an https URL (or a server on localhost)."))
                return
            }
            transport = HTTPTransport(url: url, headers: headers, session: httpSession)
        } else if let command = entry.config.command, !command.isEmpty {
            transport = StdioTransport(command: command, arguments: entry.config.args ?? [], environment: entry.config.env ?? [:],
                                       cwd: workspace)
        } else {
            set(entry, .failed("No command or url given."))
            return
        }
        let client = MCPClient(transport: transport)
        /// Whether this start is still the one wanted: no later start or stop, and the server is still configured.
        func current() -> Bool { generations[entry.name] == generation && order.contains(entry.name) }
        do {
            let info = try await client.connect()
            let list = try await client.listTools()
            guard current() else { await client.close(); return }
            if let old = clients[entry.name], old !== client { await old.close() }
            clients[entry.name] = client
            tools[entry.name] = list.map { MCPTool(server: entry.name, info: $0, client: client) }
            if info.hasResources { resourceServers.insert(entry.name) }
            serverInstructions[entry.name] = info.instructions.flatMap { $0.isEmpty ? nil : String($0.prefix(4000)) }
            var s = Status(entry: entry, state: .ready)
            s.toolNames = list.map(\.name)
            s.serverInfo = "\(info.name) \(info.version)"
            statuses[entry.name] = s
            let name = entry.name
            await client.onToolsChanged { [weak self] in Task { await self?.refreshTools(name) } }
            await client.onClosed { [weak self, weak client] why in
                Task { if let client { await self?.serverStopped(name, client, why) } }
            }
            changed?()
        } catch {
            await client.close()
            if current() { set(entry, .failed(error.localizedDescription)) }
        }
    }

    private func refreshTools(_ name: String) async {
        guard let client = clients[name], let list = try? await client.listTools() else { return }
        tools[name] = list.map { MCPTool(server: name, info: $0, client: client) }
        statuses[name]?.toolNames = list.map(\.name)
        changed?()
    }

    /// A ready server's connection ended by itself (it exited or dropped the connection): its tools go, and the
    /// status says so, until it's restarted.
    private func serverStopped(_ name: String, _ client: MCPClient, _ why: String) {
        guard let current = clients[name], current === client, let entry = statuses[name]?.entry else { return }
        clients[name] = nil
        tools[name] = nil
        resourceServers.remove(name)
        serverInstructions[name] = nil
        set(entry, .failed("Stopped. \(why)\nRestart it to use its tools again."))
    }

    private func set(_ entry: MCPServerEntry, _ state: State) {
        var s = statuses[entry.name] ?? Status(entry: entry, state: state)
        s.entry = entry
        s.state = state
        if state != .ready { s.toolNames = [] }
        statuses[entry.name] = s
        changed?()
    }

    private func stop(_ name: String, forget: Bool) async {
        generations[name, default: 0] += 1
        tools[name] = nil
        resourceServers.remove(name)
        serverInstructions[name] = nil
        if let c = clients.removeValue(forKey: name) { await c.close() }
        if forget { statuses[name] = nil }
    }

    /// Trusts a project server (for its exact command) and starts it.
    public func approve(_ name: String) async throws {
        guard let entry = statuses[name]?.entry, let workspace else { return }
        try approvals.approve(entry, workspace: workspace)
        await start(entry)
    }

    public func restart(_ name: String) async {
        guard let entry = statuses[name]?.entry else { return }
        await stop(name, forget: false)
        await startIfAllowed(entry)
    }

    /// Waits (up to `timeout`) while any server is still starting, so the first request sees its tools.
    public func waitForStartup(timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while statuses.values.contains(where: { $0.state == .starting }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    public func shutdown() async {
        for name in Array(clients.keys) { await stop(name, forget: false) }
    }
}

/// Lists what the MCP servers offer as resources (documents, records), by server.
struct MCPResourceList: Tool {
    let servers: [String: MCPClient]
    let name = MCPHub.resourceTools[0]
    let description = "List the resources MCP servers offer: their URIs, names and descriptions. Read one with mcp_read_resource."
    let parameters: JSONValue = ["type": "object", "properties": .object([:])]
    let risk = ToolRisk.execute

    func summary(_ args: ToolArguments) -> String { "List MCP resources" }

    func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        var lines: [String] = []
        for (name, client) in servers.sorted(by: { $0.key < $1.key }) {
            do {
                for r in try await client.listResources() {
                    lines.append("\(name)  \(r.uri)  \(r.name)" + (r.description.isEmpty ? "" : ": " + r.description))
                }
            } catch { lines.append("\(name): \(error.localizedDescription)") }
        }
        let (text, truncated) = BashTool.capHeadTail(lines.isEmpty ? "No resources." : lines.joined(separator: "\n"), maxBytes: context.maxOutputBytes)
        return ToolOutput(text: text, truncated: truncated)
    }
}

/// Reads one MCP resource.
struct MCPResourceRead: Tool {
    let servers: [String: MCPClient]
    let name = MCPHub.resourceTools[1]
    let description = "Read a resource from an MCP server, by the server's name and the resource's URI (see mcp_list_resources)."
    let parameters: JSONValue = [
        "type": "object",
        "properties": ["server": ["type": "string"], "uri": ["type": "string"]],
        "required": ["server", "uri"],
    ]
    let risk = ToolRisk.execute

    func summary(_ args: ToolArguments) -> String { "Read \(args.string("uri") ?? "?") from \(args.string("server") ?? "?")" }

    func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let server = try args.require("server")
        guard let client = servers[server] else { throw ToolFailure("there's no MCP server called \(server) with resources") }
        let text = try await client.readResource(try args.require("uri"))
        let (capped, truncated) = BashTool.capHeadTail(text.isEmpty ? "(empty)" : text, maxBytes: context.maxOutputBytes)
        return ToolOutput(text: capped, truncated: truncated)
    }
}
