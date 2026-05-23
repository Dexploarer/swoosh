// SwooshClient/WireTypes+Memories.swift — 0.4A Tier 1 Memories CRUD wire types
//
// Wire format for `GET /api/memories/{id}`, `POST /api/memories`, and
// the approve / reject mutations. `MemorySummary` itself is in
// WireTypes+Records.swift since the dashboard records endpoint reuses it.

import Foundation

public struct MemoryDetailResponse: Codable, Sendable, Equatable {
    public let memory: MemorySummary
    public let evidenceJSON: String?

    public init(memory: MemorySummary, evidenceJSON: String? = nil) {
        self.memory = memory
        self.evidenceJSON = evidenceJSON
    }
}

public struct MemoryProposeRequest: Codable, Sendable, Equatable {
    public let text: String
    public let category: String
    public let sensitivity: String
    public let confidence: Double
    public let evidenceJSON: String?

    public init(
        text: String,
        category: String,
        sensitivity: String = "low",
        confidence: Double = 0.8,
        evidenceJSON: String? = nil
    ) {
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.evidenceJSON = evidenceJSON
    }
}

public struct MemoryReviewRequest: Codable, Sendable, Equatable {
    public let reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct MemoryMutationResponse: Codable, Sendable, Equatable {
    public let memory: MemorySummary
    public let message: String

    public init(memory: MemorySummary, message: String) {
        self.memory = memory
        self.message = message
    }
}
