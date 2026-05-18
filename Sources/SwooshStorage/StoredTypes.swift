// SwooshStorage/StoredTypes.swift — Stored data types for StateStore
import Foundation

// MARK: - Stored types

public struct StoredScoutRecord: Sendable {
    public let id: String
    public let sourceID: String
    public let kind: String
    public let sensitivity: String
    public let content: String
    public let metadata: String
    public let createdAt: String
    public init(id: String, sourceID: String, kind: String, sensitivity: String, content: String, metadata: String, createdAt: String) {
        self.id = id; self.sourceID = sourceID; self.kind = kind; self.sensitivity = sensitivity
        self.content = content; self.metadata = metadata; self.createdAt = createdAt
    }
}

public struct StoredMemoryCandidate: Sendable {
    public let id: String
    public let text: String
    public let category: String
    public let confidence: Double
    public let sensitivity: String
    public let status: String
    public let evidence: String
    public let createdAt: String
    public init(id: String, text: String, category: String, confidence: Double, sensitivity: String, status: String, evidence: String, createdAt: String) {
        self.id = id; self.text = text; self.category = category; self.confidence = confidence
        self.sensitivity = sensitivity; self.status = status; self.evidence = evidence; self.createdAt = createdAt
    }
}

public struct StoredApprovedMemory: Sendable {
    public let id: String
    public let text: String
    public let category: String
    public let sensitivity: String
    public let sourceCandidateID: String?
    public let approvedAt: String
    public init(id: String, text: String, category: String, sensitivity: String, sourceCandidateID: String?, approvedAt: String) {
        self.id = id; self.text = text; self.category = category; self.sensitivity = sensitivity
        self.sourceCandidateID = sourceCandidateID; self.approvedAt = approvedAt
    }
}

public struct StoredAuditEvent: Sendable {
    public let id: String
    public let eventType: String
    public let actor: String
    public let target: String
    public let details: String
    public let createdAt: String
    public init(id: String, eventType: String, actor: String, target: String, details: String, createdAt: String) {
        self.id = id; self.eventType = eventType; self.actor = actor; self.target = target
        self.details = details; self.createdAt = createdAt
    }
}

public struct StoredSetupReport: Sendable {
    public let id: String
    public let content: String
    public let createdAt: String
    public init(id: String, content: String, createdAt: String) {
        self.id = id; self.content = content; self.createdAt = createdAt
    }
}
