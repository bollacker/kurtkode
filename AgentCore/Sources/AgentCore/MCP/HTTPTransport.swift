import Foundation

/// MCP's Streamable HTTP transport (spec 2025-06-18): each message is a POST to the server's URL; a request's
/// reply comes back as JSON or as an SSE stream (which can carry the server's own requests and notifications
/// first); notifications get 202. The server's `Mcp-Session-Id` and the negotiated `MCP-Protocol-Version`
/// go on every later request. A GET stream, when the server offers one, carries server-initiated messages.
public final class HTTPTransport: MCPTransport, @unchecked Sendable {
    let url: URL
    let headers: [String: String]
    let session: URLSession
    private let lock = NSLock()
    private var sessionID: String?
    private var protocolVersion: String?
    private var onMessage: (@Sendable (Data) -> Void)?
    private var listener: Task<Void, Never>?
    /// The SSE replies to POSTs still being read, so `close` can end them.
    private var replyReaders: [UUID: Task<Void, Never>] = [:]
    private var closed = false
    private let redirects = SameOriginRedirects()

    public init(url: URL, headers: [String: String] = [:], session: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    public func start(onMessage: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable (String?) -> Void) async throws {
        lock.withLock { self.onMessage = onMessage }
    }

    public func setProtocolVersion(_ version: String) async { lock.withLock { protocolVersion = version } }

    func request(method: String, body: Data? = nil, accept: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 300)
        r.httpMethod = method
        r.httpBody = body
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        r.setValue(accept, forHTTPHeaderField: "Accept")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (sid, version) = lock.withLock { (sessionID, protocolVersion) }
        if let sid { r.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        if let version { r.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
        return r
    }

    public func send(_ message: Data) async throws {
        if lock.withLock({ closed }) { throw MCPError.transport("The connection is closed.") }
        let host = url.host() ?? url.absoluteString
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request(method: "POST", body: message, accept: "application/json, text/event-stream"),
                                                        delegate: redirects)
        }
        catch { throw MCPError.transport("Couldn't reach \(host): \(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse else { throw MCPError.transport("\(host) didn't answer over HTTP.") }
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") { lock.withLock { sessionID = sid } }
        switch http.statusCode {
        case 202, 204:
            return
        case 200..<300:
            if http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true {
                // The stream stays open until the reply arrives; read it without holding up the sender.
                let id = UUID()
                lock.withLock {
                    guard !closed else { return }
                    replyReaders[id] = Task {
                        await self.readEvents(bytes)
                        _ = self.lock.withLock { self.replyReaders.removeValue(forKey: id) }
                    }
                }
            } else {
                deliver(try await Self.collect(bytes))
            }
        case 401, 403:
            let body = String(decoding: (try? await Self.collect(bytes, limit: 2000)) ?? Data(), as: UTF8.self)
            throw MCPError.transport("\(host) refused the request (HTTP \(http.statusCode)): check the server's token "
                                     + "(Settings → MCP → Set Token…, or an Authorization header in its config)."
                                     + (body.isEmpty ? "" : " It said: " + body.prefix(300)))
        case 300..<400:
            // Only same-origin redirects are followed (`SameOriginRedirects`), so the token never goes elsewhere.
            let to = http.value(forHTTPHeaderField: "Location").map { " to " + $0 } ?? ""
            throw MCPError.transport("\(host) redirected the request\(to) (HTTP \(http.statusCode)), and kurtkode doesn't follow a "
                                     + "redirect to another host, port or scheme. Put the address it redirects to in the server's config.")
        case 404 where lock.withLock({ sessionID != nil }):
            throw MCPError.transport("\(host) says the session has expired (HTTP 404). Restart the server to start a new one.")
        default:
            let body = String(decoding: (try? await Self.collect(bytes, limit: 2000)) ?? Data(), as: UTF8.self)
            throw MCPError.transport("\(host) answered HTTP \(http.statusCode)" + (body.isEmpty ? "." : ": " + body.prefix(300)))
        }
    }

    /// Opens the server's stream of its own messages (list_changed, pings), if it offers one (else 405).
    public func listen() async {
        guard lock.withLock({ listener == nil && !closed }) else { return }
        let r = request(method: "GET", accept: "text/event-stream")
        let task = Task { [weak self] in
            guard let self, let (bytes, response) = try? await self.session.bytes(for: r, delegate: self.redirects),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { return }
            await self.readEvents(bytes)
        }
        lock.withLock { listener = task }
    }

    public func close() async {
        let (sid, tasks): (String?, [Task<Void, Never>]) = lock.withLock {
            closed = true
            defer { replyReaders = [:] }
            return (sessionID, [listener].compactMap { $0 } + Array(replyReaders.values))
        }
        for task in tasks { task.cancel() }
        // Ending the session is a courtesy; don't wait long for it.
        if sid != nil {
            var r = request(method: "DELETE", accept: "application/json")
            r.timeoutInterval = 3
            _ = try? await session.data(for: r, delegate: redirects)
        }
    }

    /// Each SSE event's message (see `SSEJoiner`).
    func readEvents(_ bytes: URLSession.AsyncBytes) async {
        var joiner = SSEJoiner()
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                if let data = joiner.feed(line) { deliver(data) }
            }
        } catch {}
    }

    /// Whether `url` names this machine (where plain http can't be read on the way).
    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let ipv4Loopback = octets.count == 4 && octets[0] == "127" && octets.allSatisfy { UInt8($0) != nil }
        return host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || ipv4Loopback
    }

    /// One message, or each message of a JSON-RPC batch.
    func deliver(_ data: Data) {
        guard let handler = lock.withLock({ onMessage }) else { return }
        if case .array(let items)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
            for item in items { handler(MCPClient.encode(item)) }
        } else if !data.isEmpty {
            handler(data)
        }
    }

    static func collect(_ bytes: URLSession.AsyncBytes, limit: Int = 20_000_000) async throws -> Data {
        var data = Data()
        for try await b in bytes {
            data.append(b)
            if data.count >= limit { break }
        }
        return data
    }
}

/// Joins SSE `data:` lines until they parse as JSON (URLSession's line reader drops the blank lines that would end an
/// event, so a complete JSON value is the end of one). Data that never parses is dropped rather than kept growing
/// in front of every later event: when another event's fields start (`event:`, `id:`), when a new JSON value starts
/// at the beginning of a `data:` line, or past `limit` bytes.
struct SSEJoiner {
    var limit = 20_000_000
    private(set) var pending = ""

    /// The message this line completes, if any.
    mutating func feed(_ line: String) -> Data? {
        if line.hasPrefix("event:") || line.hasPrefix("id:") {
            pending = ""
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        var piece = line.dropFirst(5)
        if piece.first == " " { piece = piece.dropFirst() }
        if !pending.isEmpty, piece.first == "{" || piece.first == "[" {
            // Either a value whose earlier lines didn't parse, or a new one: try it alone first.
            let alone = Data(piece.utf8)
            if (try? JSONDecoder().decode(JSONValue.self, from: alone)) != nil {
                pending = ""
                return alone
            }
            pending = ""
        }
        pending += pending.isEmpty ? piece : "\n" + piece
        if pending.utf8.count > limit {
            pending = ""
            return nil
        }
        let data = Data(pending.utf8)
        guard (try? JSONDecoder().decode(JSONValue.self, from: data)) != nil else { return nil }
        pending = ""
        return data
    }
}

/// Follows a redirect only to the same scheme, host and port, so the server's token (an Authorization header) and the
/// config's other headers never go to another origin and https never drops to http. URLSession leaves Authorization off
/// the redirected request, so a same-origin redirect gets the original's headers back.
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static func allows(from: URL?, to: URL?) -> Bool {
        guard let from, let to else { return false }
        func port(_ u: URL) -> Int? { u.port ?? (u.scheme == "https" ? 443 : u.scheme == "http" ? 80 : nil) }
        return from.scheme?.lowercased() == to.scheme?.lowercased() && from.host()?.lowercased() == to.host()?.lowercased()
            && port(from) == port(to)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let from = task.currentRequest ?? task.originalRequest
        guard Self.allows(from: from?.url, to: request.url) else { return completionHandler(nil) }
        var next = request
        for (k, v) in from?.allHTTPHeaderFields ?? [:] where next.value(forHTTPHeaderField: k) == nil { next.setValue(v, forHTTPHeaderField: k) }
        completionHandler(next)
    }
}
