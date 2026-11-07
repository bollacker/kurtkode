import Foundation

/// Shell-style glob matching on relative paths: `*` and `?` stay within a path segment, `**` crosses
/// segments, `{a,b}` alternates, `[...]` is a character class. A pattern without a `/` matches the file
/// name at any depth, the way most people mean `*.swift`.
public struct Glob: Sendable {
    public let pattern: String
    private let regex: NSRegularExpression

    public init(_ pattern: String) throws {
        self.pattern = pattern
        var p = pattern
        if p.hasPrefix("./") { p.removeFirst(2) }
        if !p.contains("/") { p = "**/" + p }
        guard let re = try? NSRegularExpression(pattern: "^" + Self.translate(p) + "$") else {
            throw ToolFailure("invalid glob pattern: \(pattern)")
        }
        regex = re
    }

    public func matches(_ path: String) -> Bool {
        regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    static func translate(_ glob: String) -> String {
        var out = ""
        let chars = Array(glob)
        var i = 0
        var braceDepth = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    // "**/" matches zero or more directories; a bare "**" matches anything.
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"
                        i += 3
                    } else {
                        out += ".*"
                        i += 2
                    }
                    continue
                }
                out += "[^/]*"
            case "?": out += "[^/]"
            case "{": braceDepth += 1; out += "(?:"
            case "}" where braceDepth > 0: braceDepth -= 1; out += ")"
            case "," where braceDepth > 0: out += "|"
            case "[":
                if let close = chars[(i + 1)...].firstIndex(of: "]") {
                    var cls = String(chars[(i + 1)..<close])
                    if cls.hasPrefix("!") { cls = "^" + cls.dropFirst() }
                    out += "[" + cls.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                    i = close + 1
                    continue
                }
                out += "\\["
            default:
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        return out
    }
}
