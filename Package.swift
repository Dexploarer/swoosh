// swift-tools-version: 6.3
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Swoosh",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // ── Executables ───────────────────────────────────────────────
        .executable(name: "swoosh",  targets: ["SwooshCLI"]),
        .executable(name: "swooshd", targets: ["SwooshDaemon"]),

        // ── Public SDK ────────────────────────────────────────────────
        .library(name: "SwooshKit", targets: ["SwooshKit"]),

        // ── Individual libraries ──────────────────────────────────────
        .library(name: "SwooshCore",      targets: ["SwooshCore"]),
        .library(name: "SwooshConfig",    targets: ["SwooshConfig"]),
        .library(name: "SwooshScout",     targets: ["SwooshScout"]),
        .library(name: "SwooshStorage",   targets: ["SwooshStorage"]),
        .library(name: "SwooshDBClient",  targets: ["SwooshDBClient"]),
        .library(name: "SwooshTUI",       targets: ["SwooshTUI"]),
        .library(name: "SwooshVault",     targets: ["SwooshVault"]),
        .library(name: "SwooshFirewall",  targets: ["SwooshFirewall"]),
        .library(name: "SwooshFlow",      targets: ["SwooshFlow"]),
        .library(name: "SwooshBoard",     targets: ["SwooshBoard"]),
        .library(name: "SwooshTriggers",  targets: ["SwooshTriggers"]),
        .library(name: "SwooshMLX",       targets: ["SwooshMLX"]),
        .library(name: "SwooshFoundation",targets: ["SwooshFoundation"]),
        .library(name: "SwooshBridge",    targets: ["SwooshBridge"]),
        .library(name: "SwooshUI",        targets: ["SwooshUI"]),
        .library(name: "SwooshApprovals", targets: ["SwooshApprovals"]),
    ],
    dependencies: [
        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Local inference
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.0.0"),
        // Database
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
        // HTTP server
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        // Logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.4"),
        // Macros infrastructure
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ],
    targets: [
        // ══════════════════════════════════════════════════════════════
        // MARK: - CLI & Daemon
        // ══════════════════════════════════════════════════════════════
        .executableTarget(
            name: "SwooshCLI",
            dependencies: [
                "SwooshKit",
                "SwooshConfig",
                "SwooshScout",
                "SwooshStorage",
                "SwooshDBClient",
                "SwooshTUI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SwooshDaemon",
            dependencies: [
                "SwooshKit",
                "SwooshConfig",
                "SwooshAPI",
                "SwooshGateway",
                "SwooshTriggers",
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshKit — public SDK
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshKit",
            dependencies: [
                "SwooshCore",
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - @SwooshTool macro
        // ══════════════════════════════════════════════════════════════
        .macro(
            name: "SwooshMacroPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "SwooshMacros",
            dependencies: ["SwooshMacroPlugin"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Core runtime
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshCore",
            dependencies: [
                "SwooshStorage",
                "SwooshTools",
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Config, credentials, setup, diagnostics
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshConfig", dependencies: []),
        .target(
            name: "SwooshStorage",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(
            name: "SwooshDBClient",
            dependencies: ["SwooshStorage"]
        ),
        .target(name: "SwooshTUI", dependencies: []),
        .target(
            name: "SwooshObservability",
            dependencies: [.product(name: "Logging", package: "swift-log")]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Scout — personalization scanner
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshScout", dependencies: []),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Models & inference
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshModels",    dependencies: []),  // Standalone model catalog + HF discovery
        .target(
            name: "SwooshMLX",
            dependencies: [
                .product(name: "MLX",           package: "mlx-swift"),
                .product(name: "MLXRandom",     package: "mlx-swift"),
                .product(name: "MLXNN",         package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXLLM",        package: "mlx-swift-lm"),
                .product(name: "MLXVLM",        package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon",   package: "mlx-swift-lm"),
            ]
        ),
        .target(name: "SwooshFoundation", dependencies: []),   // Apple Foundation Models adapter
        .target(name: "SwooshProviders",  dependencies: []),   // OpenAI / Anthropic / OpenRouter etc.

        // ══════════════════════════════════════════════════════════════
        // MARK: - Tools
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshTools",    dependencies: []),
        .target(name: "SwooshToolsets", dependencies: ["SwooshTools"]),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Differentiating subsystems
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshVault",
            dependencies: [
                "SwooshTools",
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(name: "SwooshFirewall", dependencies: [
            "SwooshTools",
            .product(name: "SQLite", package: "SQLite.swift"),
        ]),
        .target(name: "SwooshFlow",     dependencies: ["SwooshTools", "SwooshFirewall"]),
        .target(name: "SwooshSkills",   dependencies: []),
        .target(
            name: "SwooshBoard",
            dependencies: [
                "SwooshTools",
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(name: "SwooshTriggers", dependencies: []),
        .target(
            name: "SwooshApprovals",
            dependencies: ["SwooshTools"]
        ),
        .target(
            name: "SwooshFiles",
            dependencies: ["SwooshTools"]
        ),
        .target(
            name: "SwooshProcess",
            dependencies: ["SwooshTools"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Infrastructure
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshGateway",  dependencies: []),
        .target(name: "SwooshMCP",      dependencies: []),
        .target(name: "SwooshSandbox",  dependencies: []),
        .target(name: "SwooshBrowser",  dependencies: []),
        .target(name: "SwooshMedia",    dependencies: []),
        .target(name: "SwooshPlugins",  dependencies: []),
        .target(name: "SwooshLSP",      dependencies: []),
        .target(name: "SwooshBridge",   dependencies: ["SwooshTools"]),
        .target(name: "SwooshBench",    dependencies: ["SwooshTools"]),

        // ══════════════════════════════════════════════════════════════
        // MARK: - API server
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshAPI",
            dependencies: [
                "SwooshCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwiftUI (shared)
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshUI",
            dependencies: ["SwooshCore", "SwooshVault", "SwooshBoard", "SwooshFirewall", "SwooshFlow"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Tests
        // ══════════════════════════════════════════════════════════════
        .testTarget(
            name: "SwooshTUITests",
            dependencies: ["SwooshTUI"]
        ),
        .testTarget(
            name: "SwooshCoreTests",
            dependencies: ["SwooshCore"]
        ),
        .testTarget(
            name: "SwooshToolsTests",
            dependencies: ["SwooshTools", "SwooshFirewall", "SwooshToolsets"]
        ),
        .testTarget(
            name: "SwooshAgentLoopTests",
            dependencies: ["SwooshCore", "SwooshTools", "SwooshFirewall", "SwooshApprovals", "SwooshToolsets"]
        ),
        .testTarget(
            name: "SwooshDevToolsTests",
            dependencies: ["SwooshTools", "SwooshFiles", "SwooshProcess", "SwooshFirewall"]
        ),
        .testTarget(
            name: "SwooshFlowTests",
            dependencies: ["SwooshFlow", "SwooshTools", "SwooshFirewall"]
        ),
    ]
)
