// SwooshStorage/SQLitePermissionStore.swift — Durable permission grant persistence — 0.9S

import Foundation
import SQLite
import SwooshTools

// SQLitePermissionStore conforms to PermissionPersisting (defined in SwooshTools/Tool.swift)
// so the firewall can accept it without depending on SwooshStorage.

public actor SQLitePermissionStore: PermissionPersisting {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func loadGrants() async throws -> [(permission: SwooshPermission, granted: Bool)] {
        try await db.execute { conn in
            let stmt = try conn.prepare("SELECT permission, granted FROM permission_grants")
            var results: [(permission: SwooshPermission, granted: Bool)] = []
            for row in stmt {
                guard let perm = SwooshPermission(rawValue: row[0] as! String) else { continue }
                results.append((permission: perm, granted: (row[1] as! Int64) != 0))
            }
            return results
        }
    }

    public func saveGrant(_ permission: SwooshPermission, granted: Bool) async throws {
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT OR REPLACE INTO permission_grants (permission, granted, updated_at)
                VALUES (?, ?, ?)
            """, permission.rawValue, granted ? 1 : 0, now)
        }
    }

    public func removeGrant(_ permission: SwooshPermission) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run("DELETE FROM permission_grants WHERE permission = ?", permission.rawValue)
        }
    }
}
