import Foundation
import Testing
@testable import AgentCore

/// A fresh repository with one commit (a.txt, b.txt), committer set locally.
private func makeRepo(commit: Bool = true) async throws -> GitRepo {
    let root = FileManager.default.temporaryDirectory.appending(path: "kk-git-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let repo = GitRepo(root: root)
    _ = try await repo.git(["init", "-q", "-b", "main"])
    _ = try await repo.git(["config", "user.email", "t@example.com"])
    _ = try await repo.git(["config", "user.name", "Test"])
    try write(repo, "a.txt", "one\ntwo\n")
    try write(repo, "b.txt", "bee\n")
    if commit {
        try await repo.stageAll()
        try await repo.commit(message: "first")
    }
    return repo
}

private func write(_ repo: GitRepo, _ path: String, _ text: String) throws {
    let url = repo.root.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func read(_ repo: GitRepo, _ path: String) -> String? {
    (try? Data(contentsOf: repo.root.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
}

@Suite struct GitRepoTests {
    @Test func parsesBranchAheadBehindAndRenames() {
        let s = GitRepo.parseStatus("## main...origin/main [ahead 2, behind 1]\0 M a.txt\0R  new.txt\0old.txt\0?? notes/x.md\0UU both.txt\0")
        #expect(s.branch == "main")
        #expect(s.upstream == "origin/main")
        #expect(s.ahead == 2 && s.behind == 1)
        #expect(s.files.map(\.path) == ["a.txt", "new.txt", "notes/x.md", "both.txt"])
        #expect(s.files[1].originalPath == "old.txt")
        #expect(s.files.map(\.kind) == ["modified", "renamed", "new", "conflict"])
        #expect(s.files[0].isUnstaged && !s.files[0].isStaged)
        #expect(s.files[1].isStaged && !s.files[1].isUnstaged)
        let fresh = GitRepo.parseStatus("## No commits yet on main\0?? a.txt\0")
        #expect(fresh.isNewRepository && fresh.branch == "main")
    }

    @Test func statusDiffStageUnstageCommit() async throws {
        let repo = try await makeRepo()
        try write(repo, "a.txt", "one\nTWO\n")
        try write(repo, "c.txt", "sea\n")
        var s = try await repo.status()
        #expect(s.branch == "main")
        #expect(s.files.map(\.path).sorted() == ["a.txt", "c.txt"])
        let a = try #require(s.files.first { $0.path == "a.txt" })
        let diff = try await repo.diff(a)
        #expect(diff.contains("-two") && diff.contains("+TWO"))
        let c = try #require(s.files.first { $0.path == "c.txt" })
        #expect(try await repo.diff(c).contains("+sea"))

        try await repo.stage(["a.txt"])
        s = try await repo.status()
        #expect(s.files.first { $0.path == "a.txt" }?.isStaged == true)
        try await repo.unstage(["a.txt"])
        s = try await repo.status()
        #expect(s.files.first { $0.path == "a.txt" }?.isStaged == false)

        try await repo.stage(["a.txt"])
        let commit = try await repo.commit(message: "Capitalize two\n\nBody text.")
        #expect(commit.hasSuffix("Capitalize two"))
        s = try await repo.status()
        #expect(s.files.map(\.path) == ["c.txt"])                // the untracked file is untouched
    }

    @Test func discardRestoresOrDeletes() async throws {
        let repo = try await makeRepo()
        try write(repo, "a.txt", "changed\n")
        try await repo.stage(["a.txt"])
        try write(repo, "a.txt", "changed again\n")             // staged and unstaged changes
        try write(repo, "new.txt", "scratch\n")
        try write(repo, "added.txt", "staged new file\n")
        try await repo.stage(["added.txt"])
        for f in try await repo.status().files { try await repo.discard(f) }
        #expect(read(repo, "a.txt") == "one\ntwo\n")
        #expect(read(repo, "new.txt") == nil)
        #expect(read(repo, "added.txt") == nil)
        #expect(try await repo.status().files.isEmpty)
    }

    @Test func worksBeforeTheFirstCommitAndReportsGitErrors() async throws {
        let repo = try await makeRepo(commit: false)
        var s = try await repo.status()
        #expect(s.isNewRepository)
        try await repo.stage(["a.txt"])
        s = try await repo.status()
        let a = try #require(s.files.first { $0.path == "a.txt" })
        #expect(a.isStaged)
        #expect(try await repo.diff(a, isNewRepository: true).contains("+one"))
        try await repo.unstage(["a.txt"], isNewRepository: true)
        #expect(try await repo.status().files.first { $0.path == "a.txt" }?.isUntracked == true)
        await #expect(throws: GitRepo.Failure.self) { try await repo.commit(message: "nothing staged") }
        await #expect(throws: GitRepo.Failure.self) { try await repo.commit(message: "  ") }
    }
}
