// SwooshDBClient/SQLiteStatePlane.swift — SQLite backend for SwooshStatePlane
//
// Wraps SwooshStateStore to conform to the SwooshStatePlane protocol.
// This is the v0.1 default backend. SpacetimeStatePlane is the v0.2 spike.

import Foundation
import SwooshStorage

public struct SQLiteStatePlane: SwooshStatePlane, Sendable {
    private let store: SwooshStateStore

    public init() throws {
        self.store = try SwooshStateStore()
    }

    // MARK: - Memory candidates

    public func listMemoryCandidates(status: String?) async throws -> [MemoryCandidateRow] {
        try await store.listMemoryCandidates(status: status).map { c in
            MemoryCandidateRow(
                id: c.id, text: c.text, category: c.category,
                confidence: c.confidence, sensitivity: c.sensitivity,
                status: c.status, evidenceJSON: c.evidence, createdAt: c.createdAt
            )
        }
    }

    public func createMemoryCandidate(_ row: MemoryCandidateRow) async throws {
        try await store.insertMemoryCandidates([
            StoredMemoryCandidate(
                id: row.id, text: row.text, category: row.category,
                confidence: row.confidence, sensitivity: row.sensitivity,
                status: row.status, evidence: row.evidenceJSON, createdAt: row.createdAt
            )
        ])
    }

    public func approveMemoryCandidate(id: String, finalText: String) async throws {
        try await store.approveMemoryCandidate(id: id, finalText: finalText)
    }

    public func rejectMemoryCandidate(id: String, reason: String?) async throws {
        try await store.rejectMemoryCandidate(id: id)
    }

    public func approveAllPending() async throws -> Int {
        try await store.approveAllPending()
    }

    // MARK: - Approved memories

    public func listApprovedMemories() async throws -> [ApprovedMemoryRow] {
        try await store.listApprovedMemories().map { m in
            ApprovedMemoryRow(
                id: m.id, text: m.text, category: m.category,
                sensitivity: m.sensitivity, sourceCandidateID: m.sourceCandidateID,
                approvedAt: m.approvedAt
            )
        }
    }

    public func approvedMemoryCount() async throws -> Int {
        try await store.approvedMemoryCount()
    }

    // MARK: - Scout records

    public func submitScoutRecords(_ records: [ScoutRecordRow]) async throws {
        let stored = records.map { r in
            StoredScoutRecord(
                id: r.id, sourceID: r.sourceID, kind: r.kind,
                sensitivity: r.sensitivity, content: r.content,
                metadata: r.metadataJSON, createdAt: r.createdAt
            )
        }
        try await store.insertScoutRecords(stored)
    }

    public func listScoutRecords(source: String?) async throws -> [ScoutRecordRow] {
        try await store.listScoutRecords(source: source).map { r in
            ScoutRecordRow(
                id: r.id, sourceID: r.sourceID, kind: r.kind,
                sensitivity: r.sensitivity, content: r.content,
                metadataJSON: r.metadata, createdAt: r.createdAt
            )
        }
    }

    // MARK: - Audit

    public func appendAuditEvent(eventType: String, subjectType: String, subjectID: String, metadata: String) async throws {
        try await store.appendAuditEvent(
            eventType: eventType, actor: subjectType,
            target: subjectID, details: metadata
        )
    }

    public func listAuditEvents(limit: Int) async throws -> [AuditEventRow] {
        try await store.listAuditEvents(limit: limit).map { e in
            AuditEventRow(
                id: e.id, eventType: e.eventType, subjectType: e.actor,
                subjectID: e.target, metadataJSON: e.details, createdAt: e.createdAt
            )
        }
    }

    // MARK: - Setup reports

    public func saveSetupReport(content: String) async throws -> String {
        try await store.saveSetupReport(content: content)
    }

    public func latestSetupReport() async throws -> String? {
        try await store.latestSetupReport()?.content
    }
}
