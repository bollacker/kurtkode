import CryptoKit
import Foundation

/// A system prompt template: text with a small subset of Mustache. `{{name}}` is a variable (left as written when
/// the name is unknown, so a typo shows in the prompt); `{{#name}}…{{/name}}` is kept when the variable is set and
/// not empty, `{{^name}}…{{/name}}` when it isn't; `{{! … }}` is a comment. A line holding only a section tag or a
/// comment is dropped whole, newline included, so sections and comments can sit on lines of their own.
public struct PromptTemplate: Sendable {
    indirect enum Node: Sendable {
        case text(String)
        case variable(String)
        case section(String, inverted: Bool, [Node])
    }

    public struct ParseError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    let nodes: [Node]

    public init(_ source: String) throws {
        nodes = try Self.parse(Self.dropStandaloneLines(Self.tokenize(source)))
    }

    /// The text with `values` filled in. Exactly one final newline is dropped: files end with one, prompts don't.
    public func render(_ values: [String: String]) -> String {
        var out = ""
        Self.render(nodes, values, into: &out)
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    private static func render(_ nodes: [Node], _ values: [String: String], into out: inout String) {
        for node in nodes {
            switch node {
            case .text(let t): out += t
            case .variable(let name): out += values[name] ?? "{{\(name)}}"
            case .section(let name, let inverted, let children):
                if !(values[name] ?? "").isEmpty != inverted { render(children, values, into: &out) }
            }
        }
    }

    enum Token: Equatable {
        case text(String)
        /// `kind`: "#", "^", "/", "!", or nil for a variable.
        case tag(kind: Character?, name: String)
    }

    static func tokenize(_ s: String) throws -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(s)
        while let open = rest.range(of: "{{") {
            if open.lowerBound > rest.startIndex { tokens.append(.text(String(rest[..<open.lowerBound]))) }
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                throw ParseError(description: "a {{ has no closing }}")
            }
            var inner = rest[open.upperBound..<close.lowerBound]
            var kind: Character?
            if let c = inner.first, "#^/!".contains(c) { kind = c; inner = inner.dropFirst() }
            let name = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind != "!" && (name.isEmpty || name.contains(where: { $0.isWhitespace })) {
                throw ParseError(description: "{{\(rest[open.upperBound..<close.lowerBound])}} isn't a variable name")
            }
            tokens.append(.tag(kind: kind, name: name))
            rest = rest[close.upperBound...]
        }
        if !rest.isEmpty { tokens.append(.text(String(rest))) }
        return tokens
    }

    /// Mustache's standalone rule: a section tag or comment alone on its line takes the line with it.
    static func dropStandaloneLines(_ tokens: [Token]) -> [Token] {
        func text(_ i: Int) -> String? {
            guard tokens.indices.contains(i), case .text(let t) = tokens[i] else { return nil }
            return t
        }
        func blank(_ s: Substring) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" } }
        // Cuts decided on the original tokens, then made: [index: (head through its first newline, tail after its last)].
        var cutHead = Set<Int>(), cutTail = Set<Int>()
        for (i, token) in tokens.enumerated() {
            guard case .tag(_?, _) = token else { continue }
            let before: Bool
            if i == 0 { before = true } else if let t = text(i - 1) {
                let tail = t.lastIndex(of: "\n").map { t[t.index(after: $0)...] } ?? t[...]
                before = blank(tail) && (t.contains("\n") || i - 1 == 0)
            } else { before = false }
            let after: Bool
            if i == tokens.count - 1 { after = true } else if let t = text(i + 1) {
                let head = t.firstIndex(of: "\n").map { t[..<$0] } ?? t[...]
                after = blank(head) && (t.contains("\n") || i + 1 == tokens.count - 1)
            } else { after = false }
            if before && after {
                if i > 0 { cutTail.insert(i - 1) }
                if i < tokens.count - 1 { cutHead.insert(i + 1) }
            }
        }
        return tokens.enumerated().map { i, token in
            guard case .text(var t) = token else { return token }
            if cutHead.contains(i) {
                if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) } else { t = "" }
            }
            if cutTail.contains(i) {
                if let nl = t.lastIndex(of: "\n") { t = String(t[...nl]) } else { t = "" }
            }
            return .text(t)
        }
    }

    static func parse(_ tokens: [Token]) throws -> [Node] {
        var stack: [(name: String, inverted: Bool, nodes: [Node])] = [("", false, [])]
        for token in tokens {
            switch token {
            case .text(let t): if !t.isEmpty { stack[stack.count - 1].nodes.append(.text(t)) }
            case .tag(nil, let name): stack[stack.count - 1].nodes.append(.variable(name))
            case .tag("!", _): break
            case .tag(let kind?, let name) where kind == "#" || kind == "^":
                stack.append((name, kind == "^", []))
            case .tag(_, let name):
                guard stack.count > 1, let open = stack.last, open.name == name else {
                    throw ParseError(description: stack.count > 1
                                     ? "{{/\(name)}} closes {{#\(stack[stack.count - 1].name)}}" : "{{/\(name)}} closes nothing")
                }
                stack.removeLast()
                stack[stack.count - 1].nodes.append(.section(open.name, inverted: open.inverted, open.nodes))
            }
        }
        guard stack.count == 1 else { throw ParseError(description: "{{#\(stack[stack.count - 1].name)}} isn't closed") }
        return stack[0].nodes
    }
}

/// Where the system prompt's text comes from: Markdown templates named `intro`, `mode`, and `style-<name>` (one per
/// prompt style), looked up in a project's `.kurtkode/prompts/`, then the user's `~/.kurtkode/prompts/`, then the
/// defaults shipped with kurtkode (AgentCore's `Prompts` resources). SYSTEM_PROMPT.md describes them.
public struct PromptTemplates: Sendable {
    /// Override folders, searched first to last.
    public var overrides: [URL]
    /// The shipped defaults (nil: not found, and the prompt has only what kurtkode adds itself).
    public var defaults: URL?

    public init(overrides: [URL], defaults: URL? = PromptTemplates.defaultsFolder) {
        self.overrides = overrides
        self.defaults = defaults
    }

    /// The project's overrides (when there's a project), then the user's, then the defaults.
    public static func standard(project: URL?) -> PromptTemplates {
        PromptTemplates(overrides: (project.map { [projectFolder($0)] } ?? []) + [userFolder])
    }

    public static var userFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kurtkode/prompts")
    }

    public static func projectFolder(_ root: URL) -> URL { root.appending(path: ".kurtkode/prompts") }

    /// The templates every prompt uses besides its style.
    public static let shared = ["intro", "mode"]

    /// The shipped templates: in the app's resources, beside the command-line binary, or (a build run from its
    /// source tree: tests, `swift run`) in the sources.
    public static let defaultsFolder: URL? = {
        if let u = resourceFolder("Prompts", marker: "intro.md") { return u }
        FileHandle.standardError.write(Data(("kurtkode: the default system prompt templates weren't found (\(bundleName) "
            + "belongs next to the kurtkode binary); prompts have only the environment and instructions.\n").utf8))
        return nil
    }()

    static let bundleName = "AgentCore_AgentCore.bundle"

    /// A folder of AgentCore's resources (`Prompts`, `BuiltinSkills`): in the app's resources, beside the
    /// command-line binary, or (a build run from its source tree) in the sources, where `marker` must exist.
    static func resourceFolder(_ name: String, marker: String) -> URL? {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r) }
        dirs.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() { dirs.append(exe.deletingLastPathComponent()) }
        dirs += Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
        for dir in dirs {
            if let b = Bundle(url: dir.appending(path: bundleName)), let u = b.url(forResource: name, withExtension: nil) {
                return u
            }
        }
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: name)
        return FileManager.default.fileExists(atPath: sources.appending(path: marker).path) ? sources : nil
    }

    /// A template's file, where it was found.
    public struct Source: Sendable {
        public var name: String
        public var url: URL
        public var text: String
        /// From the shipped defaults (not an override).
        public var isDefault: Bool
    }

    /// The file `name` comes from: the first folder that has it.
    public func source(_ name: String) -> Source? {
        for dir in overrides + (defaults.map { [$0] } ?? []) {
            let url = dir.appending(path: name + ".md")
            if let data = try? Data(contentsOf: url) {
                return Source(name: name, url: url, text: String(decoding: data, as: UTF8.self), isDefault: dir == defaults)
            }
        }
        return nil
    }

    /// The shipped text of `name`, if kurtkode ships one.
    public func defaultText(_ name: String) -> String? {
        guard let defaults, let data = try? Data(contentsOf: defaults.appending(path: name + ".md")) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `name` rendered with `values`; an override that doesn't parse gives way to the default. Empty when neither exists.
    public func render(_ name: String, _ values: [String: String]) -> String {
        if let s = source(name), let t = try? PromptTemplate(s.text) { return t.render(values) }
        if let d = defaultText(name), let t = try? PromptTemplate(d) { return t.render(values) }
        return ""
    }

    /// The style names on offer: every `style-<name>.md` in any folder, defaults first.
    public var styles: [String] {
        var names: [String] = []
        for dir in (defaults.map { [$0] } ?? []) + overrides.reversed() {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in files.sorted() where f.hasPrefix("style-") && f.hasSuffix(".md") {
                let n = String(f.dropFirst(6).dropLast(3))
                if PromptStyle(rawValue: n) != nil, !names.contains(n) { names.append(n) }
            }
        }
        return names
    }

    /// Whether `style` has a template anywhere.
    public func has(style: PromptStyle) -> Bool { source("style-" + style.rawValue) != nil }

    /// A short hash of the overrides among `names` whose text differs from the default; empty when there are none,
    /// so a prompt built from the defaults keeps the identity it had before templates existed.
    public func fingerprint(_ names: [String]) -> String {
        let edited = names.compactMap { n -> String? in
            guard let s = source(n), !s.isDefault, s.text != defaultText(n) else { return nil }
            return n + "\u{0}" + s.text
        }
        guard !edited.isEmpty else { return "" }
        return SHA256.hash(data: Data(edited.joined(separator: "\u{1}").utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The user's overrides (Settings, `kurtkode prompts`)

    /// Saves `text` as the user's `name`, after checking it parses; text equal to the default removes the override.
    public static func saveUserOverride(_ name: String, text: String) throws {
        _ = try PromptTemplate(text)
        let url = userFolder.appending(path: name + ".md")
        if PromptTemplates(overrides: []).defaultText(name) == text {
            try resetUserOverride(name)
            return
        }
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Removes the user's `name` (back to the default, or gone for a style kurtkode doesn't ship).
    public static func resetUserOverride(_ name: String) throws {
        let url = userFolder.appending(path: name + ".md")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Whether `name` is a usable template name (lowercase letters, digits, hyphens).
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, first != "-" else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}
