// SwooshAPI/SwooshServer.swift — HTTP API server
//
// Hummingbird router with three layers:
//
//   1. Public routes  — `/health`, `/api/version`. No auth, safe to expose.
//   2. Auth-gated     — every other `/api/*` route. Requires a bearer token.
//                       When the daemon was started without one, the entire
//                       `/api/*` tree is shadow-mounted under DenyAllMiddleware
//                       so binding to 0.0.0.0 still can't expose the agent.
//   3. Agent          — `POST /api/agent/chat` calls the tool loop when it is
//                       configured, otherwise the plain kernel.
//
// Streaming / WebSocket and the audit/approvals endpoints will land on top of
// this once the iOS slice is proven; this file is intentionally the smallest
// thing that gives the phone a real conversation.

import Foundation
import Hummingbird
import SwooshCore
import SwooshClient
import SwooshChatSDK
import SwooshConfig
import SwooshTools

// Server-side conformance so `ChatResponse` can be returned from a Hummingbird
// route directly. `SwooshClient` itself doesn't import Hummingbird.
extension ChatResponse: ResponseEncodable {}
extension TranscriptResponse: ResponseEncodable {}
extension APIErrorBody: ResponseEncodable {}
extension APIVersion: ResponseEncodable {}
extension AgentStatusResponse: ResponseEncodable {}
extension SwooshReadinessReport: ResponseEncodable {}
extension ProvidersResponse: ResponseEncodable {}
extension ProviderStatusResponse: ResponseEncodable {}
extension ProviderMutationResponse: ResponseEncodable {}
extension BoardCardsResponse: ResponseEncodable {}
extension BoardLanesResponse: ResponseEncodable {}
extension MetricsResponse: ResponseEncodable {}
extension UsageResponse: ResponseEncodable {}
extension SkillsResponse: ResponseEncodable {}
extension MemoriesResponse: ResponseEncodable {}
extension RecordsResponse: ResponseEncodable {}
extension MediaGalleryResponse: ResponseEncodable {}
extension ChatAdaptersResponse: ResponseEncodable {}
extension RuntimeConfigResponse: ResponseEncodable {}
extension RuntimeConfigMutationResponse: ResponseEncodable {}
extension WalletDashboardResponse: ResponseEncodable {}

public struct SwooshAPISnapshot: Sendable {
    public let startedAt: Date
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let skills: [SkillSummary]

    public init(
        startedAt: Date = Date(),
        providers: [ProviderSummary] = [],
        activeProviderID: String? = nil,
        skills: [SkillSummary] = []
    ) {
        self.startedAt = startedAt
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.skills = skills
    }
}

public struct SwooshAPIRuntimeSources: Sendable {
    public let providers: @Sendable () async -> ProvidersResponse?
    public let saveProviderKey: @Sendable (ProviderAuthRequest) async throws -> ProviderMutationResponse
    public let selectProvider: @Sendable (ProviderSelectionRequest) async throws -> ProviderMutationResponse
    public let skills: @Sendable () async -> SkillsResponse?
    public let memories: @Sendable () async -> MemoriesResponse?
    public let records: @Sendable () async -> RecordsResponse?
    public let media: @Sendable () async -> MediaGalleryResponse?
    public let readiness: @Sendable () async -> SwooshReadinessReport?
    public let updateRuntimeFlags: @Sendable (RuntimeFlagUpdateRequest) async throws -> RuntimeConfigMutationResponse
    public let updateRuntimeProfile: @Sendable (RuntimeProfileUpdateRequest) async throws -> RuntimeConfigMutationResponse
    public let wallet: @Sendable () async -> WalletDashboardResponse?

    public init(
        providers: @escaping @Sendable () async -> ProvidersResponse? = { nil },
        saveProviderKey: @escaping @Sendable (ProviderAuthRequest) async throws -> ProviderMutationResponse = { _ in
            throw APIError.badRequest("provider auth is not configured")
        },
        selectProvider: @escaping @Sendable (ProviderSelectionRequest) async throws -> ProviderMutationResponse = { _ in
            throw APIError.badRequest("provider selection is not configured")
        },
        skills: @escaping @Sendable () async -> SkillsResponse? = { nil },
        memories: @escaping @Sendable () async -> MemoriesResponse? = { nil },
        records: @escaping @Sendable () async -> RecordsResponse? = { nil },
        media: @escaping @Sendable () async -> MediaGalleryResponse? = { nil },
        readiness: @escaping @Sendable () async -> SwooshReadinessReport? = { nil },
        updateRuntimeFlags: @escaping @Sendable (RuntimeFlagUpdateRequest) async throws -> RuntimeConfigMutationResponse = { _ in
            throw APIError.badRequest("runtime flag updates are not configured")
        },
        updateRuntimeProfile: @escaping @Sendable (RuntimeProfileUpdateRequest) async throws -> RuntimeConfigMutationResponse = { _ in
            throw APIError.badRequest("runtime profile updates are not configured")
        },
        wallet: @escaping @Sendable () async -> WalletDashboardResponse? = { nil }
    ) {
        self.providers = providers
        self.saveProviderKey = saveProviderKey
        self.selectProvider = selectProvider
        self.skills = skills
        self.memories = memories
        self.records = records
        self.media = media
        self.readiness = readiness
        self.updateRuntimeFlags = updateRuntimeFlags
        self.updateRuntimeProfile = updateRuntimeProfile
        self.wallet = wallet
    }
}

/// Swoosh HTTP API server. Wraps a Hummingbird application that calls
/// the supplied `AgentKernel` for chat requests.
public struct SwooshAPIServer: Sendable {
    public static let buildVersion: String = "0.9P"

    private let port: Int
    private let hostname: String
    private let token: String?
    private let agent: AgentHandle?
    private let snapshot: SwooshAPISnapshot
    private let runtimeSources: SwooshAPIRuntimeSources

    /// - Parameters:
    ///   - port: TCP port to listen on.
    ///   - hostname: Bind address. `127.0.0.1` keeps the daemon loopback-only;
    ///     `0.0.0.0` exposes it on every interface and should only be used
    ///     when a bearer token is also supplied.
    ///   - token: Bearer token required on every `/api/*` request (except
    ///     `/api/version`). `nil` mounts `DenyAllMiddleware` on the entire
    ///     `/api/*` tree so an accidentally-public daemon is still inert.
    ///   - kernel: Agent kernel that handles chat requests. `nil` makes
    ///     `/api/agent/chat` return 503 — useful in tests that only want to
    ///     exercise routing and auth.
    public init(
        port: Int = 8787,
        hostname: String = "127.0.0.1",
        token: String? = nil,
        kernel: AgentKernel? = nil,
        toolLoop: AgentToolLoop? = nil,
        snapshot: SwooshAPISnapshot = SwooshAPISnapshot(),
        runtimeSources: SwooshAPIRuntimeSources = SwooshAPIRuntimeSources()
    ) {
        self.port = port
        self.hostname = hostname
        self.token = token
        if let toolLoop {
            self.agent = .toolLoop(ToolLoopHandle(toolLoop))
        } else if let kernel {
            self.agent = .kernel(KernelHandle(kernel))
        } else {
            self.agent = nil
        }
        self.snapshot = snapshot
        self.runtimeSources = runtimeSources
    }

    /// Build the Hummingbird application with all routes wired in.
    public func build() -> some ApplicationProtocol {
        let router = Router()
        let agent = self.agent
        let buildVersion = SwooshAPIServer.buildVersion
        let runtime = APIRuntimeState(snapshot: snapshot, sources: runtimeSources)
        let adapterCatalog = ChatAdapterCatalog()
        let adapterToggles = ChatAdapterToggleStore()
        let stateAdapterCatalog = ChatStateAdapterCatalog()
        let stateAdapterToggles = ChatStateAdapterToggleStore()

        // ── Public routes ────────────────────────────────────────────────
        router.get("/health") { _, _ in "ok" }
        router.get("/api/version") { _, _ -> APIVersion in
            APIVersion(name: "Swoosh", version: buildVersion)
        }

        // ── Auth-gated routes ───────────────────────────────────────────
        let apiGroup = router.group("/api")
        if let token {
            apiGroup.add(middleware: BearerAuthMiddleware(token: token))
        } else {
            apiGroup.add(middleware: DenyAllMiddleware())
        }

        apiGroup.post("/agent/chat") { request, context -> ChatResponse in
            guard let agent else {
                throw HTTPError(.serviceUnavailable, message: "kernel not configured")
            }
            let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
            let agentRequest = AgentRequest(
                sessionID: chatRequest.sessionID,
                input: chatRequest.input
            )
            let agentResponse: AgentResponse
            do {
                agentResponse = try await agent.run(agentRequest)
            } catch {
                throw HTTPError(.internalServerError, message: error.localizedDescription)
            }
            await runtime.recordChat(agentResponse)
            return ChatResponse(
                message: agentResponse.message,
                sessionID: agentResponse.sessionID,
                memoryIDsUsed: agentResponse.memoryIDsUsed,
                modelUsed: agentResponse.modelUsed,
                createdAt: agentResponse.createdAt
            )
        }

        apiGroup.get("/agent/transcript/:sessionID") { _, context -> TranscriptResponse in
            guard let agent else {
                throw HTTPError(.serviceUnavailable, message: "kernel not configured")
            }
            let sessionID = try context.parameters.require("sessionID", as: String.self)
            do {
                let transcript = try await agent.loadTranscript(sessionID: sessionID)
                return TranscriptResponse(
                    sessionID: sessionID,
                    messages: transcript.compactMap(transcriptMessage)
                )
            } catch {
                throw HTTPError(.internalServerError, message: error.localizedDescription)
            }
        }

        apiGroup.get("/agent/status") { _, _ -> AgentStatusResponse in
            await runtime.agentStatus(chatEnabled: agent != nil)
        }

        apiGroup.get("/runtime/readiness") { _, _ -> SwooshReadinessReport in
            await runtime.readiness(chatEnabled: agent != nil)
        }
        apiGroup.get("/runtime/config") { _, _ -> RuntimeConfigResponse in
            runtimeConfigResponse(SwooshReadinessDetector().loadRuntimeConfig())
        }
        apiGroup.post("/runtime/flags") { request, context -> RuntimeConfigMutationResponse in
            let body = try await request.decode(as: RuntimeFlagUpdateRequest.self, context: context)
            do {
                return try await runtime.updateRuntimeFlags(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/runtime/profile") { request, context -> RuntimeConfigMutationResponse in
            let body = try await request.decode(as: RuntimeProfileUpdateRequest.self, context: context)
            do {
                return try await runtime.updateRuntimeProfile(body)
            } catch {
                throw apiHTTPError(error)
            }
        }

        apiGroup.get("/providers") { _, _ -> ProvidersResponse in
            await runtime.providers()
        }
        apiGroup.get("/providers/status") { _, _ -> ProviderStatusResponse in
            await runtime.providerStatus()
        }
        apiGroup.post("/providers/auth") { request, context -> ProviderMutationResponse in
            let body = try await request.decode(as: ProviderAuthRequest.self, context: context)
            do {
                return try await runtime.saveProviderKey(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/providers/select") { request, context -> ProviderMutationResponse in
            let body = try await request.decode(as: ProviderSelectionRequest.self, context: context)
            do {
                return try await runtime.selectProvider(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.get("/board/cards") { _, _ -> BoardCardsResponse in
            await runtime.boardCards(chatEnabled: agent != nil)
        }
        apiGroup.get("/board/lanes") { _, _ -> BoardLanesResponse in
            await runtime.boardLanes(chatEnabled: agent != nil)
        }
        apiGroup.get("/metrics") { _, _ -> MetricsResponse in
            await runtime.metrics()
        }
        apiGroup.get("/usage") { _, _ -> UsageResponse in
            await runtime.usage()
        }
        apiGroup.get("/skills") { _, _ -> SkillsResponse in
            await runtime.skills()
        }
        apiGroup.get("/memories") { _, _ -> MemoriesResponse in
            await runtime.memories()
        }
        apiGroup.get("/records") { _, _ -> RecordsResponse in
            await runtime.records(chatEnabled: agent != nil)
        }
        apiGroup.get("/media") { _, _ -> MediaGalleryResponse in
            await runtime.media()
        }
        apiGroup.get("/wallet") { _, _ -> WalletDashboardResponse in
            await runtime.wallet()
        }
        apiGroup.get("/chat-adapters") { _, _ -> ChatAdaptersResponse in
            try await makeChatAdaptersResponse(
                catalog: adapterCatalog,
                store: adapterToggles,
                stateCatalog: stateAdapterCatalog,
                stateStore: stateAdapterToggles
            )
        }
        apiGroup.post("/chat-adapters/toggle") { request, context -> ChatAdaptersResponse in
            let toggle = try await request.decode(as: ChatAdapterToggleRequest.self, context: context)
            if let kind = ChatAdapterKind(rawValue: toggle.id) {
                try await adapterToggles.set(kind, enabled: toggle.enabled)
            } else if let kind = ChatStateAdapterKind(rawValue: toggle.id) {
                try await stateAdapterToggles.set(kind, enabled: toggle.enabled)
            } else {
                throw HTTPError(.badRequest, message: "unknown chat adapter: \(toggle.id)")
            }
            return try await makeChatAdaptersResponse(
                catalog: adapterCatalog,
                store: adapterToggles,
                stateCatalog: stateAdapterCatalog,
                stateStore: stateAdapterToggles
            )
        }

        return Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
    }
}

private func makeChatAdaptersResponse(
    catalog: ChatAdapterCatalog,
    store: ChatAdapterToggleStore,
    stateCatalog: ChatStateAdapterCatalog,
    stateStore: ChatStateAdapterToggleStore
) async throws -> ChatAdaptersResponse {
    let statuses = try await catalog.statuses(store: store)
    let stateStatuses = try await stateCatalog.statuses(store: stateStore)
    return ChatAdapterProjection.response(platformStatuses: statuses, stateStatuses: stateStatuses)
}

private func apiHTTPError(_ error: Error) -> HTTPError {
    if let apiError = error as? APIError {
        switch apiError {
        case .notFound(let message):
            return HTTPError(.notFound, message: message)
        case .unauthorized:
            return HTTPError(.unauthorized, message: "unauthorized")
        case .badRequest(let message):
            return HTTPError(.badRequest, message: message)
        case .internalError(let message):
            return HTTPError(.internalServerError, message: message)
        }
    }
    return HTTPError(.internalServerError, message: error.localizedDescription)
}

private func runtimeConfigResponse(_ config: SwooshRuntimeConfig?) -> RuntimeConfigResponse {
    guard let config else {
        return RuntimeConfigResponse(
            configured: false,
            setupMode: nil,
            permissionProfile: nil,
            modelPath: nil,
            daemonHost: nil,
            daemonPort: nil,
            preferredProviderID: nil,
            localDiagnosticFallback: false,
            toolPolicy: nil,
            safetyFlags: []
        )
    }
    let policy = config.toolPolicy
    return RuntimeConfigResponse(
        configured: true,
        setupMode: config.setupMode,
        permissionProfile: config.permissionProfile,
        modelPath: config.modelPath,
        daemonHost: config.daemonHost,
        daemonPort: config.daemonPort,
        preferredProviderID: config.preferredProviderID,
        localDiagnosticFallback: config.localDiagnosticFallback,
        toolPolicy: ToolPolicySummary(
            maxToolCallsPerTurn: policy.maxToolCallsPerTurn,
            maxToolChainDepth: policy.maxToolChainDepth,
            allowModelToolCalls: policy.allowModelToolCalls,
            allowHumanOnlyFromModel: policy.allowHumanOnlyFromModel,
            allowCriticalToolsFromModel: policy.allowCriticalToolsFromModel,
            requireApprovalForMediumRiskAndAbove: policy.requireApprovalForMediumRiskAndAbove
        ),
        safetyFlags: safetyFlagSummaries(config.safetyConfig)
    )
}

private func safetyFlagSummaries(_ config: SwooshSafetyConfig) -> [RuntimeFlagSummary] {
    [
        RuntimeFlagSummary(id: "autonomousTradingEnabled", label: "Autonomous trading", enabled: config.autonomousTradingEnabled),
        RuntimeFlagSummary(id: "humanPromptedTradingEnabled", label: "Human-prompted trading", enabled: config.humanPromptedTradingEnabled),
        RuntimeFlagSummary(id: "swapExecutionEnabled", label: "Swap execution", enabled: config.swapExecutionEnabled),
        RuntimeFlagSummary(id: "portfolioRecommendationsEnabled", label: "Portfolio recommendations", enabled: config.portfolioRecommendationsEnabled),
        RuntimeFlagSummary(id: "privateKeyCustodyEnabled", label: "Private-key custody", enabled: config.privateKeyCustodyEnabled),
        RuntimeFlagSummary(id: "seedPhraseIngestionEnabled", label: "Seed phrase ingestion", enabled: config.seedPhraseIngestionEnabled),
        RuntimeFlagSummary(id: "cookieIngestionEnabled", label: "Cookie ingestion", enabled: config.cookieIngestionEnabled),
        RuntimeFlagSummary(id: "shellToBlockchainBridgeEnabled", label: "Shell to blockchain bridge", enabled: config.shellToBlockchainBridgeEnabled),
        RuntimeFlagSummary(id: "modelSelfApprovalEnabled", label: "Model self-approval", enabled: config.modelSelfApprovalEnabled),
        RuntimeFlagSummary(id: "mainnetWritesByDefault", label: "Mainnet writes by default", enabled: config.mainnetWritesByDefault),
    ]
}

private func defaultWalletDashboard(config: SwooshRuntimeConfig?) -> WalletDashboardResponse {
    let safety = config?.safetyConfig ?? .defaultAgent
    let permissions = PermissionProfilePreset(rawValue: config?.permissionProfile ?? "")?.grantedSwooshPermissions ?? []
    let promptedTradingEnabled = safety.humanPromptedTradingEnabled || safety.autonomousTradingEnabled
    let tradingEnabled = promptedTradingEnabled && permissions.contains(.hyperliquidTrade)
    let swapsEnabled = promptedTradingEnabled && safety.swapExecutionEnabled
        && (permissions.contains(.evmBuildTransaction) || permissions.contains(.solanaBuildTransaction))
    let portfolioEnabled = safety.portfolioRecommendationsEnabled
    let mainnetEnabled = safety.mainnetWritesByDefault
        && permissions.contains(.evmMainnetWrite)
        && permissions.contains(.solanaMainnetWrite)
    return WalletDashboardResponse(
        connected: false,
        walletLabel: nil,
        analytics: WalletAnalyticsSummary(
            totalValueUSD: nil,
            realizedPnLUSD: nil,
            unrealizedPnLUSD: nil,
            totalPnLPercent: nil,
            dailyChangePercent: nil,
            openPositions: 0
        ),
        assets: [],
        insights: [
            WalletInsightSummary(
                id: "wallet.not_connected",
                severity: .warning,
                title: "No wallet connected",
                detail: "Wallet analytics and PnL stay empty until a wallet bridge or account source is connected.",
                source: "runtime"
            ),
        ],
        capabilities: [
            WalletTradingCapabilitySummary(
                id: "trading.human_prompted",
                name: "Human-prompted trading",
                enabled: safety.humanPromptedTradingEnabled,
                configured: true,
                status: safety.humanPromptedTradingEnabled ? "approval_required" : "disabled_by_safety_flag",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "mainnet.write",
                name: "Mainnet writes",
                enabled: mainnetEnabled,
                configured: permissions.contains(.evmMainnetWrite) || permissions.contains(.solanaMainnetWrite),
                status: mainnetEnabled ? "mainnet_enabled" : "requires_trader_or_autonomous_profile",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "portfolio",
                name: "Portfolio insights",
                enabled: portfolioEnabled,
                configured: portfolioEnabled,
                status: portfolioEnabled ? "enabled" : "disabled_by_safety_flag",
                risk: "medium"
            ),
            WalletTradingCapabilitySummary(
                id: "swaps",
                name: "DEX swaps",
                enabled: swapsEnabled,
                configured: false,
                status: swapsEnabled ? "waiting_for_wallet" : "disabled_by_config",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "hyperliquid",
                name: "Hyperliquid trading",
                enabled: tradingEnabled,
                configured: false,
                status: tradingEnabled ? "waiting_for_secret_ref" : "disabled_by_config",
                risk: "critical"
            ),
        ]
    )
}

/// Sendable handle around `AgentKernel`. The kernel is already an actor, but
/// boxing it in a struct keeps the public `SwooshAPIServer` initializer
/// auto-Sendable.
private struct KernelHandle: Sendable {
    let kernel: AgentKernel
    init(_ kernel: AgentKernel) { self.kernel = kernel }
}

private struct ToolLoopHandle: Sendable {
    let loop: AgentToolLoop
    init(_ loop: AgentToolLoop) { self.loop = loop }
}

private enum AgentHandle: Sendable {
    case kernel(KernelHandle)
    case toolLoop(ToolLoopHandle)

    func run(_ request: AgentRequest) async throws -> AgentResponse {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.run(request)
        case .toolLoop(let handle):
            return try await handle.loop.run(request).agentResponse
        }
    }

    func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.loadTranscript(sessionID: sessionID)
        case .toolLoop(let handle):
            return try await handle.loop.loadTranscript(sessionID: sessionID)
        }
    }
}

private func transcriptMessage(_ message: SwooshCore.ChatMessage) -> TranscriptMessage? {
    guard !isInternalAuditMessage(message.content) else { return nil }
    return TranscriptMessage(
        id: message.id,
        role: transcriptRole(message.role),
        content: message.content,
        createdAt: message.createdAt
    )
}

private func isInternalAuditMessage(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("{") && trimmed.contains("\"_swoosh_audit\"")
}

private func transcriptRole(_ role: SwooshCore.ChatRole) -> TranscriptRole {
    switch role {
    case .system:
        return .system
    case .user:
        return .user
    case .assistant:
        return .assistant
    case .tool:
        return .tool
    }
}

private actor APIRuntimeState {
    private let snapshot: SwooshAPISnapshot
    private let sources: SwooshAPIRuntimeSources
    private var chatTurns = 0
    private var approvedMemoryReferences = 0
    private var lastChatAt: Date?

    init(snapshot: SwooshAPISnapshot, sources: SwooshAPIRuntimeSources) {
        self.snapshot = snapshot
        self.sources = sources
    }

    func recordChat(_ response: AgentResponse) {
        chatTurns += 1
        approvedMemoryReferences += response.memoryIDsUsed.count
        lastChatAt = response.createdAt
    }

    func agentStatus(chatEnabled: Bool) async -> AgentStatusResponse {
        let active = await activeProvider()
        return AgentStatusResponse(
            status: chatEnabled ? "ready" : "degraded",
            chat: chatEnabled,
            model: active?.model,
            provider: active?.name,
            startedAt: snapshot.startedAt,
            chatTurns: chatTurns,
            lastChatAt: lastChatAt
        )
    }

    func providers() async -> ProvidersResponse {
        await sources.providers() ?? ProvidersResponse(
            providers: snapshot.providers,
            activeProviderID: snapshot.activeProviderID
        )
    }

    func saveProviderKey(_ request: ProviderAuthRequest) async throws -> ProviderMutationResponse {
        try await sources.saveProviderKey(request)
    }

    func selectProvider(_ request: ProviderSelectionRequest) async throws -> ProviderMutationResponse {
        try await sources.selectProvider(request)
    }

    func updateRuntimeFlags(_ request: RuntimeFlagUpdateRequest) async throws -> RuntimeConfigMutationResponse {
        try await sources.updateRuntimeFlags(request)
    }

    func updateRuntimeProfile(_ request: RuntimeProfileUpdateRequest) async throws -> RuntimeConfigMutationResponse {
        try await sources.updateRuntimeProfile(request)
    }

    func readiness(chatEnabled: Bool) async -> SwooshReadinessReport {
        if let readiness = await sources.readiness() {
            return readiness
        }
        let active = await activeProvider()
        let skills = await skills()
        return SwooshReadinessDetector().report(inputs: SwooshReadinessInputs(
            daemonReachable: true,
            chatEnabled: chatEnabled,
            activeProviderName: active?.name,
            activeModel: active?.model,
            promptableSkillCount: skills.skills.count
        ))
    }

    func providerStatus() async -> ProviderStatusResponse {
        ProviderStatusResponse(providers: await providers().providers)
    }

    func boardLanes(chatEnabled: Bool) async -> BoardLanesResponse {
        let cards = await boardCards(chatEnabled: chatEnabled).cards
        let lanes = [
            BoardLaneSummary(
                id: "runtime",
                title: "Runtime",
                cardCount: cards.filter { $0.laneID == "runtime" }.count
            ),
            BoardLaneSummary(
                id: "configuration",
                title: "Configuration",
                cardCount: cards.filter { $0.laneID == "configuration" }.count
            ),
        ]
        return BoardLanesResponse(lanes: lanes)
    }

    func boardCards(chatEnabled: Bool) async -> BoardCardsResponse {
        let now = Date()
        let active = await activeProvider()
        let skills = await skills()
        var cards = [
            BoardCardSummary(
                id: "daemon",
                laneID: "runtime",
                title: "Daemon",
                detail: chatEnabled ? "HTTP API is accepting chat turns." : "HTTP API is running without an agent kernel.",
                updatedAt: now
            ),
            BoardCardSummary(
                id: "provider",
                laneID: "configuration",
                title: "Model Provider",
                detail: active.map { "\($0.name) \($0.model ?? "")".trimmingCharacters(in: .whitespaces) }
                    ?? "No model provider configured.",
                updatedAt: now
            ),
            BoardCardSummary(
                id: "skills",
                laneID: "configuration",
                title: "Skills",
                detail: "\(skills.skills.count) reviewed or promoted skills loaded.",
                updatedAt: now
            ),
        ]
        if let lastChatAt {
            cards.append(BoardCardSummary(
                id: "last-chat",
                laneID: "runtime",
                title: "Last Chat",
                detail: "Last completed chat at \(ISO8601DateFormatter().string(from: lastChatAt)).",
                updatedAt: lastChatAt
            ))
        }
        return BoardCardsResponse(cards: cards)
    }

    func metrics() async -> MetricsResponse {
        let providerCount = await providers().providers.count
        let skillCount = await skills().skills.count
        return MetricsResponse(counters: [
            MetricCounter(id: "chat_turns", value: chatTurns),
            MetricCounter(id: "approved_memory_references", value: approvedMemoryReferences),
            MetricCounter(id: "providers", value: providerCount),
            MetricCounter(id: "skills", value: skillCount),
        ])
    }

    func usage() -> UsageResponse {
        UsageResponse(
            chatTurns: chatTurns,
            approvedMemoryReferences: approvedMemoryReferences,
            lastChatAt: lastChatAt
        )
    }

    func skills() async -> SkillsResponse {
        await sources.skills() ?? SkillsResponse(skills: snapshot.skills)
    }

    func memories() async -> MemoriesResponse {
        await sources.memories() ?? MemoriesResponse(approved: [], pending: [])
    }

    func records(chatEnabled: Bool) async -> RecordsResponse {
        let base = RecordsResponse(
            readiness: await readiness(chatEnabled: chatEnabled),
            metrics: await metrics(),
            usage: usage(),
            boardCards: await boardCards(chatEnabled: chatEnabled).cards,
            goals: [],
            manifestations: [],
            cronJobs: []
        )
        guard let durable = await sources.records() else {
            return base
        }
        return RecordsResponse(
            readiness: base.readiness,
            metrics: base.metrics,
            usage: base.usage,
            boardCards: base.boardCards + durable.boardCards,
            goals: durable.goals,
            manifestations: durable.manifestations,
            cronJobs: durable.cronJobs
        )
    }

    func media() async -> MediaGalleryResponse {
        await sources.media() ?? MediaGalleryResponse(items: [], root: "")
    }

    func wallet() async -> WalletDashboardResponse {
        await sources.wallet() ?? defaultWalletDashboard(config: SwooshReadinessDetector().loadRuntimeConfig())
    }

    private func activeProvider() async -> ProviderSummary? {
        let current = await providers()
        if let activeProviderID = current.activeProviderID {
            return current.providers.first { $0.id == activeProviderID }
        }
        return current.providers.first(where: \.active)
    }
}

public enum APIError: Error, Sendable {
    case notFound(String)
    case unauthorized
    case badRequest(String)
    case internalError(String)
}
