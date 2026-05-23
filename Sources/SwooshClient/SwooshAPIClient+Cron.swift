// SwooshClient/SwooshAPIClient+Cron.swift — 0.4A Cron CRUD endpoints
//
// Wire methods for `GET /api/cron`, `POST /api/cron`, `DELETE
// /api/cron/{id}`, and the `POST /api/cron/{id}/run` ad-hoc trigger.

import Foundation

extension SwooshAPIClient {
    public func cronJobs() async throws -> CronJobsResponse {
        let request = try makeRequest(method: "GET", path: "api/cron", body: nil)
        return try await execute(request, as: CronJobsResponse.self)
    }

    public func createCronJob(_ body: CronJobCreateRequest) async throws -> CronJobMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/cron", body: encoded)
        return try await execute(request, as: CronJobMutationResponse.self)
    }

    public func deleteCronJob(id: String) async throws -> CronJobsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/cron/\(encodedID)", body: nil)
        return try await execute(request, as: CronJobsResponse.self)
    }

    public func runCronJob(id: String) async throws -> CronJobMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/cron/\(encodedID)/run", body: nil)
        return try await execute(request, as: CronJobMutationResponse.self)
    }
}
