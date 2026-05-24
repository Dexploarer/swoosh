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


