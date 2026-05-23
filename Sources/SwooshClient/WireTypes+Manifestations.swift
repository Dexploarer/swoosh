// SwooshClient/WireTypes+Manifestations.swift — 0.4A Tier 1 Manifestations wire types
//
// Wire format for `GET /api/manifestations`, `GET /api/manifestations/{id}`,
// and the `POST /api/manifestations/run` trigger. Proposals are surfaced
// as `payloadJSON` strings so the client never has to know the
// per-proposal schema.

import Foundation

public struct ManifestationPhaseSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let observation: String?

    public init(
        id: String,
        name: String,
        startedAt: Date,
        finishedAt: Date?,
        observation: String?
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.observation = observation
    }
}

public struct ManifestationProposalSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let rationale: String
    public let confidence: Double
    public let payloadJSON: String
    public let createdAt: Date

    public init(
        id: String,
        kind: String,
        title: String,
        rationale: String,
        confidence: Double,
        payloadJSON: String,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.confidence = confidence
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public struct ManifestationDetailResponse: Codable, Sendable, Equatable {
    public let manifestation: ManifestationRecordSummary
    public let phases: [ManifestationPhaseSummary]
    public let proposals: [ManifestationProposalSummary]
    public let auditWindowStart: Date?
    public let auditWindowEnd: Date?
    public let finishedAt: Date?

    public init(
        manifestation: ManifestationRecordSummary,
        phases: [ManifestationPhaseSummary],
        proposals: [ManifestationProposalSummary],
        auditWindowStart: Date?,
        auditWindowEnd: Date?,
        finishedAt: Date?
    ) {
        self.manifestation = manifestation
        self.phases = phases
        self.proposals = proposals
        self.auditWindowStart = auditWindowStart
        self.auditWindowEnd = auditWindowEnd
        self.finishedAt = finishedAt
    }
}

public struct ManifestationsResponse: Codable, Sendable, Equatable {
    public let manifestations: [ManifestationRecordSummary]

    public init(manifestations: [ManifestationRecordSummary]) {
        self.manifestations = manifestations
    }
}

public struct ManifestationRunRequest: Codable, Sendable, Equatable {
    public let triggerReason: String?

    public init(triggerReason: String? = nil) {
        self.triggerReason = triggerReason
    }
}
