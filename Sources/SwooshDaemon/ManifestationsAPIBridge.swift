// SwooshDaemon/ManifestationsAPIBridge.swift — 0.9S Manifester ↔ HTTP API
//
// Maps `ManifestationStoring` + `Manifester` into the wire types the
// API serves. Kept out of Daemon.swift so the long startup function
// stays readable. Follows the same pattern as PluginAPIBridge.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshManifesting

extension SwooshDaemon {
    static func manifestationRecordSummary(_ m: Manifestation) -> ManifestationRecordSummary {
        ManifestationRecordSummary(
            id: m.id,
            status: m.status.rawValue,
            triggerReason: m.triggerReason,
            proposalCount: m.proposals.count,
            summary: m.summary,
            startedAt: m.startedAt
        )
    }

    static func manifestationPhaseSummary(_ phase: ManifestationPhase) -> ManifestationPhaseSummary {
        ManifestationPhaseSummary(
            id: phase.id,
            name: phase.name.rawValue,
            startedAt: phase.startedAt,
            finishedAt: phase.finishedAt,
            observation: phase.observation
        )
    }

    static func manifestationProposalSummary(_ p: ManifestationProposal) -> ManifestationProposalSummary {
        ManifestationProposalSummary(
            id: p.id,
            kind: p.kind.rawValue,
            title: p.title,
            rationale: p.rationale,
            confidence: p.confidence,
            payloadJSON: p.payloadJSON,
            createdAt: p.createdAt
        )
    }

    static func manifestationDetail(_ m: Manifestation) -> ManifestationDetailResponse {
        ManifestationDetailResponse(
            manifestation: manifestationRecordSummary(m),
            phases: m.phases.map(manifestationPhaseSummary),
            proposals: m.proposals.map(manifestationProposalSummary),
            auditWindowStart: m.auditWindowStart,
            auditWindowEnd: m.auditWindowEnd,
            finishedAt: m.finishedAt
        )
    }

    static func manifestationsResponse(
        store: any ManifestationStoring, limit: Int = 50
    ) async -> ManifestationsResponse {
        let recent = (try? await store.listRecent(limit: limit)) ?? []
        return ManifestationsResponse(manifestations: recent.map(manifestationRecordSummary))
    }

    static func manifestationDetailResponse(
        store: any ManifestationStoring, id: String
    ) async throws -> ManifestationDetailResponse {
        guard let m = try await store.get(id: id) else {
            throw APIError.notFound("manifestation not found: \(id)")
        }
        return manifestationDetail(m)
    }

    static func runManifestationResponse(
        manifester: Manifester, request: ManifestationRunRequest
    ) async throws -> ManifestationDetailResponse {
        let trigger = request.triggerReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (trigger?.isEmpty == false) ? trigger! : "manual"
        let m = try await manifester.runOnce(triggerReason: reason)
        return manifestationDetail(m)
    }

    static func deleteManifestationResponse(
        store: any ManifestationStoring, id: String
    ) async throws -> ManifestationsResponse {
        guard try await store.get(id: id) != nil else {
            throw APIError.notFound("manifestation not found: \(id)")
        }
        try await store.delete(id: id)
        return await manifestationsResponse(store: store)
    }
}
