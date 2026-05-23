// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Swoosh",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        // ── Executables ───────────────────────────────────────────────
        .executable(name: "swoosh",  targets: ["SwooshCLIRunner"]),
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
        .library(name: "SwooshMLX",       targets: ["SwooshMLX"]),
        .library(name: "SwooshFoundation",targets: ["SwooshFoundation"]),
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
        .library(name: "SwooshLocalLLM", targets: ["SwooshLocalLLM"]),
        .library(name: "SwooshModels", targets: ["SwooshModels"]),
        .library(name: "SwooshSTT", targets: ["SwooshSTT"]),
        .library(name: "SwooshVoiceProviders", targets: ["SwooshVoiceProviders"]),
        .library(name: "SwooshLocalVoice", targets: ["SwooshLocalVoice"]),
        .library(name: "SwooshMusic", targets: ["SwooshMusic"]),
        .library(name: "SwooshVision", targets: ["SwooshVision"]),
        .library(name: "SwooshTranslation", targets: ["SwooshTranslation"]),
        .library(name: "SwooshEmbeddings", targets: ["SwooshEmbeddings"]),
        .library(name: "SwooshImageGen", targets: ["SwooshImageGen"]),
        .library(name: "SwooshCapabilities", targets: ["SwooshCapabilities"]),
        .library(name: "SwooshNetworkPolicy", targets: ["SwooshNetworkPolicy"]),
        .library(name: "SwooshCLI",          targets: ["SwooshCLI"]),
    ],
    dependencies: [
        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Local inference
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.0.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx", exact: "0.3.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", exact: "0.5.0"),
        .package(url: "https://github.com/DePasqualeOrg/swift-hf-api.git", from: "0.3.2"),
        // Database
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
        // HTTP server
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        // Blockchain primitives and DEX integrations
        // BigInt — arbitrary-precision integers for EVM/Solana quantities
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        // secp256k1 - EVM key signing for wallet primitives
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.16.0"),
        // CryptoSwift — keccak256 for EVM address derivation in the iOS wallet
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        // Hyperliquid — perp/spot DEX (macOS .v12+, secp256k1 + CryptoSwift)
        .package(path: "Vendor/hyperliquid-swift-sdk"),
        // ActantDB — event-sourced agent backend (sibling repo, local path)
        .package(path: "../actantDB/sdks/swift"),
        // WhisperKit — Apple Silicon-optimised speech-to-text via Core ML
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.0.0"),
        // FluidAudio — frontier CoreML audio models in Swift (Kokoro TTS
        // on ANE, VAD, diarization). Apache-2.0, drives the real Kokoro
        // backend in SwooshLocalVoice. iOS 17+ / macOS 14+.
        // 0.14.x lands Swift 6 strict-concurrency cleanups and an iOS 26
        // compatibility fix (heap corruption in KokoroAne ANE path).
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.7"),
        // WasmKit — embeddable WebAssembly runtime for the wasm-kind plugin
        // executor. Includes the `WAT` package so the bundled .wat demo can
        // be compiled at runtime without shipping a precompiled .wasm.
        .package(url: "https://github.com/swiftwasm/WasmKit.git", from: "0.2.0"),
    ],
    targets: [
        // ══════════════════════════════════════════════════════════════
        // MARK: - CLI & Daemon
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshCLI",
            dependencies: [
                "SwooshKit",
                "SwooshClient",
                "SwooshConfig",
                "SwooshScout",
                "SwooshTUI",
                "SwooshModels",
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
                "SwooshFlow",
                "SwooshApprovals",
                "SwooshFiles",
                "SwooshProcess",
                .product(name: "ActantAgent", package: "swift"),
                .product(name: "ActantDB",    package: "swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SwooshCLIRunner",
            dependencies: ["SwooshCLI"]
        ),
        .executableTarget(
            name: "SwooshDaemon",
            dependencies: [
                "SwooshKit",
                "SwooshConfig",
                "SwooshAPI",
                "SwooshScout",
                "SwooshSkills",
                "SwooshGoals",
                "SwooshManifesting",
                "SwooshCron",
                "SwooshDoctor",
                "SwooshProviderBridge",
                "SwooshSecrets",
                "SwooshModels",
                "SwooshProviders",
                "SwooshDaemonSupport",
                "SwooshToolsets",
                "SwooshTools",
                "SwooshFirewall",
                "SwooshFlow",
                "SwooshApprovals",
                "SwooshFiles",
                "SwooshProcess",
                "SwooshMLX",
                "SwooshFoundation",
                "SwooshActantBackend",
                "SwooshPlugins",
                "SwooshPluginRuntime",
                "SwooshDemoPlugins",
                "SwooshWallet",
                .product(name: "ActantAgent", package: "swift"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "secp256k1", package: "secp256k1.swift"),
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
                .product(name: "HFAPI", package: "swift-hf-api"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
            ]
        ),
        .target(name: "SwooshFoundation", dependencies: ["SwooshCore", "SwooshClient"]),   // Apple Foundation Models adapter
        .target(name: "SwooshSecrets",    dependencies: ["SwooshTools"]),   // Keychain + SecretRef + SecretResolving
        .target(name: "SwooshNetworkPolicy", dependencies: ["SwooshTools"]),   // Per-host outbound HTTP gate + audit fanout
        .target(name: "SwooshProviders",  dependencies: ["SwooshTools", "SwooshSecrets", "SwooshModels", "SwooshNetworkPolicy"]),
        .target(
            name: "SwooshProviderBridge",
            dependencies: ["SwooshCore", "SwooshProviders", "SwooshSecrets", "SwooshTools", "SwooshModels", "SwooshMLX"]
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
            "SwooshMCP",
            "SwooshClient",
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
            name: "SwooshApprovals",
            dependencies: ["SwooshTools"]
        ),
        // SwooshVision — Apple Vision wrapper (OCR, depth, foreground mask,
        // document recognition, face detection). Cross-platform.
        .target(
            name: "SwooshVision",
            dependencies: []
        ),
        // SwooshTranslation — Apple Translation framework + OpenAI fallback.
        // Cross-platform.
        .target(
            name: "SwooshTranslation",
            dependencies: []
        ),
        // SwooshEmbeddings — Apple NaturalLanguage + OpenAI cloud fallback
        // wrapped behind a single EmbeddingRouter. Cross-platform.
        .target(
            name: "SwooshEmbeddings",
            dependencies: []
        ),
        // SwooshImageGen — Apple Image Playground + OpenAI cloud fallback.
        // Cross-platform; the local provider gates on macOS 15.2+/iOS 18.2+.
        // Depends on SwooshTools so cloud providers can require permissions
        // and emit AuditEntry records through the Firewall + AuditLogging
        // protocols (concrete impls injected daemon-side; iOS picker passes
        // nil and the gating is a no-op).
        .target(
            name: "SwooshImageGen",
            dependencies: ["SwooshTools"]
        ),
        // SwooshCapabilities — unified router + status snapshot for the
        // four post-LLM modalities (Vision/Translation/Embeddings/ImageGen).
        // Mirrors the VoiceRouter pattern: UserDefaults-driven, swappable.
        // Reads API keys hot from SwooshSecrets' KeychainAPIKeyProvider so
        // a key written by any picker is picked up on the next provider call.
        .target(
            name: "SwooshCapabilities",
            dependencies: [
                "SwooshSecrets",
                "SwooshVision",
                "SwooshTranslation",
                "SwooshEmbeddings",
                "SwooshImageGen",
            ]
        ),
        .testTarget(
            name: "SwooshCapabilitiesTests",
            dependencies: ["SwooshCapabilities", "SwooshSecrets"]
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
        .target(name: "SwooshMCP",      dependencies: ["SwooshTools"]),
        .target(name: "SwooshPlugins",  dependencies: ["SwooshTools"]),
        // SwooshPluginRuntime — server-side plugin host. Owns the lifecycle
        // (enable/disable/install/uninstall), the bridge that turns plugin
        // tools into AnySwooshTool instances inside ToolRegistry, and the
        // per-kind executors. macOS/Linux only — iOS never links this.
        .target(
            name: "SwooshPluginRuntime",
            dependencies: [
                "SwooshPlugins",
                "SwooshTools",
                "SwooshFirewall",
                "SwooshMCP",
                .product(name: "WasmKit", package: "WasmKit"),
                .product(name: "WAT", package: "WasmKit"),
                .product(name: "WasmKitWASI", package: "WasmKit"),
            ]
        ),
        // SwooshDemoPlugins — reference Swift plugins linked into swooshd.
        // Authors copy this target's shape when writing their own Swift
        // plugin. Empty on iOS (the iOS app never loads plugins).
        .target(
            name: "SwooshDemoPlugins",
            dependencies: ["SwooshPlugins", "SwooshTools"]
        ),
        .target(name: "SwooshDoctor",        dependencies: ["SwooshTools", "SwooshConfig", "SwooshClient"]),

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
        // ══════════════════════════════════════════════════════════════
        // MARK: - LiteRT-LM (vendored Swift wrapper + binary)
        // ══════════════════════════════════════════════════════════════
        //
        // Wrapper sources live in Sources/LiteRTLM/ (vendored from
        // google-ai-edge/LiteRT-LM under Apache 2.0). The actual native
        // engine ships as a binary xcframework from the upstream's
        // GitHub release. Vendoring the wrapper means we don't pay the
        // multi-GB git clone tax SwiftPM imposes for full-repo deps.
        .binaryTarget(
            name: "CLiteRTLM",
            url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.12.0/CLiteRTLM.xcframework.zip",
            checksum: "3c2a11ecc8511d1e74efa7ca308dc7130c95223325c33212337ffb0563b79cde"
        ),
        .target(
            name: "LiteRTLM",
            dependencies: ["CLiteRTLM"],
            swiftSettings: [
                // Upstream was written against Swift 5.9; relax our 6.x
                // strict-concurrency checks just for this vendored target.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-all_load"]),
            ]
        ),
        .target(
            name: "SwooshLocalLLM",
            dependencies: [
                "SwooshClient",
                "SwooshModels",
                "LiteRTLM",
            ],
            swiftSettings: [
                // The upstream LiteRTLM API isn't Sendable-clean; relax
                // strict concurrency for this thin wrapper. Public types
                // we export are still Sendable-safe (SwooshExecutor is
                // an actor, FallbackExecutor is an actor).
                .swiftLanguageMode(.v5),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshSTT — speech-to-text providers
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshSTT",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshVoiceProviders — cloud TTS adapters
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshVoiceProviders",
            dependencies: ["SwooshSecrets", "SwooshMusic", "SwooshSTT"]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshLocalVoice — on-device TTS (Kokoro, OmniVoice)
        // ══════════════════════════════════════════════════════════════
        // Mirrors SwooshLocalLLM for voice. Today the engine falls back
        // to AVSpeechSynthesizer (so the audio loop works end-to-end);
        // the swap point is `LocalVoiceEngine.backend`. When an ONNX
        // Runtime / MLX-Audio / CoreML dep lands, add a Backend impl
        // and the rest of the stack (downloader, provider, picker,
        // Settings UI) keeps working.
        .target(
            name: "SwooshLocalVoice",
            dependencies: [
                "SwooshVoiceProviders",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),

        // ══════════════════════════════════════════════════════════════
        // MARK: - SwooshMusic — music generation providers
        // ══════════════════════════════════════════════════════════════
        .target(
            name: "SwooshMusic",
            dependencies: ["SwooshSecrets"]
        ),

        .target(
            name: "SwooshUI",
            dependencies: ["SwooshCore", "SwooshClient", "SwooshConfig", "SwooshTools", "SwooshVault", "SwooshFirewall", "SwooshFlow", "SwooshSecrets", "SwooshProviders", "SwooshGenerativeUI", "SwooshModels", "SwooshSkills"]
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
            name: "SwooshNetworkPolicyTests",
            dependencies: ["SwooshNetworkPolicy", "SwooshTools"]
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
            name: "SwooshPluginRuntimeTests",
            dependencies: ["SwooshPluginRuntime", "SwooshPlugins", "SwooshTools", "SwooshFirewall"]
        ),
        .testTarget(
            name: "SwooshDoctorTests",
            dependencies: ["SwooshDoctor", "SwooshTools"]
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
            name: "SwooshFilesTests",
            dependencies: ["SwooshFiles", "SwooshTools"]
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
            dependencies: ["SwooshProviders", "SwooshProviderBridge", "SwooshSecrets", "SwooshTools", "SwooshCore", "SwooshModels"]
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
                "SwooshToolsets",
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
            name: "SwooshConfigTests",
            dependencies: ["SwooshConfig"]
        ),
        .testTarget(
            name: "SwooshFirewallTests",
            dependencies: ["SwooshFirewall", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshVaultTests",
            dependencies: ["SwooshVault", "SwooshFirewall", "SwooshTools"]
        ),
        .testTarget(
            name: "SwooshModelsTests",
            dependencies: ["SwooshModels"]
        ),
        .testTarget(
            name: "SwooshLocalLLMTests",
            dependencies: ["SwooshLocalLLM"]
        ),
        .testTarget(
            name: "SwooshLocalVoiceTests",
            dependencies: ["SwooshLocalVoice"]
        ),
        .testTarget(
            name: "SwooshFoundationTests",
            dependencies: ["SwooshFoundation", "SwooshCore", "SwooshClient"]
        ),
        .testTarget(
            name: "SwooshEmbeddingsTests",
            dependencies: ["SwooshEmbeddings"]
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
        .testTarget(
            name: "SwooshCLITests",
            dependencies: [
                "SwooshCLI",
                "SwooshClient",
                "SwooshConfig",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
