// SwooshToolsets/JupiterRecurringDepositTools.swift
// Jupiter DCA price-triggered deposit and withdraw.
// These modify collateral on an active price-DCA order.
// Both require wallet bridge + askEveryTime approval.

import Foundation
import SwooshTools
import JupSwift

// MARK: - Price DCA deposit

public struct JupiterPriceDepositInput: Codable, Sendable {
    /// Order key of the existing price-DCA order
    public let orderKey: String
    /// Amount in lamports to deposit into the order's collateral
    public let amountLamports: UInt64
    public let walletSessionID: String
    public init(orderKey: String, amountLamports: UInt64, walletSessionID: String) {
        self.orderKey = orderKey
        self.amountLamports = amountLamports
        self.walletSessionID = walletSessionID
    }
}

public struct JupiterPriceDepositOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterPriceDepositTool: SwooshTool {
    public typealias Input = JupiterPriceDepositInput
    public typealias Output = JupiterPriceDepositOutput
    public static let name: ToolName = "jupiter.dca.price_deposit"
    public static let displayName = "Jupiter DCA Price Deposit"
    public static let description = "Deposit additional collateral into a Jupiter price-DCA order"
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let wallet = dependencies.walletBridge else {
            throw ToolError.executionFailed("No wallet bridge — connect a Solana wallet first")
        }
        let accounts = try await wallet.solanaAccounts(sessionID: input.walletSessionID)
        guard let user = accounts.first else {
            throw ToolError.executionFailed("No Solana accounts in session \(input.walletSessionID)")
        }
        let resp = try await JupiterApi.priceDeposit(
            order: input.orderKey,
            user: user.base58,
            amount: input.amountLamports
        )
        return JupiterPriceDepositOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}

// MARK: - Price DCA withdraw

public struct JupiterPriceWithdrawInput: Codable, Sendable {
    public let orderKey: String
    public let amountLamports: UInt64
    public let walletSessionID: String
    public init(orderKey: String, amountLamports: UInt64, walletSessionID: String) {
        self.orderKey = orderKey
        self.amountLamports = amountLamports
        self.walletSessionID = walletSessionID
    }
}

public struct JupiterPriceWithdrawOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterPriceWithdrawTool: SwooshTool {
    public typealias Input = JupiterPriceWithdrawInput
    public typealias Output = JupiterPriceWithdrawOutput
    public static let name: ToolName = "jupiter.dca.price_withdraw"
    public static let displayName = "Jupiter DCA Price Withdraw"
    public static let description = "Withdraw collateral from a Jupiter price-DCA order"
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let wallet = dependencies.walletBridge else {
            throw ToolError.executionFailed("No wallet bridge — connect a Solana wallet first")
        }
        let accounts = try await wallet.solanaAccounts(sessionID: input.walletSessionID)
        guard let user = accounts.first else {
            throw ToolError.executionFailed("No Solana accounts in session \(input.walletSessionID)")
        }
        let resp = try await JupiterApi.priceWithdraw(
            order: input.orderKey,
            user: user.base58,
            amount: input.amountLamports
        )
        return JupiterPriceWithdrawOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}
