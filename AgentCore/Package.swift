// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .executable(name: "kurtkode-eval", targets: ["kurtkode-eval"]),
        .executable(name: "kurtkode", targets: ["kurtkode"]),
    ],
    targets: [
        // Prompts: the system prompt's default templates (SYSTEM_PROMPT.md). BuiltinSkills: the skills every session
        // has unless Settings turns them off (skilllib/ holds their docs and tests). Bin: ripgrep for the grep tool.
        .target(name: "AgentCore", resources: [.copy("Prompts"), .copy("BuiltinSkills"), .copy("Bin")]),
        // Scenarios, fixtures, and the runner for evaluating models; a library so its checks are testable.
        .target(name: "EvalKit", dependencies: ["AgentCore", "KurtkodeCLI"]),
        .executableTarget(name: "kurtkode-eval", dependencies: ["EvalKit", "AgentCore"]),
        // The agent in a terminal; the library holds what's testable (options, the session driver, rendering).
        .target(name: "KurtkodeCLI", dependencies: ["AgentCore", "CEditLine"]),
        // macOS's libedit, for line editing and history at the kurtkode prompt.
        .systemLibrary(name: "CEditLine"),
        .executableTarget(name: "kurtkode", dependencies: ["KurtkodeCLI", "AgentCore"]),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: ["AgentCore", "EvalKit", "KurtkodeCLI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
