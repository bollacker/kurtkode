import Foundation

public enum ChatError: Error, Sendable, Equatable, LocalizedError {
    case http(status: Int, message: String?)
    case badResponse
    case malformedChunk(String)
    /// The connection ended mid-reply: no `[DONE]`, and no choice said why it finished.
    case streamCut
    /// The server reported an error inside the stream (Anthropic's `error` event, Gemini's error chunk).
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let message): "Server returned HTTP \(status)" + (message.map { ": \($0)" } ?? "")
        case .badResponse: "The server's response was not HTTP."
        case .malformedChunk(let s): "Could not decode a streamed chunk: \(s.prefix(200))"
        case .streamCut: "The connection closed before the reply finished; what arrived is kept, but it is incomplete."
        case .server(let message): "The server reported an error: \(message)"
        }
    }
}

/// Streams chat completions from an OpenAI-compatible endpoint, or from Anthropic's or Google's native API.
public struct ChatClient: Sendable {
    public let baseURL: URL          // the API base, including its version (/v1, /v1beta)
    public let apiKey: String?
    public let api: WireAPI
    let session: URLSession
    /// Longest silence tolerated between bytes. Prompt processing on a long context can take minutes.
    public var idleTimeout: TimeInterval = 300
    /// Waits before each retry of a request the server turned away for now (rate limits, overloaded
    /// gateways). The server's Retry-After wins when it gives one, up to a minute.
    public var retryDelays: [TimeInterval] = [2, 5, 10, 20, 30]

    public init(baseURL: URL, apiKey: String? = nil, api: WireAPI = .openai, session: URLSession = .shared) {
        self.baseURL = baseURL
        // Pasted keys can bring a line break, which makes URLSession drop the header (seen: Anthropic's 401 "x-api-key
        // header is required" with a key stored).
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.api = api
        self.session = session
    }

    public init(endpoint: Endpoint, apiKey: String? = nil, session: URLSession = .shared) {
        self.init(baseURL: endpoint.baseURL, apiKey: apiKey, api: endpoint.kind.api, session: session)
    }

    func urlRequest(path: String, query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var r = URLRequest(url: url)
        r.timeoutInterval = idleTimeout
        if let body {
            r.httpMethod = "POST"
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        switch api {
        case .openai:
            if let apiKey, !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if let apiKey, !apiKey.isEmpty { r.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
            r.setValue(AnthropicWire.version, forHTTPHeaderField: "anthropic-version")
            if let body, let betas = AnthropicWire.betas(forBody: body) { r.setValue(betas, forHTTPHeaderField: "anthropic-beta") }
        case .gemini:
            if let apiKey, !apiKey.isEmpty { r.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key") }
        }
        return r
    }

    /// The server is outside this Mac and the local network (`Endpoint.isThirdParty`).
    public var isThirdParty: Bool { api != .openai || Endpoint.isThirdParty(baseURL) }

    /// The request for one streamed reply from `model`.
    func streamRequest(body: Data, model: String) -> URLRequest {
        switch api {
        case .openai: urlRequest(path: "chat/completions", body: body)
        case .anthropic: urlRequest(path: "messages", body: body)
        case .gemini: urlRequest(path: "models/\(model):streamGenerateContent", query: [URLQueryItem(name: "alt", value: "sse")], body: body)
        }
    }

    /// Claude on OpenRouter caches only what the request marks (`cache_control` on content parts); kurtkode's own
    /// Anthropic requests use the automatic form instead.
    func usesCacheBreakpoints(model: String) -> Bool {
        api == .openai && (baseURL.host()?.hasSuffix("openrouter.ai") ?? false) && model.lowercased().hasPrefix("anthropic/")
    }

    /// The request asks the server for an hour's cache (Claude natively or through OpenRouter; other servers ignore
    /// `cacheForAnHour`).
    func sendsHourCache(_ request: ChatRequest) -> Bool {
        request.cacheForAnHour && !request.oneOff && (api == .anthropic || usesCacheBreakpoints(model: request.model))
    }

    /// Where a request's cache key goes: OpenAI's own API (and Azure's) or OpenRouter; other servers get none.
    var cacheRouting: WireFormat.CacheRouting {
        guard api == .openai, let host = baseURL.host()?.lowercased() else { return .none }
        if host == "api.openai.com" || host.hasSuffix(".openai.azure.com") { return .openAI }
        return host.hasSuffix("openrouter.ai") ? .openRouter : .none
    }

    /// OpenAI's own servers (and Azure OpenAI): the output cap goes as `max_completion_tokens`.
    var usesCompletionTokens: Bool {
        guard api == .openai, let host = baseURL.host()?.lowercased() else { return false }
        return host == "api.openai.com" || host.hasSuffix(".openai.azure.com")
    }

    /// Encodes a request in this client's wire format.
    public func encode(_ request: ChatRequest) throws -> Data {
        switch api {
        case .openai: try WireFormat.encodeRequest(request, cacheBreakpoints: usesCacheBreakpoints(model: request.model) && !request.oneOff,
                                                   completionTokens: usesCompletionTokens, routing: cacheRouting)
        case .anthropic: try AnthropicWire.encodeRequest(request)
        case .gemini: try GeminiWire.encodeRequest(request)
        }
    }

    static func decoder(api: WireAPI, model: String) -> any StreamDecoder {
        switch api {
        case .openai: OpenAIStreamDecoder()
        case .anthropic: AnthropicStreamDecoder(requestedModel: model)
        case .gemini: GeminiStreamDecoder(requestedModel: model)
        }
    }

    /// Streams one completion. Cancelling the consuming task closes the connection, which makes
    /// LM Studio stop generating.
    /// `tap`, when given, sees the request and the raw response (for the wire log).
    public func stream(_ request: ChatRequest, tap: WireTap? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        let body: Data
        do { body = try encode(request) }
        catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
        return stream(body: body, model: request.model, tap: tap)
    }

    /// Streams one completion for a request body as it is (a replay of a recorded request). `model` is the one the
    /// body asks for (Gemini names it in the URL, not the body).
    public func stream(body: Data, model: String, tap: WireTap? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        let urlRequest = streamRequest(body: body, model: model)
        if let url = urlRequest.url { tap?.request(url: url, body: body) }
        let session = session
        let retryDelays = retryDelays
        let api = api
        let apiKey = apiKey

        return AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = Self.decoder(api: api, model: model)
                do {
                    var attempt = 0
                    let host = RateLimits.scope(host: urlRequest.url?.host() ?? "", apiKey: apiKey, model: model)
                    // A used-up rate-limit window (reported on an earlier response): wait for its reset.
                    let wait = await RateLimits.shared.pause(host: host)
                    if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                    // An overloaded or similar error inside a 200 stream, before anything was generated, is retried like
                    // the same error as an HTTP status (Anthropic sends `overloaded_error` this way).
                    var midStreamRetries = 0
                    streaming: while true {
                        var generated = false
                        do {
                            var (bytes, response) = try await session.bytes(for: urlRequest)
                            while true {
                                guard let http = response as? HTTPURLResponse else { throw ChatError.badResponse }
                                tap?.status(http.statusCode)
                                await RateLimits.shared.record(host: host, headers: http.allHeaderFields)
                                if http.statusCode == 200 {
                                    // Anthropic's request id (its support and console find a request by it).
                                    if let id = http.value(forHTTPHeaderField: "request-id") { continuation.yield(.requestID(id)) }
                                    break
                                }
                                var data = Data()
                                for try await b in bytes {
                                    data.append(b)
                                    if data.count > 65_536 { break }
                                }
                                tap?.errorBody(String(decoding: data, as: UTF8.self))
                                guard Self.isTransient(http.statusCode), attempt < retryDelays.count else {
                                    throw ChatError.http(status: http.statusCode, message: WireFormat.errorMessage(fromBody: data))
                                }
                                let wait = Self.retryAfter(http) ?? RateLimits.retryDelay(fromBody: data) ?? retryDelays[attempt]
                                attempt += 1
                                try await Task.sleep(for: .seconds(wait))
                                (bytes, response) = try await session.bytes(for: urlRequest)
                            }
                            // A stream that just stops (the server crashed, a proxy dropped it) must not pass for a whole
                            // reply: its text is cut off, and a tool call in it may be half-written.
                            var sawData = false
                            // An event's data so far, when its first `data:` line was not whole JSON.
                            var pending = ""
                            // Lines that are not SSE (bounded), for a 200 whose body is not a stream at all.
                            var other = Data()
                            /// Decodes and yields one event's data. Returns false, keeping the data for the next `data:`
                            /// line, when it is not whole JSON yet and the event may go on.
                            func dispatch(_ payload: String, final: Bool) throws -> Bool {
                                let data = Data(payload.utf8)
                                let events: [StreamEvent]
                                do { events = try decoder.decode(data) }
                                catch let e as ChatError { throw e }
                                catch {
                                    if !final, (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) == nil {
                                        return false
                                    }
                                    throw ChatError.malformedChunk(payload)
                                }
                                for e in events {
                                    switch e {
                                    case .content, .reasoning, .toolCallDelta: generated = true
                                    default: break
                                    }
                                    continuation.yield(e)
                                }
                                return true
                            }
                            lines: for try await line in ByteLines(base: bytes) {
                                if line.isEmpty {
                                    // A blank line ends an SSE event.
                                    if !pending.isEmpty { _ = try dispatch(pending, final: true); pending = "" }
                                    continue
                                }
                                tap?.line(line)
                                switch SSELineParser.parse(line[...]) {
                                case .ignore: continue
                                case .other:
                                    if !sawData, other.count < 65_536 { other.append(contentsOf: line.utf8); other.append(0x0A) }
                                case .done: break lines
                                case .data(let payload):
                                    sawData = true
                                    pending = pending.isEmpty ? payload : pending + "\n" + payload
                                    if try dispatch(pending, final: false) { pending = "" }
                                }
                            }
                            if !pending.isEmpty { _ = try dispatch(pending, final: true) }
                            // Some servers skip `[DONE]`, and the native APIs have none; a finish reason is enough.
                            if !decoder.finished {
                                // A 200 whose body is not a stream (a proxy's JSON error, a server ignoring `stream`).
                                if !sawData, let message = Self.nonStreamMessage(other) { throw ChatError.server(message) }
                                throw ChatError.streamCut
                            }
                            break streaming
                        } catch ChatError.server(let message) where !generated && Self.isTransient(serverError: message)
                                    && midStreamRetries < retryDelays.count {
                            let wait = retryDelays[midStreamRetries]
                            midStreamRetries += 1
                            decoder = Self.decoder(api: api, model: model)
                            try await Task.sleep(for: .seconds(wait))
                        }
                    }
                    for e in decoder.end() { continuation.yield(e) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What a 200 response that carried no `data:` line said: the server's error message, or the start of the body.
    static func nonStreamMessage(_ body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        // Gemini without `alt=sse` answers with a JSON array of chunks.
        var first = body
        if case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: body), let item = items.first,
           let data = try? JSONEncoder().encode(item) { first = data }
        if let message = WireFormat.errorMessage(fromBody: first) { return message }
        let text = String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return "the server sent this instead of a stream: \(text)"
    }

    /// Statuses that mean "not now" rather than "not this request". A plain 500 is not retried: on LM
    /// Studio it usually means a template error, which fails the same way every time.
    static func isTransient(_ status: Int) -> Bool { [408, 429, 502, 503, 504, 529].contains(status) }

    /// An error reported inside a stream that means "not now": the server is overloaded or briefly failing.
    static func isTransient(serverError message: String) -> Bool {
        let m = message.lowercased()
        return ["overloaded", "api_error", "rate_limit", "timeout_error", "unavailable", "resource_exhausted", "internal error"]
            .contains { m.contains($0) }
    }

    /// Retry-After in seconds (the date form is ignored), capped at a minute.
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let v = response.value(forHTTPHeaderField: "Retry-After"), let s = TimeInterval(v.trimmingCharacters(in: .whitespaces)),
              s >= 0 else { return nil }
        return min(s, 60)
    }

    /// A model's list price in dollars per token (prompt, completion), from `GET /v1/models` where the server lists
    /// prices (OpenRouter does); nil when it doesn't.
    public func listPrice(of model: String) async -> (prompt: Double, completion: Double)? {
        guard let data = await modelsList(),
              case .object(let o) = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .array(let list)? = o["data"] else { return nil }
        for case .object(let m) in list where m["id"] == .string(model) {
            guard case .object(let p)? = m["pricing"] else { return nil }
            func number(_ v: JSONValue?) -> Double? {
                switch v { case .string(let s)?: Double(s); case .number(let n)?: n; default: nil }
            }
            guard let prompt = number(p["prompt"]), let completion = number(p["completion"]) else { return nil }
            return (prompt, completion)
        }
        return nil
    }

    /// The raw `GET /models` response of an OpenAI-compatible server (OpenRouter lists prices in it); nil on failure.
    public func modelsList() async -> Data? {
        guard api == .openai, let (data, response) = try? await session.data(for: urlRequest(path: "models")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// OpenRouter's record of one generation (`GET /generation?id=`): what it charged and the native token counts.
    /// Nil until the record exists (it can lag the reply by a few seconds), or on any other server.
    public func generationStats(id: String) async -> [String: JSONValue]? {
        await generationLookup(id: id).record
    }

    /// The generation record, or what came back instead (the HTTP status and the start of the body), for diagnosis.
    public func generationLookup(id: String) async -> (record: [String: JSONValue]?, status: Int?, body: String) {
        guard api == .openai else { return (nil, nil, "not an OpenAI-compatible server") }
        let request = urlRequest(path: "generation", query: [URLQueryItem(name: "id", value: id)])
        guard let (data, response) = try? await session.data(for: request) else { return (nil, nil, "no response") }
        let status = (response as? HTTPURLResponse)?.statusCode
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        guard status == 200, case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let d)? = o["data"] else { return (nil, status, body) }
        return (d, status, body)
    }

    /// Model ids from `GET /models`. Works on any OpenAI-compatible endpoint and the native APIs.
    public func modelIDs() async throws -> [String] {
        try await models().map(\.id)
    }

    /// The server's models, with their context lengths where it gives them (Anthropic and Gemini do).
    public func models() async throws -> [ListedModel] {
        func get(_ query: [URLQueryItem]) async throws -> JSONValue {
            let (data, response) = try await session.data(for: urlRequest(path: "models", query: query))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ChatError.http(status: http.statusCode, message: WireFormat.errorMessage(fromBody: data))
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        switch api {
        case .openai:
            guard case .object(let o) = try await get([]), case .array(let list)? = o["data"] else { throw ChatError.badResponse }
            var out = list.compactMap { m -> ListedModel? in
                guard case .object(let m) = m else { return nil }
                return ListedModel.openAI(m)
            }
            // Ollama lists its own models as owned by "library" and says nothing else about them here; its `/api/show`
            // has each one's context and capabilities. Asked for a few dozen models at most.
            let ollama = list.contains { if case .object(let m) = $0 { NativeWire.string(m["owned_by"]) == "library" } else { false } }
            if ollama, out.count <= 40 {
                await withTaskGroup(of: (Int, [String: JSONValue]?).self) { group in
                    for (i, m) in out.enumerated() { group.addTask { (i, await self.ollamaShow(m.id)) } }
                    for await (i, show) in group { if let show { out[i].absorbOllama(show) } }
                }
            }
            return out
        case .anthropic:
            var out: [ListedModel] = []
            var after: String?
            repeat {
                var query = [URLQueryItem(name: "limit", value: "1000")]
                if let after { query.append(URLQueryItem(name: "after_id", value: after)) }
                guard case .object(let o) = try await get(query), case .array(let list)? = o["data"] else { throw ChatError.badResponse }
                for case .object(let m) in list {
                    guard let id = NativeWire.string(m["id"]) else { continue }
                    out.append(ListedModel(id: id, displayName: NativeWire.string(m["display_name"]),
                                           contextLength: NativeWire.int(m["max_input_tokens"])))
                }
                after = o["has_more"] == .bool(true) ? NativeWire.string(o["last_id"]) : nil
            } while after != nil && out.count < 10_000
            return out
        case .gemini:
            var out: [ListedModel] = []
            var token: String?
            repeat {
                var query = [URLQueryItem(name: "pageSize", value: "1000")]
                if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
                guard case .object(let o) = try await get(query) else { throw ChatError.badResponse }
                if case .array(let list)? = o["models"] {
                    for case .object(let m) in list {
                        // Only models that chat (not embedding or image models).
                        guard let name = NativeWire.string(m["name"]), case .array(let methods)? = m["supportedGenerationMethods"],
                              methods.contains("generateContent") else { continue }
                        out.append(ListedModel(id: name.hasPrefix("models/") ? String(name.dropFirst(7)) : name,
                                               displayName: NativeWire.string(m["displayName"]),
                                               contextLength: NativeWire.int(m["inputTokenLimit"])))
                    }
                }
                token = NativeWire.string(o["nextPageToken"]).flatMap { $0.isEmpty ? nil : $0 }
            } while token != nil && out.count < 10_000
            return out
        }
    }

    /// A model's context length as the server lists it (nil when it doesn't).
    public func contextLength(of model: String) async -> Int? {
        try? await models().first { $0.id == model }?.contextLength
    }

    /// Ollama's `POST /api/show` for a model (at the server's root, not under `/v1`); nil from any other server.
    func ollamaShow(_ model: String) async -> [String: JSONValue]? {
        var root = baseURL
        if root.lastPathComponent == "v1" { root = root.deletingLastPathComponent() }
        var r = URLRequest(url: root.appending(path: "api/show"))
        r.timeoutInterval = 10
        r.httpMethod = "POST"
        r.httpBody = try? JSONEncoder().encode(["model": model])
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await session.data(for: r), (response as? HTTPURLResponse)?.statusCode == 200,
              case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return o
    }
}
