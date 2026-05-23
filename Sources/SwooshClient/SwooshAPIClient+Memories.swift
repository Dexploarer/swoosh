// SwooshClient/SwooshAPIClient+Memories.swift — 0.4A Memories CRUD endpoint methods
//
// Wire methods for `GET /api/memories/{id}`, `POST /api/memories`, and
// the approve / reject mutations. `GET /api/memories` (list) is on the
// core client.

import Foundation

extension SwooshAPIClient {
    public func memory(id: String) async throws -> MemoryDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/memories/\(encodedID)", body: nil)
        return try await execute(request, as: MemoryDetailResponse.self)
    }

    public func proposeMemory(_ body: MemoryProposeRequest) async throws -> MemoryMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/memories", body: encoded)
        return try await execute(request, as: MemoryMutationResponse.self)
    }

    public func approveMemory(id: String) async throws -> MemoryMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/memories/\(encodedID)/approve", body: nil)
        return try await execute(request, as: MemoryMutationResponse.self)
    }

    public func rejectMemory(id: String, body: MemoryReviewRequest = MemoryReviewRequest()) async throws -> MemoryMutationResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/memories/\(encodedID)/reject", body: encoded)
        return try await execute(request, as: MemoryMutationResponse.self)
    }
}
