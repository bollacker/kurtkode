import Foundation
import Testing
@testable import AgentCore

/// Serves scripted HTTP responses to a URLSession, optionally streaming them in timed pieces.
/// Each test registers its own host, so tests running in parallel don't see each other's routes.
final class MockServer: URLProtocol, @unchecked Sendable {
    struct Route: Sendable {
        var status: Int = 200
        var chunks: [Data]
        var delay: TimeInterval = 0          // before each chunk
        var repeatForever = false            // keep sending the last chunk until cancelled
        /// When set, request N is answered with turns[N] (the last one repeats); `chunks` is ignored.
        var turns: [[Data]]? = nil
        /// HTTP status per turn; missing entries use `status`.
        var turnStatuses: [Int: Int] = [:]
        /// Answers to GET requests, by the URL's last path component ("generation", "models"); others get `chunks`.
        var gets: [String: Data] = [:]

        init(status: Int = 200, chunks: [Data] = [], delay: TimeInterval = 0, repeatForever: Bool = false,
             turns: [[Data]]? = nil, turnStatuses: [Int: Int] = [:]) {
            self.status = status
            self.chunks = chunks
            self.delay = delay
            self.repeatForever = repeatForever
            self.turns = turns
            self.turnStatuses = turnStatuses
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Route] = [:]
    nonisolated(unsafe) private static var cancelledHosts: Set<String> = []
    nonisolated(unsafe) private static var lastBodies: [String: Data] = [:]
    nonisolated(unsafe) private static var allBodies: [String: [Data]] = [:]
    nonisolated(unsafe) private static var gets: [String: [URL]] = [:]

    /// The GET requests a route answered from `gets`.
    static func getRequests(_ host: String) -> [URL] { lock.withLock { gets[host] ?? [] } }

    /// A session whose requests all go to MockServer routes.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockServer.self]
        return URLSession(configuration: config)
    }()

    /// Registers a route and returns a client pointed at it.
    static func client(_ route: Route, api: WireAPI = .openai, host suffix: String? = nil) -> (ChatClient, String) {
        // A suffix like ".openrouter.ai" makes the client look like that server (what ToolForcing checks).
        let host = "mock-\(UUID().uuidString.prefix(8).lowercased())" + (suffix ?? "")
        lock.withLock { routes[host] = route }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockServer.self]
        var client = ChatClient(baseURL: URL(string: "http://\(host)/v1")!, api: api, session: URLSession(configuration: config))
        client.retryDelays = [0.01, 0.01]
        return (client, host)
    }

    static func sse(fixture name: String) throws -> Route {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        // One chunk per SSE line, as a server would flush them.
        let chunks = text.split(separator: "\n", omittingEmptySubsequences: false).map { Data(($0 + "\n").utf8) }
        return Route(chunks: chunks)
    }

    static func wasCancelled(_ host: String) -> Bool { lock.withLock { cancelledHosts.contains(host) } }
    static func requestBody(_ host: String) -> Data? { lock.withLock { lastBodies[host] } }
    static func requestBodies(_ host: String) -> [Data] { lock.withLock { allBodies[host] ?? [] } }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var stopped = false
    private let stopLock = NSLock()

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard var route = Self.lock.withLock({ Self.routes[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if request.httpMethod ?? "GET" == "GET", let answer = route.gets[request.url?.lastPathComponent ?? ""] {
            Self.lock.withLock { Self.gets[host, default: []].append(request.url!) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var requestIndex = 0
        if let body = request.httpBody ?? request.httpBodyStream.map(Self.read) {
            Self.lock.withLock {
                Self.lastBodies[host] = body
                requestIndex = Self.allBodies[host, default: []].count
                Self.allBodies[host, default: []].append(body)
            }
        }
        if let turns = route.turns, !turns.isEmpty {
            route.chunks = turns[min(requestIndex, turns.count - 1)]
            if let s = route.turnStatuses[requestIndex] { route.status = s }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        Thread.detachNewThread { [self] in
            var i = 0
            while true {
                if stopLock.withLock({ stopped }) { return }
                if route.delay > 0 { Thread.sleep(forTimeInterval: route.delay) }
                if i < route.chunks.count {
                    client?.urlProtocol(self, didLoad: route.chunks[i])
                    i += 1
                } else if route.repeatForever, let last = route.chunks.last {
                    client?.urlProtocol(self, didLoad: last)
                } else {
                    break
                }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stopLock.withLock { stopped = true }
        let host = request.url?.host() ?? ""
        Self.lock.withLock { _ = Self.cancelledHosts.insert(host) }
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

func fixtureData(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func sseEvents(fixture name: String) throws -> [StreamEvent] {
    let text = String(decoding: try fixtureData(name, "txt"), as: UTF8.self)
    var out: [StreamEvent] = []
    for line in text.split(separator: "\n") {
        if case .data(let payload) = SSELineParser.parse(line) {
            out += try WireFormat.events(fromChunk: Data(payload.utf8))
        }
    }
    return out
}


// MARK: - Scripted SSE turns

enum SSE {
    static func line(_ json: String) -> Data { Data("data: \(json)\n".utf8) }

    static func content(_ text: String, model: String = "test-model") -> [Data] {
        let escaped = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        return [
            line(#"{"model":"\#(model)","choices":[{"index":0,"delta":{"role":"assistant","content":\#(escaped)},"finish_reason":null}]}"#),
            line(#"{"model":"\#(model)","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#),
            line(#"{"model":"\#(model)","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":10}}"#),
            Data("data: [DONE]\n".utf8),
        ]
    }

    /// One turn calling the given tools, in order.
    static func toolCalls(_ calls: [(id: String, name: String, arguments: String)], model: String = "test-model") -> [Data] {
        var out: [Data] = []
        for (i, c) in calls.enumerated() {
            let args = String(decoding: try! JSONEncoder().encode(c.arguments), as: UTF8.self)
            out.append(line(#"{"model":"\#(model)","choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(i),"id":"\#(c.id)","type":"function","function":{"name":"\#(c.name)","arguments":""}}]},"finish_reason":null}]}"#))
            out.append(line(#"{"model":"\#(model)","choices":[{"index":0,"delta":{"tool_calls":[{"index":\#(i),"function":{"arguments":\#(args)}}]},"finish_reason":null}]}"#))
        }
        out.append(line(#"{"model":"\#(model)","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#))
        out.append(line(#"{"model":"\#(model)","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":20}}"#))
        out.append(Data("data: [DONE]\n".utf8))
        return out
    }

    static func toolCall(_ id: String, _ name: String, _ arguments: String) -> [Data] {
        toolCalls([(id, name, arguments)])
    }
}
