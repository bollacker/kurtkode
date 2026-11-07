import Foundation

/// The environment kurtkode hands the processes it starts for a model or a project (commands, MCP servers, hooks): its
/// own, less the API keys it consumed. A command's `env` in Plan mode on a remote model would otherwise send another
/// provider's key to a third party, and a project's MCP server or hook would read it; `.env` withholding covers files,
/// not variables. What the user's own login profile exports comes back in a `zsh -l`, so a key the user keeps there
/// still reaches the commands that need it: only what kurtkode was launched with is held back.
enum ChildEnvironment {
    /// The variables kurtkode reads keys from (`Settings.apiKey`, `Endpoint.Kind.standardKeyVariables`), and the other
    /// providers' usual ones.
    static let secretNames: Set<String> = Set(Endpoint.Kind.allCases.flatMap(\.standardKeyVariables))
        .union(["ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY"])

    static func isSecret(_ name: String) -> Bool {
        name.hasPrefix("KURTKODE_API_KEY_") || secretNames.contains(name)
    }

    /// `environment` without the keys.
    static func stripped(_ environment: [String: String]) -> [String: String] {
        environment.filter { !isSecret($0.key) }
    }

    /// kurtkode's own environment without the keys.
    static var inherited: [String: String] { stripped(ProcessInfo.processInfo.environment) }
}
