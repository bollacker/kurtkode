import AgentCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Multi-line input: Return sends, Shift-Return (or Option-Return) inserts a newline, and the view grows
/// with its text. An NSTextView, because SwiftUI's TextEditor can't reliably tell the two apart.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    /// Arrow keys, Tab, Escape, and Return go here first; true means handled (the command list uses them). The flag
    /// says ↑ or ↓ would leave the text: the caret is on its first or last line.
    var onKey: (ComposerKey, Bool) -> Bool = { _, _ in false }
    /// Images pasted into the composer (image data, or image files copied in Finder).
    var onPasteImages: ([Data]) -> Void = { _ in }
    /// A long text pasted into the composer: gives what to put in its place.
    var onPasteLongText: (String) -> String = { $0 }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = SubmittingTextView()
        tv.delegate = context.coordinator
        tv.onSubmit = { context.coordinator.parent.onSubmit() }
        tv.onKey = { context.coordinator.parent.onKey($0, $1) }
        tv.onPasteImages = { context.coordinator.parent.onPasteImages($0) }
        tv.onPasteLongText = { context.coordinator.parent.onPasteLongText($0) }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.placeholder = placeholder
        scroll.documentView = tv
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        #if DEBUG
        // KURTKODE_PASTE_FILE=path: paste this file's text into the composer, as ⌘V does, from a private pasteboard.
        if let path = ProcessInfo.processInfo.environment["KURTKODE_PASTE_FILE"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let pb = NSPasteboard(name: NSPasteboard.Name("kurtkode.test"))
                pb.clearContents()
                pb.setString(text, forType: .string)
                tv.pasteboard = pb
                tv.paste(nil)
                tv.pasteboard = .general
            }
        }
        // KURTKODE_KEYS=path: play a script of keys at the composer, for what accessibility can't press. One step a line:
        // wait SECONDS | text TEXT | clear | key esc|return|up|down | shortcut esc | dump (appends the draft to path.out).
        if let path = ProcessInfo.processInfo.environment["KURTKODE_KEYS"], let script = try? String(contentsOfFile: path, encoding: .utf8) {
            Task { @MainActor in await KeyScript.play(script, in: tv, out: path + ".out") }
        }
        #endif
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            tv.string = text
            // Filled in from outside (a recalled prompt, a completion): typing goes on at its end.
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            tv.invalidateIntrinsicContentSize()
        }
        tv.placeholder = placeholder
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let tv = context.coordinator.textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        lm.ensureLayout(for: tc)
        let height = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        return CGSize(width: proposal.width ?? 400, height: min(max(height, 30), 200))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: SubmittingTextView?

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            tv.invalidateIntrinsicContentSize()
            tv.enclosingScrollView?.invalidateIntrinsicContentSize()
        }
    }
}

enum ComposerKey { case up, down, tab, escape, submit }

final class SubmittingTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onKey: ((ComposerKey, Bool) -> Bool)?
    var onPasteImages: (([Data]) -> Void)?
    var onPasteLongText: ((String) -> String)?
    var placeholder = "" { didSet { needsDisplay = true } }
    /// Where pastes come from: the general pasteboard, but for the Debug hook above.
    var pasteboard = NSPasteboard.general

    /// Image files or image data become attachments; a long text a token (`PastedText`); other text pastes as usual
    /// (text wins when both are there).
    override func paste(_ sender: Any?) {
        let pb = pasteboard
        let files = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        if !files.isEmpty {
            onPasteImages?(files.compactMap { try? Data(contentsOf: $0) })
            return
        }
        if pb.string(forType: .string) == nil, let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onPasteImages?([data])
            return
        }
        if let text = pb.string(forType: .string), PastedText.isLong(text), let token = onPasteLongText?(text) {
            insertText(token, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    /// The caret is on the text's first line (or last, going down), as drawn: a wrapped line counts as several.
    private func caretAtEdge(up: Bool) -> Bool {
        guard selectedRange().length == 0 else { return false }
        guard !string.isEmpty, let lm = layoutManager, let tc = textContainer else { return true }
        lm.ensureLayout(for: tc)
        let glyph = min(lm.glyphIndexForCharacter(at: selectedRange().location), lm.numberOfGlyphs - 1)
        let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let all = lm.usedRect(for: tc)
        return up ? line.minY <= all.minY + 1 : line.maxY >= all.maxY - 1
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76      // Return, keypad Enter
        let newlineModifiers: NSEvent.ModifierFlags = [.shift, .option]
        let plain = event.modifierFlags.intersection([.shift, .option, .command, .control]).isEmpty
        if plain, !hasMarkedText() {
            let key: ComposerKey? = switch event.keyCode {
            case 126: .up
            case 125: .down
            case 48: .tab
            case 53: .escape
            case 36, 76: .submit
            default: nil
            }
            if let key, onKey?(key, caretAtEdge(up: event.keyCode == 126)) == true { return }
        }
        if isReturn, event.modifierFlags.intersection(newlineModifiers).isEmpty, !hasMarkedText() {
            onSubmit?()
            return
        }
        if isReturn {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.placeholderTextColor, .font: font ?? .systemFont(ofSize: 13)]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5),
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }
}

#if DEBUG
@MainActor enum KeyScript {
    static func play(_ script: String, in tv: SubmittingTextView, out: String) async {
        func event(_ code: UInt16, _ characters: String) -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0,
                             context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        }
        let keys: [String: (UInt16, String)] = ["esc": (53, "\u{1B}"), "return": (36, "\r"), "up": (126, "\u{F700}"), "down": (125, "\u{F701}")]
        for line in script.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "wait": try? await Task.sleep(for: .seconds(Double(parts[1]) ?? 1))
            case "text": tv.insertText(parts[1], replacementRange: tv.selectedRange())
            case "clear":
                tv.selectAll(nil)
                tv.insertText("", replacementRange: tv.selectedRange())
            case "key":
                if let (code, characters) = keys[parts[1]], let e = event(code, characters) { tv.keyDown(with: e) }
            case "shortcut":
                if let (code, characters) = keys[parts[1]], let e = event(code, characters) { _ = tv.window?.performKeyEquivalent(with: e) }
            case "dump":
                let text = "[\(tv.string.replacingOccurrences(of: "\n", with: "\\n"))]\n"
                if let h = FileHandle(forWritingAtPath: out) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
                else { FileManager.default.createFile(atPath: out, contents: Data(text.utf8)) }
            default: break
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }
}
#endif
