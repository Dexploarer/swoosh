// SwooshDaemon/DaemonAutopilots.swift — 0.9S Scout autopilot + helpers
//
// Background Task that drives the passive Scout pipeline every N minutes
// when the user is idle. Pulls candidates into the in-memory memory store
// and logs proposed-candidate counts so the dashboard can surface activity.
//
// All helpers are file-private to the daemon executable. `Manifester` /
// `GoalRunner` meta-task closures live in `DaemonMetaTasks.swift`.

import Foundation
import SwooshScout
import SwooshTools

@Sendable
func makeScoutAutopilotTask(
    memoryStore: any MemoryToolStoring,
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
                    memoryStore: memoryStore,
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
    memoryStore: any MemoryToolStoring,
    signalStore: PersonalizationSignalStore
) async throws -> ScoutPipelineResult {
    let existing = try await existingMemorySummaries(memoryStore: memoryStore)
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

    // TODO: wire durable backend — scout records were previously persisted
    // to ActantDB; for now they are only used for the pipeline result stats.
    for candidate in result.candidates {
        _ = try await memoryStore.propose(ProposeMemoryCandidateInput(
            text: candidate.text,
            category: toolCategory(from: candidate.category),
            sensitivity: toolSensitivity(from: candidate.sensitivity),
            confidence: candidate.confidence,
            evidence: candidate.evidence.map(toolEvidence)
        ))
    }
    return result
}

func makePassiveScoutSources(signalStore: PersonalizationSignalStore) -> [any ScoutSource] {
    ScoutSourceCatalog.passiveLocalSources(signalStore: signalStore)
}

func existingMemorySummaries(memoryStore: any MemoryToolStoring) async throws -> [ExistingMemorySummary] {
    let approved = try await memoryStore.listApproved(category: nil, limit: nil)
    let pending = try await memoryStore.listCandidates(status: .pending, limit: nil)
    return approved.map { ExistingMemorySummary(text: $0.text, category: $0.category.rawValue) } +
        pending.map { ExistingMemorySummary(text: $0.text, category: $0.category.rawValue) }
}

/// Maps a Scout sensitivity level to the SwooshTools `Sensitivity` enum.
func toolSensitivity(from scout: SwooshScout.Sensitivity) -> SwooshTools.Sensitivity {
    switch scout {
    case .low, .medium: return .normal
    case .high:         return .sensitive
    case .critical:     return .secret
    }
}

/// Maps a Scout category string to the SwooshTools `MemoryCategory` enum.
/// Falls back to `.fact` for unknown categories.
func toolCategory(from raw: String) -> MemoryCategory {
    MemoryCategory(rawValue: raw) ?? .fact
}

/// Maps a Scout `EvidencePointer` to the SwooshTools `EvidencePointer`.
func toolEvidence(_ pointer: SwooshScout.EvidencePointer) -> SwooshTools.EvidencePointer {
    SwooshTools.EvidencePointer(
        sourceID: pointer.source,
        description: pointer.detail
    )
}
