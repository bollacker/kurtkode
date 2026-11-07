import Foundation

/// Line diffs in unified format, from Swift's `CollectionDifference`.
public enum LineDiff {
    public enum Op: Equatable, Sendable {
        case same(String), removed(String), added(String)
    }

    static func lines(_ s: String) -> [String] {
        guard !s.isEmpty else { return [] }
        var l = s.components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return l
    }

    /// Past these sizes of the changed part (what's left between the lines both texts start and end with), lines aren't
    /// diffed: `CollectionDifference` takes time in proportion to the lines times the changes, and a rewrite of a big file
    /// froze the app. Then a diff says the file was rewritten, and how many lines it had and has.
    static let maxDiffLines = 20_000
    static let maxDiffBytes = 2_000_000

    /// Two texts compared once, for a call's preview, unified diff, counts and changed regions.
    public struct Comparison: Sendable {
        public let oldLines: [String]
        public let newLines: [String]
        /// nil when the changed part was too large to diff (`maxDiffLines`, `maxDiffBytes`).
        public let ops: [Op]?
        /// The lines both texts start with, and how many lines differ after them before the lines both end with (an
        /// upper bound on what a diff would count).
        let head: Int, changedOld: Int, changedNew: Int
    }

    public static func compare(old: String, new: String) -> Comparison {
        let a = lines(old), b = lines(new)
        // The lines both start and end with are the same; only what's between needs diffing.
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var end = 0
        while end < a.count - start, end < b.count - start, a[a.count - 1 - end] == b[b.count - 1 - end] { end += 1 }
        let midA = a[start..<(a.count - end)], midB = b[start..<(b.count - end)]
        let bytes = midA.reduce(0) { $0 + $1.utf8.count } + midB.reduce(0) { $0 + $1.utf8.count }
        guard max(midA.count, midB.count) <= maxDiffLines, bytes <= maxDiffBytes else {
            return Comparison(oldLines: a, newLines: b, ops: nil, head: start, changedOld: midA.count, changedNew: midB.count)
        }
        var out: [Op] = a[..<start].map { .same($0) }
        let diff = Array(midB).difference(from: Array(midA))
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let ma = Array(midA), mb = Array(midB)
        var i = 0, j = 0
        while i < ma.count || j < mb.count {
            if i < ma.count, removed.contains(i) { out.append(.removed(ma[i])); i += 1 }
            else if j < mb.count, inserted.contains(j) { out.append(.added(mb[j])); j += 1 }
            else if i < ma.count, j < mb.count { out.append(.same(ma[i])); i += 1; j += 1 }
            else if i < ma.count { out.append(.removed(ma[i])); i += 1 }
            else { out.append(.added(mb[j])); j += 1 }
        }
        out += a[(a.count - end)...].map { .same($0) }
        return Comparison(oldLines: a, newLines: b, ops: out, head: start, changedOld: midA.count, changedNew: midB.count)
    }

    /// The ops of a diff; for texts too large to diff (`compare`), everything between their common start and end removed
    /// and added.
    public static func ops(old: String, new: String) -> [Op] { ops(compare(old: old, new: new)) }

    static func ops(_ c: Comparison) -> [Op] {
        if let ops = c.ops { return ops }
        let h = c.head
        return c.oldLines[..<h].map { .same($0) } + c.oldLines[h..<(h + c.changedOld)].map { .removed($0) }
            + c.newLines[h..<(h + c.changedNew)].map { .added($0) } + c.oldLines[(h + c.changedOld)...].map { .same($0) }
    }

    /// Counts of added and removed lines.
    public static func stats(old: String, new: String) -> (added: Int, removed: Int) { stats(compare(old: old, new: new)) }

    public static func stats(_ c: Comparison) -> (added: Int, removed: Int) {
        guard let ops = c.ops else { return (c.changedNew, c.changedOld) }
        var add = 0, rem = 0
        for op in ops {
            switch op {
            case .added: add += 1
            case .removed: rem += 1
            case .same: break
            }
        }
        return (add, rem)
    }

    /// A unified diff with `context` lines around each change. Empty when nothing changed.
    public static func unified(old: String, new: String, path: String, context: Int = 3) -> String {
        unified(compare(old: old, new: new), path: path, context: context)
    }

    public static func unified(_ c: Comparison, path: String, context: Int = 3) -> String {
        guard let ops = c.ops else {
            return "--- a/\(path)\n+++ b/\(path)\n[File rewritten: \(c.oldLines.count) lines → \(c.newLines.count) lines, too large "
                + "a change to show line by line.]\n"
        }
        guard ops.contains(where: { if case .same = $0 { false } else { true } }) else { return "" }

        // Positions (in `ops`) that are changes, then windows of context around them, merged.
        let changeIdx = ops.indices.filter { if case .same = ops[$0] { false } else { true } }
        var windows: [ClosedRange<Int>] = []
        for idx in changeIdx {
            let w = max(0, idx - context)...min(ops.count - 1, idx + context)
            if let last = windows.last, w.lowerBound <= last.upperBound + 1 {
                windows[windows.count - 1] = last.lowerBound...max(last.upperBound, w.upperBound)
            } else {
                windows.append(w)
            }
        }

        // Line numbers at each op position.
        var aLine = [Int](repeating: 0, count: ops.count), bLine = aLine
        var a = 1, b = 1
        for (k, op) in ops.enumerated() {
            aLine[k] = a; bLine[k] = b
            switch op {
            case .same: a += 1; b += 1
            case .removed: a += 1
            case .added: b += 1
            }
        }

        var out = "--- a/\(path)\n+++ b/\(path)\n"
        for w in windows {
            let slice = ops[w]
            let aCount = slice.filter { if case .added = $0 { false } else { true } }.count
            let bCount = slice.filter { if case .removed = $0 { false } else { true } }.count
            let aStart = aCount == 0 ? aLine[w.lowerBound] - 1 : aLine[w.lowerBound]
            let bStart = bCount == 0 ? bLine[w.lowerBound] - 1 : bLine[w.lowerBound]
            out += "@@ -\(aStart),\(aCount) +\(bStart),\(bCount) @@\n"
            for op in slice {
                switch op {
                case .same(let l): out += " \(l)\n"
                case .removed(let l): out += "-\(l)\n"
                case .added(let l): out += "+\(l)\n"
                }
            }
        }
        return out
    }
}
