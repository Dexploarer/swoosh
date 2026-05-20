// SwooshManifesting/Manifestation.swift — Swoosh's name for "dreaming"
//
// A Manifestation is one pass of the background self-improvement loop.
// It reads recent audit events, mines for patterns, drafts skill /
// memory candidates, and writes a report. Every pass is durable: the
// `Manifestation` record is the audit trail of what the agent thought
// about while the user was away.
//
// The pillar's name is intentional. "Dreaming" implies the agent is
// hallucinating private state; "manifesting" makes the actual semantic
// load-bearing — the loop turns observed patterns into proposed
// concrete artifacts (skill drafts, memory candidates) that surface in
// the user's review inbox. Nothing the manifester produces takes effect
// until the user approves it, mirroring the Scout → MemoryStore flow
// that's already part of the trust contract.

import Foundation

/// Lifecycle state for a manifestation pass.
public enum ManifestationStatus: String, Codable, Sendable, CaseIterable {
    case running
    case completed
    case failed
    case skipped       // Skipped because no new audit events since last run.
}

/// A single phase within a manifestation. Phases run sequentially and
/// each records its own start/end so failures and slow phases are
/// pin-pointable in the audit log.
public struct ManifestationPhase: Codable, Sendable, Identifiable {
    public let id: String
    public let name: PhaseName
    public let startedAt: Date
    public var finishedAt: Date?
    public var observation: String?     // Free-form note from the phase

    public enum PhaseName: String, Codable, Sendable, CaseIterable {
        case gather       // Pull audit events since last manifestation
        case mine         // Detect candidate patterns (skills, memories, observations)
        case propose      // Emit drafts (writes to skill / memory stores)
        case consolidate  // Find duplicates / suggested merges
        case summarize    // Write the human-readable summary
    }

    public init(name: PhaseName, startedAt: Date = Date()) {
        self.id = UUID().uuidString
        self.name = name
        self.startedAt = startedAt
    }
}

/// One proposal produced by a manifestation pass. Lives in the report
/// for audit; the corresponding draft also lands in the appropriate
/// store (skill draft → SwooshSkills, memory candidate → MemoryStore).
public struct ManifestationProposal: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: Kind
    public let title: String
    public let rationale: String     // Why the manifester thought this was worth proposing
    public let confidence: Double    // 0.0 ... 1.0
    public let payloadJSON: String   // Encoded body of the proposal (skill draft, etc.)
    public let createdAt: Date

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case newSkill
        case skillImprovement
        case skillMerge
        case skillRetire
        case newMemoryCandidate
        case memoryConsolidation
        case observation         // A "huh, interesting" note that isn't itself an action
    }

    public init(
        kind: Kind,
        title: String,
        rationale: String,
        confidence: Double,
        payloadJSON: String,
        createdAt: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.confidence = confidence
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

/// One pass of the manifesting loop, durably persisted.
public struct Manifestation: Codable, Sendable, Identifiable {
    public let id: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: ManifestationStatus
    public var phases: [ManifestationPhase]
    public var proposals: [ManifestationProposal]
    public var summary: String?          // Human-readable digest
    public var triggerReason: String     // "scheduled-daily", "manual", "idle-trigger", etc.
    public var auditWindowStart: Date?   // First event consumed this pass
    public var auditWindowEnd: Date?     // Last event consumed this pass

    public init(
        triggerReason: String,
        startedAt: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.startedAt = startedAt
        self.status = .running
        self.phases = []
        self.proposals = []
        self.triggerReason = triggerReason
    }
}
