import Foundation
import Testing
@testable import AgentCore

private func run(_ tool: some Tool, _ args: [String: JSONValue], in ws: Workspace, config: AgentConfig? = nil) async -> ToolOutput {
    var config = config ?? AgentConfig(tools: [tool])
    if config.tools.isEmpty { config.tools = [tool] }
    return await AgentLoop.execute(ToolCall(id: "t", name: tool.name,
                                            arguments: String(decoding: try! JSONEncoder().encode(JSONValue.object(args)), as: UTF8.self)),
                                   tools: [tool.name: tool], config: config, workspace: ws)
}

/// BUG_HUNT_2026-11-02.md Part 1, items 5 to 10: the sandbox and secrets.
@Suite struct BugHuntSandboxTests {
    // MARK: Item 5: a new file under a linked folder is checked where it lands.

    @Test func writesThroughALinkedFolderAreCheckedWhereTheyLand() async throws {
        let ws = try makeProject(git: true)
        let fm = FileManager.default
        try fm.createSymbolicLink(atPath: ws.root.path + "/tools", withDestinationPath: ".git/hooks")
        try fm.createSymbolicLink(atPath: ws.root.path + "/away", withDestinationPath: "../..")
        try fm.createSymbolicLink(atPath: ws.root.path + "/a", withDestinationPath: "b")        // a chain into .git
        try fm.createSymbolicLink(atPath: ws.root.path + "/b", withDestinationPath: "tools")
        try fm.createSymbolicLink(atPath: ws.root.path + "/dangle", withDestinationPath: "/etc/kk-nowhere-\(UUID().uuidString.prefix(6))")
        try fm.createSymbolicLink(atPath: ws.root.path + "/local", withDestinationPath: "nowhere.txt")   // dangling, inside

        #expect(throws: ToolFailure.self) { try ws.resolveForWriting("tools/pre-commit") }
        #expect(throws: ToolFailure.self) { try ws.resolveForWriting("a/pre-commit") }
        #expect(throws: ToolFailure.self) { try ws.resolveForWriting("away/escaped.txt") }
        #expect(throws: ToolFailure.self) { try ws.resolveForWriting("dangle") }
        #expect(throws: ToolFailure.self) { try ws.resolveForWriting("dangle/x") }
        // Resolved, not just refused: the link's target is named.
        #expect(try ws.resolveForWriting("local").path == ws.root.path + "/nowhere.txt")
        #expect(try ws.resolveForWriting("src/new/deeper/file.swift").path == ws.root.path + "/src/new/deeper/file.swift")

        let hook = await run(WriteFileTool(), ["path": "tools/pre-commit", "content": "echo pwned\n"], in: ws)
        #expect(hook.isError && hook.text.contains(".git"))
        #expect(!fm.fileExists(atPath: ws.root.path + "/.git/hooks/pre-commit"))
        let escaped = ws.root.deletingLastPathComponent().deletingLastPathComponent().appending(path: "kk-escaped-\(UUID().uuidString.prefix(6)).txt")
        defer { try? fm.removeItem(at: escaped) }
        let out = await run(WriteFileTool(), ["path": .string("away/" + escaped.lastPathComponent), "content": "x\n"], in: ws)
        #expect(out.isError && out.text.contains("outside the workspace"))
        #expect(!fm.fileExists(atPath: escaped.path))
        let patch = await run(ApplyPatchTool(), ["patch": "*** Begin Patch\n*** Add File: tools/post-checkout\n+echo pwned\n*** End Patch"], in: ws)
        #expect(patch.isError && patch.text.contains(".git"))
        #expect(!fm.fileExists(atPath: ws.root.path + "/.git/hooks/post-checkout"))
        let move = await run(ApplyPatchTool(), ["patch": "*** Begin Patch\n*** Update File: README.md\n*** Move to: tools/pre-push\n@@ # Demo\n-# Demo\n+# Moved\n*** End Patch"], in: ws)
        #expect(move.isError && move.text.contains(".git"))
        #expect(fm.fileExists(atPath: ws.root.path + "/README.md"))
    }

    @Test func existingPathsStillResolveAsBefore() throws {
        let ws = try makeProject()
        #expect(try ws.resolve("src/main.swift").path == ws.root.path + "/src/main.swift")
        #expect(throws: ToolFailure.self) { try ws.resolve("escape/etc/hosts") }
        // The firmlink spelling: a file under /tmp is known as /tmp/…, whether or not it exists yet.
        #expect(Workspace.canonical(URL(fileURLWithPath: "/private/tmp/kk-none-\(UUID().uuidString)/x.txt")).path.hasPrefix("/tmp/"))
        #expect(Workspace.canonical(URL(fileURLWithPath: "/tmp")).path == "/tmp")
    }

    // MARK: Item 6: preference writes and Apple events are denied in the sandbox.

    @Test func profileDeniesPreferenceWritesAndAppleEvents() {
        let p = SandboxPolicy.profile(extraCount: 0, allowNetwork: false)
        #expect(p.contains("(deny user-preference-write"))
        #expect(p.contains("(deny appleevent-send"))
    }

    @Test(.enabled(if: SandboxPolicy.isAvailable)) func sandboxedCommandsCantWritePreferences() async throws {
        let ws = try makeProject()
        var config = AgentConfig(tools: [BashTool()])
        config.sandbox = SandboxPolicy()
        let domain = "org.mlcommons.kurt.kurtkode.bughunt-\(UUID().uuidString.prefix(8))"
        defer { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/defaults"), arguments: ["delete", domain]) }
        let write = await run(BashTool(), ["command": .string("defaults write \(domain) sandboxUse never")], in: ws, config: config)
        #expect(write.exitCode != 0)
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        check.arguments = ["read", domain, "sandboxUse"]
        check.standardOutput = FileHandle.nullDevice; check.standardError = FileHandle.nullDevice
        try check.run(); check.waitUntilExit()
        #expect(check.terminationStatus != 0, "the preference was written through cfprefsd")
        // Reading preferences still works.
        let read = await run(BashTool(), ["command": .string("defaults read -g AppleLanguages")], in: ws, config: config)
        #expect(read.exitCode == 0)
    }

    // MARK: Item 7: the attempt store is outside the sandbox's write set and restores only inside the run's folders.

    @Test func attemptStoreIsNotInATempFolder() {
        let store = SubagentSetup.defaultAttemptStore.path
        for tmp in [FileManager.default.temporaryDirectory.path, "/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp",
                    SandboxPolicy.darwinDir(_CS_DARWIN_USER_TEMP_DIR) ?? "", SandboxPolicy.darwinDir(_CS_DARWIN_USER_CACHE_DIR) ?? ""] where !tmp.isEmpty {
            #expect(!store.hasPrefix(tmp.hasSuffix("/") ? tmp : tmp + "/"), "attempt store under \(tmp)")
        }
        #expect(store.contains("/Application Support/"))
    }

    @Test func restoreRefusesEntriesOutsideTheRunsFolders() async throws {
        let ws = try makeProject()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "kk-bh-ckpt-\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: dir) }
        let store = CheckpointStore(directory: dir)
        let turn = UUID()
        let inside = ws.root.appending(path: "README.md")
        try await store.snapshot(inside, turn: turn)
        try Data("changed\n".utf8).write(to: inside)
        // A forged entry: a file outside the project that "didn't exist", so a restore would delete it.
        let victim = fm.temporaryDirectory.appending(path: "kk-bh-victim-\(UUID().uuidString.prefix(8)).txt")
        try Data("precious\n".utf8).write(to: victim)
        defer { try? fm.removeItem(at: victim) }
        let forged = #"{"turn":"\#(turn.uuidString)","path":"\#(victim.path)","existed":false,"date":"2026-11-02T00:00:00Z"}"# + "\n"
        try JSONLines.append(Data(forged.utf8), to: dir.appending(path: "index.jsonl"), create: true)

        await #expect(throws: ToolFailure.self) { try await store.restore(turns: [turn], only: nil, within: [ws.root]) }
        #expect(fm.fileExists(atPath: victim.path), "the forged entry deleted a file outside the project")
        #expect(try String(contentsOf: inside, encoding: .utf8) == "changed\n", "nothing is restored when one entry is refused")
        // Without a limit (the session's own store, which commands can't write) the restore is as before.
        let restored = try await store.restore(turns: [turn], only: Set([inside.path]))
        #expect(restored.map(\.path) == [inside.path])
        #expect(try String(contentsOf: inside, encoding: .utf8) == "# Demo\n\nA demo project.\n")
    }

    // MARK: Item 8: children don't inherit kurtkode's API keys.

    @Test func childEnvironmentDropsTheKeysKurtkodeReads() {
        let env = ["ANTHROPIC_API_KEY": "sk-1", "GEMINI_API_KEY": "g", "GOOGLE_API_KEY": "g2", "OPENAI_API_KEY": "o", "OPENROUTER_API_KEY": "r",
                   "KURTKODE_API_KEY_OPENROUTER": "k", "KURTKODE_API_KEY_MY_SERVER": "k2", "PATH": "/usr/bin", "HOME": "/Users/x", "KURTKODE_NO_KEYCHAIN": "1"]
        let kept = ChildEnvironment.stripped(env)
        #expect(kept == ["PATH": "/usr/bin", "HOME": "/Users/x", "KURTKODE_NO_KEYCHAIN": "1"])
        for name in Endpoint.Kind.allCases.flatMap(\.standardKeyVariables) { #expect(ChildEnvironment.isSecret(name)) }
    }

    @Test func commandsAndHooksDontSeeTheKeys() async throws {
        let name = "KURTKODE_API_KEY_BUGHUNT_\(UUID().uuidString.prefix(6).uppercased())"
        setenv(name, "secret-value", 1); setenv("ANTHROPIC_API_KEY", "sk-ant-bughunt", 1)
        defer { unsetenv(name); unsetenv("ANTHROPIC_API_KEY") }
        #expect(BashTool.environment[name] == nil && BashTool.environment["ANTHROPIC_API_KEY"] == nil)
        #expect(BashTool.environment["PATH"] != nil)
        let ws = try makeProject()
        let out = await run(BashTool(), ["command": .string("echo \"[${\(name):-unset}][${ANTHROPIC_API_KEY:-unset}]\"")], in: ws)
        // The login profile may export ANTHROPIC_API_KEY on this Mac; kurtkode's own name can't come from there.
        #expect(out.text.contains("[unset]["))
        let hook = await Hooks.execute("echo \"[${\(name):-unset}]\"", stdin: "{}", cwd: ws.root, timeout: 20)
        #expect(hook.stdout.contains("[unset]"))
        // An MCP server's own configuration still sets what it names.
        let transport = StdioTransport(command: "env", environment: ["MY_SERVER_KEY": "explicit"])
        #expect(transport.environment["MY_SERVER_KEY"] == "explicit")
    }

    // MARK: Item 10: exports made in the sandbox don't reach commands outside it.

    @Test func exportsFromSandboxedCommandsAreHeldOutsideTheSandbox() {
        let shell = ShellState(cwd: URL(fileURLWithPath: "/"))
        shell.absorb(before: ["PATH": "/usr/bin"], after: ["PATH": "/p/.bin:/usr/bin", "VIRTUAL_ENV": "/p/venv"], sandboxed: true)
        shell.absorb(before: [:], after: ["SAFE": "1"], sandboxed: false)
        let inside = shell.prelude(sandboxed: true)
        #expect(inside.held.isEmpty && inside.text.contains("export PATH=") && inside.text.contains("export SAFE="))
        let outside = shell.prelude(sandboxed: false)
        #expect(outside.held == ["PATH", "VIRTUAL_ENV"])
        #expect(!outside.text.contains("PATH") && outside.text.contains("export SAFE='1'"))
        // Set again outside the sandbox, it's trusted; unset, it's forgotten.
        shell.absorb(before: ["PATH": "/p/.bin:/usr/bin"], after: ["PATH": "/usr/bin"], sandboxed: false)
        shell.absorb(before: ["VIRTUAL_ENV": "/p/venv"], after: [:], sandboxed: false)
        #expect(shell.sandboxed.isEmpty)
        #expect(shell.prelude(sandboxed: false).text.contains("export PATH='/usr/bin'"))
        // Copies for a check command or a subagent keep the marks.
        shell.absorb(before: [:], after: ["GIT_SSH_COMMAND": "x"], sandboxed: true)
        let copy = ShellState(cwd: URL(fileURLWithPath: "/"), exported: shell.exported, unset: shell.unset, sandboxed: shell.sandboxed)
        #expect(copy.prelude(sandboxed: false).held == ["GIT_SSH_COMMAND"])
    }

    @Test(.enabled(if: SandboxPolicy.isAvailable)) func aSandboxedExportDoesNotReachALaterUnsandboxedCommand() async throws {
        let ws = try makeProject()
        var sandboxed = AgentConfig(tools: [BashTool()])
        sandboxed.shell = ShellState(cwd: ws.root)
        sandboxed.sandbox = SandboxPolicy()
        let first = await run(BashTool(), ["command": "export KK_BH_PATHISH=\"$PWD/.bin\"; echo set"], in: ws, config: sandboxed)
        #expect(first.exitCode == 0 && first.text.contains("Exported for later commands: KK_BH_PATHISH"))
        var open = sandboxed
        open.sandbox = nil
        let second = await run(BashTool(), ["command": "echo \"[${KK_BH_PATHISH:-unset}]\""], in: ws, config: open)
        #expect(second.text.contains("[unset]"))
        #expect(second.text.contains("Not applied to this command, which ran outside the sandbox: KK_BH_PATHISH"))
        // Back in the sandbox it applies again.
        let third = await run(BashTool(), ["command": "echo \"[${KK_BH_PATHISH:-unset}]\""], in: ws, config: sandboxed)
        #expect(third.text.contains("/.bin]"))
    }
}
