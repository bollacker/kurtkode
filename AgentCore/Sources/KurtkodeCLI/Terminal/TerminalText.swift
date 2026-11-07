import Foundation

/// How text takes up a terminal's cells, escape sequences aside.
public enum TerminalText {
    public static func width(of c: Character) -> Int {
        // A sequence (a flag, a family, a keycap) is drawn as one wide glyph; a combining mark adds nothing.
        guard let first = c.unicodeScalars.first else { return 0 }
        if c.unicodeScalars.count > 1, c.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) { return 2 }
        // Not wcwidth: in the C locale a program starts in, it knows no character past ASCII.
        switch first.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .control, .format: return 0
        default: break
        }
        return first.properties.isEmojiPresentation || wide.contains { $0.contains(first.value) } ? 2 : 1
    }

    /// East Asian wide and fullwidth blocks, and the emoji planes.
    private static let wide: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F,
        0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1FAFF, 0x20000...0x3FFFD,
    ]

    /// Calls `body` with each stretch: an escape sequence (`isEscape`), or a character.
    private static func scan(_ s: String, _ body: (Substring, Bool) -> Bool) {
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", let end = sequenceEnd(s, from: i) {
                guard body(s[i..<end], true) else { return }
                i = end
            } else {
                let next = s.index(after: i)
                guard body(s[i..<next], false) else { return }
                i = next
            }
        }
    }

    private static func sequenceEnd(_ s: String, from i: String.Index) -> String.Index? {
        let n = s.index(after: i)
        guard n < s.endIndex, s[n] == "[" else { return nil }
        var j = s.index(after: n)
        while j < s.endIndex {
            if s[j].isLetter { return s.index(after: j) }
            j = s.index(after: j)
        }
        return nil
    }

    public static func width(_ s: String) -> Int {
        var w = 0
        scan(s) { part, escape in
            if !escape, let c = part.first { w += width(of: c) }
            return true
        }
        return w
    }

    /// `s` cut to `limit` cells, styles reset if any were open, with an ellipsis where it was cut.
    public static func truncate(_ s: String, to limit: Int) -> String {
        guard width(s) > limit else { return s }
        guard limit > 1 else { return "" }
        var out = "", used = 0, styled = false
        scan(s) { part, escape in
            if escape {
                out += part
                styled = true
                return true
            }
            let w = part.first.map { width(of: $0) } ?? 0
            guard used + w < limit else { return false }
            out += part
            used += w
            return true
        }
        return out + "…" + (styled ? "\u{1B}[0m" : "")
    }

    // MARK: Text from outside

    /// The styles this program writes. Text from outside reaches `safe` with these allowed: none of them can hide text.
    private static let ownStyles: Set<String> = ["", "0", "1", "2", "3", "7", "31", "32", "33", "34", "36"]

    private static func isBidiControl(_ v: UInt32) -> Bool {
        (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) || v == 0x200E || v == 0x200F || v == 0x061C
    }

    /// Past the escape sequence that starts at `i`. One that's never closed ends at its opener, so what follows it is
    /// shown rather than swallowed.
    private static func sequenceEnd(_ u: [Unicode.Scalar], from i: Int) -> Int {
        var j = i + 1
        var kind = u[i].value
        if kind == 0x1B {
            guard j < u.count else { return j }
            kind = u[j].value + 0x40
            j += 1
        }
        switch kind {
        case 0x9B:
            while j < u.count, (0x20...0x3F).contains(u[j].value) { j += 1 }
            return j < u.count && (0x40...0x7E).contains(u[j].value) ? j + 1 : j
        case 0x90, 0x98, 0x9D, 0x9E, 0x9F:
            var k = j
            while k < u.count {
                if u[k].value == 0x07 || u[k].value == 0x9C { return k + 1 }
                if u[k].value == 0x1B, k + 1 < u.count, u[k + 1] == "\\" { return k + 2 }
                k += 1
            }
            return j
        default:
            j = i + 1
            while j < u.count, (0x20...0x2F).contains(u[j].value) { j += 1 }
            return j < u.count && (0x30...0x7E).contains(u[j].value) ? j + 1 : j
        }
    }

    private static func strip(_ s: String, keepingStyles: Bool) -> String {
        let u = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView(), i = 0
        while i < u.count {
            let c = u[i], v = c.value
            switch v {
            case 0x1B, 0x90, 0x98, 0x9B, 0x9D, 0x9E, 0x9F:
                let end = sequenceEnd(u, from: i)
                if keepingStyles, v == 0x1B, end > i + 2, u[i + 1] == "[", u[end - 1] == "m",
                   ownStyles.contains(String(String.UnicodeScalarView(u[(i + 2)..<(end - 1)]))) {
                    out.append(contentsOf: u[i..<end])
                }
                i = end
                continue
            case 0x0A: out.append(c)
            case 0x09: out.append(contentsOf: "    ".unicodeScalars)
            case 0x0D: if i + 1 == u.count || u[i + 1] != "\n" { out.append("\n") }
            case 0x07: if keepingStyles { out.append(c) }
            case 0..<0x20, 0x7F...0x9F: break
            default: if !isBidiControl(v) { out.append(c) }
            }
            i += 1
        }
        return String(out)
    }

    /// Text from outside (a reply, a command's output, a file's name) with everything a terminal would act on taken out:
    /// escape sequences, control characters, what reorders the text. Otherwise a reply could clear the screen, set the
    /// clipboard, or draw over an approval card.
    public static func plain(_ s: String) -> String { strip(s, keepingStyles: false) }

    /// The last check on what's about to be written, which is a mix of this program's styles and text from outside.
    public static func safe(_ s: String) -> String { strip(s, keepingStyles: true) }

    /// Text the user is deciding on (a command, a path, a diff): `plain` would hide what it takes out, and that part still
    /// runs, so here each control character shows as a symbol, one for one.
    public static func visible(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            switch c.value {
            case 0x0A: out.append(c)
            case 0..<0x20: out.append(Unicode.Scalar(0x2400 + c.value)!)
            case 0x7F: out.append("\u{2421}")
            case 0x80...0x9F: out.append("\u{FFFD}")
            case let v where isBidiControl(v): out.append("\u{FFFD}")
            default: out.append(c)
            }
        }
        return String(out)
    }

    /// One character of what's being typed, as `visible` shows it: the caret counts characters, so it stays one.
    static func visible(_ c: Character) -> Character {
        if c.isNewline { return c }
        let shown = visible(String(c))
        return shown.count == 1 ? shown.first! : "\u{FFFD}"
    }

    /// `plain`, on one row.
    public static func oneLine(_ s: String) -> String { plain(s).replacingOccurrences(of: "\n", with: " ") }

    /// Plain text (no escapes) broken into rows of at most `width` cells; a newline always breaks. For each character
    /// index of the text, where it lands: (row, column). The extra last entry is the end of the text.
    public static func layout(_ text: [Character], width limit: Int) -> (rows: [String], positions: [(row: Int, column: Int)]) {
        var rows = [""], positions: [(row: Int, column: Int)] = [], row = 0, column = 0
        for c in text {
            if c.isNewline {
                positions.append((row, column))
                rows.append("")
                row += 1
                column = 0
                continue
            }
            let w = width(of: c)
            if column + w > limit {
                rows.append("")
                row += 1
                column = 0
            }
            positions.append((row, column))
            rows[row].append(c)
            column += w
        }
        positions.append((row, column))
        return (rows, positions)
    }
}

/// Styles, off when the output isn't a color terminal.
public struct TerminalStyle: Sendable {
    public var on: Bool
    public init(on: Bool) { self.on = on }

    func wrap(_ code: String, _ s: String) -> String { on ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
    public func bold(_ s: String) -> String { wrap("1", s) }
    public func dim(_ s: String) -> String { wrap("2", s) }
    public func italic(_ s: String) -> String { wrap("3", s) }
    public func red(_ s: String) -> String { wrap("31", s) }
    public func green(_ s: String) -> String { wrap("32", s) }
    public func yellow(_ s: String) -> String { wrap("33", s) }
    public func blue(_ s: String) -> String { wrap("34", s) }
    public func cyan(_ s: String) -> String { wrap("36", s) }
    public func inverse(_ s: String) -> String { wrap("7", s) }
}

/// A unified diff as colored lines, cut to `limit`.
public enum DiffPreview {
    public static func lines(_ unified: String, limit: Int, style: TerminalStyle) -> [String] {
        var all = unified.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if all.last == "" { all.removeLast() }
        // The file names are in the line above it.
        all.removeAll { $0.hasPrefix("--- ") || $0.hasPrefix("+++ ") }
        var out = all.prefix(limit).map { line -> String in
            if line.hasPrefix("+") { return style.green(line) }
            if line.hasPrefix("-") { return style.red(line) }
            if line.hasPrefix("@@") { return style.cyan(line) }
            return line
        }
        if all.count > limit { out.append(style.dim("… \(all.count - limit) more lines")) }
        return out
    }
}
