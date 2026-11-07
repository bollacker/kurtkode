import Foundation

// Google's Gemini API (`models/{model}:streamGenerateContent?alt=sse`): request encoding and streamed-chunk decoding.
//
// Spoken natively so thought summaries come back (`includeThoughts`) and thought signatures round-trip: Gemini 3
// rejects a function call sent back without the signature it came with. Each reply's parts are kept on the message
// (`NativeContent`) and sent back unchanged while the message still matches them and the same model is asked.

enum GeminiWire {
    /// Stands in for a signature on a function call Gemini didn't write (another model's, or one the loop changed);
    /// the API documents it for history it can't validate.
    static let skipSignature = "skip_thought_signature_validator"

    /// Gemini 2.x and earlier set thinking with a token budget and don't need signatures; later models take levels.
    static func isBudgetModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("gemini-1") || m.contains("gemini-2")
    }

    static func encodeRequest(_ r: ChatRequest) throws -> Data {
        var system: [String] = []
        var rest = r.messages[...]
        while let first = rest.first, first.role == .system {
            if !first.content.isEmpty { system.append(first.content) }
            rest = rest.dropFirst()
        }
        var generation: [String: JSONValue] = ["maxOutputTokens": .number(Double(r.maxTokens))]
        if let t = r.temperature { generation["temperature"] = .number(t) }
        var thinking: [String: JSONValue] = ["includeThoughts": true]
        let effort = r.reasoningEffort?.lowercased()
        if isBudgetModel(r.model) {
            let budgets = ["none": 0, "minimal": 512, "low": 1024, "medium": 8192, "high": 24576, "xhigh": 24576, "max": 32768]
            if let e = effort, var b = budgets[e] {
                // Each 2.5 model takes its own range: Pro can't turn thinking off (128 at least, 32768 at most; 0 is
                // rejected), Flash tops out at 24576, and Flash-Lite thinks with 512 or more, or not at all (0).
                let m = r.model.lowercased()
                if m.contains("gemini-2.5") {
                    if m.contains("pro") { b = max(128, b) }
                    else { b = min(24576, b) }
                }
                thinking["thinkingBudget"] = .number(Double(b))
                if b == 0 { thinking["includeThoughts"] = false }
            }
        } else if let e = effort {
            let pro = r.model.lowercased().contains("pro")
            let levels = ["none": pro ? "low" : "minimal", "minimal": pro ? "low" : "minimal", "low": "low",
                          "medium": "medium", "high": "high", "xhigh": "high", "max": "high"]
            if let level = levels[e] { thinking["thinkingLevel"] = .string(level) }
        }
        generation["thinkingConfig"] = .object(thinking)
        var body: [String: JSONValue] = [
            "contents": .array(encodeContents(Array(rest), model: r.model, images: r.sendImages)),
            "generationConfig": .object(generation),
        ]
        if !system.isEmpty { body["systemInstruction"] = ["parts": [["text": .string(system.joined(separator: "\n\n"))]]] }
        var tools: [JSONValue] = []
        if !r.tools.isEmpty {
            // `parametersJsonSchema` takes full JSON Schema (MCP tools use keywords `parameters` rejects).
            tools.append(["functionDeclarations": .array(r.tools.map { t in
                ["name": .string(t.name), "description": .string(t.description), "parametersJsonSchema": t.parameters]
            })])
        }
        // Grounding with Google Search: the server searches when it helps (billed per search by Google).
        if r.webSearch {
            tools.append(["googleSearch": .object([:])])
            // Required to combine a built-in tool with function calling (HTTP 400 otherwise); the server's own tool
            // calls then come back as parts, kept and sent back like the rest.
            if !r.tools.isEmpty { body["toolConfig"] = ["includeServerSideToolInvocations": true] }
        }
        if let t = r.forcedTool, r.tools.contains(where: { $0.name == t }) {
            var config: [String: JSONValue] = { if case .object(let o)? = body["toolConfig"] { o } else { [:] } }()
            config["functionCallingConfig"] = ["mode": "ANY", "allowedFunctionNames": [.string(t)]]
            body["toolConfig"] = .object(config)
        }
        if !tools.isEmpty { body["tools"] = .array(tools) }
        return try NativeWire.encoder().encode(JSONValue.object(body))
    }

    /// Contents with roles `user` and `model`. Tool results become `functionResponse` parts in a user turn, and
    /// consecutive turns of one role merge: a reply's results go back together, after all of its calls.
    static func encodeContents(_ messages: [ChatMessage], model: String, images: Bool) -> [JSONValue] {
        var turns: [(role: String, parts: [JSONValue])] = []
        func add(_ role: String, _ parts: [JSONValue]) {
            guard !parts.isEmpty else { return }
            if turns.last?.role == role { turns[turns.count - 1].parts += parts } else { turns.append((role, parts)) }
        }
        var callNames: [String: String] = [:]
        var serverIDs = Set<String>()          // call ids Gemini gave (sent back with their responses)
        for m in messages {
            switch m.role {
            case .system:
                add("user", [["text": .string("[System] " + m.content)]])
            case .user:
                var parts: [JSONValue] = []
                var note = ""
                if let attached = m.images, !attached.isEmpty {
                    if images {
                        for image in attached {
                            if let (type, data) = NativeWire.imageData(image) {
                                parts.append(["inlineData": ["mimeType": .string(type), "data": .string(data)]])
                            } else {
                                parts.append(["text": .string(NativeWire.missingImage)])
                            }
                        }
                    } else {
                        note = NativeWire.imageNote(attached.count)
                    }
                }
                let words = [m.content, note].filter { !$0.isEmpty }.joined(separator: "\n\n")
                if !words.isEmpty { parts.append(["text": .string(words)]) }
                add("user", parts)
            case .tool:
                let id = m.toolCallID ?? ""
                var response: [String: JSONValue] = ["name": .string(callNames[id] ?? "unknown"),
                                                     "response": ["output": .string(m.content)]]
                if serverIDs.contains(id) { response["id"] = .string(id) }
                add("user", [["functionResponse": .object(response)]])
            case .assistant:
                let parts = modelParts(m, model: model)
                for c in m.toolCalls { callNames[c.id] = c.name }
                for case .object(let p) in parts {
                    if case .object(let fc)? = p["functionCall"], let id = NativeWire.string(fc["id"]) { serverIDs.insert(id) }
                }
                add("model", parts)
            }
        }
        if turns.first?.role == "model" { turns.insert(("user", [["text": "(The conversation continues.)"]]), at: 0) }
        return turns.map { ["role": .string($0.role), "parts": .array($0.parts)] }
    }

    /// A reply's parts: as returned (with their signatures) while they still match the message and the same model is
    /// asked; otherwise rebuilt, with the stand-in signature on each step's first call.
    static func modelParts(_ m: ChatMessage, model: String) -> [JSONValue] {
        if let n = m.native, n.api == .gemini, n.model == model, case .array(let parts) = n.blocks, matches(parts, m) {
            return parts
        }
        var out: [JSONValue] = []
        if !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(["text": .string(m.content)]) }
        for (i, c) in m.toolCalls.enumerated() {
            var part: [String: JSONValue] = ["functionCall": ["name": .string(c.name), "args": NativeWire.argumentsObject(c.arguments)]]
            if i == 0, !isBudgetModel(model) { part["thoughtSignature"] = .string(skipSignature) }
            out.append(.object(part))
        }
        return out
    }

    static func matches(_ parts: [JSONValue], _ m: ChatMessage) -> Bool {
        var text = ""
        var calls: [[String: JSONValue]] = []
        for case .object(let p) in parts {
            if case .object(let fc)? = p["functionCall"] { calls.append(fc); continue }
            if p["thought"] == .bool(true) { continue }
            text += NativeWire.string(p["text"]) ?? ""
        }
        guard text == m.content, calls.count == m.toolCalls.count else { return false }
        return zip(calls, m.toolCalls).allSatisfy { fc, c in
            NativeWire.string(fc["name"]) == c.name && NativeWire.sameArguments(c.arguments, fc["args"] ?? .object([:]))
        }
    }
}

/// Folds Gemini's streamed `GenerateContentResponse` chunks into events, and assembles the reply's parts (streamed text
/// merged into one part per run, signatures kept on the part they came with).
struct GeminiStreamDecoder: StreamDecoder {
    let requestedModel: String
    var finished = false
    private var model: String?
    private var parts: [[String: JSONValue]] = []
    private var calls = 0
    private var finishReason: String?
    private var usage: Usage?
    private var notes: [String] = []
    private var thoughtRuns = 0
    private var searched: [String] = []
    private var responseID: String?
    /// Finish reasons that mean the reply was refused, not lost or cut.
    static let declinedReasons: Set<String> = ["BLOCKED", "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII",
                                               "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT"]

    init(requestedModel: String) { self.requestedModel = requestedModel }

    mutating func decode(_ payload: Data) throws -> [StreamEvent] {
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: payload) else { return [] }
        var out: [StreamEvent] = []
        if case .object(let e)? = o["error"] {
            throw ChatError.server(NativeWire.string(e["message"]) ?? "The server reported an error mid-reply.")
        }
        if let id = NativeWire.string(o["responseId"]), id != responseID {
            responseID = id
            out.append(.requestID(id))
        }
        if model == nil, let m = NativeWire.string(o["modelVersion"]) {
            model = m
            out.append(.model(m))
        }
        if case .object(let f)? = o["promptFeedback"], let reason = NativeWire.string(f["blockReason"]) {
            notes.append("Gemini blocked the prompt (\(reason)).")
            finishReason = finishReason ?? "BLOCKED"
            finished = true
        }
        if case .array(let candidates)? = o["candidates"], case .object(let c)? = candidates.first {
            if case .object(let content)? = c["content"], case .array(let ps)? = content["parts"] {
                for case .object(let p) in ps { out += take(p) }
            }
            if case .object(let g)? = c["groundingMetadata"], case .array(let qs)? = g["webSearchQueries"] {
                let queries = qs.compactMap { NativeWire.string($0) }.filter { !searched.contains($0) }
                if !queries.isEmpty {
                    searched += queries
                    out.append(.note("Searched the web: " + queries.joined(separator: "; ")))
                }
            }
            if let reason = NativeWire.string(c["finishReason"]) {
                finishReason = reason
                finished = true
            }
        }
        if case .object(let u)? = o["usageMetadata"] {
            let thoughts = NativeWire.int(u["thoughtsTokenCount"]) ?? 0
            // `cachedContentTokenCount`: the part of the prompt served from the (implicit) cache.
            // `toolUsePromptTokenCount`: the prompt tokens of tool results (Google Search, URL context) the server added.
            usage = Usage(promptTokens: (NativeWire.int(u["promptTokenCount"]) ?? 0) + (NativeWire.int(u["toolUsePromptTokenCount"]) ?? 0),
                          completionTokens: (NativeWire.int(u["candidatesTokenCount"]) ?? 0) + thoughts,
                          reasoningTokens: thoughts, cacheReadTokens: NativeWire.int(u["cachedContentTokenCount"]) ?? 0)
            // Usage comes with every chunk: count it as it goes, so a reply cut off still counts its input.
            if !searched.isEmpty { usage!.webSearches = searched.count }
            out.append(.usageRaw(.object(u)))
            out.append(.usage(priced(usage!)))
        }
        return out
    }

    private mutating func take(_ p: [String: JSONValue]) -> [StreamEvent] {
        if case .object(let fc)? = p["functionCall"] {
            parts.append(p)
            defer { calls += 1 }
            return [.toolCallDelta(index: calls, id: NativeWire.string(fc["id"]), name: NativeWire.string(fc["name"]),
                                   arguments: NativeWire.text(fc["args"] ?? .object([:])))]
        }
        guard let text = NativeWire.string(p["text"]) else {
            parts.append(p)
            return []
        }
        let thought = p["thought"] == .bool(true)
        let signature = p["thoughtSignature"]
        var startsRun = true
        if var last = parts.last, last["functionCall"] == nil, let lastText = NativeWire.string(last["text"]),
           (last["thought"] == .bool(true)) == thought, last["thoughtSignature"] == nil {
            last["text"] = .string(lastText + text)
            if let signature { last["thoughtSignature"] = signature }
            parts[parts.count - 1] = last
            startsRun = false
        } else {
            parts.append(p)
        }
        guard !text.isEmpty else { return [] }
        if !thought { return [.content(text)] }
        if startsRun { thoughtRuns += 1 }
        return [.reasoning(startsRun && thoughtRuns > 1 ? "\n\n" + text : text)]
    }

    private func priced(_ u: Usage) -> Usage {
        var usage = u
        if let c = PriceList.cost(usage, api: .gemini, model: requestedModel) {
            usage.cost = c
            usage.costIsEstimate = true
        }
        return usage
    }

    mutating func end() -> [StreamEvent] {
        var out: [StreamEvent] = notes.map(StreamEvent.note)
        switch finishReason {
        case "STOP"?: out.append(.finish(calls > 0 ? .toolCalls : .stop))
        case "MAX_TOKENS"?: out.append(.finish(.length))
        case let r?:
            if r != "BLOCKED" { out.append(.note("Gemini stopped the reply: \(r).")) }
            if Self.declinedReasons.contains(r) { out.append(.declined) }
            out.append(.finish(.other))
        case nil: break
        }
        if let usage { out.append(.usage(priced(usage))) }
        if !parts.isEmpty {
            // Kept under the id asked for (signatures are checked against the model requests name, which may be an
            // alias of the version that answered).
            out.append(.native(NativeContent(api: .gemini, model: requestedModel, blocks: .array(parts.map(JSONValue.object)))))
        }
        return out
    }
}
