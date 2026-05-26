// SwooshDaemon/DaemonResponseBuilders.swift — 0.9S API response builders
//
// All `static func xResponse(...) -> Y` shims used by `DaemonAPIRoutes`
// closures. Extracted from `Daemon.swift` so the boot orchestration
// there stays focused. Roughly 900 LOC of mostly-pure mappings from
// store/registry types to wire types — further thematic splits
// (providers, wallet, MCP, …) are a follow-up.

import Foundation
import ActantAgent
import ActantDB
import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshFirewall
import SwooshKit
import SwooshMCP
import SwooshMLX
import SwooshModels
import SwooshProviderBridge
import SwooshProviders
import SwooshSecrets
import SwooshCron
import SwooshGoals
import SwooshManifesting
import SwooshSkills
import SwooshTools
import SwooshWallet

extension SwooshDaemon {

    static func makeProviderSummaries(
        secrets: KeychainSecretStore,
        activeProvider: (name: String, model: String)?,
        preferredProviderID: String? = nil,
        preferredModelID: String? = nil
    ) async -> (providers: [ProviderSummary], activeProviderID: String?, preferredProviderID: String?) {
        let openAIConfigured = await secrets.exists(SecretRef("openai", "api_key"))
        let openRouterConfigured = await secrets.exists(SecretRef("openrouter", "api_key"))
        let elizaCloudConfigured = await secrets.exists(SecretRef("eliza-cloud", "api_key"))
        let codexConfigured = await CodexBridgeProvider().isAuthenticated()
        let localServers = await LocalProviderDiscovery().discover()
        let localModel = localServers.first?.models.first

        let env = ProcessInfo.processInfo.environment
        let mlxModelEnv = env["SWOOSH_MLX_MODEL"]?.trimmingCharacters(in: .whitespaces)
        let mlxModel = mlxModelEnv.flatMap { $0.isEmpty ? nil : $0 } ?? ModelDefaults.localMLXModelID
        let mlxConfigured = MLXInferenceEngine.isAppleSilicon
        let foundationEnabled = env["SWOOSH_FOUNDATION_MODEL"] == "1"

        let activeID: String? = {
            guard let activeProvider else { return "local-diagnostic" }
            return ProviderFactory.providerID(forDetectedProviderName: activeProvider.name)
        }()

        var providers: [ProviderSummary] = [
            ProviderSummary(
                id: ModelDefaults.codexProviderID,
                name: "ChatGPT (via Codex)",
                model: codexConfigured ? modelForProvider(ModelDefaults.codexProviderID, preferredProviderID, preferredModelID, ModelDefaults.codexModelID) : nil,
                configured: codexConfigured,
                active: activeID == "codex",
                status: codexConfigured ? "signed_in" : "needs_signin"
            ),
            ProviderSummary(
                id: ModelDefaults.openAIProviderID,
                name: "OpenAI API",
                model: modelForProvider(ModelDefaults.openAIProviderID, preferredProviderID, preferredModelID, ModelDefaults.openAIModelID),
                configured: openAIConfigured,
                active: activeID == "openai",
                status: openAIConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: ModelDefaults.openRouterProviderID,
                name: "OpenRouter",
                model: modelForProvider(ModelDefaults.openRouterProviderID, preferredProviderID, preferredModelID, ModelDefaults.openRouterModelID),
                configured: openRouterConfigured,
                active: activeID == "openrouter",
                status: openRouterConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: ModelDefaults.elizaCloudProviderID,
                name: "Eliza Cloud",
                model: modelForProvider(ModelDefaults.elizaCloudProviderID, preferredProviderID, preferredModelID, ModelDefaults.elizaCloudModelID),
                configured: elizaCloudConfigured,
                active: activeID == ModelDefaults.elizaCloudProviderID,
                status: elizaCloudConfigured ? "configured" : "missing_key"
            ),
        ]

        if foundationEnabled {
            providers.append(ProviderSummary(
                id: ModelDefaults.localFoundationProviderID,
                name: "Apple Foundation Models",
                model: modelForProvider(ModelDefaults.localFoundationProviderID, preferredProviderID, preferredModelID, ModelDefaults.localFoundationModelID),
                configured: true,
                active: activeID == ModelDefaults.localFoundationProviderID,
                status: "running"
            ))
        }
        if mlxConfigured {
            providers.append(ProviderSummary(
                id: ModelDefaults.localMLXProviderID,
                name: "MLX Local",
                model: modelForProvider(ModelDefaults.localMLXProviderID, preferredProviderID, preferredModelID, mlxModel),
                configured: true,
                active: activeID == ModelDefaults.localMLXProviderID,
                status: (activeID == ModelDefaults.localMLXProviderID) ? "running" : "available"
            ))
        }
        providers.append(ProviderSummary(
            id: ModelDefaults.localOpenAIProviderID,
            name: localServers.first?.name ?? "Ollama / Local OpenAI",
            model: localModel.map { modelForProvider(ModelDefaults.localOpenAIProviderID, preferredProviderID, preferredModelID, $0) },
            configured: localModel != nil,
            active: activeID == ModelDefaults.localOpenAIProviderID,
            status: localModel == nil ? "not_running" : "running"
        ))

        if activeProvider == nil {
            providers.append(ProviderSummary(
                id: "local-diagnostic",
                name: "Local Diagnostic Provider",
                model: "swoosh-local-diagnostic-v1",
                configured: true,
                active: true,
                status: "active_until_model_provider_configured"
            ))
        }

        return (providers, activeID, preferredProviderID)
    }

    static func selectedRuntimeModelID(_ modelPath: String?) -> String? {
        let trimmed = modelPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return ["auto", "hybrid", "local", "cloud"].contains(trimmed.lowercased()) ? nil : trimmed
    }

    private static func modelForProvider(
        _ providerID: String,
        _ preferredProviderID: String?,
        _ preferredModelID: String?,
        _ fallback: String
    ) -> String {
        providerID == preferredProviderID ? (preferredModelID ?? fallback) : fallback
    }

    static func skillSummary(_ skill: SkillDocument) -> SkillSummary {
        SkillSummary(
            id: skill.id,
            title: skill.title,
            description: skill.description,
            category: skill.category.rawValue,
            trust: skill.trust.rawValue
        )
    }

    static func auditSummary(_ entry: AuditEntry) -> AuditEventSummary {
        AuditEventSummary(
            id: entry.id,
            timestamp: entry.timestamp,
            kind: entry.kind.rawValue,
            toolName: entry.toolName,
            sessionID: entry.sessionID,
            detail: entry.detail,
            success: entry.success
        )
    }

    static func approvalSummary(_ request: ToolApprovalRequest, status: String = "pending") -> ApprovalSummary {
        ApprovalSummary(
            id: request.id,
            sessionID: request.sessionID,
            toolName: request.toolName,
            risk: request.risk.rawValue,
            permission: request.permission.rawValue,
            inputPreview: request.inputPreview,
            status: status,
            createdAt: request.createdAt
        )
    }

    static func approvalDecision(_ decision: ApprovalResolveRequest.Decision) -> ApprovalDecision {
        switch decision {
        case .approveOnce:
            return .approveOnce
        case .approveForSession:
            return .approveForSession
        case .deny:
            return .deny
        }
    }

    static func saveProviderKey(
        _ request: ProviderAuthRequest,
        secrets: KeychainSecretStore,
        configStore: SwooshConfigStore,
        currentProvider: (name: String, model: String)?
    ) async throws -> ProviderMutationResponse {
        // Eliza Cloud is intentionally not iOS-accessible — it's an
        // experimental provider configured server-side via the CLI.
        guard ["openai", "openrouter"].contains(request.providerID) else {
            throw APIError.badRequest("provider does not accept API keys from the iOS app")
        }
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw APIError.badRequest("apiKey is required")
        }
        try await secrets.set(key, ref: SecretRef(request.providerID, "api_key"))
        try savePreferredProvider(request.providerID, modelID: nil, configStore: configStore)
        return try await providerMutationResponse(
            message: "Key stored in the Mac keychain. Restart swooshd to move chat onto this provider.",
            configStore: configStore,
            secrets: secrets,
            currentProvider: currentProvider
        )
    }

    static func selectProvider(
        _ request: ProviderSelectionRequest,
        configStore: SwooshConfigStore,
        secrets: KeychainSecretStore,
        currentProvider: (name: String, model: String)?
    ) async throws -> ProviderMutationResponse {
        let known = [
            ModelDefaults.routerProviderID,
            ModelDefaults.codexProviderID,
            ModelDefaults.openAIProviderID,
            ModelDefaults.openRouterProviderID,
            ModelDefaults.elizaCloudProviderID,
            ModelDefaults.localOpenAIProviderID,
            ModelDefaults.localMLXProviderID,
            ModelDefaults.localFoundationProviderID,
        ]
        guard known.contains(request.providerID) else {
            throw APIError.badRequest("unknown provider: \(request.providerID)")
        }
        try savePreferredProvider(request.providerID, modelID: request.modelID, configStore: configStore)
        return try await providerMutationResponse(
            message: "Provider preference saved. Restart swooshd to apply it to new chat turns.",
            configStore: configStore,
            secrets: secrets,
            currentProvider: currentProvider
        )
    }

    static func memoriesResponse(backend: AgentBackend) async -> SwooshClient.MemoriesResponse? {
        let store = MemoryStore(backend: backend)
        guard let approved = try? await store.listApproved(),
              let pending = try? await store.listPending() else { return nil }
        let rejectedRows = (try? await backend.client.memories(
            workspaceID: backend.workspaceID,
            status: "rejected"
        )) ?? []
        let rejected = rejectedRows.compactMap { row -> MemorySummary? in
            if case .rejected(let candidate) = row {
                return memorySummary(candidate)
            }
            return nil
        }
        return SwooshClient.MemoriesResponse(
            approved: approved.map(memorySummary),
            pending: pending.map(memorySummary),
            rejected: rejected
        )
    }

    static func recordsResponse(
        configStore: SwooshConfigStore,
        secrets: KeychainSecretStore,
        skillStore: FileSkillStore,
        goalStore: FileGoalStore,
        manifestStore: FileManifestationStore,
        cronStore: FileCronJobStore
    ) async -> RecordsResponse? {
        let skills = (try? await skillStore.listAll()) ?? []
        let active = await ProviderFactory.detectActiveProvider(
            secrets: secrets,
            preferredProviderID: (try? configStore.load(SwooshRuntimeConfig.self).preferredProviderID)
        )
        let readiness = SwooshReadinessDetector(config: configStore).report(inputs: SwooshReadinessInputs(
            daemonReachable: true,
            chatEnabled: true,
            activeProviderName: active?.name,
            activeModel: active?.model,
            promptableSkillCount: skills.filter { SkillTrust.promptable.contains($0.trust) }.count
        ))
        let goals = ((try? await goalStore.listAll()) ?? []).map { goal in
            GoalRecordSummary(
                id: goal.id,
                statement: goal.statement,
                state: goal.state.rawValue,
                progress: "\(goal.progress.completed)/\(goal.progress.ceiling)",
                updatedAt: goal.updatedAt
            )
        }
        let manifestations = ((try? await manifestStore.listRecent(limit: 20)) ?? []).map { manifestation in
            ManifestationRecordSummary(
                id: manifestation.id,
                status: manifestation.status.rawValue,
                triggerReason: manifestation.triggerReason,
                proposalCount: manifestation.proposals.count,
                summary: manifestation.summary,
                startedAt: manifestation.startedAt
            )
        }
        let cronJobs = ((try? await cronStore.list()) ?? []).map { job in
            CronJobRecordSummary(
                id: job.id,
                name: job.name,
                state: job.state.rawValue,
                enabled: job.enabled,
                nextRunAt: job.nextRunAt,
                lastRunAt: job.lastRunAt
            )
        }
        return RecordsResponse(
            readiness: readiness,
            metrics: MetricsResponse(counters: [
                MetricCounter(id: "skills", value: skills.count),
                MetricCounter(id: "goals", value: goals.count),
                MetricCounter(id: "manifestations", value: manifestations.count),
                MetricCounter(id: "cron_jobs", value: cronJobs.count),
            ]),
            usage: UsageResponse(chatTurns: 0, approvedMemoryReferences: 0, lastChatAt: nil),
            boardCards: [],
            goals: goals,
            manifestations: manifestations,
            cronJobs: cronJobs
        )
    }

    static func toolsResponse(registry: ToolRegistry) async -> ToolCatalogResponse {
        let context = ToolContext(
            sessionID: "dashboard",
            isModelInvocation: false,
            callerIdentity: "dashboard"
        )
        let descriptors = await registry.listAvailable(context: context)
            .sorted { lhs, rhs in
                if lhs.toolset.rawValue == rhs.toolset.rawValue {
                    return lhs.name < rhs.name
                }
                return lhs.toolset.rawValue < rhs.toolset.rawValue
            }
        let tools = descriptors.map { descriptor in
            ToolCatalogToolSummary(
                id: descriptor.id,
                name: descriptor.name,
                displayName: descriptor.displayName,
                description: descriptor.description,
                permission: descriptor.permission.rawValue,
                risk: descriptor.risk.rawValue,
                approval: approvalLabel(descriptor.approval),
                toolset: descriptor.toolset.rawValue,
                platforms: descriptor.platforms.map(\.rawValue).sorted()
            )
        }
        let toolsets = Dictionary(grouping: descriptors, by: \.toolset.rawValue)
            .map { id, grouped in
                ToolsetSummary(
                    id: id,
                    toolCount: grouped.count,
                    readOnlyCount: grouped.filter { $0.risk == .readOnly }.count,
                    writeCount: grouped.filter { $0.risk != .readOnly }.count,
                    humanOnlyCount: grouped.filter { $0.approval == .humanOnly }.count
                )
            }
            .sorted { $0.id < $1.id }
        return ToolCatalogResponse(tools: tools, toolsets: toolsets)
    }

    static func mcpServersResponse(registry: MCPServerRegistry) async -> MCPServersResponse {
        let servers = await registry.listServers()
        var summaries: [MCPServerRuntimeSummary] = []
        summaries.reserveCapacity(servers.count)
        for server in servers {
            let tools = await registry.listTools(serverID: server.id)
            var toolSummaries: [MCPDiscoveredToolSummary] = []
            toolSummaries.reserveCapacity(tools.count)
            for tool in tools {
                let risk = await registry.classifyToolRisk(serverID: server.id, toolName: tool.name)
                toolSummaries.append(MCPDiscoveredToolSummary(
                    id: tool.id,
                    name: tool.name,
                    title: tool.title,
                    description: tool.description,
                    estimatedRisk: risk.rawValue
                ))
            }
            summaries.append(MCPServerRuntimeSummary(
                id: server.id,
                name: server.name,
                description: server.description,
                enabled: server.enabled,
                trustLevel: server.trustLevel.rawValue,
                state: server.state.rawValue,
                transport: mcpTransportLabel(server.transport),
                toolCount: tools.count,
                importedToolCount: (await registry.importedToolNames(serverID: server.id)).count,
                tools: toolSummaries.sorted { $0.name < $1.name }
            ))
        }
        return MCPServersResponse(servers: summaries)
    }

    static func updateRuntimeFlags(
        _ request: RuntimeFlagUpdateRequest,
        configStore: SwooshConfigStore
    ) async throws -> RuntimeConfigMutationResponse {
        let current = runtimeConfigOrDefault(configStore: configStore)
        var safety = current.safetyConfig
        for flag in request.flags {
            switch flag.id {
            case "autonomousTradingEnabled":
                safety.autonomousTradingEnabled = flag.enabled
            case "humanPromptedTradingEnabled":
                safety.humanPromptedTradingEnabled = flag.enabled
            case "swapExecutionEnabled":
                safety.swapExecutionEnabled = flag.enabled
            case "portfolioRecommendationsEnabled":
                safety.portfolioRecommendationsEnabled = flag.enabled
            case "privateKeyCustodyEnabled":
                safety.privateKeyCustodyEnabled = flag.enabled
            case "seedPhraseIngestionEnabled":
                safety.seedPhraseIngestionEnabled = flag.enabled
            case "cookieIngestionEnabled":
                safety.cookieIngestionEnabled = flag.enabled
            case "shellToBlockchainBridgeEnabled":
                safety.shellToBlockchainBridgeEnabled = flag.enabled
            case "modelSelfApprovalEnabled":
                safety.modelSelfApprovalEnabled = flag.enabled
            case "mainnetWritesByDefault":
                safety.mainnetWritesByDefault = flag.enabled
            default:
                throw APIError.badRequest("unknown safety flag: \(flag.id)")
            }
        }
        let updated = runtimeConfig(from: current, safetyConfig: safety)
        try configStore.save(updated)
        let changed = updated.safetyConfig != current.safetyConfig
        return RuntimeConfigMutationResponse(
            config: runtimeConfigResponse(updated),
            requiresRestart: changed,
            message: changed
                ? "Safety flags saved. Restart swooshd to rebuild the firewall and tool registry with the new policy."
                : "Safety flags were already up to date."
        )
    }

    static func updateRuntimeProfile(
        _ request: RuntimeProfileUpdateRequest,
        configStore: SwooshConfigStore
    ) async throws -> RuntimeConfigMutationResponse {
        guard let preset = PermissionProfilePreset(rawValue: request.permissionProfile) else {
            throw APIError.badRequest("unknown permission profile: \(request.permissionProfile)")
        }
        let current = runtimeConfigOrDefault(configStore: configStore)
        let updated = runtimeConfig(
            from: current,
            permissionProfile: preset.rawValue,
            toolPolicy: preset.defaultToolPolicy,
            safetyConfig: preset.defaultSafetyConfig
        )
        try configStore.save(updated)
        let changed = updated.permissionProfile != current.permissionProfile
            || updated.toolPolicy != current.toolPolicy
            || updated.safetyConfig != current.safetyConfig
        return RuntimeConfigMutationResponse(
            config: runtimeConfigResponse(updated),
            requiresRestart: changed,
            message: changed
                ? "Permission profile saved. Restart swooshd to apply the new permissions to tool calls."
                : "Permission profile was already up to date."
        )
    }

    static func walletDashboard(
        configStore: SwooshConfigStore,
        secrets: KeychainSecretStore,
        dependencies: ToolDependencies,
        walletStore: WalletStore
    ) async -> WalletDashboardResponse {
        let config = runtimeConfigOrDefault(configStore: configStore)
        let permissions = PermissionProfilePreset(rawValue: config.permissionProfile)?.grantedSwooshPermissions ?? []
        let safety = config.safetyConfig
        let walletBridgeAvailable = dependencies.walletBridge != nil
        let walletAccounts = await walletStore.accounts()
        let assets = await walletAssetSummaries(walletStore: walletStore, accounts: walletAccounts)
        let evmRPCConfigured = dependencies.evmClient != nil
        let solanaRPCConfigured = dependencies.solanaClient != nil
        let hyperliquidRefs = (try? await secrets.listRefs(namespace: "hyperliquid")) ?? []
        let hyperliquidSecretConfigured = !hyperliquidRefs.isEmpty
        let payCLIAvailable = executableAvailable("pay")
        let provider = await ProviderFactory.detectActiveProvider(
            secrets: secrets,
            preferredProviderID: config.preferredProviderID
        )
        let promptedTradingEnabled = safety.humanPromptedTradingEnabled || safety.autonomousTradingEnabled
        let mainnetWritesEnabled = safety.mainnetWritesByDefault
            && permissions.contains(.evmMainnetWrite)
            && permissions.contains(.solanaMainnetWrite)

        let capabilities = [
            WalletTradingCapabilitySummary(
                id: "wallet.bridge",
                name: "Swoosh wallet bridge",
                enabled: permissions.contains(.evmRequestSignature) || permissions.contains(.solanaRequestSignature),
                configured: walletBridgeAvailable,
                status: walletBridgeAvailable ? "local_wallet_available" : "not_connected",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "evm.read",
                name: "EVM balances",
                enabled: permissions.contains(.evmRead),
                configured: evmRPCConfigured,
                status: evmRPCConfigured ? "rpc_ready" : "rpc_not_configured",
                risk: "read-only"
            ),
            WalletTradingCapabilitySummary(
                id: "solana.read",
                name: "Solana balances",
                enabled: permissions.contains(.solanaRead),
                configured: solanaRPCConfigured,
                status: solanaRPCConfigured ? "rpc_ready" : "rpc_not_configured",
                risk: "read-only"
            ),
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
                enabled: mainnetWritesEnabled,
                configured: permissions.contains(.evmMainnetWrite) || permissions.contains(.solanaMainnetWrite),
                status: mainnetWritesEnabled ? "mainnet_enabled" : "requires_trader_or_autonomous_profile",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "jupiter.swaps",
                name: "Jupiter swaps",
                enabled: promptedTradingEnabled && safety.swapExecutionEnabled && permissions.contains(.solanaRequestSignature),
                configured: walletBridgeAvailable,
                status: walletBridgeAvailable ? "wallet_ready" : "waiting_for_wallet_bridge",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "uniswap.swaps",
                name: "Uniswap swap builder",
                enabled: promptedTradingEnabled && safety.swapExecutionEnabled && permissions.contains(.evmBuildTransaction),
                configured: evmRPCConfigured,
                status: evmRPCConfigured ? "rpc_ready" : "waiting_for_evm_rpc",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "pay.api_wallet",
                name: "Pay API wallet",
                enabled: permissions.contains(.mcpExecute),
                configured: payCLIAvailable,
                status: payCLIAvailable ? "pay_cli_available_attach_mcp" : "install_pay_cli",
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
                id: "pumpportal.launchpad",
                name: "PumpPortal launchpad",
                enabled: permissions.contains(.solanaBuildTransaction),
                configured: true,
                status: "local_tx_skill_ready_lightning_requires_api_key",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "bags.launchpad",
                name: "Bags launchpad",
                enabled: permissions.contains(.solanaBuildTransaction),
                configured: true,
                status: "launch_intent_and_transaction_skill_ready",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "flap.launchpad",
                name: "Flap launchpad",
                enabled: permissions.contains(.evmBuildTransaction),
                configured: evmRPCConfigured,
                status: evmRPCConfigured ? "vaultportal_skill_ready" : "waiting_for_evm_rpc",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "fourmeme.launchpad",
                name: "Four.meme launchpad",
                enabled: permissions.contains(.evmBuildTransaction),
                configured: evmRPCConfigured,
                status: evmRPCConfigured ? "tokenmanager_skill_ready" : "waiting_for_evm_rpc",
                risk: "high"
            ),
            WalletTradingCapabilitySummary(
                id: "hyperliquid.market_data",
                name: "Hyperliquid market data",
                enabled: permissions.contains(.networkRead),
                configured: true,
                status: "public_read_client",
                risk: "read-only"
            ),
            WalletTradingCapabilitySummary(
                id: "hyperliquid.trading",
                name: "Hyperliquid trading",
                enabled: promptedTradingEnabled && permissions.contains(.hyperliquidTrade),
                configured: hyperliquidSecretConfigured,
                status: hyperliquidSecretConfigured ? "secret_ref_available" : "waiting_for_keychain_secret_ref",
                risk: "critical"
            ),
            WalletTradingCapabilitySummary(
                id: "portfolio.insights",
                name: "Portfolio AI insights",
                enabled: safety.portfolioRecommendationsEnabled,
                configured: provider != nil,
                status: provider == nil ? "waiting_for_model_provider" : "model_provider_ready",
                risk: "medium"
            ),
        ]
        return WalletDashboardResponse(
            connected: walletBridgeAvailable,
            walletLabel: walletBridgeAvailable ? "Local Swoosh wallet" : nil,
            analytics: WalletAnalyticsSummary(
                totalValueUSD: nil,
                realizedPnLUSD: nil,
                unrealizedPnLUSD: nil,
                totalPnLPercent: nil,
                dailyChangePercent: nil,
                openPositions: 0
            ),
            assets: assets,
            insights: walletInsights(
                safety: safety,
                walletBridgeAvailable: walletBridgeAvailable,
                providerConfigured: provider != nil,
                hyperliquidSecretConfigured: hyperliquidSecretConfigured,
                mainnetWritesEnabled: mainnetWritesEnabled
            ),
            capabilities: capabilities
        )
    }

    static func walletAssetSummaries(
        walletStore: WalletStore,
        accounts: [WalletAccount]
    ) async -> [WalletAssetSummary] {
        var assets: [WalletAssetSummary] = []
        for account in accounts {
            let balance = try? await walletStore.refreshBalance(for: account)
            assets.append(WalletAssetSummary(
                id: account.id.uuidString,
                chain: account.chain.rawValue,
                symbol: account.chain.nativeSymbol,
                name: account.label.isEmpty ? account.address : account.label,
                quantity: balance?.formatted ?? account.address,
                valueUSD: nil,
                costBasisUSD: nil,
                pnlUSD: nil,
                pnlPercent: nil
            ))
        }
        return assets
    }

    private static func executableAvailable(_ name: String) -> Bool {
        let fm = FileManager.default
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/\(name)" }
        let commonCandidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return (pathCandidates + commonCandidates).contains { fm.isExecutableFile(atPath: $0) }
    }

    static func mediaResponse(root: URL) -> MediaGalleryResponse {
        let manager = FileManager.default
        let root = root.standardizedFileURL
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return MediaGalleryResponse(items: [], root: root.path)
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let items = enumerator.compactMap { entry -> MediaGalleryItem? in
            guard let url = entry as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { return nil }
            let path = url.standardizedFileURL.path
            let relativePath = path.hasPrefix(rootPrefix) ? String(path.dropFirst(rootPrefix.count)) : url.lastPathComponent
            return MediaGalleryItem(
                id: relativePath,
                title: url.lastPathComponent,
                kind: mediaKind(for: url.pathExtension),
                relativePath: relativePath,
                byteSize: Int64(values?.fileSize ?? 0),
                createdAt: values?.creationDate
            )
        }
        .sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        return MediaGalleryResponse(items: Array(items.prefix(200)), root: root.path)
    }

    private static func savePreferredProvider(_ providerID: String, modelID: String?, configStore: SwooshConfigStore) throws {
        let current = try? configStore.load(SwooshRuntimeConfig.self)
        let selectedProvider = providerID == ModelDefaults.routerProviderID ? nil : providerID
        let selectedModel = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPath: String
        if let selectedModel, !selectedModel.isEmpty {
            modelPath = selectedModel
        } else if current?.preferredProviderID == selectedProvider {
            modelPath = current?.modelPath ?? UnifiedModelCatalog.defaultModel(providerID: providerID) ?? "auto"
        } else {
            modelPath = UnifiedModelCatalog.defaultModel(providerID: providerID) ?? "auto"
        }
        let updated = SwooshRuntimeConfig(
            version: current?.version ?? 1,
            setupMode: current?.setupMode ?? "phone",
            permissionProfile: current?.permissionProfile ?? PermissionProfilePreset.developer.rawValue,
            modelPath: selectedProvider == nil ? "auto" : modelPath,
            daemonHost: current?.daemonHost ?? "0.0.0.0",
            daemonPort: current?.daemonPort ?? 8787,
            preferredProviderID: selectedProvider,
            localDiagnosticFallback: current?.localDiagnosticFallback ?? true,
            toolPolicy: current?.toolPolicy,
            safetyConfig: current?.safetyConfig,
            configuredAt: current?.configuredAt ?? ISO8601DateFormatter().string(from: Date())
        )
        try configStore.save(updated)
    }

    private static func providerMutationResponse(
        message: String,
        configStore: SwooshConfigStore,
        secrets: KeychainSecretStore,
        currentProvider: (name: String, model: String)?
    ) async throws -> ProviderMutationResponse {
        let runtimeConfig = try? configStore.load(SwooshRuntimeConfig.self)
        let preferredProviderID = runtimeConfig?.preferredProviderID
        let summary = await makeProviderSummaries(
            secrets: secrets,
            activeProvider: currentProvider,
            preferredProviderID: preferredProviderID,
            preferredModelID: selectedRuntimeModelID(runtimeConfig?.modelPath)
        )
        return ProviderMutationResponse(
            providers: summary.providers,
            activeProviderID: summary.activeProviderID,
            preferredProviderID: summary.preferredProviderID,
            requiresRestart: summary.activeProviderID != preferredProviderID,
            message: message
        )
    }

    private static func runtimeConfigOrDefault(configStore: SwooshConfigStore) -> SwooshRuntimeConfig {
        (try? configStore.load(SwooshRuntimeConfig.self)) ?? SwooshRuntimeConfig(
            setupMode: "phone",
            permissionProfile: PermissionProfilePreset.developer.rawValue,
            modelPath: "auto",
            daemonHost: "0.0.0.0",
            daemonPort: 8787,
            preferredProviderID: nil
        )
    }

    private static func runtimeConfig(
        from current: SwooshRuntimeConfig,
        permissionProfile: String? = nil,
        toolPolicy: ToolCallPolicy? = nil,
        safetyConfig: SwooshSafetyConfig? = nil
    ) -> SwooshRuntimeConfig {
        SwooshRuntimeConfig(
            version: current.version,
            setupMode: current.setupMode,
            permissionProfile: permissionProfile ?? current.permissionProfile,
            modelPath: current.modelPath,
            daemonHost: current.daemonHost,
            daemonPort: current.daemonPort,
            preferredProviderID: current.preferredProviderID,
            localDiagnosticFallback: current.localDiagnosticFallback,
            toolPolicy: toolPolicy ?? current.toolPolicy,
            safetyConfig: safetyConfig ?? current.safetyConfig,
            configuredAt: current.configuredAt
        )
    }

    private static func approvalLabel(_ approval: ApprovalPolicy) -> String {
        switch approval {
        case .never:
            return "never"
        case .askFirstTime:
            return "askFirstTime"
        case .askEveryTime:
            return "askEveryTime"
        case .askForRiskAtLeast(let risk):
            return "askForRiskAtLeast:\(risk.rawValue)"
        case .humanOnly:
            return "humanOnly"
        case .disabled:
            return "disabled"
        }
    }

    static func mcpTransportLabel(_ transport: MCPTransportConfiguration) -> String {
        switch transport {
        case .stdio:
            return "stdio"
        case .http:
            return "http"
        }
    }

    private static func runtimeConfigResponse(_ config: SwooshRuntimeConfig) -> RuntimeConfigResponse {
        RuntimeConfigResponse(
            configured: true,
            setupMode: config.setupMode,
            permissionProfile: config.permissionProfile,
            modelPath: config.modelPath,
            daemonHost: config.daemonHost,
            daemonPort: config.daemonPort,
            preferredProviderID: config.preferredProviderID,
            localDiagnosticFallback: config.localDiagnosticFallback,
            toolPolicy: ToolPolicySummary(
                maxToolCallsPerTurn: config.toolPolicy.maxToolCallsPerTurn,
                maxToolChainDepth: config.toolPolicy.maxToolChainDepth,
                allowModelToolCalls: config.toolPolicy.allowModelToolCalls,
                allowHumanOnlyFromModel: config.toolPolicy.allowHumanOnlyFromModel,
                allowCriticalToolsFromModel: config.toolPolicy.allowCriticalToolsFromModel,
                requireApprovalForMediumRiskAndAbove: config.toolPolicy.requireApprovalForMediumRiskAndAbove
            ),
            safetyFlags: safetyFlagSummaries(config.safetyConfig)
        )
    }

    private static func safetyFlagSummaries(_ config: SwooshSafetyConfig) -> [RuntimeFlagSummary] {
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

    private static func walletInsights(
        safety: SwooshSafetyConfig,
        walletBridgeAvailable: Bool,
        providerConfigured: Bool,
        hyperliquidSecretConfigured: Bool,
        mainnetWritesEnabled: Bool
    ) -> [WalletInsightSummary] {
        var insights: [WalletInsightSummary] = []
        if walletBridgeAvailable {
            insights.append(WalletInsightSummary(
                id: "wallet.bridge_available",
                severity: .info,
                title: "Wallet bridge is available",
                detail: "Trading tools can request accounts and signatures through the configured bridge.",
                source: "runtime"
            ))
        } else {
            insights.append(WalletInsightSummary(
                id: "wallet.bridge_missing",
                severity: .warning,
                title: "No wallet bridge connected",
                detail: "EVM, Solana, Jupiter, Uniswap, Pay, and PancakeSwap write or payment flows need wallet or MCP setup before live account actions.",
                source: "runtime"
            ))
        }
        if safety.portfolioRecommendationsEnabled {
            insights.append(WalletInsightSummary(
                id: "portfolio.insights_enabled",
                severity: providerConfigured ? .info : .warning,
                title: "Portfolio insights are enabled",
                detail: providerConfigured
                    ? "The configured model provider can generate portfolio commentary once wallet data is available."
                    : "Add a model provider key before treating insights as model-backed analysis.",
                source: "runtime"
            ))
        }
        if safety.humanPromptedTradingEnabled {
            insights.append(WalletInsightSummary(
                id: "trading.human_prompted_enabled",
                severity: .warning,
                title: "Human-prompted trading is enabled",
                detail: "Trading tools may be requested by the agent, but write/sign/broadcast actions still require approval.",
                source: "safety_config"
            ))
        }
        if safety.autonomousTradingEnabled {
            insights.append(WalletInsightSummary(
                id: "trading.autonomous_enabled",
                severity: .warning,
                title: "Autonomous trading is enabled",
                detail: "The runtime will allow trading tools after a daemon restart when matching permissions and credentials are present.",
                source: "safety_config"
            ))
        }
        if mainnetWritesEnabled {
            insights.append(WalletInsightSummary(
                id: "trading.mainnet_enabled",
                severity: .critical,
                title: "Mainnet writes are enabled",
                detail: "Mainnet write tools will be eligible by default after the daemon reloads this config.",
                source: "safety_config"
            ))
        }
        if !hyperliquidSecretConfigured {
            insights.append(WalletInsightSummary(
                id: "hyperliquid.secret_missing",
                severity: .info,
                title: "Hyperliquid key is not configured",
                detail: "Read-only Hyperliquid market data is available, but trading needs a Keychain secret ref.",
                source: "keychain"
            ))
        }
        return insights
    }

    static func memorySummary(_ memory: ActantDB.ApprovedMemory) -> MemorySummary {
        MemorySummary(
            id: memory.id,
            text: memory.text,
            category: memory.category,
            status: memory.status,
            sensitivity: memory.sensitivity.rawValue,
            confidence: memory.confidence,
            createdAt: memory.createdAt
        )
    }

    static func memorySummary(_ candidate: ActantDB.MemoryCandidate) -> MemorySummary {
        MemorySummary(
            id: candidate.id,
            text: candidate.text,
            category: candidate.category,
            status: candidate.status,
            sensitivity: candidate.sensitivity.rawValue,
            confidence: candidate.confidence,
            createdAt: candidate.createdAt
        )
    }

    private static func mediaKind(for fileExtension: String) -> MediaGalleryKind {
        switch fileExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff":
            return .image
        case "mp4", "mov", "m4v", "webm":
            return .video
        case "mp3", "wav", "m4a", "aac", "flac", "ogg":
            return .audio
        default:
            return .other
        }
    }
}
