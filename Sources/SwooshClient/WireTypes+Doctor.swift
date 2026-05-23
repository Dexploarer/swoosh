// SwooshClient/WireTypes+Doctor.swift — 0.4A Tier 1 Doctor wire types
//
// Wire format for `GET /api/doctor`. Mirrors `SwooshDoctor.DoctorReport`
// shape but lives in SwooshClient so iOS — which does NOT import
// SwooshDoctor — can decode the response. The daemon-side bridge
// translates `DoctorReport` → `DoctorReportResponse` at the route
// boundary.
//
// `status` is a raw String rather than a typed enum so a future
// SwooshDoctor adds a new status without breaking the wire contract.

import Foundation

public struct DoctorReportResponse: Codable, Sendable, Equatable {
    public let id: String
    public let createdAt: Date
    public let checks: [DoctorCheckSummary]
    public let summary: DoctorSummaryWire
    public let recommendations: [String]
    public let isHealthy: Bool

    public init(
        id: String,
        createdAt: Date,
        checks: [DoctorCheckSummary],
        summary: DoctorSummaryWire,
        recommendations: [String],
        isHealthy: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.checks = checks
        self.summary = summary
        self.recommendations = recommendations
        self.isHealthy = isHealthy
    }
}

public struct DoctorCheckSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String          // matches `checkID` so SwiftUI ForEach can key off it
    public let title: String
    public let category: String    // raw rawValue of DoctorCategory
    public let status: String      // raw rawValue of DoctorCheckStatus
    public let message: String?
    public let fixCommand: String?

    public init(
        id: String,
        title: String,
        category: String,
        status: String,
        message: String?,
        fixCommand: String?
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.message = message
        self.fixCommand = fixCommand
    }
}

public struct DoctorSummaryWire: Codable, Sendable, Equatable {
    public let passed: Int
    public let warnings: Int
    public let failures: Int
    public let skipped: Int

    public init(passed: Int, warnings: Int, failures: Int, skipped: Int) {
        self.passed = passed
        self.warnings = warnings
        self.failures = failures
        self.skipped = skipped
    }
}
