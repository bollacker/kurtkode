import AgentCore
import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Where the window's typing goes, for the cards' shortcuts and the composer's Escape (`CardKeys`).
    @Entry var textFocus: CardKeys.Focus = .none
}

extension CardKeys {
    /// What pressed the button whose action is running.
    @MainActor static var currentInput: Input {
        guard let event = NSApp.currentEvent else { return .other }
        switch event.type {
        case .keyDown: return .key(isRepeat: event.isARepeat)
        case .leftMouseDown, .leftMouseUp: return .mouse(clickCount: event.clickCount)
        default: return .other
        }
    }

    /// Whether the press running a card's yes-button counts, for a card on screen since `appearedAt`.
    @MainActor static func pressCounts(since appearedAt: Date) -> Bool {
        accepts(currentInput, appearedAt: appearedAt, now: Date())
    }

    /// `shortcut` while it's in force for a card, else none, so the key goes on to the field being typed in.
    static func shortcut(_ key: Key, _ shortcut: KeyboardShortcut, focus: Focus, inCard: Bool) -> KeyboardShortcut? {
        shortcutActive(key, focus: focus, inCard: inCard) ? shortcut : nil
    }
}

/// Reports where the window's typing goes whenever its first responder changes (NSWindow's `firstResponder` is KVO
/// compliant): the composer, another editable text (a TextField's field editor), or neither.
struct FirstResponderReader: NSViewRepresentable {
    let report: (CardKeys.Focus) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.report = report
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) { view.report = report }

    final class ReaderView: NSView {
        var report: ((CardKeys.Focus) -> Void)?
        private var observation: NSKeyValueObservation?
        private var last: CardKeys.Focus?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
                MainActor.assumeIsolated {
                    let focus = Self.focus(of: window.firstResponder)
                    // Not in the middle of the responder change, which can happen during a view update.
                    DispatchQueue.main.async { self?.publish(focus) }
                }
            }
        }

        private func publish(_ focus: CardKeys.Focus) {
            guard focus != last else { return }
            last = focus
            report?(focus)
        }

        static func focus(of responder: NSResponder?) -> CardKeys.Focus {
            if responder is SubmittingTextView { return .composer }
            if let text = responder as? NSText, text.isEditable { return .otherField }
            return .none
        }
    }
}
