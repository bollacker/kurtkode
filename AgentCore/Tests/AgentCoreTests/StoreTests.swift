import Foundation
import Testing
@testable import AgentCore

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "kurtkode-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct SessionStoreTests {
    @Test func roundTripsASession() async throws {
        let store = SessionStore(root: try tempDir())
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "qwen/qwen3-coder-30b")
        try await store.create(header)
        try await store.append(.message(.user("What is a closure?\nExplain briefly.")), to: header.id)
        let meta = TurnMeta(requestedModel: "qwen/qwen3-coder-30b", reportedModel: "qwen/qwen3-coder-30b",
                            usage: Usage(promptTokens: 20, completionTokens: 50), finishReason: .stop,
                            stopReason: .completed, timeToFirstToken: 0.4, duration: 2.5)
        try await store.append(.message(ChatMessage(role: .assistant, content: "A function that…", reasoning: "hmm",
                                                    meta: meta)), to: header.id)
        try await store.append(.model("google/gemma-4-12b-qat"), to: header.id)
        let openrouter = UUID()
        try await store.append(.model("qwen/qwen3-coder", endpoint: openrouter), to: header.id)
        try await store.append(.model("google/gemma-4-12b-qat", endpoint: Endpoint.localLMStudio.id), to: header.id)
        let dropped = ChatMessage.user("retried away")
        try await store.append(.message(dropped), to: header.id)
        try await store.append(.retract(dropped.id), to: header.id)
        let prompt = RecordedPrompt(text: "You are kurtkode.\n- Date: Monday", key: "ask||||", facts: "- Date: Monday")
        try await store.append(.systemPrompt(prompt), to: header.id)

        let s = try #require(try await store.load(header.id))
        #expect(s.header.id == header.id)
        #expect(s.header.model == header.model)
        #expect(abs(s.header.createdAt.timeIntervalSince(header.createdAt)) < 0.001)   // stored to the millisecond
        #expect(s.messages.count == 2)
        #expect(s.messages[1].meta == meta)
        #expect(s.messages[1].reasoning == "hmm")
        #expect(s.model == "google/gemma-4-12b-qat")
        #expect(s.endpointID == Endpoint.localLMStudio.id)
        #expect(s.displayTitle == "What is a closure?")
        #expect(s.recordedPrompt == prompt && s.systemPrompt == prompt.text)

        try await store.append(.title("Closures"), to: header.id)
        let list = try await store.list()
        #expect(list.map(\.title) == ["Closures"])
        #expect(list.first?.messageCount == 2)
    }

    /// The app and the command line each have a store on the same folder: each notices the other's appends.
    @Test func noticesAppendsByAnotherStore() async throws {
        let root = try tempDir()
        let app = SessionStore(root: root), cli = SessionStore(root: root)
        let header = SessionHeader(endpointID: Endpoint.localLMStudio.id, model: "m")
        try await app.create(header)
        try await app.append(.message(.user("from the app")), to: header.id)
        #expect(await app.changedElsewhere(header.id) == false)       // its own writes don't count
        _ = try await cli.load(header.id)
        try await cli.append(.message(.user("from the command line")), to: header.id)
        #expect(await app.changedElsewhere(header.id) == true)
        #expect(await cli.changedElsewhere(header.id) == false)
        // Still noticed after the app appends on top of it.
        try await app.append(.message(.user("app again")), to: header.id)
        #expect(await app.changedElsewhere(header.id) == true)
        // Loading catches up.
        let s = try #require(try await app.load(header.id))
        #expect(s.messages.map(\.content) == ["from the app", "from the command line", "app again"])
        #expect(await app.changedElsewhere(header.id) == false)
        #expect(await cli.changedElsewhere(header.id) == true)
        #expect(await SessionStore(root: root).changedElsewhere(header.id) == false)   // never read: nothing to compare
    }

    @Test func skipsATornLastLine() async throws {
        let root = try tempDir()
        let store = SessionStore(root: root)
        let header = SessionHeader(endpointID: UUID(), model: "m")
        try await store.create(header)
        try await store.append(.message(.user("one")), to: header.id)
        let file = root.appending(path: "_chats/\(header.id.uuidString).jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"message","message":{"id":"#.utf8))   // crash mid-write
        try handle.close()

        let s = try #require(try await SessionStore(root: root).load(header.id))
        #expect(s.messages.map(\.content) == ["one"])

        // The next record starts a line of its own instead of being glued onto the torn one (and lost with it).
        let again = SessionStore(root: root)
        _ = try await again.load(header.id)
        try await again.append(.message(.user("two")), to: header.id)
        let reloaded = try #require(try await SessionStore(root: root).load(header.id))
        #expect(reloaded.messages.map(\.content) == ["one", "two"])
    }

    @Test func listsNewestFirstAcrossProjects() async throws {
        let store = SessionStore(root: try tempDir())
        let a = SessionHeader(endpointID: UUID(), model: "m")
        let b = SessionHeader(endpointID: UUID(), model: "m", workspace: "/Users/me/git/kurtkode")
        try await store.create(a)
        try await store.append(.message(.user("older")), to: a.id)
        try await Task.sleep(for: .milliseconds(1100))    // mtime resolution
        try await store.create(b)
        try await store.append(.message(.user("newer")), to: b.id)
        let list = try await store.list()
        #expect(list.map(\.title) == ["newer", "older"])
        #expect(list.first?.workspace == "/Users/me/git/kurtkode")
    }

    @Test func projectKeysAreReadableAndDistinct() {
        #expect(SessionStore.projectKey(for: nil) == "_chats")
        let a = SessionStore.projectKey(for: "/Users/me/git/app")
        let b = SessionStore.projectKey(for: "/Users/me/old/app")
        #expect(a.hasPrefix("app-"))
        #expect(a != b)
    }
}

@Suite struct EndpointTests {
    @Test func localDefaultUsesIPv4AndDerivesServerRoot() {
        let e = Endpoint.localLMStudio
        #expect(e.baseURL.absoluteString == "http://127.0.0.1:1234/v1")
        #expect(e.serverRoot.absoluteString == "http://127.0.0.1:1234/")
        #expect(e.isLocal)
        let remote = Endpoint(name: "Studio", kind: .lmstudio, baseURL: URL(string: "http://studio.local:1234/v1")!)
        #expect(!remote.isLocal)
    }

    @Test func normalizesPastedRequestURLs() {
        for pasted in ["https://openrouter.ai/api/v1/chat/completions", "https://openrouter.ai/api/v1/",
                       "https://openrouter.ai/api/v1/models", "https://openrouter.ai/api/v1"] {
            #expect(Endpoint.normalizedBaseURL(URL(string: pasted)!).absoluteString == "https://openrouter.ai/api/v1")
        }
        #expect(Endpoint.normalizedBaseURL(URL(string: "http://127.0.0.1:1234/v1/")!).absoluteString == "http://127.0.0.1:1234/v1")
    }

    @Test func storeAlwaysIncludesLocalLMStudio() throws {
        let store = EndpointStore(fileURL: try tempDir().appending(path: "endpoints.json"))
        #expect(store.load() == [.localLMStudio])
        let other = Endpoint(name: "OpenRouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                             usesAPIKey: true, manualContextLength: 128_000)
        try store.save([other])
        #expect(store.load() == [.localLMStudio, other])
    }
}

@Suite struct SystemTests {
    @Test func readsMemoryStatus() {
        let m = MemoryStatus.current()
        #expect(m.totalBytes > 1 << 30)
        #expect((0...100).contains(m.freePercent))
    }

    @Test func cleansLMSProgressOutput() {
        let raw = "\u{1B}[?25lLoading x 0% ⠋\rLoading x 50% ⠙\rLoading x 100%\u{1B}[K\u{1B}[?25hModel loaded successfully in 3.2s.\n(14.57 GiB)"
        #expect(LMSCLI.clean(raw) == "Loading x 100%Model loaded successfully in 3.2s.\n(14.57 GiB)")
    }
}
