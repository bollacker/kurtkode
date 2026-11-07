import Foundation
import Testing
@testable import AgentCore

/// BUG_HUNT_2026-11-02 Part 1 item 9: a project server's env and headers were approved unseen, and `${VAR}` in a
/// project's .mcp.json took values from kurtkode's environment.
@Suite struct BugHuntMCPApprovalTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "kk-bh-mcp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func detailsShowEnvAndHeaderNames() {
        let c = MCPServerConfig(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem"],
                                env: ["NODE_OPTIONS": "--require ./x.js", "A": "1"])
        #expect(c.approvalDetails == ["env A=1", "env NODE_OPTIONS=--require ./x.js"])
        let h = MCPServerConfig(url: "https://mcp.example.com/mcp",
                                headers: ["Authorization": "Bearer abc", "X-Team": "blue", "X-Opaque": "sk9f8a7s6d5f4g3h2j1k0l"])
        #expect(h.approvalDetails == ["header Authorization: (set, value hidden)", "header X-Opaque: (set, value hidden)",
                                      "header X-Team: blue"])
        #expect(MCPServerConfig(command: "server").approvalDetails.isEmpty)
    }

    @Test func fingerprintCoversWhatIsShown() {
        let base = MCPServerConfig(command: "npx", args: ["srv"], env: ["A": "1"], url: nil, headers: nil)
        var env = base; env.env = ["A": "2"]
        var header = base; header.headers = ["X": "y"]
        #expect(base.fingerprint != env.fingerprint)
        #expect(base.fingerprint != header.fingerprint)
        #expect(base.approvalDetails != env.approvalDetails)
        #expect(base.approvalDetails != header.approvalDetails)
    }

    @Test func projectServersDontExpandVariables() throws {
        let home = try folder(), project = try folder()
        let json = #"{"mcpServers": {"s": {"command": "${HOME}/bin/s", "args": ["${HOME}"], "env": {"K": "${HOME}"},"#
            + #" "headers": {"X": "${HOME}"}}, "r": {"url": "https://${HOME}.example.com", "headers": {"X": "${HOME:-d}"}}}}"#
        try Data(json.utf8).write(to: MCPConfigFile.projectFile(project))
        let entries = try MCPConfigFile.load(workspace: project, home: home)
        let s = try #require(entries.first { $0.name == "s" })
        #expect(s.scope == .project)
        #expect(s.config.command == "${HOME}/bin/s")
        #expect(s.config.args == ["${HOME}"])
        #expect(s.config.env == ["K": "${HOME}"])
        #expect(s.config.headers == ["X": "${HOME}"])
        let r = try #require(entries.first { $0.name == "r" })
        #expect(r.config.url == "https://${HOME}.example.com")
        #expect(r.config.headers == ["X": "${HOME:-d}"])
        #expect(s.config.approvalDetails.last?.hasPrefix("${…} is passed as written") == true)
    }

    @Test func userServersStillExpandVariables() throws {
        let home = try folder()
        try FileManager.default.createDirectory(at: MCPConfigFile.userFile(home: home).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"mcpServers": {"u": {"command": "s", "env": {"K": "${HOME}", "D": "${KK_BH_UNSET_VAR:-d}"}}}}"#.utf8)
            .write(to: MCPConfigFile.userFile(home: home))
        let u = try #require(try MCPConfigFile.load(workspace: nil, home: home).first)
        #expect(u.scope == .user)
        #expect(u.config.env?["K"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(u.config.env?["D"] == "d")
    }
}
