import Foundation
import Testing
@testable import AgentCore
@testable import EvalKit
@testable import KurtkodeCLI

/// The live cascade's data folder (REAL_TASKS_PLAN.md "Cascade, live"): the product's own escalation picks the strong model.
@Suite struct CascadeTests {
    @Test func theProductsEscalationGoesToTheStrongModel() throws {
        let top = FileManager.default.temporaryDirectory.appending(path: "kk-cascade-test-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: top) }
        let openRouter = Endpoint(name: "Openrouter", kind: .openai, baseURL: URL(string: "https://openrouter.ai/api/v1")!, usesAPIKey: true)
        let user = top.appending(path: "user")
        try EndpointStore(fileURL: user.appending(path: "endpoints.json")).save([openRouter])
        var cheap = ModelTarget(endpoint: openRouter, model: "anthropic/claude-haiku-5.5")
        cheap.profile.providers = ProviderRouting(dataCollection: "deny")
        let strong = ModelTarget(endpoint: openRouter, model: "anthropic/claude-sonnet-5.5")
        let support = top.appending(path: "support")
        try Cascade.makeSupport(at: support, userSupport: user, cheap: cheap, strong: strong)

        let settings = AppSettings(support: support, defaults: UserDefaults(suiteName: "kk-cascade-test-\(UUID().uuidString.prefix(6))"),
                                   environment: ["KURTKODE_NO_KEYCHAIN": "1"])
        #expect(settings.sessionStore.root.path.hasPrefix(support.path))     // sessions stay out of the app's folder
        let e = try #require(settings.endpoints.first { $0.id == openRouter.id })
        let tier = try #require(Escalation.tier(endpoint: e, model: cheap.model, pool: settings.pool, endpoints: settings.endpoints))
        #expect(tier == .standard)
        let to = try #require(Escalation.target(above: tier, current: (e.id, cheap.model), pool: settings.pool, endpoints: settings.endpoints))
        #expect(to.model == strong.model && to.entry.providers == nil)
        #expect(settings.pool.entries.first?.providers?.dataCollection == "deny")
    }
}
