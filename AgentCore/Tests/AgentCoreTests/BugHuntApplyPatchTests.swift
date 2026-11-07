import Foundation
import Testing
@testable import AgentCore

// Bug hunt 2026-11-02, item 40: apply_patch's loose matching and all-or-none writes.

private func project(_ files: [String: String]) throws -> Workspace {
    let root = FileManager.default.temporaryDirectory.appending(path: "kk-bh-patch-\(UUID().uuidString.prefix(8))")
    for (path, text) in files {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    return Workspace(root: root)
}

private func patch(_ text: String, in ws: Workspace) async -> (text: String, failed: Bool) {
    do {
        let out = try await ApplyPatchTool().run(ToolArguments(["patch": .string(text)]), context: ToolContext(workspace: ws))
        return (out.text, out.isError)
    } catch { return (error.localizedDescription, true) }
}

private func read(_ ws: Workspace, _ path: String) -> String? { try? String(contentsOf: ws.root.appending(path: path), encoding: .utf8) }

@Suite struct BugHuntApplyPatchTests {
    @Test func aLooseMatchInSeveralPlacesIsRefused() async throws {
        let original = "class A:\n    def f(self):\n        return 1\n\nclass B:\n    def f(self):\n        return 1\n"
        let ws = try project(["m.py": original])
        defer { try? FileManager.default.removeItem(at: ws.root) }
        let (text, failed) = await patch("""
            *** Begin Patch
            *** Update File: m.py
            @@
             def f(self):
            -    return 1
            +    return 2
            *** End Patch
            """, in: ws)
        #expect(failed)
        #expect(text.contains("matches 2 places") && text.contains("lines 2, 6") && text.contains("Nothing was changed"))
        #expect(read(ws, "m.py") == original)
    }

    @Test func aMatchFoundByIgnoringIndentationTakesTheFilesIndentation() async throws {
        let ws = try project(["m.py": "class A:\n    def f(self):\n        return 1\n"])
        defer { try? FileManager.default.removeItem(at: ws.root) }
        let (text, failed) = await patch("""
            *** Begin Patch
            *** Update File: m.py
            @@
             def f(self):
            -    return 1
            +    if self.x:
            +        return 2
            +    return 1
            *** End Patch
            """, in: ws)
        #expect(!failed, "\(text)")
        #expect(read(ws, "m.py") == "class A:\n    def f(self):\n        if self.x:\n            return 2\n        return 1\n")
    }

    @Test func theWholeFileSearchRefusesSeveralExactMatches() async throws {
        let original = "a\nx\nb\nx\nc\n"
        let ws = try project(["t.txt": original])
        defer { try? FileManager.default.removeItem(at: ws.root) }
        // The second hunk's lines come before the first's: they're looked for in the whole file, where "x" is twice.
        let (text, failed) = await patch("""
            *** Begin Patch
            *** Update File: t.txt
            @@
            -c
            +C
            @@
            -x
            +X
            *** End Patch
            """, in: ws)
        #expect(failed)
        #expect(text.contains("hunk 2 of 2") && text.contains("matches 2 places"))
        #expect(read(ws, "t.txt") == original)
    }

    @Test func aWriteThatFailsChangesNoFile() async throws {
        let ws = try project(["a.txt": "one\n", "locked/b.txt": "two\n"])
        let locked = ws.root.appending(path: "locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: ws.root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let (text, failed) = await patch("""
            *** Begin Patch
            *** Update File: a.txt
            @@
            -one
            +ONE
            *** Add File: fresh/new.txt
            +new
            *** Update File: locked/b.txt
            @@
            -two
            +TWO
            *** End Patch
            """, in: ws)
        #expect(failed)
        #expect(text.contains("couldn't write locked/b.txt") && text.contains("Nothing was changed"))
        #expect(read(ws, "a.txt") == "one\n")
        #expect(read(ws, "locked/b.txt") == "two\n")
        #expect(!FileManager.default.fileExists(atPath: ws.root.appending(path: "fresh").path))
        let left = try FileManager.default.contentsOfDirectory(atPath: ws.root.path)
        #expect(!left.contains { $0.contains("kk-patch") })
    }

    @Test func anUpdatedFileKeepsItsPermissions() async throws {
        let ws = try project(["run.sh": "#!/bin/sh\necho 1\n"])
        defer { try? FileManager.default.removeItem(at: ws.root) }
        let script = ws.root.appending(path: "run.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let (text, failed) = await patch("*** Begin Patch\n*** Update File: run.sh\n@@\n-echo 1\n+echo 2\n*** End Patch", in: ws)
        #expect(!failed, "\(text)")
        #expect(read(ws, "run.sh") == "#!/bin/sh\necho 2\n")
        #expect((try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int) == 0o755)
    }
}
