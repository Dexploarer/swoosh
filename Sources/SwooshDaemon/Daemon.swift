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
import SwooshKit
import SwooshScout
import SwooshSkills
import SwooshGoals
import SwooshManifesting
import SwooshCron
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
        let swooshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
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
        log("API token: \(token)")
        log("Pair an iPhone by entering this token into the Swoosh iOS app.")

        // ── Provider router (real inference when keys are present) ───
        // Matches the CLI's wiring: detect any configured provider via
        // ProviderFactory; if one exists, build the router + bridge and
        // plug it into Swoosh.configure. Falls back to LocalDiagnosticProvider
        // when no keys are configured so chat keeps returning *some*
        // response while the user finishes provisioning.
        let secrets = KeychainSecretStore()
        let providerInfo = await ProviderFactory.detectActiveProvider(secrets: secrets)
        let modelProvider: any SwooshCore.ModelProvider
        if let info = providerInfo {
            let (router, _) = await ProviderFactory.buildRouter(secrets: secrets)
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

        // ── Real kernel ──────────────────────────────────────────────
        // ACTANT_BASE_URL is set; SwooshKit.configure picks it up and wires
        // the kernel through SwooshActantBackend so the iPhone's chat turns
        // ride the same ledger as the Mac's.
        let swoosh: Swoosh
        do {
            swoosh = try await Swoosh.configure { config in
                config.modelProvider = modelProvider
            }
        } catch {
            log("FATAL: failed to build agent kernel: \(error)")
            exit(1)
        }
        log("Agent kernel ready")

        // ── Self-improvement pillars ────────────────────────────────
        // Stores live entirely in process today. When the actantDB iOS
        // SDK lands, the conformances wire through SwooshActantBackend
        // and these become CloudKit-synced alongside memories.
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

        let goalStore = InMemoryGoalStore()
        let manifestStore = InMemoryManifestationStore()

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
                let response = try await swoosh.kernel.run(request)
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

        let cronStore = FileCronJobStore(root: swooshDir.appendingPathComponent("cron", isDirectory: true))
        let cronScheduler = CronScheduler(store: cronStore, processRunner: CronProcessRunner())
        let cronExecutor: CronAgentExecutor = { request in
            let response = try await swoosh.kernel.run(AgentRequest(sessionID: request.sessionID, input: request.prompt))
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
            activeProvider: providerInfo
        )
        let skillSummaries = loadedSkills.map {
            SkillSummary(
                id: $0.id,
                title: $0.title,
                description: $0.description,
                category: $0.category.rawValue,
                trust: $0.trust.rawValue
            )
        }
        let server = SwooshAPIServer(
            port: port,
            hostname: host,
            token: token,
            kernel: swoosh.kernel,
            snapshot: SwooshAPISnapshot(
                providers: providerSummaries.providers,
                activeProviderID: providerSummaries.activeProviderID,
                skills: skillSummaries
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

    static func makeProviderSummaries(
        secrets: KeychainSecretStore,
        activeProvider: (name: String, model: String)?
    ) async -> (providers: [ProviderSummary], activeProviderID: String?) {
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

        return (providers, activeID)
    }
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
    [
        DeviceSource(),
        InstalledAppsSource(),
        RunningAppsSource(),
        PersonalizationSignalSource(store: signalStore),
        AppUsageSource(),
        FocusModeSource(),
        CalendarSource(),
        RemindersSource(),
        RecentDocumentsSource(),
        HealthSleepSource(),
        MusicHistorySource(),
        ScreenTimeSource(),
    ]
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

private func candidateEvidenceJSON(
    evidence: [EvidencePointer],
    ttl: TimeInterval?
) -> ActantDB.JSONValue {
    struct Payload: Encodable {
        let evidence: [EvidencePointer]
        let recommendedTTL: TimeInterval?
    }
    let payload = Payload(evidence: evidence, recommendedTTL: ttl)
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
