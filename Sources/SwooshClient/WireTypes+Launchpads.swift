// SwooshClient/WireTypes+Launchpads.swift — 0.4A Launchpad catalog wire types
//
// Token-launchpad descriptors + the static `SwooshLaunchpadCatalog`
// bundled list. Wire format for `GET /api/launchpads` and
// `GET /api/launchpads/{id}`. Adding a launchpad means adding a new
// `LaunchpadPlatformDetail` to `details` here; the server reads from the
// same catalog so the wire and runtime stay aligned.

import Foundation

public struct LaunchpadPlatformSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let chain: String
    public let network: String
    public let execution: String
    public let skillID: String
    public let status: String
    public let risk: String
    public let docsURL: String
    public let capabilities: [String]

    public init(
        id: String,
        name: String,
        chain: String,
        network: String,
        execution: String,
        skillID: String,
        status: String,
        risk: String,
        docsURL: String,
        capabilities: [String]
    ) {
        self.id = id
        self.name = name
        self.chain = chain
        self.network = network
        self.execution = execution
        self.skillID = skillID
        self.status = status
        self.risk = risk
        self.docsURL = docsURL
        self.capabilities = capabilities
    }
}

public struct LaunchpadDocLink: Codable, Sendable, Equatable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public struct LaunchpadPlatformDetail: Codable, Sendable, Equatable {
    public let platform: LaunchpadPlatformSummary
    public let docs: [LaunchpadDocLink]
    public let requiredPermissions: [String]
    public let integrationNotes: [String]
    public let limitations: [String]

    public init(
        platform: LaunchpadPlatformSummary,
        docs: [LaunchpadDocLink],
        requiredPermissions: [String],
        integrationNotes: [String],
        limitations: [String]
    ) {
        self.platform = platform
        self.docs = docs
        self.requiredPermissions = requiredPermissions
        self.integrationNotes = integrationNotes
        self.limitations = limitations
    }
}

public struct LaunchpadsResponse: Codable, Sendable, Equatable {
    public let platforms: [LaunchpadPlatformSummary]
    public let generatedAt: Date

    public init(platforms: [LaunchpadPlatformSummary], generatedAt: Date = Date()) {
        self.platforms = platforms
        self.generatedAt = generatedAt
    }
}

public struct LaunchpadPlatformResponse: Codable, Sendable, Equatable {
    public let detail: LaunchpadPlatformDetail
    public let generatedAt: Date

    public init(detail: LaunchpadPlatformDetail, generatedAt: Date = Date()) {
        self.detail = detail
        self.generatedAt = generatedAt
    }
}

public enum SwooshLaunchpadCatalog {
    public static let details: [LaunchpadPlatformDetail] = [
        LaunchpadPlatformDetail(
            platform: LaunchpadPlatformSummary(
                id: "pumpportal",
                name: "PumpPortal",
                chain: "Solana",
                network: "mainnet",
                execution: "Lightning API or local unsigned transaction build",
                skillID: "bundled.launchpads.pumpportal.SKILL",
                status: "skill_docs_ready",
                risk: "high",
                docsURL: "https://pumpportal.fun/trading-api/",
                capabilities: [
                    "create-token",
                    "pumpfun-buy-sell",
                    "pumpswap-buy-sell",
                    "websocket-data",
                    "fees-rate-limits",
                ]
            ),
            docs: [
                LaunchpadDocLink(title: "Docs home", url: "https://pumpportal.fun/"),
                LaunchpadDocLink(title: "Trading API", url: "https://pumpportal.fun/trading-api/"),
                LaunchpadDocLink(title: "Setup", url: "https://pumpportal.fun/trading-api/setup"),
                LaunchpadDocLink(title: "Fees", url: "https://pumpportal.fun/fees/"),
                LaunchpadDocLink(title: "Wallets", url: "https://pumpportal.fun/create-wallet"),
            ],
            requiredPermissions: [
                "toolRead",
                "solanaRead",
                "solanaBuildTransaction",
                "solanaRequestSignature",
                "solanaSendTransaction",
            ],
            integrationNotes: [
                "Local API fits the Swoosh wallet model because it can return transactions for external signing.",
                "Lightning API is faster but requires a PumpPortal API key and explicit user approval.",
                "Data and WebSocket surfaces are read-only discovery inputs for the agent.",
            ],
            limitations: [
                "No native PumpPortal HTTP executor is registered yet.",
                "Lightning API execution remains docs-and-skill surfaced until credential storage is wired.",
            ]
        ),
        LaunchpadPlatformDetail(
            platform: LaunchpadPlatformSummary(
                id: "bags",
                name: "Bags",
                chain: "Solana",
                network: "mainnet",
                execution: "launch intent and launch transaction through Bags API",
                skillID: "bundled.launchpads.bags.SKILL",
                status: "skill_docs_ready",
                risk: "high",
                docsURL: "https://docs.bags.fm/how-to-guides/launch-token",
                capabilities: [
                    "agent-authentication",
                    "launch-intent",
                    "create-launch-transaction",
                    "draft-review",
                ]
            ),
            docs: [
                LaunchpadDocLink(title: "Docs index", url: "https://docs.bags.fm/llms.txt"),
                LaunchpadDocLink(title: "Launch token", url: "https://docs.bags.fm/how-to-guides/launch-token"),
                LaunchpadDocLink(title: "Agent authentication", url: "https://docs.bags.fm/how-to-guides/agent-authentication"),
                LaunchpadDocLink(title: "Create launch intent", url: "https://docs.bags.fm/how-to-guides/create-launch-intent"),
                LaunchpadDocLink(title: "Create launch transaction", url: "https://docs.bags.fm/api-reference/create-token-launch-transaction"),
            ],
            requiredPermissions: [
                "toolRead",
                "solanaRead",
                "solanaBuildTransaction",
                "solanaRequestSignature",
                "solanaSendTransaction",
            ],
            integrationNotes: [
                "Use Bags authentication as the readiness probe before claiming launch capability.",
                "Use launch intents for resumable user-facing drafts.",
                "Use the official launch transaction endpoint for execution planning.",
            ],
            limitations: [
                "No native Bags API client is registered yet.",
                "Swoosh should not substitute a custom launch builder when Bags provides the transaction flow.",
            ]
        ),
        LaunchpadPlatformDetail(
            platform: LaunchpadPlatformSummary(
                id: "flap",
                name: "Flap",
                chain: "BNB Chain",
                network: "mainnet",
                execution: "wallet, bot, token-launcher, and VaultPortal flows",
                skillID: "bundled.launchpads.flap.SKILL",
                status: "skill_docs_ready",
                risk: "high",
                docsURL: "https://docs.flap.sh/flap",
                capabilities: [
                    "trade-tokens",
                    "launcher-quickstart",
                    "vaultportal-launch",
                    "deployed-contracts",
                    "blink-surface",
                ]
            ),
            docs: [
                LaunchpadDocLink(title: "Docs home", url: "https://docs.flap.sh/flap"),
                LaunchpadDocLink(title: "Deployed contracts", url: "https://docs.flap.sh/flap/developers/deployed-contract-addresses"),
                LaunchpadDocLink(title: "Wallet terminal bot quickstart", url: "https://docs.flap.sh/flap/developers/wallet-and-terminal-and-bot-developers/a-quick-start-for-wallet-terminal-bot-developers"),
                LaunchpadDocLink(title: "Trade tokens", url: "https://docs.flap.sh/flap/developers/wallet-and-terminal-and-bot-developers/trade-tokens"),
                LaunchpadDocLink(title: "Token launcher quickstart", url: "https://docs.flap.sh/flap/developers/token-launcher-developers/quick-start-token-launcher-developers"),
                LaunchpadDocLink(title: "VaultPortal launch", url: "https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-vaultportal"),
            ],
            requiredPermissions: [
                "toolRead",
                "evmRead",
                "evmBuildTransaction",
                "evmRequestSignature",
                "evmBroadcast",
            ],
            integrationNotes: [
                "Resolve contract addresses from Flap docs before transaction planning.",
                "Treat Blink surfaces as UI wrappers over backend quote/build endpoints.",
                "Use EVM wallet approval for any transaction path.",
            ],
            limitations: [
                "No native Flap API or contract client is registered yet.",
                "Blink launch distribution depends on the host app backend.",
            ]
        ),
        LaunchpadPlatformDetail(
            platform: LaunchpadPlatformSummary(
                id: "four-meme",
                name: "Four.meme",
                chain: "BNB Chain",
                network: "mainnet",
                execution: "TokenManager helper contract and protocol integration flow",
                skillID: "bundled.launchpads.four-meme.SKILL",
                status: "skill_docs_ready",
                risk: "high",
                docsURL: "https://four-meme.gitbook.io/four.meme/brand/protocol-integration",
                capabilities: [
                    "create-token",
                    "creator-prebuy",
                    "tax-token-planning",
                    "bonding-curve-graduation",
                    "pancakeswap-liquidity",
                ]
            ),
            docs: [
                LaunchpadDocLink(title: "How it works", url: "https://four-meme.gitbook.io/four.meme/guide/how-it-works"),
                LaunchpadDocLink(title: "Tax tokens", url: "https://four-meme.gitbook.io/four.meme/guide/introducing-tax-tokens-on-four.meme"),
                LaunchpadDocLink(title: "Protocol integration", url: "https://four-meme.gitbook.io/four.meme/brand/protocol-integration"),
            ],
            requiredPermissions: [
                "toolRead",
                "evmRead",
                "evmBuildTransaction",
                "evmRequestSignature",
                "evmBroadcast",
            ],
            integrationNotes: [
                "Use TokenManagerHelper3 for cross-generation token support.",
                "Surface tax-token settings before transaction planning.",
                "Graduation context belongs with PancakeSwap liquidity UX.",
            ],
            limitations: [
                "No native Four.meme contract writer is registered yet.",
                "Tax-token and anti-sniping parameters require explicit user review before wallet approval.",
            ]
        ),
    ]

    public static func platformsResponse(generatedAt: Date = Date()) -> LaunchpadsResponse {
        LaunchpadsResponse(platforms: details.map(\.platform), generatedAt: generatedAt)
    }

    public static func detail(id: String, generatedAt: Date = Date()) -> LaunchpadPlatformResponse? {
        details.first(where: { $0.platform.id == id }).map {
            LaunchpadPlatformResponse(detail: $0, generatedAt: generatedAt)
        }
    }
}
