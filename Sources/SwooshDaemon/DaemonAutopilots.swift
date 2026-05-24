// SwooshDaemon/DaemonAutopilots.swift — 0.9S Scout autopilot + helpers
//
// Background Task that drives the passive Scout pipeline every N minutes
// when the user is idle. Pulls candidates into the durable memory store
// via ActantDB and logs proposed-candidate counts so the dashboard can
// surface activity.
//
// All helpers are file-private to the daemon executable. `Manifester` /
// `GoalRunner` meta-task closures live in `DaemonMetaTasks.swift`.

import Foundation
import ActantAgent
import ActantDB
import SwooshScout

@Sendable
func makeScoutAutopilotTask(
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

func runPassiveScoutOnce(
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

func makePassiveScoutSources(signalStore: PersonalizationSignalStore) -> [any ScoutSource] {
    ScoutSourceCatalog.passiveLocalSources(signalStore: signalStore)
}

func existingMemorySummaries(memory: MemoryStore) async throws -> [ExistingMemorySummary] {
    let approved = try await memory.listApproved()
    let pending = try await memory.listPending()
    return approved.map { ExistingMemorySummary(text: $0.text, category: $0.category) } +
        pending.map { ExistingMemorySummary(text: $0.text, category: $0.category) }
}

func actantSensitivity(from raw: String) -> ActantDB.Sensitivity {
    switch raw {
    case "low": .low
    case "medium": .medium
    default: .high
    }
}

func jsonValue(_ metadata: [String: String]) -> ActantDB.JSONValue {
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

func candidateEvidenceJSON<Evidence: Encodable>(
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
