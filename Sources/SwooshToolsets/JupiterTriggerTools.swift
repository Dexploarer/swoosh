// SwooshToolsets/JupiterTriggerTools.swift
// Jupiter limit-order (Trigger) tools.
// Create = askEveryTime, cancel = askEveryTime, read = never.

import Foundation
import SwooshTools

// MARK: - Create limit order

public struct JupiterCreateLimitOrderInput: Codable, Sendable {
    public let inputMint: String     // token to sell
    public let outputMint: String    // token to buy
    public let makingAmount: String  // amount to sell (base units)
    public let takingAmount: String  // amount to receive (base units)
    public let walletSessionID: String
    public init(inputMint: String, outputMint: String, makingAmount: String,
                takingAmount: String, walletSessionID: String) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.makingAmount = makingAmount; self.takingAmount = takingAmount
        self.walletSessionID = walletSessionID
    }
}

public struct JupiterCreateLimitOrderOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterCreateLimitOrderTool: SwooshTool {
    public typealias Input = JupiterCreateLimitOrderInput
    public typealias Output = JupiterCreateLimitOrderOutput
    public static let name: ToolName = "jupiter.limit_order.create"
    public static let displayName = "Jupiter Create Limit Order"
    public static let description = "Create a Jupiter limit order (trigger order) — builds unsigned tx"
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
        guard let payer = accounts.first else {
            throw ToolError.executionFailed("No Solana accounts in session \(input.walletSessionID)")
        }
        let resp = try await JupiterApi.createOrder(
            inputMint: input.inputMint, outputMint: input.outputMint,
            makingAmount: input.makingAmount, takingAmount: input.takingAmount,
            payer: payer.base58
        )
        return JupiterCreateLimitOrderOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}

// MARK: - Get active/history limit orders

public struct JupiterGetLimitOrdersInput: Codable, Sendable {
    public let userAddress: SolanaPubkey
    public let status: String // "active" | "history"
    public init(userAddress: SolanaPubkey, status: String = "active") {
        self.userAddress = userAddress; self.status = status
    }
}

public struct JupiterLimitOrderSummary: Codable, Sendable {
    public let orderKey: String
    public let inputMint: String
    public let outputMint: String
    public let makingAmount: String
    public let takingAmount: String
    public let remainingMaking: String
    public let status: String
    public let createdAt: String
}

public struct JupiterGetLimitOrdersOutput: Codable, Sendable {
    public let orders: [JupiterLimitOrderSummary]
    public let totalItems: Int?
}

public struct JupiterGetLimitOrdersTool: SwooshTool {
    public typealias Input = JupiterGetLimitOrdersInput
    public typealias Output = JupiterGetLimitOrdersOutput
    public static let name: ToolName = "jupiter.limit_order.list"
    public static let displayName = "Jupiter List Limit Orders"
    public static let description = "List active or historical Jupiter limit orders for a wallet"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = input.status == "active"
            ? try await JupiterApi.getActiveTriggerOrders(user: input.userAddress.base58)
            : try await JupiterApi.getHistoryTriggerOrders(user: input.userAddress.base58)
        let orders = resp.orders.map { o in
            JupiterLimitOrderSummary(
                orderKey: o.orderKey, inputMint: o.inputMint, outputMint: o.outputMint,
                makingAmount: o.makingAmount, takingAmount: o.takingAmount,
                remainingMaking: o.remainingMakingAmount, status: o.status,
                createdAt: o.createdAt
            )
        }
        return JupiterGetLimitOrdersOutput(orders: orders, totalItems: resp.totalItems)
    }
}

// MARK: - Cancel limit order

public struct JupiterCancelLimitOrderInput: Codable, Sendable {
    public let orderKey: String
    public let walletSessionID: String
    public init(orderKey: String, walletSessionID: String) {
        self.orderKey = orderKey; self.walletSessionID = walletSessionID
    }
}

public struct JupiterCancelLimitOrderOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterCancelLimitOrderTool: SwooshTool {
    public typealias Input = JupiterCancelLimitOrderInput
    public typealias Output = JupiterCancelLimitOrderOutput
    public static let name: ToolName = "jupiter.limit_order.cancel"
    public static let displayName = "Jupiter Cancel Limit Order"
    public static let description = "Cancel a Jupiter limit order — builds unsigned cancellation tx"
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
        guard let maker = accounts.first else {
            throw ToolError.executionFailed("No Solana accounts in session \(input.walletSessionID)")
        }
        let resp = try await JupiterApi.cancelTriggerOrder(
            maker: maker.base58, order: input.orderKey
        )
        return JupiterCancelLimitOrderOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}
