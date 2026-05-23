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
import SwooshActantBackend
import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshWallet
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
import SwooshFlow
import SwooshProcess
import SwooshProviderBridge
import SwooshProviders
import SwooshModels
import SwooshMLX
import SwooshFoundation
import SwooshMCP
import SwooshCore
import SwooshSecrets
import SwooshDaemonSupport
import SwooshPlugins
import SwooshPluginRuntime
import SwooshDemoPlugins

@main
struct SwooshDaemon {
    static func main() async throws {
        let version = "0.9P"

        let cliArgs = Array(CommandLine.arguments.dropFirst())
        if cliArgs.contains("--help") || cliArgs.contains("-h") {
            printDaemonHelp(version: version)
            return
        }
        if cliArgs.contains("--version") {
            print("swooshd \(version)")
            return
        }

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
        let searchPaths = actantDBSearchPaths()
        let supervisor = ActantDBSupervisor(
            extraSearchPaths: searchPaths,
            logOutputTo: swooshDir.appendingPathComponent("logs/actantdb.log")
        )
        let baseURL: URL
        do {
            baseURL = try await supervisor.start(
                dbPath: swooshDir.appendingPathComponent("actant.db")
            )
        } catch {
            log("FATAL: could not start ActantDB: \(error)")
            log("")
            log("swooshd needs the `actantdb` binary on PATH or in one of these search paths:")
            for path in searchPaths { log("  • \(path.path)") }
            log("")
            log("Fix one of three ways:")
            log("  1. Build it from the sibling repo:")
            log("       cd ../actantDB && cargo build           (debug, lands in ~/.cache/cargo-actantdb/debug)")
            log("       cd ../actantDB && cargo build --release (release, lands in ../actantDB/target/release)")
            log("  2. Point swooshd at an existing binary:")
            log("       SWOOSH_ACTANTDB_PATH=/path/to/actantdb swift run swooshd")
            log("  3. Install it on PATH so `which actantdb` resolves.")
            log("")
            log("See Docs/GettingStarted.md §11 for more.")
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
        let hasMetaModel: Bool
        if let mlxModel = env["SWOOSH_MLX_MODEL"], !mlxModel.trimmingCharacters(in: .whitespaces).isEmpty {
            modelProvider = MLXModelProvider(modelID: mlxModel.trimmingCharacters(in: .whitespaces))
            hasMetaModel = true
            log("Provider: MLX local (\(mlxModel)) — on-device inference.")
        } else if env["SWOOSH_FOUNDATION_MODEL"] == "1" {
            // Apple's on-device Foundation model — opt-in, no cloud key.
            modelProvider = FoundationModelProvider()
            hasMetaModel = true
            log("Provider: Apple Foundation Models — on-device inference.")
        } else if let info = providerInfo {
            let (router, _) = await ProviderFactory.buildRouter(
                secrets: secrets,
                preferredProviderID: runtimeConfig?.preferredProviderID
            )
            modelProvider = ProviderBridgeAdapter(
                router: router,
                role: .primaryChat,
                modelName: info.model,
                defaultProviderID: ProviderFactory.providerID(forDetectedProviderName: info.name)
            )
            hasMetaModel = true
            log("Provider: \(info.name) (\(info.model))")
        } else {
            modelProvider = LocalDiagnosticProvider()
            hasMetaModel = false
            log("Provider: local diagnostic (no API key configured — run `swoosh provider auth`).")
        }

        // Build a second adapter for the meta-tasks (manifester miner +
        // goal judge) so they don't compete with chat for the same model
        // routing decisions. Uses a distinct role so the user can route
        // reflective passes through a cheaper / faster provider.
        // metaProvider drives the goal judge + manifester miner. Use the
        // configured model whenever we have any real one — MLX/Foundation/
        // cloud — and only fall back to the deterministic path when the
        // diagnostic placeholder is in use.
        let metaProvider: (any SwooshCore.ModelProvider)? = hasMetaModel ? modelProvider : nil

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
        //
        // The skill store is created here — ahead of the other
        // self-improvement stores — so the kernel can inject the Level-0
        // skill catalog (id, title, description per promotable skill) into
        // every system prompt.
        let skillStore = FileSkillStore(
            directory: swooshDir.appendingPathComponent("skills", isDirectory: true)
        )
        let swoosh: Swoosh
        do {
            swoosh = try await Swoosh.configure { config in
                config.modelProvider = modelProvider
                config.toolRegistry = toolRuntime.registry
                config.toolPolicy = toolPolicy
                config.skillCatalogProvider = {
                    let all = (try? await skillStore.listAll()) ?? []
                    return all
                        .filter { SkillTrust.promptable.contains($0.trust) }
                        .map { (id: $0.id, title: $0.title, description: $0.description) }
                }
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
        // Real audit source: the manifester mines the durable tool-audit
        // log instead of the empty default, so scheduled passes see real
        // activity rather than short-circuiting to `.skipped`.
        let manifester = Manifester(
            store: manifestStore,
            auditSource: AuditLogManifestationSource(audit: toolRuntime.dependencies.audit),
            miner: miner
        )
        let manifestPolicy = ManifestationPolicy()
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: manifestStore,
            policy: manifestPolicy
        )
        log("Manifester ready (\(metaProvider == nil ? "deterministic" : "model-backed") miner; scheduler armed).")

        let cronStore = FileCronJobStore(root: swooshDir.appendingPathComponent("cron", isDirectory: true))
        let cronScheduler = CronScheduler(store: cronStore, processRunner: CronProcessRunner())

        // ── MCP servers (loaded from ~/.swoosh/mcp/servers.json) ──
        // The registry stays empty when the file is absent; the CLI is
        // responsible for adding servers and the user is responsible for
        // enabling them. Loaded profiles default to `.untrusted` per
        // MCPServerProfile.init so even after enabling, mcp.call's
        // static `.high` risk + askEveryTime approval still gates each
        // invocation through the firewall.
        let mcpRegistry = MCPServerRegistry()
        let mcpServersFile = swooshDir.appendingPathComponent("mcp/servers.json")
        if FileManager.default.fileExists(atPath: mcpServersFile.path) {
            do {
                let data = try Data(contentsOf: mcpServersFile)
                let profiles = try JSONDecoder().decode([MCPServerProfile].self, from: data)
                for profile in profiles {
                    try await mcpRegistry.addServer(profile)
                }
                log("MCP: loaded \(profiles.count) server profile(s) from \(mcpServersFile.path).")
            } catch {
                log("MCP: failed to load \(mcpServersFile.path): \(error.localizedDescription). Continuing with no MCP servers.")
            }
        } else {
            log("MCP: no servers configured (\(mcpServersFile.path) absent).")
        }
        // Reuse the same secret-ref grammar the crypto tools use:
        // `"namespace.key"` or `"key"` (with `"mcp"` as the default
        // namespace). MCP server profiles only reference Keychain refs,
        // never raw secret values.
        let mcpSecretResolver = KeychainSecretResolver(store: secrets, defaultNamespace: "mcp")
        let mcpConnector = MCPConnector(secretResolver: { @Sendable ref in
            try? await mcpSecretResolver.resolve(ref: ref)
        })
        let mcpDeps = MCPDependencies(registry: mcpRegistry, connector: mcpConnector)

        await DefaultToolRegistrar.registerAll(
            into: toolRuntime.registry,
            dependencies: toolRuntime.dependencies,
            selfImprovement: SelfImprovementDependencies(
                skills: SkillToolDependencies(store: skillStore),
                goals: GoalToolDependencies(store: goalStore),
                manifest: ManifestToolDependencies(store: manifestStore, manifester: manifester),
                cron: CronToolDependencies(store: cronStore, scheduler: cronScheduler)
            ),
            mcp: mcpDeps
        )

        // ── Plugin host ─────────────────────────────────────────────
        // Plugins are user-installed extensions to the agent — Swift,
        // executable, or wasm. Phase 1 ships the spine + the Swift kind;
        // executable + wasm come in follow-on phases. Manifests live under
        // ~/.swoosh/plugins/<id>/manifest.json; plugin tool calls go
        // through the ordinary ToolRegistry/firewall/audit pipeline. The
        // host grants requested permissions to the firewall when the user
        // enables a plugin (humanOnly admin) and revokes them on disable
        // unless another enabled plugin still needs them.
        let pluginStore = FilePluginStore(
            root: swooshDir.appendingPathComponent("plugins", isDirectory: true)
        )
        let bundledPluginLoader = BundledPluginLoader(
            store: pluginStore,
            directory: BundledPluginLoader.defaultDirectory()
        )
        if let outcome = try? await bundledPluginLoader.loadAll() {
            if !outcome.installed.isEmpty {
                log("Plugins: bundled installed \(outcome.installed.joined(separator: ", ")).")
            }
            if !outcome.failed.isEmpty {
                log("Plugins: failed to read bundled \(outcome.failed.joined(separator: ", ")).")
            }
        }
        let pluginRegistry = PluginRegistry(audit: toolRuntime.audit)
        let swiftPlugins = SwiftPluginRegistry()
        // Register every Swift plugin entrypoint linked into the daemon.
        // Adding a new SwiftPluginEntrypoint = one extra `register(_:)` here.
        await swiftPlugins.register(HelloSwiftPlugin())
        let pluginsRoot = swooshDir.appendingPathComponent("plugins", isDirectory: true)
        let pluginHost = PluginHost(
            store: pluginStore,
            registry: pluginRegistry,
            toolRegistry: toolRuntime.registry,
            firewall: toolRuntime.firewall,
            executors: [
                SwiftPluginExecutor(registry: swiftPlugins),
                ExecutablePluginExecutor(pluginsRoot: pluginsRoot),
                WasmPluginExecutor(pluginsRoot: pluginsRoot),
                MCPBridgePluginExecutor(registry: mcpRegistry, connector: mcpConnector),
            ],
            baselineGrants: toolRuntime.baselineGrants,
            pluginsRoot: pluginsRoot
        )
        do {
            try await pluginHost.bootstrap()
            let installed = await pluginHost.listAll()
            let enabled = installed.filter(\.enabled)
            log("Plugins: \(installed.count) installed, \(enabled.count) re-enabled from \(swooshDir.appendingPathComponent("plugins").path).")
        } catch {
            log("Plugins: bootstrap failed: \(error.localizedDescription). Continuing without plugin tools.")
        }
        // Keep `swiftPlugins` and `pluginHost` alive for the daemon's
        // lifetime so plugin tools registered in ToolRegistry remain
        // dispatchable. Actor references suffice — no explicit storage
        // needed since the closures captured by the registry retain them.
        _ = swiftPlugins
        _ = pluginHost

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
        // ── Goal autopilot ──────────────────────────────────────────
        // Advances pending / active goals to a terminal state via the
        // GoalRunner. Without this, `goal_set` creates goals no loop ever
        // pursues. Opt out with SWOOSH_GOAL_AUTOPILOT_DISABLED=1.
        let goalAutopilotTask: Task<Void, Never>
        if env["SWOOSH_GOAL_AUTOPILOT_DISABLED"] == "1" {
            goalAutopilotTask = Task {}
            log("Goal autopilot disabled (SWOOSH_GOAL_AUTOPILOT_DISABLED=1).")
        } else {
            let interval = UInt64(max(60, Int(env["SWOOSH_GOAL_AUTOPILOT_INTERVAL_SECONDS"] ?? "300") ?? 300))
            goalAutopilotTask = Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                while !Task.isCancelled {
                    let goals = (try? await goalStore.listAll()) ?? []
                    for goal in goals where goal.state == .pending || goal.state == .active {
                        do {
                            let final = try await goalRunner.run(goalID: goal.id)
                            SwooshDaemon.log("Goal \(goal.id) advanced to \(final.state.rawValue).")
                        } catch {
                            SwooshDaemon.log("Goal runner error for \(goal.id): \(error.localizedDescription)")
                        }
                    }
                    try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                }
            }
            log("Goal autopilot started (advances pending/active goals).")
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
            goalAutopilotTask: goalAutopilotTask,
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
        let codexAuth = CodexAuthManager(workingDirectory: swooshDir)
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
                    try await SwooshDaemon.memoryDetailResponse(backend: agentBackend, id: id)
                },
                proposeMemory: { request in
                    try await SwooshDaemon.proposeMemoryResponse(backend: agentBackend, request: request)
                },
                approveMemory: { id in
                    try await SwooshDaemon.approveMemoryResponse(backend: agentBackend, id: id)
                },
                rejectMemory: { id, request in
                    try await SwooshDaemon.rejectMemoryResponse(backend: agentBackend, id: id, request: request)
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

    static func printDaemonHelp(version: String) {
        print("""
        swooshd \(version) — Swoosh local daemon

        Runs the Swoosh agent kernel, spawns ActantDB, and serves the
        bearer-gated HTTP API that the Swoosh CLI and iPhone app talk to.

        USAGE:
            swooshd [--help] [--version]

        swooshd takes no subcommands — it runs until stopped with Ctrl-C.
        Configuration is by environment variable:

            SWOOSH_HOST          Bind address (default 127.0.0.1; 0.0.0.0 for LAN)
            SWOOSH_PORT          TCP port (default 8787)
            SWOOSH_API_TOKEN     Bearer token (default: persisted/generated)
            SWOOSH_CONFIG_DIR    State directory (default ~/.swoosh)
            SWOOSH_ACTANTDB_PATH Explicit path to the actantdb binary

        The resolved API token is written to ~/.swoosh/api_token — paste it
        into the Swoosh iOS app to pair an iPhone.
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
        let elizaCloudConfigured = (try? await secrets.exists(SecretRef("eliza-cloud", "api_key"))) ?? false
        let codexConfigured = await CodexBridgeProvider().isAuthenticated()
        let localServers = await LocalProviderDiscovery().discover()
        let localModel = localServers.first?.models.first

        let env = ProcessInfo.processInfo.environment
        let mlxModelEnv = env["SWOOSH_MLX_MODEL"]?.trimmingCharacters(in: .whitespaces)
        let mlxModel = (mlxModelEnv?.isEmpty == false) ? mlxModelEnv : ModelDefaults.localMLXModelID
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
                model: codexConfigured ? ModelDefaults.codexModelID : nil,
                configured: codexConfigured,
                active: activeID == "codex",
                status: codexConfigured ? "signed_in" : "needs_signin"
            ),
            ProviderSummary(
                id: ModelDefaults.openAIProviderID,
                name: "OpenAI API",
                model: ModelDefaults.openAIModelID,
                configured: openAIConfigured,
                active: activeID == "openai",
                status: openAIConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: ModelDefaults.openRouterProviderID,
                name: "OpenRouter",
                model: ModelDefaults.openRouterModelID,
                configured: openRouterConfigured,
                active: activeID == "openrouter",
                status: openRouterConfigured ? "configured" : "missing_key"
            ),
            ProviderSummary(
                id: ModelDefaults.elizaCloudProviderID,
                name: "Eliza Cloud",
                model: ModelDefaults.elizaCloudModelID,
                configured: elizaCloudConfigured,
                active: activeID == ModelDefaults.elizaCloudProviderID,
                status: elizaCloudConfigured ? "configured" : "missing_key"
            ),
        ]

        if foundationEnabled {
            providers.append(ProviderSummary(
                id: ModelDefaults.localFoundationProviderID,
                name: "Apple Foundation Models",
                model: ModelDefaults.localFoundationModelID,
                configured: true,
                active: activeID == ModelDefaults.localFoundationProviderID,
                status: "running"
            ))
        }
        if mlxConfigured {
            providers.append(ProviderSummary(
                id: ModelDefaults.localMLXProviderID,
                name: "MLX Local",
                model: mlxModel,
                configured: true,
                active: activeID == ModelDefaults.localMLXProviderID,
                status: (activeID == ModelDefaults.localMLXProviderID) ? "running" : "available"
            ))
        }
        providers.append(ProviderSummary(
            id: ModelDefaults.localOpenAIProviderID,
            name: localServers.first?.name ?? "Ollama / Local OpenAI",
            model: localModel,
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
        let known = [
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

// MARK: - Tool runtime

private struct DaemonToolRuntime: Sendable {
    let registry: ToolRegistry
    let dependencies: ToolDependencies
    let firewall: SwooshFirewallActor
    let audit: any AuditLogging
    let baselineGrants: Set<SwooshPermission>
    let walletStore: WalletStore
}

private func makeDaemonToolRuntime(
    swooshDir: URL,
    backend: AgentBackend,
    grantedPermissions: Set<SwooshPermission>,
    safetyConfig: SwooshSafetyConfig
) async throws -> DaemonToolRuntime {
    // Durable tool audit + approvals — both ride the ActantDB ledger so the
    // audit trail and the pending-approval queue survive daemon restarts.
    let audit: any AuditLogging = ActantAuditLog(backend: backend)
    let firewall = SwooshFirewallActor(granted: grantedPermissions)
    let approvalCenter = SwooshApprovals.ApprovalCenter(
        store: ActantApprovalStore(backend: backend), audit: audit)
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
    // Secret resolver — backs RPC-endpoint refs and the Hyperliquid
    // trade tools' Keychain-stored private keys. Tools never receive
    // the raw secret value through their input types.
    let secretResolver = KeychainSecretResolver(store: KeychainSecretStore())
    // Concrete JSON-RPC clients. The endpoint URL is resolved per call
    // from the chain/cluster (Keychain ref → env override → public
    // fallback); these clients are read/broadcast only — no private keys.
    let evmClient = URLSessionEVMRPCClient(secrets: secretResolver)
    let solanaClient = URLSessionSolanaRPCClient(secrets: secretResolver)
    let walletStore = WalletStore()
    let walletBridge = LocalWalletBridge(store: walletStore)
    let dependencies = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: safetyConfig,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(approvedRoots: [cwd.path, swooshDir.path]),
        evmClient: evmClient,
        solanaClient: solanaClient,
        walletBridge: walletBridge,
        memoryStore: MemoryStore(backend: backend),
        scoutStore: FileScoutToolStore(url: swooshDir.appendingPathComponent("scout/tool-state.json")),
        workflowStore: FileWorkflowToolStore(url: swooshDir.appendingPathComponent("workflows/tool-drafts.json")),
        workflowStepExecutor: TracingWorkflowStepExecutor(
            inner: RegistryWorkflowStepExecutor(registry: registry),
            recorder: InMemoryWorkflowTraceRecorder(),
            workflowID: "daemon"
        ),
        secrets: secretResolver
    )
    return DaemonToolRuntime(
        registry: registry,
        dependencies: dependencies,
        firewall: firewall,
        audit: audit,
        baselineGrants: grantedPermissions,
        walletStore: walletStore
    )
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
