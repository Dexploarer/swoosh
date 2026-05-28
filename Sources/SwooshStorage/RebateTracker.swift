// SwooshStorage/RebateTracker.swift — On-chain receipt rebate accounting — 0.9S

import Foundation
import SQLite
import SwooshTools

// MARK: - Rebate record

public struct RebateRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let walletAddress: String
    public let auditEntryID: String
    public let toolName: String
    public let toolsetID: String
    public var anchorBatchID: String?
    public var rebateAmount: Double?
    public let period: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, walletAddress: String, auditEntryID: String,
        toolName: String, toolsetID: String, anchorBatchID: String? = nil,
        rebateAmount: Double? = nil, period: String, createdAt: Date = Date()
    ) {
        self.id = id; self.walletAddress = walletAddress; self.auditEntryID = auditEntryID
        self.toolName = toolName; self.toolsetID = toolsetID
        self.anchorBatchID = anchorBatchID; self.rebateAmount = rebateAmount
        self.period = period; self.createdAt = createdAt
    }
}

// MARK: - Rebate aggregation

public struct RebateAggregation: Codable, Sendable {
    public let walletAddress: String
    public let period: String
    public let totalReceipts: Int
    public let anchoredReceipts: Int
    public let totalRebateAmount: Double

    public init(
        walletAddress: String, period: String, totalReceipts: Int,
        anchoredReceipts: Int, totalRebateAmount: Double
    ) {
        self.walletAddress = walletAddress; self.period = period
        self.totalReceipts = totalReceipts; self.anchoredReceipts = anchoredReceipts
        self.totalRebateAmount = totalRebateAmount
    }
}

// MARK: - Rebate tracker actor

public actor RebateTracker {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func recordEligible(
        walletAddress: String, auditEntryID: String,
        toolName: String, toolsetID: String
    ) async throws {
        let id = UUID().uuidString
        let period = currentPeriod()
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO rebate_ledger
                    (id, wallet_address, audit_entry_id, tool_name, toolset_id, period, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, id, walletAddress, auditEntryID, toolName, toolsetID, period, now)
        }
    }

    public func linkToAnchorBatch(auditEntryIDs: [String], batchID: String) async throws {
        guard !auditEntryIDs.isEmpty else { return }
        try await db.execute { conn -> Void in
            for entryID in auditEntryIDs {
                _ = try conn.run(
                    "UPDATE rebate_ledger SET anchor_batch_id = ? WHERE audit_entry_id = ?",
                    batchID, entryID)
            }
        }
    }

    public func aggregateForPeriod(_ period: String) async throws -> [RebateAggregation] {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT wallet_address, COUNT(*) as total,
                       COUNT(anchor_batch_id) as anchored,
                       COALESCE(SUM(rebate_amount), 0) as total_rebate
                FROM rebate_ledger WHERE period = ?
                GROUP BY wallet_address ORDER BY total DESC
            """, period)
            var results: [RebateAggregation] = []
            for row in stmt {
                results.append(RebateAggregation(
                    walletAddress: row[0] as! String, period: period,
                    totalReceipts: Int(row[1] as! Int64),
                    anchoredReceipts: Int(row[2] as! Int64),
                    totalRebateAmount: swooshDouble(row[3])
                ))
            }
            return results
        }
    }

    public func records(wallet: String, period: String) async throws -> [RebateRecord] {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT id, wallet_address, audit_entry_id, tool_name, toolset_id,
                       anchor_batch_id, rebate_amount, period, created_at
                FROM rebate_ledger WHERE wallet_address = ? AND period = ?
                ORDER BY created_at DESC
            """, wallet, period)
            var results: [RebateRecord] = []
            for row in stmt {
                results.append(RebateRecord(
                    id: row[0] as! String, walletAddress: row[1] as! String,
                    auditEntryID: row[2] as! String, toolName: row[3] as! String,
                    toolsetID: row[4] as! String, anchorBatchID: row[5] as? String,
                    rebateAmount: row[6] != nil ? swooshDouble(row[6]) : nil, period: row[7] as! String,
                    createdAt: swooshParseDate(row[8] as! String)
                ))
            }
            return results
        }
    }

    private func currentPeriod() -> String {
        let cal = Calendar.current; let now = Date()
        let year = cal.component(.year, from: now)
        let quarter = (cal.component(.month, from: now) - 1) / 3 + 1
        return "\(year)-Q\(quarter)"
    }
}
