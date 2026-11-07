import AgentCore
import Foundation

/// A chat model offered by an endpoint, merged from whatever that endpoint can tell us.
struct ModelEntry: Identifiable, Hashable {
    var id: String
    var displayName: String
    var isLoaded: Bool
    var loadedContext: Int?
    var maxContext: Int?
    var supportsTools: Bool
    var supportsVision: Bool
    var sizeBytes: Int64?
    /// Parallel slots of a loaded model on this Mac's LM Studio (`lms ps`): requests it serves at once.
    var parallel: Int? = nil
    /// What the server lists beyond that (OpenRouter, Ollama): the output cap, reasoning, and the list price.
    var maxOutput: Int? = nil
    var supportsReasoning: Bool? = nil
    var price: PriceList.Price? = nil
    /// Whether an OpenAI-compatible server said the model takes images (nil: it didn't say).
    var imagesListed: Bool? = nil

    /// Whether the model takes images: LM Studio's report, else what the list said, else yes (Claude, Gemini, and
    /// servers that don't say).
    func acceptsImages(_ kind: Endpoint.Kind) -> Bool { kind == .lmstudio ? supportsVision : imagesListed ?? true }

    var contextLength: Int? { loadedContext ?? maxContext }
}

/// Models for one endpoint, plus whether its server answered.
struct ModelCatalog {
    enum Reachability: Equatable { case unknown, reachable, unreachable(String) }

    var entries: [ModelEntry] = []
    var reachability: Reachability = .unknown
    var refreshedAt: Date?

    func entry(_ id: String) -> ModelEntry? { entries.first { $0.id == id } }

    /// `apiKey` is called only if the server rejects an unauthenticated request.
    static func fetch(endpoint: Endpoint, apiKey: @escaping @Sendable () async -> String?) async -> ModelCatalog {
        var catalog = ModelCatalog()
        do {
            switch endpoint.kind {
            case .lmstudio:
                async let infos = LMStudioService(endpoint: endpoint).models()
                async let files: [LMSCLI.LocalModel]? = endpoint.isLocal ? try? LMSCLI().localModels() : nil
                async let running: [LMSCLI.LoadedModel]? = endpoint.isLocal ? try? LMSCLI().loadedModels() : nil
                let sizes = Dictionary((await files ?? []).map { ($0.modelKey, $0) }, uniquingKeysWith: { a, _ in a })
                let slots = Dictionary((await running ?? []).compactMap { m in m.parallel.map { (m.identifier, $0) } },
                                       uniquingKeysWith: { a, _ in a })
                catalog.entries = try await infos.filter(\.isChatModel).map { m in
                    ModelEntry(id: m.id,
                               displayName: sizes[m.id]?.displayName ?? m.id,
                               isLoaded: m.state == .loaded,
                               loadedContext: m.loadedContextLength,
                               maxContext: m.maxContextLength,
                               supportsTools: m.supportsTools,
                               supportsVision: m.supportsVision,
                               sizeBytes: sizes[m.id]?.sizeBytes,
                               parallel: m.state == .loaded ? slots[m.id] : nil)
                }
            case .openai:
                let models: [ListedModel]
                do {
                    models = try await ChatClient(endpoint: endpoint).models()
                } catch ChatError.http(let status, _) where status == 401 || status == 403 {
                    models = try await ChatClient(endpoint: endpoint, apiKey: await apiKey()).models()
                }
                // What the server says (OpenRouter, vLLM, Ollama list context and capabilities); otherwise tools are
                // assumed and images aren't. A context entered for the endpoint wins.
                catalog.entries = models.map { m in
                    ModelEntry(id: m.id, displayName: m.id, isLoaded: true, loadedContext: nil,
                               maxContext: endpoint.manualContextLength ?? m.contextLength.map { min($0, Endpoint.nativeContextCap) },
                               supportsTools: m.supportsTools ?? true, supportsVision: m.supportsImages ?? false, sizeBytes: nil,
                               maxOutput: m.maxOutputTokens, supportsReasoning: m.supportsReasoning, price: m.price,
                               imagesListed: m.supportsImages)
                }
            case .anthropic, .gemini:
                // These always need the key, and list each model's context (capped: see `nativeContextCap`).
                let models = try await ChatClient(endpoint: endpoint, apiKey: await apiKey()).models()
                catalog.entries = models.map { m in
                    ModelEntry(id: m.id, displayName: m.displayName ?? m.id, isLoaded: true, loadedContext: nil,
                               maxContext: endpoint.manualContextLength ?? m.contextLength.map { min($0, Endpoint.nativeContextCap) },
                               supportsTools: true, supportsVision: true, sizeBytes: nil)
                }
            }
            catalog.entries.sort { ($0.isLoaded ? 0 : 1, $0.id) < ($1.isLoaded ? 0 : 1, $1.id) }
            catalog.reachability = .reachable
        } catch {
            catalog.reachability = .unreachable(error.localizedDescription)
        }
        catalog.refreshedAt = Date()
        return catalog
    }
}
