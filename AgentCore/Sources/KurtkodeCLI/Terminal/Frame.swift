import Foundation

/// What the session looks like, for the status line.
public struct StatusInfo: Sendable, Equatable {
    public var model = ""
    public var mode = ""
    /// A mode change that takes effect after the run.
    public var nextMode: String?
    public var contextUsed: Int?
    public var contextLimit: Int?
    public var spent: Double?
    public var spentIsEstimate = false
    public var steps = 0
    public var runStarted: Date?
    /// What the agent is doing, with when it started.
    public var activity: String?
    public var activitySince: Date?

    public init() {}

    static let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s / 3600)h \(String(format: "%02d", s / 60 % 60))m"
    }

    /// The run's line: what it's doing now and for how long.
    func runLine(now: Date, style: TerminalStyle) -> String? {
        guard let start = runStarted else { return nil }
        let frame = Self.spinner[Int(now.timeIntervalSinceReferenceDate * 10) % Self.spinner.count]
        var parts: [String] = []
        if let activity {
            var s = TerminalText.oneLine(activity)
            if let since = activitySince, now.timeIntervalSince(since) >= 2 { s += " " + Self.clock(now.timeIntervalSince(since)) }
            parts.append(s)
        } else {
            parts.append("Working")
        }
        parts.append(Self.clock(now.timeIntervalSince(start)))
        if steps > 0 { parts.append("step \(steps)") }
        return style.cyan(frame) + " " + parts[0] + style.dim(" · " + parts.dropFirst().joined(separator: " · ") + " · esc to stop")
    }

    /// The line that's always there.
    func line(style: TerminalStyle) -> String {
        let model = TerminalText.oneLine(model)
        var parts = [model.split(separator: "/").last.map(String.init) ?? model, mode + (nextMode.map { " → \($0) next" } ?? "")]
        if let used = contextUsed, let limit = contextLimit, limit > 0 { parts.append("ctx \(used * 100 / limit)%") }
        if let spent { parts.append((spentIsEstimate ? "≈" : "") + String(format: spent < 1 ? "$%.3f" : "$%.2f", spent)) }
        return style.dim(parts.joined(separator: " · ") + " · shift+tab mode · ctrl+o output · /help")
    }
}

/// The rows at the bottom of the terminal, and where the caret goes in them.
public struct Frame: Equatable, Sendable {
    public var rows: [String]
    public var caretRow: Int
    public var caretColumn: Int

    public init(rows: [String], caretRow: Int, caretColumn: Int) {
        self.rows = rows
        self.caretRow = caretRow
        self.caretColumn = caretColumn
    }

    /// Lays out what's above and in the composer for a terminal of this size. The composer keeps its rows around the
    /// caret; everything else gives way first, since a frame taller than the screen can't be redrawn in place.
    public static func make(input: InputState, status: StatusInfo, live: String, tail: [String], width: Int, height: Int,
                            now: Date = Date(), style: TerminalStyle) -> Frame {
        let cells = max(10, width - 1)                  // the last column: a full row would wrap at the next write
        var above: [String] = []
        if !live.isEmpty {
            above += TerminalText.layout(Array(TerminalText.plain(live)), width: cells).rows.suffix(4)
        }
        above += tail.suffix(4).map { TerminalText.truncate(style.dim("  " + TerminalText.oneLine($0)), to: cells) }
        if input.question != nil {
            above.append(style.yellow("⏸ waiting for your answer"))
        } else if let run = status.runLine(now: now, style: style) {
            above.append(TerminalText.truncate(run, to: cells))
        }
        if !input.queued.isEmpty {
            for q in input.queued.suffix(3) {
                let first = q.split(whereSeparator: \.isNewline).first.map(String.init) ?? q
                let mark = InputState.isCommand(q) ? "⏵ " : "◦ "
                above.append(TerminalText.truncate(style.dim(mark + TerminalText.visible(first)), to: cells))
            }
            above.append(style.dim(TerminalText.truncate("  queued: messages go in at the next step, commands when it's done; ↑ takes one back", to: cells)))
        }

        var promptText = TerminalText.plain(input.question ?? "› ")
        if let search = input.search {
            promptText = TerminalText.visible("search: \(search)" + (input.searchMatch.map { " → " + ($0.split(whereSeparator: \.isNewline).first.map(String.init) ?? $0) } ?? "") + " ")
        }
        // A long question takes the rows above, keeping the one the answer starts on.
        let promptRows = TerminalText.layout(Array(promptText), width: cells).rows
        above += promptRows.dropLast()
        promptText = promptRows.last ?? ""
        let prompt = Array(promptText)
        let indent = TerminalText.width(promptText)
        let text = input.search == nil ? input.buffer.characters.map(TerminalText.visible) : []
        let caret = input.search == nil ? input.buffer.caret : 0
        let room = max(4, cells - indent)
        let (textRows, positions) = TerminalText.layout(text, width: room)
        var composer = textRows.enumerated().map { i, row in
            (i == 0 ? String(prompt) : String(repeating: " ", count: indent)) + row
        }
        var caretRow = positions[caret].row
        let caretColumn = indent + positions[caret].column

        var below: [String] = []
        if !input.images.isEmpty {
            below.append(style.dim("  " + input.images.indices.map { "[Image #\($0 + 1)]" }.joined(separator: " ")))
        }
        let held = input.pastes.filter { input.buffer.string.contains($0.token) }
        if !held.isEmpty { below.append(style.dim("  " + held.map { "\($0.lineCount) lines pasted" }.joined(separator: ", ") + "; sent in full")) }
        if let list = input.choices { below += choiceRows(list, cells: cells, style: style) }
        let shown = input.completions.prefix(6)
        for (i, c) in shown.enumerated() {
            let row = TerminalText.truncate(TerminalText.oneLine("  " + c.text + (c.detail.isEmpty ? "" : "  " + c.detail)), to: cells)
            below.append(i == min(input.selected, shown.count - 1) ? style.inverse(row) : style.dim(row))
        }
        below.append(TerminalText.truncate(status.line(style: style), to: cells))

        // Each part gives up rows until it fits: what's above first, then the text away from the caret.
        let limit = max(3, height - 1)
        while above.count + composer.count + below.count > limit, !above.isEmpty { above.removeFirst() }
        while above.count + composer.count + below.count > limit, below.count > 1 { below.removeFirst() }
        while above.count + composer.count + below.count > limit, composer.count > 1 {
            if caretRow > composer.count / 2 {
                composer.removeFirst()
                caretRow -= 1
            } else {
                composer.removeLast()
            }
        }
        return Frame(rows: above + composer + below, caretRow: above.count + caretRow, caretColumn: caretColumn)
    }

    /// A question's options, the one the list is on picked out, with its description in full if its row cuts that off.
    private static func choiceRows(_ list: QuestionChoices, cells: Int, style: TerminalStyle) -> [String] {
        var rows: [String] = []
        var cutOff = false
        for (i, option) in list.options.enumerated() {
            var row = "  \(i + 1). " + (list.multiple ? (list.picked.contains(i) ? "[x] " : "[ ] ") + TerminalText.oneLine(option.label) : TerminalText.oneLine(option.label))
            if i == list.recommended { row += " (recommended)" }
            if !option.description.isEmpty { row += "  " + TerminalText.oneLine(option.description) }
            if i == list.selected { cutOff = TerminalText.width(row) > cells }
            let fitted = TerminalText.truncate(row, to: cells)
            rows.append(i == list.selected ? style.inverse(fitted) : style.dim(fitted))
        }
        if cutOff {
            rows += TerminalText.layout(Array(TerminalText.oneLine(list.options[list.selected].description)), width: max(10, cells - 5)).rows.prefix(3)
                .map { style.dim("     " + $0) }
        }
        let keys = "↑↓ move" + (list.multiple ? " · space select" : "") + " · enter answer · esc skip · or type your own answer"
        rows.append(TerminalText.truncate(style.dim("  " + keys), to: cells))
        return rows
    }
}

/// Draws a frame in place below the output. What's committed goes above it and on into the terminal's own scrollback:
/// no alternate screen and no scroll region, so copying, searching and scrolling work as in any terminal.
public struct LiveScreen: Sendable {
    private var caretRow = 0
    private var drawn = false

    public init() {}

    /// The escape sequences for one update: `commit` (whole lines) above, then the new frame.
    public mutating func update(commit: String, frame: Frame) -> String {
        var s = "\u{1B}[?2026h"                                     // the terminal shows it all at once, where it can
        s += erase()
        if !commit.isEmpty { s += commit.hasSuffix("\n") ? commit : commit + "\n" }
        s += frame.rows.joined(separator: "\n")
        let up = frame.rows.count - 1 - frame.caretRow
        if up > 0 { s += "\u{1B}[\(up)A" }
        s += "\r"
        if frame.caretColumn > 0 { s += "\u{1B}[\(frame.caretColumn)C" }
        s += "\u{1B}[?2026l"
        caretRow = frame.caretRow
        drawn = true
        return s
    }

    /// Takes the frame away, leaving the caret where it started (before running something else in the terminal).
    public mutating func clear() -> String {
        defer { drawn = false }
        return erase()
    }

    private mutating func erase() -> String {
        guard drawn else { return "" }
        return (caretRow > 0 ? "\u{1B}[\(caretRow)A" : "") + "\r\u{1B}[J"
    }
}
