import Foundation

/// What a replay changes in the recorded request. Nil leaves the recorded value.
public struct ReplayOptions: Codable, Sendable, Hashable {
    /// The model to ask (the request's `model`).
    public var model: String
    public var temperature: Double?
    /// `reasoning_effort` to send; "" removes it (the model's default).
    public var reasoningEffort: String?
    /// Replaces the system prompt's text.
    public var systemPrompt: String?
    /// Keep the recorded OpenRouter `provider` preferences (only meaningful on the same endpoint).
    public var keepProvider: Bool

    public init(model: String, temperature: Double? = nil, reasoningEffort: String? = nil, systemPrompt: String? = nil,
                keepProvider: Bool = false) {
        self.model = model
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.systemPrompt = systemPrompt
        self.keepProvider = keepProvider
    }
}

/// One replay of a recorded turn: where it went, what was changed, the reply, and the wire record.
public struct ReplayRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The session reply whose request was replayed.
    public var sourceReply: UUID
    public var startedAt: Date
    public var endpointName: String
    public var endpointID: UUID?
    public var options: ReplayOptions
    /// The reply as it came back (content, reasoning, tool calls, meta with tokens and times). Tools weren't run.
    public var reply: ChatMessage
    /// The request as sent and the raw response.
    public var wire: WireRecord
    /// What couldn't be replayed as recorded (images left out of the record, …).
    public var warnings: [String]
    /// What the replay cost (`purpose: replay`, outside any run). Replays are kept beside the wire log, not in the
    /// session file, so a session's spending is its `cost` records plus its replays' entries.
    public var cost: CostEntry?
}

/// How a replay's reply differs from the original.
public struct ReplayComparison: Sendable, Hashable {
    public var sameToolCalls: Bool
    /// One line per call that differs: "read_file: path src/a.swift → src/b.swift", "+ grep {…}", "- edit_file {…}".
    public var toolCallDifferences: [String]
    public var sameText: Bool
    public var original: Figures
    public var replay: Figures

    public struct Figures: Sendable, Hashable {
        public var promptTokens: Int?
        public var completionTokens: Int?
        public var reasoningTokens: Int?
        public var timeToFirstToken: Double?
        public var duration: Double?
        public var stop: String
    }
}

public enum Replay {
    /// The recorded request with `options` applied, ready to send in the format it was recorded in. `api` is the
    /// format of the server it goes to (default: the recorded one); a request can't be replayed in another format.
    public static func body(from record: WireRecord, options: ReplayOptions, api: WireAPI? = nil) throws -> (Data, warnings: [String]) {
        guard case .object(var o) = record.request else { throw ToolFailure("this turn's request wasn't recorded as JSON") }
        if let api, api != record.api {
            throw ToolFailure("this turn was sent with \(name(record.api)); replay it on an endpoint that speaks it, not \(name(api))")
        }
        var warnings: [String] = []
        var dropped = 0
        /// Images aren't kept in the record (a size note stands in their place): sent without them.
        func placeholder(_ v: JSONValue?) -> Bool {
            if case .string(let s)? = v { return s.hasPrefix("[image,") }
            return false
        }
        func keep(_ part: JSONValue) -> Bool {
            guard case .object(let po) = part else { return true }
            var gone = false
            if case .object(let img)? = po["image_url"] { gone = placeholder(img["url"]) }                    // OpenAI
            if case .object(let src)? = po["source"], po["type"] == "image" { gone = placeholder(src["data"]) }  // Anthropic
            if case .object(let inline)? = po["inlineData"] { gone = placeholder(inline["data"]) }               // Gemini
            if gone { dropped += 1 }
            return !gone
        }
        func withoutImages(_ list: JSONValue?, key: String) -> JSONValue? {
            guard case .array(let messages)? = list else { return list }
            return .array(messages.map { m in
                guard case .object(var mo) = m, case .array(let parts)? = mo[key] else { return m }
                mo[key] = .array(parts.filter(keep))
                return .object(mo)
            })
        }
        switch record.api {
        case .openai:
            o["model"] = .string(options.model)
            o["stream"] = true
            o["stream_options"] = ["include_usage": true]
            if let t = options.temperature { o["temperature"] = .number(t) }
            if let e = options.reasoningEffort { o["reasoning_effort"] = e.isEmpty ? nil : .string(e) }
            if !options.keepProvider, o["provider"] != nil { o["provider"] = nil }
            if case .array(var messages)? = o["messages"], let system = options.systemPrompt,
               case .object(var first)? = messages.first, first["role"] == "system" {
                first["content"] = .string(system)
                messages[0] = .object(first)
                o["messages"] = .array(messages)
            }
            o["messages"] = withoutImages(o["messages"], key: "content")
        case .anthropic:
            o["model"] = .string(options.model)
            o["stream"] = true
            if let t = options.temperature { o["temperature"] = .number(t) }
            if let e = options.reasoningEffort {
                var config: [String: JSONValue] = [:]
                if case .object(let c)? = o["output_config"] { config = c }
                config["effort"] = e.isEmpty ? nil : .string(e == "none" || e == "minimal" ? "low" : e)
                o["output_config"] = config.isEmpty ? nil : .object(config)
            }
            if let system = options.systemPrompt { o["system"] = .string(system) }
            o["messages"] = withoutImages(o["messages"], key: "content")
        case .gemini:
            var config: [String: JSONValue] = [:]
            if case .object(let c)? = o["generationConfig"] { config = c }
            if let t = options.temperature { config["temperature"] = .number(t) }
            if let e = options.reasoningEffort {
                var thinking: [String: JSONValue] = ["includeThoughts": true]
                if case .object(let t)? = config["thinkingConfig"] { thinking = t }
                thinking["thinkingBudget"] = nil
                thinking["thinkingLevel"] = e.isEmpty ? nil : .string(e == "none" ? "minimal" : e)
                config["thinkingConfig"] = .object(thinking)
            }
            o["generationConfig"] = .object(config)
            if let system = options.systemPrompt { o["systemInstruction"] = ["parts": [["text": .string(system)]]] }
            o["contents"] = withoutImages(o["contents"], key: "parts")
        }
        if dropped > 0 { warnings.append("\(dropped) image\(dropped == 1 ? " isn't" : "s aren't") in the record; replayed without \(dropped == 1 ? "it" : "them").") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try encoder.encode(JSONValue.object(o)), warnings)
    }

    /// The reasoning effort levels a model takes, weakest first, as the replay sheet and `kurtkode replay` offer them
    /// (sent as `reasoning_effort`, mapped per API: `output_config.effort`, Gemini's thinking level or budget).
    public static func effortLevels(api: WireAPI, model: String) -> [String] {
        switch api {
        case .openai: ["none", "low", "medium", "high"]
        case .anthropic:
            switch AnthropicWire.generation(model) {
            case .budget: ["none", "low", "medium", "high"]           // "none": no thinking; others set a budget
            case .adaptive46: ["none", "low", "medium", "high", "max"]
            case .current: ["low", "medium", "high", "xhigh", "max"]   // thinking can't be turned off
            }
        // Gemini 2.5 Pro thinks always: a budget of 0 is refused.
        case .gemini: GeminiWire.isBudgetModel(model) ? (model.lowercased().contains("pro") ? [] : ["none"]) + ["low", "medium", "high"]
            : ["minimal", "low", "medium", "high"]
        }
    }

    /// Replays a turn once per effort level, one after another (in parallel they couldn't share the server's cache,
    /// though a different effort mostly voids Claude's anyway), each saved like a single replay.
    public static func sweep(_ record: WireRecord, client: ChatClient, endpointName: String, endpointID: UUID?, model: String,
                             levels: [String], keepProvider: Bool = false, wire: URL? = nil,
                             progress: @escaping @Sendable (Int, TurnSnapshot) async -> Void = { _, _ in }) async -> [ReplayRecord] {
        var out: [ReplayRecord] = []
        for (i, level) in levels.enumerated() {
            if Task.isCancelled { break }
            let r = await run(record, client: client, endpointName: endpointName, endpointID: endpointID,
                              options: ReplayOptions(model: model, reasoningEffort: level, keepProvider: keepProvider)) { snap in
                await progress(i, snap)
            }
            if let wire { try? save(r, wire: wire) }
            out.append(r)
        }
        return out
    }

    /// One reply's line in an effort comparison: what it thought, showed, did, and cost.
    public struct EffortRow: Sendable, Hashable, Identifiable {
        public var id: UUID
        /// The effort asked for ("as recorded" for the original).
        public var level: String
        public var reasoningTokens: Int?
        /// The share of the reasoning shown, when the server billed some.
        public var shownShare: Double?
        public var outputTokens: Int?
        /// "read_file README.md, grep cobalt" or "answer".
        public var actions: String
        public var sameCallsAsOriginal: Bool
        public var duration: Double?
        public var cost: Double?
        public var costIsEstimate: Bool
        public var error: String?
    }

    /// The original reply and each replay as comparable rows.
    public static func effortRows(original: ChatMessage, replays: [ReplayRecord]) -> [EffortRow] {
        func row(_ id: UUID, _ level: String, _ m: ChatMessage, same: Bool) -> EffortRow {
            let u = m.meta?.usage
            let actions = m.toolCalls.isEmpty ? (m.content.isEmpty ? "nothing" : "answer")
                : m.toolCalls.map { c in
                    let first = SessionJournal.values(c).first.map { " " + $0.prefix(40) } ?? ""
                    return c.name + first
                }.joined(separator: ", ")
            return EffortRow(id: id, level: level, reasoningTokens: u?.reasoningTokens, shownShare: ReasoningShown(m).shownShare,
                             outputTokens: u?.completionTokens, actions: actions, sameCallsAsOriginal: same,
                             duration: m.meta?.duration, cost: u?.cost, costIsEstimate: u?.costIsEstimate == true, error: m.meta?.error)
        }
        return [row(original.id, "as recorded", original, same: true)] + replays.map { r in
            row(r.id, r.options.reasoningEffort.map { $0.isEmpty ? "default" : $0 } ?? "as recorded", r.reply,
                same: compare(original: original, replay: r.reply).sameToolCalls)
        }
    }

    static func name(_ api: WireAPI) -> String {
        switch api {
        case .openai: "the OpenAI-compatible API"
        case .anthropic: "Anthropic's API"
        case .gemini: "Google's Gemini API"
        }
    }

    /// The model a recorded request asked for (Gemini names it in the URL).
    public static func model(of record: WireRecord) -> String {
        if case .object(let o) = record.request, case .string(let m)? = o["model"] { return m }
        if record.api == .gemini, let path = URL(string: record.url)?.path(),
           let range = path.range(of: #"models/[^/:]+"#, options: .regularExpression) {
            return String(path[range].dropFirst("models/".count))
        }
        return ""
    }

    /// Sends the recorded request again (with `options`) and records what came back. Tool calls in the reply aren't run.
    public static func run(_ record: WireRecord, client: ChatClient, endpointName: String, endpointID: UUID?,
                           options: ReplayOptions, wallClock: TimeInterval = 600,
                           onUpdate: @escaping @Sendable (TurnSnapshot) async -> Void = { _ in }) async -> ReplayRecord {
        let id = UUID()
        let started = Date()
        let tap = WireTap()
        var warnings: [String] = []
        let reply: ChatMessage
        do {
            let (body, w) = try body(from: record, options: options, api: client.api)
            warnings = w
            var maxTokens = 8192
            if case .object(let o) = record.request {
                if case .number(let n)? = o["max_tokens"], let v = Int(json: n) { maxTokens = v }
                if case .object(let g)? = o["generationConfig"], case .number(let n)? = g["maxOutputTokens"], let v = Int(json: n) { maxTokens = v }
            }
            reply = await TurnRunner.run(client: client, body: body, model: options.model,
                                         limits: TurnLimits(maxTokens: maxTokens, wallClock: wallClock), tap: tap, onUpdate: onUpdate)
        } catch {
            var m = ChatMessage(role: .assistant, content: "")
            m.meta = TurnMeta(requestedModel: options.model, stopReason: .failed, error: error.localizedDescription, duration: 0)
            reply = m
        }
        var r = reply
        r.id = id
        let price = await PriceLookup.lookup(client: client, model: CostEntry.pricedModel(r))
        var cost = CostEntry.make(reply: r, purpose: .replay, run: nil, agent: "replay", client: client, endpointID: endpointID,
                                  start: started, price: price)
        if let checked = await CostEntry.reconcile([cost], clients: [client]).first { cost = checked }
        return ReplayRecord(id: id, sourceReply: record.replyID, startedAt: started, endpointName: endpointName,
                            endpointID: endpointID, options: options, reply: r,
                            wire: tap.record(replyID: id, startedAt: started, duration: Date().timeIntervalSince(started)),
                            warnings: warnings, cost: cost)
    }

    /// Replays are kept beside the wire log: `<wire>/replays/<source reply>/<replay>.json`.
    public static func directory(_ wire: URL, sourceReply: UUID) -> URL {
        wire.appending(path: "replays").appending(path: sourceReply.uuidString)
    }

    public static func save(_ r: ReplayRecord, wire: URL) throws {
        let dir = directory(wire, sourceReply: r.sourceReply)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(r).write(to: dir.appending(path: "\(r.id.uuidString).json"))
    }

    /// A turn's replays, oldest first.
    public static func load(_ wire: URL, sourceReply: UUID) -> [ReplayRecord] {
        let dir = directory(wire, sourceReply: sourceReply)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? dec.decode(ReplayRecord.self, from: $0) } }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// The replay's reply against the original's: tool calls (names and arguments, ignoring key order and spacing),
    /// text, tokens, and times.
    public static func compare(original: ChatMessage, replay: ChatMessage) -> ReplayComparison {
        func key(_ c: ToolCall) -> String { c.name + " " + AgentLoop.normalizedArguments(c.arguments) }
        var diffs: [String] = []
        let a = original.toolCalls, b = replay.toolCalls
        for i in 0..<max(a.count, b.count) {
            switch (i < a.count ? a[i] : nil, i < b.count ? b[i] : nil) {
            case let (x?, y?) where key(x) != key(y):
                diffs.append(x.name == y.name ? "\(x.name): \(x.arguments) → \(y.arguments)" : "\(x.name) \(x.arguments) → \(y.name) \(y.arguments)")
            case (let x?, nil): diffs.append("− \(x.name) \(x.arguments)")
            case (nil, let y?): diffs.append("+ \(y.name) \(y.arguments)")
            default: break
            }
        }
        func figures(_ m: ChatMessage) -> ReplayComparison.Figures {
            ReplayComparison.Figures(promptTokens: m.meta?.usage?.promptTokens, completionTokens: m.meta?.usage?.completionTokens,
                                     reasoningTokens: m.meta?.usage?.reasoningTokens, timeToFirstToken: m.meta?.timeToFirstToken,
                                     duration: m.meta?.duration, stop: m.meta.map { "\($0.stopReason)" } ?? "?")
        }
        let squash = { (s: String) in s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return ReplayComparison(sameToolCalls: diffs.isEmpty, toolCallDifferences: diffs,
                                sameText: squash(original.content) == squash(replay.content),
                                original: figures(original), replay: figures(replay))
    }

    /// A shell command that sends the recorded request again. The key is a placeholder (`$KURTKODE_API_KEY`), left
    /// out for a server on this Mac; images left out of the record are left out here too.
    public static func curl(_ record: WireRecord) -> String {
        guard let (body, warnings) = try? body(from: record, options: ReplayOptions(model: model(of: record), keepProvider: true)) else {
            return "# This turn's request wasn't recorded as JSON."
        }
        let pretty = (try? JSONSerialization.jsonObject(with: body)).flatMap {
            try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }.map { String(decoding: $0, as: UTF8.self) } ?? String(decoding: body, as: UTF8.self)
        let host = URL(string: record.url)?.host() ?? ""
        let local = ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
        var lines = warnings.map { "# " + $0 }
        lines.append("curl -sN '\(record.url)' \\")
        lines.append("  -H 'Content-Type: application/json' \\")
        switch record.api {
        case .openai:
            if !local { lines.append("  -H \"Authorization: Bearer $KURTKODE_API_KEY\" \\") }
        case .anthropic:
            lines.append("  -H \"x-api-key: $KURTKODE_API_KEY\" \\")
            lines.append("  -H 'anthropic-version: \(AnthropicWire.version)' \\")
            if let betas = AnthropicWire.betas(forBody: body) { lines.append("  -H 'anthropic-beta: \(betas)' \\") }
        case .gemini:
            lines.append("  -H \"x-goog-api-key: $KURTKODE_API_KEY\" \\")
        }
        lines.append("  --data-binary @- <<'KURTKODE_JSON'")
        lines.append(pretty)
        lines.append("KURTKODE_JSON")
        return lines.joined(separator: "\n")
    }
}
