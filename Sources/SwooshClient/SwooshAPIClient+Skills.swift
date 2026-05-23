// SwooshClient/SwooshAPIClient+Skills.swift — 0.4A Skills CRUD endpoint methods
//
// Wire methods for `GET /api/skills/{id}`, `POST /api/skills/search`,
// `POST /api/skills`, plus the approve / reject / delete mutations.
// `GET /api/skills` (list) lives in the core client because it predates
// the tier-1 push.

import Foundation

extension SwooshAPIClient {
    public func skill(id: String) async throws -> SkillDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/skills/\(encodedID)", body: nil)
        return try await execute(request, as: SkillDetailResponse.self)
    }

    public func searchSkills(_ body: SkillSearchRequest) async throws -> SkillsResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/skills/search", body: encoded)
        return try await execute(request, as: SkillsResponse.self)
    }

    public func proposeSkill(_ body: SkillProposeRequest) async throws -> SkillMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/skills", body: encoded)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func approveSkill(id: String) async throws -> SkillMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/skills/\(encodedID)/approve", body: nil)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func rejectSkill(id: String) async throws -> SkillMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/skills/\(encodedID)/reject", body: nil)
        return try await execute(request, as: SkillMutationResponse.self)
    }

    public func deleteSkill(id: String) async throws -> SkillsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/skills/\(encodedID)", body: nil)
        return try await execute(request, as: SkillsResponse.self)
    }
}
