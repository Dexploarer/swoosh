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

    public init(sessionID: String = "default", input: String) {
        self.sessionID = sessionID
        self.input = input
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

public struct SkillSummary: Codable, Sendable, Identifiable {
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

public struct MemorySummary: Codable, Sendable, Identifiable {
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

public struct GoalRecordSummary: Codable, Sendable, Identifiable {
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

public struct ManifestationRecordSummary: Codable, Sendable, Identifiable {
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

public struct CronJobRecordSummary: Codable, Sendable, Identifiable {
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

public struct ChatAdapterToggleRequest: Codable, Sendable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}
