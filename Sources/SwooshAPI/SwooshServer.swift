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
// Streaming / WebSocket can layer on top without changing the synchronous
// chat contract.

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
extension CodexAuthStatus: ResponseEncodable {}
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
extension AuditEventsResponse: ResponseEncodable {}
extension ApprovalsResponse: ResponseEncodable {}
extension ApprovalResolveResponse: ResponseEncodable {}
extension UsageResponse: ResponseEncodable {}
extension SkillsResponse: ResponseEncodable {}
extension ToolCatalogResponse: ResponseEncodable {}
extension MCPServersResponse: ResponseEncodable {}
extension LaunchpadsResponse: ResponseEncodable {}
extension LaunchpadPlatformResponse: ResponseEncodable {}
extension MemoriesResponse: ResponseEncodable {}
extension RecordsResponse: ResponseEncodable {}
extension MediaGalleryResponse: ResponseEncodable {}
extension ChatAdaptersResponse: ResponseEncodable {}
extension RuntimeConfigResponse: ResponseEncodable {}
extension RuntimeConfigMutationResponse: ResponseEncodable {}
extension WalletDashboardResponse: ResponseEncodable {}
extension PluginsResponse: ResponseEncodable {}
extension PluginDetailResponse: ResponseEncodable {}
extension PluginMutationResponse: ResponseEncodable {}
extension GoalsResponse: ResponseEncodable {}
extension GoalDetailResponse: ResponseEncodable {}
extension GoalMutationResponse: ResponseEncodable {}
extension ManifestationsResponse: ResponseEncodable {}
extension ManifestationDetailResponse: ResponseEncodable {}
extension SkillDetailResponse: ResponseEncodable {}
extension SkillMutationResponse: ResponseEncodable {}
extension MemoryDetailResponse: ResponseEncodable {}
extension MemoryMutationResponse: ResponseEncodable {}
extension ToolExecuteResponse: ResponseEncodable {}
extension MCPServerMutationResponse: ResponseEncodable {}
extension MCPServerToolsResponse: ResponseEncodable {}
extension FirewallResponse: ResponseEncodable {}
extension FirewallMutationResponse: ResponseEncodable {}
extension FirewallCheckResponse: ResponseEncodable {}
extension CronJobsResponse: ResponseEncodable {}
extension CronJobMutationResponse: ResponseEncodable {}
extension DoctorReportResponse: ResponseEncodable {}
extension WalletAccountsResponse: ResponseEncodable {}
extension WalletAccountResponse: ResponseEncodable {}
extension WalletBalanceResponse: ResponseEncodable {}

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

    // ── Tier 1: Doctor ─────────────────────────────────────────────
    public let doctorReport: @Sendable () async -> DoctorReportResponse

    // ── Tier 1: Wallet ops ─────────────────────────────────────────
    public let walletAccounts: @Sendable () async -> WalletAccountsResponse
    public let createWalletAccount: @Sendable (WalletCreateAccountRequest) async throws -> WalletAccountResponse
    public let deleteWalletAccount: @Sendable (String) async throws -> WalletAccountsResponse
    public let renameWalletAccount: @Sendable (String, WalletRenameRequest) async throws -> WalletAccountResponse
    public let refreshWalletBalance: @Sendable (String) async throws -> WalletBalanceResponse

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
        self.doctorReport = doctorReport
        self.walletAccounts = walletAccounts
        self.createWalletAccount = createWalletAccount
        self.deleteWalletAccount = deleteWalletAccount
        self.renameWalletAccount = renameWalletAccount
        self.refreshWalletBalance = refreshWalletBalance
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
                input: chatRequest.input,
                model: chatRequest.model,
                providerID: chatRequest.providerID
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
        apiGroup.post("/codex/auth/start") { _, _ -> CodexAuthStatus in
            do {
                return try await runtime.startCodexAuth()
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.get("/codex/auth/status") { _, _ -> CodexAuthStatus in
            await runtime.codexAuthStatus()
        }
        apiGroup.post("/codex/auth/cancel") { _, _ -> CodexAuthStatus in
            await runtime.cancelCodexAuth()
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
        apiGroup.get("/tools") { _, _ -> ToolCatalogResponse in
            await runtime.tools()
        }
        apiGroup.get("/audit") { _, _ -> AuditEventsResponse in
            await runtime.audit()
        }
        apiGroup.get("/approvals") { _, _ -> ApprovalsResponse in
            await runtime.approvals()
        }
        apiGroup.post("/approvals/:id/resolve") { request, context -> ApprovalResolveResponse in
            let id = try context.parameters.require("id", as: String.self)
            let body = try await request.decode(as: ApprovalResolveRequest.self, context: context)
            do {
                return try await runtime.resolveApproval(id, request: body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.get("/usage") { _, _ -> UsageResponse in
            await runtime.usage()
        }
        apiGroup.get("/skills") { _, _ -> SkillsResponse in
            await runtime.skills()
        }
        apiGroup.get("/launchpads") { _, _ -> LaunchpadsResponse in
            SwooshLaunchpadCatalog.platformsResponse()
        }
        apiGroup.get("/launchpads/:id") { _, context -> LaunchpadPlatformResponse in
            let id = try context.parameters.require("id", as: String.self)
            guard let response = SwooshLaunchpadCatalog.detail(id: id) else {
                throw HTTPError(.notFound, message: "unknown launchpad: \(id)")
            }
            return response
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
        apiGroup.get("/mcp/servers") { _, _ -> MCPServersResponse in
            await runtime.mcpServers()
        }

        // ── Plugins ────────────────────────────────────────────────
        // The HTTP layer is the humanOnly admin surface for plugin
        // lifecycle — every mutation here corresponds to one of the
        // four admin permissions (`pluginInstall`/`Uninstall`/`Enable`/
        // `Disable`). The bearer token enforces that the caller is
        // actually the user (the iOS app, the CLI, or curl with the
        // token); the firewall enforces that the model never reaches
        // these endpoints, because the API isn't reachable from inside
        // a tool call.
        apiGroup.get("/plugins") { _, _ -> PluginsResponse in
            await runtime.plugins()
        }
        apiGroup.get("/plugins/:id") { _, context -> PluginDetailResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.pluginDetail(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/plugins/:id/enable") { _, context -> PluginMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.enablePlugin(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/plugins/:id/disable") { _, context -> PluginMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.disablePlugin(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/plugins/install") { request, context -> PluginMutationResponse in
            let payload = try await request.decode(as: PluginInstallRequest.self, context: context)
            do {
                return try await runtime.installPlugin(payload)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/plugins/:id") { _, context -> PluginsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.uninstallPlugin(id)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Goals ──────────────────────────────────────────
        apiGroup.get("/goals") { _, _ -> GoalsResponse in
            await runtime.goals()
        }
        apiGroup.get("/goals/:id") { _, context -> GoalDetailResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.goalDetail(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/goals") { request, context -> GoalMutationResponse in
            let body = try await request.decode(as: GoalSetRequest.self, context: context)
            do {
                return try await runtime.setGoal(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/goals/:id/abandon") { _, context -> GoalMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.abandonGoal(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.patch("/goals/:id") { request, context -> GoalMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            let body = try await request.decode(as: GoalUpdateRequest.self, context: context)
            do {
                return try await runtime.updateGoal(id, request: body)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Manifestations ─────────────────────────────────
        apiGroup.get("/manifestations") { _, _ -> ManifestationsResponse in
            await runtime.manifestations()
        }
        apiGroup.get("/manifestations/:id") { _, context -> ManifestationDetailResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.manifestationDetail(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/manifestations/run") { request, context -> ManifestationDetailResponse in
            let body = try await request.decode(as: ManifestationRunRequest.self, context: context)
            do {
                return try await runtime.runManifestation(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/manifestations/:id") { _, context -> ManifestationsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.deleteManifestation(id)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Skills CRUD ────────────────────────────────────
        apiGroup.get("/skills/:id") { _, context -> SkillDetailResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.skillDetail(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/skills/search") { request, context -> SkillsResponse in
            let body = try await request.decode(as: SkillSearchRequest.self, context: context)
            do {
                return try await runtime.searchSkills(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/skills") { request, context -> SkillMutationResponse in
            let body = try await request.decode(as: SkillProposeRequest.self, context: context)
            do {
                return try await runtime.proposeSkill(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/skills/:id/approve") { _, context -> SkillMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.approveSkill(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/skills/:id/reject") { _, context -> SkillMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.rejectSkill(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/skills/:id") { _, context -> SkillsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.deleteSkill(id)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Memories CRUD ──────────────────────────────────
        apiGroup.get("/memories/:id") { _, context -> MemoryDetailResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.memoryDetail(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/memories") { request, context -> MemoryMutationResponse in
            let body = try await request.decode(as: MemoryProposeRequest.self, context: context)
            do {
                return try await runtime.proposeMemory(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/memories/:id/approve") { _, context -> MemoryMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.approveMemory(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/memories/:id/reject") { request, context -> MemoryMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            let body = (try? await request.decode(as: MemoryReviewRequest.self, context: context)) ?? MemoryReviewRequest()
            do {
                return try await runtime.rejectMemory(id, request: body)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Tool execution ─────────────────────────────────
        apiGroup.post("/tools/:name/execute") { request, context -> ToolExecuteResponse in
            let name = try context.parameters.require("name", as: String.self)
            // Body is required. Malformed JSON must return 400, not silently
            // execute the tool with empty args — for write tools that's a
            // hard-to-debug no-op or unexpected mutation.
            let body = try await request.decode(as: ToolExecuteRequest.self, context: context)
            do {
                return try await runtime.executeTool(name, request: body)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: MCP CRUD ───────────────────────────────────────
        apiGroup.post("/mcp/servers") { request, context -> MCPServerMutationResponse in
            let body = try await request.decode(as: MCPServerCreateRequest.self, context: context)
            do {
                return try await runtime.addMCPServer(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/mcp/servers/:id") { _, context -> MCPServersResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.removeMCPServer(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/mcp/servers/:id/connect") { _, context -> MCPServerMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.connectMCPServer(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/mcp/servers/:id/disconnect") { _, context -> MCPServerMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.disconnectMCPServer(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.get("/mcp/servers/:id/tools") { _, context -> MCPServerToolsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.mcpServerTools(id)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Firewall ───────────────────────────────────────
        apiGroup.get("/firewall/grants") { _, _ -> FirewallResponse in
            await runtime.firewallGrants()
        }
        apiGroup.post("/firewall/grants") { request, context -> FirewallMutationResponse in
            let body = try await request.decode(as: FirewallGrantRequest.self, context: context)
            do {
                return try await runtime.updateFirewall(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/firewall/grants/:permission") { _, context -> FirewallResponse in
            let permission = try context.parameters.require("permission", as: String.self)
            do {
                return try await runtime.revokeFirewall(permission)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/firewall/check") { request, context -> FirewallCheckResponse in
            let body = try await request.decode(as: FirewallCheckRequest.self, context: context)
            do {
                return try await runtime.checkFirewall(body)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Cron CRUD ──────────────────────────────────────
        apiGroup.get("/cron") { _, _ -> CronJobsResponse in
            await runtime.cronJobs()
        }
        apiGroup.post("/cron") { request, context -> CronJobMutationResponse in
            let body = try await request.decode(as: CronJobCreateRequest.self, context: context)
            do {
                return try await runtime.createCronJob(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/cron/:id") { _, context -> CronJobsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.deleteCronJob(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/cron/:id/run") { _, context -> CronJobMutationResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.runCronJob(id)
            } catch {
                throw apiHTTPError(error)
            }
        }

        // ── Tier 1: Doctor ─────────────────────────────────────────
        apiGroup.get("/doctor") { _, _ -> DoctorReportResponse in
            await runtime.doctorReport()
        }

        // ── Tier 1: Wallet ops ─────────────────────────────────────
        apiGroup.get("/wallet/accounts") { _, _ -> WalletAccountsResponse in
            await runtime.walletAccounts()
        }
        apiGroup.post("/wallet/accounts") { request, context -> WalletAccountResponse in
            let body = try await request.decode(as: WalletCreateAccountRequest.self, context: context)
            do {
                return try await runtime.createWalletAccount(body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.delete("/wallet/accounts/:id") { _, context -> WalletAccountsResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.deleteWalletAccount(id)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.patch("/wallet/accounts/:id") { request, context -> WalletAccountResponse in
            let id = try context.parameters.require("id", as: String.self)
            let body = try await request.decode(as: WalletRenameRequest.self, context: context)
            do {
                return try await runtime.renameWalletAccount(id, request: body)
            } catch {
                throw apiHTTPError(error)
            }
        }
        apiGroup.post("/wallet/accounts/:id/balance") { _, context -> WalletBalanceResponse in
            let id = try context.parameters.require("id", as: String.self)
            do {
                return try await runtime.refreshWalletBalance(id)
            } catch {
                throw apiHTTPError(error)
            }
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
                id: "pay.api_wallet",
                name: "Pay API wallet",
                enabled: permissions.contains(.mcpExecute),
                configured: false,
                status: "requires_pay_cli_or_mcp",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "pancakeswap.planner",
                name: "PancakeSwap planner",
                enabled: true,
                configured: true,
                status: "bundled_skill_deeplinks",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "launchpads.solana",
                name: "Solana launchpads",
                enabled: true,
                configured: true,
                status: "pumpportal_bags_skills",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "launchpads.bnb",
                name: "BNB launchpads",
                enabled: true,
                configured: true,
                status: "flap_fourmeme_skills",
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
