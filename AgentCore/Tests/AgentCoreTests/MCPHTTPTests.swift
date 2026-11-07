import Foundation
import Testing
@testable import AgentCore

/// Runs the mock Streamable HTTP server; stops it when released.
private final class MockHTTPServer: @unchecked Sendable {
    let process = Process()
    let stdin = Pipe()
    var url: URL!

    init() throws {
        let script = try #require(Bundle.module.url(forResource: "mock_mcp_http_server", withExtension: "py", subdirectory: "Fixtures"))
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path]
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
        let port = try #require(text.split(separator: " ").last.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        url = URL(string: "http://127.0.0.1:\(port)/mcp")!
    }

    deinit {
        try? stdin.fileHandleForWriting.close()
        process.terminate()
    }
}

private func connect(_ server: MockHTTPServer, token: String = "secret-token") async throws -> MCPClient {
    let client = MCPClient(transport: HTTPTransport(url: server.url, headers: ["Authorization": "Bearer \(token)"]))
    try await client.connect(timeout: 10)
    return client
}

@Suite(.serialized) struct MCPHTTPTests {
    @Test func talksStreamableHTTP() async throws {
        let server = try MockHTTPServer()
        let client = try await connect(server)
        #expect(await client.server?.name == "mock-http")
        #expect(try await client.listTools().map(\.name) == ["echo", "headers", "expire", "deleted"])        // a JSON reply
        #expect(try await client.callTool("echo", arguments: ["text": "over http"]).text == "over http")      // an SSE reply
        let seen = try await client.callTool("headers", arguments: [:]).text
        #expect(seen == "version=\(MCPClient.protocolVersion) session=sess-1")
        await client.close()
        let again = try await connect(server)
        #expect(try await again.callTool("deleted", arguments: [:]).text == "yes")                           // close sent DELETE
        await again.close()
    }

    @Test func hearsTheServersOwnStream() async throws {
        let server = try MockHTTPServer()
        final class Flag: @unchecked Sendable { var set = false }
        let flag = Flag()
        let client = MCPClient(transport: HTTPTransport(url: server.url, headers: ["Authorization": "Bearer secret-token"]))
        await client.onToolsChanged { flag.set = true }
        try await client.connect(timeout: 10)
        for _ in 0..<40 where !flag.set { try await Task.sleep(for: .milliseconds(100)) }
        #expect(flag.set)                               // list_changed came on the GET stream
        await client.close()
    }

    @Test func explainsAuthAndExpiredSessions() async throws {
        let server = try MockHTTPServer()
        do {
            _ = try await connect(server, token: "wrong")
            Issue.record("expected a refusal")
        } catch {
            #expect(error.localizedDescription.contains("HTTP 401") && error.localizedDescription.contains("token"))
        }
        let client = try await connect(server)
        _ = try await client.callTool("expire", arguments: [:])
        do {
            _ = try await client.callTool("echo", arguments: ["text": "x"])
            Issue.record("expected an expired session")
        } catch {
            #expect(error.localizedDescription.contains("session has expired"))
        }
    }

    @Test func theHubSendsTheKeychainTokenOnlyWithoutItsOwnHeader() async throws {
        let server = try MockHTTPServer()
        let home = FileManager.default.temporaryDirectory.appending(path: "kk-mcphttp-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = MCPConfigFile.userFile(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(MCPConfigFile.File(mcpServers: [
            "remote": MCPServerConfig(type: "http", url: server.url.absoluteString),
            "own-header": MCPServerConfig(type: "http", url: server.url.absoluteString, headers: ["Authorization": "Bearer wrong"]),
        ])).write(to: file)
        final class Asked: @unchecked Sendable { var accounts: [String] = [] }
        let asked = Asked()
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: home.appending(path: "a.json")), home: home, token: { entry in
            asked.accounts.append(KeychainStore.mcpAccount(server: entry.name, url: entry.config.url ?? ""))
            return "secret-token"
        })
        await hub.reload()
        await hub.waitForStartup()
        let states = Dictionary(uniqueKeysWithValues: await hub.statusList.map { ($0.entry.name, $0.state) })
        #expect(states["remote"] == .ready)
        guard case .failed(let why)? = states["own-header"] else { Issue.record("own header should win and fail"); return }
        #expect(why.contains("HTTP 401"))
        #expect(asked.accounts.contains("remote@127.0.0.1"))
        #expect(await hub.allTools.map(\.name).contains("mcp__remote__echo"))
        await hub.shutdown()
    }
}
