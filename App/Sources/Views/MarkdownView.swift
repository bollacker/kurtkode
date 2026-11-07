import SwiftUI
import Textual

/// Renders assistant Markdown. The only file that imports Textual (D6), so the renderer can be swapped.
///
/// Prose goes through Textual; top-level fenced code blocks are cut out and drawn by `CodeBlockView`, which
/// shows plain text while the reply streams and colors it off the main thread afterwards. (Textual's own code
/// blocks re-highlighted on every streamed update and kept the main thread busy; see PLAN.md, "Freezes".)
struct MarkdownView: View {
    let markdown: String
    /// The reply is still streaming: code stays plain.
    var live = false

    #if DEBUG
    /// KURTKODE_MD=textual (Textual for everything, as before) or plain (no Markdown): for measuring.
    static let mode = ProcessInfo.processInfo.environment["KURTKODE_MD"] ?? ""
    #else
    static let mode = ""
    #endif

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        switch Self.mode {
        case "plain":
            Text(verbatim: markdown).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        case "textual":
            prose(markdown)
        default:
            let segments = MarkdownSegments.split(markdown)
            if segments.count == 1, case .prose(let text) = segments[0] {
                ProseBlock(text: text).equatable()
            } else {
                // Done pieces are equatable: their bodies don't run again. (Replies in the transcript use MarkdownPieces.)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in segmentView(seg) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func prose(_ text: String) -> some View { ProseBlock(text: text) }

    private func segmentView(_ seg: MarkdownSegments.Segment) -> some View { MarkdownSegmentView(segment: seg, live: live) }
}

/// A reply's Markdown as separate views, one per piece, with no container: inside the transcript's lazy stack each
/// piece is a row of its own, so only the rows on screen are laid out as a reply grows. Inside one view, every
/// finished piece was laid out again 10 times a second while a reply streamed (Textual's layout isn't cached): 46% of
/// the app's CPU for a 30 KB reply, and 1-7 s stalls late in long ones. Finished replies use the same rows, so
/// nothing jumps when a reply ends (one big view in place of many rows left the transcript scrolled past its end).
/// Tried and dropped: a lazy stack inside the transcript's (didn't draw its pieces after a jump to the end), and the
/// finished pieces as one row (no faster: that row was laid out again too).
struct MarkdownPieces: View {
    let markdown: String
    /// Still streaming: code stays plain, and the text is split again from its last piece only.
    var live = false

    var body: some View {
        ForEach(Array((live ? MarkdownSplitCache.split(markdown) : MarkdownSegments.split(markdown)).enumerated()),
                id: \.offset) { _, seg in MarkdownSegmentView(segment: seg, live: live) }
    }
}

/// One piece: Textual prose, or a code block of ours.
struct MarkdownSegmentView: View {
    let segment: MarkdownSegments.Segment
    var live = false

    var body: some View {
        switch segment {
        case .prose(let text): ProseBlock(text: text).equatable()
        case .code(let code, let language): CodeBlockView(code: code, language: language, live: live)
        }
    }
}

/// One piece of prose, drawn by Textual.
private struct ProseBlock: View, Equatable {
    let text: String

    var body: some View {
        #if DEBUG
        let _ = BodyTrace.on ? Self._printChanges() : ()
        #endif
        StructuredText(markdown: text)
            .textual.structuredTextStyle(.gitHub)
            .textual.codeBlockStyle(CopyableCodeBlockStyle())
            .textual.textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Markdown cut into prose and fenced code blocks (``` or ~~~ at the start of a line). Prose is also cut before
/// each heading at the start of a line (a heading ends whatever block came before it), so a long reply is many
/// small pieces and only the last one changes while it streams.
enum MarkdownSegments {
    enum Segment: Equatable {
        case prose(String)
        case code(String, language: String?)
    }

    /// A segment and where its first line starts (a UTF-8 offset in the whole text).
    struct Piece: Equatable {
        var segment: Segment
        var start: Int
    }

    static func split(_ markdown: String) -> [Segment] { pieces(markdown[...], base: 0).map(\.segment) }

    /// Splits `text`, which starts `base` bytes into the whole text.
    static func pieces(_ text: Substring, base: Int) -> [Piece] {
        var out: [Piece] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var fence: Substring?
        var language: String?
        var codeStart = 0
        func offset(_ line: Substring) -> Int { base + text.utf8.distance(from: text.startIndex, to: line.startIndex) }
        func flushProse() {
            var piece: [Substring] = []
            func flushPiece() {
                guard let first = piece.first else { return }
                let joined = piece.joined(separator: "\n")
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(Piece(segment: .prose(joined), start: offset(first)))
                }
                piece = []
            }
            for line in prose {
                if isHeading(line) { flushPiece() }
                piece.append(line)
            }
            flushPiece()
            prose = []
        }
        func isHeading(_ line: Substring) -> Bool {
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { return false }
            let rest = line.dropFirst(hashes)
            return rest.isEmpty || rest.first == " " || rest.first == "\t"
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if let f = fence {
                if trimmed.hasPrefix(f), trimmed.drop(while: { $0 == f.first }).allSatisfy(\.isWhitespace) {
                    out.append(Piece(segment: .code(code.joined(separator: "\n"), language: language), start: codeStart))
                    code = []
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if line.count - trimmed.count <= 3, let marker = trimmed.first, marker == "`" || marker == "~" {
                let run = trimmed.prefix { $0 == marker }
                if run.count >= 3 {
                    flushProse()
                    fence = run
                    codeStart = offset(line)
                    let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
                    language = info.isEmpty ? nil : String(info.split(separator: " ").first ?? "")
                } else {
                    prose.append(line)
                }
            } else {
                prose.append(line)
            }
        }
        if fence != nil {      // still streaming
            out.append(Piece(segment: .code(code.joined(separator: "\n"), language: language), start: codeStart))
        }
        flushProse()
        return out
    }
}

/// Splits a streaming reply again from its last piece only: the reply only grows, so the pieces before the last one
/// stay as they were. Splitting all of a 60 KB reply on every update made thousands of short-lived strings, and on a
/// fragmented heap freeing them took 11% of the main thread during a stall.
@MainActor enum MarkdownSplitCache {
    private static var entries: [(text: String, pieces: [MarkdownSegments.Piece])] = []

    static func split(_ markdown: String) -> [MarkdownSegments.Segment] {
        for (i, entry) in entries.enumerated() {
            // The last piece may still change; everything before its start is the same text, split the same way.
            guard let last = entry.pieces.last, last.start > 0, markdown.utf8.count >= last.start,
                  markdown.utf8.prefix(last.start).elementsEqual(entry.text.utf8.prefix(last.start)) else { continue }
            let tail = markdown[markdown.utf8.index(markdown.startIndex, offsetBy: last.start)...]
            let pieces = Array(entry.pieces.dropLast()) + MarkdownSegments.pieces(tail, base: last.start)
            entries[i] = (markdown, pieces)
            return pieces.map(\.segment)
        }
        let pieces = MarkdownSegments.pieces(markdown[...], base: 0)
        entries.insert((markdown, pieces), at: 0)
        if entries.count > 4 { entries.removeLast() }
        return pieces.map(\.segment)
    }
}

/// GitHub-style code block with the language and a copy button in a header row. Used only for code blocks
/// nested inside other blocks (in a list item, say), which stay with Textual.
struct CopyableCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.languageHint ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton { configuration.codeBlock.copyToPasteboard() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .textual.fontScale(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(12)
            }
        }
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .textual.blockSpacing(.init(top: 0, bottom: 14))
    }
}

private struct CopyButton: View {
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
    }
}
