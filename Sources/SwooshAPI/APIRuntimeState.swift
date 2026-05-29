// SwooshAPI/APIRuntimeState.swift — 0.9S Stateful route adapter actor
//
// One per server boot. Wraps the boot-time `SwooshAPISnapshot` (start
// time, baseline provider/skill data) and the `SwooshAPIRuntimeSources`
// closures, and tracks the small amount of mutable state the read-side
// of the HTTP API needs (chat turn counter, last chat timestamp,
// approved-memory references). Every method maps to one route handler.

import Foundation
import SwooshClient
import SwooshConfig
import SwooshCore

actor APIRuntimeState {
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

    func startCodexAuth() async throws -> CodexAuthStatus {
        try await sources.startCodexAuth()
    }

    func codexAuthStatus() async -> CodexAuthStatus {
        await sources.codexAuthStatus()
    }

    func cancelCodexAuth() async -> CodexAuthStatus {
        await sources.cancelCodexAuth()
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
        let toolCount = await tools().tools.count
        return MetricsResponse(counters: [
            MetricCounter(id: "chat_turns", value: chatTurns),
            MetricCounter(id: "approved_memory_references", value: approvedMemoryReferences),
            MetricCounter(id: "providers", value: providerCount),
            MetricCounter(id: "skills", value: skillCount),
            MetricCounter(id: "tools", value: toolCount),
        ])
    }

    func tools() async -> ToolCatalogResponse {
        await sources.tools()
    }

    func mcpServers() async -> MCPServersResponse {
        await sources.mcpServers()
    }

    func audit() async -> AuditEventsResponse {
        await sources.audit()
    }

    func approvals() async -> ApprovalsResponse {
        await sources.approvals()
    }

    func resolveApproval(_ id: String, request: ApprovalResolveRequest) async throws -> ApprovalResolveResponse {
        try await sources.resolveApproval(id, request)
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

    func plugins() async -> PluginsResponse {
        await sources.plugins()
    }
    func pluginDetail(_ id: String) async throws -> PluginDetailResponse {
        try await sources.pluginDetail(id)
    }
    func enablePlugin(_ id: String) async throws -> PluginMutationResponse {
        try await sources.enablePlugin(id)
    }
    func disablePlugin(_ id: String) async throws -> PluginMutationResponse {
        try await sources.disablePlugin(id)
    }
    func installPlugin(_ request: PluginInstallRequest) async throws -> PluginMutationResponse {
        try await sources.installPlugin(request)
    }
    func uninstallPlugin(_ id: String) async throws -> PluginsResponse {
        try await sources.uninstallPlugin(id)
    }

    // ── Tier 1: Goals ──────────────────────────────────────────────
    func goals() async -> GoalsResponse {
        await sources.goals()
    }
    func goalDetail(_ id: String) async throws -> GoalDetailResponse {
        try await sources.goalDetail(id)
    }
    func setGoal(_ request: GoalSetRequest) async throws -> GoalMutationResponse {
        try await sources.setGoal(request)
    }
    func abandonGoal(_ id: String) async throws -> GoalMutationResponse {
        try await sources.abandonGoal(id)
    }
    func updateGoal(_ id: String, request: GoalUpdateRequest) async throws -> GoalMutationResponse {
        try await sources.updateGoal(id, request)
    }

    // ── Tier 1: Manifestations ─────────────────────────────────────
    func manifestations() async -> ManifestationsResponse {
        await sources.manifestations()
    }
    func manifestationDetail(_ id: String) async throws -> ManifestationDetailResponse {
        try await sources.manifestationDetail(id)
    }
    func runManifestation(_ request: ManifestationRunRequest) async throws -> ManifestationDetailResponse {
        try await sources.runManifestation(request)
    }
    func deleteManifestation(_ id: String) async throws -> ManifestationsResponse {
        try await sources.deleteManifestation(id)
    }

    // ── Tier 1: Skills CRUD ────────────────────────────────────────
    func skillDetail(_ id: String) async throws -> SkillDetailResponse {
        try await sources.skillDetail(id)
    }
    func searchSkills(_ request: SkillSearchRequest) async throws -> SkillsResponse {
        try await sources.searchSkills(request)
    }
    func proposeSkill(_ request: SkillProposeRequest) async throws -> SkillMutationResponse {
        try await sources.proposeSkill(request)
    }
    func approveSkill(_ id: String) async throws -> SkillMutationResponse {
        try await sources.approveSkill(id)
    }
    func rejectSkill(_ id: String) async throws -> SkillMutationResponse {
        try await sources.rejectSkill(id)
    }
    func deleteSkill(_ id: String) async throws -> SkillsResponse {
        try await sources.deleteSkill(id)
    }

    // ── Tier 1: Memories CRUD ──────────────────────────────────────
    func memoryDetail(_ id: String) async throws -> MemoryDetailResponse {
        try await sources.memoryDetail(id)
    }
    func proposeMemory(_ request: MemoryProposeRequest) async throws -> MemoryMutationResponse {
        try await sources.proposeMemory(request)
    }
    func approveMemory(_ id: String) async throws -> MemoryMutationResponse {
        try await sources.approveMemory(id)
    }
    func rejectMemory(_ id: String, request: MemoryReviewRequest) async throws -> MemoryMutationResponse {
        try await sources.rejectMemory(id, request)
    }

    // ── Tier 1: Tool execution ─────────────────────────────────────
    func executeTool(_ name: String, request: ToolExecuteRequest) async throws -> ToolExecuteResponse {
        try await sources.executeTool(name, request)
    }

    // ── Tier 1: MCP CRUD ───────────────────────────────────────────
    func addMCPServer(_ request: MCPServerCreateRequest) async throws -> MCPServerMutationResponse {
        try await sources.addMCPServer(request)
    }
    func removeMCPServer(_ id: String) async throws -> MCPServersResponse {
        try await sources.removeMCPServer(id)
    }
    func connectMCPServer(_ id: String) async throws -> MCPServerMutationResponse {
        try await sources.connectMCPServer(id)
    }
    func disconnectMCPServer(_ id: String) async throws -> MCPServerMutationResponse {
        try await sources.disconnectMCPServer(id)
    }
    func mcpServerTools(_ id: String) async throws -> MCPServerToolsResponse {
        try await sources.mcpServerTools(id)
    }

    // ── Tier 1: Firewall ───────────────────────────────────────────
    func firewallGrants() async -> FirewallResponse {
        await sources.firewallGrants()
    }
    func updateFirewall(_ request: FirewallGrantRequest) async throws -> FirewallMutationResponse {
        try await sources.updateFirewall(request)
    }
    func revokeFirewall(_ permission: String) async throws -> FirewallResponse {
        try await sources.revokeFirewall(permission)
    }
    func checkFirewall(_ request: FirewallCheckRequest) async throws -> FirewallCheckResponse {
        try await sources.checkFirewall(request)
    }

    // ── Tier 1: Cron CRUD ──────────────────────────────────────────
    func cronJobs() async -> CronJobsResponse {
        await sources.cronJobs()
    }
    func calendarEvents() async -> CalendarEventsResponse {
        await sources.calendarEvents()
    }
    func createCronJob(_ request: CronJobCreateRequest) async throws -> CronJobMutationResponse {
        try await sources.createCronJob(request)
    }
    func deleteCronJob(_ id: String) async throws -> CronJobsResponse {
        try await sources.deleteCronJob(id)
    }
    func runCronJob(_ id: String) async throws -> CronJobMutationResponse {
        try await sources.runCronJob(id)
    }

    // ── Tier 1: Doctor ─────────────────────────────────────────────
    func doctorReport() async -> DoctorReportResponse {
        await sources.doctorReport()
    }

    // ── Tier 1: Wallet ops ─────────────────────────────────────────
    func walletAccounts() async -> WalletAccountsResponse {
        await sources.walletAccounts()
    }
    func createWalletAccount(_ request: WalletCreateAccountRequest) async throws -> WalletAccountResponse {
        try await sources.createWalletAccount(request)
    }
    func deleteWalletAccount(_ id: String) async throws -> WalletAccountsResponse {
        try await sources.deleteWalletAccount(id)
    }
    func renameWalletAccount(_ id: String, request: WalletRenameRequest) async throws -> WalletAccountResponse {
        try await sources.renameWalletAccount(id, request)
    }
    func refreshWalletBalance(_ id: String) async throws -> WalletBalanceResponse {
        try await sources.refreshWalletBalance(id)
    }

    // ── Tier 1: Rebates & Anchoring ────────────────────────────────
    func rebateSummary(_ wallet: String, period: String) async throws -> RebateSummaryResponse {
        try await sources.rebateSummary(wallet, period)
    }
    func anchorBatches() async throws -> AnchorBatchesResponse {
        try await sources.anchorBatches()
    }

    private func activeProvider() async -> ProviderSummary? {
        let current = await providers()
        if let activeProviderID = current.activeProviderID {
            return current.providers.first { $0.id == activeProviderID }
        }
        return current.providers.first(where: \.active)
    }
}
