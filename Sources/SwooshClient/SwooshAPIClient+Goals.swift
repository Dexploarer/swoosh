// SwooshClient/SwooshAPIClient+Goals.swift — 0.4A Tier 1 Goals endpoint methods
//
// Wire methods for `GET /api/goals`, `GET /api/goals/{id}`,
// `POST /api/goals`, `PATCH /api/goals/{id}`, and the abandon mutation.

import Foundation

extension SwooshAPIClient {
    public func goals() async throws -> GoalsResponse {
        let request = try makeRequest(method: "GET", path: "api/goals", body: nil)
        return try await execute(request, as: GoalsResponse.self)
    }

    public func goal(id: String) async throws -> GoalDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/goals/\(encodedID)", body: nil)
        return try await execute(request, as: GoalDetailResponse.self)
    }

    public func setGoal(_ body: GoalSetRequest) async throws -> GoalMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/goals", body: encoded)
        return try await execute(request, as: GoalMutationResponse.self)
    }

    public func abandonGoal(id: String) async throws -> GoalMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/goals/\(encodedID)/abandon", body: nil)
        return try await execute(request, as: GoalMutationResponse.self)
    }

    public func updateGoal(id: String, body: GoalUpdateRequest) async throws -> GoalMutationResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "PATCH", path: "api/goals/\(encodedID)", body: encoded)
        return try await execute(request, as: GoalMutationResponse.self)
    }
}
