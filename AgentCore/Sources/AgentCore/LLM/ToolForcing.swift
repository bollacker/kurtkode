import Foundation

/// Whether a server can be made to call a given tool (A7). LM Studio can't: it rejects OpenAI's named `tool_choice`
/// ("Supported string values: none, auto, required"), and with "required" qwen3-coder-30b still answered in text
/// (2026-10-26). OpenRouter and OpenAI take the named choice, Gemini its `ANY` mode; Claude only with thinking off.
public enum ToolForcing {
    public static func supported(client: ChatClient, model: String, effort: String?) -> Bool {
        switch client.api {
        case .gemini: return true
        case .anthropic: return AnthropicWire.canForceTool(model: model, effort: effort)
        case .openai:
            let host = client.baseURL.host()?.lowercased() ?? ""
            return (host.hasSuffix("openrouter.ai") || host == "api.openai.com") && !claudeThinking(model: model, effort: effort)
        }
    }

    /// Whether kurtkode may write a tool call into the conversation itself: not for Claude with thinking on (natively or
    /// through OpenRouter), whose next request then needs the call's turn to begin with a thinking block.
    public static func canWrite(client: ChatClient, model: String, effort: String?) -> Bool {
        switch client.api {
        case .anthropic: return AnthropicWire.canForceTool(model: model, effort: effort)
        case .gemini: return true
        case .openai: return !claudeThinking(model: model, effort: effort)
        }
    }

    /// Claude on an OpenAI-compatible server with a reasoning level set (OpenRouter turns it into thinking).
    static func claudeThinking(model: String, effort: String?) -> Bool {
        let m = model.lowercased()
        return (m.contains("claude") || m.hasPrefix("anthropic/")) && effort.map { $0.lowercased() != "none" } == true
    }
}
