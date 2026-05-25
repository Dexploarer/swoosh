// SwooshClient/SwooshAPIClient+Doctor.swift — 0.4A Doctor endpoint
//
// Wire method for `GET /api/doctor` — runs the daemon-side
// `DoctorRunner` and returns a `DoctorReportResponse`.

import Foundation

extension SwooshAPIClient {
    public func doctorReport() async throws -> DoctorReportResponse {
        let request = try makeRequest(method: "GET", path: "api/doctor", body: nil)
        return try await execute(request, as: DoctorReportResponse.self)
    }
}
