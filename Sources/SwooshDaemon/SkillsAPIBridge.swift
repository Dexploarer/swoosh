// SwooshDaemon/SkillsAPIBridge.swift — 0.9S Skill store ↔ HTTP API
//
// Maps the `SkillStoring` actor surface into the wire types the API
// serves. Detail + search + propose + approve/reject + delete CRUD,
// gated by the same trust contract the prompt builder enforces.
//
// Drafts are created with `.draft` trust so they never enter the
// agent's prompt until a user explicitly approves them — same rule
// as the memory pipeline.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshSkills

extension SwooshDaemon {
    static func skillDetailResponse(_ skill: SkillDocument) -> SkillDetailResponse {
        SkillDetailResponse(
            skill: skillSummary(skill),
            body: skill.body,
            tags: skill.tags,
            triggerPatterns: skill.triggerPatterns,
            toolsRequired: skill.toolsRequired,
            platforms: Array(skill.platforms).sorted(),
            usageCount: skill.usageCount,
            successRate: skill.successRate,
            updatedAt: skill.updatedAt
        )
    }

    static func skillDetailResponse(
        store: any SkillStoring, id: String
    ) async throws -> SkillDetailResponse {
        guard let skill = try await store.get(id: id) else {
            throw APIError.notFound("skill not found: \(id)")
        }
        return skillDetailResponse(skill)
    }

    static func searchSkillsResponse(
        store: any SkillStoring, request: SkillSearchRequest
    ) async throws -> SkillsResponse {
        let limit = request.limit ?? 25
        guard limit > 0 else {
            throw APIError.badRequest("limit must be positive")
        }
        let hits = try await store.search(query: request.query, limit: limit)
        return SkillsResponse(skills: hits.map(skillSummary))
    }

    static func proposeSkillResponse(
        store: any SkillStoring, request: SkillProposeRequest
    ) async throws -> SkillMutationResponse {
        let trimmedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw APIError.badRequest("skill title is empty")
        }
        let category = SkillCategory(rawValue: request.category ?? "") ?? .general
        let skill = SkillDocument(
            title: trimmedTitle,
            description: request.description,
            category: category,
            triggerPatterns: request.triggerPatterns ?? [],
            tags: request.tags ?? [],
            trust: .draft,
            body: request.body,
            sourceDirectory: nil,
            supportingFiles: [],
            relatedSkills: [],
            requiredToolsets: [],
            requiredTools: [],
            fallbackToolsets: [],
            fallbackTools: [],
            requiredEnvironmentVariables: [],
            configRequirements: [],
            pinned: false
        )
        try await store.save(skill)
        return SkillMutationResponse(
            skill: skillSummary(skill),
            message: "Skill draft created."
        )
    }

    static func approveSkillResponse(
        store: any SkillStoring, id: String
    ) async throws -> SkillMutationResponse {
        try await transitionSkill(store: store, id: id, to: .reviewed, message: "Skill approved.")
    }

    static func rejectSkillResponse(
        store: any SkillStoring, id: String
    ) async throws -> SkillMutationResponse {
        try await transitionSkill(store: store, id: id, to: .rejected, message: "Skill rejected.")
    }

    static func deleteSkillResponse(
        store: any SkillStoring, id: String
    ) async throws -> SkillsResponse {
        guard try await store.get(id: id) != nil else {
            throw APIError.notFound("skill not found: \(id)")
        }
        try await store.delete(id: id)
        // Return all remaining skills regardless of trust — matches GET /api/skills.
        // Filtering to promptable-only would silently hide drafts/rejected from the caller.
        let all = try await store.listAll()
        return SkillsResponse(skills: all.map(skillSummary))
    }

    // MARK: - private

    private static func transitionSkill(
        store: any SkillStoring,
        id: String,
        to newTrust: SkillTrust,
        message: String
    ) async throws -> SkillMutationResponse {
        guard var skill = try await store.get(id: id) else {
            throw APIError.notFound("skill not found: \(id)")
        }
        skill.trust = newTrust
        skill.updatedAt = Date()
        try await store.update(skill)
        return SkillMutationResponse(
            skill: skillSummary(skill),
            message: message
        )
    }
}
