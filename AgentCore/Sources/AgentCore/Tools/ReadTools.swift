import Foundation

/// The read-only tool set (Phase 2).
public enum ReadTools {
    public static let all: [any Tool] = [ReadFileTool(), ListDirTool(), GlobTool(), GrepTool()]
}

/// Every tool; the permission policy decides which are offered and which ask first.
public enum AllTools {
    public static let all: [any Tool] = ReadTools.all + [TodoWriteTool(), EditFileTool(), WriteFileTool(), BashTool(), WebFetchTool()]

    /// A built-in tool by name, including the ones the loop adds when they apply (for labels and icons).
    public static func named(_ name: String) -> (any Tool)? {
        all.first { $0.name == name } ?? ([SkillTool(skills: []), AskUserTool(), ApplyPatchTool()] + BackgroundTools.all as [any Tool]).first { $0.name == name }
    }
}

public struct ReadFileTool: Tool {
    public init() {}
    public let name = "read_file"
    public let description = """
        Read a file from the project: text, an image (when the model can see images), or a PDF (pages: a page or range). \
        Text comes as lines prefixed with their line numbers. \
        Reads up to 2000 lines, fewer when they don't fit the output size; the result says where to continue. \
        For long files, read a range with offset (first line, 1-based) and limit (number of lines).
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "path": ["type": "string", "description": "File path, relative to the project root."],
            "offset": ["type": "integer", "description": "First line to read, 1-based. Default 1."],
            "limit": ["type": "integer", "description": "Maximum lines to read. Default 2000."],
            "pages": ["type": "string", "description": "For a PDF: a page or range, like 3 or 2-5. Leave it out for the whole file."],
        ],
        "required": ["path"],
    ]
    public let risk = ToolRisk.read
    static let maxLineLength = 1000
    static let maxFileBytes = 200_000_000
    /// Lines read when the call gives no limit (Claude Code's default). The output size usually stops it sooner.
    static let defaultLimit = 2000

    public func summary(_ args: ToolArguments) -> String {
        var s = "Read \(args.string("path") ?? "?")"
        if let o = args.int("offset") {
            s += " from line \(o)"
            if let l = args.int("limit") { s += "–\(o + l - 1)" }
        }
        return s
    }

    private func readPDF(_ data: Data, path: String, args: ToolArguments, context: ToolContext) throws -> ToolOutput {
        let (text, count) = try PDFText.extract(data, pages: args.string("pages"))
        let room = max(1000, context.maxOutputBytes - 200)
        guard text.utf8.count > room else { return ToolOutput(text: text) }
        var shown = String(decoding: Array(text.utf8.prefix(room)), as: UTF8.self)
        while shown.last == "\u{FFFD}" { shown.removeLast() }
        // The page's own number, from its heading: a range doesn't start at 1.
        let page = shown.components(separatedBy: "--- page ").last.flatMap { Int($0.prefix { $0.isNumber }) } ?? 1
        return ToolOutput(text: shown + "\n\n[\(path) has \(count) pages. Cut in page \(page): use pages to read on, like \"\(page)-\(min(count, page + 9))\".]", truncated: true)
    }

    /// An image file, as an image for the model when it can see them.
    private func readImage(_ data: Data, path: String, context: ToolContext) throws -> ToolOutput? {
        guard ImageStore.isImage(data) else { return nil }
        guard let dir = context.imagesDirectory, context.acceptsImages else {
            throw ToolFailure("\(path) is an image, and this model can't see images (\(data.count) bytes)")
        }
        let image = try ImageStore.save(data, in: dir)
        var out = ToolOutput(text: "\(path): an image, \(image.width)×\(image.height). It's in the next message.")
        out.images = [image]
        return out
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let path = try args.require("path")
        let url = try context.workspace.resolve(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ToolFailure("\(path) does not exist")
        }
        if isDir.boolValue { throw ToolFailure("\(path) is a directory; use list_dir") }
        // Before it's read: a pipe never ends, and all of a huge file goes into memory.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else { throw ToolFailure("\(path) isn't a regular file") }
        if let size = attributes?[.size] as? Int, size > Self.maxFileBytes {
            throw ToolFailure("\(path) is \(size / 1_000_000) MB, too big to read here. Search it with grep, or take a part with sed or head in bash.")
        }
        let data = try Data(contentsOf: url)
        if data.starts(with: Array("%PDF".utf8)) { return try readPDF(data, path: path, args: args, context: context) }
        if let output = try readImage(data, path: path, context: context) { return output }
        if looksBinary(data) { throw ToolFailure("\(path) is a binary file (\(data.count) bytes)") }
        let text = String(decoding: data, as: UTF8.self)
        if text.isEmpty { return ToolOutput(text: "(\(path) is empty)") }

        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let offset = max(1, args.int("offset") ?? 1)
        let limit = max(1, args.int("limit") ?? Self.defaultLimit)
        guard offset <= lines.count else {
            throw ToolFailure("offset \(offset) is past the end of \(path) (\(lines.count) lines)")
        }
        context.reads?.record(url)
        var end = min(lines.count, offset - 1 + limit)
        let width = String(end).count
        var out = ""
        // Whole lines up to the output size, so a long file stops at a line boundary with a note saying where to go
        // on (not cut mid-line with a "truncated" marker). Room is kept for that note.
        let room = context.maxOutputBytes - 200
        var bytes = 0
        for n in offset...end {
            var line = lines[n - 1]
            if line.count > Self.maxLineLength { line = String(line.prefix(Self.maxLineLength)) + " […line truncated]" }
            let numbered = String(repeating: " ", count: width - String(n).count) + "\(n)\t\(line)\n"
            let size = numbered.utf8.count
            if n > offset, bytes + size > room { end = n - 1; break }
            out += numbered
            bytes += size
        }
        var truncated = false
        if end < lines.count {
            out += "\n[Showing lines \(offset)–\(end) of \(lines.count). Use offset=\(end + 1) to read more.]"
            truncated = true
        }
        let (capped, cut) = capOutput(out, maxBytes: context.maxOutputBytes,
                                      hint: "Read a smaller range with offset and limit.")
        return ToolOutput(text: capped, truncated: truncated || cut)
    }
}

public struct ListDirTool: Tool {
    public init() {}
    public let name = "list_dir"
    public let description = "List the files and folders in a project directory. Folders end with /."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": ["path": ["type": "string", "description": "Directory, relative to the project root. Default \".\"."]],
    ]
    public let risk = ToolRisk.read
    static let maxEntries = 400

    public func summary(_ args: ToolArguments) -> String { "List \(args.string("path") ?? ".")" }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let path = args.string("path") ?? "."
        let url = try context.workspace.resolve(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ToolFailure("\(path) does not exist")
        }
        guard isDir.boolValue else { throw ToolFailure("\(path) is a file; use read_file") }
        let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            .filter { $0.lastPathComponent != ".DS_Store" }
        var dirs: [String] = [], files: [String] = []
        for item in items {
            let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if v?.isDirectory == true {
                let name = item.lastPathComponent
                dirs.append(Workspace.defaultIgnores.contains(name) ? "\(name)/  (ignored)" : "\(name)/")
            } else {
                files.append("\(item.lastPathComponent)  (\(Self.size(v?.fileSize ?? 0)))")
            }
        }
        let all = dirs.sorted() + files.sorted()
        if all.isEmpty { return ToolOutput(text: "(\(path) is empty)") }
        var out = all.prefix(Self.maxEntries).joined(separator: "\n")
        let truncated = all.count > Self.maxEntries
        if truncated { out += "\n[\(all.count - Self.maxEntries) more entries not shown. Use glob to search.]" }
        return ToolOutput(text: out, truncated: truncated)
    }

    static func size(_ bytes: Int) -> String {
        switch bytes {
        case ..<1024: "\(bytes) B"
        case ..<(1024 * 1024): String(format: "%.1f KB", Double(bytes) / 1024)
        default: String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
    }
}

public struct GlobTool: Tool {
    public init() {}
    public let name = "glob"
    public let description = """
        Find files by name pattern, e.g. "**/*.swift" or "src/**/test_*.py". A pattern without a slash \
        matches file names at any depth. Honors .gitignore. Returns paths relative to the project root, \
        most recently modified first.
        """
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "pattern": ["type": "string", "description": "Glob pattern."],
            "path": ["type": "string", "description": "Directory to search in. Default: the project root."],
        ],
        "required": ["pattern"],
    ]
    public let risk = ToolRisk.read
    static let maxResults = 300

    public func summary(_ args: ToolArguments) -> String {
        "Find \(args.string("pattern") ?? "?")" + (args.string("path").map { " in \($0)" } ?? "")
    }

    public func run(_ args: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let pattern = try args.require("pattern")
        let dir = try context.workspace.resolve(args.string("path") ?? ".")
        let dirRel = context.workspace.relative(dir)
        let glob = try Glob(pattern)
        let prefix = dirRel == "." ? "" : dirRel + "/"
        let found = await context.workspace.files(under: dir)
            .filter { glob.matches(prefix.isEmpty ? $0 : String($0.dropFirst(prefix.count))) }
        // Newest first (as Claude Code's glob): the files a task is about are usually the ones changed lately, and
        // they survive the cut at maxResults. Ties by path, so a result is stable.
        let dated = found.map { rel in
            (rel, (try? context.workspace.url(ofListed: rel).resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast)
        }
        let matches = dated.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.0)
        if matches.isEmpty { return ToolOutput(text: "No files match \(pattern)" + (prefix.isEmpty ? "" : " in \(dirRel)")) }
        var out = matches.prefix(Self.maxResults).joined(separator: "\n")
        let truncated = matches.count > Self.maxResults
        if truncated { out += "\n[\(matches.count - Self.maxResults) more matches not shown. Use a narrower pattern.]" }
        return ToolOutput(text: out, truncated: truncated)
    }
}
