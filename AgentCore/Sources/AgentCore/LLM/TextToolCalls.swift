import Foundation

/// Recovers tool calls a model wrote as plain text instead of structured calls. Only well-formed calls to
/// known tools are taken (a name the agent offered, followed by a JSON object), so prose that happens to
/// mention a tool isn't mistaken for a call.
public enum TextToolCalls {
    /// Returns the calls found and the content with them removed; nil when there are none.
    /// `parameterSchemas` (tool name → its JSON schema) types the raw values of XML-style calls.
    public static func extract(from content: String, knownTools: Set<String>,
                               parameterSchemas: [String: JSONValue] = [:]) -> (calls: [ToolCall], remaining: String)? {
        var calls: [ToolCall] = []
        // A call written inside a code block or a code span is an example the model quotes, not one it makes.
        var remaining = neutralizingQuoted(content)
        // Mistral: [TOOL_CALLS]name{json}, [TOOL_CALLS]name [ARGS]{json}, or [TOOL_CALLS][{"name":..,"arguments":..}]
        while let r = remaining.range(of: "[TOOL_CALLS]") {
            var rest = remaining[r.upperBound...].drop { $0 == " " }
            var removedEnd = rest.startIndex
            if rest.first == "[" , let (json, end) = jsonValue(rest), case .array(let list) = json {
                for item in list { if let c = call(fromObject: item, known: knownTools, index: calls.count) { calls.append(c) } }
                removedEnd = end
            } else {
                let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                rest = rest.dropFirst(name.count).drop { $0 == " " }
                if rest.hasPrefix("[ARGS]") { rest = rest.dropFirst(6).drop { $0 == " " } }
                guard knownTools.contains(name), let (json, end) = jsonValue(rest), case .object = json else { break }
                calls.append(ToolCall(id: "text_\(calls.count)", name: name, arguments: encode(json)))
                removedEnd = end
            }
            remaining.removeSubrange(r.lowerBound..<removedEnd)
        }
        // Qwen3-Coder style, seen from OpenRouter as plain text (the opening <tool_call> sometimes missing):
        // <tool_call><function=name><parameter=p>value</parameter>...</function></tool_call>
        while let fn = remaining.range(of: "<function="),
              let nameEnd = remaining.range(of: ">", range: fn.upperBound..<remaining.endIndex),
              let close = remaining.range(of: "</function>", range: nameEnd.upperBound..<remaining.endIndex) {
            let name = String(remaining[fn.upperBound..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard knownTools.contains(name) else { break }
            let args = xmlParameters(remaining[nameEnd.upperBound..<close.lowerBound], schema: parameterSchemas[name])
            calls.append(ToolCall(id: "text_\(calls.count)", name: name, arguments: encode(.object(args))))
            var start = fn.lowerBound, end = close.upperBound
            let before = remaining[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
            if before.hasSuffix("<tool_call>"), let r = remaining.range(of: "<tool_call>", options: .backwards, range: remaining.startIndex..<start) {
                start = r.lowerBound
            }
            let after = remaining[end...].drop { $0.isWhitespace }
            if after.hasPrefix("</tool_call>") { end = remaining.index(after.startIndex, offsetBy: "</tool_call>".count) }
            remaining.removeSubrange(start..<end)
        }
        // Hermes / Qwen 2.5 style: <tool_call>{"name": ..., "arguments": {...}}</tool_call>
        while let open = remaining.range(of: "<tool_call>"), let close = remaining.range(of: "</tool_call>", range: open.upperBound..<remaining.endIndex) {
            let inner = remaining[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = try? JSONDecoder().decode(JSONValue.self, from: Data(inner.utf8)),
               let c = call(fromObject: v, known: knownTools, index: calls.count) {
                calls.append(c)
            }
            remaining.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // Gemma 4 style, seen from LM Studio as text: [<|tool_call>call:]name{key:<|"|>text<|"|>, n:3, list:[<|"|>a<|"|>]}[<tool_call|>]
        if remaining.contains(gemmaQuote) {
            for name in knownTools.sorted(by: { $0.count > $1.count }) {
                while let r = remaining.range(of: name + "{"), let (json, end) = gemmaObject(remaining[remaining.index(before: r.upperBound)...]) {
                    calls.append(ToolCall(id: "text_\(calls.count)", name: name, arguments: encode(json)))
                    var start = r.lowerBound, stop = end
                    for prefix in ["<|tool_call>call:", "call:"] where remaining[..<start].hasSuffix(prefix) {
                        start = remaining.index(start, offsetBy: -prefix.count)
                        break
                    }
                    if remaining[stop...].hasPrefix("<tool_call|>") { stop = remaining.index(stop, offsetBy: "<tool_call|>".count) }
                    remaining.removeSubrange(start..<stop)
                }
            }
        }
        guard !calls.isEmpty else { return nil }
        return (calls, remaining.replacingOccurrences(of: String(quoteMark), with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Gemma 4's string delimiter in its text tool calls.
    static let gemmaQuote = "<|\"|>"

    /// The Gemma-style object starting at `s` (`{` first), as JSON: bare keys quoted, `<|"|>`-delimited strings
    /// escaped. Returns the value and where the object ends; nil when it isn't one.
    static func gemmaObject(_ s: Substring) -> (JSONValue, String.Index)? {
        guard s.first == "{" else { return nil }
        var json = ""
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            if s[i...].hasPrefix(gemmaQuote) {
                let open = s.index(i, offsetBy: gemmaQuote.count)
                guard let close = s.range(of: gemmaQuote, range: open..<s.endIndex) else { return nil }
                json += encode(.string(String(s[open..<close.lowerBound])))
                i = close.upperBound
                continue
            }
            let c = s[i]
            if c == "{" || c == "[" { depth += 1 }
            if c == "}" || c == "]" { depth -= 1 }
            if c.isLetter || c == "_", let prev = json.last(where: { !$0.isWhitespace }), prev == "{" || prev == "," {
                // A bare key: quote it.
                let key = s[i...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                json += encode(.string(String(key)))
                i = s.index(i, offsetBy: key.count)
                continue
            }
            json.append(c)
            i = s.index(after: i)
            if depth == 0 {
                guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), case .object = v else { return nil }
                return (v, i)
            }
        }
        return nil
    }

    /// Put after a quoted marker's first character so the extraction doesn't see it (removed again afterwards).
    static let quoteMark: Character = "\u{E000}"
    static let markers = ["<tool_call>", "<function=", "[TOOL_CALLS]"]

    /// `content` with each call marker that sits inside a fenced code block or an inline code span broken by
    /// `quoteMark`. Real calls are skipped whole, so fences inside their arguments (a Markdown file's content) don't
    /// count.
    static func neutralizingQuoted(_ content: String) -> String {
        guard markers.contains(where: { content.contains($0) }), content.contains("`") || content.contains("~~~") else { return content }
        var out = ""
        var i = content.startIndex
        var inFence: String?            // the fence that opened the block
        var inSpan = false
        var lineStart = true
        while i < content.endIndex {
            let rest = content[i...]
            if lineStart {
                let trimmed = rest.drop { $0 == " " }
                if let fence = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                    if inFence == nil { inFence = fence; inSpan = false } else if inFence == fence { inFence = nil }
                    let eol = rest.firstIndex(of: "\n") ?? content.endIndex
                    out += content[i..<eol]
                    i = eol
                    continue
                }
            }
            if let m = markers.first(where: { rest.hasPrefix($0) }) {
                if inFence != nil || inSpan {
                    out.append(m.first!)
                    out.append(quoteMark)
                    out += m.dropFirst()
                    i = content.index(i, offsetBy: m.count)
                    lineStart = false
                    continue
                }
                // A real call: copied as it is, up to its end.
                let end = callEnd(rest, marker: m)
                out += content[i..<end]
                i = end
                lineStart = end > content.startIndex && content[content.index(before: end)] == "\n"
                continue
            }
            let c = content[i]
            if c == "`", inFence == nil { inSpan.toggle() }
            if c == "\n" {
                lineStart = true
                if rest.dropFirst().first == "\n" { inSpan = false }     // a blank line ends a code span
            } else {
                lineStart = false
            }
            out.append(c)
            i = content.index(after: i)
        }
        return out
    }

    /// Where a call that starts `rest` with `marker` ends.
    static func callEnd(_ rest: Substring, marker: String) -> String.Index {
        switch marker {
        case "<tool_call>": return rest.range(of: "</tool_call>")?.upperBound ?? rest.endIndex
        case "<function=":
            guard let close = rest.range(of: "</function>") else { return rest.endIndex }
            let after = rest[close.upperBound...].drop { $0.isWhitespace }
            return after.hasPrefix("</tool_call>") ? rest.index(after.startIndex, offsetBy: "</tool_call>".count) : close.upperBound
        default:
            var body = rest.dropFirst(marker.count).drop { $0 == " " }
            if body.first != "[" { body = body.drop { $0.isLetter || $0.isNumber || $0 == "_" }.drop { $0 == " " } }
            if body.hasPrefix("[ARGS]") { body = body.dropFirst(6).drop { $0 == " " } }
            return jsonValue(body)?.1 ?? (rest.firstIndex(of: "\n") ?? rest.endIndex)
        }
    }

    /// Repairs a tool name that has text glued onto its front. Seen with Devstral on LM Studio: the model
    /// repeats the previous tool result and the server folds it into the name
    /// ("Todo list updated (4/14 completed).[TOOL_CALLS]read_file", "Todo_list_updated_8_14_completed_TOOL_CALLS_read_file").
    /// Returns a known tool only when the name ends with it at a word boundary; otherwise nil.
    public static func repairName(_ name: String, known: Set<String>) -> String? {
        guard !known.contains(name) else { return name }
        if let r = name.range(of: "[TOOL_CALLS]", options: .backwards) {
            let tail = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if known.contains(tail) { return tail }
        }
        for tool in known.sorted(by: { $0.count > $1.count }) where name.hasSuffix(tool) {
            let before = name.dropLast(tool.count)
            if before.isEmpty || before.last == "_" || before.last == " " || before.last == "]" || before.last == "." { return tool }
        }
        return nil
    }

    /// `<parameter=p>value</parameter>` pairs. A value loses the one newline on each side that the format
    /// puts there; its type comes from the tool's schema (strings stay verbatim, which edits depend on).
    static func xmlParameters(_ body: Substring, schema: JSONValue?) -> [String: JSONValue] {
        var types: [String: String] = [:]
        if case .object(let o)? = schema, case .object(let props)? = o["properties"] {
            for (k, v) in props { if case .object(let p) = v, case .string(let t)? = p["type"] { types[k] = t } }
        }
        var out: [String: JSONValue] = [:]
        var rest = body
        while let open = rest.range(of: "<parameter="), let nameEnd = rest.range(of: ">", range: open.upperBound..<rest.endIndex),
              let close = rest.range(of: "</parameter>", range: nameEnd.upperBound..<rest.endIndex) {
            let key = String(rest[open.upperBound..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            var value = rest[nameEnd.upperBound..<close.lowerBound]
            if value.first == "\n" { value = value.dropFirst() }
            if value.last == "\n" { value = value.dropLast() }
            let text = String(value)
            switch types[key] {
            case "string", nil: out[key] = .string(text)
            default:
                let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
                out[key] = parsed ?? .string(text)
            }
            rest = rest[close.upperBound...]
        }
        return out
    }

    static func call(fromObject v: JSONValue, known: Set<String>, index: Int) -> ToolCall? {
        guard case .object(let o) = v, case .string(let name)? = o["name"], known.contains(name) else { return nil }
        var args = o["arguments"] ?? o["parameters"] ?? .object([:])
        if case .string(let s) = args, let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) { args = parsed }
        return ToolCall(id: "text_\(index)", name: name, arguments: encode(args))
    }

    /// Sorted keys, so the same call always encodes the same way.
    static func encode(_ v: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// Parses the JSON value at the start of `s` by matching brackets (strings respected). Returns the value
    /// and where it ends.
    static func jsonValue(_ s: Substring) -> (JSONValue, String.Index)? {
        guard let first = s.first, first == "{" || first == "[" else { return nil }
        var depth = 0, inString = false, escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if inString {
                if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else if ch == "\"" { inString = true }
            else if ch == "{" || ch == "[" { depth += 1 }
            else if ch == "}" || ch == "]" {
                depth -= 1
                if depth == 0 {
                    let end = s.index(after: i)
                    guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(s[s.startIndex..<end].utf8)) else { return nil }
                    return (v, end)
                }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
