import Foundation

/// Markdown for a terminal, a line at a time: a streaming reply is shown as its lines finish, and what's printed can't
/// be taken back. So only what one line (and whether it's inside a code block) decides is styled.
public struct MarkdownLines: Sendable {
    public let style: TerminalStyle
    private var fence: String?

    public init(style: TerminalStyle) { self.style = style }

    public mutating func render(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let open = fence {
            if trimmed.hasPrefix(open), trimmed.allSatisfy({ open.first == $0 }) {
                fence = nil
                return ""
            }
            return style.cyan("  " + line)
        }
        if let marker = Self.fenceMarker(trimmed) {
            fence = marker
            let language = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return language.isEmpty ? "" : style.dim("  " + language)
        }
        if trimmed.isEmpty { return "" }
        if let (level, text) = Self.heading(trimmed) {
            let body = inline(text)
            return level == 1 ? style.bold(style.blue(body)) : style.bold(body)
        }
        if Self.isRule(trimmed) { return style.dim(String(repeating: "─", count: 40)) }
        if trimmed.hasPrefix("> ") { return style.dim("│ ") + style.italic(inline(String(trimmed.dropFirst(2)))) }
        let indent = String(line.prefix { $0 == " " })
        if let rest = Self.bullet(trimmed) { return indent + style.cyan("• ") + inline(rest) }
        return indent + inline(String(line.dropFirst(indent.count)))
    }

    /// A reply that ended inside a code block: the next one starts clean.
    public mutating func reset() { fence = nil }

    private static func fenceMarker(_ s: String) -> String? {
        for mark in ["```", "~~~"] where s.hasPrefix(mark) { return String(s.prefix { $0 == mark.first }) }
        return nil
    }

    private static func heading(_ s: String) -> (Int, String)? {
        let level = s.prefix { $0 == "#" }.count
        guard (1...6).contains(level), s.dropFirst(level).first == " " else { return nil }
        return (level, s.dropFirst(level + 1).trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
    }

    private static func isRule(_ s: String) -> Bool {
        s.count >= 3 && ["-", "*", "_"].contains { mark in s.allSatisfy { String($0) == mark } }
    }

    private static func bullet(_ s: String) -> String? {
        for mark in ["- ", "* ", "+ "] where s.hasPrefix(mark) { return String(s.dropFirst(2)) }
        return nil
    }

    /// `**bold**`, `*italic*`, `` `code` ``, and `[text](url)`. A marker that doesn't close stays as typed, so a stray
    /// `*` in a sentence or a formula is left alone.
    public func inline(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        func closing(_ mark: String, from start: String.Index) -> Range<String.Index>? {
            guard start < s.endIndex, !s[start].isWhitespace, let r = s.range(of: mark, range: start..<s.endIndex), r.lowerBound > start else { return nil }
            return r
        }
        while i < s.endIndex {
            let rest = s[i...]
            if rest.hasPrefix("`"), let r = s.range(of: "`", range: s.index(after: i)..<s.endIndex) {
                out += style.cyan(String(s[s.index(after: i)..<r.lowerBound]))
                i = r.upperBound
            } else if rest.hasPrefix("**"), let r = closing("**", from: s.index(i, offsetBy: 2)) {
                out += style.bold(String(s[s.index(i, offsetBy: 2)..<r.lowerBound]))
                i = r.upperBound
            } else if rest.hasPrefix("*"), !rest.hasPrefix("**"), let r = closing("*", from: s.index(after: i)) {
                out += style.italic(String(s[s.index(after: i)..<r.lowerBound]))
                i = r.upperBound
            } else if rest.hasPrefix("["), let close = s.range(of: "](", range: i..<s.endIndex),
                      let end = s.range(of: ")", range: close.upperBound..<s.endIndex),
                      !s[s.index(after: i)..<close.lowerBound].contains("[") {
                let text = String(s[s.index(after: i)..<close.lowerBound])
                out += style.blue(text) + style.dim(" (" + s[close.upperBound..<end.lowerBound] + ")")
                i = end.upperBound
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }
}
