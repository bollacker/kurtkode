import Foundation

/// A key press, or a bracketed paste, as the terminal sends it.
public enum Key: Equatable, Sendable {
    case text(String)
    case paste(String)
    case enter
    /// A newline in the text: Ctrl-J, Alt-Enter, or Shift-Enter where the terminal tells it apart.
    case newline
    case backspace, delete, tab, shiftTab, esc
    case up, down, left, right, home, end, wordLeft, wordRight
    case ctrl(Character)
}

/// Turns the bytes a terminal sends in raw mode into keys. A lone Esc looks like the start of a sequence, so it's held
/// until `flush` (the reader calls it when no more bytes follow at once).
public struct KeyDecoder: Sendable {
    private var pending: [UInt8] = []
    private var paste: [UInt8]?

    private static let pasteEnd: [UInt8] = Array("\u{1B}[201~".utf8)

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [Key] {
        pending += bytes
        var out: [Key] = []
        func add(_ key: Key) {
            if case .text(let s) = key, case .text(let before)? = out.last { out[out.count - 1] = .text(before + s) } else { out.append(key) }
        }
        while !pending.isEmpty {
            if paste != nil {
                guard takePaste(&out) else { break }
                continue
            }
            let b = pending[0]
            if b == 0x1B {
                guard let (key, used) = escape() else { break }
                pending.removeFirst(used)
                if let key { add(key) }
                continue
            }
            if b < 0x80 {
                pending.removeFirst()
                switch b {
                case 0x0D: add(.enter)
                case 0x0A: add(.newline)
                case 0x09: add(.tab)
                case 0x7F, 0x08: add(.backspace)
                case 0x00..<0x20: add(.ctrl(Character(UnicodeScalar(b + 0x60))))
                default: add(.text(String(UnicodeScalar(b))))
                }
                continue
            }
            // UTF-8: wait for the rest of a character cut between reads.
            let length = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
            guard pending.count >= length else { break }
            add(.text(String(decoding: pending[..<length], as: UTF8.self)))
            pending.removeFirst(length)
        }
        return out
    }

    /// No byte followed: what's held was a lone Esc.
    public mutating func flush() -> [Key] {
        guard paste == nil, pending == [0x1B] else { return [] }
        pending = []
        return [.esc]
    }

    private mutating func takePaste(_ out: inout [Key]) -> Bool {
        guard let i = pending.firstRange(of: Self.pasteEnd)?.lowerBound else { return false }
        let text = String(decoding: (paste ?? []) + pending[..<i], as: UTF8.self)
        pending.removeFirst(i + Self.pasteEnd.count)
        paste = nil
        out.append(.paste(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")))
        return true
    }

    /// The sequence at the start of `pending`, with its length; nil while it's incomplete.
    private mutating func escape() -> (Key?, Int)? {
        guard pending.count >= 2 else { return nil }
        switch pending[1] {
        case UInt8(ascii: "["):
            guard let end = pending[2...].firstIndex(where: { (0x40...0x7E).contains($0) }) else { return nil }
            let params = String(decoding: pending[2..<end], as: UTF8.self)
            let final = Character(UnicodeScalar(pending[end]))
            if params == "200", final == "~" {
                pending.removeFirst(end + 1)
                paste = []
                return (nil, 0)
            }
            return (Self.csi(params, final), end + 1)
        case UInt8(ascii: "O"):
            guard pending.count >= 3 else { return nil }
            return (Self.csi("", Character(UnicodeScalar(pending[2]))), 3)
        case 0x0D: return (.newline, 2)
        case 0x7F: return (.ctrl("w"), 2)
        case UInt8(ascii: "b"): return (.wordLeft, 2)
        case UInt8(ascii: "f"): return (.wordRight, 2)
        // Alt and a key that means nothing here: not Esc, which stops a run or refuses an approval.
        case 0x20...0x7E: return (nil, 2)
        default: return (.esc, 1)
        }
    }

    private static func csi(_ params: String, _ final: Character) -> Key? {
        let parts = params.split(separator: ";").map { Int($0) ?? 0 }
        let modified = parts.count > 1 && [3, 5].contains(parts[1])          // Alt or Ctrl
        switch final {
        case "A": return .up
        case "B": return .down
        case "C": return modified ? .wordRight : .right
        case "D": return modified ? .wordLeft : .left
        case "H": return .home
        case "F": return .end
        case "Z": return .shiftTab
        case "u": return parts.first == 13 ? .newline : nil                  // the kitty protocol's Shift-Enter
        case "~":
            switch parts.first {
            case 1, 7: return .home
            case 4, 8: return .end
            case 3: return .delete
            case 27: return parts.last == 13 ? .newline : nil                // xterm's modifyOtherKeys Shift-Enter
            default: return nil
            }
        default: return nil
        }
    }
}
