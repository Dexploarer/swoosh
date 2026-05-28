// SwooshDaemon/DaemonAPIRoutes.swift — 0.9S SwooshAPIRuntimeSources factory
//
// Builds the `SwooshAPIRuntimeSources` value that backs every route on
// /api/*. Extracted from `Daemon.swift` because it was a single
// ~300-line literal initialiser of named closures. Each closure
// delegates to a static `xResponse(...)` shim on `SwooshDaemon` that
// lives alongside the type it returns.
//
// All parameters here are values captured by the original closures —
// the daemon constructs them at boot and threads them through this
// factory so the route surface stays declarative.

import Foundation

import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshCron
import SwooshDaemonSupport
import SwooshGoals
import SwooshManifesting
import SwooshMCP
import SwooshPlugins
import SwooshPluginRuntime
import SwooshProviders
import SwooshSecrets
import SwooshSkills
import SwooshTools

extension SwooshDaemon {

    // swiftlint:disable function_parameter_count function_body_length
    static func makeRuntimeSources(
        configStore: SwooshConfigStore,
        secrets: KeychainSecretStore,
        providerInfo: (name: String, model: String)?,
        toolRuntime: DaemonToolRuntime,
        codexAuth: CodexAuthManager,
        pluginHost: PluginHost,
        pluginRegistry: PluginRegistry,
        mcpRegistry: MCPServerRegistry,
        skillStore: FileSkillStore,
        goalStore: FileGoalStore,
        manifestStore: FileManifestationStore,
        cronStore: FileCronJobStore,
        cronScheduler: CronScheduler,
        cronExecutor: @escaping CronAgentExecutor,
        manifester: Manifester,
        swooshDir: URL,
        providerRouter: ProviderRouter? = nil
    ) -> SwooshAPIRuntimeSources {
        return SwooshAPIRuntimeSources(
                providers: {
                    let preferredProviderID = (try? configStore.load(SwooshRuntimeConfig.self).preferredProviderID)
                    let summary = await SwooshDaemon.makeProviderSummaries(
                        secrets: secrets,
                        activeProvider: providerInfo,
                        preferredProviderID: preferredProviderID
                    )
                    return ProvidersResponse(
                        providers: summary.providers,
                        activeProviderID: summary.activeProviderID,
                        preferredProviderID: summary.preferredProviderID
                    )
                },
                saveProviderKey: { request in
                    try await SwooshDaemon.saveProviderKey(
                        request,
                        secrets: secrets,
                        configStore: configStore,
                        currentProvider: providerInfo
                    )
                },
                selectProvider: { request in
                    try await SwooshDaemon.selectProvider(
                        request,
                        configStore: configStore,
                        secrets: secrets,
                        currentProvider: providerInfo,
                        swooshDir: swooshDir,
                        router: providerRouter
                    )
                },
                skills: {
                    let skills = (try? await skillStore.listAll()) ?? []
                    return SkillsResponse(skills: skills
                        .filter { SkillTrust.promptable.contains($0.trust) }
                        .map(SwooshDaemon.skillSummary))
                },
                memories: {
                    await SwooshDaemon.memoriesResponse(memoryStore: toolRuntime.dependencies.memoryStore)
                },
                records: {
                    await SwooshDaemon.recordsResponse(
                        configStore: configStore,
                        secrets: secrets,
                        skillStore: skillStore,
                        goalStore: goalStore,
                        manifestStore: manifestStore,
                        cronStore: cronStore
                    )
                },
                media: {
                    SwooshDaemon.mediaResponse(root: swooshDir.appendingPathComponent("artifacts", isDirectory: true))
                },
                readiness: {
                    let preferredProviderID = (try? configStore.load(SwooshRuntimeConfig.self).preferredProviderID)
                    let summary = await SwooshDaemon.makeProviderSummaries(
                        secrets: secrets,
                        activeProvider: providerInfo,
                        preferredProviderID: preferredProviderID
                    )
                    let skills = (try? await skillStore.listAll()) ?? []
                    let activeProvider = summary.providers.first { $0.id == summary.activeProviderID }
                        ?? summary.providers.first(where: \.active)
                    return SwooshReadinessDetector(config: configStore).report(inputs: SwooshReadinessInputs(
                        daemonReachable: true,
                        chatEnabled: true,
                        activeProviderName: activeProvider?.name,
                        activeModel: activeProvider?.model,
                        promptableSkillCount: skills.filter { SkillTrust.promptable.contains($0.trust) }.count
                    ))
                },
                updateRuntimeFlags: { request in
                    try await SwooshDaemon.updateRuntimeFlags(request, configStore: configStore)
                },
                updateRuntimeProfile: { request in
                    try await SwooshDaemon.updateRuntimeProfile(request, configStore: configStore)
                },
                wallet: {
                    await SwooshDaemon.walletDashboard(
                        configStore: configStore,
                        secrets: secrets,
                        dependencies: toolRuntime.dependencies,
                        walletStore: toolRuntime.walletStore
                    )
                },
                tools: {
                    await SwooshDaemon.toolsResponse(registry: toolRuntime.registry)
                },
                mcpServers: {
                    await SwooshDaemon.mcpServersResponse(registry: mcpRegistry)
                },
                audit: {
                    let events = await toolRuntime.audit.tail(limit: 100)
                    return AuditEventsResponse(events: events.map(SwooshDaemon.auditSummary))
                },
                approvals: {
                    let pending = await toolRuntime.dependencies.approvals.listPending()
                    return ApprovalsResponse(pending: pending.map { SwooshDaemon.approvalSummary($0) })
                },
                resolveApproval: { id, request in
                    try await toolRuntime.dependencies.approvals.resolve(
                        id: id,
                        decision: SwooshDaemon.approvalDecision(request.decision),
                        reason: request.reason
                    )
                    let pending = await toolRuntime.dependencies.approvals.listPending()
                    let approval = pending.first { $0.id == id }
                        ?? ToolApprovalRequest(
                            id: id,
                            toolName: "Resolved approval",
                            risk: .medium,
                            inputPreview: request.reason ?? "Resolved",
                            sessionID: "default"
                        )
                    return ApprovalResolveResponse(
                        approval: SwooshDaemon.approvalSummary(approval, status: request.decision == .deny ? "denied" : "approved"),
                        message: "Approval resolved."
                    )
                },
                startCodexAuth: {
                    do {
                        let status = try await codexAuth.start()
                        return CodexAuthStatus(
                            state: .init(rawValue: status.state.rawValue) ?? .pending,
                            message: status.message,
                            startedAt: status.startedAt,
                            url: status.url
                        )
                    } catch {
                        throw APIError.internalError(error.localizedDescription)
                    }
                },
                codexAuthStatus: {
                    let status = await codexAuth.snapshot()
                    return CodexAuthStatus(
                        state: .init(rawValue: status.state.rawValue) ?? .idle,
                        message: status.message,
                        startedAt: status.startedAt,
                        url: status.url
                    )
                },
                cancelCodexAuth: {
                    await codexAuth.cancel()
                    let status = await codexAuth.snapshot()
                    return CodexAuthStatus(
                        state: .init(rawValue: status.state.rawValue) ?? .cancelled,
                        message: status.message,
                        startedAt: status.startedAt,
                        url: status.url
                    )
                },
                plugins: {
                    await SwooshDaemon.pluginsResponse(host: pluginHost)
                },
                pluginDetail: { id in
                    try await SwooshDaemon.pluginDetailResponse(host: pluginHost, registry: pluginRegistry, id: id)
                },
                enablePlugin: { id in
                    try await SwooshDaemon.enablePluginResponse(host: pluginHost, registry: pluginRegistry, id: id)
                },
                disablePlugin: { id in
                    try await SwooshDaemon.disablePluginResponse(host: pluginHost, registry: pluginRegistry, id: id)
                },
                installPlugin: { request in
                    try await SwooshDaemon.installPluginResponse(host: pluginHost, request: request)
                },
                uninstallPlugin: { id in
                    try await SwooshDaemon.uninstallPluginResponse(host: pluginHost, id: id)
                },
                goals: {
                    await SwooshDaemon.goalsResponse(store: goalStore)
                },
                goalDetail: { id in
                    try await SwooshDaemon.goalDetailResponse(store: goalStore, id: id)
                },
                setGoal: { request in
                    try await SwooshDaemon.setGoalResponse(store: goalStore, request: request)
                },
                abandonGoal: { id in
                    try await SwooshDaemon.abandonGoalResponse(store: goalStore, id: id)
                },
                updateGoal: { id, request in
                    try await SwooshDaemon.updateGoalResponse(store: goalStore, id: id, request: request)
                },
                manifestations: {
                    await SwooshDaemon.manifestationsResponse(store: manifestStore)
                },
                manifestationDetail: { id in
                    try await SwooshDaemon.manifestationDetailResponse(store: manifestStore, id: id)
                },
                runManifestation: { request in
                    try await SwooshDaemon.runManifestationResponse(manifester: manifester, request: request)
                },
                deleteManifestation: { id in
                    try await SwooshDaemon.deleteManifestationResponse(store: manifestStore, id: id)
                },
                skillDetail: { id in
                    try await SwooshDaemon.skillDetailResponse(store: skillStore, id: id)
                },
                searchSkills: { request in
                    try await SwooshDaemon.searchSkillsResponse(store: skillStore, request: request)
                },
                proposeSkill: { request in
                    try await SwooshDaemon.proposeSkillResponse(store: skillStore, request: request)
                },
                approveSkill: { id in
                    try await SwooshDaemon.approveSkillResponse(store: skillStore, id: id)
                },
                rejectSkill: { id in
                    try await SwooshDaemon.rejectSkillResponse(store: skillStore, id: id)
                },
                deleteSkill: { id in
                    try await SwooshDaemon.deleteSkillResponse(store: skillStore, id: id)
                },
                memoryDetail: { id in
                    try await SwooshDaemon.memoryDetailResponse(memoryStore: toolRuntime.dependencies.memoryStore, id: id)
                },
                proposeMemory: { request in
                    try await SwooshDaemon.proposeMemoryResponse(memoryStore: toolRuntime.dependencies.memoryStore, request: request)
                },
                approveMemory: { id in
                    try await SwooshDaemon.approveMemoryResponse(memoryStore: toolRuntime.dependencies.memoryStore, id: id)
                },
                rejectMemory: { id, request in
                    try await SwooshDaemon.rejectMemoryResponse(memoryStore: toolRuntime.dependencies.memoryStore, id: id, request: request)
                },
                executeTool: { name, request in
                    try await SwooshDaemon.executeToolResponse(
                        registry: toolRuntime.registry,
                        name: name,
                        request: request
                    )
                },
                addMCPServer: { request in
                    try await SwooshDaemon.addMCPServerResponse(registry: mcpRegistry, request: request)
                },
                removeMCPServer: { id in
                    try await SwooshDaemon.removeMCPServerResponse(registry: mcpRegistry, id: id)
                },
                connectMCPServer: { id in
                    try await SwooshDaemon.connectMCPServerResponse(registry: mcpRegistry, id: id)
                },
                disconnectMCPServer: { id in
                    try await SwooshDaemon.disconnectMCPServerResponse(registry: mcpRegistry, id: id)
                },
                mcpServerTools: { id in
                    try await SwooshDaemon.mcpServerToolsResponse(registry: mcpRegistry, id: id)
                },
                firewallGrants: {
                    await SwooshDaemon.firewallResponse(firewall: toolRuntime.firewall)
                },
                updateFirewall: { request in
                    try await SwooshDaemon.updateFirewallResponse(firewall: toolRuntime.firewall, request: request)
                },
                revokeFirewall: { permission in
                    try await SwooshDaemon.revokeFirewallResponse(firewall: toolRuntime.firewall, permission: permission)
                },
                checkFirewall: { request in
                    try await SwooshDaemon.checkFirewallResponse(firewall: toolRuntime.firewall, request: request)
                },
                cronJobs: {
                    await SwooshDaemon.cronJobsAPIResponse(store: cronStore)
                },
                createCronJob: { request in
                    try await SwooshDaemon.createCronJobResponse(store: cronStore, request: request)
                },
                deleteCronJob: { id in
                    try await SwooshDaemon.deleteCronJobResponse(store: cronStore, id: id)
                },
                runCronJob: { id in
                    try await SwooshDaemon.runCronJobResponse(
                        scheduler: cronScheduler,
                        store: cronStore,
                        executor: cronExecutor,
                        id: id
                    )
                },
                doctorReport: {
                    await SwooshDaemon.doctorReportResponse(config: configStore)
                },
                walletAccounts: {
                    await SwooshDaemon.walletAccountsResponse(store: toolRuntime.walletStore)
                },
                createWalletAccount: { request in
                    try await SwooshDaemon.createWalletAccountResponse(
                        store: toolRuntime.walletStore,
                        request: request
                    )
                },
                deleteWalletAccount: { id in
                    try await SwooshDaemon.deleteWalletAccountResponse(
                        store: toolRuntime.walletStore,
                        id: id
                    )
                },
                renameWalletAccount: { id, request in
                    try await SwooshDaemon.renameWalletAccountResponse(
                        store: toolRuntime.walletStore,
                        id: id,
                        request: request
                    )
                },
                refreshWalletBalance: { id in
                    try await SwooshDaemon.refreshWalletBalanceResponse(
                        store: toolRuntime.walletStore,
                        id: id
                    )
                }
        )
    }
    // swiftlint:enable function_parameter_count function_body_length
}
