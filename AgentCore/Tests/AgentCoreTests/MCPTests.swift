import Foundation
import Testing
@testable import AgentCore

private func mockServerPath() throws -> String {
    try #require(Bundle.module.url(forResource: "mock_mcp_server", withExtension: "py", subdirectory: "Fixtures")).path
}

private func connectMock() async throws -> MCPClient {
    let client = MCPClient(transport: StdioTransport(command: "/usr/bin/python3", arguments: [try mockServerPath()]))
    try await client.connect(timeout: 20)
    return client
}

private func tempDir(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kk-mcp-\(tag)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeConfig(_ url: URL, _ servers: [String: MCPServerConfig]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(MCPConfigFile.File(mcpServers: servers)).write(to: url)
}

/// Polls until `condition` holds (async notifications), up to about 5 seconds.
private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<50 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return false
}

@Suite struct MCPClientTests {
    @Test func talksToAServer() async throws {
        let client = try await connectMock()
        defer { Task { await client.close() } }
        let info = await client.server
        #expect(info?.name == "mock")
        #expect(info?.protocolVersion == MCPClient.protocolVersion)

        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["echo", "add", "fail", "picture", "slow", "pinged", "change", "crash"])    // two pages

        #expect(try await client.callTool("echo", arguments: ["text": "hello"]) == .init(text: "hello", isError: false))
        #expect(try await client.callTool("add", arguments: ["a": 2, "b": 3]).text == "5")
        #expect(try await client.callTool("fail", arguments: [:]).isError)
        let picture = try await client.callTool("picture", arguments: [:])
        #expect(picture.text.contains("a chart:") && picture.text.contains("[image (image/png) returned"))
        #expect(try await client.callTool("pinged", arguments: [:]).text == "yes")          // we answered its ping
        await #expect(throws: MCPError.self) { try await client.callTool("nope", arguments: [:]) }
    }

    @Test func timesOutAndNoticesChanges() async throws {
        let client = try await connectMock()
        defer { Task { await client.close() } }
        do {
            _ = try await client.callTool("slow", arguments: [:], timeout: 1)
            Issue.record("expected a timeout")
        } catch let e as MCPError {
            guard case .timeout = e else { Issue.record("wrong error \(e)"); return }
        }
        final class Flag: @unchecked Sendable { var set = false }
        let flag = Flag()
        await client.onToolsChanged { flag.set = true }
        _ = try await client.callTool("change", arguments: [:])
        #expect(await eventually { flag.set })
        #expect(try await client.listTools().contains { $0.name == "extra" })
    }

    @Test func reportsACrashWithTheServersOwnMessage() async throws {
        let client = try await connectMock()
        do {
            _ = try await client.callTool("crash", arguments: [:], timeout: 10)
            Issue.record("expected a failure")
        } catch {
            #expect(error.localizedDescription.contains("crashing on purpose"))
        }
        await #expect(throws: MCPError.self) { try await client.callTool("echo", arguments: ["text": "x"]) }
    }

    @Test func aMissingCommandFailsClearly() async throws {
        let client = MCPClient(transport: StdioTransport(command: "kurtkode-no-such-server"))
        await #expect(throws: MCPError.self) { try await client.connect(timeout: 10) }
    }
}

@Suite struct MCPConfigTests {
    @Test func readsUserThenProjectAndExpandsVariables() throws {
        let home = try tempDir("home"), project = try tempDir("proj")
        try writeConfig(MCPConfigFile.userFile(home: home), [
            "shared": MCPServerConfig(command: "user-cmd"),
            "tools": MCPServerConfig(command: "${HOME}/bin/tool", args: ["--port", "${KK_NO_SUCH_VAR:-8080}"]),
        ])
        try writeConfig(MCPConfigFile.projectFile(project), [
            "shared": MCPServerConfig(command: "project-cmd"),
            "db": MCPServerConfig(command: "npx", args: ["-y", "some-server"], env: ["TOKEN": "${KK_NO_SUCH_VAR}"]),
        ])
        let entries = try MCPConfigFile.load(workspace: project, home: home)
        #expect(entries.map(\.name) == ["shared", "tools", "db"])
        #expect(entries[0].config.command == "user-cmd" && entries[0].scope == .user)       // the user's wins
        #expect(entries[1].config.command == NSHomeDirectory() + "/bin/tool")
        #expect(entries[1].config.args == ["--port", "8080"])
        // A project's server isn't given kurtkode's environment variables (BUG_HUNT_2026-11-02 item 9).
        #expect(entries[2].scope == .project && entries[2].config.env == ["TOKEN": "${KK_NO_SUCH_VAR}"])
        #expect(entries[2].config.displayCommand == "npx -y some-server")

        try Data("{ not json".utf8).write(to: MCPConfigFile.projectFile(project))
        #expect(throws: MCPError.self) { try MCPConfigFile.load(workspace: project, home: home) }
    }

    @Test func projectServersNeedApprovalForTheirExactCommand() throws {
        let dir = try tempDir("approvals"), project = try tempDir("proj")
        let approvals = MCPApprovals(fileURL: dir.appending(path: "approvals.json"))
        let server = MCPServerEntry(name: "db", config: MCPServerConfig(command: "npx", args: ["a"]), scope: .project)
        let mine = MCPServerEntry(name: "mine", config: MCPServerConfig(command: "x"), scope: .user)
        #expect(approvals.isApproved(mine, workspace: project))
        #expect(!approvals.isApproved(server, workspace: project))
        try approvals.approve(server, workspace: project)
        #expect(approvals.isApproved(server, workspace: project))
        var changed = server
        changed.config.args = ["b"]
        #expect(!approvals.isApproved(changed, workspace: project))                   // a new command asks again
        #expect(!approvals.isApproved(server, workspace: try tempDir("other")))       // per project
    }

    @Test func exposedNamesAreValidAndShort() {
        #expect(MCPTool.exposedName(server: "github", tool: "create_issue") == "mcp__github__create_issue")
        #expect(MCPTool.exposedName(server: "my server", tool: "do.thing") == "mcp__my_server__do_thing")
        let long = MCPTool.exposedName(server: String(repeating: "s", count: 40), tool: String(repeating: "t", count: 40))
        #expect(long.count == 64)
        #expect(long.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    }
}

@Suite struct MCPHubTests {
    @Test func startsTrustedServersAndWaitsForApprovalOfProjectOnes() async throws {
        let home = try tempDir("home"), project = try tempDir("proj"), data = try tempDir("data")
        let mock = try mockServerPath()
        try writeConfig(MCPConfigFile.userFile(home: home), ["mock": MCPServerConfig(command: "/usr/bin/python3", args: [mock])])
        try writeConfig(MCPConfigFile.projectFile(project), [
            "repo": MCPServerConfig(command: "/usr/bin/python3", args: [mock]),
            "off": MCPServerConfig(command: "/usr/bin/python3", args: [mock], disabled: true),
            "remote": MCPServerConfig(type: "sse", url: "https://example.com/sse"),
        ])
        let hub = MCPHub(workspace: project, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home,
                         token: { _ in nil })
        await hub.reload()
        await hub.waitForStartup()
        let states = Dictionary(uniqueKeysWithValues: await hub.statusList.map { ($0.entry.name, $0.state) })
        #expect(states["mock"] == .ready)
        #expect(states["repo"] == .needsApproval)
        #expect(states["off"] == .disabled)
        guard case .failed(let why)? = states["remote"] else { Issue.record("remote should fail"); return }
        #expect(why.contains("older HTTP+SSE"))
        #expect(await hub.allTools.map(\.name).contains("mcp__mock__echo"))
        #expect(!(await hub.allTools.map(\.name).contains("mcp__repo__echo")))

        try await hub.approve("repo")
        #expect(await hub.allTools.map(\.name).contains("mcp__repo__echo"))

        // A tool call through the Tool interface, as the agent loop makes it.
        let echo = try #require(await hub.allTools.first { $0.name == "mcp__mock__echo" })
        let out = try await echo.run(ToolArguments(["text": "via the hub"]), context: ToolContext(workspace: Workspace(root: project)))
        #expect(out.text == "via the hub")
        #expect(echo.risk == .execute)
        #expect(PermissionPolicy.suggestedRule(echo, ToolArguments(["text": "x"])) == .tool("mcp__mock__echo"))
        #expect(!PermissionPolicy(mode: .ask).isAllowedWithoutAsking(echo, ToolArguments()))
        let add = try #require(await hub.allTools.first { $0.name == "mcp__mock__add" })       // echo says it only reads; add doesn't
        #expect(PermissionPolicy(mode: .plan).offered([add]).isEmpty)
        await hub.shutdown()
    }
    /// A server that exits mid-session: its status says so and its tools go, until a restart brings them back.
    @Test func aServerThatExitsIsMarkedFailedUntilRestarted() async throws {
        let home = try tempDir("home"), data = try tempDir("data")
        try writeConfig(MCPConfigFile.userFile(home: home), ["mock": MCPServerConfig(command: "/usr/bin/python3", args: [try mockServerPath()])])
        let hub = MCPHub(workspace: nil, approvals: MCPApprovals(fileURL: data.appending(path: "a.json")), home: home, token: { _ in nil })
        await hub.reload()
        await hub.waitForStartup()
        let crash = try #require(await hub.allTools.first { $0.name == "mcp__mock__crash" })
        let heldEcho = try #require(await hub.allTools.first { $0.name == "mcp__mock__echo" })
        let ctx = ToolContext(workspace: Workspace(root: home))
        let first = try? await crash.run(ToolArguments(), context: ctx)
        #expect(first == nil || first?.isError == true)
        #expect(await eventually { if case .failed = await hub.statusList.first?.state { true } else { false } })
        guard case .failed(let why)? = await hub.statusList.first?.state else { Issue.record("not failed"); return }
        #expect(why.contains("Stopped.") && why.contains("crashing on purpose"))
        #expect(await hub.allTools.isEmpty)
        // A call through a tool the run still holds says the server is down, not the crash again.
        var said = ""
        do { said = try await heldEcho.run(ToolArguments(["text": "x"]), context: ctx).text } catch { said = error.localizedDescription }
        #expect(said.contains("isn't running any more"))
        await hub.restart("mock")
        #expect(await hub.statusList.first?.state == .ready)
        #expect(await hub.allTools.contains { $0.name == "mcp__mock__echo" })
        await hub.shutdown()
    }
}

