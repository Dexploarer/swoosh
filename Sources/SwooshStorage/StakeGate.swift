// SwooshStorage/StakeGate.swift — Stake-to-act gating — 0.9S

import Foundation
import SQLite
import SwooshTools

// MARK: - Stake config

public struct StakeGateConfig: Codable, Sendable {
    public let requirements: [String: Double]

    public init(requirements: [String: Double]) {
        self.requirements = requirements
    }

    public static let `default` = StakeGateConfig(requirements: [
        "hyperliquidTrade": 1000, "evmBuildTransaction": 500,
        "solanaSubmitTransaction": 500, "uniswap": 500, "launchpads": 500
    ])
}

// MARK: - Stake record

public struct StakeRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let walletAddress: String
    public let tokenMint: String
    public let amountStaked: Double
    public let toolsetID: String
    public let stakedAt: Date
    public var releasedAt: Date?
    public var status: StakeStatus

    public init(
        id: String = UUID().uuidString, walletAddress: String, tokenMint: String,
        amountStaked: Double, toolsetID: String, stakedAt: Date = Date(),
        releasedAt: Date? = nil, status: StakeStatus = .active
    ) {
        self.id = id; self.walletAddress = walletAddress; self.tokenMint = tokenMint
        self.amountStaked = amountStaked; self.toolsetID = toolsetID
        self.stakedAt = stakedAt; self.releasedAt = releasedAt; self.status = status
    }
}

public enum StakeStatus: String, Codable, Sendable {
    case active, released, slashed
}

// MARK: - Stake gate actor

public actor StakeGateActor: StakeGating {
    private let db: SwooshDatabase
    private let config: StakeGateConfig

    public init(db: SwooshDatabase, config: StakeGateConfig = .default) {
        self.db = db
        self.config = config
    }

    /// Check if a wallet has sufficient stake for a toolset.
    public func requireStake(wallet: String, toolsetID: String) async throws {
        guard let required = config.requirements[toolsetID] else { return }
        let current = try await activeStake(wallet: wallet, toolsetID: toolsetID)
        if current < required {
            throw ToolError.denied(
                toolsetID,
                "Insufficient stake for \(toolsetID): need \(required), have \(current)")
        }
    }

    /// Record a new stake.
    public func recordStake(
        wallet: String, tokenMint: String, amount: Double, toolsetID: String
    ) async throws -> String {
        let id = UUID().uuidString
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO stake_ledger
                    (id, wallet_address, token_mint, amount_staked, toolset_id, staked_at, status)
                VALUES (?, ?, ?, ?, ?, ?, 'active')
            """, id, wallet, tokenMint, amount, toolsetID, now)
        }
        return id
    }

    /// Release a stake (return tokens).
    public func releaseStake(stakeID: String) async throws {
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                UPDATE stake_ledger SET status = 'released', released_at = ?
                WHERE id = ? AND status = 'active'
            """, now, stakeID)
            if conn.changes == 0 { throw ToolError.notFound(stakeID) }
        }
    }

    /// Slash a stake (penalty for violations).
    public func slashStake(stakeID: String) async throws {
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                UPDATE stake_ledger SET status = 'slashed', released_at = ?
                WHERE id = ? AND status = 'active'
            """, now, stakeID)
            if conn.changes == 0 { throw ToolError.notFound(stakeID) }
        }
    }

    /// Get total active stake for a wallet + toolset.
    public func activeStake(wallet: String, toolsetID: String) async throws -> Double {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT COALESCE(SUM(amount_staked), 0) FROM stake_ledger
                WHERE wallet_address = ? AND toolset_id = ? AND status = 'active'
            """, wallet, toolsetID)
            for row in stmt { return swooshDouble(row[0]) }
            return 0
        }
    }

    /// List all active stakes for a wallet.
    public func listActiveStakes(wallet: String) async throws -> [StakeRecord] {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT id, wallet_address, token_mint, amount_staked, toolset_id,
                       staked_at, released_at, status
                FROM stake_ledger WHERE wallet_address = ? AND status = 'active'
                ORDER BY staked_at DESC
            """, wallet)
            var results: [StakeRecord] = []
            for row in stmt {
                results.append(StakeRecord(
                    id: row[0] as! String, walletAddress: row[1] as! String,
                    tokenMint: row[2] as! String, amountStaked: swooshDouble(row[3]),
                    toolsetID: row[4] as! String,
                    stakedAt: swooshParseDate(row[5] as! String),
                    releasedAt: (row[6] as? String).map(swooshParseDate),
                    status: StakeStatus(rawValue: row[7] as! String) ?? .active
                ))
            }
            return results
        }
    }
}
