// SwooshAPI/SwooshAPIRuntimeSources.swift — 0.9S Adapter closures for the API server
//
// `SwooshAPIServer` is a thin Hummingbird wrapper — every route delegates
// to one of these `@Sendable` closures. The daemon constructs the value
// with concrete implementations; tests build it with stubs. Defaults
// throw `APIError.badRequest` or return an empty payload, so an
// unconfigured server still answers without crashing.

import Foundation
import SwooshClient

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
    public let tools: @Sendable () async -> ToolCatalogResponse
    public let mcpServers: @Sendable () async -> MCPServersResponse
    public let audit: @Sendable () async -> AuditEventsResponse
    public let approvals: @Sendable () async -> ApprovalsResponse
    public let resolveApproval: @Sendable (String, ApprovalResolveRequest) async throws -> ApprovalResolveResponse
    /// `POST /api/codex/auth/start` — spawn `codex login` if no live
    /// attempt exists, otherwise return the current status.
    public let startCodexAuth: @Sendable () async throws -> CodexAuthStatus
    /// `GET /api/codex/auth/status` — read-only poll.
    public let codexAuthStatus: @Sendable () async -> CodexAuthStatus
    /// `POST /api/codex/auth/cancel` — terminate the in-flight attempt.
    public let cancelCodexAuth: @Sendable () async -> CodexAuthStatus
    /// `GET /api/plugins` — list installed plugins.
    public let plugins: @Sendable () async -> PluginsResponse
    /// `GET /api/plugins/:id` — single plugin + audit tail.
    public let pluginDetail: @Sendable (String) async throws -> PluginDetailResponse
    /// `POST /api/plugins/:id/enable` — humanOnly admin gate is the API itself.
    public let enablePlugin: @Sendable (String) async throws -> PluginMutationResponse
    /// `POST /api/plugins/:id/disable`.
    public let disablePlugin: @Sendable (String) async throws -> PluginMutationResponse
    /// `POST /api/plugins/install` — copy a plugin dir into ~/.swoosh/plugins.
    public let installPlugin: @Sendable (PluginInstallRequest) async throws -> PluginMutationResponse
    /// `DELETE /api/plugins/:id` — disable (if enabled) and remove the manifest.
    public let uninstallPlugin: @Sendable (String) async throws -> PluginsResponse

    // ── Tier 1: Goals ──────────────────────────────────────────────
    public let goals: @Sendable () async -> GoalsResponse
    public let goalDetail: @Sendable (String) async throws -> GoalDetailResponse
    public let setGoal: @Sendable (GoalSetRequest) async throws -> GoalMutationResponse
    public let abandonGoal: @Sendable (String) async throws -> GoalMutationResponse
    public let updateGoal: @Sendable (String, GoalUpdateRequest) async throws -> GoalMutationResponse

    // ── Tier 1: Manifestations ─────────────────────────────────────
    public let manifestations: @Sendable () async -> ManifestationsResponse
    public let manifestationDetail: @Sendable (String) async throws -> ManifestationDetailResponse
    public let runManifestation: @Sendable (ManifestationRunRequest) async throws -> ManifestationDetailResponse
    public let deleteManifestation: @Sendable (String) async throws -> ManifestationsResponse

    // ── Tier 1: Skills CRUD ────────────────────────────────────────
    public let skillDetail: @Sendable (String) async throws -> SkillDetailResponse
    public let searchSkills: @Sendable (SkillSearchRequest) async throws -> SkillsResponse
    public let proposeSkill: @Sendable (SkillProposeRequest) async throws -> SkillMutationResponse
    public let approveSkill: @Sendable (String) async throws -> SkillMutationResponse
    public let rejectSkill: @Sendable (String) async throws -> SkillMutationResponse
    public let deleteSkill: @Sendable (String) async throws -> SkillsResponse

    // ── Tier 1: Memories CRUD ──────────────────────────────────────
    public let memoryDetail: @Sendable (String) async throws -> MemoryDetailResponse
    public let proposeMemory: @Sendable (MemoryProposeRequest) async throws -> MemoryMutationResponse
    public let approveMemory: @Sendable (String) async throws -> MemoryMutationResponse
    public let rejectMemory: @Sendable (String, MemoryReviewRequest) async throws -> MemoryMutationResponse

    // ── Tier 1: Tool execution ─────────────────────────────────────
    public let executeTool: @Sendable (String, ToolExecuteRequest) async throws -> ToolExecuteResponse

    // ── Tier 1: MCP CRUD ───────────────────────────────────────────
    public let addMCPServer: @Sendable (MCPServerCreateRequest) async throws -> MCPServerMutationResponse
    public let removeMCPServer: @Sendable (String) async throws -> MCPServersResponse
    public let connectMCPServer: @Sendable (String) async throws -> MCPServerMutationResponse
    public let disconnectMCPServer: @Sendable (String) async throws -> MCPServerMutationResponse
    public let mcpServerTools: @Sendable (String) async throws -> MCPServerToolsResponse

    // ── Tier 1: Firewall ───────────────────────────────────────────
    public let firewallGrants: @Sendable () async -> FirewallResponse
    public let updateFirewall: @Sendable (FirewallGrantRequest) async throws -> FirewallMutationResponse
    public let revokeFirewall: @Sendable (String) async throws -> FirewallResponse
    public let checkFirewall: @Sendable (FirewallCheckRequest) async throws -> FirewallCheckResponse

    // ── Tier 1: Cron CRUD ──────────────────────────────────────────
    public let cronJobs: @Sendable () async -> CronJobsResponse
    public let createCronJob: @Sendable (CronJobCreateRequest) async throws -> CronJobMutationResponse
    public let deleteCronJob: @Sendable (String) async throws -> CronJobsResponse
    public let runCronJob: @Sendable (String) async throws -> CronJobMutationResponse

    // ── Calendar (Detour agent-managed) ────────────────────────────
    public let calendarEvents: @Sendable () async -> CalendarEventsResponse

    // ── Tier 1: Doctor ─────────────────────────────────────────────
    public let doctorReport: @Sendable () async -> DoctorReportResponse

    // ── Tier 1: Wallet ops ─────────────────────────────────────────
    public let walletAccounts: @Sendable () async -> WalletAccountsResponse
    public let createWalletAccount: @Sendable (WalletCreateAccountRequest) async throws -> WalletAccountResponse
    public let deleteWalletAccount: @Sendable (String) async throws -> WalletAccountsResponse
    public let renameWalletAccount: @Sendable (String, WalletRenameRequest) async throws -> WalletAccountResponse
    public let refreshWalletBalance: @Sendable (String) async throws -> WalletBalanceResponse

    // ── Tier 1: Rebates & Anchoring ────────────────────────────────
    public let rebateSummary: @Sendable (String, String) async throws -> RebateSummaryResponse
    public let anchorBatches: @Sendable () async throws -> AnchorBatchesResponse

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
        wallet: @escaping @Sendable () async -> WalletDashboardResponse? = { nil },
        tools: @escaping @Sendable () async -> ToolCatalogResponse = {
            ToolCatalogResponse(tools: [], toolsets: [])
        },
        mcpServers: @escaping @Sendable () async -> MCPServersResponse = {
            MCPServersResponse(servers: [])
        },
        audit: @escaping @Sendable () async -> AuditEventsResponse = {
            AuditEventsResponse(events: [])
        },
        approvals: @escaping @Sendable () async -> ApprovalsResponse = {
            ApprovalsResponse(pending: [])
        },
        resolveApproval: @escaping @Sendable (String, ApprovalResolveRequest) async throws -> ApprovalResolveResponse = { id, _ in
            throw APIError.notFound(id)
        },
        startCodexAuth: @escaping @Sendable () async throws -> CodexAuthStatus = {
            throw APIError.badRequest("codex auth is not configured")
        },
        codexAuthStatus: @escaping @Sendable () async -> CodexAuthStatus = {
            CodexAuthStatus(state: .idle, message: "codex auth not configured")
        },
        cancelCodexAuth: @escaping @Sendable () async -> CodexAuthStatus = {
            CodexAuthStatus(state: .idle)
        },
        plugins: @escaping @Sendable () async -> PluginsResponse = {
            PluginsResponse(plugins: [])
        },
        pluginDetail: @escaping @Sendable (String) async throws -> PluginDetailResponse = { _ in
            throw APIError.badRequest("plugin host is not configured")
        },
        enablePlugin: @escaping @Sendable (String) async throws -> PluginMutationResponse = { _ in
            throw APIError.badRequest("plugin host is not configured")
        },
        disablePlugin: @escaping @Sendable (String) async throws -> PluginMutationResponse = { _ in
            throw APIError.badRequest("plugin host is not configured")
        },
        installPlugin: @escaping @Sendable (PluginInstallRequest) async throws -> PluginMutationResponse = { _ in
            throw APIError.badRequest("plugin host is not configured")
        },
        uninstallPlugin: @escaping @Sendable (String) async throws -> PluginsResponse = { _ in
            throw APIError.badRequest("plugin host is not configured")
        },
        goals: @escaping @Sendable () async -> GoalsResponse = {
            GoalsResponse(goals: [])
        },
        goalDetail: @escaping @Sendable (String) async throws -> GoalDetailResponse = { id in
            throw APIError.notFound(id)
        },
        setGoal: @escaping @Sendable (GoalSetRequest) async throws -> GoalMutationResponse = { _ in
            throw APIError.badRequest("goal store is not configured")
        },
        abandonGoal: @escaping @Sendable (String) async throws -> GoalMutationResponse = { _ in
            throw APIError.badRequest("goal store is not configured")
        },
        updateGoal: @escaping @Sendable (String, GoalUpdateRequest) async throws -> GoalMutationResponse = { _, _ in
            throw APIError.badRequest("goal store is not configured")
        },
        manifestations: @escaping @Sendable () async -> ManifestationsResponse = {
            ManifestationsResponse(manifestations: [])
        },
        manifestationDetail: @escaping @Sendable (String) async throws -> ManifestationDetailResponse = { id in
            throw APIError.notFound(id)
        },
        runManifestation: @escaping @Sendable (ManifestationRunRequest) async throws -> ManifestationDetailResponse = { _ in
            throw APIError.badRequest("manifester is not configured")
        },
        deleteManifestation: @escaping @Sendable (String) async throws -> ManifestationsResponse = { _ in
            throw APIError.badRequest("manifestation store is not configured")
        },
        skillDetail: @escaping @Sendable (String) async throws -> SkillDetailResponse = { id in
            throw APIError.notFound(id)
        },
        searchSkills: @escaping @Sendable (SkillSearchRequest) async throws -> SkillsResponse = { _ in
            throw APIError.badRequest("skill store is not configured")
        },
        proposeSkill: @escaping @Sendable (SkillProposeRequest) async throws -> SkillMutationResponse = { _ in
            throw APIError.badRequest("skill store is not configured")
        },
        approveSkill: @escaping @Sendable (String) async throws -> SkillMutationResponse = { _ in
            throw APIError.badRequest("skill store is not configured")
        },
        rejectSkill: @escaping @Sendable (String) async throws -> SkillMutationResponse = { _ in
            throw APIError.badRequest("skill store is not configured")
        },
        deleteSkill: @escaping @Sendable (String) async throws -> SkillsResponse = { _ in
            throw APIError.badRequest("skill store is not configured")
        },
        memoryDetail: @escaping @Sendable (String) async throws -> MemoryDetailResponse = { id in
            throw APIError.notFound(id)
        },
        proposeMemory: @escaping @Sendable (MemoryProposeRequest) async throws -> MemoryMutationResponse = { _ in
            throw APIError.badRequest("memory store is not configured")
        },
        approveMemory: @escaping @Sendable (String) async throws -> MemoryMutationResponse = { _ in
            throw APIError.badRequest("memory store is not configured")
        },
        rejectMemory: @escaping @Sendable (String, MemoryReviewRequest) async throws -> MemoryMutationResponse = { _, _ in
            throw APIError.badRequest("memory store is not configured")
        },
        executeTool: @escaping @Sendable (String, ToolExecuteRequest) async throws -> ToolExecuteResponse = { _, _ in
            throw APIError.badRequest("tool registry is not configured")
        },
        addMCPServer: @escaping @Sendable (MCPServerCreateRequest) async throws -> MCPServerMutationResponse = { _ in
            throw APIError.badRequest("mcp registry is not configured")
        },
        removeMCPServer: @escaping @Sendable (String) async throws -> MCPServersResponse = { _ in
            throw APIError.badRequest("mcp registry is not configured")
        },
        connectMCPServer: @escaping @Sendable (String) async throws -> MCPServerMutationResponse = { _ in
            throw APIError.badRequest("mcp registry is not configured")
        },
        disconnectMCPServer: @escaping @Sendable (String) async throws -> MCPServerMutationResponse = { _ in
            throw APIError.badRequest("mcp registry is not configured")
        },
        mcpServerTools: @escaping @Sendable (String) async throws -> MCPServerToolsResponse = { _ in
            throw APIError.badRequest("mcp registry is not configured")
        },
        firewallGrants: @escaping @Sendable () async -> FirewallResponse = {
            FirewallResponse(granted: [], denied: [])
        },
        updateFirewall: @escaping @Sendable (FirewallGrantRequest) async throws -> FirewallMutationResponse = { _ in
            throw APIError.badRequest("firewall is not configured")
        },
        revokeFirewall: @escaping @Sendable (String) async throws -> FirewallResponse = { _ in
            throw APIError.badRequest("firewall is not configured")
        },
        checkFirewall: @escaping @Sendable (FirewallCheckRequest) async throws -> FirewallCheckResponse = { _ in
            throw APIError.badRequest("firewall is not configured")
        },
        cronJobs: @escaping @Sendable () async -> CronJobsResponse = {
            CronJobsResponse(jobs: [])
        },
        createCronJob: @escaping @Sendable (CronJobCreateRequest) async throws -> CronJobMutationResponse = { _ in
            throw APIError.badRequest("cron store is not configured")
        },
        deleteCronJob: @escaping @Sendable (String) async throws -> CronJobsResponse = { _ in
            throw APIError.badRequest("cron store is not configured")
        },
        runCronJob: @escaping @Sendable (String) async throws -> CronJobMutationResponse = { _ in
            throw APIError.badRequest("cron store is not configured")
        },
        calendarEvents: @escaping @Sendable () async -> CalendarEventsResponse = {
            CalendarEventsResponse(events: [])
        },
        doctorReport: @escaping @Sendable () async -> DoctorReportResponse = {
            DoctorReportResponse(
                id: "unconfigured",
                createdAt: Date(),
                checks: [],
                summary: DoctorSummaryWire(passed: 0, warnings: 0, failures: 0, skipped: 0),
                recommendations: [],
                isHealthy: true
            )
        },
        walletAccounts: @escaping @Sendable () async -> WalletAccountsResponse = {
            WalletAccountsResponse(accounts: [])
        },
        createWalletAccount: @escaping @Sendable (WalletCreateAccountRequest) async throws -> WalletAccountResponse = { _ in
            throw APIError.badRequest("wallet store is not configured")
        },
        deleteWalletAccount: @escaping @Sendable (String) async throws -> WalletAccountsResponse = { _ in
            throw APIError.badRequest("wallet store is not configured")
        },
        renameWalletAccount: @escaping @Sendable (String, WalletRenameRequest) async throws -> WalletAccountResponse = { _, _ in
            throw APIError.badRequest("wallet store is not configured")
        },
        refreshWalletBalance: @escaping @Sendable (String) async throws -> WalletBalanceResponse = { _ in
            throw APIError.badRequest("wallet store is not configured")
        },
        rebateSummary: @escaping @Sendable (String, String) async throws -> RebateSummaryResponse = { _, _ in
            throw APIError.badRequest("rebate tracker is not configured")
        },
        anchorBatches: @escaping @Sendable () async throws -> AnchorBatchesResponse = {
            throw APIError.badRequest("anchor engine is not configured")
        }
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
        self.tools = tools
        self.mcpServers = mcpServers
        self.audit = audit
        self.approvals = approvals
        self.resolveApproval = resolveApproval
        self.startCodexAuth = startCodexAuth
        self.codexAuthStatus = codexAuthStatus
        self.cancelCodexAuth = cancelCodexAuth
        self.plugins = plugins
        self.pluginDetail = pluginDetail
        self.enablePlugin = enablePlugin
        self.disablePlugin = disablePlugin
        self.installPlugin = installPlugin
        self.uninstallPlugin = uninstallPlugin
        self.goals = goals
        self.goalDetail = goalDetail
        self.setGoal = setGoal
        self.abandonGoal = abandonGoal
        self.updateGoal = updateGoal
        self.manifestations = manifestations
        self.manifestationDetail = manifestationDetail
        self.runManifestation = runManifestation
        self.deleteManifestation = deleteManifestation
        self.skillDetail = skillDetail
        self.searchSkills = searchSkills
        self.proposeSkill = proposeSkill
        self.approveSkill = approveSkill
        self.rejectSkill = rejectSkill
        self.deleteSkill = deleteSkill
        self.memoryDetail = memoryDetail
        self.proposeMemory = proposeMemory
        self.approveMemory = approveMemory
        self.rejectMemory = rejectMemory
        self.executeTool = executeTool
        self.addMCPServer = addMCPServer
        self.removeMCPServer = removeMCPServer
        self.connectMCPServer = connectMCPServer
        self.disconnectMCPServer = disconnectMCPServer
        self.mcpServerTools = mcpServerTools
        self.firewallGrants = firewallGrants
        self.updateFirewall = updateFirewall
        self.revokeFirewall = revokeFirewall
        self.checkFirewall = checkFirewall
        self.cronJobs = cronJobs
        self.createCronJob = createCronJob
        self.deleteCronJob = deleteCronJob
        self.runCronJob = runCronJob
        self.calendarEvents = calendarEvents
        self.doctorReport = doctorReport
        self.walletAccounts = walletAccounts
        self.createWalletAccount = createWalletAccount
        self.deleteWalletAccount = deleteWalletAccount
        self.renameWalletAccount = renameWalletAccount
        self.refreshWalletBalance = refreshWalletBalance
        self.rebateSummary = rebateSummary
        self.anchorBatches = anchorBatches
    }
}
