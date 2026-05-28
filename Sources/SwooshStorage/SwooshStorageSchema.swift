// SwooshStorage/SwooshStorageSchema.swift — SQLite database + migration runner — 0.9S
//
// The single durable backend for all Swoosh state. Replaces the retired
// ActantDB event-sourced backend with a local SQLite file at ~/.swoosh/swoosh.db.
// Schema versioning is handled by a simple integer migration table.

import Foundation
import SQLite

// MARK: - Database actor

/// Thread-safe wrapper around a SQLite connection. All store implementations
/// share one `SwooshDatabase` instance and call its `connection` accessor.
public actor SwooshDatabase {
    private let db: Connection

    /// Opens (or creates) the database at the given path and runs migrations.
    public init(path: String? = nil) throws {
        let resolvedPath = path ?? SwooshDatabase.defaultPath()
        let dir = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.db = try Connection(resolvedPath)

        // WAL mode for concurrent reads
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA foreign_keys = ON")

        try SwooshMigrationRunner.run(on: db)
    }

    /// In-memory database for testing.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        self.db = try Connection(.inMemory)
        try db.execute("PRAGMA foreign_keys = ON")
        try SwooshMigrationRunner.run(on: db)
    }

    /// Execute a read or write operation on the database connection.
    public func execute<T>(_ body: (Connection) throws -> T) rethrows -> T {
        try body(db)
    }

    /// Default database path: ~/.swoosh/swoosh.db
    public static func defaultPath() -> String {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".swoosh/swoosh.db").path
        #else
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ai.swoosh.agent/swoosh.db").path
        #endif
    }
}

// MARK: - Migration runner

enum SwooshMigrationRunner {
    static func run(on db: Connection) throws {
        // Create the version-tracking table itself
        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        let currentVersion = try currentSchemaVersion(db)

        for migration in migrations where migration.version > currentVersion {
            try db.transaction {
                try db.execute(migration.sql)
                try db.run(
                    "INSERT INTO schema_version (version) VALUES (?)",
                    migration.version
                )
            }
        }
    }

    private static func currentSchemaVersion(_ db: Connection) throws -> Int {
        let stmt = try db.prepare("SELECT COALESCE(MAX(version), 0) FROM schema_version")
        for row in stmt {
            return row[0] as? Int64 != nil ? Int(row[0] as! Int64) : 0
        }
        return 0
    }

    // MARK: - Migration definitions

    struct Migration {
        let version: Int
        let sql: String
    }

    static let migrations: [Migration] = [
        Migration(version: 1, sql: v1_initialSchema),
    ]

    // ── v1: full initial schema ──────────────────────────────────────

    static let v1_initialSchema = """
        -- Sessions (SessionStoring)
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            tool_calls TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id);

        -- Response audit records (ResponseAuditing)
        CREATE TABLE IF NOT EXISTS response_audits (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            response_id TEXT NOT NULL,
            model_used TEXT NOT NULL,
            memory_ids_used TEXT NOT NULL,
            setup_report_used INTEGER NOT NULL DEFAULT 0,
            permission_summary_used INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_response_audits_session ON response_audits(session_id);

        -- Audit log (AuditLogging)
        CREATE TABLE IF NOT EXISTS audit_log (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            kind TEXT NOT NULL,
            tool_name TEXT,
            session_id TEXT,
            detail TEXT NOT NULL,
            success INTEGER NOT NULL DEFAULT 1,
            anchor_batch_id TEXT,
            merkle_leaf_hash TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_audit_log_kind ON audit_log(kind);
        CREATE INDEX IF NOT EXISTS idx_audit_log_tool ON audit_log(tool_name);
        CREATE INDEX IF NOT EXISTS idx_audit_log_batch ON audit_log(anchor_batch_id);

        -- Approved memories (MemoryToolStoring)
        CREATE TABLE IF NOT EXISTS approved_memories (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            category TEXT NOT NULL,
            sensitivity TEXT NOT NULL DEFAULT 'normal',
            confidence REAL NOT NULL DEFAULT 1.0,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            last_used_at TEXT
        );

        -- Memory candidates (MemoryToolStoring)
        CREATE TABLE IF NOT EXISTS memory_candidates (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            category TEXT NOT NULL,
            sensitivity TEXT NOT NULL DEFAULT 'normal',
            confidence REAL NOT NULL DEFAULT 0.5,
            evidence TEXT NOT NULL DEFAULT '[]',
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_candidates_status ON memory_candidates(status);

        -- Approval records (ApprovalStoring)
        CREATE TABLE IF NOT EXISTS approvals (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            tool_name TEXT NOT NULL,
            risk TEXT NOT NULL,
            permission TEXT NOT NULL,
            input_preview TEXT NOT NULL,
            origin TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            resolved_at TEXT,
            resolved_by TEXT,
            deny_reason TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_approvals_status ON approvals(status);
        CREATE INDEX IF NOT EXISTS idx_approvals_session ON approvals(session_id);

        -- Setup reports (SetupReportLoading)
        CREATE TABLE IF NOT EXISTS setup_reports (
            id TEXT PRIMARY KEY,
            summary TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Permission grants (PermissionPersisting)
        CREATE TABLE IF NOT EXISTS permission_grants (
            permission TEXT PRIMARY KEY,
            granted INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Anchor batches (on-chain receipt system)
        CREATE TABLE IF NOT EXISTS anchor_batches (
            id TEXT PRIMARY KEY,
            merkle_root TEXT NOT NULL,
            entry_count INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            anchor_tx_signature TEXT,
            anchor_status TEXT NOT NULL DEFAULT 'pending',
            anchor_chain TEXT NOT NULL DEFAULT 'solana',
            token_fee_lamports INTEGER
        );

        -- Stake ledger (stake-to-act gating)
        CREATE TABLE IF NOT EXISTS stake_ledger (
            id TEXT PRIMARY KEY,
            wallet_address TEXT NOT NULL,
            token_mint TEXT NOT NULL,
            amount_staked REAL NOT NULL,
            toolset_id TEXT NOT NULL,
            staked_at TEXT NOT NULL DEFAULT (datetime('now')),
            released_at TEXT,
            status TEXT NOT NULL DEFAULT 'active'
        );
        CREATE INDEX IF NOT EXISTS idx_stake_wallet ON stake_ledger(wallet_address, toolset_id);

        -- Rebate tracking
        CREATE TABLE IF NOT EXISTS rebate_ledger (
            id TEXT PRIMARY KEY,
            wallet_address TEXT NOT NULL,
            audit_entry_id TEXT NOT NULL,
            tool_name TEXT NOT NULL,
            toolset_id TEXT NOT NULL,
            anchor_batch_id TEXT,
            rebate_amount REAL,
            period TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (audit_entry_id) REFERENCES audit_log(id)
        );
        CREATE INDEX IF NOT EXISTS idx_rebate_wallet_period ON rebate_ledger(wallet_address, period);
    """
}

// MARK: - ISO 8601 helpers

nonisolated(unsafe) let swooshISO8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func swooshDateString(_ date: Date = Date()) -> String {
    swooshISO8601.string(from: date)
}

func swooshParseDate(_ string: String) -> Date {
    swooshISO8601.date(from: string) ?? Date()
}

/// Safely extract a Double from a SQLite `Binding?`.
/// SQLite may return `Int64` for integer-valued REAL columns or
/// aggregates like `COALESCE(SUM(...), 0)`.
func swooshDouble(_ value: Any?) -> Double {
    if let d = value as? Double { return d }
    if let i = value as? Int64 { return Double(i) }
    return 0
}
