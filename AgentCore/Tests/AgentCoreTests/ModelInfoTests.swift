import Foundation
import Testing
@testable import AgentCore

@Test func decodesLMStudioModelList() throws {
    let url = try #require(Bundle.module.url(forResource: "api_v0_models", withExtension: "json",
                                             subdirectory: "Fixtures"))
    let models = try LMStudioService.decodeModels(Data(contentsOf: url))

    // 5 entries: loading with `lms load --identifier gemma26` adds the alias as its own entry.
    #expect(models.count == 5)
    let loaded = models.filter { $0.state == .loaded }
    #expect(!loaded.isEmpty)
    #expect(loaded.allSatisfy { $0.loadedContextLength != nil })

    let chat = models.filter(\.isChatModel)
    #expect(chat.count == 4)
    #expect(chat.allSatisfy { $0.supportsTools })

    let embed = try #require(models.first { $0.type == "embeddings" })
    #expect(!embed.isChatModel)
    #expect(!embed.supportsTools)
}
