import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

/// Bug hunt 2026-11-02, Part 1 items 13, 15 and 26: settings files, session locking, trash and rewrites.
@Suite struct BugHuntCoreDataTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bh-coredata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: 13. endpoints.json and profiles.json

    @Test func anEndpointThisBuildCantReadIsKeptAndTheOthersLoad() throws {
        let dir = try tempDir()
        let url = dir.appending(path: "endpoints.json")
        let good = Endpoint(name: "Router", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let future = #"{"id":"\#(UUID().uuidString)","name":"Future","kind":"quantum","baseURL":"https://q.example/v1"}"#
        try Data("[\(goodJSON),\(future)]".utf8).write(to: url)

        let store = EndpointStore(fileURL: url)
        let loaded = store.loadChecked()
        #expect(loaded.value.map(\.name).contains("Router"))
        #expect(!loaded.unreadable)
        #expect(loaded.problem?.contains("1 entry") == true)

        // Saving (as the app does on any edit) keeps the entry it couldn't read.
        var list = loaded.value
        list.append(Endpoint(name: "Added", kind: .openai, baseURL: URL(string: "http://127.0.0.1:8080/v1")!))
        try store.save(list)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("quantum"))
        #expect(Set(store.load().map(\.name)) == [Endpoint.localLMStudio.name, "Router", "Added"])
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Any]
        #expect(raw?.count == 4)
    }

    @Test func anUnreadableEndpointsFileIsBackedUpAndNotSavedOver() throws {
        let dir = try tempDir()
        let url = dir.appending(path: "endpoints.json")
        // Cut off mid-write. (A trailing comma, the other case reported, now reads: Foundation's parser accepts it.)
        let original = #"[{"id":"\#(UUID().uuidString)","name":"Mine","kind":"openai","baseURL":"https://x.exa"#
        try Data(original.utf8).write(to: url)

        let store = EndpointStore(fileURL: url)
        let loaded = store.loadChecked()
        #expect(loaded.unreadable)
        #expect(loaded.value.map(\.id) == [Endpoint.localLMStudio.id])
        #expect(loaded.problem?.contains("can't be read") == true)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("endpoints.json.bad-") }
        #expect(backups.count == 1)
        _ = store.loadChecked()            // a second launch doesn't make a second copy
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("endpoints.json.bad-") }.count == 1)

        #expect(throws: ConfigFileUnreadable.self) { try store.save(loaded.value) }
        #expect(try String(contentsOf: url, encoding: .utf8) == original)

        // Replacing it on purpose works, and the original stays in the copy.
        try store.save(loaded.value, replacingUnreadable: true)
        #expect(!store.loadChecked().unreadable)
        let copy = dir.appending(path: backups[0])
        #expect(try String(contentsOf: copy, encoding: .utf8) == original)
    }

    @Test func profilesFollowTheSameRules() throws {
        let dir = try tempDir()
        let url = dir.appending(path: "profiles.json")
        let store = ProfileStore(fileURL: url)
        let ep = UUID()
        try store.save(ModelProfile.defaults(endpointID: ep, model: "a"))
        try store.save(ModelProfile.defaults(endpointID: ep, model: "b"))     // the first isn't lost
        #expect(store.load().count == 2)

        try Data("not json".utf8).write(to: url)
        #expect(store.loadChecked().unreadable)
        #expect(throws: ConfigFileUnreadable.self) { try store.save(ModelProfile.defaults(endpointID: ep, model: "c")) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func mergingKeepsChangesFromBothSides() {
        func e(_ name: String) -> Endpoint { Endpoint(name: name, kind: .openai, baseURL: URL(string: "http://h/v1")!) }
        let a = e("A"), b = e("B"), c = e("C"), d = e("D")
        let base = [a, b, c]
        var aMine = a; aMine.name = "A renamed here"
        var bTheirs = b; bTheirs.name = "B renamed there"
        let mine = [aMine, b, d]                 // renamed A, removed C, added D
        let theirs = [a, bTheirs, c, e("CLI")]   // renamed B, added one
        let merged = EndpointStore.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.map(\.name) == ["A renamed here", "B renamed there", "D", "CLI"])

        // Removed elsewhere and unchanged here: gone.
        #expect(EndpointStore.merge(base: [a, b], mine: [a, b], theirs: [a]).map(\.name) == ["A"])
    }

    @Test func theCLIRefusesToChangeAnUnreadableEndpointsFile() throws {
        let dir = try tempDir()
        let url = dir.appending(path: "endpoints.json")
        try Data("[{".utf8).write(to: url)
        let settings = AppSettings(support: dir, defaults: UserDefaults(suiteName: "bh-coredata-\(UUID().uuidString)")!,
                                   environment: [:])
        var output = ""
        let status = SetupCommands.endpoint(["add", "x", "http://127.0.0.1:9/v1", "--no-key"], settings: settings,
                                            readKey: { _ in nil }, saveKey: { _, _ in }, out: { output += $0 })
        #expect(status == 1)
        #expect(output.contains("Nothing changed"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "[{")
    }

    // MARK: 15. Session operations hold the session's lock

    /// Settings in a temporary data folder with one OpenAI-style endpoint, as CLITests sets them up.
    private func cliSettings() throws -> AppSettings {
        let support = try tempDir()
        let mock = Endpoint(name: "Mock", kind: .openai, baseURL: URL(string: "http://mock.invalid/v1")!)
        try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([mock])
        let defaults = try #require(UserDefaults(suiteName: "bh-coredata-\(UUID().uuidString.prefix(8))"))
        defaults.set(mock.id.uuidString, forKey: "defaultEndpointID")
        defaults.set("test-model", forKey: "defaultModel")
        defaults.set(SkillRouting.off.rawValue, forKey: RunSettings.Key.skillRouting)
        return AppSettings(support: support, defaults: defaults, environment: [:])
    }

    /// Looking at who holds the lock never takes it, so it can't make another process's start fail.
    @Test func checkingTheHolderNeverBlocksAnAcquire() throws {
        let url = SessionLock.url(forSession: UUID(), sessionsRoot: try tempDir().appending(path: "sessions"))
        if case .acquired(let l) = SessionLock.acquire(url, holder: "x") { l.release() }
        let stop = NSLock()
        nonisolated(unsafe) var done = false
        let checker = Thread {
            while !stop.withLock({ done }) { _ = SessionLock.holder(url) }
        }
        checker.start()
        var refused = 0
        for _ in 0..<3000 {
            switch SessionLock.acquire(url, holder: "kurtkode in a terminal (pid 2)") {
            case .acquired(let l):
                #expect(SessionLock.holder(url) == "kurtkode in a terminal (pid 2)")
                l.release()
            case .held: refused += 1
            }
        }
        stop.withLock { done = true }
        #expect(refused == 0)
    }

    @Test func withLockRefusesWhileHeldAndReloadsFirst() async throws {
        let url = SessionLock.url(forSession: UUID(), sessionsRoot: try tempDir().appending(path: "sessions"))
        guard case .acquired(let other) = SessionLock.acquire(url, holder: "the kurtkode app (pid 1)") else {
            Issue.record("not acquired"); return
        }
        var ran = false
        await #expect(throws: SessionBusy.self) {
            try await SessionLock.withLock(url, holder: "me", reload: {}) { ran = true }
        }
        #expect(!ran)
        other.release()
        var steps: [String] = []
        try await SessionLock.withLock(url, holder: "me", reload: { steps.append("reload") }) {
            steps.append("body")
            #expect(SessionLock.holder(url) == "me")
        }
        #expect(steps == ["reload", "body"])
        #expect(SessionLock.holder(url) == nil)
    }

    @Test func theCLIsCommandsWaitForTheOtherRunAndRetryReloadsFirst() async throws {
        let settings = try cliSettings()
        let ws = try makeProject()
        let (client, host) = MockServer.client(.init(turns: [SSE.content("First."), SSE.content("Second."), SSE.content("Third.")]))
        var options = CLIOptions()
        options.mcp = false
        let mine = try await CLISession(settings: settings, workspace: ws.root, options: options) { _, _ in client }
        _ = try await mine.send("one")
        var again = CLIOptions()
        again.continueLast = true
        again.mcp = false
        let other = try await CLISession(settings: settings, workspace: ws.root, options: again) { _, _ in client }
        _ = try await other.send("two")

        // While the app runs the session, a !command, /compact, /rewind and /retry are refused and change nothing.
        let url = settings.sessionStore.lockURL(for: mine.session.header.id)
        guard case .acquired(let app) = SessionLock.acquire(url, holder: "the kurtkode app (pid 1)") else {
            Issue.record("not acquired"); return
        }
        let before = try await settings.sessionStore.load(mine.session.header.id)?.messages.count
        await #expect(throws: CLISession.Failure.self) { _ = try await mine.runUserCommand("echo hi") }
        await #expect(throws: CLISession.Failure.self) { _ = try await mine.compact(focus: "") }
        await #expect(throws: CLISession.Failure.self) { _ = try await mine.retry() }
        let first = try #require(mine.session.messages.first?.id)
        await #expect(throws: CLISession.Failure.self) { _ = try await mine.rewind(to: first, choice: .conversation) }
        #expect(try await settings.sessionStore.load(mine.session.header.id)?.messages.count == before)
        app.release()

        // /retry takes back the newest reply, the other process's, not this one's stale last.
        _ = try await mine.retry()
        #expect(mine.session.messages.map(\.content) == ["one", "First.", "two", "Third."])
        let last = try JSONDecoder().decode(JSONValue.self, from: try #require(MockServer.requestBodies(host).last))
        guard case .object(let o) = last, case .array(let msgs) = o["messages"] else { Issue.record("body"); return }
        let users = msgs.compactMap { m -> String? in
            guard case .object(let mo) = m, mo["role"] == "user", case .string(let t) = mo["content"] else { return nil }
            return t
        }
        #expect(users == ["one", "two"])
    }

    // MARK: 26. Trash takes the companions; rewrites are atomic; orphaned shadow repositories go

    @Test func trashingASessionTakesItsCompanionsButNotImagesAForkUses() async throws {
        let root = try tempDir().appending(path: "sessions")
        let trash = try tempDir()
        let store = SessionStore(root: root)
        func companions(_ h: SessionHeader) throws {
            for (dir, file) in [(store.wireDirectory(for: h), "index.jsonl"), (store.outputDirectory(for: h), "o.txt"),
                                (store.checkpointDirectory(for: h), "index.jsonl"), (store.subagentDirectory(for: h), "\(UUID().uuidString).jsonl"),
                                (store.imagesDirectory(for: h), "a.png")] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data("x\n".utf8).write(to: dir.appending(path: file))
            }
            if case .acquired(let l) = SessionLock.acquire(store.lockURL(for: h.id), holder: "x") { l.release() }
        }
        func move(_ url: URL) throws { try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent)) }

        let a = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(a)
        try companions(a)
        // A fork of it whose message shows one of its images.
        let b = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(b)
        var shown = ChatMessage.user("look")
        shown.images = [ImageAttachment(id: UUID(), mediaType: "image/png",
                                        path: store.imagesDirectory(for: a).appending(path: "a.png").path, width: 1, height: 1)]
        try await store.append(.message(shown), to: b.id)

        try await store.trash(a.id, moveToTrash: move)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: store.fileURL(for: a).deletingLastPathComponent().path))
        let id = a.id.uuidString
        #expect(!left.contains("\(id).jsonl"))
        for kind in ["wire", "outputs", "checkpoints", "subagents"] {
            #expect(!left.contains("\(id).\(kind)"))
            #expect(FileManager.default.fileExists(atPath: trash.appending(path: "\(id).\(kind)").path))
        }
        #expect(left.contains("\(id).images"))                 // the fork still shows it
        #expect(!FileManager.default.fileExists(atPath: store.lockURL(for: a.id).path))

        // With no fork pointing at them, the images go too.
        let c = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(c)
        try companions(c)
        try await store.trash(c.id, moveToTrash: move)
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: "\(c.id.uuidString).images").path))
    }

    @Test func aRewriteReplacesTheFileWholeAndKeepsAConcurrentAppend() throws {
        let url = try tempDir().appending(path: "index.jsonl")
        try Data("a\nb\nc\n{\"torn".utf8).write(to: url)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int

        // An append that opens the file while the rewrite holds its lock, then waits for it.
        let appended = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        try JSONLines.rewrite(url) { lines in
            Thread.detachNewThread {
                started.signal()
                _ = try? JSONLines.append(Data("d\n".utf8), to: url)
                appended.signal()
            }
            started.wait()
            Thread.sleep(forTimeInterval: 0.2)
            return lines.filter { $0 != Data("b".utf8) }
        }
        #expect(appended.wait(timeout: .now() + 5) == .success)
        // Written to a new file renamed over the old (a crash can't leave it half written), the torn line kept as it was
        // (F3), and the append that waited landed in the new file.
        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
        #expect(before != after)
        #expect(try String(contentsOf: url, encoding: .utf8) == "a\nc\n{\"torn\nd\n")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(leftovers == ["index.jsonl"])
    }

    @Test func shadowRepositoriesOfProjectsThatAreGoneAreSwept() throws {
        let root = try tempDir()
        let old = Date().addingTimeInterval(-40 * 86_400)
        func repo(_ name: String, project: String, modified: Date) throws -> URL {
            let dir = root.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("kurtkode's snapshots of \(project) (GAP_ANALYSIS.md C1)\n".utf8).write(to: dir.appending(path: "description"))
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.path)
            return dir
        }
        let alive = try tempDir()
        let gone = try repo("gone-1.git", project: "/nonexistent-\(UUID().uuidString)/p", modified: old)
        let recent = try repo("recent-2.git", project: "/nonexistent-\(UUID().uuidString)/p", modified: Date())
        let present = try repo("present-3.git", project: alive.path, modified: old)
        let unmounted = try repo("unmounted-4.git", project: "/Volumes/NoSuchDisk-\(UUID().uuidString)/p", modified: old)
        let removed = ProjectSnapshots.sweepOrphans(root: root)
        #expect(removed.map(\.lastPathComponent) == ["gone-1.git"])
        #expect(!FileManager.default.fileExists(atPath: gone.path))
        for kept in [recent, present, unmounted] { #expect(FileManager.default.fileExists(atPath: kept.path)) }
    }
}
