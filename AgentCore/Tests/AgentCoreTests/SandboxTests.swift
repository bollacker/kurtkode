import Foundation
import Testing
@testable import AgentCore

/// Runs real commands under sandbox-exec (D9).
private func sandboxed(_ command: String, in ws: Workspace, policy: SandboxPolicy = SandboxPolicy()) async -> ToolOutput {
    let json = String(decoding: try! JSONEncoder().encode(JSONValue.object(["command": .string(command)])), as: UTF8.self)
    var config = AgentConfig(tools: [BashTool()])
    config.sandbox = policy
    return await AgentLoop.execute(ToolCall(id: "t", name: "bash", arguments: json), tools: ["bash": BashTool()],
                                   config: config, workspace: ws)
}

@Suite(.enabled(if: SandboxPolicy.isAvailable)) struct SandboxTests {
    @Test func writesInsideTheProjectWork() async throws {
        let ws = try makeProject()
        let out = await sandboxed("echo made > new.txt && mkdir -p a/b && cat new.txt", in: ws)
        #expect(out.exitCode == 0)
        #expect(out.text.contains("made"))
        #expect(FileManager.default.fileExists(atPath: ws.root.appending(path: "a/b").path))
    }

    @Test func writesOutsideAreBlockedAndReported() async throws {
        let ws = try makeProject()
        let outside = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kurtkode-sbx-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: outside) }
        let out = await sandboxed("echo escaped > '\(outside.path)'", in: ws)
        #expect(out.exitCode != 0)
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(out.text.contains("The sandbox blocked: write ~/" + outside.lastPathComponent))
        #expect(out.text.contains("tell the user"))
    }

    @Test func goGetsABuildCacheItCanWrite() async throws {
        let ws = try makeProject()
        let out = await sandboxed(#"mkdir -p "$GOCACHE" && touch "$GOCACHE/probe" && echo "cache=$GOCACHE""#, in: ws)
        #expect(out.exitCode == 0)
        #expect(out.text.contains("/kurtkode/go-build"))
        #expect(!out.text.contains("/Library/Caches/"))
        #expect(SandboxPolicy.cacheVariables(for: ["GOCACHE": "/mine"]).isEmpty)
        #expect(BashTool.environment(nil)["GOCACHE"] == ProcessInfo.processInfo.environment["GOCACHE"])
    }

    @Test func gitHooksAndConfigStayReadOnly() async throws {
        let ws = try makeProject(git: true)
        let hook = await sandboxed("echo 'echo pwned' > .git/hooks/pre-commit", in: ws)
        #expect(hook.exitCode != 0)
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: ".git/hooks/pre-commit").path))
        let config = await sandboxed("git config core.hooksPath /tmp/elsewhere", in: ws)
        #expect(config.exitCode != 0)
        // Ordinary git work still writes .git.
        let commit = await sandboxed("echo x >> README.md && git add README.md && git -c user.email=t@t -c user.name=t commit -qm edit && git log --oneline | wc -l", in: ws)
        #expect(commit.exitCode == 0)
    }

    @Test func networkIsOffUnlessAllowed() async throws {
        let ws = try makeProject()
        let probe = #"python3 -c 'import socket; s=socket.socket(); s.settimeout(3); s.connect(("1.1.1.1", 80)); print("connected")'"#
        let off = await sandboxed(probe, in: ws)
        #expect(off.exitCode != 0)
        #expect(off.text.contains("not permitted"))
        let on = await sandboxed(probe, in: ws, policy: SandboxPolicy(allowNetwork: true))
        #expect(!on.text.contains("not permitted"))
    }

    /// A tool that starts its own sandbox (SwiftPM compiles a package's manifest in one) fails inside this one, and the
    /// error says nothing about why: the note names the cause and SwiftPM's flag.
    @Test func aToolStartingItsOwnSandboxGetsTheHint() async throws {
        let ws = try makeProject()
        let out = await sandboxed("/usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true", in: ws)
        #expect(out.exitCode != 0)
        #expect(out.text.contains("sandbox_apply: Operation not permitted"))
        #expect(out.text.contains("A tool tried to start its own sandbox") && out.text.contains("add --disable-sandbox"))
    }

    @Test func aFailureTheSandboxDidntCauseGetsNoNote() async throws {
        let ws = try makeProject()
        let out = await sandboxed("ls no-such-file", in: ws)
        #expect(out.exitCode != 0)
        #expect(!out.text.contains("sandbox"))
    }

    @Test func theSystemPromptSaysSoOnlyWhenSandboxed() async throws {
        let ws = try makeProject()
        var builder = SystemPromptBuilder(workspace: ws, tools: AllTools.all, mode: .fullAuto,
                                          globalInstructions: ws.root.appending(path: ".none"))
        let plain = await builder.build()
        builder.sandbox = SandboxPolicy()
        let boxed = await builder.build()
        #expect(!plain.contains("sandbox"))
        #expect(boxed.contains("Commands run in a sandbox"))
        #expect(boxed.contains("no network"))
        #expect(SandboxUse.fullAuto.policy(for: .ask, SandboxPolicy()) == nil)
        #expect(SandboxUse.fullAuto.policy(for: .fullAuto, SandboxPolicy()) != nil)
    }

    @Test func parsesDenialsFromTheLog() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let log = """
            2026-09-27 11:16:36.763 E  kernel[0:1] (Sandbox) Sandbox: zsh(52656) deny(1) file-write-data /dev/tty
            2026-09-27 11:16:36.765 E  kernel[0:1] (Sandbox) Sandbox: zsh(52656) deny(1) file-write-create \(home)/nope.txt
            2026-09-27 11:16:36.766 E  kernel[0:1] (Sandbox) Sandbox: Python(52657) deny(1) file-write-create \(home)/nope.txt
            2026-09-27 11:16:36.767 E  kernel[0:1] (Sandbox) Sandbox: curl(52658) deny(1) network-outbound 1.1.1.1:80
            """
        #expect(SandboxPolicy.parseDenials(log) == ["write ~/nope.txt", "network"])
    }
}
