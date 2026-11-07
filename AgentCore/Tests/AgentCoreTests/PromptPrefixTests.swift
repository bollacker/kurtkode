import Foundation
import Testing
@testable import AgentCore

/// The system prompt keeps what changes between runs (the project root, the date, the git status) in its last
/// section, so runs in different folders or on different days share a cacheable prefix (COST_AUDIT.md F4,
/// improvement 1), and the Claude wire formats put a cache breakpoint before that section.
@Suite struct PromptPrefixTests {
    func folder() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "kurtkode-prefix-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("print(1)\n".utf8).write(to: root.appending(path: "main.py"))
        return root
    }

    func builder(_ root: URL) -> SystemPromptBuilder {
        var b = SystemPromptBuilder(workspace: Workspace(path: root.path), tools: AllTools.all, mode: .fullAuto,
                                    globalInstructions: root.appending(path: ".none"))
        b.userFiles = false
        return b
    }

    @Test func runsInOtherFoldersOnOtherDaysShareTheStablePart() async throws {
        let a = try folder(), b = try folder()
        let day2 = Date().addingTimeInterval(86_400 * 3)
        let (textA, factsA) = await builder(a).buildWithFacts()
        let (textB, _) = await builder(b).buildWithFacts(now: day2)
        let (stableA, volatileA) = SystemPromptBuilder.splitVolatile(textA)
        let (stableB, volatileB) = SystemPromptBuilder.splitVolatile(textB)
        #expect(stableA + volatileA == textA)
        #expect(stableA == stableB)
        #expect(!stableA.contains(a.path) && !stableA.contains("- Date: "))
        #expect(volatileA.contains("- Project root: " + a.path) && volatileA.hasSuffix(factsA))
        #expect(volatileB.contains(b.path) && volatileA != volatileB)
        // The tools and the platform stay in the stable part.
        #expect(stableA.contains("Tools available: ") && stableA.contains("- Platform: macOS"))
    }

    @Test func stableExtrasGoBeforeTheChangingSection() async throws {
        let a = try folder()
        let base = await builder(a).build()
        let with = SystemPromptBuilder.insertingStable("ADDENDUM", into: base)
        #expect(SystemPromptBuilder.splitVolatile(with).stable.hasSuffix("\n\nADDENDUM"))
        #expect(SystemPromptBuilder.splitVolatile(with).volatile == SystemPromptBuilder.splitVolatile(base).volatile)
        #expect(SystemPromptBuilder.insertingStable("X", into: "plain") == "plain\n\nX")
        #expect(SystemPromptBuilder.insertingStable("X", into: "") == "X")
        #expect(SystemPromptBuilder.insertingStable("", into: base) == base)

        // A subagent's role, and a session's addendum, are part of the stable prefix.
        let sub = await SubagentSetup.defaultPrompt(workspace: Workspace(path: a.path), agent: .general, tools: AllTools.all,
                                                    mode: .fullAuto, globalInstructions: a.appending(path: ".none"), userFiles: false)
        #expect(SystemPromptBuilder.splitVolatile(sub).stable.contains("Your role (general): "))
        #expect(!SystemPromptBuilder.splitVolatile(sub).volatile.contains("Your role"))
        let frozen = FrozenSystemPrompt()
        let session = await frozen.text(workspace: Workspace(path: a.path), tools: AllTools.all, mode: .ask, sandbox: nil,
                                        userPrompt: "", addendum: "MODEL NOTE")
        #expect(SystemPromptBuilder.splitVolatile(session).stable.hasSuffix("MODEL NOTE"))
    }

    let system = "RULES\n\nTools available: read_file.\n\n" + SystemPromptBuilder.volatileHeading + "\n- Project root: /tmp/x\n- Date: Monday"

    @Test func anthropicMarksTheStablePartOfTheSystemPrompt() throws {
        var r = ChatRequest(model: "claude-haiku-5-5", messages: [.system(system), .user("hi")], maxTokens: 100)
        func body() throws -> [String: JSONValue] {
            guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: AnthropicWire.encodeRequest(r)) else { return [:] }
            return o
        }
        let ephemeral: JSONValue = ["type": "ephemeral"]
        #expect(try body()["system"] == [["type": "text", "text": "RULES\n\nTools available: read_file.", "cache_control": ephemeral],
                                          ["type": "text", "text": .string(SystemPromptBuilder.volatileHeading + "\n- Project root: /tmp/x\n- Date: Monday")]])
        #expect(try body()["cache_control"] == ephemeral)            // the automatic breakpoint still covers the history
        r.cacheForAnHour = true
        guard case .array(let blocks)? = try body()["system"], case .object(let first) = blocks[0] else { Issue.record("no blocks"); return }
        #expect(first["cache_control"] == ["type": "ephemeral", "ttl": "1h"])   // same TTL as the automatic one
        // A prompt without the section is sent as one string, as before.
        r.messages = [.system("You are kurtkode."), .user("hi")]
        #expect(try body()["system"] == "You are kurtkode.")
    }

    @Test func claudeOnOpenRouterMarksTheStablePartOfTheSystemPrompt() throws {
        let r = ChatRequest(model: "anthropic/claude-haiku-5.5", messages: [.system(system), .user("hi")], maxTokens: 100)
        let data = try ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai).encode(r)
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data), case .array(let ms)? = o["messages"] else {
            Issue.record("no messages"); return
        }
        let ephemeral: JSONValue = ["type": "ephemeral"]
        #expect(ms[0] == ["role": "system", "content": [
            ["type": "text", "text": "RULES\n\nTools available: read_file.", "cache_control": ephemeral],
            ["type": "text", "text": .string(SystemPromptBuilder.volatileHeading + "\n- Project root: /tmp/x\n- Date: Monday")]]])
        // Other models get the text unchanged: their providers cache prefixes by themselves.
        let plain = try ChatClient(baseURL: URL(string: "https://openrouter.ai/api/v1")!, api: .openai)
            .encode(ChatRequest(model: "inclusionai/ling-3.0-flash", messages: [.system(system), .user("hi")], maxTokens: 100))
        guard case .object(let p) = try JSONDecoder().decode(JSONValue.self, from: plain), case .array(let pm)? = p["messages"] else { return }
        #expect(pm[0] == ["role": "system", "content": .string(system)])
    }
}
