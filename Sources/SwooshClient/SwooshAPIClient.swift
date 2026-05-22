// SwooshClient/SwooshAPIClient.swift — URLSession HTTP client for swooshd
//
// Thin client over the SwooshAPI endpoints. Used by the iOS app and any other
// process that wants to talk to a running swooshd without embedding the full
// SwooshKit. Transports JSON, sends a `Bearer` token if one is configured.

import Foundation

/// HTTP client targeting a swooshd instance.
public actor SwooshAPIClient {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        token: String? = nil,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        // Default to a session with a tight 15s request timeout — the
        // shared session's 60s default makes "daemon unreachable" look
        // like "app frozen" for a long time on iOS.
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
        self.encoder = JSONEncoder.swooshDefault
        self.decoder = JSONDecoder.swooshDefault
    }

    // MARK: - Endpoints

    /// `GET /health` — returns true if the server responded `200 ok`.
    public func health() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok"
        } catch {
            return false
        }
    }

    /// `GET /api/version` — server build metadata.
    public func version() async throws -> APIVersion {
        let request = try makeRequest(method: "GET", path: "api/version", body: nil)
        return try await execute(request, as: APIVersion.self)
    }

    public func agentStatus() async throws -> AgentStatusResponse {
        let request = try makeRequest(method: "GET", path: "api/agent/status", body: nil)
        return try await execute(request, as: AgentStatusResponse.self)
    }

    public func transcript(sessionID: String) async throws -> TranscriptResponse {
        let encodedSessionID = try pathComponent(sessionID)
        let request = try makeRequest(method: "GET", path: "api/agent/transcript/\(encodedSessionID)", body: nil)
        return try await execute(request, as: TranscriptResponse.self)
    }

    public func readiness() async throws -> SwooshReadinessReport {
        let request = try makeRequest(method: "GET", path: "api/runtime/readiness", body: nil)
        return try await execute(request, as: SwooshReadinessReport.self)
    }

    public func runtimeConfig() async throws -> RuntimeConfigResponse {
        let request = try makeRequest(method: "GET", path: "api/runtime/config", body: nil)
        return try await execute(request, as: RuntimeConfigResponse.self)
    }

    public func updateRuntimeFlags(_ flags: [RuntimeFlagUpdate]) async throws -> RuntimeConfigMutationResponse {
        let body = try encoder.encode(RuntimeFlagUpdateRequest(flags: flags))
        let request = try makeRequest(method: "POST", path: "api/runtime/flags", body: body)
        return try await execute(request, as: RuntimeConfigMutationResponse.self)
    }

    public func updateRuntimeProfile(_ permissionProfile: String) async throws -> RuntimeConfigMutationResponse {
        let body = try encoder.encode(RuntimeProfileUpdateRequest(permissionProfile: permissionProfile))
        let request = try makeRequest(method: "POST", path: "api/runtime/profile", body: body)
        return try await execute(request, as: RuntimeConfigMutationResponse.self)
    }

    public func providers() async throws -> ProvidersResponse {
        let request = try makeRequest(method: "GET", path: "api/providers", body: nil)
        return try await execute(request, as: ProvidersResponse.self)
    }

    public func providerStatus() async throws -> ProviderStatusResponse {
        let request = try makeRequest(method: "GET", path: "api/providers/status", body: nil)
        return try await execute(request, as: ProviderStatusResponse.self)
    }

    public func saveProviderKey(providerID: String, apiKey: String) async throws -> ProviderMutationResponse {
        let body = try encoder.encode(ProviderAuthRequest(providerID: providerID, apiKey: apiKey))
        let request = try makeRequest(method: "POST", path: "api/providers/auth", body: body)
        return try await execute(request, as: ProviderMutationResponse.self)
    }

    public func selectProvider(providerID: String) async throws -> ProviderMutationResponse {
        let body = try encoder.encode(ProviderSelectionRequest(providerID: providerID))
        let request = try makeRequest(method: "POST", path: "api/providers/select", body: body)
        return try await execute(request, as: ProviderMutationResponse.self)
    }

    public func startCodexAuth() async throws -> CodexAuthStatus {
        let request = try makeRequest(method: "POST", path: "api/codex/auth/start", body: nil)
        return try await execute(request, as: CodexAuthStatus.self)
    }

    public func codexAuthStatus() async throws -> CodexAuthStatus {
        let request = try makeRequest(method: "GET", path: "api/codex/auth/status", body: nil)
        return try await execute(request, as: CodexAuthStatus.self)
    }

    public func cancelCodexAuth() async throws -> CodexAuthStatus {
        let request = try makeRequest(method: "POST", path: "api/codex/auth/cancel", body: nil)
        return try await execute(request, as: CodexAuthStatus.self)
    }

    public func boardCards() async throws -> BoardCardsResponse {
        let request = try makeRequest(method: "GET", path: "api/board/cards", body: nil)
        return try await execute(request, as: BoardCardsResponse.self)
    }

    public func boardLanes() async throws -> BoardLanesResponse {
        let request = try makeRequest(method: "GET", path: "api/board/lanes", body: nil)
        return try await execute(request, as: BoardLanesResponse.self)
    }

    public func metrics() async throws -> MetricsResponse {
        let request = try makeRequest(method: "GET", path: "api/metrics", body: nil)
        return try await execute(request, as: MetricsResponse.self)
    }

    public func audit() async throws -> AuditEventsResponse {
        let request = try makeRequest(method: "GET", path: "api/audit", body: nil)
        return try await execute(request, as: AuditEventsResponse.self)
    }

    public func approvals() async throws -> ApprovalsResponse {
        let request = try makeRequest(method: "GET", path: "api/approvals", body: nil)
        return try await execute(request, as: ApprovalsResponse.self)
    }

    public func resolveApproval(id: String, request body: ApprovalResolveRequest) async throws -> ApprovalResolveResponse {
        let encodedID = try pathComponent(id)
        let bodyData = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/approvals/\(encodedID)/resolve", body: bodyData)
        return try await execute(request, as: ApprovalResolveResponse.self)
    }

    public func usage() async throws -> UsageResponse {
        let request = try makeRequest(method: "GET", path: "api/usage", body: nil)
        return try await execute(request, as: UsageResponse.self)
    }

    public func skills() async throws -> SkillsResponse {
        let request = try makeRequest(method: "GET", path: "api/skills", body: nil)
        return try await execute(request, as: SkillsResponse.self)
    }

    public func toolCatalog() async throws -> ToolCatalogResponse {
        let request = try makeRequest(method: "GET", path: "api/tools", body: nil)
        return try await execute(request, as: ToolCatalogResponse.self)
    }

    public func mcpServers() async throws -> MCPServersResponse {
        let request = try makeRequest(method: "GET", path: "api/mcp/servers", body: nil)
        return try await execute(request, as: MCPServersResponse.self)
    }

    public func launchpads() async throws -> LaunchpadsResponse {
        let request = try makeRequest(method: "GET", path: "api/launchpads", body: nil)
        return try await execute(request, as: LaunchpadsResponse.self)
    }

    public func launchpad(id: String) async throws -> LaunchpadPlatformResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/launchpads/\(encodedID)", body: nil)
        return try await execute(request, as: LaunchpadPlatformResponse.self)
    }

    public func memories() async throws -> MemoriesResponse {
        let request = try makeRequest(method: "GET", path: "api/memories", body: nil)
        return try await execute(request, as: MemoriesResponse.self)
    }

    public func records() async throws -> RecordsResponse {
        let request = try makeRequest(method: "GET", path: "api/records", body: nil)
        return try await execute(request, as: RecordsResponse.self)
    }

    public func mediaGallery() async throws -> MediaGalleryResponse {
        let request = try makeRequest(method: "GET", path: "api/media", body: nil)
        return try await execute(request, as: MediaGalleryResponse.self)
    }

    public func walletDashboard() async throws -> WalletDashboardResponse {
        let request = try makeRequest(method: "GET", path: "api/wallet", body: nil)
        return try await execute(request, as: WalletDashboardResponse.self)
    }

    public func chatAdapters() async throws -> ChatAdaptersResponse {
        let request = try makeRequest(method: "GET", path: "api/chat-adapters", body: nil)
        return try await execute(request, as: ChatAdaptersResponse.self)
    }

    public func setChatAdapter(id: String, enabled: Bool) async throws -> ChatAdaptersResponse {
        let body = try encoder.encode(ChatAdapterToggleRequest(id: id, enabled: enabled))
        let request = try makeRequest(method: "POST", path: "api/chat-adapters/toggle", body: body)
        return try await execute(request, as: ChatAdaptersResponse.self)
    }

    /// `POST /api/agent/chat` — synchronous chat turn. The server runs one
    /// kernel pass and returns the full response in a single HTTP message.
    public func chat(_ chatRequest: ChatRequest) async throws -> ChatResponse {
        let body = try encoder.encode(chatRequest)
        let request = try makeRequest(method: "POST", path: "api/agent/chat", body: body)
        return try await execute(request, as: ChatResponse.self)
    }

    // MARK: - Plugins

    public func plugins() async throws -> PluginsResponse {
        let request = try makeRequest(method: "GET", path: "api/plugins", body: nil)
        return try await execute(request, as: PluginsResponse.self)
    }

    public func plugin(id: String) async throws -> PluginDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/plugins/\(encodedID)", body: nil)
        return try await execute(request, as: PluginDetailResponse.self)
    }

    public func enablePlugin(id: String) async throws -> PluginMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/plugins/\(encodedID)/enable", body: nil)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func disablePlugin(id: String) async throws -> PluginMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/plugins/\(encodedID)/disable", body: nil)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func installPlugin(sourcePath: String) async throws -> PluginMutationResponse {
        let body = try encoder.encode(PluginInstallRequest(sourcePath: sourcePath))
        let request = try makeRequest(method: "POST", path: "api/plugins/install", body: body)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func uninstallPlugin(id: String) async throws -> PluginsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/plugins/\(encodedID)", body: nil)
        return try await execute(request, as: PluginsResponse.self)
    }

    // MARK: - Tier 1: Goals

    public func goals() async throws -> GoalsResponse {
        let request = try makeRequest(method: "GET", path: "api/goals", body: nil)
        return try await execute(request, as: GoalsResponse.self)
    }

    public func goal(id: String) async throws -> GoalDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/goals/\(encodedID)", body: nil)
        return try await execute(request, as: GoalDetailResponse.self)
    }

    public func setGoal(_ body: GoalSetRequest) async throws -> GoalMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/goals", body: encoded)
        return try await execute(request, as: GoalMutationResponse.self)
    }

    public func abandonGoal(id: String) async throws -> GoalMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/goals/\(encodedID)/abandon", body: nil)
        return try await execute(request, as: GoalMutationResponse.self)
    }

    public func updateGoal(id: String, body: GoalUpdateRequest) async throws -> GoalMutationResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "PATCH", path: "api/goals/\(encodedID)", body: encoded)
        return try await execute(request, as: GoalMutationResponse.self)
    }

    // MARK: - Tier 1: Manifestations

    public func manifestations() async throws -> ManifestationsResponse {
        let request = try makeRequest(method: "GET", path: "api/manifestations", body: nil)
        return try await execute(request, as: ManifestationsResponse.self)
    }

    public func manifestation(id: String) async throws -> ManifestationDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/manifestations/\(encodedID)", body: nil)
        return try await execute(request, as: ManifestationDetailResponse.self)
    }

    public func runManifestation(_ body: ManifestationRunRequest = ManifestationRunRequest()) async throws -> ManifestationDetailResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/manifestations/run", body: encoded)
        return try await execute(request, as: ManifestationDetailResponse.self)
    }

    public func deleteManifestation(id: String) async throws -> ManifestationsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/manifestations/\(encodedID)", body: nil)
        return try await execute(request, as: ManifestationsResponse.self)
    }

    // MARK: - Tier 1: Skills CRUD

    public func skill(id: String) async throws -> SkillDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/skills/\(encodedID)", body: nil)
        return try await execute(request, as: SkillDetailResponse.self)
    }

    public func searchSkills(_ body: SkillSearchRequest) async throws -> SkillsResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/skills/search", body: encoded)
        return try await execute(request, as: SkillsResponse.self)
    }

    public func proposeSkill(_ body: SkillProposeRequest) async throws -> SkillMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/skills", body: encoded)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func approveSkill(id: String) async throws -> SkillMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/skills/\(encodedID)/approve", body: nil)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func rejectSkill(id: String) async throws -> SkillMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/skills/\(encodedID)/reject", body: nil)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func deleteSkill(id: String) async throws -> SkillsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/skills/\(encodedID)", body: nil)
        return try await execute(request, as: SkillsResponse.self)
    }

    // MARK: - Tier 1: Memories CRUD

    public func memory(id: String) async throws -> MemoryDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/memories/\(encodedID)", body: nil)
        return try await execute(request, as: MemoryDetailResponse.self)
    }

    public func proposeMemory(_ body: MemoryProposeRequest) async throws -> MemoryMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/memories", body: encoded)
        return try await execute(request, as: MemoryMutationResponse.self)
    }

    public func approveMemory(id: String) async throws -> MemoryMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/memories/\(encodedID)/approve", body: nil)
        return try await execute(request, as: MemoryMutationResponse.self)
    }

    public func rejectMemory(id: String, body: MemoryReviewRequest = MemoryReviewRequest()) async throws -> MemoryMutationResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/memories/\(encodedID)/reject", body: encoded)
        return try await execute(request, as: MemoryMutationResponse.self)
    }

    // MARK: - Tier 1: Tool execution

    public func executeTool(name: String, body: ToolExecuteRequest = ToolExecuteRequest()) async throws -> ToolExecuteResponse {
        let encodedName = try pathComponent(name)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/tools/\(encodedName)/execute", body: encoded)
        return try await execute(request, as: ToolExecuteResponse.self)
    }

    // MARK: - Tier 1: MCP CRUD

    public func addMCPServer(_ body: MCPServerCreateRequest) async throws -> MCPServerMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers", body: encoded)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func removeMCPServer(id: String) async throws -> MCPServersResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/mcp/servers/\(encodedID)", body: nil)
        return try await execute(request, as: MCPServersResponse.self)
    }

    public func connectMCPServer(id: String) async throws -> MCPServerMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers/\(encodedID)/connect", body: nil)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func disconnectMCPServer(id: String) async throws -> MCPServerMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers/\(encodedID)/disconnect", body: nil)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func mcpServerTools(id: String) async throws -> MCPServerToolsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/mcp/servers/\(encodedID)/tools", body: nil)
        return try await execute(request, as: MCPServerToolsResponse.self)
    }

    // MARK: - Tier 1: Firewall

    public func firewallGrants() async throws -> FirewallResponse {
        let request = try makeRequest(method: "GET", path: "api/firewall/grants", body: nil)
        return try await execute(request, as: FirewallResponse.self)
    }

    public func updateFirewall(_ body: FirewallGrantRequest) async throws -> FirewallMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/firewall/grants", body: encoded)
        return try await execute(request, as: FirewallMutationResponse.self)
    }

    public func revokeFirewall(permission: String) async throws -> FirewallResponse {
        let encoded = try pathComponent(permission)
        let request = try makeRequest(method: "DELETE", path: "api/firewall/grants/\(encoded)", body: nil)
        return try await execute(request, as: FirewallResponse.self)
    }

    public func checkFirewall(_ body: FirewallCheckRequest) async throws -> FirewallCheckResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/firewall/check", body: encoded)
        return try await execute(request, as: FirewallCheckResponse.self)
    }

    // MARK: - Tier 1: Cron CRUD

    public func cronJobs() async throws -> CronJobsResponse {
        let request = try makeRequest(method: "GET", path: "api/cron", body: nil)
        return try await execute(request, as: CronJobsResponse.self)
    }

    public func createCronJob(_ body: CronJobCreateRequest) async throws -> CronJobMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/cron", body: encoded)
        return try await execute(request, as: CronJobMutationResponse.self)
    }

    public func deleteCronJob(id: String) async throws -> CronJobsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/cron/\(encodedID)", body: nil)
        return try await execute(request, as: CronJobsResponse.self)
    }

    public func runCronJob(id: String) async throws -> CronJobMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/cron/\(encodedID)/run", body: nil)
        return try await execute(request, as: CronJobMutationResponse.self)
    }

    // MARK: - Tier 1: Wallet ops

    public func walletAccounts() async throws -> WalletAccountsResponse {
        let request = try makeRequest(method: "GET", path: "api/wallet/accounts", body: nil)
        return try await execute(request, as: WalletAccountsResponse.self)
    }

    public func createWalletAccount(_ body: WalletCreateAccountRequest) async throws -> WalletAccountResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/wallet/accounts", body: encoded)
        return try await execute(request, as: WalletAccountResponse.self)
    }

    public func deleteWalletAccount(id: String) async throws -> WalletAccountsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/wallet/accounts/\(encodedID)", body: nil)
        return try await execute(request, as: WalletAccountsResponse.self)
    }

    public func renameWalletAccount(id: String, body: WalletRenameRequest) async throws -> WalletAccountResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "PATCH", path: "api/wallet/accounts/\(encodedID)", body: encoded)
        return try await execute(request, as: WalletAccountResponse.self)
    }

    public func refreshWalletBalance(id: String) async throws -> WalletBalanceResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/wallet/accounts/\(encodedID)/balance", body: nil)
        return try await execute(request, as: WalletBalanceResponse.self)
    }

    // MARK: - Internals

    private func makeRequest(method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw SwooshClientError.transport("invalid path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
        }
        return request
    }

    private func pathComponent(_ value: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw SwooshClientError.transport("invalid path component: \(value)")
        }
        return encoded
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SwooshClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SwooshClientError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? decoder.decode(APIErrorBody.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw SwooshClientError.server(status: http.statusCode, message: serverMessage)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SwooshClientError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Errors

public enum SwooshClientError: Error, Sendable, LocalizedError {
    case transport(String)
    case server(status: Int, message: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .transport(let msg):
            return "Network error: \(msg)"
        case .server(let status, let message):
            return "Server returned \(status): \(message)"
        case .decoding(let msg):
            return "Could not decode server response: \(msg)"
        }
    }
}

// MARK: - JSON defaults

extension JSONEncoder {
    /// JSON encoder configured for the Swoosh wire format (ISO-8601 dates).
    public static let swooshDefault: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    /// JSON decoder configured for the Swoosh wire format (ISO-8601 dates).
    public static let swooshDefault: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
