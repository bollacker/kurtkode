import Foundation
import Testing
@testable import AgentCore
@testable import KurtkodeCLI

private final class Text: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String] = []
    func add(_ s: String) { lock.withLock { parts.append(s) } }
    var all: String { lock.withLock { parts.joined() } }
}

/// CACHING_PLAN.md Phase 0: prompt prints, naming a cache miss, and the what-ifs over recorded requests.
struct CacheLedgerTests {
    static let header = SessionHeader(endpointID: UUID(), model: "claude-opus-5-5")
    static let anthropic = PriceList.Rates(input: 4, output: 20, cacheRead: 0.2, cacheWrite5m: 5, cacheWrite1h: 8)

    static func entry(prompt: Int, read: Int, write: Int = 0, hour: Int = 0, at start: Date, model: String = "claude-opus-5-5",
                      rates: PriceList.Rates = anthropic, provider: String? = nil) -> CostEntry {
        var m = ChatMessage(role: .assistant, content: "x")
        var meta = TurnMeta.test
        meta.usage = Usage(promptTokens: prompt, completionTokens: 100, cacheReadTokens: read, cacheWriteTokens: write,
                           cacheWriteHourTokens: hour)
        m.meta = meta
        let price = PriceLookup.known(PriceList.Price(standard: rates, longAbove: nil, long: nil, perSearch: nil, perRequest: nil),
                                      source: "t", version: "t")
        var e = CostEntry.make(reply: m, purpose: .reply, run: nil, agent: "main",
                               client: ChatClient(baseURL: URL(string: "https://api.anthropic.com/v1")!, api: .anthropic),
                               endpointID: nil, start: start, price: price)
        e.requestedModel = model
        e.start = start
        e.end = start.addingTimeInterval(5)
        e.provider = provider
        return e
    }

    static func request(_ messages: [ChatMessage], tools: [ToolDefinition] = [], effort: String? = nil) -> ChatRequest {
        var r = ChatRequest(model: "m", messages: [.system("rules")] + messages, tools: tools, maxTokens: 100)
        r.reasoningEffort = effort
        return r
    }

    @Test func aPrintTellsWhetherTheHistoryWasOnlyAddedTo() {
        let a = ChatMessage(role: .user, content: "fix it"), b = ChatMessage(role: .assistant, content: "done")
        let first = PromptPrint.of(Self.request([a])).print
        #expect(first.messages == 1)
        #expect(PromptPrint.of(Self.request([a, b]), previous: first).extends == true)
        #expect(PromptPrint.of(Self.request([a]), previous: first).extends == true)        // the same history again
        var edited = a
        edited.content = "fix it, please"
        #expect(PromptPrint.of(Self.request([edited, b]), previous: first).extends == false)
        let tool = ToolDefinition(name: "read", description: "Reads", parameters: ["type": "object"])
        #expect(PromptPrint.of(Self.request([a], tools: [tool])).print.tools != first.tools)
        #expect(PromptPrint.of(Self.request([a], effort: "high")).print.effort == "high")
    }

    @Test func aMissIsNamedByWhatChanged() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let warm = Self.entry(prompt: 50_000, read: 48_000, at: t0)
        func next(after seconds: Double, read: Int = 1_000, model: String = "claude-opus-5-5", provider: String? = nil) -> CostEntry {
            Self.entry(prompt: 52_000, read: read, write: 51_000, at: warm.end.addingTimeInterval(seconds), model: model, provider: provider)
        }
        // Read about all the previous prompt: no miss.
        #expect(CacheLedger.classify(previous: warm, current: next(after: 10, read: 49_000)) == nil)
        #expect(CacheLedger.classify(previous: warm, current: next(after: 10))?.cause == .evicted)
        #expect(CacheLedger.classify(previous: warm, current: next(after: 400))?.cause == .ttl)
        #expect(CacheLedger.classify(previous: warm, current: next(after: 10, model: "claude-sonnet-5-5"))?.cause == .model)
        #expect(CacheLedger.classify(previous: warm, current: next(after: 10),
                                     changes: CacheLedger.Changes(compacted: true))?.cause == .compaction)
        #expect(CacheLedger.classify(previous: warm, current: next(after: 10),
                                     changes: CacheLedger.Changes(extends: false))?.cause == .history)
        var p = warm, c = next(after: 10)
        p.provider = "Anthropic"; c.provider = "Google"
        #expect(CacheLedger.classify(previous: p, current: c)?.cause == .provider)
        // An hour's cache doesn't expire in 400 s.
        let hourly = Self.entry(prompt: 50_000, read: 0, write: 50_000, hour: 50_000, at: t0)
        #expect(CacheLedger.classify(previous: hourly, current: next(after: 400))?.cause == .evicted)
        // The prints tell a tool-list change from the rest.
        var pp = warm, cc = next(after: 10)
        pp.prompt = PromptPrint(tools: "a", system: "s", messages: 1, history: "h", model: "m")
        cc.prompt = PromptPrint(tools: "b", system: "s", messages: 2, history: "i", model: "m")
        let miss = CacheLedger.classify(previous: pp, current: cc)
        #expect(miss?.cause == .tools)
        #expect(miss?.lostTokens == 49_000)
        // 49k tokens written at $5/M instead of read at $0.20/M (the request paid write rates for its uncached part).
        #expect(abs((miss?.lost ?? 0) - 49_000 * (5.0 - 0.2) / 1_000_000) < 0.001)
    }

    @Test func theTTLWhatIfRepricesPauses() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // A 5-minute cache: the second request comes 10 minutes later and writes the whole prompt again.
        let a = Self.entry(prompt: 100_000, read: 0, write: 100_000, at: t0)
        let b = Self.entry(prompt: 101_000, read: 0, write: 101_000, at: a.end.addingTimeInterval(600))
        var s = CacheLedger.steps([(Self.header, a), (Self.header, b)])
        #expect(s.count == 2 && s[1].miss?.cause == .ttl)
        let hour = CacheLedger.ttlWhatIf(s, ttl: "1h")
        // As recorded: 201k written at $5. With an hour: 100k + 1k written at $8, 100k read at $0.20.
        #expect(abs(hour.actual - 201_000 * 5 / 1e6) < 1e-6)
        #expect(abs(hour.whatIf - (101_000 * 8 + 100_000 * 0.2) / 1e6) < 1e-6)
        // The other way: an hour's cache that held over the pause, repriced at five minutes.
        let c = Self.entry(prompt: 100_000, read: 0, write: 100_000, hour: 100_000, at: t0)
        let d = Self.entry(prompt: 101_000, read: 100_000, write: 1_000, hour: 1_000, at: c.end.addingTimeInterval(600))
        s = CacheLedger.steps([(Self.header, c), (Self.header, d)])
        let five = CacheLedger.ttlWhatIf(s, ttl: "5m")
        #expect(abs(five.whatIf - 201_000 * 5 / 1e6) < 1e-6)
    }

    @Test func theCompactionWhatIfOnlyCountsSessionsThatGrewPastIt() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var list: [(SessionHeader, CostEntry)] = []
        for i in 0..<60 {          // 20k growing by 5k a request to 315k, each step reading the last
            let p = 20_000 + i * 5_000
            list.append((Self.header, Self.entry(prompt: p, read: max(0, p - 5_000), write: min(p, 5_000),
                                                        at: t0.addingTimeInterval(Double(i) * 20))))
        }
        let steps = CacheLedger.steps(list)
        let at150 = CacheLedger.compactionWhatIf(steps, threshold: 150_000)
        #expect(at150.sessions == 1)
        #expect(at150.estimate < at150.actual)
        #expect(CacheLedger.compactionWhatIf(steps, threshold: 400_000).sessions == 0)
    }

    @Test func aColdLargeSessionIsPricedBeforeItsNextMessage() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let last = Self.entry(prompt: 300_000, read: 290_000, write: 10_000, at: t0)
        // Warm within five minutes, or small, or unpriced: nothing to say.
        #expect(CacheLedger.coldResumeNote(last: last, now: last.end.addingTimeInterval(200)) == nil)
        #expect(CacheLedger.coldResumeNote(last: Self.entry(prompt: 20_000, read: 0, at: t0), now: t0.addingTimeInterval(3600)) == nil)
        #expect(CacheLedger.coldResumeNote(last: nil) == nil)
        let note = try #require(CacheLedger.coldResumeNote(last: last, now: last.end.addingTimeInterval(1800)))
        // 300k written at $5/M; /compact: that, a 4k summary at $20/M and 40k written again; then 260k less read at $0.20/M.
        #expect(note.contains("idle 30 minutes") && note.contains("300k tokens"))
        #expect(note.contains("about $1.50") && note.contains("about $1.78") && note.contains("$0.05 less each"))
        // An hour's cache is still warm after 30 minutes.
        let hourly = Self.entry(prompt: 300_000, read: 290_000, write: 10_000, hour: 10_000, at: t0)
        #expect(CacheLedger.coldResumeNote(last: hourly, now: hourly.end.addingTimeInterval(1800)) == nil)
        #expect(CacheLedger.coldResumeNote(last: hourly, now: hourly.end.addingTimeInterval(7300))?.contains("idle 2 hours") == true)
    }

    @Test func theCacheReportRunsOverAStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cacheledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(root: dir)
        let text = Text()
        try await DebugCommands.cacheReport(store: store, options: DebugCommands.Parsed(), out: { text.add($0) })
        #expect(text.all.contains("0 reply requests"))
    }
}
