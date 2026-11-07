import Foundation
import Testing
@testable import AgentCore

// Bug hunt 2026-11-02, item 37: MCP tool names, re-entrant starts, SSE parsing, tokens over http and redirects.

private func mockPath(_ name: String) throws -> String {
    try #require(Bundle.module.url(forResource: name, withExtension: "py", subdirectory: "Fixtures")).path
}

private func scratch(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-bh-mcp-\(tag)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeServers(_ home: URL, _ servers: [String: MCPServerConfig]) throws {
    let file = MCPConfigFile.userFile(home: home)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(MCPConfigFile.File(mcpServers: servers)).write(to: file)
}

private func until(seconds: Double = 10, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}

/// A mock stdio server that records its pid in `pids` and takes a second to start.
private func slowServer(pids: URL) throws -> MCPServerConfig {
    MCPServerConfig(command: "/bin/sh", args: ["-c", "echo $$ >> '\(pids.path)'; sleep 1; exec /usr/bin/python3 '\(try mockPath("mock_mcp_server"))'"])
}

private func pidsIn(_ file: URL) -> [pid_t] {
    ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { pid_t($0) }
}

private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

@Suite(.serialized) struct BugHuntToolsMCPTests {
    @Test func toolNamesThatCleanTheSameStayUniqueAndReachTheirOwnServer() async throws {
        let home = try scratch("names"), data = try scratch("data")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: data) }
        let mock = try mockPath("mock_mcp_server")
        try writeServers(home, ["a.b": MCPServerConfig(command: "/usr/bin/python3", args: [mock]),
                                "a_b": MCPServerConfig(command: "/usr/bin/python3", args: [mock])])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home, token: { _ in nil })
        await hub.reload()
        await hub.waitForStartup()
        let tools = await hub.allTools
        let names = tools.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.count <= 64 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } })
        let echoes = tools.compactMap { $0 as? MCPTool }.filter { $0.toolName == "echo" }
        #expect(Set(echoes.map(\.server)) == ["a.b", "a_b"])
        #expect(Set(echoes.map(\.name)).count == 2)
        #expect(names.contains("mcp__a_b__echo"))
        // The renamed one is stable: asking again gives the same names.
        #expect(await hub.allTools.map(\.name) == names)
        // A call by the hashed name, through the dictionary the loop builds, reaches its own server.
        let byName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for echo in echoes {
            let tool = try #require(byName[echo.name] as? MCPTool)
            #expect(tool.server == echo.server)
            let out = try await tool.run(ToolArguments(["text": "hi"]), context: ToolContext(workspace: Workspace(root: home)))
            #expect(out.text == "hi")
        }
        await hub.shutdown()
    }

    @Test func aRestartDuringStartupLeavesOneServerRunning() async throws {
        let home = try scratch("restart"), data = try scratch("data")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: data) }
        let pids = home.appending(path: "pids")
        try writeServers(home, ["slow": try slowServer(pids: pids)])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home, token: { _ in nil })
        let first = Task { await hub.reload() }
        #expect(await until { pidsIn(pids).count == 1 })
        await hub.restart("slow")
        await first.value
        #expect(await hub.statusList.first?.state == .ready)
        #expect(pidsIn(pids).count == 2)
        // The first start's server was closed when it finished, not left running beside the second.
        #expect(await until { pidsIn(pids).filter(alive).count == 1 })
        #expect(pidsIn(pids).filter(alive) == [pidsIn(pids)[1]])
        await hub.shutdown()
        #expect(await until { pidsIn(pids).filter(alive).isEmpty })
    }

    @Test func aServerRemovedDuringStartupIsNotRegisteredWhenItFinishes() async throws {
        let home = try scratch("removed"), data = try scratch("data")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: data) }
        let pids = home.appending(path: "pids")
        try writeServers(home, ["slow": try slowServer(pids: pids)])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home, token: { _ in nil })
        let first = Task { await hub.reload() }
        #expect(await until { pidsIn(pids).count == 1 })
        try writeServers(home, [:])
        await hub.reload()
        await first.value
        #expect(await hub.statusList.isEmpty)
        #expect(await hub.allTools.isEmpty)
        #expect(await until { pidsIn(pids).filter(alive).isEmpty })
    }

    @Test func aReloadDuringStartupDoesNotStartTheSameServerAgain() async throws {
        let home = try scratch("reload"), data = try scratch("data")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: data) }
        let pids = home.appending(path: "pids")
        try writeServers(home, ["slow": try slowServer(pids: pids)])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home, token: { _ in nil })
        let first = Task { await hub.reload() }
        #expect(await until { pidsIn(pids).count == 1 })
        await hub.reload()
        await first.value
        #expect(await hub.statusList.first?.state == .ready)
        #expect(pidsIn(pids).count == 1)
        await hub.shutdown()
    }

    @Test func aMessageThatNeverParsesDoesNotSwallowLaterOnes() {
        var j = SSEJoiner()
        #expect(j.feed("data: {\"broken\": ") == nil)
        #expect(j.feed("data: {\"jsonrpc\":\"2.0\",\"method\":\"a\"}") == Data("{\"jsonrpc\":\"2.0\",\"method\":\"a\"}".utf8))
        #expect(j.pending.isEmpty)
        // A field of the next event ends a broken one, so a value split over lines still joins.
        #expect(j.feed("data: not json") == nil)
        #expect(j.feed("event: message") == nil)
        #expect(j.feed("data: {\"x\":") == nil)
        #expect(j.feed("data: 1}") == Data("{\"x\":\n1}".utf8))
        // Past the limit the pending text is dropped instead of growing.
        var small = SSEJoiner(limit: 100)
        for _ in 0..<50 { _ = small.feed("data: xxxxxxxxxx") }
        #expect(small.pending.utf8.count <= 100)
    }

    @Test func aTokenIsNotSentOverPlainHTTPToAnotherMachine() async throws {
        #expect(HTTPTransport.isLoopback(URL(string: "http://127.0.0.1:8080/mcp")!))
        #expect(HTTPTransport.isLoopback(URL(string: "http://localhost/mcp")!))
        #expect(HTTPTransport.isLoopback(URL(string: "http://[::1]:9000/mcp")!))
        #expect(!HTTPTransport.isLoopback(URL(string: "http://example.com/mcp")!))
        #expect(!HTTPTransport.isLoopback(URL(string: "http://127.0.0.1.evil.example/mcp")!))
        let home = try scratch("http"), data = try scratch("data")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: data) }
        // .invalid never resolves, so even a regression wouldn't reach a real host.
        try writeServers(home, ["far": MCPServerConfig(type: "http", url: "http://mcp.example.invalid/mcp")])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home,
                         token: { _ in "secret-token" })
        await hub.reload()
        await hub.waitForStartup()
        guard case .failed(let why)? = await hub.statusList.first?.state else { Issue.record("should refuse"); return }
        #expect(why.contains("plain http") && why.contains("https"))
    }

    @Test func redirectsAreFollowedOnlyWithinTheOrigin() async throws {
        #expect(SameOriginRedirects.allows(from: URL(string: "https://a.example/mcp"), to: URL(string: "https://a.example:443/other")))
        #expect(!SameOriginRedirects.allows(from: URL(string: "https://a.example/mcp"), to: URL(string: "https://b.example/mcp")))
        #expect(!SameOriginRedirects.allows(from: URL(string: "https://a.example/mcp"), to: URL(string: "http://a.example/mcp")))
        #expect(!SameOriginRedirects.allows(from: URL(string: "http://127.0.0.1:1/mcp"), to: URL(string: "http://127.0.0.1:2/mcp")))

        let server = try RedirectingMockServer()
        // Same origin: followed, and the session works.
        let same = MCPClient(transport: HTTPTransport(url: server.url(path: "/same"), headers: ["Authorization": "Bearer secret-token"]))
        try await same.connect(timeout: 10)
        #expect(await same.server?.name == "mock-http")
        await same.close()
        // Another origin (localhost for 127.0.0.1): not followed, so the token isn't sent there, and the error says why.
        let cross = MCPClient(transport: HTTPTransport(url: server.url(path: "/cross"), headers: ["Authorization": "Bearer secret-token"]))
        do {
            try await cross.connect(timeout: 10)
            Issue.record("a cross-origin redirect should not be followed")
        } catch {
            #expect(error.localizedDescription.contains("redirected") && error.localizedDescription.contains("HTTP 307"))
        }
        await cross.close()
    }
}

/// The Streamable HTTP mock (see MCPHTTPTests), at a chosen path.
private final class RedirectingMockServer: @unchecked Sendable {
    let process = Process()
    let stdin = Pipe()
    var port = 0

    init() throws {
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [try mockPath("mock_mcp_http_server")]
        process.standardInput = stdin
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data()
        while !line.contains(0x0A) {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            line.append(chunk)
        }
        let text = String(decoding: line, as: UTF8.self)
        port = try #require(text.split(separator: " ").last.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
    }

    func url(path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    deinit {
        try? stdin.fileHandleForWriting.close()
        process.terminate()
    }
}
