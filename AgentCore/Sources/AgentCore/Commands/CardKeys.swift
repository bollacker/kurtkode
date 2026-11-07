import Foundation

/// When the keys of a card that asks (an approval, a question, a plan) may act. The app's cards appear one after another
/// in the same spot, and their shortcuts work anywhere in the window, so without these rules a double press or a held ⌘↩
/// answers a card the user never saw, ⌘↩ typed in the composer allows instead of sending, and Escape in the sidebar's
/// search denies the call. Pure, so it can be tested without a window; the app asks it.
public enum CardKeys {
    /// How long a new card ignores what could be the end of the last one's answer (the CLI's live screen waits as long).
    public static let settle: TimeInterval = 0.5

    /// Where the window's typing goes.
    public enum Focus: Sendable, Equatable {
        /// Nowhere that takes text: the transcript, a button, a selection.
        case none
        /// The chat's message box.
        case composer
        /// Some other editable field: the sidebar's search, the find bar, a review comment, a settings field.
        case otherField
    }

    /// A card's keys: the one that answers yes (Allow, Answer, Approve, an option's ⌘1…9), and the one that says no
    /// (Deny, Skip, Reject: Escape).
    public enum Key: Sendable, Equatable { case confirm, dismiss }

    /// What pressed a card's button, as the app's current event tells it.
    public enum Input: Sendable, Equatable {
        case key(isRepeat: Bool)
        case mouse(clickCount: Int)
        /// No event to go by (accessibility, an action run after its event): waits for `settle` like a key press.
        case other
    }

    /// The kinds of card, in the order they're shown when several arrive together.
    public enum Card: Int, Sendable, Comparable, CaseIterable {
        case approval, question, plan
        public static func < (a: Card, b: Card) -> Bool { a.rawValue < b.rawValue }
    }

    /// Whether a card's shortcut is in force. Typing in another field keeps both keys there (Escape clears the search,
    /// ⌘↩ is the field's own); in the composer ⌘↩ sends what's typed, but Escape still says no, as it always has.
    /// `inCard` is focus in one of the card's own fields, where both keys belong to the card.
    public static func shortcutActive(_ key: Key, focus: Focus, inCard: Bool = false) -> Bool {
        if inCard { return true }
        switch focus {
        case .none: return true
        case .composer: return key == .dismiss
        case .otherField: return false
        }
    }

    /// Whether a press of a card's yes-button counts. A held key's repeats never do; a key press, or the second click of
    /// a double click, only once the card has been on screen for `settle` (the first press answered the card before it).
    /// A single click always counts; a press with no event to go by waits like a key press.
    public static func accepts(_ input: Input, appearedAt: Date, now: Date) -> Bool {
        let settled = now.timeIntervalSince(appearedAt) >= settle
        switch input {
        case .key(let isRepeat): return !isRepeat && settled
        case .mouse(let clickCount): return clickCount <= 1 || settled
        case .other: return settled
        }
    }

    /// The hidden Escape-stops-the-run button is in force unless another field is being typed in (its Escape is its own).
    public static func escapeStopsRun(focus: Focus) -> Bool { focus != .otherField }

    /// The one card to show of those waiting: the one already shown while it waits, otherwise the first in `Card` order.
    /// The rest wait their turn, so two cards never share ⌘↩ and Escape, and a card never changes under the pointer.
    public static func shown(current: Card?, waiting: Set<Card>) -> Card? {
        if let current, waiting.contains(current) { return current }
        return waiting.min()
    }
}
