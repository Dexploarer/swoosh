// SwooshClient/WireTypes+Rebates.swift — Rebate claim API wire types — 0.9S

import Foundation

// MARK: - Rebate summary

/// Response body for `GET /api/rebates/:wallet`.
public struct RebateSummaryResponse: Codable, Sendable {
    public let walletAddress: String
    public let period: String
    public let totalReceipts: Int
    public let anchoredReceipts: Int
    public let totalRebateAmount: Double
    public let records: [RebateRecordWire]

    public init(
        walletAddress: String,
        period: String,
        totalReceipts: Int,
        anchoredReceipts: Int,
        totalRebateAmount: Double,
        records: [RebateRecordWire] = []
    ) {
        self.walletAddress = walletAddress
        self.period = period
        self.totalReceipts = totalReceipts
        self.anchoredReceipts = anchoredReceipts
        self.totalRebateAmount = totalRebateAmount
        self.records = records
    }
}

public struct RebateRecordWire: Codable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let toolsetID: String
    public let anchorBatchID: String?
    public let rebateAmount: Double?
    public let createdAt: Date

    public init(
        id: String,
        toolName: String,
        toolsetID: String,
        anchorBatchID: String?,
        rebateAmount: Double?,
        createdAt: Date
    ) {
        self.id = id
        self.toolName = toolName
        self.toolsetID = toolsetID
        self.anchorBatchID = anchorBatchID
        self.rebateAmount = rebateAmount
        self.createdAt = createdAt
    }
}

// MARK: - Anchor batches

/// Response body for `GET /api/rebates/batches`.
public struct AnchorBatchesResponse: Codable, Sendable {
    public let batches: [AnchorBatchWire]

    public init(batches: [AnchorBatchWire] = []) {
        self.batches = batches
    }
}

public struct AnchorBatchWire: Codable, Sendable, Identifiable {
    public let id: String
    public let merkleRoot: String
    public let entryCount: Int
    public let anchorTxSignature: String?
    public let anchorStatus: String
    public let createdAt: Date

    public init(
        id: String,
        merkleRoot: String,
        entryCount: Int,
        anchorTxSignature: String?,
        anchorStatus: String,
        createdAt: Date
    ) {
        self.id = id
        self.merkleRoot = merkleRoot
        self.entryCount = entryCount
        self.anchorTxSignature = anchorTxSignature
        self.anchorStatus = anchorStatus
        self.createdAt = createdAt
    }
}
