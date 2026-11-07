import Foundation

/// The ripgrep binary the grep tool runs (B4): bundled in AgentCore's resources (`Bin/rg`, ripgrep 15.2.0 for arm64,
/// MIT), so the app and the CLI both carry it. `KURTKODE_RG` names another binary, or `none` for the built-in search;
/// without either, Homebrew's rg, else the built-in search.
public enum Ripgrep {
    public static let executable: URL? = locate(ProcessInfo.processInfo.environment)

    static func locate(_ env: [String: String]) -> URL? {
        let fm = FileManager.default
        if let v = env["KURTKODE_RG"], !v.isEmpty {
            if ["none", "off", "builtin"].contains(v.lowercased()) { return nil }
            let p = (v as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: p) ? URL(fileURLWithPath: p) : nil
        }
        if let bin = PromptTemplates.resourceFolder("Bin", marker: "rg")?.appending(path: "rg"),
           fm.isExecutableFile(atPath: bin.path) { return bin }
        for p in ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"] where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
}

/// File types for grep's `type` filter, as globs (both engines use this table, so a type means the same files).
enum FileTypes {
    static let globs: [String: [String]] = {
        var t: [String: [String]] = [
            "swift": ["*.swift"], "py": ["*.py", "*.pyi"], "js": ["*.js", "*.mjs", "*.cjs", "*.jsx"],
            "ts": ["*.ts", "*.tsx", "*.mts", "*.cts"], "go": ["*.go"], "rust": ["*.rs"], "java": ["*.java"],
            "kotlin": ["*.kt", "*.kts"], "c": ["*.c", "*.h"], "cpp": ["*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hh", "*.hxx", "*.h"],
            "objc": ["*.m", "*.mm", "*.h"], "cs": ["*.cs"], "ruby": ["*.rb"], "php": ["*.php"],
            "sh": ["*.sh", "*.bash", "*.zsh"], "md": ["*.md", "*.markdown", "*.mdx"], "json": ["*.json", "*.jsonl"],
            "yaml": ["*.yaml", "*.yml"], "toml": ["*.toml"], "html": ["*.html", "*.htm"],
            "css": ["*.css", "*.scss", "*.sass", "*.less"], "sql": ["*.sql"], "txt": ["*.txt"], "xml": ["*.xml"],
            "make": ["Makefile", "makefile", "GNUmakefile", "*.mk"], "docker": ["Dockerfile", "*.dockerfile"],
            "lua": ["*.lua"], "r": ["*.r", "*.R"], "scala": ["*.scala"], "dart": ["*.dart"], "elixir": ["*.ex", "*.exs"],
            "zig": ["*.zig"], "log": ["*.log"], "vue": ["*.vue"], "svelte": ["*.svelte"], "proto": ["*.proto"], "tf": ["*.tf", "*.tfvars"],
        ]
        for (alias, name) in ["python": "py", "javascript": "js", "typescript": "ts", "rs": "rust", "kt": "kotlin",
                              "csharp": "cs", "rb": "ruby", "markdown": "md", "yml": "yaml", "shell": "sh",
                              "bash": "sh", "c++": "cpp", "terraform": "tf"] { t[alias] = t[name] }
        return t
    }()

    /// The globs for a type, and a note when the type isn't in the table: then it's taken as a file extension (a
    /// refusal would cost a weak model a turn; the note says what was searched, so a typo shows).
    static func globs(for type: String) throws -> (globs: [Glob], note: String?) {
        let name = type.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".* "))
        if let patterns = globs[name] { return (try patterns.map(Glob.init), nil) }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            throw ToolFailure("unknown file type \"\(type)\". Known types: \(known.joined(separator: ", ")). Or use glob, e.g. \"*.ext\".")
        }
        return ([try Glob("*.\(name)")], "[\"\(type)\" isn't a known type; searched *.\(name) files. Known types: \(known.joined(separator: ", ")).]")
    }

    static let known: [String] = Set(globs.keys).subtracting(["python", "javascript", "typescript", "rs", "kt", "csharp", "rb",
                                                             "markdown", "yml", "shell", "bash", "c++", "terraform"]).sorted()
}

/// What a grep call asks for, after defaults and aliases.
struct GrepQuery: Sendable {
    enum Mode: String, Sendable { case content, files, count }
    var pattern: String
    var caseInsensitive = false
    /// `.` matches newlines and a match may span lines.
    var multiline = false
    var before = 0
    var after = 0
    var mode = Mode.content
}

/// One file's results: its matching lines with their context (content mode) and how many matched.
struct GrepFileHits: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        var number: Int
        var text: String
        var isMatch: Bool
    }
    var path: String
    var lines: [Line] = []
    /// Matching lines; in multiline mode, matches.
    var count = 0
    /// Output lines (matches and context) counted but not kept: past the page asked for, or in a mode that shows none.
    var omittedLines = 0
}

/// Search engines: ripgrep when there is one, and the built-in one (NSRegularExpression) when not, or when rg
/// can't start. Both take the files to search (already filtered for withheld and denied files) and return the files
/// that matched, in path order.
enum GrepEngine {
    static let maxFileBytes = 2_000_000

    /// The most of rg's JSON read for a page of content results; past it the search stops, and `complete` says so.
    static let maxJSONBytes = 32_000_000

    /// The files that matched. With `keepLines` (content mode: the end of the page asked for), only that many output
    /// lines are kept, in path order, and the rest are counted (`omittedLines`): a search matching most of a big
    /// project would otherwise be held whole to show 200 lines of it. Then rg's output is read up to `maxJSONBytes`,
    /// and `complete` is false if it stopped there.
    static func search(_ files: [String], root: URL, query: GrepQuery, rg: URL? = Ripgrep.executable,
                       keepLines: Int? = nil, jsonLimit: Int = maxJSONBytes) async throws -> (hits: [GrepFileHits], complete: Bool) {
        if let rg, let found = try await ripgrep(rg, files: files, root: root, query: query, keepLines: keepLines, jsonLimit: jsonLimit) {
            return found
        }
        return (try builtin(files, root: root, query: query, keepLines: keepLines), true)
    }

    // MARK: ripgrep

    /// nil when rg couldn't run (the caller falls back); a bad pattern throws.
    static func ripgrep(_ rg: URL, files: [String], root: URL, query: GrepQuery,
                        keepLines: Int? = nil, jsonLimit: Int = maxJSONBytes) async throws -> (hits: [GrepFileHits], complete: Bool)? {
        var args = ["--json", "--no-config", "--engine", "auto", "--max-filesize", String(maxFileBytes), "--no-messages"]
        // The lines kept must be the first in path order: the files go in that order and rg keeps it.
        let files = keepLines == nil ? files : files.sorted()
        if keepLines != nil { args += ["--sort", "path"] }
        if query.caseInsensitive { args.append("-i") }
        if query.multiline { args += ["-U", "--multiline-dotall"] }
        switch query.mode {
        case .content:
            if query.before > 0 { args += ["-B", String(query.before)] }
            if query.after > 0 { args += ["-A", String(query.after)] }
        case .files: args += ["-m", "1"]
        case .count: break
        }
        args += ["-e", query.pattern, "--"]
        var all: [GrepFileHits] = []
        // Only content mode shows lines.
        var keep = query.mode == .content ? keepLines ?? .max : 0
        var budget = keepLines == nil ? nil : jsonLimit, stopped = false
        // Explicit file lists, in batches that keep well under the argument limit (1 MB on macOS).
        var batch: [String] = [], size = 0
        func flush() async throws -> Bool {
            defer { batch = []; size = 0 }
            guard !batch.isEmpty, !stopped else { return true }
            // A name starting with "-" ("-" itself is stdin to rg) goes as "./-…"; results are mapped back below.
            let named = batch.map { $0.hasPrefix("-") ? "./" + $0 : $0 }
            guard let run = await runParsing(rg, args + named, cwd: root, multiline: query.multiline, keep: keep, byteLimit: budget)
            else { return false }
            if run.status == 2, !run.stopped, let problem = patternProblem(run.stderr) {
                throw ToolFailure("invalid regular expression: \(query.pattern) (\(problem))")
            }
            all += run.hits.map { h in
                var h = h
                if h.path.hasPrefix("./-") { h.path.removeFirst(2) }
                return h
            }
            keep = max(0, keep - run.hits.reduce(0) { $0 + $1.lines.count })
            budget = budget.map { $0 - run.bytes }
            stopped = run.stopped
            return true
        }
        for f in files {
            if size + f.utf8.count + 1 > 200_000 { guard try await flush() else { return nil } }
            if stopped { break }
            batch.append(f)
            size += f.utf8.count + 1
            if Task.isCancelled { break }
        }
        guard try await flush() else { return nil }
        return (all.sorted { $0.path < $1.path }, !stopped)
    }

    /// rg's complaint about the pattern, when its error output is one (other errors are about files, and skipped).
    static func patternProblem(_ stderr: String) -> String? {
        guard stderr.contains("regex parse error") || stderr.contains("error parsing") || stderr.contains("PCRE2") else { return nil }
        let lines = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { $0.hasPrefix("error:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            ?? lines.last ?? "rg refused it"
    }

    private struct Event: Decodable {
        struct Text: Decodable {
            var text: String?
            var bytes: String?
            var string: String { text ?? bytes.flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? "" }
        }
        struct Payload: Decodable {
            var path: Text?
            var lines: Text?
            var line_number: Int?
            var binary_offset: Int?
            var submatches: [Submatch]?
        }
        struct Submatch: Decodable { var start: Int }
        var type: String
        var data: Payload
    }

    /// rg's JSON lines to results. A file rg found a NUL byte in is dropped (the built-in search skips binary files).
    static func parseJSON(_ data: Data, multiline: Bool) -> [GrepFileHits] {
        var parser = JSONParser(multiline: multiline)
        for raw in data.split(separator: 0x0A) { parser.feed(raw) }
        return parser.out
    }

    /// `parseJSON` a line at a time, keeping at most `keep` output lines (the rest are counted in `omittedLines`).
    struct JSONParser {
        let multiline: Bool
        let keep: Int
        private(set) var out: [GrepFileHits] = []
        private var current: GrepFileHits?
        /// The current file's last line listed (kept or counted).
        private var lastLine = 0
        private var kept = 0
        private let decoder = JSONDecoder()

        init(multiline: Bool, keep: Int = .max) {
            self.multiline = multiline
            self.keep = keep
        }

        /// The results when the search stopped part way: the file being read counts if it had matched.
        var partial: [GrepFileHits] { current.map { $0.count > 0 ? out + [$0] : out } ?? out }

        mutating func feed(_ raw: Data) {
            guard let e = try? decoder.decode(Event.self, from: raw) else { return }
            switch e.type {
            case "begin":
                current = GrepFileHits(path: e.data.path?.string ?? "")
                lastLine = 0
            case "match", "context":
                guard var c = current, let first = e.data.line_number else { return }
                let isMatch = e.type == "match"
                var texts = (e.data.lines?.string ?? "").components(separatedBy: "\n")
                if texts.count > 1, texts.last == "" { texts.removeLast() }
                for (i, t) in texts.enumerated() {
                    let n = first + i
                    // A multiline match can overlap a line already listed (as context, or the previous match's end).
                    if lastLine >= n {
                        if isMatch, let j = c.lines.lastIndex(where: { $0.number == n }) { c.lines[j].isMatch = true }
                        continue
                    }
                    lastLine = n
                    guard kept < keep else { c.omittedLines += 1; continue }
                    let text = t.hasSuffix("\r") ? String(t.dropLast()) : t
                    c.lines.append(.init(number: n, text: text, isMatch: isMatch))
                    kept += 1
                }
                // rg joins a multiline match with matches on the lines next to it into one event; its submatches count.
                if isMatch { c.count += multiline ? max(1, e.data.submatches?.count ?? 1) : texts.count }
                current = c
            case "end":
                // As the built-in engine decides (`looksBinary`): binary when a NUL byte is in the first 8 KB.
                if let c = current {
                    if (e.data.binary_offset ?? Int.max) >= 8192, c.count > 0 { out.append(c) } else { kept -= c.lines.count }
                }
                current = nil
            default: break
            }
        }
    }

    struct Parsed { var hits: [GrepFileHits]; var stderr: String; var status: Int32; var bytes: Int; var stopped: Bool }

    /// Runs rg, parsing its JSON as it comes (keeping `keep` output lines); past `byteLimit` bytes of it, stops rg.
    /// nil when it can't start. Stopping the task stops it.
    static func runParsing(_ exe: URL, _ args: [String], cwd: URL, multiline: Bool, keep: Int, byteLimit: Int?) async -> Parsed? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.currentDirectoryURL = cwd
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let exited: DispatchSemaphore
        do { exited = try p.startWithExitSignal() } catch { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let stderr = PipeDrain(err.fileHandleForReading)
                    var parser = JSONParser(multiline: multiline, keep: keep)
                    var pending = Data(), bytes = 0, stopped = false
                    let reader = out.fileHandleForReading
                    while true {
                        let chunk = reader.availableData
                        if chunk.isEmpty { break }
                        bytes += chunk.count
                        pending.append(chunk)
                        if let nl = pending.lastIndex(of: 0x0A) {
                            for raw in pending[..<nl].split(separator: 0x0A) { parser.feed(Data(raw)) }
                            pending = Data(pending[(nl + 1)...])
                        }
                        if let byteLimit, bytes > byteLimit {
                            stopped = true
                            p.terminate()
                            break
                        }
                    }
                    if !stopped, !pending.isEmpty { parser.feed(pending) }
                    let status = p.waitForExit(exited, timeout: 120)
                    let errText = String(decoding: stderr.wait(timeout: 2) ?? Data(), as: UTF8.self)
                    cont.resume(returning: Parsed(hits: stopped ? parser.partial : parser.out, stderr: errText, status: status,
                                                  bytes: bytes, stopped: stopped))
                }
            }
        } onCancel: {
            p.terminate()
        }
    }

    // MARK: built-in

    static func builtin(_ files: [String], root: URL, query: GrepQuery, keepLines: Int? = nil) throws -> [GrepFileHits] {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if query.caseInsensitive { options.insert(.caseInsensitive) }
        if query.multiline { options.insert(.dotMatchesLineSeparators) }
        let regex: NSRegularExpression
        do { regex = try NSRegularExpression(pattern: query.pattern, options: options) }
        catch { throw ToolFailure("invalid regular expression: \(query.pattern)") }
        var out: [GrepFileHits] = []
        var keep = keepLines ?? .max
        for rel in keepLines == nil ? files : files.sorted() {
            if Task.isCancelled { break }
            let url = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : root.appending(path: rel)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  data.count <= maxFileBytes, !looksBinary(data) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            var lines = text.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            var matched = Set<Int>()       // 1-based
            var count = 0
            if query.multiline {
                let ns = text as NSString
                // Line starts, to turn a match's offsets into line numbers.
                var starts = [0]
                var i = 0
                for u in text.utf16 { i += 1; if u == 0x0A { starts.append(i) } }
                func line(at offset: Int) -> Int {
                    var lo = 0, hi = starts.count - 1
                    while lo < hi { let mid = (lo + hi + 1) / 2; if starts[mid] <= offset { lo = mid } else { hi = mid - 1 } }
                    return lo + 1
                }
                for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.range.length > 0 {
                    count += 1
                    let first = line(at: m.range.location), last = line(at: max(m.range.location, NSMaxRange(m.range) - 1))
                    for n in first...min(last, lines.count) { matched.insert(n) }
                    if query.mode == .files { break }
                }
            } else {
                for (i, l) in lines.enumerated() where regex.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil {
                    matched.insert(i + 1)
                    count += 1
                    if query.mode == .files { break }
                }
            }
            guard count > 0 else { continue }
            var hits = GrepFileHits(path: rel, count: count)
            if query.mode == .content {
                var shown = Set<Int>()
                for n in matched {
                    for k in max(1, n - query.before)...min(lines.count, n + query.after) { shown.insert(k) }
                }
                let numbers = shown.sorted()
                hits.lines = numbers.prefix(keep).map { .init(number: $0, text: lines[$0 - 1], isMatch: matched.contains($0)) }
                hits.omittedLines = numbers.count - hits.lines.count
                keep -= hits.lines.count
            }
            out.append(hits)
        }
        return out
    }
}

public struct GrepTool: Tool {
    /// The ripgrep to run; nil for the built-in search.
    let rg: URL?
    public init() { rg = Ripgrep.executable }
    init(rg: URL?) { self.rg = rg }
    /// Files listed for one search at most (more are left out, and the result says so).
    var fileLimit = 50_000
    public let name = "grep"
    public let description = """
        Search file contents with a regular expression (ripgrep). output_mode "content" (default) returns matching \
        lines as path:line: text, with context lines as path-line- text when asked; "files_with_matches" lists the \
        files; "count" gives matching lines per file and the total (use it to count, rather than counting lines \
        yourself). Narrow with glob (e.g. "*.swift"), type (e.g. "py") and path. Page with head_limit and offset. \
        Honors .gitignore.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "pattern": ["type": "string", "description": "Regular expression (Rust/PCRE syntax: escape literal ( ) [ ] { } . * + ? |)."],
            "path": ["type": "string", "description": "File or directory to search. Default: the project root."],
            "glob": ["type": "string", "description": "Only search files matching this glob, e.g. \"*.py\" or \"src/**/*.ts\"."],
            "type": ["type": "string", "description": "Only search files of this type: py, js, ts, swift, go, rust, java, c, cpp, md, json, yaml, sh, …"],
            "output_mode": ["type": "string", "enum": ["content", "files_with_matches", "count"],
                            "description": "content (default): matching lines; files_with_matches: file paths; count: matches per file and total."],
            "case_insensitive": ["type": "boolean", "description": "Ignore case. Default false."],
            "context": ["type": "integer", "description": "Lines of context before and after each match (content mode)."],
            "before_context": ["type": "integer", "description": "Lines of context before each match (content mode)."],
            "after_context": ["type": "integer", "description": "Lines of context after each match (content mode)."],
            "multiline": ["type": "boolean", "description": "Let a match span lines; . matches newlines. Default false."],
            "head_limit": ["type": "integer", "description": "Show at most this many lines, files or counts. Default 200 lines, 500 files."],
            "offset": ["type": "integer", "description": "Skip this many lines, files or counts first (for the next page). Default 0."],
        ],
        "required": ["pattern"],
    ]
    public let risk = ToolRisk.read
    static let defaultLineLimit = 200
    static let defaultFileLimit = 500
    static let maxContext = 20
    static let maxLineLength = 300

    public func summary(_ args: ToolArguments) -> String {
        var s = (Self.mode(args) == .count ? "Count " : "Search for ") + (args.string("pattern").map { "\"\($0)\"" } ?? "?")
        if let g = args.string("glob") { s += " in \(g)" }
        if let t = args.string("type") { s += " in \(t) files" }
        if let p = args.string("path"), p != "." { s += " under \(p)" }
        return s
    }

    static func mode(_ args: ToolArguments) -> GrepQuery.Mode {
        switch args.string("output_mode")?.lowercased() {
        case "files_with_matches", "files", "files_only", "list", "l": return .files
        case "count", "count_matches", "c": return .count
        default: return args.bool("files_only") == true ? .files : .content
        }
    }

    static func query(_ args: ToolArguments) throws -> GrepQuery {
        var q = GrepQuery(pattern: try args.require("pattern"))
        q.caseInsensitive = args.bool("case_insensitive") ?? args.bool("-i") ?? args.bool("ignore_case") ?? false
        q.multiline = args.bool("multiline") ?? args.bool("-U") ?? false
        q.mode = mode(args)
        let both = args.int("context") ?? args.int("-C") ?? 0
        q.before = min(maxContext, max(0, args.int("before_context") ?? args.int("-B") ?? both))
        q.after = min(maxContext, max(0, args.int("after_context") ?? args.int("-A") ?? both))
        return q
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let query = try Self.query(args)
        let glob = try args.string("glob").map(Glob.init)
        let typed = try args.string("type").map(FileTypes.globs(for:))
        let types = typed?.globs
        let ws = context.workspace
        let target = try ws.resolve(args.string("path") ?? ".")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            throw ToolFailure("\(args.string("path") ?? ".") does not exist")
        }
        let listed = isDir.boolValue ? await ws.files(under: target, limit: fileLimit) : [ws.relative(target)]

        // Withheld and denied files never reach the engine, and links are followed only inside the workspace.
        var searched: [String] = []
        var withheld = 0, denied = 0, outside = 0
        for rel in listed {
            if let glob, !glob.matches(rel) { continue }
            if let types, !types.contains(where: { $0.matches(rel) }) { continue }
            let url = ws.url(ofListed: rel)
            let real = Workspace.canonical(url)
            // Only files: a folder listed as one entry (a submodule, a nested repository, a link to a folder) would be
            // walked by rg itself, past the withheld and denied filters.
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: real.path, isDirectory: &isFolder), isFolder.boolValue { continue }
            if real.path != url.standardizedFileURL.path, !ws.contains(real), ws.folder(containing: real) == nil {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir), !isDir.boolValue { outside += 1 }
                continue
            }
            if let w = ws.withheld, w.matches(url) || w.matches(real) { withheld += 1; continue }
            if let r = ws.readDenied, r.deniesRead(url) || r.deniesRead(real) { denied += 1; continue }
            searched.append(rel)
        }
        let offset = max(0, args.int("offset") ?? 0)
        let limit = max(1, args.int("head_limit") ?? args.int("limit")
                        ?? (query.mode == .content ? Self.defaultLineLimit : Self.defaultFileLimit))
        // Content mode keeps the lines up to this page's end; the rest are only counted.
        let (hits, complete) = try await GrepEngine.search(searched, root: ws.root, query: query, rg: rg,
                                                           keepLines: query.mode == .content ? offset + limit : nil)

        func files(_ n: Int) -> String { "\(n) file\(n == 1 ? "" : "s")" }
        var notes = typed?.note.map { "\n" + $0 } ?? ""
        if listed.count >= fileLimit {
            notes += "\n[This folder has more files than one search covers: only the first \(fileLimit) files (in path order) were "
                + "searched. Narrow it with path, glob or type.]"
        }
        if withheld > 0 { notes += "\n[\(files(withheld)) withheld from remote models weren't searched.]" }
        if denied > 0 { notes += "\n[\(files(denied)) that permission rules keep from being read weren't searched.]" }
        if outside > 0 { notes += "\n[\(outside) link\(outside == 1 ? "" : "s") to files outside the workspace weren't followed.]" }
        if hits.isEmpty { return ToolOutput(text: "No matches for \(query.pattern)" + notes) }

        let total = hits.reduce(0) { $0 + $1.count }
        let unit = query.multiline ? "match" : "matching line"
        func many(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : (word.hasSuffix("ch") ? "es" : "s"))" }
        let totals = (complete ? "" : "at least ") + "\(many(total, unit)) in \(files(hits.count))"
            + (complete ? "" : "; the search stopped there")

        // The entries to page over: output lines (content), files, or per-file counts.
        var entries: [String] = []
        var groupStarts = Set<Int>()        // content entries that begin a new group (a "--" goes before them)
        switch query.mode {
        case .files: entries = hits.map(\.path)
        case .count: entries = hits.map { "\($0.path): \($0.count)" }
        case .content:
            let withContext = query.before > 0 || query.after > 0
            for h in hits {
                var previous: Int?
                for l in h.lines {
                    if withContext, !entries.isEmpty, previous.map({ l.number != $0 + 1 }) ?? true { groupStarts.insert(entries.count) }
                    let text = l.text.count > Self.maxLineLength ? String(l.text.prefix(Self.maxLineLength)) + "…" : l.text
                    entries.append(l.isMatch ? "\(h.path):\(l.number): \(text)" : "\(h.path)-\(l.number)- \(text)")
                    previous = l.number
                }
            }
        }
        // Lines past the page were counted, not kept.
        let available = entries.count + (query.mode == .content ? hits.reduce(0) { $0 + $1.omittedLines } : 0)
        guard offset < available else {
            return ToolOutput(text: "offset \(offset) is past the end: there are \(available) results (\(totals)).")
        }
        let end = min(entries.count, offset + limit)
        var shown: [String] = []
        for i in offset..<end {
            if i > offset, groupStarts.contains(i) { shown.append("--") }
            shown.append(entries[i])
        }
        var out = shown.joined(separator: "\n")
        var truncated = false
        if query.mode == .count { out += "\nTotal: \(totals)." }
        if offset > 0 || end < available || !complete {
            let what = query.mode == .content ? "lines" : query.mode == .files ? "files" : "counts"
            out += "\n[Showing \(what) \(offset + 1)–\(end) of \(complete ? "" : "at least ")\(available) (\(totals))."
            out += end < available || !complete ? " Use offset=\(end) for more, or narrow with glob, type or path.]" : "]"
            truncated = end < available || !complete
        }
        out += notes
        let (capped, cut) = capOutput(out, maxBytes: context.maxOutputBytes,
                                      hint: "Narrow the search with glob, type or path, or use head_limit and offset.")
        return ToolOutput(text: capped, truncated: truncated || cut)
    }
}
