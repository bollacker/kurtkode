import Foundation

/// The editor a changed file opens in, at its line.
public enum Editor: String, CaseIterable, Sendable, Identifiable {
    case system, vscode, cursor, zed, sublime, xcode

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "Default app"
        case .vscode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .sublime: "Sublime Text"
        case .xcode: "Xcode"
        }
    }

    /// Where its command-line tool can be: an app started from the Finder doesn't have the shell's PATH.
    var candidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func onPath(_ name: String) -> [String] { ["/usr/local/bin/" + name, "/opt/homebrew/bin/" + name, home + "/.local/bin/" + name] }
        switch self {
        case .system: return []
        case .vscode: return onPath("code") + ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
        case .cursor: return onPath("cursor") + ["/Applications/Cursor.app/Contents/Resources/app/bin/cursor"]
        case .zed: return onPath("zed") + ["/Applications/Zed.app/Contents/MacOS/cli"]
        case .sublime: return onPath("subl") + ["/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl"]
        case .xcode: return ["/usr/bin/xed"]
        }
    }

    /// The arguments that open `path` at `line`.
    public func arguments(path: String, line: Int?) -> [String] {
        let at = line.map { "\(path):\($0)" } ?? path
        switch self {
        case .system: return [path]
        case .vscode, .cursor: return ["-g", at]
        case .zed, .sublime: return [at]
        case .xcode: return (line.map { ["-l", String($0)] } ?? []) + [path]
        }
    }

    /// The tool and arguments to run, or nil when this editor isn't here (or is the default app).
    public func command(path: String, line: Int?) -> (tool: String, arguments: [String])? {
        guard let tool = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return (tool, arguments(path: path, line: line))
    }
}
