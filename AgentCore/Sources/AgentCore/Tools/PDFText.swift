import Foundation
import PDFKit

/// The text of a PDF, a range of pages at a time.
public enum PDFText {
    /// "3" or "2-5": first and last page, from 1.
    static func range(_ spec: String, count: Int) throws -> ClosedRange<Int> {
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...2).contains(parts.count), let first = Int(parts[0]), let last = Int(parts.last ?? ""), first >= 1, last >= first else {
            throw ToolFailure("pages wants a page or a range, like 3 or 2-5. Leave it out for the whole file.")
        }
        guard first <= count else { throw ToolFailure("page \(first) is past the end (\(count) pages)") }
        return first...min(last, count)
    }

    /// `pages` as models spell the default. An error there reads as "this tool can't read PDFs", and they go elsewhere.
    static func meansWhole(_ pages: String) -> Bool {
        ["", "all", "*"].contains(pages.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The pages' text, each headed with its number; the whole document without `pages`. Fails on a PDF that won't open;
    /// a scanned one gives no text, which is said rather than passed off as empty.
    public static func extract(_ data: Data, pages: String?) throws -> (text: String, pageCount: Int) {
        guard let doc = PDFDocument(data: data) else { throw ToolFailure("that PDF can't be read") }
        if doc.isLocked { throw ToolFailure("that PDF is password-protected") }
        let span = try pages.flatMap { meansWhole($0) ? nil : try range($0, count: doc.pageCount) } ?? 1...max(1, doc.pageCount)
        var out: [String] = []
        for n in span where n <= doc.pageCount {
            let text = doc.page(at: n - 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            out.append("--- page \(n) of \(doc.pageCount) ---\n" + (text.isEmpty ? "(no text on this page: it may be a scan)" : text))
        }
        return (out.joined(separator: "\n\n"), doc.pageCount)
    }
}
