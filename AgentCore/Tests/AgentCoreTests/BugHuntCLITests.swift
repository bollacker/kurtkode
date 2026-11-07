import Darwin
import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

private func settings(default endpoint: Endpoint, others: [Endpoint] = []) throws -> AppSettings {
    let support = FileManager.default.temporaryDirectory.appending(path: "kk-bhcli-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try EndpointStore(fileURL: support.appending(path: "endpoints.json")).save([endpoint] + others)
    let defaults = try #require(UserDefaults(suiteName: "kk-bhcli-\(UUID().uuidString.prefix(8))"))
    defaults.set(endpoint.id.uuidString, forKey: "defaultEndpointID")
    defaults.set("test-model", forKey: "defaultModel")
    return AppSettings(support: support, defaults: defaults, environment: [:])
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func add(_ s: String) { lock.withLock { text += s } }
    var all: String { lock.withLock { text } }
    var objects: [[String: JSONValue]] {
        all.split(separator: "\n").compactMap { line in
            guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { return nil }
            return o
        }
    }
}

private struct Boom: Error, CustomStringConvertible { var description: String { "the session is locked by another kurtkode" } }

// MARK: 32: -p's piped input and thrown errors

@Suite struct BugHuntPipedInputTests {
    @Test func pipesAndFilesAreReadToTheEndSocketsAndDevicesOnlyWhenReady() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        #expect(PipedInput.plan(fd: fds[0], promptGiven: true) == .readAll)

        let file = FileManager.default.temporaryDirectory.appending(path: "kk-bhcli-\(UUID().uuidString.prefix(8)).txt")
        try "diff".write(to: file, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        #expect(PipedInput.plan(fd: handle.fileDescriptor, promptGiven: true) == .readAll)

        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        #expect(PipedInput.plan(fd: pair[0], promptGiven: true) == .readIfReady)
        #expect(PipedInput.plan(fd: pair[0], promptGiven: false) == .readAll)       // the input is the prompt

        let null = open("/dev/null", O_RDONLY)
        defer { close(null) }
        #expect(PipedInput.plan(fd: null, promptGiven: true) == .readIfReady)
    }

    @Test func aSlowPipeIsWaitedFor() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        defer { close(fds[0]) }
        let writer = fds[1]
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            _ = "the diff".withCString { Darwin.write(writer, $0, strlen($0)) }
            close(writer)
        }
        let notes = Lines()
        let text = PipedInput.read(fd: fds[0], promptGiven: true, waitMilliseconds: 100) { notes.add($0) }
        #expect(text == "the diff")
        #expect(notes.all.contains("waiting for stdin"))
    }

    @Test func aQuietSocketIsSkippedWithANote() throws {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        let notes = Lines()
        #expect(PipedInput.read(fd: pair[0], promptGiven: true, waitMilliseconds: 50) { notes.add($0) } == nil)
        #expect(notes.all.contains("not reading stdin"))
    }

    @Test func jsonOutputCarriesAThrownError() throws {
        let out = Lines()
        let r = Renderer(style: .print(.json), out: { out.add($0) }, err: { _ in })
        r.fail(Boom())
        r.finish(session: UUID(), model: "m")
        let o = try #require(out.objects.last)
        #expect(o["stop"] == .string("error"))
        #expect(o["error"] == .string("the session is locked by another kurtkode"))
    }

    @Test func streamJSONEndsWithAnErrorEvent() throws {
        let out = Lines()
        let r = Renderer(style: .print(.streamJSON), out: { out.add($0) }, err: { _ in })
        r.fail(Boom())
        r.finish(session: UUID(), model: "m")
        let objects = out.objects
        #expect(objects.first?["type"] == .string("error"))
        #expect(objects.last?["stop"] == .string("error") && objects.last?["error"] != nil)
    }

    @Test func aCompletedRunHasNoError() throws {
        let out = Lines()
        let r = Renderer(style: .print(.json), out: { out.add($0) }, err: { _ in })
        r.handle(.finished(.completed))
        r.finish(session: UUID(), model: "m")
        let o = try #require(out.objects.last)
        #expect(o["stop"] == .string("completed") && o["error"] == nil)
    }
}

// MARK: 33: stopping /model's load; Shift-Tab's order

@Suite struct BugHuntStopAndModeTests {
    @Test func cancellingAnLMSRunEndsTheProcess() async throws {
        let lms = LMSCLI(executable: URL(fileURLWithPath: "/bin/sleep"))
        let started = Date()
        let task = Task { try await lms.run(["30"]) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func fastPressesStepFromTheLastPickAndApplyInOrder() async throws {
        let applied = Lines()
        let cycle = ModeCycle { mode in
            // The first change is the slowest: applied out of order, the mode would end as the first pick.
            try? await Task.sleep(for: .milliseconds(mode == .acceptEdits ? 200 : 10))
            applied.add(mode.rawValue + " ")
        }
        let order: [PermissionMode] = [.ask, .acceptEdits, .plan, .fullAuto]
        // The session still says Ask for every press: the changes haven't been applied yet.
        let picks = (0..<3).map { _ in cycle.step(from: .ask, order: order) }
        #expect(picks == [.acceptEdits, .plan, .fullAuto])
        #expect(cycle.pendingMode == .fullAuto)
        await cycle.settled()
        #expect(applied.all == "acceptEdits plan fullAuto ")
        #expect(cycle.pendingMode == nil)
    }
}

// MARK: 34: endpoint names and subcommands

@Suite struct BugHuntEndpointNameTests {
    let keyed = Endpoint(name: "Claude", kind: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!)
    let local = Endpoint(name: "Ollama", kind: .openai, baseURL: URL(string: "http://127.0.0.1:11434/v1")!, usesAPIKey: false)

    @Test func aMisspelledEndpointIsRefusedNotSentToTheDefault() throws {
        let s = try settings(default: keyed, others: [local])
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.resolveModel("lmstudo:qwen3", settings: s) }
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.resolveModel("ollamma:qwen3", settings: s) }
        // A remote, keyed default doesn't take a colon id without a vendor.
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.resolveModel("myserver:qwen3", settings: s) }
        do { _ = try CLIOptions.resolveModel("lmstudo:qwen3", settings: s) } catch {
            #expect("\(error)".contains("no endpoint named lmstudo") && "\(error)".contains("did you mean lmstudio"))
        }
        // Still fine: a known endpoint, a vendor's id with a tag, a bare model.
        #expect(try CLIOptions.resolveModel("ollama:qwen3:8b", settings: s) == (local, "qwen3:8b"))
        #expect(try CLIOptions.resolveModel("lmstudio:x", settings: s).0.id == Endpoint.localLMStudio.id)
        #expect(try CLIOptions.resolveModel("google/gemma-4:free", settings: s) == (keyed, "google/gemma-4:free"))
        #expect(try CLIOptions.resolveModel("claude-sonnet-4-5", settings: s) == (keyed, "claude-sonnet-4-5"))
    }

    @Test func aLocalDefaultTakesOllamaStyleIds() throws {
        let s = try settings(default: local)
        #expect(try CLIOptions.resolveModel("qwen3:8b", settings: s) == (local, "qwen3:8b"))
        // But not an endpoint-shaped prefix before a vendor's model id.
        #expect(throws: CLIOptions.ParseError.self) { try CLIOptions.resolveModel("studio:qwen/qwen3-coder", settings: s) }
    }

    @Test func aLaunchEndpointCantShareASavedName() throws {
        var s = try settings(default: keyed)
        #expect(throws: CLIOptions.ParseError.self) {
            try s.addLaunchEndpoints([.launchOnly(name: "claude", url: URL(string: "http://127.0.0.1:18090/v1")!)])
        }
        #expect(throws: CLIOptions.ParseError.self) {
            try s.addLaunchEndpoints([.launchOnly(name: "local", url: URL(string: "http://127.0.0.1:18090/v1")!)])
        }
        let mock = Endpoint.launchOnly(name: "mock", url: URL(string: "http://127.0.0.1:18090/v1")!)
        try s.addLaunchEndpoints([mock])
        #expect(s.endpoint(named: "mock")?.id == mock.id)
        #expect(throws: CLIOptions.ParseError.self) { try s.addLaunchEndpoints([mock]) }
    }

    @Test func aSubcommandAfterGlobalOptionsIsFound() {
        let names = SetupCommands.names.union(DebugCommands.names)
        #expect(CLIOptions.subcommandFirst(["-C", "~/proj", "inspect"], names: names) == ["inspect", "-C", "~/proj"])
        #expect(CLIOptions.subcommandFirst(["--plain", "-m", "x:y", "doctor", "--json"], names: names)
                == ["doctor", "--plain", "-m", "x:y", "--json"])
        #expect(CLIOptions.subcommandFirst(["inspect"], names: names) == ["inspect"])
        #expect(CLIOptions.subcommandFirst(["-p", "fix the inspect command"], names: names) == nil)
        #expect(CLIOptions.subcommandFirst(["-m", "doctor", "hello"], names: names) == nil)   // -m's value
        #expect(CLIOptions.subcommandFirst(["--", "inspect"], names: names) == nil)
    }
}

// MARK: 35: a reader that goes away

@Suite struct BugHuntBrokenPipeTests {
    @Test func writingToAClosedPipeReportsItInsteadOfDying() throws {
        signal(SIGPIPE, SIG_IGN)                // as kurtkode does at startup
        let pipe = Pipe()
        try pipe.fileHandleForReading.close()
        #expect(!Renderer.put(Data("hello\n".utf8), to: pipe.fileHandleForWriting))
        let closed = Lines()
        let write = Renderer.write(to: pipe.fileHandleForWriting, closed: { closed.add("closed") })
        write("more\n")
        #expect(closed.all == "closed")
        // An open pipe takes it.
        let open = Pipe()
        #expect(Renderer.put(Data("ok".utf8), to: open.fileHandleForWriting))
    }
}
