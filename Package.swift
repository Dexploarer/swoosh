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
        .library(name: "SwooshSecrets",   targets: ["SwooshSecrets"]),
        .library(name: "SwooshUI",        targets: ["SwooshUI"]),
        .library(name: "SwooshApprovals", targets: ["SwooshApprovals"]),
        .library(name: "SwooshWidgets",  targets: ["SwooshWidgets"]),
        .library(name: "SwooshActantBackend", targets: ["SwooshActantBackend"]),
        .library(name: "SwooshGenerativeUI", targets: ["SwooshGenerativeUI"]),
        .library(name: "SwooshClient",       targets: ["SwooshClient"]),
        .library(name: "SwooshWallet",       targets: ["SwooshWallet"]),
        .library(name: "SwooshDaemonSupport", targets: ["SwooshDaemonSupport"]),
        .library(name: "SwooshGoals",        targets: ["SwooshGoals"]),
        .library(name: "SwooshManifesting",  targets: ["SwooshManifesting"]),
        .library(name: "SwooshProviderBridge", targets: ["SwooshProviderBridge"]),
        .library(name: "SwooshCron", targets: ["SwooshCron"]),
        .library(name: "SwooshChatSDK", targets: ["SwooshChatSDK"]),
    ],
    dependencies: [
        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Local inference
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.0.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx", exact: "0.3.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", exact: "0.5.0"),
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
        // secp256k1 — EVM key signing for the iOS in-app wallet
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.16.0"),
        // CryptoSwift — keccak256 for EVM address derivation in the iOS wallet
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        // Hyperliquid — perp/spot DEX (macOS .v12+, secp256k1 + CryptoSwift)
        .package(path: "Vendor/hyperliquid-swift-sdk"),
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
                "SwooshClient",
                "SwooshConfig",
                "SwooshScout",
                "SwooshTUI",
                "SwooshProviders",
                "SwooshProviderBridge",
                "SwooshCron",
                "SwooshSkills",
                "SwooshToolsets",
                "SwooshChatSDK",
                "SwooshSecrets",
                "SwooshDoctor",
                "SwooshActantBackend",
                "SwooshFirewall",
                "SwooshApprovals",
                "SwooshFiles",
                "SwooshProcess",
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
                "SwooshScout",
                "SwooshSkills",
                "SwooshGoals",
                "SwooshManifesting",
                "SwooshCron",
                "SwooshProviderBridge",
                "SwooshSecrets",
                "SwooshProviders",
                "SwooshDaemonSupport",
                "SwooshToolsets",
                "SwooshTools",
                "SwooshFirewall",
                "SwooshApprovals",
                "SwooshFiles",
                "SwooshProcess",
                "SwooshMLX",
                "SwooshFoundation",
                "SwooshActantBackend",
                .product(name: "ActantAgent", package: "swift"),
            ]
        ),
        .target(
            name: "SwooshDaemonSupport",
            dependencies: []
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshKit — public SDK
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshKit",
            dependencies: [
                "SwooshCore",
                "SwooshTools",
                "SwooshActantBackend",
                "SwooshClient",
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
            dependencies: ["SwooshMacroPlugin", "SwooshTools"]
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
        .target(name: "SwooshConfig", dependencies: ["SwooshClient", "SwooshTools"]),
        .target(name: "SwooshTUI", dependencies: ["SwooshTools"]),
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
                "SwooshCore",
                .product(name: "MLX",           package: "mlx-swift"),
                .product(name: "MLXRandom",     package: "mlx-swift"),
                .product(name: "MLXNN",         package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXLLM",        package: "mlx-swift-lm"),
                .product(name: "MLXVLM",        package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon",   package: "mlx-swift-lm"),
                .product(name: "MLXLMTokenizers", package: "swift-tokenizers-mlx"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
            ]
        ),
        .target(name: "SwooshFoundation", dependencies: ["SwooshCore"]),   // Apple Foundation Models adapter
        .target(name: "SwooshSecrets",    dependencies: ["SwooshTools"]),   // Keychain + SecretRef + SecretResolving
        .target(name: "SwooshProviders",  dependencies: ["SwooshTools", "SwooshSecrets"]),
        .target(
            name: "SwooshProviderBridge",
            dependencies: ["SwooshCore", "SwooshProviders", "SwooshSecrets", "SwooshTools"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - Tools
        // ══════════════════════════════════════════════════════════════
        .target(name: "SwooshTools",    dependencies: [
            .product(name: "BigInt", package: "BigInt")
        ]),
        .target(name: "SwooshToolsets", dependencies: [
            "SwooshTools",
            "SwooshFiles",
            "SwooshScout",
            "SwooshSkills",
            "SwooshGoals",
            "SwooshManifesting",
            "SwooshCron",
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
        .target(name: "SwooshSkills",       dependencies: ["SwooshTools"]),
        .target(name: "SwooshGoals",        dependencies: ["SwooshTools"]),
        .target(name: "SwooshManifesting",  dependencies: ["SwooshTools"]),
        .target(name: "SwooshCron", dependencies: ["SwooshTools"]),
        .target(name: "SwooshChatSDK", dependencies: ["SwooshClient"]),
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
        .target(name: "SwooshDoctor",        dependencies: ["SwooshTools", "SwooshConfig", "SwooshClient"]),
        .target(name: "SwooshInstaller",     dependencies: ["SwooshTools"]),
        .target(name: "SwooshLSP",      dependencies: []),
        .target(name: "SwooshBridge",   dependencies: ["SwooshTools"]),
        .target(name: "SwooshBench",    dependencies: ["SwooshTools"]),

        // ══════════════════════════════════════════════════════════════
        // MARK: - API server + transport-agnostic client
        // ══════════════════════════════════════════════════════════════
        // SwooshClient holds the wire format (Codable types) plus a
        // URLSession-based client. It is intentionally free of Hummingbird,
        // SwooshCore, or anything that touches `Process`, so the iOS app
        // can import it without pulling in the kernel or the actantdb
        // supervisor.
        .target(
            name: "SwooshClient",
            dependencies: []
        ),
        // SwooshWallet — iOS-safe in-app wallet primitives. Holds key
        // generation (CryptoKit ed25519 for Solana, secp256k1 for EVM),
        // Keychain-backed storage, base58 / hex / keccak helpers, and
        // direct JSON-RPC clients for Solana mainnet + ETH + Base + BNB.
        // Zero dependency on SwooshKit or any module that touches Process,
        // so it's safe to import from both the iOS app and the daemon.
        .target(
            name: "SwooshWallet",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "BigInt", package: "BigInt"),
            ]
        ),
        .target(
            name: "SwooshAPI",
            dependencies: [
                "SwooshCore",
                "SwooshClient",
                "SwooshConfig",
                "SwooshTools",
                "SwooshChatSDK",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwiftUI (shared)
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshUI",
            dependencies: ["SwooshCore", "SwooshClient", "SwooshConfig", "SwooshTools", "SwooshVault", "SwooshBoard", "SwooshFirewall", "SwooshFlow", "SwooshSecrets", "SwooshProviders", "SwooshGenerativeUI"]
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
                "SwooshTools",
                "SwooshApprovals",
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
            dependencies: ["SwooshCore", "SwooshTools", "SwooshFirewall", "SwooshApprovals"]
        ),
        .testTarget(
            name: "SwooshScoutTests",
            dependencies: ["SwooshScout"]
        ),
        .testTarget(
            name: "SwooshToolsTests",
            dependencies: ["SwooshTools", "SwooshFirewall", "SwooshToolsets"]
        ),
        .testTarget(
            name: "SwooshAgentLoopTests",
            dependencies: ["SwooshCore", "SwooshKit", "SwooshTools", "SwooshFirewall", "SwooshApprovals", "SwooshToolsets"]
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
            dependencies: ["SwooshProviders", "SwooshSecrets", "SwooshTools", "SwooshCore"]
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
                "SwooshTools",
                "SwooshApprovals",
                .product(name: "ActantDB", package: "swift"),
            ]
        ),
        .testTarget(
            name: "SwooshGenerativeUITests",
            dependencies: ["SwooshGenerativeUI"]
        ),
        .testTarget(
            name: "SwooshAPITests",
            dependencies: [
                "SwooshAPI",
                "SwooshCore",
                "SwooshConfig",
                "SwooshTools",
                "SwooshFirewall",
                "SwooshApprovals",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "SwooshClientTests",
            dependencies: ["SwooshClient", "SwooshChatSDK"]
        ),
        .testTarget(
            name: "SwooshWalletTests",
            dependencies: ["SwooshWallet"]
        ),
        .testTarget(
            name: "SwooshCronTests",
            dependencies: ["SwooshCron", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshSkillsTests",
            dependencies: ["SwooshSkills"]
        ),
        .testTarget(
            name: "SwooshChatSDKTests",
            dependencies: ["SwooshChatSDK", "SwooshClient"]
        ),
        .testTarget(
            name: "SwooshDaemonTests",
            dependencies: ["SwooshDaemonSupport"]
        ),
        .testTarget(
            name: "SwooshBrowserTests",
            dependencies: ["SwooshBrowser"]
        ),
        .testTarget(
            name: "SwooshMLXTests",
            dependencies: ["SwooshMLX", "SwooshCore"]
        ),
        .testTarget(
            name: "SwooshGoalsTests",
            dependencies: ["SwooshGoals", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshManifestingTests",
            dependencies: ["SwooshManifesting", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshObservabilityTests",
            dependencies: ["SwooshObservability"]
        ),
        .testTarget(
            name: "SwooshConfigTests",
            dependencies: ["SwooshConfig"]
        ),
        .testTarget(
            name: "SwooshFirewallTests",
            dependencies: ["SwooshFirewall", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshSandboxTests",
            dependencies: ["SwooshSandbox"]
        ),
        .testTarget(
            name: "SwooshVaultTests",
            dependencies: ["SwooshVault", "SwooshFirewall", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshTriggersTests",
            dependencies: ["SwooshTriggers"]
        ),
        .testTarget(
            name: "SwooshBridgeTests",
            dependencies: ["SwooshBridge", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshGatewayTests",
            dependencies: ["SwooshGateway"]
        ),
        .testTarget(
            name: "SwooshLSPTests",
            dependencies: ["SwooshLSP"]
        ),
        .testTarget(
            name: "SwooshMediaTests",
            dependencies: ["SwooshMedia"]
        ),
        .testTarget(
            name: "SwooshModelsTests",
            dependencies: ["SwooshModels"]
        ),
        .testTarget(
            name: "SwooshFoundationTests",
            dependencies: ["SwooshFoundation", "SwooshCore"]
        ),
        .testTarget(
            name: "SwooshKitTests",
            dependencies: ["SwooshKit", "SwooshClient", "SwooshCore"]
        ),
        .testTarget(
            name: "SwooshToolsetsTests",
            dependencies: [
                "SwooshToolsets",
                "SwooshTools",
                "SwooshFirewall",
                "SwooshFiles",
                "SwooshProcess",
            ]
        ),
    ]
)
