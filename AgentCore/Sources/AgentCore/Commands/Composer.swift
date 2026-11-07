import Foundation

/// A long paste, kept beside the composer while a short token stands in for it in the draft. The model gets the text.
public struct PastedText: Sendable, Hashable, Identifiable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }

    /// A paste becomes a token past either of these; a few lines of code stay readable where they were typed.
    public static let minCharacters = 800
    public static let minLines = 12

    public static func isLong(_ text: String) -> Bool {
        text.count >= minCharacters || text.reduce(1) { $0 + ($1.isNewline ? 1 : 0) } >= minLines
    }

    public var lineCount: Int {
        var trimmed = Substring(text)
        while trimmed.last?.isNewline == true { trimmed.removeLast() }
        return trimmed.reduce(1) { $0 + ($1.isNewline ? 1 : 0) }
    }

    public var token: String { "[Pasted text #\(id): \(lineCount) line\(lineCount == 1 ? "" : "s")]" }

    /// `draft` with each paste's token replaced by its text. Text that only looks like a token stays as typed.
    public static func expand(_ draft: String, _ pastes: [PastedText]) -> String {
        pastes.reduce(draft) { $0.replacingOccurrences(of: $1.token, with: $1.text) }
    }

    /// Goes before a message that starts with a paste. The user sees a token there, so what the paste starts with can't
    /// make it a `!command`, a `/command` or a `# note`: none of those recognize text that starts with this.
    public static let messageMark = "\u{2060}"

    /// What to send for `draft`: its pastes in place, and marked if it starts with one.
    public static func text(of draft: String, _ pastes: [PastedText]) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = expand(trimmed, pastes).trimmingCharacters(in: .whitespacesAndNewlines)
        return pastes.contains { trimmed.hasPrefix($0.token) } ? messageMark + text : text
    }

    /// The message itself, for the model.
    public static func withoutMark(_ text: String) -> String { text.hasPrefix(messageMark) ? String(text.dropFirst()) : text }
}

/// What was queued, and what's being typed, back in one draft. A command in front would take everything after it as its
/// own text (`!npm test` and a sentence would run as one script), so a draft of several things then starts with words.
public func joinedDraft(_ parts: [String]) -> String {
    let parts = parts.filter { !$0.isEmpty }
    guard parts.count > 1, let first = parts.first, SlashCommands.parse(first) != nil || UserShell.command(in: first) != nil else {
        return parts.joined(separator: "\n\n")
    }
    return "Queued:\n\n" + parts.joined(separator: "\n\n")
}

/// ↑ and ↓ in the composer: older and newer prompts, like a shell. What was being typed comes back past the newest.
public struct PromptRecall: Sendable, Equatable {
    /// Oldest first.
    public let entries: [String]
    private var index: Int?
    private var typed = ""

    public init(entries: [String]) { self.entries = entries }

    /// On a prompt, not back at what was being typed: past that the list is out of date, and a new one is made.
    public var isWalking: Bool { index != nil }

    /// What was being typed, while a prompt has its place: it comes back if that prompt is sent.
    public var waiting: String { index == nil ? "" : typed }

    /// The next older prompt; nil when there's none (the draft stays as it is).
    public mutating func older(draft: String) -> String? {
        guard !entries.isEmpty else { return nil }
        if index == nil { typed = draft }
        let next = (index ?? entries.count) - 1
        guard next >= 0 else { return nil }
        index = next
        return entries[next]
    }

    /// The next newer prompt, then what was being typed; nil when already there.
    public mutating func newer() -> String? {
        guard let i = index else { return nil }
        if i + 1 < entries.count {
            index = i + 1
            return entries[i + 1]
        }
        index = nil
        return typed
    }
}

extension SlashCommands {
    /// Commands that only show something: they answer at once, even during a run. Others wait for the run's end.
    public static let answersWhileRunning: Set<String> = ["help", "context", "agents", "skills", "memory", "btw"]
}
