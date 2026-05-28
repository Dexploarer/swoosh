// SwooshStorage/ReceiptTrackingActor.swift — Composite receipt tracker — 0.9S
//
// Bridges the ReceiptTracking protocol (defined in SwooshTools) to the
// concrete RebateTracker. Called by ToolRegistry after every successful
// crypto tool call to record the receipt for rebate accounting and
// future on-chain anchoring.

import Foundation
import SwooshTools

public actor ReceiptTrackingActor: ReceiptTracking {
    private let rebateTracker: RebateTracker

    public init(rebateTracker: RebateTracker) {
        self.rebateTracker = rebateTracker
    }

    public func trackReceipt(
        auditEntryID: String,
        toolName: String,
        toolsetID: String,
        wallet: String
    ) async throws {
        try await rebateTracker.recordEligible(
            walletAddress: wallet,
            auditEntryID: auditEntryID,
            toolName: toolName,
            toolsetID: toolsetID
        )
    }
}
