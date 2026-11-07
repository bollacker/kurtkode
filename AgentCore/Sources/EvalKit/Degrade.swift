import AgentCore
import Foundation

/// Ways to make a good run wrong on purpose, each a kind of failure real subagents have (EVAL_PLAN.md E2). Each is
/// applied to a copy of a passing run's report or project; a copy counts as a known failure only if gold then fails.
public enum Degradation: String, CaseIterable, Sendable {
    /// Every multi-digit number in the report changed (lines, amounts, times, names like Heron42).
    case digits
    /// Each file the report names replaced with another file of the project with the same extension.
    case wrongFile = "wrong-file"
    /// Every other answer line dropped (lines with a path, list items, table rows).
    case dropHalf = "drop-half"
    /// The first hunk of the run's changes reversed; the report still claims it all.
    case undoHalf = "undo-half"
    /// The project reset to the fixture; the report still claims success.
    case undoAll = "undo-all"
    /// The files the run created deleted.
    case vanish
    /// An edit outside the task (README.md).
    case strayEdit = "stray-edit"

    /// Whether the kind fits the task: project changes only for tasks that change files.
    public static func applies(_ kind: Degradation, to task: BankTask) -> Bool {
        switch kind {
        case .undoHalf, .undoAll, .vanish: return !task.mayChange.isEmpty
        default: return true
        }
    }

    /// Applies `kind` to the copy in `dir` and returns the report to go with it; nil when it changes nothing.
    public static func apply(_ kind: Degradation, report: String, dir: URL) -> String? {
        switch kind {
        case .digits:
            let bad = Runner.degrade(report)
            return bad == report ? nil : bad
        case .wrongFile:
            return wrongFile(report, dir: dir)
        case .dropHalf:
            return dropHalf(report)
        case .undoHalf:
            return undoFirstHunk(dir) ? report : nil
        case .undoAll:
            guard !TaskBank.changedPaths(dir).isEmpty else { return nil }
            _ = shell("cd \(q(dir.path)) && git checkout -q -- . && git clean -qfd")
            return report
        case .vanish:
            let created = shell("git -C \(q(dir.path)) ls-files --others --exclude-standard").output.split(separator: "\n")
                .map(String.init).filter { !$0.contains("__pycache__") && !$0.hasSuffix(".pyc") }
            guard !created.isEmpty else { return nil }
            for p in created { try? FileManager.default.removeItem(at: dir.appending(path: p)) }
            return report
        case .strayEdit:
            let readme = dir.appending(path: "README.md")
            let text = (try? String(contentsOf: readme, encoding: .utf8)) ?? ""
            try? (text + "\nEdited outside the task.\n").write(to: readme, atomically: true, encoding: .utf8)
            return report
        }
    }

    /// The report with each project file it names (by path, or by file name) swapped for another file of the same
    /// extension; nil if it names none.
    static func wrongFile(_ report: String, dir: URL) -> String? {
        let files = shell("git -C \(q(dir.path)) ls-files").output.split(separator: "\n").map(String.init).sorted()
        var out = report
        var swaps: [(String, String)] = []
        for f in files.sorted(by: { $0.count > $1.count }) {
            let ext = (f as NSString).pathExtension
            guard !ext.isEmpty, let other = files.first(where: { $0 != f && ($0 as NSString).pathExtension == ext
                                                                && !report.contains(($0 as NSString).lastPathComponent) }) else { continue }
            for (from, to) in [(f, other), ((f as NSString).lastPathComponent, (other as NSString).lastPathComponent)] where out.contains(from) {
                // A placeholder first, so a swapped name isn't swapped again.
                let mark = "\u{1}\(swaps.count)\u{1}"
                out = out.replacingOccurrences(of: from, with: mark)
                swaps.append((mark, to))
            }
        }
        guard !swaps.isEmpty else { return nil }
        for (mark, to) in swaps { out = out.replacingOccurrences(of: mark, with: to) }
        return out
    }

    /// The report with every other answer line removed; nil with fewer than two.
    static func dropHalf(_ report: String) -> String? {
        let lines = report.components(separatedBy: "\n")
        func isAnswer(_ l: String) -> Bool {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.contains("---") { return false }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.firstMatch(of: /^\d+[.)]\s/) != nil { return true }
            if t.hasPrefix("|") { return !t.lowercased().contains("file") || t.contains(".") }
            return t.firstMatch(of: /[\w-]+\.(py|md|csv|log|txt|swift|diff)\b/) != nil
        }
        let answers = lines.indices.filter { isAnswer(lines[$0]) }
        guard answers.count >= 2 else { return nil }
        let drop = Set(answers.enumerated().filter { $0.offset % 2 == 1 }.map(\.element))
        return lines.indices.filter { !drop.contains($0) }.map { lines[$0] }.joined(separator: "\n")
    }

    /// Reverses the first hunk of the run's changes since the fixture's base commit (new files and the run's own
    /// commits included); false with fewer than two hunks.
    static func undoFirstHunk(_ dir: URL) -> Bool {
        let path = q(dir.path)
        _ = shell("git -C \(path) add -A -- . ':!*__pycache__*'")
        // No context lines: changes a few lines apart are separate hunks.
        let diff = shell("git -C \(path) diff --cached -U0 \(Fixtures.base(dir))").output
        _ = shell("git -C \(path) reset -q")
        // Files, each a header and its hunks.
        var sections: [(header: [String], hunks: [[String]])] = []
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git") { sections.append(([line], [])) }
            else if line.hasPrefix("@@"), !sections.isEmpty { sections[sections.count - 1].hunks.append([line]) }
            else if !sections.isEmpty {
                if sections[sections.count - 1].hunks.isEmpty { sections[sections.count - 1].header.append(line) }
                else { sections[sections.count - 1].hunks[sections[sections.count - 1].hunks.count - 1].append(line) }
            }
        }
        let total = sections.map(\.hunks.count).reduce(0, +)
        guard total >= 2, let first = sections.first(where: { !$0.hunks.isEmpty }) else { return false }
        let patch = (first.header + first.hunks[0]).joined(separator: "\n") + "\n"
        let file = FileManager.default.temporaryDirectory.appending(path: "kk-hunk-\(UUID().uuidString.prefix(6)).patch")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? patch.write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        return shell("git -C \(path) apply -R --unidiff-zero --whitespace=nowarn \(q(file.path))").status == 0
    }
}
