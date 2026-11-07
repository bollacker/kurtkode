import CryptoKit
import Foundation

/// One MCP server from a config file, in the shape Claude Code and Claude Desktop use:
/// `{"mcpServers": {"name": {"command": "npx", "args": [...], "env": {...}}}}`, or
/// `{"type": "http", "url": "...", "headers": {...}}` for a remote server.
public struct MCPServerConfig: Codable, Sendable, Hashable {
    public var command: String?
    public var args: [String]?
    public var env: [String: String]?
    public var type: String?
    public var url: String?
    public var headers: [String: String]?
    /// kurtkode extension: skip this server without deleting it.
    public var disabled: Bool?

    public init(command: String? = nil, args: [String]? = nil, env: [String: String]? = nil, type: String? = nil,
                url: String? = nil, headers: [String: String]? = nil, disabled: Bool? = nil) {
        self.command = command
        self.args = args
        self.env = env
        self.type = type
        self.url = url
        self.headers = headers
        self.disabled = disabled
    }

    public var isHTTP: Bool { url != nil && (type == nil || type == "http" || type == "streamable-http") }
    /// MCP's older HTTP+SSE transport (2024-11-05), which kurtkode doesn't speak.
    public var isLegacySSE: Bool { type == "sse" }

    /// What an approval covers: the exact command, arguments, environment keys and values, or URL.
    /// A project's server must be approved again when any of these change.
    public var fingerprint: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = (try? enc.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The command line as the user would read it.
    public var displayCommand: String {
        if let url { return url }
        return ([command ?? "?"] + (args ?? [])).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    /// What an approval shows besides `displayCommand`, one line each: every environment variable with its value
    /// (`NODE_OPTIONS=--require ./x.js` changes what a well-known command runs) and every header's name, with its value
    /// unless it looks like a secret (then only that it's set). The fingerprint covers all of these.
    public var approvalDetails: [String] {
        var lines = (env ?? [:]).sorted(by: { $0.key < $1.key }).map { "env \($0.key)=\($0.value)" }
        lines += (headers ?? [:]).sorted(by: { $0.key < $1.key }).map { name, value in
            "header \(name): " + (Self.looksSecret(name: name, value: value) ? "(set, value hidden)" : value)
        }
        if [command, url].compactMap({ $0 }).contains(where: { $0.contains("${") })
            || (args ?? []).contains(where: { $0.contains("${") }) || (env ?? [:]).values.contains(where: { $0.contains("${") })
            || (headers ?? [:]).values.contains(where: { $0.contains("${") }) {
            lines.append("${…} is passed as written: a project's server doesn't get kurtkode's environment variables")
        }
        return lines
    }

    /// A header value not to print: credentials by name, or a long unbroken token.
    static func looksSecret(name: String, value: String) -> Bool {
        let n = name.lowercased()
        if ["auth", "token", "key", "secret", "cookie", "password", "session", "credential"].contains(where: { n.contains($0) }) {
            return true
        }
        let v = value.trimmingCharacters(in: .whitespaces)
        if v.lowercased().hasPrefix("bearer ") || v.lowercased().hasPrefix("basic ") { return true }
        return v.count >= 20 && !v.contains(" ") && v.contains(where: \.isNumber) && v.contains(where: \.isLetter)
    }
}

public enum MCPScope: String, Sendable, Codable {
    /// `~/.kurtkode/mcp.json`: written by the user, trusted.
    case user
    /// `<project>/.mcp.json`: may come with a cloned repository, so each server needs approval.
    case project
}

public struct MCPServerEntry: Sendable, Hashable, Identifiable {
    public var name: String
    public var config: MCPServerConfig
    public var scope: MCPScope
    public var id: String { "\(scope.rawValue):\(name)" }
}

public enum MCPConfigFile {
    struct File: Codable { var mcpServers: [String: MCPServerConfig]? }

    public static func userFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".kurtkode/mcp.json")
    }

    public static func projectFile(_ workspace: URL) -> URL { workspace.appending(path: ".mcp.json") }

    /// Servers from the user's file, then the project's; a project server with a user server's name is
    /// dropped (the user's wins). Throws with the file name when a file isn't valid JSON.
    public static func load(workspace: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [MCPServerEntry] {
        var out: [MCPServerEntry] = []
        for (file, scope) in [(userFile(home: home), MCPScope.user)] + (workspace.map { [(projectFile($0), MCPScope.project)] } ?? []) {
            guard let data = try? Data(contentsOf: file) else { continue }
            let parsed: File
            do { parsed = try JSONDecoder().decode(File.self, from: data) }
            catch { throw MCPError.config("\(file.path) isn't a valid MCP config: \(error.localizedDescription)") }
            for (name, config) in (parsed.mcpServers ?? [:]).sorted(by: { $0.key < $1.key })
            where !out.contains(where: { $0.name == name }) {
                // `${VAR}` comes from kurtkode's environment only for the user's own file: a project's file could
                // otherwise send any of its variables (an API key in a header) to a server of its choosing.
                out.append(MCPServerEntry(name: name, config: scope == .user ? expand(config) : config, scope: scope))
            }
        }
        return out
    }

    /// `${VAR}` and `${VAR:-default}` in commands, arguments, env values, URLs, and headers.
    static func expand(_ c: MCPServerConfig, environment: [String: String] = ProcessInfo.processInfo.environment) -> MCPServerConfig {
        func x(_ s: String) -> String {
            var out = "", rest = Substring(s)
            while let open = rest.range(of: "${"), let close = rest[open.upperBound...].firstIndex(of: "}") {
                out += rest[..<open.lowerBound]
                let body = String(rest[open.upperBound..<close])
                let parts = body.components(separatedBy: ":-")
                out += environment[parts[0]] ?? (parts.count > 1 ? parts[1...].joined(separator: ":-") : "")
                rest = rest[rest.index(after: close)...]
            }
            return out + rest
        }
        var c = c
        c.command = c.command.map(x)
        c.args = c.args?.map(x)
        c.env = c.env?.mapValues(x)
        c.url = c.url.map(x)
        c.headers = c.headers?.mapValues(x)
        return c
    }
}

/// Which project servers the user approved: (project, name, fingerprint), in a JSON file.
public struct MCPApprovals: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    static func key(_ workspace: URL, _ entry: MCPServerEntry) -> String {
        "\(workspace.standardizedFileURL.path)|\(entry.name)|\(entry.config.fingerprint)"
    }

    public func isApproved(_ entry: MCPServerEntry, workspace: URL?) -> Bool {
        guard entry.scope == .project else { return true }
        guard let workspace else { return false }
        return load().contains(Self.key(workspace, entry))
    }

    public func approve(_ entry: MCPServerEntry, workspace: URL) throws {
        var set = load()
        set.insert(Self.key(workspace, entry))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(set.sorted()).write(to: fileURL, options: .atomic)
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }
}

public enum MCPError: Error, LocalizedError, Sendable, Equatable {
    case config(String)
    case transport(String)
    case timeout(String)
    case server(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .config(let s), .transport(let s): s
        case .timeout(let s): "Timed out: \(s)"
        case .server(let code, let message): "MCP error \(code): \(message)"
        }
    }
}

/// The PATH an interactive login shell has. Apps started from the Finder get a minimal PATH, so servers
/// run with `npx` or `uvx` (installed through nvm, Homebrew, pyenv, ~/.local/bin) wouldn't be found.
public enum LoginShell {
    private static let cache = PathCache()

    public static func path() -> String {
        if let p = cache.value { return p }
        let marker = "__KURTKODE_PATH__"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        var found: String?
        if (try? p.run()) != nil {
            let deadline = DispatchTime.now() + 5
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { p.waitUntilExit(); done.signal() }
            if done.wait(timeout: deadline) == .timedOut { p.terminate() }
            let text = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
            if let a = text.range(of: marker), let b = text.range(of: marker, range: a.upperBound..<text.endIndex) {
                found = String(text[a.upperBound..<b.lowerBound])
            }
        }
        let value = found ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        cache.value = value
        return value
    }

    final class PathCache: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: String?
        var value: String? {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }
}
