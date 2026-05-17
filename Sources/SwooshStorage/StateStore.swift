// SwooshStorage/StateStore.swift — SQLite state store for Swoosh v0
//
// Single source of truth: ~/.swoosh/state.db
// Tables: scout_records, memory_candidates, approved_memories, audit_events, permissions, setup_reports

import Foundation
import SQLite

// MARK: - State store

public actor SwooshStateStore {
    private let db: Connection

    // ── Table definitions ────────────────────────────────────────

    // Scout records
    private let scoutRecords = Table("scout_records")
    private let sr_id = SQLite.Expression<String>("id")
    private let sr_sourceID = SQLite.Expression<String>("source_id")
    private let sr_kind = SQLite.Expression<String>("kind")
    private let sr_sensitivity = SQLite.Expression<String>("sensitivity")
    private let sr_content = SQLite.Expression<String>("content")
    private let sr_metadata = SQLite.Expression<String>("metadata")
    private let sr_createdAt = SQLite.Expression<String>("created_at")

    // Memory candidates
    private let memoryCandidates = Table("memory_candidates")
    private let mc_id = SQLite.Expression<String>("id")
    private let mc_text = SQLite.Expression<String>("text")
    private let mc_category = SQLite.Expression<String>("category")
    private let mc_confidence = SQLite.Expression<Double>("confidence")
    private let mc_sensitivity = SQLite.Expression<String>("sensitivity")
    private let mc_status = SQLite.Expression<String>("status")   // pending, approved, rejected, edited
    private let mc_evidence = SQLite.Expression<String>("evidence")
    private let mc_createdAt = SQLite.Expression<String>("created_at")

    // Approved memories
    private let approvedMemories = Table("approved_memories")
    private let am_id = SQLite.Expression<String>("id")
    private let am_text = SQLite.Expression<String>("text")
    private let am_category = SQLite.Expression<String>("category")
    private let am_sensitivity = SQLite.Expression<String>("sensitivity")
    private let am_sourceCandidateID = SQLite.Expression<String?>("source_candidate_id")
    private let am_approvedAt = SQLite.Expression<String>("approved_at")

    // Audit events
    private let auditEvents = Table("audit_events")
    private let ae_id = SQLite.Expression<String>("id")
    private let ae_eventType = SQLite.Expression<String>("event_type")
    private let ae_actor = SQLite.Expression<String>("actor")
    private let ae_target = SQLite.Expression<String>("target")
    private let ae_details = SQLite.Expression<String>("details")
    private let ae_createdAt = SQLite.Expression<String>("created_at")

    // Permissions
    private let permissions = Table("permissions")
    private let p_id = SQLite.Expression<String>("id")
    private let p_permission = SQLite.Expression<String>("permission")
    private let p_level = SQLite.Expression<String>("level")
    private let p_scope = SQLite.Expression<String>("scope")
    private let p_updatedAt = SQLite.Expression<String>("updated_at")

    // Setup reports
    private let setupReports = Table("setup_reports")
    private let rep_id = SQLite.Expression<String>("id")
    private let rep_content = SQLite.Expression<String>("content")
    private let rep_createdAt = SQLite.Expression<String>("created_at")

    // MARK: - Init

    public init(path: String? = nil) throws {
        let dbPath = path ?? {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".swoosh").path
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return "\(dir)/state.db"
        }()

        db = try Connection(dbPath)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA foreign_keys = ON")

        // Create tables using raw SQL to avoid actor isolation issues with closure-based API
        try db.execute("""
            CREATE TABLE IF NOT EXISTS scout_records (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                sensitivity TEXT NOT NULL,
                content TEXT NOT NULL,
                metadata TEXT DEFAULT '{}',
                created_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS memory_candidates (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                category TEXT NOT NULL,
                confidence REAL NOT NULL,
                sensitivity TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                evidence TEXT DEFAULT '[]',
                created_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS approved_memories (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                category TEXT NOT NULL,
                sensitivity TEXT NOT NULL,
                source_candidate_id TEXT,
                approved_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS audit_events (
                id TEXT PRIMARY KEY,
                event_type TEXT NOT NULL,
                actor TEXT NOT NULL,
                target TEXT NOT NULL,
                details TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS permissions (
                id TEXT PRIMARY KEY,
                permission TEXT NOT NULL,
                level TEXT NOT NULL,
                scope TEXT DEFAULT '',
                updated_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS setup_reports (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
    }

    // MARK: - Scout records

    public func insertScoutRecords(_ records: [StoredScoutRecord]) throws {
        for r in records {
            try db.run(scoutRecords.insert(or: .replace,
                sr_id <- r.id,
                sr_sourceID <- r.sourceID,
                sr_kind <- r.kind,
                sr_sensitivity <- r.sensitivity,
                sr_content <- r.content,
                sr_metadata <- r.metadata,
                sr_createdAt <- r.createdAt
            ))
        }
    }

    public func listScoutRecords(source: String? = nil) throws -> [StoredScoutRecord] {
        var query = scoutRecords.order(sr_createdAt.desc)
        if let s = source {
            query = query.filter(sr_sourceID == s)
        }
        return try db.prepare(query).map { row in
            StoredScoutRecord(
                id: row[sr_id], sourceID: row[sr_sourceID],
                kind: row[sr_kind], sensitivity: row[sr_sensitivity],
                content: row[sr_content], metadata: row[sr_metadata],
                createdAt: row[sr_createdAt]
            )
        }
    }

    public func scoutRecordCount() throws -> Int {
        try db.scalar(scoutRecords.count)
    }

    // MARK: - Memory candidates

    public func insertMemoryCandidates(_ candidates: [StoredMemoryCandidate]) throws {
        for c in candidates {
            try db.run(memoryCandidates.insert(or: .replace,
                mc_id <- c.id,
                mc_text <- c.text,
                mc_category <- c.category,
                mc_confidence <- c.confidence,
                mc_sensitivity <- c.sensitivity,
                mc_status <- c.status,
                mc_evidence <- c.evidence,
                mc_createdAt <- c.createdAt
            ))
        }
    }

    public func listMemoryCandidates(status: String? = nil) throws -> [StoredMemoryCandidate] {
        var query = memoryCandidates.order(mc_createdAt.desc)
        if let s = status {
            query = query.filter(mc_status == s)
        }
        return try db.prepare(query).map { row in
            StoredMemoryCandidate(
                id: row[mc_id], text: row[mc_text],
                category: row[mc_category], confidence: row[mc_confidence],
                sensitivity: row[mc_sensitivity], status: row[mc_status],
                evidence: row[mc_evidence], createdAt: row[mc_createdAt]
            )
        }
    }

    public func approveMemoryCandidate(id: String, finalText: String? = nil) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let candidate = memoryCandidates.filter(mc_id == id)

        // Get the candidate
        guard let row = try db.pluck(candidate) else { return }
        let text = finalText ?? row[mc_text]

        // Update status
        try db.run(candidate.update(mc_status <- "approved"))

        // Insert approved memory
        try db.run(approvedMemories.insert(
            am_id <- UUID().uuidString,
            am_text <- text,
            am_category <- row[mc_category],
            am_sensitivity <- row[mc_sensitivity],
            am_sourceCandidateID <- id,
            am_approvedAt <- now
        ))

        // Audit
        try appendAuditEvent(
            eventType: "memory.approved",
            actor: "user",
            target: id,
            details: "Approved memory: \(text.prefix(80))"
        )
    }

    public func rejectMemoryCandidate(id: String) throws {
        let candidate = memoryCandidates.filter(mc_id == id)
        try db.run(candidate.update(mc_status <- "rejected"))
        try appendAuditEvent(
            eventType: "memory.rejected",
            actor: "user",
            target: id,
            details: "Rejected memory candidate"
        )
    }

    public func approveAllPending() throws -> Int {
        let pending = try listMemoryCandidates(status: "pending")
        for c in pending {
            try approveMemoryCandidate(id: c.id)
        }
        return pending.count
    }

    // MARK: - Approved memories

    public func listApprovedMemories() throws -> [StoredApprovedMemory] {
        try db.prepare(approvedMemories.order(am_approvedAt.desc)).map { row in
            StoredApprovedMemory(
                id: row[am_id], text: row[am_text],
                category: row[am_category], sensitivity: row[am_sensitivity],
                sourceCandidateID: row[am_sourceCandidateID],
                approvedAt: row[am_approvedAt]
            )
        }
    }

    public func approvedMemoryCount() throws -> Int {
        try db.scalar(approvedMemories.count)
    }

    /// Get all approved memories as context for the agent
    public func recallMemories(query: String? = nil) throws -> [StoredApprovedMemory] {
        // v0: return all. v1: semantic search.
        try listApprovedMemories()
    }

    // MARK: - Audit events

    public func appendAuditEvent(eventType: String, actor: String, target: String, details: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try db.run(auditEvents.insert(
            ae_id <- UUID().uuidString,
            ae_eventType <- eventType,
            ae_actor <- actor,
            ae_target <- target,
            ae_details <- details,
            ae_createdAt <- now
        ))
    }

    public func listAuditEvents(limit: Int = 50) throws -> [StoredAuditEvent] {
        try db.prepare(auditEvents.order(ae_createdAt.desc).limit(limit)).map { row in
            StoredAuditEvent(
                id: row[ae_id], eventType: row[ae_eventType],
                actor: row[ae_actor], target: row[ae_target],
                details: row[ae_details], createdAt: row[ae_createdAt]
            )
        }
    }

    public func auditEventCount() throws -> Int {
        try db.scalar(auditEvents.count)
    }

    // MARK: - Setup reports

    public func saveSetupReport(content: String) throws -> String {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        try db.run(setupReports.insert(
            rep_id <- id,
            rep_content <- content,
            rep_createdAt <- now
        ))
        try appendAuditEvent(
            eventType: "setup.report_saved",
            actor: "system",
            target: id,
            details: "Setup report saved"
        )
        return id
    }

    public func latestSetupReport() throws -> StoredSetupReport? {
        try db.pluck(setupReports.order(rep_createdAt.desc)).map { row in
            StoredSetupReport(
                id: row[rep_id],
                content: row[rep_content],
                createdAt: row[rep_createdAt]
            )
        }
    }
}

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
