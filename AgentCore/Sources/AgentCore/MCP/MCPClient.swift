import Darwin
import Foundation

/// Moves JSON-RPC messages to and from an MCP server.
public protocol MCPTransport: Sendable {
    /// Starts the connection. `onMessage` gets each message; `onClose` is called once when it ends.
    func start(onMessage: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable (String?) -> Void) async throws
    func send(_ message: Data) async throws
    func close() async
    /// After the handshake: the protocol version agreed on (HTTP sends it on every request).
    func setProtocolVersion(_ version: String) async
    /// After the handshake: open a channel for messages the server starts (HTTP's GET stream).
    func listen() async
}

extension MCPTransport {
    public func setProtocolVersion(_ version: String) async {}
    public func listen() async {}
}

/// A server run as a child process, speaking newline-delimited JSON-RPC on stdin and stdout. stderr is
/// kept (its end) to explain failures. The process gets its own process group, so closing stops helpers
/// it started too (npx starts node, which starts the server).
public final class StdioTransport: MCPTransport, @unchecked Sendable {
    let command: String
    let arguments: [String]
    let environment: [String: String]
    let cwd: URL?
    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var stderrTail = Data()
    private var closed = false

    public init(command: String, arguments: [String] = [], environment: [String: String] = [:], cwd: URL? = nil) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.cwd = cwd
    }

    public func start(onMessage: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable (String?) -> Void) async throws {
        let p = Process()
        // Through /usr/bin/env, so a bare name (npx, uvx) is looked up on the login shell's PATH.
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [command] + arguments
        // kurtkode's own API keys stay out; what the server's configuration sets explicitly is kept.
        var env = ChildEnvironment.inherited
        env["PATH"] = LoginShell.path()
        for (k, v) in environment { env[k] = v }
        p.environment = env
        if let cwd { p.currentDirectoryURL = cwd }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.terminationHandler = { [weak self] proc in
            Self.running.remove(proc.processIdentifier)
            guard let self else { return }
            let why = self.lock.withLock { () -> String? in
                if self.closed { return nil }
                self.closed = true
                let tail = String(decoding: self.stderrTail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return "The server exited (status \(proc.terminationStatus))" + (tail.isEmpty ? "." : ": " + String(tail.suffix(600)))
            }
            onClose(why)
        }
        do { try p.run() } catch {
            throw MCPError.transport("Couldn't start \(command): \(error.localizedDescription)")
        }
        setpgid(p.processIdentifier, p.processIdentifier)
        lock.withLock { process = p; stdin = inPipe.inputForChild }
        Self.running.insert(p.processIdentifier)

        // stdout: one JSON-RPC message per line.
        Thread.detachNewThread {
            let handle = outPipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) { onMessage(Data(line)) }
                }
            }
        }
        Thread.detachNewThread { [weak self] in
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                guard let self else { continue }
                self.lock.withLock {
                    self.stderrTail.append(chunk)
                    if self.stderrTail.count > 8192 { self.stderrTail = self.stderrTail.suffix(4096) }
                }
            }
        }
    }

    /// Process ids of every running server, so the app can stop them all when it quits.
    static let running = PIDSet()

    /// Stops every server's process group now (for app termination, where there's no time for async work).
    public static func terminateAll() {
        for pid in running.all { kill(-pid, SIGTERM) }
    }

    final class PIDSet: @unchecked Sendable {
        private let lock = NSLock()
        private var set = Set<pid_t>()
        func insert(_ p: pid_t) { lock.withLock { _ = set.insert(p) } }
        func remove(_ p: pid_t) { lock.withLock { _ = set.remove(p) } }
        var all: [pid_t] { lock.withLock { Array(set) } }
    }

    public func send(_ message: Data) async throws {
        guard let handle = lock.withLock({ closed ? nil : stdin }) else { throw MCPError.transport("The server isn't running.") }
        do { try handle.write(contentsOf: message + Data([0x0A])) }
        catch { throw MCPError.transport("Couldn't write to the server: \(error.localizedDescription)") }
    }

    public func close() async {
        let p: Process? = lock.withLock {
            closed = true
            return process
        }
        guard let p, p.isRunning else { return }
        try? lock.withLock { stdin }?.close()          // well-behaved servers exit on EOF
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if p.isRunning { kill(-pid, SIGTERM) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(-pid, SIGKILL) } }
        }
    }
}

/// An MCP client over any transport: initialize, list tools, call them.
public actor MCPClient {
    public struct ServerInfo: Sendable, Hashable {
        public var name: String
        public var version: String
        public var protocolVersion: String
        public var instructions: String?
        /// It says it serves resources.
        public var hasResources = false
    }

    public struct ToolInfo: Sendable, Hashable {
        public var name: String
        public var description: String
        public var inputSchema: JSONValue
        /// The server says the tool changes nothing. Its word, so it's never a reason to skip asking: only to offer the
        /// tool in Plan mode, where it still asks.
        public var readOnly = false
    }

    public struct ResourceInfo: Sendable, Hashable {
        public var uri: String
        public var name: String
        public var description: String
        public var mimeType: String?
    }

    public struct CallResult: Sendable, Hashable {
        public var text: String
        public var isError: Bool
    }

    public static let protocolVersion = "2025-06-18"

    let transport: MCPTransport
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var closedReason: String?
    private var toolsChanged: (@Sendable () -> Void)?
    private var onClose: (@Sendable (String) -> Void)?
    public private(set) var server: ServerInfo?

    public init(transport: MCPTransport) { self.transport = transport }

    /// Starts the transport and does the initialize handshake.
    @discardableResult
    public func connect(timeout: TimeInterval = 60) async throws -> ServerInfo {
        try await transport.start(
            onMessage: { [weak self] data in Task { await self?.receive(data) } },
            onClose: { [weak self] why in Task { await self?.closed(why) } })
        let result = try await request("initialize", [
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": ["name": "kurtkode", "version": "0.1"],
        ], timeout: timeout)
        guard case .object(let o) = result else { throw MCPError.transport("The server's initialize reply wasn't an object.") }
        var info = ServerInfo(name: "?", version: "?", protocolVersion: o["protocolVersion"]?.stringValue ?? "?",
                              instructions: o["instructions"]?.stringValue)
        if case .object(let s)? = o["serverInfo"] {
            info.name = s["name"]?.stringValue ?? "?"
            info.version = s["version"]?.stringValue ?? "?"
        }
        if case .object(let c)? = o["capabilities"] { info.hasResources = c["resources"] != nil }
        server = info
        await transport.setProtocolVersion(info.protocolVersion)
        try await notify("notifications/initialized")
        await transport.listen()
        return info
    }

    public func onToolsChanged(_ handler: @escaping @Sendable () -> Void) { toolsChanged = handler }
    /// Called once when the connection ends by itself (the server exited or dropped it), not on `close()`.
    public func onClosed(_ handler: @escaping @Sendable (String) -> Void) { onClose = handler }

    /// All tools, following pagination.
    public func listTools() async throws -> [ToolInfo] {
        var out: [ToolInfo] = []
        var cursor: String?
        var pages = 0
        repeat {
            pages += 1
            let result = try await request("tools/list", cursor.map { ["cursor": .string($0)] } ?? [:])
            guard case .object(let o) = result, case .array(let tools)? = o["tools"] else { break }
            for case .object(let t) in tools {
                guard let name = t["name"]?.stringValue else { continue }
                var info = ToolInfo(name: name, description: t["description"]?.stringValue ?? "",
                                    inputSchema: t["inputSchema"] ?? ["type": "object"])
                if case .object(let a)? = t["annotations"] { info.readOnly = a["readOnlyHint"] == .bool(true) }
                out.append(info)
            }
            cursor = o["nextCursor"]?.stringValue
        } while cursor != nil && out.count < 1000 && pages < 100
        return out
    }

    /// All resources, following pagination.
    public func listResources() async throws -> [ResourceInfo] {
        var out: [ResourceInfo] = []
        var cursor: String?
        // A server can go on handing out empty pages: the count below wouldn't end that.
        var pages = 0
        repeat {
            pages += 1
            let result = try await request("resources/list", cursor.map { ["cursor": .string($0)] } ?? [:])
            guard case .object(let o) = result, case .array(let items)? = o["resources"] else { break }
            for case .object(let r) in items {
                guard let uri = r["uri"]?.stringValue else { continue }
                out.append(ResourceInfo(uri: uri, name: r["name"]?.stringValue ?? uri, description: r["description"]?.stringValue ?? "",
                                        mimeType: r["mimeType"]?.stringValue))
            }
            cursor = o["nextCursor"]?.stringValue
        } while cursor != nil && out.count < 1000 && pages < 100
        return out
    }

    /// A resource's text parts.
    public func readResource(_ uri: String) async throws -> String {
        let result = try await request("resources/read", ["uri": .string(uri)])
        guard case .object(let o) = result, case .array(let contents)? = o["contents"] else { return "" }
        return contents.compactMap { item -> String? in
            guard case .object(let c) = item else { return nil }
            return c["text"]?.stringValue ?? c["blob"].map { _ in "[binary content from \(uri); not shown to the model]" }
        }.joined(separator: "\n")
    }

    /// Calls a tool. Text parts are joined; other content is described, since tool results are text here.
    public func callTool(_ name: String, arguments: JSONValue, timeout: TimeInterval = 300) async throws -> CallResult {
        let result = try await request("tools/call", ["name": .string(name), "arguments": arguments], timeout: timeout)
        guard case .object(let o) = result else { return CallResult(text: "", isError: false) }
        var parts: [String] = []
        if case .array(let content)? = o["content"] {
            for case .object(let c) in content {
                switch c["type"]?.stringValue {
                case "text": parts.append(c["text"]?.stringValue ?? "")
                case "image": parts.append("[image (\(c["mimeType"]?.stringValue ?? "unknown type")) returned; not shown to the model]")
                case "audio": parts.append("[audio returned; not shown to the model]")
                case "resource":
                    if case .object(let r)? = c["resource"] {
                        parts.append(r["text"]?.stringValue ?? "[resource \(r["uri"]?.stringValue ?? "")]")
                    }
                case "resource_link": parts.append("[resource link: \(c["uri"]?.stringValue ?? "")]")
                default: break
                }
            }
        }
        if parts.isEmpty, let structured = o["structuredContent"] { parts.append(TextToolCalls.encode(structured)) }
        return CallResult(text: parts.joined(separator: "\n"), isError: o["isError"] == .bool(true))
    }

    public func close() async {
        onClose = nil
        closed("Closed.")
        await transport.close()
    }

    // MARK: JSON-RPC

    func request(_ method: String, _ params: [String: JSONValue], timeout: TimeInterval = 60) async throws -> JSONValue {
        if let closedReason { throw MCPError.transport("The server isn't running any more (\(closedReason))") }
        let id = nextID
        nextID += 1
        let message: JSONValue = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": .object(params)]
        let timer = Task { [weak self] in
            try await Task.sleep(for: .seconds(timeout))
            await self?.fail(id, MCPError.timeout("\(method) got no reply in \(Int(timeout)) s"))
        }
        defer { timer.cancel() }
        // Stop shouldn't wait for a server that's taking its time: the call ends now, and the server is told.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                pending[id] = cont
                if Task.isCancelled {
                    fail(id, CancellationError())
                    return
                }
                Task {
                    do { try await transport.send(Self.encode(message)) }
                    catch { fail(id, error) }
                }
            }
        } onCancel: {
            Task { [weak self] in await self?.cancel(id) }
        }
    }

    private func cancel(_ id: Int) async {
        guard pending[id] != nil else { return }
        fail(id, CancellationError())
        let note: JSONValue = ["jsonrpc": "2.0", "method": "notifications/cancelled",
                               "params": ["requestId": .number(Double(id)), "reason": "The user stopped it."]]
        try? await transport.send(Self.encode(note))
    }

    func notify(_ method: String) async throws {
        try await transport.send(Self.encode(["jsonrpc": "2.0", "method": .string(method)]))
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func closed(_ why: String?) {
        let reason = why ?? "The server closed the connection."
        let first = closedReason == nil
        if first { closedReason = reason }
        for (_, c) in pending { c.resume(throwing: MCPError.transport(reason)) }
        pending = [:]
        if first, let onClose {
            self.onClose = nil
            onClose(reason)
        }
    }

    func receive(_ data: Data) async {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        let id = o["id"].flatMap { v -> Int? in if case .number(let n) = v { return Int(json: n) } else { return nil } }
        if let method = o["method"]?.stringValue {
            if let rawID = o["id"] {
                // A request from the server. kurtkode declares no client capabilities, so only ping is answered.
                let reply: JSONValue = method == "ping"
                    ? ["jsonrpc": "2.0", "id": rawID, "result": .object([:])]
                    : ["jsonrpc": "2.0", "id": rawID, "error": ["code": -32601, "message": .string("\(method) isn't supported")]]
                try? await transport.send(Self.encode(reply))
            } else if method == "notifications/tools/list_changed" {
                toolsChanged?()
            }
            return
        }
        guard let id, let cont = pending.removeValue(forKey: id) else { return }
        if case .object(let e)? = o["error"] {
            let code = e["code"].flatMap { v -> Int? in if case .number(let n) = v { return Int(json: n) } else { return nil } } ?? 0
            cont.resume(throwing: MCPError.server(code: code, message: e["message"]?.stringValue ?? "unknown error"))
        } else {
            cont.resume(returning: o["result"] ?? .null)
        }
    }

    static func encode(_ v: JSONValue) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        return (try? enc.encode(v)) ?? Data()
    }
}

extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}
