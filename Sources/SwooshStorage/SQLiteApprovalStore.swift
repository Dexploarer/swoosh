// SwooshStorage/SQLiteApprovalStore.swift — Durable approval store — 0.9S

import Foundation
import SQLite
import SwooshTools
import SwooshApprovals

public actor SQLiteApprovalStore: ApprovalStoring {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func save(_ approval: ApprovalRecord) async throws {
        let now = swooshDateString(approval.createdAt)
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT OR REPLACE INTO approvals
                    (id, session_id, tool_name, risk, permission, input_preview,
                     origin, status, created_at, resolved_at, resolved_by, deny_reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
                approval.id, approval.sessionID, approval.toolName,
                approval.risk.rawValue, approval.permission.rawValue,
                approval.inputPreview, approval.origin.rawValue,
                approval.status.rawValue, now,
                approval.resolvedAt.map(swooshDateString),
                approval.resolvedBy?.rawValue, approval.denyReason
            )
        }
    }

    public func get(id: String) async -> ApprovalRecord? {
        try? await db.execute { conn -> ApprovalRecord? in
            let stmt = try conn.prepare("""
                SELECT id, session_id, tool_name, risk, permission, input_preview,
                       origin, status, created_at, resolved_at, resolved_by, deny_reason
                FROM approvals WHERE id = ?
            """, id)
            return Self.parseRecords(from: stmt).first
        }
    }

    public func listPending(sessionID: String?) async -> [ApprovalRecord] {
        (try? await db.execute { conn in
            let sql: String
            let bindings: [Binding?]
            if let sid = sessionID {
                sql = """
                    SELECT id, session_id, tool_name, risk, permission, input_preview,
                           origin, status, created_at, resolved_at, resolved_by, deny_reason
                    FROM approvals WHERE status = 'pending' AND session_id = ?
                    ORDER BY created_at DESC
                """
                bindings = [sid]
            } else {
                sql = """
                    SELECT id, session_id, tool_name, risk, permission, input_preview,
                           origin, status, created_at, resolved_at, resolved_by, deny_reason
                    FROM approvals WHERE status = 'pending'
                    ORDER BY created_at DESC
                """
                bindings = []
            }
            let stmt = try conn.prepare(sql, bindings)
            return Self.parseRecords(from: stmt)
        }) ?? []
    }

    public func resolve(
        id: String, status: ApprovalStatus,
        resolvedBy: ToolCallOrigin, reason: String?
    ) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                UPDATE approvals
                SET status = ?, resolved_at = ?, resolved_by = ?, deny_reason = ?
                WHERE id = ? AND status = 'pending'
            """, status.rawValue, swooshDateString(), resolvedBy.rawValue, reason, id)

            if conn.changes == 0 {
                let check = try conn.prepare("SELECT status FROM approvals WHERE id = ?", id)
                var found = false
                for _ in check { found = true; break }
                if found {
                    throw ApprovalError.alreadyResolved(id)
                } else {
                    throw ApprovalError.approvalNotFound(id)
                }
            }
        }
    }

    public func isApprovedForSession(toolName: String, sessionID: String) async -> Bool {
        (try? await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT COUNT(*) FROM approvals
                WHERE tool_name = ? AND session_id = ? AND status = 'approvedForSession'
            """, toolName, sessionID)
            for row in stmt {
                return (row[0] as! Int64) > 0
            }
            return false
        }) ?? false
    }

    private static func parseRecords(from stmt: Statement) -> [ApprovalRecord] {
        var results: [ApprovalRecord] = []
        for row in stmt {
            guard let risk = ToolRisk(rawValue: row[3] as! String),
                  let permission = SwooshPermission(rawValue: row[4] as! String),
                  let origin = ToolCallOrigin(rawValue: row[6] as! String),
                  let status = ApprovalStatus(rawValue: row[7] as! String) else { continue }
            var record = ApprovalRecord(
                id: row[0] as! String, sessionID: row[1] as! String,
                toolName: row[2] as! String, risk: risk, permission: permission,
                inputPreview: row[5] as! String, origin: origin, status: status,
                createdAt: swooshParseDate(row[8] as! String)
            )
            record.resolvedAt = (row[9] as? String).map(swooshParseDate)
            record.resolvedBy = (row[10] as? String).flatMap(ToolCallOrigin.init(rawValue:))
            record.denyReason = row[11] as? String
            results.append(record)
        }
        return results
    }
}
