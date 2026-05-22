// SwooshClient/WireTypes.swift — Wire format shared by the iOS app and swooshd
//
// These Codable types are the contract between any Swoosh client and the
// SwooshAPI server. SwooshClient stays transport-agnostic (no Hummingbird
// dependency); SwooshAPI adds the ResponseEncodable conformance on the
// server side.

import Foundation

/// Request body for `POST /api/agent/chat`.
public struct ChatRequest: Codable, Sendable {
    public let sessionID: String
    public let input: String
    public let model: String?
    public let providerID: String?

    public init(
        sessionID: String = "default",
        input: String,
        model: String? = nil,
        providerID: String? = nil
    ) {
        self.sessionID = sessionID
        self.input = input
        self.model = model
        self.providerID = providerID
    }
}

/// Response body for `POST /api/agent/chat`. Mirrors `SwooshCore.AgentResponse`
/// without depending on it — the server translates between the two.
public struct ChatResponse: Codable, Sendable {
    public let message: String
    public let sessionID: String
    public let memoryIDsUsed: [String]
    public let modelUsed: String
    public let createdAt: Date

    public init(
        message: String,
        sessionID: String,
        memoryIDsUsed: [String] = [],
        modelUsed: String = "unknown",
        createdAt: Date = Date()
    ) {
        self.message = message
        self.sessionID = sessionID
        self.memoryIDsUsed = memoryIDsUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

public enum TranscriptRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct TranscriptMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let role: TranscriptRole
    public let content: String
    public let createdAt: Date

    public init(id: String, role: TranscriptRole, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct TranscriptResponse: Codable, Sendable, Equatable {
    public let sessionID: String
    public let messages: [TranscriptMessage]

    public init(sessionID: String, messages: [TranscriptMessage]) {
        self.sessionID = sessionID
        self.messages = messages
    }
}

public enum SwooshReadinessState: String, Codable, Sendable {
    case ready
    case degraded
    case blocked
}

public enum SwooshReadinessStatus: String, Codable, Sendable {
    case ready
    case warning
    case blocked
}

public struct SwooshReadinessComponent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let status: SwooshReadinessStatus
    public let detail: String
    public let fixCommand: String?

    public init(
        id: String,
        title: String,
        status: SwooshReadinessStatus,
        detail: String,
        fixCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fixCommand = fixCommand
    }
}

public struct SwooshReadinessReport: Codable, Sendable, Equatable {
    public let state: SwooshReadinessState
    public let summary: String
    public let components: [SwooshReadinessComponent]
    public let generatedAt: Date

    public init(
        state: SwooshReadinessState,
        summary: String,
        components: [SwooshReadinessComponent],
        generatedAt: Date = Date()
    ) {
        self.state = state
        self.summary = summary
        self.components = components
        self.generatedAt = generatedAt
    }

    public var isReady: Bool {
        state == .ready
    }

    public func component(id: String) -> SwooshReadinessComponent? {
        components.first { $0.id == id }
    }
}

/// Generic error envelope returned by the server for non-2xx responses.
public struct APIErrorBody: Codable, Sendable {
    public let error: String
    public let code: String?

    public init(error: String, code: String? = nil) {
        self.error = error
        self.code = code
    }
}

/// Version payload returned by `GET /api/version`.
public struct APIVersion: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct AgentStatusResponse: Codable, Sendable {
    public let status: String
    public let chat: Bool
    public let model: String?
    public let provider: String?
    public let startedAt: Date
    public let chatTurns: Int
    public let lastChatAt: Date?

    public init(
        status: String,
        chat: Bool,
        model: String?,
        provider: String?,
        startedAt: Date,
        chatTurns: Int,
        lastChatAt: Date?
    ) {
        self.status = status
        self.chat = chat
        self.model = model
        self.provider = provider
        self.startedAt = startedAt
        self.chatTurns = chatTurns
        self.lastChatAt = lastChatAt
    }
}

public struct ProviderSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let model: String?
    public let configured: Bool
    public let active: Bool
    public let status: String

    public init(
        id: String,
        name: String,
        model: String?,
        configured: Bool,
        active: Bool,
        status: String
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.configured = configured
        self.active = active
        self.status = status
    }
}

public struct ProviderAuthRequest: Codable, Sendable {
    public let providerID: String
    public let apiKey: String

    public init(providerID: String, apiKey: String) {
        self.providerID = providerID
        self.apiKey = apiKey
    }
}

public struct ProviderSelectionRequest: Codable, Sendable {
    public let providerID: String

    public init(providerID: String) {
        self.providerID = providerID
    }
}

public struct ProviderMutationResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let preferredProviderID: String?
    public let requiresRestart: Bool
    public let message: String

    public init(
        providers: [ProviderSummary],
        activeProviderID: String?,
        preferredProviderID: String?,
        requiresRestart: Bool,
        message: String
    ) {
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.preferredProviderID = preferredProviderID
        self.requiresRestart = requiresRestart
        self.message = message
    }
}

public struct ProvidersResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let preferredProviderID: String?

    public init(providers: [ProviderSummary], activeProviderID: String?, preferredProviderID: String? = nil) {
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.preferredProviderID = preferredProviderID
    }
}

public struct ProviderStatusResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let checkedAt: Date

    public init(providers: [ProviderSummary], checkedAt: Date = Date()) {
        self.providers = providers
        self.checkedAt = checkedAt
    }
}

public struct BoardLaneSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let cardCount: Int

    public init(id: String, title: String, cardCount: Int) {
        self.id = id
        self.title = title
        self.cardCount = cardCount
    }
}

public struct BoardCardSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let laneID: String
    public let title: String
    public let detail: String
    public let updatedAt: Date

    public init(id: String, laneID: String, title: String, detail: String, updatedAt: Date = Date()) {
        self.id = id
        self.laneID = laneID
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct BoardLanesResponse: Codable, Sendable {
    public let lanes: [BoardLaneSummary]

    public init(lanes: [BoardLaneSummary]) {
        self.lanes = lanes
    }
}

public struct BoardCardsResponse: Codable, Sendable {
    public let cards: [BoardCardSummary]

    public init(cards: [BoardCardSummary]) {
        self.cards = cards
    }
}

public struct MetricCounter: Codable, Sendable, Identifiable {
    public let id: String
    public let value: Int

    public init(id: String, value: Int) {
        self.id = id
        self.value = value
    }
}

public struct MetricsResponse: Codable, Sendable {
    public let counters: [MetricCounter]
    public let generatedAt: Date

    public init(counters: [MetricCounter], generatedAt: Date = Date()) {
        self.counters = counters
        self.generatedAt = generatedAt
    }
}

public struct AuditEventSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let timestamp: Date
    public let kind: String
    public let toolName: String?
    public let sessionID: String?
    public let detail: String
    public let success: Bool

    public init(
        id: String,
        timestamp: Date,
        kind: String,
        toolName: String?,
        sessionID: String?,
        detail: String,
        success: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.toolName = toolName
        self.sessionID = sessionID
        self.detail = detail
        self.success = success
    }
}

public struct AuditEventsResponse: Codable, Sendable, Equatable {
    public let events: [AuditEventSummary]
    public let generatedAt: Date

    public init(events: [AuditEventSummary], generatedAt: Date = Date()) {
        self.events = events
        self.generatedAt = generatedAt
    }
}

public struct ApprovalSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    public let risk: String
    public let permission: String
    public let inputPreview: String
    public let status: String
    public let createdAt: Date

    public init(
        id: String,
        sessionID: String,
        toolName: String,
        risk: String,
        permission: String,
        inputPreview: String,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.risk = risk
        self.permission = permission
        self.inputPreview = inputPreview
        self.status = status
        self.createdAt = createdAt
    }
}

public struct ApprovalsResponse: Codable, Sendable, Equatable {
    public let pending: [ApprovalSummary]
    public let history: [ApprovalSummary]
    public let generatedAt: Date

    public init(pending: [ApprovalSummary], history: [ApprovalSummary] = [], generatedAt: Date = Date()) {
        self.pending = pending
        self.history = history
        self.generatedAt = generatedAt
    }
}

public struct ApprovalResolveRequest: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable {
        case approveOnce
        case approveForSession
        case deny
    }

    public let decision: Decision
    public let reason: String?

    public init(decision: Decision, reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }
}

public struct ApprovalResolveResponse: Codable, Sendable, Equatable {
    public let approval: ApprovalSummary
    public let message: String

    public init(approval: ApprovalSummary, message: String) {
        self.approval = approval
        self.message = message
    }
}

public struct RuntimeFlagSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let enabled: Bool

    public init(id: String, label: String, enabled: Bool) {
        self.id = id
        self.label = label
        self.enabled = enabled
    }
}

public struct ToolPolicySummary: Codable, Sendable, Equatable {
    public let maxToolCallsPerTurn: Int
    public let maxToolChainDepth: Int
    public let allowModelToolCalls: Bool
    public let allowHumanOnlyFromModel: Bool
    public let allowCriticalToolsFromModel: Bool
    public let requireApprovalForMediumRiskAndAbove: Bool

    public init(
        maxToolCallsPerTurn: Int,
        maxToolChainDepth: Int,
        allowModelToolCalls: Bool,
        allowHumanOnlyFromModel: Bool,
        allowCriticalToolsFromModel: Bool,
        requireApprovalForMediumRiskAndAbove: Bool
    ) {
        self.maxToolCallsPerTurn = maxToolCallsPerTurn
        self.maxToolChainDepth = maxToolChainDepth
        self.allowModelToolCalls = allowModelToolCalls
        self.allowHumanOnlyFromModel = allowHumanOnlyFromModel
        self.allowCriticalToolsFromModel = allowCriticalToolsFromModel
        self.requireApprovalForMediumRiskAndAbove = requireApprovalForMediumRiskAndAbove
    }
}

public struct RuntimeConfigResponse: Codable, Sendable, Equatable {
    public let configured: Bool
    public let setupMode: String?
    public let permissionProfile: String?
    public let modelPath: String?
    public let daemonHost: String?
    public let daemonPort: Int?
    public let preferredProviderID: String?
    public let localDiagnosticFallback: Bool
    public let toolPolicy: ToolPolicySummary?
    public let safetyFlags: [RuntimeFlagSummary]

    public init(
        configured: Bool,
        setupMode: String?,
        permissionProfile: String?,
        modelPath: String?,
        daemonHost: String?,
        daemonPort: Int?,
        preferredProviderID: String? = nil,
        localDiagnosticFallback: Bool,
        toolPolicy: ToolPolicySummary?,
        safetyFlags: [RuntimeFlagSummary]
    ) {
        self.configured = configured
        self.setupMode = setupMode
        self.permissionProfile = permissionProfile
        self.modelPath = modelPath
        self.daemonHost = daemonHost
        self.daemonPort = daemonPort
        self.preferredProviderID = preferredProviderID
        self.localDiagnosticFallback = localDiagnosticFallback
        self.toolPolicy = toolPolicy
        self.safetyFlags = safetyFlags
    }
}

public struct RuntimeFlagUpdate: Codable, Sendable, Equatable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

public struct RuntimeFlagUpdateRequest: Codable, Sendable, Equatable {
    public let flags: [RuntimeFlagUpdate]

    public init(flags: [RuntimeFlagUpdate]) {
        self.flags = flags
    }
}

public struct RuntimeProfileUpdateRequest: Codable, Sendable, Equatable {
    public let permissionProfile: String

    public init(permissionProfile: String) {
        self.permissionProfile = permissionProfile
    }
}

public struct RuntimeConfigMutationResponse: Codable, Sendable, Equatable {
    public let config: RuntimeConfigResponse
    public let requiresRestart: Bool
    public let message: String

    public init(config: RuntimeConfigResponse, requiresRestart: Bool, message: String) {
        self.config = config
        self.requiresRestart = requiresRestart
        self.message = message
    }
}

public struct UsageResponse: Codable, Sendable {
    public let chatTurns: Int
    public let approvedMemoryReferences: Int
    public let lastChatAt: Date?
    public let generatedAt: Date

    public init(
        chatTurns: Int,
        approvedMemoryReferences: Int,
        lastChatAt: Date?,
        generatedAt: Date = Date()
    ) {
        self.chatTurns = chatTurns
        self.approvedMemoryReferences = approvedMemoryReferences
        self.lastChatAt = lastChatAt
        self.generatedAt = generatedAt
    }
}

public struct SkillSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let trust: String

    public init(id: String, title: String, description: String, category: String, trust: String) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.trust = trust
    }
}

public struct SkillsResponse: Codable, Sendable {
    public let skills: [SkillSummary]

    public init(skills: [SkillSummary]) {
        self.skills = skills
    }
}

public struct ToolCatalogToolSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let permission: String
    public let risk: String
    public let approval: String
    public let toolset: String
    public let platforms: [String]

    public init(
        id: String,
        name: String,
        displayName: String,
        description: String,
        permission: String,
        risk: String,
        approval: String,
        toolset: String,
        platforms: [String]
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.permission = permission
        self.risk = risk
        self.approval = approval
        self.toolset = toolset
        self.platforms = platforms
    }
}

public struct ToolsetSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let toolCount: Int
    public let readOnlyCount: Int
    public let writeCount: Int
    public let humanOnlyCount: Int

    public init(id: String, toolCount: Int, readOnlyCount: Int, writeCount: Int, humanOnlyCount: Int) {
        self.id = id
        self.toolCount = toolCount
        self.readOnlyCount = readOnlyCount
        self.writeCount = writeCount
        self.humanOnlyCount = humanOnlyCount
    }
}

public struct ToolCatalogResponse: Codable, Sendable, Equatable {
    public let tools: [ToolCatalogToolSummary]
    public let toolsets: [ToolsetSummary]
    public let generatedAt: Date

    public init(tools: [ToolCatalogToolSummary], toolsets: [ToolsetSummary], generatedAt: Date = Date()) {
        self.tools = tools
        self.toolsets = toolsets
        self.generatedAt = generatedAt
    }
}

public struct MCPDiscoveredToolSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let title: String?
    public let description: String?
    public let estimatedRisk: String

    public init(id: String, name: String, title: String?, description: String?, estimatedRisk: String) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.estimatedRisk = estimatedRisk
    }
}

public struct MCPServerRuntimeSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let enabled: Bool
    public let trustLevel: String
    public let state: String
    public let transport: String
    public let toolCount: Int
    public let importedToolCount: Int
    public let tools: [MCPDiscoveredToolSummary]

    public init(
        id: String,
        name: String,
        description: String?,
        enabled: Bool,
        trustLevel: String,
        state: String,
        transport: String,
        toolCount: Int,
        importedToolCount: Int,
        tools: [MCPDiscoveredToolSummary]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.trustLevel = trustLevel
        self.state = state
        self.transport = transport
        self.toolCount = toolCount
        self.importedToolCount = importedToolCount
        self.tools = tools
    }
}

public struct MCPServersResponse: Codable, Sendable, Equatable {
    public let servers: [MCPServerRuntimeSummary]
    public let generatedAt: Date

    public init(servers: [MCPServerRuntimeSummary], generatedAt: Date = Date()) {
        self.servers = servers
        self.generatedAt = generatedAt
    }
}

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

public struct MemorySummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let text: String
    public let category: String
    public let status: String
    public let sensitivity: String
    public let confidence: Double?
    public let createdAt: String

    public init(
        id: String,
        text: String,
        category: String,
        status: String,
        sensitivity: String,
        confidence: Double?,
        createdAt: String
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.status = status
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

public struct MemoriesResponse: Codable, Sendable {
    public let approved: [MemorySummary]
    public let pending: [MemorySummary]
    public let rejected: [MemorySummary]

    public init(approved: [MemorySummary], pending: [MemorySummary], rejected: [MemorySummary] = []) {
        self.approved = approved
        self.pending = pending
        self.rejected = rejected
    }
}

public struct GoalRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let statement: String
    public let state: String
    public let progress: String
    public let updatedAt: Date

    public init(id: String, statement: String, state: String, progress: String, updatedAt: Date) {
        self.id = id
        self.statement = statement
        self.state = state
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

public struct ManifestationRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let status: String
    public let triggerReason: String
    public let proposalCount: Int
    public let summary: String?
    public let startedAt: Date

    public init(
        id: String,
        status: String,
        triggerReason: String,
        proposalCount: Int,
        summary: String?,
        startedAt: Date
    ) {
        self.id = id
        self.status = status
        self.triggerReason = triggerReason
        self.proposalCount = proposalCount
        self.summary = summary
        self.startedAt = startedAt
    }
}

public struct CronJobRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let state: String
    public let enabled: Bool
    public let nextRunAt: Date?
    public let lastRunAt: Date?

    public init(id: String, name: String, state: String, enabled: Bool, nextRunAt: Date?, lastRunAt: Date?) {
        self.id = id
        self.name = name
        self.state = state
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
    }
}

public struct RecordsResponse: Codable, Sendable {
    public let readiness: SwooshReadinessReport
    public let metrics: MetricsResponse
    public let usage: UsageResponse
    public let boardCards: [BoardCardSummary]
    public let goals: [GoalRecordSummary]
    public let manifestations: [ManifestationRecordSummary]
    public let cronJobs: [CronJobRecordSummary]
    public let generatedAt: Date

    public init(
        readiness: SwooshReadinessReport,
        metrics: MetricsResponse,
        usage: UsageResponse,
        boardCards: [BoardCardSummary],
        goals: [GoalRecordSummary],
        manifestations: [ManifestationRecordSummary],
        cronJobs: [CronJobRecordSummary],
        generatedAt: Date = Date()
    ) {
        self.readiness = readiness
        self.metrics = metrics
        self.usage = usage
        self.boardCards = boardCards
        self.goals = goals
        self.manifestations = manifestations
        self.cronJobs = cronJobs
        self.generatedAt = generatedAt
    }
}

public enum MediaGalleryKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case other
}

public struct MediaGalleryItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kind: MediaGalleryKind
    public let relativePath: String
    public let byteSize: Int64
    public let createdAt: Date?

    public init(
        id: String,
        title: String,
        kind: MediaGalleryKind,
        relativePath: String,
        byteSize: Int64,
        createdAt: Date?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.createdAt = createdAt
    }
}

public struct MediaGalleryResponse: Codable, Sendable {
    public let items: [MediaGalleryItem]
    public let root: String
    public let generatedAt: Date

    public init(items: [MediaGalleryItem], root: String, generatedAt: Date = Date()) {
        self.items = items
        self.root = root
        self.generatedAt = generatedAt
    }
}

public struct WalletAnalyticsSummary: Codable, Sendable, Equatable {
    public let totalValueUSD: String?
    public let realizedPnLUSD: String?
    public let unrealizedPnLUSD: String?
    public let totalPnLPercent: String?
    public let dailyChangePercent: String?
    public let openPositions: Int

    public init(
        totalValueUSD: String?,
        realizedPnLUSD: String?,
        unrealizedPnLUSD: String?,
        totalPnLPercent: String?,
        dailyChangePercent: String?,
        openPositions: Int
    ) {
        self.totalValueUSD = totalValueUSD
        self.realizedPnLUSD = realizedPnLUSD
        self.unrealizedPnLUSD = unrealizedPnLUSD
        self.totalPnLPercent = totalPnLPercent
        self.dailyChangePercent = dailyChangePercent
        self.openPositions = openPositions
    }
}

public struct WalletAssetSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let chain: String
    public let symbol: String
    public let name: String?
    public let quantity: String
    public let valueUSD: String?
    public let costBasisUSD: String?
    public let pnlUSD: String?
    public let pnlPercent: String?

    public init(
        id: String,
        chain: String,
        symbol: String,
        name: String?,
        quantity: String,
        valueUSD: String?,
        costBasisUSD: String?,
        pnlUSD: String?,
        pnlPercent: String?
    ) {
        self.id = id
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.valueUSD = valueUSD
        self.costBasisUSD = costBasisUSD
        self.pnlUSD = pnlUSD
        self.pnlPercent = pnlPercent
    }
}

public enum WalletInsightSeverity: String, Codable, Sendable {
    case info
    case warning
    case critical
}

public struct WalletInsightSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let severity: WalletInsightSeverity
    public let title: String
    public let detail: String
    public let source: String

    public init(id: String, severity: WalletInsightSeverity, title: String, detail: String, source: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.source = source
    }
}

public struct WalletTradingCapabilitySummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let enabled: Bool
    public let configured: Bool
    public let status: String
    public let risk: String

    public init(id: String, name: String, enabled: Bool, configured: Bool, status: String, risk: String) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.configured = configured
        self.status = status
        self.risk = risk
    }
}

public struct WalletDashboardResponse: Codable, Sendable, Equatable {
    public let connected: Bool
    public let walletLabel: String?
    public let analytics: WalletAnalyticsSummary
    public let assets: [WalletAssetSummary]
    public let insights: [WalletInsightSummary]
    public let capabilities: [WalletTradingCapabilitySummary]
    public let generatedAt: Date

    public init(
        connected: Bool,
        walletLabel: String?,
        analytics: WalletAnalyticsSummary,
        assets: [WalletAssetSummary],
        insights: [WalletInsightSummary],
        capabilities: [WalletTradingCapabilitySummary],
        generatedAt: Date = Date()
    ) {
        self.connected = connected
        self.walletLabel = walletLabel
        self.analytics = analytics
        self.assets = assets
        self.insights = insights
        self.capabilities = capabilities
        self.generatedAt = generatedAt
    }
}

public struct ChatAdapterSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let distribution: String
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]
    public let supportsStreaming: Bool
    public let supportsDMs: Bool
    public let supportsCards: Bool
    public let supportsModals: Bool

    public init(
        id: String,
        displayName: String,
        packageName: String?,
        distribution: String = "official",
        enabled: Bool,
        configured: Bool,
        missingCredentials: [String],
        configurationNotes: [String] = [],
        supportsStreaming: Bool,
        supportsDMs: Bool,
        supportsCards: Bool,
        supportsModals: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
        self.supportsStreaming = supportsStreaming
        self.supportsDMs = supportsDMs
        self.supportsCards = supportsCards
        self.supportsModals = supportsModals
    }
}

public struct ChatStateAdapterSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let distribution: String
    public let productionReady: Bool
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]

    public init(
        id: String,
        displayName: String,
        packageName: String?,
        distribution: String,
        productionReady: Bool,
        enabled: Bool,
        configured: Bool,
        missingCredentials: [String],
        configurationNotes: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.productionReady = productionReady
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
    }
}

public struct ChatAdaptersResponse: Codable, Sendable {
    public let adapters: [ChatAdapterSummary]
    public let stateAdapters: [ChatStateAdapterSummary]

    public init(adapters: [ChatAdapterSummary], stateAdapters: [ChatStateAdapterSummary] = []) {
        self.adapters = adapters
        self.stateAdapters = stateAdapters
    }
}

/// Status of an in-flight `codex login` attempt. Returned by
/// `POST /api/codex/auth/start` and `GET /api/codex/auth/status`.
public struct CodexAuthStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case idle
        case pending
        case signedIn = "signed_in"
        case failed
        case cancelled
    }
    public let state: State
    public let message: String?
    public let startedAt: Date?
    /// OAuth URL codex printed when the login process started. Useful
    /// when the daemon and browser live on different machines.
    public let url: String?

    public init(state: State, message: String? = nil,
                startedAt: Date? = nil, url: String? = nil) {
        self.state = state
        self.message = message
        self.startedAt = startedAt
        self.url = url
    }
}

public struct ChatAdapterToggleRequest: Codable, Sendable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Plugins
// ════════════════════════════════════════════════════════════════════

/// One plugin tool entry, in wire form. Lossless re-encoding of
/// `PluginToolManifest` so the iOS app can render the agent's installed
/// plugin catalog without depending on `SwooshPlugins`.
public struct PluginToolSummary: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let permission: String
    public let risk: String
    public let requiresApproval: Bool

    public init(name: String, description: String, permission: String, risk: String, requiresApproval: Bool) {
        self.name = name; self.description = description
        self.permission = permission; self.risk = risk
        self.requiresApproval = requiresApproval
    }
}

/// One installed plugin in wire form. `kind` is one of `"swift"`,
/// `"executable"`, `"wasm"`, `"mcpBridge"`.
public struct PluginSummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let author: String?
    public let kind: String
    public let enabled: Bool
    public let requestedPermissions: [String]
    public let tools: [PluginToolSummary]
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, version: String, description: String?,
                author: String?, kind: String, enabled: Bool,
                requestedPermissions: [String], tools: [PluginToolSummary],
                createdAt: Date, updatedAt: Date) {
        self.id = id; self.name = name; self.version = version
        self.description = description; self.author = author; self.kind = kind
        self.enabled = enabled
        self.requestedPermissions = requestedPermissions; self.tools = tools
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct PluginsResponse: Codable, Sendable, Equatable {
    public let plugins: [PluginSummary]

    public init(plugins: [PluginSummary]) { self.plugins = plugins }
}

public struct PluginEventSummary: Codable, Sendable, Equatable {
    public let kind: String
    public let message: String
    public let createdAt: Date

    public init(kind: String, message: String, createdAt: Date) {
        self.kind = kind; self.message = message; self.createdAt = createdAt
    }
}

public struct PluginDetailResponse: Codable, Sendable, Equatable {
    public let plugin: PluginSummary
    /// Permissions the firewall is currently granting on this plugin's
    /// behalf — i.e. the perms it added on top of the baseline.
    public let grantedPermissions: [String]
    /// Most-recent plugin events, newest last.
    public let auditTail: [PluginEventSummary]

    public init(plugin: PluginSummary, grantedPermissions: [String], auditTail: [PluginEventSummary]) {
        self.plugin = plugin
        self.grantedPermissions = grantedPermissions
        self.auditTail = auditTail
    }
}

/// Install request body. `sourcePath` is a directory on the daemon's
/// filesystem that contains a `manifest.json` (and any kind-specific
/// files — `main.sh`, `plugin.wasm`, etc.). The host copies the directory
/// into `~/.swoosh/plugins/<id>/`.
public struct PluginInstallRequest: Codable, Sendable, Equatable {
    public let sourcePath: String

    public init(sourcePath: String) { self.sourcePath = sourcePath }
}

public struct PluginMutationResponse: Codable, Sendable, Equatable {
    public let plugin: PluginSummary
    public let message: String

    public init(plugin: PluginSummary, message: String) {
        self.plugin = plugin
        self.message = message
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Goals API
// ────────────────────────────────────────────────────────────────────

public struct GoalIterationSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let iteration: Int
    public let sessionID: String?
    public let observation: String
    public let judgement: String
    public let judgeRationale: String?
    public let createdAt: Date

    public init(
        id: String,
        iteration: Int,
        sessionID: String?,
        observation: String,
        judgement: String,
        judgeRationale: String?,
        createdAt: Date
    ) {
        self.id = id
        self.iteration = iteration
        self.sessionID = sessionID
        self.observation = observation
        self.judgement = judgement
        self.judgeRationale = judgeRationale
        self.createdAt = createdAt
    }
}

public struct GoalDetailResponse: Codable, Sendable, Equatable {
    public let goal: GoalRecordSummary
    public let maxIterations: Int
    public let parentSessionID: String?
    public let createdAt: Date
    public let iterations: [GoalIterationSummary]

    public init(
        goal: GoalRecordSummary,
        maxIterations: Int,
        parentSessionID: String?,
        createdAt: Date,
        iterations: [GoalIterationSummary]
    ) {
        self.goal = goal
        self.maxIterations = maxIterations
        self.parentSessionID = parentSessionID
        self.createdAt = createdAt
        self.iterations = iterations
    }
}

public struct GoalsResponse: Codable, Sendable, Equatable {
    public let goals: [GoalRecordSummary]

    public init(goals: [GoalRecordSummary]) {
        self.goals = goals
    }
}

public struct GoalSetRequest: Codable, Sendable, Equatable {
    public let statement: String
    public let maxIterations: Int?
    public let parentSessionID: String?

    public init(statement: String, maxIterations: Int? = nil, parentSessionID: String? = nil) {
        self.statement = statement
        self.maxIterations = maxIterations
        self.parentSessionID = parentSessionID
    }
}

public struct GoalUpdateRequest: Codable, Sendable, Equatable {
    public let state: String

    public init(state: String) {
        self.state = state
    }
}

public struct GoalMutationResponse: Codable, Sendable, Equatable {
    public let goal: GoalRecordSummary
    public let message: String

    public init(goal: GoalRecordSummary, message: String) {
        self.goal = goal
        self.message = message
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Manifestations API
// ────────────────────────────────────────────────────────────────────

public struct ManifestationPhaseSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let observation: String?

    public init(
        id: String,
        name: String,
        startedAt: Date,
        finishedAt: Date?,
        observation: String?
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.observation = observation
    }
}

public struct ManifestationProposalSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let rationale: String
    public let confidence: Double
    public let payloadJSON: String
    public let createdAt: Date

    public init(
        id: String,
        kind: String,
        title: String,
        rationale: String,
        confidence: Double,
        payloadJSON: String,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.confidence = confidence
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public struct ManifestationDetailResponse: Codable, Sendable, Equatable {
    public let manifestation: ManifestationRecordSummary
    public let phases: [ManifestationPhaseSummary]
    public let proposals: [ManifestationProposalSummary]
    public let auditWindowStart: Date?
    public let auditWindowEnd: Date?
    public let finishedAt: Date?

    public init(
        manifestation: ManifestationRecordSummary,
        phases: [ManifestationPhaseSummary],
        proposals: [ManifestationProposalSummary],
        auditWindowStart: Date?,
        auditWindowEnd: Date?,
        finishedAt: Date?
    ) {
        self.manifestation = manifestation
        self.phases = phases
        self.proposals = proposals
        self.auditWindowStart = auditWindowStart
        self.auditWindowEnd = auditWindowEnd
        self.finishedAt = finishedAt
    }
}

public struct ManifestationsResponse: Codable, Sendable, Equatable {
    public let manifestations: [ManifestationRecordSummary]

    public init(manifestations: [ManifestationRecordSummary]) {
        self.manifestations = manifestations
    }
}

public struct ManifestationRunRequest: Codable, Sendable, Equatable {
    public let triggerReason: String?

    public init(triggerReason: String? = nil) {
        self.triggerReason = triggerReason
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Skills CRUD
// ────────────────────────────────────────────────────────────────────

public struct SkillDetailResponse: Codable, Sendable, Equatable {
    public let skill: SkillSummary
    public let body: String
    public let tags: [String]
    public let triggerPatterns: [String]
    public let toolsRequired: [String]
    public let platforms: [String]
    public let usageCount: Int
    public let successRate: Double
    public let updatedAt: Date

    public init(
        skill: SkillSummary,
        body: String,
        tags: [String],
        triggerPatterns: [String],
        toolsRequired: [String],
        platforms: [String],
        usageCount: Int,
        successRate: Double,
        updatedAt: Date
    ) {
        self.skill = skill
        self.body = body
        self.tags = tags
        self.triggerPatterns = triggerPatterns
        self.toolsRequired = toolsRequired
        self.platforms = platforms
        self.usageCount = usageCount
        self.successRate = successRate
        self.updatedAt = updatedAt
    }
}

public struct SkillSearchRequest: Codable, Sendable, Equatable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct SkillProposeRequest: Codable, Sendable, Equatable {
    public let title: String
    public let description: String
    public let body: String
    public let category: String?
    public let tags: [String]?
    public let triggerPatterns: [String]?

    public init(
        title: String,
        description: String,
        body: String,
        category: String? = nil,
        tags: [String]? = nil,
        triggerPatterns: [String]? = nil
    ) {
        self.title = title
        self.description = description
        self.body = body
        self.category = category
        self.tags = tags
        self.triggerPatterns = triggerPatterns
    }
}

public struct SkillMutationResponse: Codable, Sendable, Equatable {
    public let skill: SkillSummary
    public let message: String

    public init(skill: SkillSummary, message: String) {
        self.skill = skill
        self.message = message
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Memories CRUD
// ────────────────────────────────────────────────────────────────────

public struct MemoryDetailResponse: Codable, Sendable, Equatable {
    public let memory: MemorySummary
    public let evidenceJSON: String?

    public init(memory: MemorySummary, evidenceJSON: String? = nil) {
        self.memory = memory
        self.evidenceJSON = evidenceJSON
    }
}

public struct MemoryProposeRequest: Codable, Sendable, Equatable {
    public let text: String
    public let category: String
    public let sensitivity: String
    public let confidence: Double
    public let evidenceJSON: String?

    public init(
        text: String,
        category: String,
        sensitivity: String = "low",
        confidence: Double = 0.8,
        evidenceJSON: String? = nil
    ) {
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.evidenceJSON = evidenceJSON
    }
}

public struct MemoryReviewRequest: Codable, Sendable, Equatable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct MemoryMutationResponse: Codable, Sendable, Equatable {
    public let memory: MemorySummary
    public let message: String

    public init(memory: MemorySummary, message: String) {
        self.memory = memory
        self.message = message
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Tool execution
// ────────────────────────────────────────────────────────────────────

public struct ToolExecuteRequest: Codable, Sendable, Equatable {
    public let argsJSON: String
    public let sessionID: String?

    public init(argsJSON: String = "{}", sessionID: String? = nil) {
        self.argsJSON = argsJSON
        self.sessionID = sessionID
    }
}

public struct ToolExecuteResponse: Codable, Sendable, Equatable {
    public let toolName: String
    public let success: Bool
    public let outputJSON: String?
    public let error: String?
    public let durationMs: Int

    public init(
        toolName: String,
        success: Bool,
        outputJSON: String?,
        error: String?,
        durationMs: Int
    ) {
        self.toolName = toolName
        self.success = success
        self.outputJSON = outputJSON
        self.error = error
        self.durationMs = durationMs
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: MCP CRUD
// ────────────────────────────────────────────────────────────────────

public struct MCPServerCreateRequest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let transport: String          // "stdio" | "http"
    public let command: String?           // stdio
    public let arguments: [String]?
    public let workingDirectory: String?
    public let baseURL: String?           // http
    public let trustLevel: String?
    public let enabled: Bool?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        transport: String,
        command: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil,
        baseURL: String? = nil,
        trustLevel: String? = nil,
        enabled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.baseURL = baseURL
        self.trustLevel = trustLevel
        self.enabled = enabled
    }
}

public struct MCPServerMutationResponse: Codable, Sendable, Equatable {
    public let server: MCPServerRuntimeSummary
    public let message: String

    public init(server: MCPServerRuntimeSummary, message: String) {
        self.server = server
        self.message = message
    }
}

public struct MCPServerToolsResponse: Codable, Sendable, Equatable {
    public let serverID: String
    public let tools: [MCPDiscoveredToolSummary]

    public init(serverID: String, tools: [MCPDiscoveredToolSummary]) {
        self.serverID = serverID
        self.tools = tools
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Firewall
// ────────────────────────────────────────────────────────────────────

public struct FirewallResponse: Codable, Sendable, Equatable {
    public let granted: [String]
    public let denied: [String]

    public init(granted: [String], denied: [String]) {
        self.granted = granted
        self.denied = denied
    }
}

public struct FirewallGrantRequest: Codable, Sendable, Equatable {
    public let permission: String
    public let decision: String   // "grant" | "deny"

    public init(permission: String, decision: String = "grant") {
        self.permission = permission
        self.decision = decision
    }
}

public struct FirewallMutationResponse: Codable, Sendable, Equatable {
    public let firewall: FirewallResponse
    public let message: String

    public init(firewall: FirewallResponse, message: String) {
        self.firewall = firewall
        self.message = message
    }
}

public struct FirewallCheckRequest: Codable, Sendable, Equatable {
    public let permission: String

    public init(permission: String) {
        self.permission = permission
    }
}

public struct FirewallCheckResponse: Codable, Sendable, Equatable {
    public let permission: String
    public let granted: Bool
    public let denied: Bool

    public init(permission: String, granted: Bool, denied: Bool) {
        self.permission = permission
        self.granted = granted
        self.denied = denied
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Cron CRUD
// ────────────────────────────────────────────────────────────────────

public struct CronJobsResponse: Codable, Sendable, Equatable {
    public let jobs: [CronJobRecordSummary]

    public init(jobs: [CronJobRecordSummary]) {
        self.jobs = jobs
    }
}

public struct CronJobCreateRequest: Codable, Sendable, Equatable {
    public let name: String
    public let prompt: String
    public let schedule: String       // natural-language: "every 5 minutes", "daily at 9am"
    public let enabled: Bool?
    public let model: String?
    public let provider: String?
    public let skills: [String]?
    public let enabledToolsets: [String]?
    public let workdir: String?

    public init(
        name: String,
        prompt: String,
        schedule: String,
        enabled: Bool? = nil,
        model: String? = nil,
        provider: String? = nil,
        skills: [String]? = nil,
        enabledToolsets: [String]? = nil,
        workdir: String? = nil
    ) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.enabled = enabled
        self.model = model
        self.provider = provider
        self.skills = skills
        self.enabledToolsets = enabledToolsets
        self.workdir = workdir
    }
}

public struct CronJobMutationResponse: Codable, Sendable, Equatable {
    public let job: CronJobRecordSummary
    public let message: String

    public init(job: CronJobRecordSummary, message: String) {
        self.job = job
        self.message = message
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Tier 1: Wallet ops
// ────────────────────────────────────────────────────────────────────

public struct WalletAccountSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let chain: String
    public let address: String
    public let truncatedAddress: String
    public let label: String
    public let createdAt: Date

    public init(
        id: String,
        chain: String,
        address: String,
        truncatedAddress: String,
        label: String,
        createdAt: Date
    ) {
        self.id = id
        self.chain = chain
        self.address = address
        self.truncatedAddress = truncatedAddress
        self.label = label
        self.createdAt = createdAt
    }
}

public struct WalletAccountsResponse: Codable, Sendable, Equatable {
    public let accounts: [WalletAccountSummary]

    public init(accounts: [WalletAccountSummary]) {
        self.accounts = accounts
    }
}

public struct WalletCreateAccountRequest: Codable, Sendable, Equatable {
    public let chain: String
    public let label: String

    public init(chain: String, label: String) {
        self.chain = chain
        self.label = label
    }
}

public struct WalletRenameRequest: Codable, Sendable, Equatable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

public struct WalletAccountResponse: Codable, Sendable, Equatable {
    public let account: WalletAccountSummary
    public let message: String

    public init(account: WalletAccountSummary, message: String) {
        self.account = account
        self.message = message
    }
}

public struct WalletBalanceResponse: Codable, Sendable, Equatable {
    public let account: WalletAccountSummary
    public let rawAmount: String
    public let formatted: String
    public let fetchedAt: Date

    public init(
        account: WalletAccountSummary,
        rawAmount: String,
        formatted: String,
        fetchedAt: Date
    ) {
        self.account = account
        self.rawAmount = rawAmount
        self.formatted = formatted
        self.fetchedAt = fetchedAt
    }
}
