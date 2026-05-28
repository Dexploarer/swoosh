// SwooshStorage/SQLiteResponseAuditor.swift — Durable response audit store — 0.9S
//
// Persists ResponseAuditRecord entries for /why. Replaces InMemoryResponseAuditor.

import Foundation
import SQLite
import SwooshCore

public actor SQLiteResponseAuditor: ResponseAuditing {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func logResponseAudit(_ audit: ResponseAuditRecord) async throws {
        let memoryIDsJSON = String(
            data: try JSONEncoder().encode(audit.memoryIDsUsed),
            encoding: .utf8
        ) ?? "[]"
        let now = swooshDateString(audit.createdAt)

        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO response_audits
                    (id, session_id, response_id, model_used, memory_ids_used,
                     setup_report_used, permission_summary_used, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
                audit.responseID, audit.sessionID, audit.responseID,
                audit.modelUsed, memoryIDsJSON,
                audit.setupReportUsed ? 1 : 0,
                audit.permissionSummaryUsed ? 1 : 0, now
            )
        }
    }

    public func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? {
        try await db.execute { conn -> ResponseAuditRecord? in
            let stmt = try conn.prepare("""
                SELECT session_id, response_id, model_used, memory_ids_used,
                       setup_report_used, permission_summary_used, created_at
                FROM response_audits WHERE session_id = ?
                ORDER BY created_at DESC LIMIT 1
            """, sessionID)

            for row in stmt {
                let memoryIDsJSON = row[3] as? String ?? "[]"
                let memoryIDs = (try? JSONDecoder().decode(
                    [String].self, from: Data(memoryIDsJSON.utf8)
                )) ?? []
                return ResponseAuditRecord(
                    sessionID: row[0] as! String,
                    responseID: row[1] as! String,
                    modelUsed: row[2] as! String,
                    memoryIDsUsed: memoryIDs,
                    setupReportUsed: (row[4] as! Int64) != 0,
                    permissionSummaryUsed: (row[5] as! Int64) != 0,
                    createdAt: swooshParseDate(row[6] as! String)
                )
            }
            return nil
        }
    }
}
