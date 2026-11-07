import AppKit
import JavaScriptCore
import SwiftUI

/// Syntax colors for code blocks, computed off the main thread. Textual highlights a code block on every
/// change (20 times a second while a reply streams) and starts its JavaScript engine on the main thread;
/// measured, that kept the main thread busy and froze the app for about a second when a chat with code opened.
/// This uses the same Prism bundle (shipped in Textual's resource bundle) in its own JavaScriptCore context,
/// on its own actor, and caches the result per block.
actor CodeHighlighter {
    static let shared = CodeHighlighter()

    private var context: JSContext?
    private var loaded = false

    /// Loads Prism now, so the first highlight doesn't wait for it. Safe to call more than once.
    func warmUp() { _ = tokenizer() }

    private func tokenizer() -> JSValue? {
        if !loaded {
            loaded = true
            if let url = Bundle.main.resourceURL?.appending(path: "textual_Textual.bundle/Contents/Resources/prism-bundle.js"),
               let script = try? String(contentsOf: url, encoding: .utf8), let ctx = JSContext() {
                ctx.evaluateScript(script)
                context = ctx
            }
        }
        return context?.objectForKeyedSubscript("tokenizeCode")
    }

    /// The code with colors, or nil when the language isn't known (then it stays plain).
    func highlight(_ code: String, language: String) -> AttributedString? {
        let key = HighlightCache.key(code, language)
        if let hit = HighlightCache.shared[key] { return hit }
        guard let fn = tokenizer(), let result = fn.call(withArguments: [code, language]),
              let tokens = result.toArray() as? [[String: String]] else { return nil }
        var out = AttributedString()
        var colored = false
        for t in tokens {
            guard let text = t["content"] else { continue }
            var piece = AttributedString(text)
            if let color = Self.color(t["type"] ?? "plain") {
                piece.foregroundColor = color
                colored = true
            }
            out.append(piece)
        }
        guard colored else { return nil }
        HighlightCache.shared[key] = out
        return out
    }

    /// An Xcode-like palette from system colors, so it follows light and dark mode.
    static func color(_ type: String) -> Color? {
        switch type {
        case "keyword", "boolean", "important", "atrule": Color(nsColor: .systemPink)
        case "string", "char", "triple-quoted-string", "template-string", "regex", "attr-value", "url": Color(nsColor: .systemRed)
        case "comment", "prolog", "doctype", "cdata", "shebang": Color(nsColor: .secondaryLabelColor)
        case "number", "constant", "symbol": Color(nsColor: .systemPurple)
        case "function", "function-definition", "method": Color(nsColor: .systemTeal)
        case "class-name", "builtin", "type", "namespace", "tag", "selector": Color(nsColor: .systemIndigo)
        case "variable", "parameter", "environment", "property", "attr-name", "decorator", "annotation": Color(nsColor: .systemBlue)
        default: nil
        }
    }
}

/// Highlighted blocks by content, readable from the main thread without waiting, so a block that was
/// highlighted before shows its colors at once (no plain-then-colored flash on scroll or re-render).
final class HighlightCache: @unchecked Sendable {
    static let shared = HighlightCache()
    private let lock = NSLock()
    private var items: [String: AttributedString] = [:]
    private var order: [String] = []

    static func key(_ code: String, _ language: String) -> String { language + "\u{0}" + code }

    subscript(key: String) -> AttributedString? {
        get { lock.withLock { items[key] } }
        set {
            lock.withLock {
                if items[key] == nil { order.append(key) }
                items[key] = newValue
                while order.count > 300 { items[order.removeFirst()] = nil }
            }
        }
    }
}

/// A fenced code block: plain text while it streams (cheap to lay out 20 times a second), colored once done.
struct CodeBlockView: View {
    let code: String
    let language: String?
    var live = false
    @State private var highlighted: AttributedString?

    private var cached: AttributedString? {
        guard !live, let language else { return nil }
        return highlighted ?? HighlightCache.shared[HighlightCache.key(code, language)]
    }

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                CodeCopyButton(code: code)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if let cached { Text(cached) } else { Text(verbatim: code) }
                }
                .font(.system(size: NSFont.systemFontSize * 0.9, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
            }
        }
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .task(id: live ? nil : code) {
            guard !live, let language, cached == nil else { return }
            let code = code
            highlighted = await CodeHighlighter.shared.highlight(code, language: language)
        }
    }
}

struct CodeCopyButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
    }
}
