// SwooshStorage/ReceiptAnchorEngine.swift — On-chain receipt batching — 0.9S
//
// Batches crypto-toolset audit entries into Merkle roots for on-chain
// anchoring. Entries with tool names matching crypto prefixes (evm.,
// solana., jupiter., hyperliquid., uniswap.) are eligible.

import Foundation
import SQLite
import SwooshTools

// MARK: - Anchor batch

public struct AnchorBatch: Codable, Sendable, Identifiable {
    public let id: String
    public let merkleRoot: String
    public let entryCount: Int
    public let createdAt: Date
    public var anchorTxSignature: String?
    public var anchorStatus: AnchorStatus

    public init(
        id: String = UUID().uuidString, merkleRoot: String, entryCount: Int,
        createdAt: Date = Date(), anchorTxSignature: String? = nil,
        anchorStatus: AnchorStatus = .pending
    ) {
        self.id = id; self.merkleRoot = merkleRoot; self.entryCount = entryCount
        self.createdAt = createdAt; self.anchorTxSignature = anchorTxSignature
        self.anchorStatus = anchorStatus
    }
}

public enum AnchorStatus: String, Codable, Sendable {
    case pending, submitted, confirmed, failed
}

private let cryptoToolPrefixes = ["evm.", "solana.", "jupiter.", "hyperliquid.", "uniswap."]

func isCryptoTool(_ toolName: String?) -> Bool {
    guard let name = toolName else { return false }
    return cryptoToolPrefixes.contains { name.hasPrefix($0) }
}

// MARK: - Receipt anchor engine

public actor ReceiptAnchorEngine {
    private let db: SwooshDatabase
    public let batchIntervalSeconds: Int

    public init(db: SwooshDatabase, batchIntervalSeconds: Int = 300) {
        self.db = db
        self.batchIntervalSeconds = batchIntervalSeconds
    }

    public func createBatch() async throws -> AnchorBatch? {
        try await db.execute { conn -> AnchorBatch? in
            let stmt = try conn.prepare("""
                SELECT id, merkle_leaf_hash FROM audit_log
                WHERE anchor_batch_id IS NULL
                  AND kind IN ('toolCallSucceeded', 'toolCallFailed')
                  AND (tool_name LIKE 'evm.%' OR tool_name LIKE 'solana.%'
                       OR tool_name LIKE 'jupiter.%' OR tool_name LIKE 'hyperliquid.%'
                       OR tool_name LIKE 'uniswap.%')
                ORDER BY timestamp ASC
            """)

            var entryIDs: [String] = []
            var leafHashes: [Data] = []
            for row in stmt {
                entryIDs.append(row[0] as! String)
                let hashHex = row[1] as? String ?? ""
                leafHashes.append(Data(hexString: hashHex) ?? Data(repeating: 0, count: 32))
            }
            guard !entryIDs.isEmpty else { return nil }

            let rootData = MerkleTree.root(from: leafHashes)
            let rootHex = rootData.map { String(format: "%02x", $0) }.joined()
            let batchID = UUID().uuidString
            let now = swooshDateString()

            _ = try conn.run("""
                INSERT INTO anchor_batches
                    (id, merkle_root, entry_count, created_at, anchor_status)
                VALUES (?, ?, ?, ?, 'pending')
            """, batchID, rootHex, entryIDs.count, now)

            for entryID in entryIDs {
                _ = try conn.run(
                    "UPDATE audit_log SET anchor_batch_id = ? WHERE id = ?",
                    batchID, entryID)
            }

            return AnchorBatch(
                id: batchID, merkleRoot: rootHex,
                entryCount: entryIDs.count, createdAt: swooshParseDate(now))
        }
    }

    public func markSubmitted(batchID: String, txSignature: String) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                UPDATE anchor_batches
                SET anchor_status = 'submitted', anchor_tx_signature = ?
                WHERE id = ?
            """, txSignature, batchID)
        }
    }

    public func markConfirmed(batchID: String) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run(
                "UPDATE anchor_batches SET anchor_status = 'confirmed' WHERE id = ?", batchID)
        }
    }

    public func markFailed(batchID: String) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run(
                "UPDATE anchor_batches SET anchor_status = 'failed' WHERE id = ?", batchID)
        }
    }

    public func listBatches(limit: Int = 20) async throws -> [AnchorBatch] {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT id, merkle_root, entry_count, created_at,
                       anchor_tx_signature, anchor_status
                FROM anchor_batches ORDER BY created_at DESC LIMIT ?
            """, limit)
            return Self.parseBatches(from: stmt)
        }
    }

    public func getBatch(id: String) async throws -> AnchorBatch? {
        try await db.execute { conn -> AnchorBatch? in
            let stmt = try conn.prepare("""
                SELECT id, merkle_root, entry_count, created_at,
                       anchor_tx_signature, anchor_status
                FROM anchor_batches WHERE id = ?
            """, id)
            return Self.parseBatches(from: stmt).first
        }
    }

    private static func parseBatches(from stmt: Statement) -> [AnchorBatch] {
        var results: [AnchorBatch] = []
        for row in stmt {
            results.append(AnchorBatch(
                id: row[0] as! String, merkleRoot: row[1] as! String,
                entryCount: Int(row[2] as! Int64),
                createdAt: swooshParseDate(row[3] as! String),
                anchorTxSignature: row[4] as? String,
                anchorStatus: AnchorStatus(rawValue: row[5] as! String) ?? .pending
            ))
        }
        return results
    }
}

// MARK: - Data hex helper

extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

extension DataProtocol {
    /// Hex-encoded string representation (lowercase, no prefix).
    var hexString: String {
        self.map { b -> String in
            let hi = (b >> 4) & 0x0F
            let lo = b & 0x0F
            let chars: [Character] = [hexChar(hi), hexChar(lo)]
            return String(chars)
        }.joined()
    }
}

private func hexChar(_ nibble: UInt8) -> Character {
    nibble < 10 ? Character(UnicodeScalar(0x30 + nibble)) : Character(UnicodeScalar(0x57 + nibble))
}

