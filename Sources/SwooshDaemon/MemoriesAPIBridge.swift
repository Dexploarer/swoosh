// SwooshDaemon/MemoriesAPIBridge.swift — Memory store ↔ HTTP API
//
// Maps the ActantAgent `MemoryStore` propose/approve/reject + the
// underlying client query into the wire types the API serves. Same
// trust pipeline as Scout: proposals land as candidates; nothing
// enters prompts until the user approves.

import Foundation
import ActantAgent
import ActantDB
import SwooshAPI
import SwooshClient

extension SwooshDaemon {

    static func memoryDetailResponse(
        backend: AgentBackend, id: String
    ) async throws -> MemoryDetailResponse {
        // Errors propagate — a backend failure must not masquerade as 404.
        for status in ["approved", "pending", "rejected"] {
            let rows = try await backend.client.memories(
                workspaceID: backend.workspaceID,
                status: status
            )
            for row in rows {
                switch row {
                case .approved(let memory) where memory.id == id:
                    return MemoryDetailResponse(memory: memorySummary(memory), evidenceJSON: nil)
                case .pending(let candidate) where candidate.id == id:
                    return MemoryDetailResponse(memory: memorySummary(candidate), evidenceJSON: nil)
                case .rejected(let candidate) where candidate.id == id:
                    return MemoryDetailResponse(memory: memorySummary(candidate), evidenceJSON: nil)
                default:
                    continue
                }
            }
        }
        throw APIError.notFound("memory not found: \(id)")
    }

    static func proposeMemoryResponse(
        backend: AgentBackend, request: MemoryProposeRequest
    ) async throws -> MemoryMutationResponse {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.badRequest("memory text is empty")
        }
        guard let sensitivity = Sensitivity(rawValue: request.sensitivity) else {
            throw APIError.badRequest("unknown sensitivity: \(request.sensitivity)")
        }
        let evidence: JSONValue = try decodeEvidence(request.evidenceJSON)
        let store = MemoryStore(backend: backend)
        let candidateID = try await store.propose(
            text: trimmed,
            category: request.category,
            sensitivity: sensitivity,
            confidence: request.confidence,
            evidence: evidence
        )
        let summary = MemorySummary(
            id: candidateID,
            text: trimmed,
            category: request.category,
            status: "pending",
            sensitivity: sensitivity.rawValue,
            confidence: request.confidence,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        return MemoryMutationResponse(memory: summary, message: "Memory candidate proposed.")
    }

    static func approveMemoryResponse(
        backend: AgentBackend, id: String
    ) async throws -> MemoryMutationResponse {
        // Pre-fetch the pending candidate so the response carries the
        // real text/category/sensitivity even if the post-approve fetch
        // hasn't propagated yet.
        let pendingSummary = try await pendingMemorySummary(backend: backend, id: id)
        let store = MemoryStore(backend: backend)
        try await store.approve(candidateID: id)
        let approved = try await store.listApproved()
        if let memory = approved.first(where: { $0.id == id }) {
            return MemoryMutationResponse(memory: memorySummary(memory), message: "Memory approved.")
        }
        // Eventual-consistency fallback: report status as approved while
        // preserving the candidate's real text/category/sensitivity.
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
        backend: AgentBackend, id: String, request: MemoryReviewRequest
    ) async throws -> MemoryMutationResponse {
        // Pre-fetch the candidate so the response carries real metadata.
        let summary = try await pendingMemorySummary(backend: backend, id: id)
        let store = MemoryStore(backend: backend)
        try await store.reject(candidateID: id, reason: request.reason)
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
        backend: AgentBackend, id: String
    ) async throws -> MemorySummary {
        let rows = try await backend.client.memories(
            workspaceID: backend.workspaceID,
            status: "pending"
        )
        for row in rows {
            if case .pending(let candidate) = row, candidate.id == id {
                return memorySummary(candidate)
            }
        }
        throw APIError.notFound("memory candidate not found: \(id)")
    }

    private static func decodeEvidence(_ raw: String?) throws -> JSONValue {
        guard let raw, !raw.isEmpty else { return .object([:]) }
        guard let data = raw.data(using: .utf8) else {
            throw APIError.badRequest("evidenceJSON is not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw APIError.badRequest("evidenceJSON is not valid JSON")
        }
    }
}
