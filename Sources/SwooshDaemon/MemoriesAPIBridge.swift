// SwooshDaemon/MemoriesAPIBridge.swift — 0.9S Memory store ↔ HTTP API
//
// Maps the `MemoryToolStoring` propose/approve/reject into the wire
// types the API serves. Same trust pipeline as Scout: proposals land
// as candidates; nothing enters prompts until the user approves.
//
// TODO: wire durable backend — all state is currently in-memory.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshTools

extension SwooshDaemon {

    static func memoryDetailResponse(
        memoryStore: any MemoryToolStoring, id: String
    ) async throws -> MemoryDetailResponse {
        // Check approved memories first.
        let approved = try await memoryStore.listApproved(category: nil, limit: nil)
        if let memory = approved.first(where: { $0.id == id }) {
            return MemoryDetailResponse(memory: memorySummary(memory), evidenceJSON: nil)
        }
        // Then check all candidate statuses.
        for status: CandidateStatus in [.pending, .rejected, .edited] {
            let candidates = try await memoryStore.listCandidates(status: status, limit: nil)
            if let candidate = candidates.first(where: { $0.id == id }) {
                return MemoryDetailResponse(memory: memorySummary(candidate), evidenceJSON: nil)
            }
        }
        throw APIError.notFound("memory not found: \(id)")
    }

    static func proposeMemoryResponse(
        memoryStore: any MemoryToolStoring, request: MemoryProposeRequest
    ) async throws -> MemoryMutationResponse {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.badRequest("memory text is empty")
        }
        guard let sensitivity = SwooshTools.Sensitivity(rawValue: request.sensitivity) else {
            throw APIError.badRequest("unknown sensitivity: \(request.sensitivity)")
        }
        guard let category = MemoryCategory(rawValue: request.category) else {
            throw APIError.badRequest("unknown category: \(request.category)")
        }
        let evidence: [EvidencePointer] = decodeEvidencePointers(request.evidenceJSON)
        let candidateID = try await memoryStore.propose(ProposeMemoryCandidateInput(
            text: trimmed,
            category: category,
            sensitivity: sensitivity,
            confidence: request.confidence,
            evidence: evidence
        ))
        let summary = MemorySummary(
            id: candidateID,
            text: trimmed,
            category: category.rawValue,
            status: CandidateStatus.pending.rawValue,
            sensitivity: sensitivity.rawValue,
            confidence: request.confidence,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        return MemoryMutationResponse(memory: summary, message: "Memory candidate proposed.")
    }

    static func approveMemoryResponse(
        memoryStore: any MemoryToolStoring, id: String
    ) async throws -> MemoryMutationResponse {
        // Pre-fetch the pending candidate so the response carries the
        // real text/category/sensitivity even if the post-approve fetch
        // hasn't propagated yet.
        let pendingSummary = try await pendingMemorySummary(memoryStore: memoryStore, id: id)
        _ = try await memoryStore.approve(candidateID: id, finalText: nil)
        let approved = try await memoryStore.listApproved(category: nil, limit: nil)
        if let memory = approved.first(where: { $0.id == id }) {
            return MemoryMutationResponse(memory: memorySummary(memory), message: "Memory approved.")
        }
        // Fallback: report status as approved while preserving the
        // candidate's real text/category/sensitivity.
        let fallback = MemorySummary(
            id: pendingSummary.id,
            text: pendingSummary.text,
            category: pendingSummary.category,
            status: "approved",
            sensitivity: pendingSummary.sensitivity,
            confidence: pendingSummary.confidence,
            createdAt: pendingSummary.createdAt
        )
        return MemoryMutationResponse(memory: fallback, message: "Memory approved.")
    }

    static func rejectMemoryResponse(
        memoryStore: any MemoryToolStoring, id: String, request: MemoryReviewRequest
    ) async throws -> MemoryMutationResponse {
        // Pre-fetch the candidate so the response carries real metadata.
        let summary = try await pendingMemorySummary(memoryStore: memoryStore, id: id)
        try await memoryStore.reject(candidateID: id, reason: request.reason)
        let rejected = MemorySummary(
            id: summary.id,
            text: summary.text,
            category: summary.category,
            status: "rejected",
            sensitivity: summary.sensitivity,
            confidence: summary.confidence,
            createdAt: summary.createdAt
        )
        return MemoryMutationResponse(memory: rejected, message: "Memory rejected.")
    }

    // MARK: - private

    private static func pendingMemorySummary(
        memoryStore: any MemoryToolStoring, id: String
    ) async throws -> MemorySummary {
        let candidates = try await memoryStore.listCandidates(status: .pending, limit: nil)
        if let candidate = candidates.first(where: { $0.id == id }) {
            return memorySummary(candidate)
        }
        throw APIError.notFound("memory candidate not found: \(id)")
    }

    private static func decodeEvidencePointers(_ raw: String?) -> [EvidencePointer] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let pointers = try? JSONDecoder().decode([EvidencePointer].self, from: data) else {
            return []
        }
        return pointers
    }
}
