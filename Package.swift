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
        .library(name: "SwooshWidgets",  targets: ["SwooshWidgets"]),
        .library(name: "SwooshActantBackend", targets: ["SwooshActantBackend"]),
        .library(name: "SwooshGenerativeUI", targets: ["SwooshGenerativeUI"]),
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
        // Blockchain — Jupiter DEX aggregator + Solana wallet primitives
        .package(url: "https://github.com/jauyou/JupSwift.git", from: "1.2.0"),
        // BigInt — arbitrary-precision integers for EVM/Solana quantities
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        // Hyperliquid — perp/spot DEX (macOS .v12+, secp256k1 + CryptoSwift)
        .package(url: "https://github.com/tranhoangpich/hyperliquid-swift-sdk.git", from: "1.6.0"),
        // ActantDB — event-sourced agent backend (sibling repo, local path)
        .package(path: "../actantDB/sdks/swift"),
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
                "SwooshTUI",
                "SwooshProviders",
                "SwooshSecrets",
                "SwooshActantBackend",
                .product(name: "ActantAgent", package: "swift"),
                .product(name: "ActantDB",    package: "swift"),
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
                .product(name: "ActantAgent", package: "swift"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshKit — public SDK
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshKit",
            dependencies: [
                "SwooshCore",
                "SwooshActantBackend",
                .product(name: "ActantAgent", package: "swift"),
                .product(name: "ActantDB",    package: "swift"),
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
                "SwooshTools",
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Config, credentials, setup, diagnostics
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshConfig", dependencies: []),
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
        .target(name: "SwooshSecrets",    dependencies: []),   // Keychain + SecretRef
        .target(name: "SwooshProviders",  dependencies: ["SwooshTools", "SwooshSecrets"]),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Tools
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshTools",    dependencies: [
            .product(name: "BigInt", package: "BigInt")
        ]),
        .target(name: "SwooshToolsets", dependencies: [
            "SwooshTools",
            .product(name: "JupSwift", package: "JupSwift"),
            .product(name: "HyperliquidSwift", package: "hyperliquid-swift-sdk"),
        ]),

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
            name: "SwooshWorkers",
            dependencies: ["SwooshTools"]
        ),
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
        .target(name: "SwooshMCP",      dependencies: ["SwooshTools"]),
        .target(name: "SwooshSandbox",  dependencies: []),
        .target(name: "SwooshBrowser",  dependencies: []),
        .target(name: "SwooshMedia",    dependencies: []),
        .target(name: "SwooshPlugins",  dependencies: ["SwooshTools"]),
        .target(name: "SwooshMCPAuth",  dependencies: ["SwooshTools"]),
        .target(name: "SwooshNetworkPolicy", dependencies: ["SwooshTools"]),
        .target(name: "SwooshIntegrations",  dependencies: ["SwooshTools"]),
        .target(name: "SwooshSetup",         dependencies: ["SwooshTools"]),
        .target(name: "SwooshDoctor",        dependencies: ["SwooshTools"]),
        .target(name: "SwooshInstaller",     dependencies: ["SwooshTools"]),
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
            dependencies: ["SwooshCore", "SwooshVault", "SwooshBoard", "SwooshFirewall", "SwooshFlow", "SwooshSecrets", "SwooshProviders", "SwooshGenerativeUI"]
        ),
        .target(
            name: "SwooshWidgets",
            dependencies: ["SwooshSecrets", "SwooshProviders"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - ActantDB backend adapter
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshActantBackend",
            dependencies: [
                "SwooshCore",
                .product(name: "ActantDB",    package: "swift"),
                .product(name: "ActantAgent", package: "swift"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Generative UI (agent-emitted, native renderer)
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshGenerativeUI",
            dependencies: []
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Tests
        // ══════════════════════════════════════════════════════════════
        .testTarget(
            name: "SwooshApprovalsTests",
            dependencies: ["SwooshApprovals", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshBoardTests",
            dependencies: ["SwooshBoard", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshWorkersTests",
            dependencies: ["SwooshWorkers", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshMCPTests",
            dependencies: ["SwooshMCP", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshPluginsTests",
            dependencies: ["SwooshPlugins", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshMCPAuthTests",
            dependencies: ["SwooshMCPAuth", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshNetworkPolicyTests",
            dependencies: ["SwooshNetworkPolicy", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshIntegrationsTests",
            dependencies: ["SwooshIntegrations", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshSetupTests",
            dependencies: ["SwooshSetup", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshDoctorTests",
            dependencies: ["SwooshDoctor", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshInstallerTests",
            dependencies: ["SwooshInstaller", "SwooshTools"]
        ),
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
        .testTarget(
            name: "SwooshSecretsTests",
            dependencies: ["SwooshSecrets"]
        ),
        .testTarget(
            name: "SwooshProvidersTests",
            dependencies: ["SwooshProviders", "SwooshSecrets", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshUITests",
            dependencies: ["SwooshUI"]
        ),
        .testTarget(
            name: "SwooshWidgetsTests",
            dependencies: ["SwooshWidgets"]
        ),
        .testTarget(
            name: "SwooshActantBackendTests",
            dependencies: [
                "SwooshActantBackend",
                "SwooshCore",
                .product(name: "ActantDB", package: "swift"),
            ]
        ),
        .testTarget(
            name: "SwooshGenerativeUITests",
            dependencies: ["SwooshGenerativeUI"]
        ),
    ]
)
