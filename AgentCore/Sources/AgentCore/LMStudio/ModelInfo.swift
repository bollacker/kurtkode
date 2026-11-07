import Foundation

/// One entry from LM Studio's native `GET /api/v0/models`.
/// Only LM Studio endpoints expose this; generic OpenAI-compatible endpoints use `/v1/models`.
public struct ModelInfo: Codable, Sendable, Identifiable, Hashable {
    public enum State: String, Codable, Sendable {
        case loaded
        case notLoaded = "not-loaded"
    }

    public let id: String
    public let type: String               // "llm", "vlm", "embeddings"
    public let publisher: String?
    public let arch: String?
    public let quantization: String?
    public let state: State
    public let maxContextLength: Int?
    public let loadedContextLength: Int?  // present only when loaded
    public let capabilities: [String]?

    public var supportsTools: Bool { capabilities?.contains("tool_use") ?? false }
    public var supportsVision: Bool { type == "vlm" }
    public var isChatModel: Bool { type == "llm" || type == "vlm" }

    enum CodingKeys: String, CodingKey {
        case id, type, publisher, arch, quantization, state, capabilities
        case maxContextLength = "max_context_length"
        case loadedContextLength = "loaded_context_length"
    }
}

struct ModelList: Codable {
    let data: [ModelInfo]
}

public enum LMStudioError: Error, Sendable {
    case badStatus(Int)
}

/// Talks to the LM Studio-specific REST surface (model metadata). Chat goes through `ChatClient`.
public struct LMStudioService: Sendable {
    /// Server root, without `/v1`.
    public let baseURL: URL
    let session: URLSession

    /// Default is 127.0.0.1, not "localhost": LM Studio binds IPv4 only, and "localhost" tries ::1 first.
    public init(baseURL: URL = URL(string: "http://127.0.0.1:1234")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public init(endpoint: Endpoint, session: URLSession = .shared) {
        self.init(baseURL: endpoint.serverRoot, session: session)
    }

    public func models() async throws -> [ModelInfo] {
        let (data, response) = try await session.data(from: baseURL.appending(path: "api/v0/models"))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LMStudioError.badStatus(http.statusCode)
        }
        return try Self.decodeModels(data)
    }

    static func decodeModels(_ data: Data) throws -> [ModelInfo] {
        try JSONDecoder().decode(ModelList.self, from: data).data
    }
}
