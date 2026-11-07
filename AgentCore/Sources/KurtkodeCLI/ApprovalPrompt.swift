import AgentCore
import Darwin
import Foundation

/// Reading the answer at an approval card. An empty answer never approves: Enter pressed while a reply streamed is
/// buffered and would otherwise answer the next card, and in `--plain` or with piped input there is no settle delay
/// to absorb it. An empty line asks again, the end of input or a cancelled run denies.
public enum ApprovalPrompt {
    /// The prompt shown again after an empty answer.
    public static let again = "  y or n › "

    /// Reads answers through `read` (its prompt and the card to show first; nil at the end of input) until one isn't
    /// empty, then decides. `cancelled` is checked after each read (Ctrl-C ends a read with an empty line).
    public static func decide(card: String, suggestedRule: AllowRule?,
                              cancelled: @Sendable () -> Bool = { Task.isCancelled },
                              read: @Sendable (_ prompt: String, _ card: String) async -> String?) async -> ApprovalDecision {
        var typed = await read("  › ", card)
        while typed?.trimmingCharacters(in: .whitespaces).isEmpty == true, !cancelled() {
            typed = await read(again, "")
        }
        guard !cancelled(), let typed else { return .deny(feedback: nil) }
        return decision(typed, suggestedRule: suggestedRule)
    }

    /// The decision for one answer that isn't empty. Anything but a known word is taken as what to do instead.
    public static func decision(_ typed: String, suggestedRule: AllowRule?) -> ApprovalDecision {
        let answer = typed.trimmingCharacters(in: .whitespaces)
        switch answer.lowercased() {
        case "": return .deny(feedback: nil)
        case "y", "yes": return .allow
        case "n", "no": return .deny(feedback: nil)
        case "a", "always": return suggestedRule.map { .allowAlways($0) } ?? .allow
        default: return .deny(feedback: answer)
        }
    }

    /// Drops whatever was typed at the terminal and not yet read, so a line typed ahead for the next message (or an
    /// Enter pressed during the reply) doesn't answer a card the user hasn't seen. Only for a terminal: piped answers
    /// are meant. Returns whether it flushed.
    @discardableResult
    public static func flushTypedAhead(fd: Int32 = STDIN_FILENO) -> Bool {
        guard isatty(fd) == 1 else { return false }
        return tcflush(fd, TCIFLUSH) == 0
    }
}
