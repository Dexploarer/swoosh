// SwooshDBClient/StatePlane.swift — Abstract state plane protocol
//
// This is the key abstraction: Swoosh.app, CLI, and swooshd talk to
// the state plane, not directly to SQLite or SpacetimeDB.
//
// Implementations:
//   SQLiteStatePlane    — current v0.1 default
//   SpacetimeStatePlane — spike v0.2A

import Foundation

// MARK: - Row types (shared between all backends)

public struct MemoryCandidateRow: Sendable, Identifiable, Codable {
    public let id: String
    public let text: String
    public let category: String
    public let confidence: Double
    public let sensitivity: String
    public let status: String
    public let evidenceJSON: String
    public let createdAt: String

    public init(id: String, text: String, category: String, confidence: Double,
                sensitivity: String, status: String, evidenceJSON: String, createdAt: String) {
        self.id = id; self.text = text; self.category = category; self.confidence = confidence
        self.sensitivity = sensitivity; self.status = status; self.evidenceJSON = evidenceJSON
        self.createdAt = createdAt
    }
}

public struct ApprovedMemoryRow: Sendable, Identifiable, Codable {
    public let id: String
    public let text: String
    public let category: String
    public let sensitivity: String
    public let sourceCandidateID: String?
    public let approvedAt: String

    public init(id: String, text: String, category: String, sensitivity: String,
                sourceCandidateID: String?, approvedAt: String) {
        self.id = id; self.text = text; self.category = category; self.sensitivity = sensitivity
        self.sourceCandidateID = sourceCandidateID; self.approvedAt = approvedAt
    }
}

public struct AuditEventRow: Sendable, Identifiable, Codable {
    public let id: String
    public let eventType: String
    public let subjectType: String
    public let subjectID: String
    public let metadataJSON: String
    public let createdAt: String

    public init(id: String, eventType: String, subjectType: String, subjectID: String,
                metadataJSON: String, createdAt: String) {
        self.id = id; self.eventType = eventType; self.subjectType = subjectType
        self.subjectID = subjectID; self.metadataJSON = metadataJSON; self.createdAt = createdAt
    }
}

public struct ScoutRecordRow: Sendable, Identifiable, Codable {
    public let id: String
    public let sourceID: String
    public let kind: String
    public let sensitivity: String
    public let content: String
    public let metadataJSON: String
    public let createdAt: String

    public init(id: String, sourceID: String, kind: String, sensitivity: String,
                content: String, metadataJSON: String, createdAt: String) {
        self.id = id; self.sourceID = sourceID; self.kind = kind; self.sensitivity = sensitivity
        self.content = content; self.metadataJSON = metadataJSON; self.createdAt = createdAt
    }
}

// MARK: - State plane protocol

/// The abstraction that decouples Swoosh from any specific database backend.
/// Both SQLite and SpacetimeDB implement this.
public protocol SwooshStatePlane: Sendable {

    // ── Memory candidates ────────────────────────────────────
    func listMemoryCandidates(status: String?) async throws -> [MemoryCandidateRow]
    func createMemoryCandidate(_ row: MemoryCandidateRow) async throws
    func approveMemoryCandidate(id: String, finalText: String) async throws
    func rejectMemoryCandidate(id: String, reason: String?) async throws
    func approveAllPending() async throws -> Int

    // ── Approved memories ────────────────────────────────────
    func listApprovedMemories() async throws -> [ApprovedMemoryRow]
    func approvedMemoryCount() async throws -> Int

    // ── Scout records ────────────────────────────────────────
    func submitScoutRecords(_ records: [ScoutRecordRow]) async throws
    func listScoutRecords(source: String?) async throws -> [ScoutRecordRow]

    // ── Audit events ─────────────────────────────────────────
    func appendAuditEvent(eventType: String, subjectType: String, subjectID: String, metadata: String) async throws
    func listAuditEvents(limit: Int) async throws -> [AuditEventRow]

    // ── Setup reports ────────────────────────────────────────
    func saveSetupReport(content: String) async throws -> String
    func latestSetupReport() async throws -> String?
}
