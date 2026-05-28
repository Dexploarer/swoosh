// SwooshDaemon/Daemon.swift — swooshd background service
//
// Lifecycle:
//   1. Resolve a bearer API token (env var → on-disk cache → freshly minted).
//   2. Build a Swoosh agent via SwooshKit.configure { } so chat requests
//      hit the same kernel path as the SDK.
//   3. Start the Hummingbird API server with token + kernel bound in.
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
#if canImport(SwooshMLX)
import SwooshMLX
#endif
import SwooshFoundation
import SwooshMCP
import SwooshCore
import SwooshSecrets
import SwooshDaemonSupport
import SwooshPlugins
import SwooshPluginRuntime
import SwooshDemoPlugins
import SwooshStorage

@main
struct SwooshDaemon {
    static func main() async throws {
        let version = "0.9S"

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

        let signalHandler = SignalHandler()
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

        // Try MLX first (only available when SwooshMLX is linked — i.e. Xcode builds).
        var resolvedProvider: (any SwooshCore.ModelProvider)? = nil
        #if canImport(SwooshMLX)
        if let mlxModel = env["SWOOSH_MLX_MODEL"], !mlxModel.trimmingCharacters(in: .whitespaces).isEmpty {
            let hasMetallib = Bundle.allBundles.contains { bundle in
                bundle.url(forResource: "default", withExtension: "metallib") != nil
            }
            if hasMetallib {
                resolvedProvider = MLXModelProvider(modelID: mlxModel.trimmingCharacters(in: .whitespaces))
                log("Provider: MLX local (\(mlxModel)) — on-device inference.")
            } else {
                log("WARNING: MLX local requested via SWOOSH_MLX_MODEL but default.metallib is not bundled. Skipping MLX.")
            }
        }
        #endif

        if resolvedProvider == nil, env["SWOOSH_FOUNDATION_MODEL"] == "1" {
            resolvedProvider = FoundationModelProvider()
            log("Provider: Apple Foundation Models — on-device inference.")
        }

        if resolvedProvider == nil, let info = providerInfo {
            let (router, _) = await ProviderFactory.buildRouter(
                secrets: secrets,
                preferredProviderID: runtimeConfig?.preferredProviderID
            )
            resolvedProvider = ProviderBridgeAdapter(
                router: router,
                role: .primaryChat,
                modelName: info.model,
                defaultProviderID: ProviderFactory.providerID(forDetectedProviderName: info.name)
            )
            log("Provider: \(info.name) (\(info.model))")
        }

        if let resolved = resolvedProvider {
            modelProvider = resolved
            hasMetaModel = true
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

        // ── Durable SQLite backend ───────────────────────────────────
        let database: SwooshDatabase?
        do {
            database = try SwooshDatabase(
                path: swooshDir.appendingPathComponent("swoosh.db").path
            )
            log("SQLite backend ready at \(swooshDir.appendingPathComponent("swoosh.db").path)")
        } catch {
            log("WARNING: SQLite backend failed to open (\(error)); falling back to in-memory stores.")
            database = nil
        }

        let toolRuntime = try await makeDaemonToolRuntime(
            swooshDir: swooshDir,
            grantedPermissions: permissionPreset.grantedSwooshPermissions,
            safetyConfig: safetyConfig,
            database: database
        )

        // ── Real kernel ──────────────────────────────────────────────
        // SwooshKit.configure builds the kernel.
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
        // Local durable stores for self-improvement state. JSON-file
        // backed so goals and manifestation passes survive daemon restarts.
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

        // ── Receipt anchor cron (on-chain Merkle-root batching) ──────
        if let engine = toolRuntime.anchorEngine {
            Task.detached {
                let interval = 300 // 5 minutes
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    do {
                        if let batch = try await engine.createBatch() {
                            let rootPreview = String(batch.merkleRoot.prefix(16))
                            log("Anchor batch \(batch.id): \(batch.entryCount) entries, root=\(rootPreview)…")
                        }
                    } catch {
                        log("Anchor batch error: \(error)")
                    }
                }
            }
            log("Receipt anchor cron armed (300s interval).")
        }

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

        let mediaGenDeps = MediaGenWiring.build(
            firewall: toolRuntime.firewall,
            auditLog: toolRuntime.audit
        )

        await DefaultToolRegistrar.registerAll(
            into: toolRuntime.registry,
            dependencies: toolRuntime.dependencies,
            selfImprovement: SelfImprovementDependencies(
                skills: SkillToolDependencies(store: skillStore),
                goals: GoalToolDependencies(store: goalStore),
                manifest: ManifestToolDependencies(store: manifestStore, manifester: manifester),
                cron: CronToolDependencies(store: cronStore, scheduler: cronScheduler)
            ),
            mcp: mcpDeps,
            mediaGen: mediaGenDeps,
            nitrogen: NitroGenController()
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
            memoryStore: toolRuntime.dependencies.memoryStore,
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
            runtimeSources: SwooshDaemon.makeRuntimeSources(
                configStore: configStore, secrets: secrets, providerInfo: providerInfo,
                toolRuntime: toolRuntime, codexAuth: codexAuth, pluginHost: pluginHost,
                pluginRegistry: pluginRegistry, mcpRegistry: mcpRegistry, skillStore: skillStore,
                goalStore: goalStore, manifestStore: manifestStore, cronStore: cronStore,
                cronScheduler: cronScheduler, cronExecutor: cronExecutor, manifester: manifester,
                swooshDir: swooshDir
            )
        )
        let app = server.build()

        defer {
            Task {
                await runtime.stop()
            }
        }
        try await app.run()
    }

}
