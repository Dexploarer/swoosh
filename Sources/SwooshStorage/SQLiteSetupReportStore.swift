// SwooshStorage/SQLiteSetupReportStore.swift — Durable setup report store — 0.9S
//
// Persists setup report summaries to SQLite. Replaces InMemoryReportLoader.

import Foundation
import SQLite
import SwooshCore

public actor SQLiteSetupReportStore: SetupReportLoading {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func loadLatestSetupReport() async throws -> String? {
        try await db.execute { conn -> String? in
            let stmt = try conn.prepare("""
                SELECT summary FROM setup_reports
                ORDER BY created_at DESC LIMIT 1
            """)
            for row in stmt {
                return row[0] as? String
            }
            return nil
        }
    }

    /// Save a new setup report summary.
    public func saveReport(summary: String) async throws {
        let id = UUID().uuidString
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO setup_reports (id, summary, created_at)
                VALUES (?, ?, ?)
            """, id, summary, now)
        }
    }
}
