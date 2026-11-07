import Foundation
import Testing
@testable import AgentCore

// Bug hunt 2026-11-02, item 38: kurtkode's own git ignores the caller's GIT_DIR, has a time limit, and reads its
// output while it runs.

private func repo(_ tag: String) async throws -> GitRepo {
    let root = FileManager.default.temporaryDirectory.appending(path: "kk-bh-git-\(tag)-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repo = GitRepo(root: root)
    _ = try await repo.git(["init", "-q", "-b", "main"])
    _ = try await repo.git(["config", "user.email", "t@example.com"])
    _ = try await repo.git(["config", "user.name", "Test"])
    return repo
}

@Suite(.serialized) struct BugHuntGitTests {
    /// Run from a git hook or `rebase -x`, the process has GIT_DIR and GIT_WORK_TREE for another repository. (Tested on
    /// the environment rather than by setting them in this process: other suites run git at the same time.)
    @Test func theCallersGitDirDoesNotRedirectTheGitPanel() async throws {
        let caller = ["GIT_DIR": "/elsewhere/.git", "GIT_WORK_TREE": "/elsewhere", "GIT_INDEX_FILE": "/elsewhere/.git/index",
                      "GIT_SSH_COMMAND": "ssh -i key", "PATH": "/usr/bin"]
        let env = GitRepo.environment(keeping: GitRepo.keptVariables, ["GIT_LITERAL_PATHSPECS": "1"], base: caller)
        #expect(env["GIT_DIR"] == nil && env["GIT_WORK_TREE"] == nil && env["GIT_INDEX_FILE"] == nil)
        #expect(env["GIT_SSH_COMMAND"] == "ssh -i key" && env["PATH"] == "/usr/bin")
        #expect(env["GIT_TERMINAL_PROMPT"] == "0" && env["GIT_LITERAL_PATHSPECS"] == "1")
        // The snapshots' git keeps none of them.
        #expect(GitRepo.environment(base: caller)["GIT_SSH_COMMAND"] == nil)
        // And a real call, with GIT_DIR pointing at another repository, lands in its own.
        let here = try await repo("here"), other = try await repo("other")
        defer { try? FileManager.default.removeItem(at: here.root); try? FileManager.default.removeItem(at: other.root) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", here.root.path, "rev-parse", "--show-toplevel"]
        p.environment = GitRepo.environment(keeping: GitRepo.keptVariables,
                                            base: ["GIT_DIR": other.root.appending(path: ".git").path, "GIT_WORK_TREE": other.root.path])
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let top = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        #expect(top.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/" + here.root.lastPathComponent))
    }

    @Test func aGitThatHangsIsStoppedByItsTimeLimit() async throws {
        let here = try await repo("hang")
        defer { try? FileManager.default.removeItem(at: here.root) }
        // An ssh that never answers, like one waiting for a passphrase.
        let fake = here.root.appending(path: "fake-ssh")
        try Data("#!/bin/sh\nexec sleep 15\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        _ = try await here.git(["config", "core.sshCommand", fake.path])
        let started = Date()
        do {
            _ = try await here.git(["fetch", "ssh://git.example.invalid/x.git"], timeout: 2)
            Issue.record("fetch should not succeed")
        } catch {
            #expect(error.localizedDescription.contains("took longer than 2 seconds"))
            #expect(error.localizedDescription.contains("credential helper or ssh-agent"))
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func networkCommandsGetLongerAndLocalOnesShorterLimits() {
        #expect(GitRepo.timeout(for: ["push", "--quiet"]) == 120)
        #expect(GitRepo.timeout(for: ["status"]) == 60)
        #expect(GitRepo.timeout(for: ["commit", "-q"]) > 60)
    }

    /// `git status` of a big dirty tree is more than a pipe holds; waiting for the exit before reading deadlocked.
    @Test func buildInfoReadsMoreThanAPipeHolds() async throws {
        let here = try await repo("big")
        defer { try? FileManager.default.removeItem(at: here.root) }
        let big = (0..<4000).map { "line \($0) " + String(repeating: "x", count: 60) }.joined(separator: "\n")
        try Data(big.utf8).write(to: here.root.appending(path: "big.txt"))
        _ = try await here.git(["add", "big.txt"])
        _ = try await here.git(["commit", "-q", "-m", "big"])
        #expect(big.utf8.count > 200_000)
        let out = await Task.detached { BuildInfo.git(["show", "HEAD:big.txt"], in: here.root) }.value
        #expect(out == big)
    }
}
