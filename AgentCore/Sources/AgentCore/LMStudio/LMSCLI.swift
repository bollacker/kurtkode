import Foundation

/// Drives LM Studio through its `lms` command-line tool. Only meaningful for an LM Studio on this Mac.
public struct LMSCLI: Sendable {
    public let executable: URL

    public init(executable: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: ".cache/lm-studio/bin/lms")) {
        self.executable = executable
    }

    public var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    public struct Failure: Error, LocalizedError, Sendable {
        public let arguments: [String]
        public let status: Int32
        public let output: String
        public var errorDescription: String? {
            "lms \(arguments.joined(separator: " ")) failed (\(status)): \(output.suffix(400))"
        }
    }

    /// A model file on disk, from `lms ls --json`.
    public struct LocalModel: Decodable, Sendable, Hashable {
        public let type: String
        public let modelKey: String
        public let displayName: String?
        public let sizeBytes: Int64?
        public let vision: Bool?
        public let trainedForToolUse: Bool?
        public let maxContextLength: Int?
    }

    /// A model loaded now, from `lms ps --json`: its id, context, and parallel slots.
    public struct LoadedModel: Decodable, Sendable, Hashable {
        public let identifier: String
        public let contextLength: Int?
        public let parallel: Int?
    }

    public func loadedModels() async throws -> [LoadedModel] {
        let out = try await run(["ps", "--json"])
        return try JSONDecoder().decode([LoadedModel].self, from: Data(out.utf8))
    }

    public func startServer() async throws {
        _ = try await run(["server", "start"])
    }

    /// Loads a model under its own id with an explicit context and, by default, one parallel slot.
    /// Each slot reserves its own cache; LM Studio's default of 4 slots multiplied memory use.
    public func load(_ modelKey: String, contextLength: Int, parallel: Int = 1) async throws {
        _ = try await run(["load", modelKey, "--context-length", String(contextLength),
                           "--parallel", String(parallel), "-y"])
    }

    public func unload(_ modelKey: String) async throws {
        _ = try await run(["unload", modelKey])
    }

    public func unloadAll() async throws {
        _ = try await run(["unload", "--all"])
    }

    public func localModels() async throws -> [LocalModel] {
        let out = try await run(["ls", "--json"])
        return try JSONDecoder().decode([LocalModel].self, from: Data(out.utf8))
    }

    /// Runs `lms` and returns its output. Progress bars (carriage-return redraws) are collapsed. Cancelling the task
    /// ends the `lms` process (a load can take minutes; Esc in the CLI stops waiting for it).
    func run(_ arguments: [String]) async throws -> String {
        let executable = executable
        final class Launch: @unchecked Sendable {
            let lock = NSLock()
            var process: Process?
            var cancelled = false
        }
        let launch = Launch()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // Blocking reads happen off the cooperative pool. Output is drained while the process runs:
                // `lms load` prints enough progress-bar redraws to fill a pipe and stall if it isn't read.
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = executable
                    p.arguments = arguments
                    let pipe = Pipe()
                    p.standardOutput = pipe
                    p.standardError = pipe
                    do {
                        try launch.lock.withLock {
                            if launch.cancelled { throw CancellationError() }
                            try p.run()
                            launch.process = p
                        }
                    } catch { cont.resume(throwing: error); return }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    let text = Self.clean(String(decoding: data, as: UTF8.self))
                    if launch.lock.withLock({ launch.cancelled }) {
                        cont.resume(throwing: CancellationError())
                    } else if p.terminationStatus == 0 {
                        cont.resume(returning: text)
                    } else {
                        cont.resume(throwing: Failure(arguments: arguments, status: p.terminationStatus, output: text))
                    }
                }
            }
        } onCancel: {
            launch.lock.withLock {
                launch.cancelled = true
                launch.process?.terminate()
            }
        }
    }

    /// Keeps the last state of each carriage-return-redrawn line and drops ANSI escapes.
    static func clean(_ s: String) -> String {
        let noANSI = s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        return noANSI.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\r").last.map(String.init) ?? "" }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
