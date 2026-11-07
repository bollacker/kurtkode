import Foundation

/// Where the eval's default folders are anchored: the top of the git repository the process runs in (so
/// `swift run kurtkode-eval` from AgentCore/ reads and writes the repository's `eval-results`, not a stray
/// `AgentCore/eval-results`), or the working folder outside one (BUG_HUNT_2026-11-02.md item 49).
public enum EvalPaths {
    public static let root: URL = {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path, "rev-parse", "--show-toplevel"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return cwd }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let top = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !top.isEmpty ? URL(fileURLWithPath: top) : cwd
    }()
}
