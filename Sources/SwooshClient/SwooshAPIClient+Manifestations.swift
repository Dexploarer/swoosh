// SwooshClient/SwooshAPIClient+Manifestations.swift — 0.4A Manifestation endpoints
//
// Wire methods for `GET /api/manifestations`, `GET /api/manifestations/{id}`,
// `POST /api/manifestations/run`, and the delete mutation.

import Foundation

extension SwooshAPIClient {
    public func manifestations() async throws -> ManifestationsResponse {
        let request = try makeRequest(method: "GET", path: "api/manifestations", body: nil)
        return try await execute(request, as: ManifestationsResponse.self)
    }

    public func manifestation(id: String) async throws -> ManifestationDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/manifestations/\(encodedID)", body: nil)
        return try await execute(request, as: ManifestationDetailResponse.self)
    }

    public func runManifestation(_ body: ManifestationRunRequest = ManifestationRunRequest()) async throws -> ManifestationDetailResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/manifestations/run", body: encoded)
        return try await execute(request, as: ManifestationDetailResponse.self)
    }

    public func deleteManifestation(id: String) async throws -> ManifestationsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/manifestations/\(encodedID)", body: nil)
        return try await execute(request, as: ManifestationsResponse.self)
    }
}
