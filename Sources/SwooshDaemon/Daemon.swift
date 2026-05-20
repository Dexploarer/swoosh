// SwooshDaemon/Daemon.swift — swooshd background service
//
// Lifecycle:
//   1. Supervise an `actantdb serve` child process and export ACTANT_BASE_URL.
//   2. Resolve a bearer API token (env var → on-disk cache → freshly minted).
//   3. Build a Swoosh agent via SwooshKit.configure { } so chat requests
//      hit the same kernel path as the SDK.
//   4. Start the Hummingbird API server with token + kernel bound in.
//
// Network policy:
//   • Default bind is 127.0.0.1 so the daemon is loopback-only.
//   • SWOOSH_HOST=0.0.0.0 opts in to LAN exposure (used when an iPhone is
//     supposed to reach the Mac). The bearer token is *always* required on
//     /api/* regardless of the bind address — the loopback default is a
//     defense-in-depth choice, not the only line of defense.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Intents)
import Intents
#endif
import ActantDB
import ActantAgent
import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshKit
import SwooshScout
import SwooshSkills
import SwooshGoals
import SwooshManifesting
import SwooshCron
import SwooshToolsets
import SwooshTools
import SwooshFirewall
import SwooshApprovals
import SwooshFiles
import SwooshProcess
import SwooshProviderBridge
import SwooshProviders
import SwooshCore
import SwooshSecrets
import SwooshDaemonSupport

@main
struct SwooshDaemon {
    static func main() async throws {
        let version = "0.9P"
        printBanner(version: version)

        let env = ProcessInfo.processInfo.environment
        let port = Int(env["SWOOSH_PORT"] ?? "8787") ?? 8787
        let host = env["SWOOSH_HOST"] ?? "127.0.0.1"

        // ── ~/.swoosh state directory ─────────────────────────────────
        let swooshDir = stateDirectory(env: env)
        let configStore = SwooshConfigStore(configDirectory: swooshDir)
        let runtimeConfig = try? configStore.load(SwooshRuntimeConfig.self)
        let permissionPreset = PermissionProfilePreset(rawValue: runtimeConfig?.permissionProfile ?? "") ?? .developer
        let toolPolicy = runtimeConfig?.toolPolicy ?? permissionPreset.defaultToolPolicy
        let safetyConfig = runtimeConfig?.safetyConfig ?? permissionPreset.defaultSafetyConfig
        try? FileManager.default.createDirectory(at: swooshDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: swooshDir.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )

        // ── ActantDB subprocess ──────────────────────────────────────
        let supervisor = ActantDBSupervisor(
            extraSearchPaths: actantDBSearchPaths(),
            logOutputTo: swooshDir.appendingPathComponent("logs/actantdb.log")
        )
        let baseURL: URL
        do {
            baseURL = try await supervisor.start(
                dbPath: swooshDir.appendingPathComponent("actant.db")
            )
        } catch {
            log("FATAL: \(error)")
            exit(1)
        }
        log("ActantDB ready at \(baseURL)")
        setenv("ACTANT_BASE_URL", baseURL.absoluteString, 1)
        let agentBackend = AgentBackend(
            client: ActantClient(baseURL: baseURL, token: env["ACTANT_TOKEN"]),
            workspaceID: env["ACTANT_WORKSPACE_ID"] ?? "ws_swoosh",
            actorID: env["ACTANT_ACTOR_ID"] ?? "act_swoosh_daemon"
        )

        let signalHandler = SignalHandler(supervisor: supervisor)
        signalHandler.install()

        // ── Bearer token ─────────────────────────────────────────────
        // Order: explicit env > persisted file > freshly generated. The
        // freshly-generated token is also persisted so paired iPhones don't
        // need to be re-paired across daemon restarts.
        let token: String
        do {
            token = try DaemonTokenResolver.resolve(swooshDir: swooshDir, env: env)
        } catch {
            log("FATAL: failed to resolve API token: \(error)")
            exit(1)
        }
        if host != "127.0.0.1" {
            log("WARNING: binding to \(host) — daemon is reachable from other devices on this network.")
        }
        _ = token
        log("API token resolved and stored at \(swooshDir.appendingPathComponent("api_token").path).")
        log("Pair an iPhone by entering the stored token into the Swoosh iOS app.")

        // ── Provider router (real inference when keys are present) ───
        // Matches the CLI's wiring: detect any configured provider via
        // ProviderFactory; if one exists, build the router + bridge and
        // plug it into Swoosh.configure. Falls back to LocalDiagnosticProvider
        // when no keys are configured so chat keeps returning *some*
        // response while the user finishes provisioning.
        let secrets = KeychainSecretStore()
        let providerInfo = await ProviderFactory.detectActiveProvider(
            secrets: secrets,
            preferredProviderID: runtimeConfig?.preferredProviderID
        )
        let modelProvider: any SwooshCore.ModelProvider
        if let info = providerInfo {
            let (router, _) = await ProviderFactory.buildRouter(
                secrets: secrets,
                preferredProviderID: runtimeConfig?.preferredProviderID
            )
            modelProvider = ProviderBridgeAdapter(router: router, role: .primaryChat, modelName: info.model)
            log("Provider: \(info.name) (\(info.model))")
        } else {
            modelProvider = LocalDiagnosticProvider()
            log("Provider: local diagnostic (no API key configured — run `swoosh provider auth`).")
        }

        // Build a second adapter for the meta-tasks (manifester miner +
        // goal judge) so they don't compete with chat for the same model
        // routing decisions. Uses a distinct role so the user can route
        // reflective passes through a cheaper / faster provider.
        let metaProvider: (any SwooshCore.ModelProvider)? = {
            guard providerInfo != nil else { return nil }
            return modelProvider
        }()

        let toolRuntime = try await makeDaemonToolRuntime(
            swooshDir: swooshDir,
            backend: agentBackend,
            grantedPermissions: permissionPreset.grantedSwooshPermissions,
            safetyConfig: safetyConfig
        )

        // ── Real kernel ──────────────────────────────────────────────
        // ACTANT_BASE_URL is set; SwooshKit.configure picks it up and wires
        // the kernel through SwooshActantBackend so the iPhone's chat turns
        // ride the same ledger as the Mac's.
        let swoosh: Swoosh
        do {
            swoosh = try await Swoosh.configure { config in
                config.modelProvider = modelProvider
                config.toolRegistry = toolRuntime.registry
                config.toolPolicy = toolPolicy
            }
        } catch {
            log("FATAL: failed to build agent kernel: \(error)")
            exit(1)
        }
        log("Agent kernel ready with tool loop")

        // ── Self-improvement pillars ────────────────────────────────
        // Local durable stores for non-cloud self-improvement state. ActantDB
        // still owns sessions/memories/audit; these JSON stores keep goals
        // and manifestation passes alive across daemon restarts without
        // waiting on cloud sync.
        let skillStore = FileSkillStore(
            directory: swooshDir.appendingPathComponent("skills", isDirectory: true)
        )
        let bundledLoader = BundledSkillLoader(
            store: skillStore,
            directory: URL(fileURLWithPath: "Skills/Bundled", isDirectory: true,
                           relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        )
        let loadedSkills = (try? await bundledLoader.loadAll()) ?? []
        log("Skills loaded: \(loadedSkills.count) bundled + any user-authored on disk")

        let goalStore = FileGoalStore(
            url: swooshDir.appendingPathComponent("goals/goals.json")
        )
        let manifestStore = FileManifestationStore(
            url: swooshDir.appendingPathComponent("manifesting/manifestations.json")
        )

        // Pattern miner: uses a model when configured, otherwise falls
        // back to deterministic audit-window observations.
        let miner: Manifester.PatternMiner = makeMiner(metaProvider: metaProvider)
        let manifester = Manifester(store: manifestStore, miner: miner)
        let manifestPolicy = ManifestationPolicy()
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: manifestStore,
            policy: manifestPolicy
        )
        log("Manifester ready (\(metaProvider == nil ? "deterministic" : "model-backed") miner; scheduler armed).")

        let cronStore = FileCronJobStore(root: swooshDir.appendingPathComponent("cron", isDirectory: true))
        let cronScheduler = CronScheduler(store: cronStore, processRunner: CronProcessRunner())
        await DefaultToolRegistrar.registerAll(
            into: toolRuntime.registry,
            dependencies: toolRuntime.dependencies,
            selfImprovement: SelfImprovementDependencies(
                skills: SkillToolDependencies(store: skillStore),
                goals: GoalToolDependencies(store: goalStore),
                manifest: ManifestToolDependencies(store: manifestStore, manifester: manifester),
                cron: CronToolDependencies(store: cronStore, scheduler: cronScheduler)
            )
        )

        // Real judge for the goal runner.
        let judge: GoalRunner.Judge = makeJudge(metaProvider: metaProvider)
        let goalRunner = GoalRunner(
            store: goalStore,
            agentTurn: { goal in
                // Each iteration sends the goal statement back into the
                // kernel as a new chat turn. The kernel decides what to
                // do; the judge reads its observation.
                let request = AgentRequest(
                    sessionID: "goal-\(goal.id)",
                    input: goal.statement
                )
                let response = try await swoosh.ask(request.input, sessionID: request.sessionID)
                return response.message
            },
            judge: judge
        )

        // ── Scout: App-usage recorder ────────────────────────────────
        // macOS-only background observer. Other platforms keep the same
        // API surface without starting an NSWorkspace observer.
        let personalizationSignals = PersonalizationSignalStore()
        try? await personalizationSignals.append(PersonalizationSignal(
            kind: .daemonStarted,
            label: "swooshd",
            metadata: ["host": host, "port": String(port)]
        ))

        let appUsageRecorder = AppUsageRecorder(signalStore: personalizationSignals)
        await appUsageRecorder.start()
        log("AppUsageRecorder started (NSWorkspace frontmost-app observer).")

        let scoutAutopilotTask = makeScoutAutopilotTask(
            backend: agentBackend,
            signalStore: personalizationSignals,
            env: env
        )

        // ── Manifestation scheduler tick loop ───────────────────────
        // Evaluates the policy every five minutes. The policy itself
        // enforces a minimum cooldown so this won't oversample; on a
        // typical day it produces one manifestation per idle window.
        let schedulerTask = Task.detached(priority: .background) {
            while !Task.isCancelled {
                let idle = await currentIdleSeconds()
                let focus = await currentFocusIdentifier()
                _ = try? await scheduler.tick(idleSeconds: idle, activeFocus: focus)
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
        log("Manifestation scheduler tick task started.")
        log("Scout autopilot scheduler started.")

        let cronExecutor: CronAgentExecutor = { request in
            let response = try await swoosh.ask(request.prompt, sessionID: request.sessionID)
            return response.message
        }
        let cronTask = Task.detached(priority: .background) {
            while !Task.isCancelled {
                do {
                    let records = try await cronScheduler.tick(executor: cronExecutor)
                    for record in records {
                        SwooshDaemon.log("Cron job \(record.jobID) finished with \(record.status.rawValue).")
                    }
                } catch {
                    SwooshDaemon.log("Cron scheduler error: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
        let runtime = DaemonRuntime(
            skillStore: skillStore,
            goalStore: goalStore,
            manifestStore: manifestStore,
            manifester: manifester,
            goalRunner: goalRunner,
            appUsageRecorder: appUsageRecorder,
            personalizationSignals: personalizationSignals,
            scoutAutopilotTask: scoutAutopilotTask,
            manifestationTask: schedulerTask,
            cronStore: cronStore,
            cronScheduler: cronScheduler,
            cronTask: cronTask
        )
        log("Cron scheduler tick task started.")

        // ── HTTP API ─────────────────────────────────────────────────
        log("API server starting on http://\(host):\(port)")
        log("Health: http://\(host):\(port)/health (public)")
        log("Chat:   POST http://\(host):\(port)/api/agent/chat (bearer-gated)")
        let providerSummaries = await makeProviderSummaries(
            secrets: secrets,
            activeProvider: providerInfo,
            preferredProviderID: runtimeConfig?.preferredProviderID
        )
        let skillSummaries = loadedSkills
            .filter { SkillTrust.promptable.contains($0.trust) }
            .map(SwooshDaemon.skillSummary)
        let server = SwooshAPIServer(
            port: port,
            hostname: host,
            token: token,
            kernel: swoosh.kernel,
            toolLoop: swoosh.toolLoop,
            snapshot: SwooshAPISnapshot(
                providers: providerSummaries.providers,
                activeProviderID: providerSummaries.activeProviderID,
                skills: skillSummaries
            ),
            runtimeSources: SwooshAPIRuntimeSources(
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
                        currentProvider: providerInfo
                    )
                },
                skills: {
                    let skills = (try? await skillStore.listAll()) ?? []
                    return SkillsResponse(skills: skills
                        .filter { SkillTrust.promptable.contains($0.trust) }
                        .map(SwooshDaemon.skillSummary))
                },
                memories: {
                    await SwooshDaemon.memoriesResponse(backend: agentBackend)
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
                        dependencies: toolRuntime.dependencies
                    )
                }
            )
        )
        let app = server.build()

        defer {
            Task {
                await runtime.stop()
                await supervisor.stop()
            }
        }
        try await app.run()
    }

    // MARK: - Banner / log

    static func printBanner(version: String) {
        print("""

        ┌──────────────────────────────────────┐
        │  swooshd v\(version) — Swoosh Daemon     │
        │  Press Ctrl-C to stop                │
        └──────────────────────────────────────┘
        """)
    }

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] swooshd: \(message)")
    }

    static func actantDBSearchPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".cache/cargo-actantdb/debug", isDirectory: true),
            home.appendingPathComponent("actantDB/target/debug", isDirectory: true),
            home.appendingPathComponent("actantDB/node_modules/.bin", isDirectory: true),
        ]
    }

    static func stateDirectory(env: [String: String]) -> URL {
        if let configured = env["SWOOSH_CONFIG_DIR"] ?? env["SWOOSH_STATE_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
    }

    static func makeProviderSummaries(
        secrets: KeychainSecretStore,
        activeProvider: (name: String, model: String)?,
        preferredProviderID: String? = nil
    ) async -> (providers: [ProviderSummary], activeProviderID: String?, preferredProviderID: String?) {
        let openAIConfigured = (try? await secrets.exists(SecretRef("openai", "api_key"))) ?? false
        let openRouterConfigured = (try? await secrets.exists(SecretRef("openrouter", "api_key"))) ?? false
        let elizaConfigured = (try? await secrets.exists(SecretRef("eliza-cloud", "api_key"))) ?? false
        let localServers = await LocalProviderDiscovery().discover()
        let localModel = localServers.first?.models.first

        let activeID: String? = {
            guard let activeProvider else { return "local-diagnostic" }
            switch activeProvider.name {
            case "OpenAI": return "openai"
            case "OpenRouter": return "openrouter"
            case "Eliza Cloud": return "eliza-cloud"
            default: return "local-openai"
            }
        }()

        var providers = [
            ProviderSummary(
                id: "openai",
                name: "OpenAI API",
                model: "gpt-4.1",
                configured: openAIConfigured,
                active: activeID == "openai",
                status: openAIConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: "openrouter",
                name: "OpenRouter",
                model: "openai/gpt-4.1",
                configured: openRouterConfigured,
                active: activeID == "openrouter",
                status: openRouterConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: "eliza-cloud",
                name: "Eliza Cloud",
                model: "auto",
                configured: elizaConfigured,
                active: activeID == "eliza-cloud",
                status: elizaConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: "local-openai",
                name: localServers.first?.name ?? "Local OpenAI-Compatible",
                model: localModel,
                configured: localModel != nil,
                active: activeID == "local-openai",
                status: localModel == nil ? "not_running" : "running"
            ),
        ]

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

    static func skillSummary(_ skill: SkillDocument) -> SkillSummary {
        SkillSummary(
            id: skill.id,
            title: skill.title,
            description: skill.description,
            category: skill.category.rawValue,
            trust: skill.trust.rawValue
        )
    }

    static func saveProviderKey(
        _ request: ProviderAuthRequest,
        secrets: KeychainSecretStore,
        configStore: SwooshConfigStore,
        currentProvider: (name: String, model: String)?
    ) async throws -> ProviderMutationResponse {
        guard ["openai", "openrouter", "eliza-cloud"].contains(request.providerID) else {
            throw APIError.badRequest("provider does not accept API keys from the iOS app")
        }
        let key = request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw APIError.badRequest("apiKey is required")
        }
        try await secrets.set(key, ref: SecretRef(request.providerID, "api_key"))
        try savePreferredProvider(request.providerID, configStore: configStore)
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
        guard ["openai", "openrouter", "eliza-cloud", "local-openai"].contains(request.providerID) else {
            throw APIError.badRequest("unknown provider: \(request.providerID)")
        }
        try savePreferredProvider(request.providerID, configStore: configStore)
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
        dependencies: ToolDependencies
    ) async -> WalletDashboardResponse {
        let config = runtimeConfigOrDefault(configStore: configStore)
        let permissions = PermissionProfilePreset(rawValue: config.permissionProfile)?.grantedSwooshPermissions ?? []
        let safety = config.safetyConfig
        let walletBridgeAvailable = dependencies.walletBridge != nil
        let evmRPCConfigured = dependencies.evmClient != nil
        let solanaRPCConfigured = dependencies.solanaClient != nil
        let hyperliquidRefs = (try? await secrets.listRefs(namespace: "hyperliquid")) ?? []
        let hyperliquidSecretConfigured = !hyperliquidRefs.isEmpty
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
                name: "External wallet bridge",
                enabled: permissions.contains(.evmRequestSignature) || permissions.contains(.solanaRequestSignature),
                configured: walletBridgeAvailable,
                status: walletBridgeAvailable ? "available" : "not_connected",
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
            walletLabel: walletBridgeAvailable ? "External wallet bridge" : nil,
            analytics: WalletAnalyticsSummary(
                totalValueUSD: nil,
                realizedPnLUSD: nil,
                unrealizedPnLUSD: nil,
                totalPnLPercent: nil,
                dailyChangePercent: nil,
                openPositions: 0
            ),
            assets: [],
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

    private static func savePreferredProvider(_ providerID: String, configStore: SwooshConfigStore) throws {
        let current = try? configStore.load(SwooshRuntimeConfig.self)
        let updated = SwooshRuntimeConfig(
            version: current?.version ?? 1,
            setupMode: current?.setupMode ?? "phone",
            permissionProfile: current?.permissionProfile ?? PermissionProfilePreset.developer.rawValue,
            modelPath: current?.modelPath ?? "auto",
            daemonHost: current?.daemonHost ?? "0.0.0.0",
            daemonPort: current?.daemonPort ?? 8787,
            preferredProviderID: providerID,
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
        let preferredProviderID = (try? configStore.load(SwooshRuntimeConfig.self).preferredProviderID)
        let summary = await makeProviderSummaries(
            secrets: secrets,
            activeProvider: currentProvider,
            preferredProviderID: preferredProviderID
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
                detail: "EVM, Solana, Jupiter, and Uniswap write flows need a wallet bridge before analytics can attach to live accounts.",
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

    private static func memorySummary(_ memory: ActantDB.ApprovedMemory) -> MemorySummary {
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

    private static func memorySummary(_ candidate: ActantDB.MemoryCandidate) -> MemorySummary {
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

// MARK: - Tool runtime

private struct DaemonToolRuntime: Sendable {
    let registry: ToolRegistry
    let dependencies: ToolDependencies
}

private func makeDaemonToolRuntime(
    swooshDir: URL,
    backend: AgentBackend,
    grantedPermissions: Set<SwooshPermission>,
    safetyConfig: SwooshSafetyConfig
) async throws -> DaemonToolRuntime {
    let audit = SwooshAuditLog()
    let firewall = SwooshFirewallActor(granted: grantedPermissions)
    let approvalCenter = SwooshApprovals.ApprovalCenter(store: InMemoryApprovalStore(), audit: audit)
    let rootStore = InMemoryRootStore()
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .standardizedFileURL
    await rootStore.add(ApprovedRoot(
        id: "cwd",
        displayName: cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent,
        absolutePath: cwd.path,
        allowedRead: true,
        allowedWrite: true
    ))
    await rootStore.add(ApprovedRoot(
        id: "swoosh-state",
        displayName: ".swoosh",
        absolutePath: swooshDir.standardizedFileURL.path,
        allowedRead: true,
        allowedWrite: true
    ))

    let registry = ToolRegistry(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: safetyConfig
    )
    let dependencies = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: safetyConfig,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(approvedRoots: [cwd.path, swooshDir.path]),
        memoryStore: MemoryStore(backend: backend),
        scoutStore: FileScoutToolStore(url: swooshDir.appendingPathComponent("scout/tool-state.json")),
        workflowStore: FileWorkflowToolStore(url: swooshDir.appendingPathComponent("workflows/tool-drafts.json")),
        workflowStepExecutor: RegistryWorkflowStepExecutor(registry: registry)
    )
    await DefaultToolRegistrar.registerAll(into: registry, dependencies: dependencies)
    return DaemonToolRuntime(registry: registry, dependencies: dependencies)
}

// MARK: - Scout autopilot

@Sendable
private func makeScoutAutopilotTask(
    backend: AgentBackend,
    signalStore: PersonalizationSignalStore,
    env: [String: String]
) -> Task<Void, Never> {
    if env["SWOOSH_SCOUT_AUTOPILOT_DISABLED"] == "1" {
        return Task {}
    }

    let interval = UInt64(max(60, Int(env["SWOOSH_SCOUT_AUTOPILOT_INTERVAL_SECONDS"] ?? "1800") ?? 1800))
    let startupDelay = UInt64(max(5, Int(env["SWOOSH_SCOUT_AUTOPILOT_STARTUP_DELAY_SECONDS"] ?? "20") ?? 20))
    let idleThreshold = TimeInterval(max(0, Int(env["SWOOSH_SCOUT_AUTOPILOT_IDLE_SECONDS"] ?? "60") ?? 60))

    return Task.detached(priority: .background) {
        try? await Task.sleep(nanoseconds: startupDelay * 1_000_000_000)
        while !Task.isCancelled {
            let idle = await currentIdleSeconds()
            if idle == nil || (idle ?? 0) >= idleThreshold {
                let result = try? await runPassiveScoutOnce(
                    backend: backend,
                    signalStore: signalStore
                )
                if let result {
                    try? await signalStore.append(PersonalizationSignal(
                        kind: .scoutAutopilotRun,
                        label: "passive-scout",
                        weight: Double(result.candidatesGenerated),
                        metadata: [
                            "records": String(result.recordsCollected),
                            "candidates": String(result.candidatesGenerated),
                        ]
                    ))
                    SwooshDaemon.log(
                        "Scout autopilot proposed \(result.candidatesGenerated) candidate(s) from \(result.recordsCollected) record(s)."
                    )
                }
            }
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
        }
    }
}

private func runPassiveScoutOnce(
    backend: AgentBackend,
    signalStore: PersonalizationSignalStore
) async throws -> ScoutPipelineResult {
    let memory = MemoryStore(backend: backend)
    let existing = try await existingMemorySummaries(memory: memory)
    let sources = makePassiveScoutSources(signalStore: signalStore)
    let pipeline = ScoutPipeline(sources: sources)
    let result = try await pipeline.run(
        depth: .deep,
        options: ScoutPipelineOptions(
            permissionMode: .skipUnavailable,
            existingMemories: existing,
            minimumConfidence: 0.74
        )
    )

    let client = await backend.client
    let workspaceID = await backend.workspaceID
    let actorID = await backend.actorID
    for record in result.records {
        _ = try await client.saveScoutRecord(
            workspaceID: workspaceID,
            actorID: actorID,
            sourceID: record.sourceID,
            kind: record.kind.rawValue,
            sensitivity: actantSensitivity(from: record.sensitivity.rawValue),
            content: record.content,
            metadata: jsonValue(record.metadata)
        )
    }
    for candidate in result.candidates {
        _ = try await memory.propose(
            text: candidate.text,
            category: candidate.category,
            sensitivity: actantSensitivity(from: candidate.sensitivity.rawValue),
            confidence: candidate.confidence,
            evidence: candidateEvidenceJSON(evidence: candidate.evidence, ttl: candidate.recommendedTTL)
        )
    }
    if result.recordsCollected > 0 || result.candidatesGenerated > 0 {
        _ = try await client.saveSetupReport(
            workspaceID: workspaceID,
            actorID: actorID,
            content: result.setupReport
        )
    }
    return result
}

private func makePassiveScoutSources(signalStore: PersonalizationSignalStore) -> [any ScoutSource] {
    ScoutSourceCatalog.passiveLocalSources(signalStore: signalStore)
}

private func existingMemorySummaries(memory: MemoryStore) async throws -> [ExistingMemorySummary] {
    let approved = try await memory.listApproved()
    let pending = try await memory.listPending()
    return approved.map { ExistingMemorySummary(text: $0.text, category: $0.category) } +
        pending.map { ExistingMemorySummary(text: $0.text, category: $0.category) }
}

private func actantSensitivity(from raw: String) -> ActantDB.Sensitivity {
    switch raw {
    case "low": .low
    case "medium": .medium
    default: .high
    }
}

private func jsonValue(_ metadata: [String: String]) -> ActantDB.JSONValue {
    guard
        let data = try? JSONSerialization.data(withJSONObject: metadata),
        let value = try? JSONDecoder().decode(ActantDB.JSONValue.self, from: data)
    else { return .object([:]) }
    return value
}

private struct CandidateEvidencePayload<Evidence: Encodable>: Encodable {
    let evidence: Evidence
    let recommendedTTL: TimeInterval?
}

private func candidateEvidenceJSON<Evidence: Encodable>(
    evidence: Evidence,
    ttl: TimeInterval?
) -> ActantDB.JSONValue {
    let payload = CandidateEvidencePayload(evidence: evidence, recommendedTTL: ttl)
    guard
        let data = try? JSONEncoder().encode(payload),
        let value = try? JSONDecoder().decode(ActantDB.JSONValue.self, from: data)
    else { return .array([]) }
    return value
}

// MARK: - Meta-task closures (miner + judge)

/// Build the manifester's pattern miner. When `metaProvider` is nil the
/// deterministic miner still emits conservative audit observations. When
/// a provider is supplied, the miner asks it for structured proposals.
@Sendable
private func makeMiner(metaProvider: (any SwooshCore.ModelProvider)?) -> Manifester.PatternMiner {
    guard let provider = metaProvider else {
        return Manifester.deterministicMiner
    }
    return { events in
        let condensed = events.prefix(50).map {
            "- [\($0.timestamp.timeIntervalSince1970)] \($0.kind): \($0.summary)"
        }.joined(separator: "\n")
        let system = """
        You are Swoosh's nightly Manifester. Read the user's recent audit
        events and propose at most five new skill drafts or memory
        candidates that would make the agent more useful tomorrow.
        Respond with a JSON array. Each item must be:
        { "kind": "newSkill" | "newMemoryCandidate" | "observation",
          "title": string, "rationale": string, "confidence": 0..1,
          "payload": string }
        No prose outside the JSON.
        """
        let user = """
        Recent audit events (\(events.count) total, most recent first):
        \(condensed)
        """
        let response = try await provider.complete(SwooshCore.ModelCompletionRequest(
            messages: [
                SwooshCore.ChatMessage(role: .system, content: system),
                SwooshCore.ChatMessage(role: .user, content: user),
            ],
            model: nil
        ))
        // Extract the JSON array. Models sometimes wrap it in code
        // fences; strip those and decode defensively.
        let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let data = stripped.data(using: .utf8) else { return [] }
        struct RawProposal: Decodable {
            let kind: String
            let title: String
            let rationale: String
            let confidence: Double?
            let payload: String?
        }
        let decoded = (try? JSONDecoder().decode([RawProposal].self, from: data)) ?? []
        return decoded.compactMap { item in
            let kind: ManifestationProposal.Kind
            switch item.kind {
            case "newSkill": kind = .newSkill
            case "skillImprovement": kind = .skillImprovement
            case "skillMerge": kind = .skillMerge
            case "skillRetire": kind = .skillRetire
            case "newMemoryCandidate": kind = .newMemoryCandidate
            case "memoryConsolidation": kind = .memoryConsolidation
            default: kind = .observation
            }
            return ManifestationProposal(
                kind: kind,
                title: item.title,
                rationale: item.rationale,
                confidence: item.confidence ?? 0.6,
                payloadJSON: item.payload ?? "{}"
            )
        }
    }
}

/// Build the goal runner's judge. Defers to the sentinel-heuristic
/// judge when no provider is available; otherwise asks the model for a
/// structured verdict.
@Sendable
private func makeJudge(metaProvider: (any SwooshCore.ModelProvider)?) -> GoalRunner.Judge {
    guard let provider = metaProvider else {
        return GoalRunner.heuristicJudge
    }
    return { goal, observation in
        let system = """
        You are the judge for one of Swoosh's persistent goals. Read the
        user's goal statement and the agent's most recent observation.
        Respond with one JSON object:
        { "verdict": "progressing" | "stuck" | "completed" | "needsUserInput",
          "rationale": string }
        Be conservative — only return "completed" when the agent has
        explicitly produced the deliverable the goal asks for.
        """
        let user = """
        Goal: \(goal.statement)

        Latest observation:
        \(observation)
        """
        let response = try await provider.complete(SwooshCore.ModelCompletionRequest(
            messages: [
                SwooshCore.ChatMessage(role: .system, content: system),
                SwooshCore.ChatMessage(role: .user, content: user),
            ],
            model: nil
        ))
        struct RawVerdict: Decodable {
            let verdict: String
            let rationale: String?
        }
        let stripped = response.content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = stripped.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(RawVerdict.self, from: data)
        else {
            return (.progressing, "judge returned unparseable response")
        }
        let verdict: GoalJudgement
        switch decoded.verdict {
        case "completed": verdict = .completed
        case "stuck": verdict = .stuck
        case "needsUserInput": verdict = .needsUserInput
        default: verdict = .progressing
        }
        return (verdict, decoded.rationale)
    }
}

// MARK: - Idle / focus probes (Mac-only signals for the scheduler)

@Sendable
private func currentIdleSeconds() async -> TimeInterval? {
    #if canImport(IOKit) && os(macOS)
    // CGEventSource gives wall-clock idle time across all event types
    // without an entitlement. Returns Double.greatestFiniteMagnitude
    // when no events have happened — clamp to nil in that case.
    let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
    if seconds.isFinite, seconds >= 0 { return seconds }
    return nil
    #else
    return nil
    #endif
}

@Sendable
private func currentFocusIdentifier() async -> String? {
    #if canImport(Intents)
    let focused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
    return focused ? "active" : nil
    #else
    return nil
    #endif
}

// MARK: - Signal handler

final class SignalHandler: @unchecked Sendable {
    let supervisor: ActantDBSupervisor
    init(supervisor: ActantDBSupervisor) { self.supervisor = supervisor }

    func install() {
        let action: @convention(c) (Int32) -> Void = { sig in
            print("[swooshd] received signal \(sig), shutting down…")
            exit(0)
        }
        signal(SIGTERM, action)
        signal(SIGINT,  action)
    }
}
