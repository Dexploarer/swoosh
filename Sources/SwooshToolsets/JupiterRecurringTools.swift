// SwooshToolsets/JupiterRecurringTools.swift
// Jupiter DCA (Recurring) tools.
// Supports time-based DCA and price-triggered accumulation.
// Create/cancel = askEveryTime; list = read-only.

import Foundation
import SwooshTools

// MARK: - Create DCA (time-based)

public struct JupiterCreateDCAInput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let inAmountPerCycle: UInt64   // lamports per swap cycle
    public let intervalSeconds: UInt64    // seconds between each cycle
    public let numberOfOrders: UInt64     // how many cycles
    public let minPriceUSD: Double?       // skip cycle if price below this
    public let maxPriceUSD: Double?       // skip cycle if price above this
    public let walletSessionID: String
    public init(inputMint: String, outputMint: String, inAmountPerCycle: UInt64,
                intervalSeconds: UInt64, numberOfOrders: UInt64,
                minPriceUSD: Double? = nil, maxPriceUSD: Double? = nil,
                walletSessionID: String) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.inAmountPerCycle = inAmountPerCycle; self.intervalSeconds = intervalSeconds
        self.numberOfOrders = numberOfOrders; self.minPriceUSD = minPriceUSD
        self.maxPriceUSD = maxPriceUSD; self.walletSessionID = walletSessionID
    }
}

public struct JupiterCreateDCAOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterCreateDCATool: SwooshTool {
    public typealias Input = JupiterCreateDCAInput
    public typealias Output = JupiterCreateDCAOutput
    public static let name: ToolName = "jupiter.dca.create"
    public static let displayName = "Jupiter Create DCA"
    public static let description = "Create a Jupiter DCA (dollar-cost averaging) recurring order"
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
        let params = RecurringParams.time(TimeParams(
            inAmount: input.inAmountPerCycle,
            interval: input.intervalSeconds,
            maxPrice: input.maxPriceUSD,
            minPrice: input.minPriceUSD,
            numberOfOrders: input.numberOfOrders
        ))
        let resp = try await JupiterApi.createRecurringOrder(
            inputMint: input.inputMint, outputMint: input.outputMint,
            params: params, user: user.base58
        )
        return JupiterCreateDCAOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}

// MARK: - List DCA orders

public struct JupiterListDCAInput: Codable, Sendable {
    public let userAddress: SolanaPubkey
    public let status: String       // "active" | "history"
    public let recurringType: String // "time" | "price"
    public init(userAddress: SolanaPubkey, status: String = "active", recurringType: String = "time") {
        self.userAddress = userAddress; self.status = status; self.recurringType = recurringType
    }
}

public struct JupiterDCASummary: Codable, Sendable {
    public let orderKey: String
    public let inputMint: String
    public let outputMint: String
    public let inAmountPerCycle: String
    public let cycleFrequency: String
    public let inUsed: String
    public let outReceived: String
    public let createdAt: String
    public let recurringType: String
}

public struct JupiterListDCAOutput: Codable, Sendable {
    public let orders: [JupiterDCASummary]
    public let totalItems: Int
}

public struct JupiterListDCATool: SwooshTool {
    public typealias Input = JupiterListDCAInput
    public typealias Output = JupiterListDCAOutput
    public static let name: ToolName = "jupiter.dca.list"
    public static let displayName = "Jupiter List DCA Orders"
    public static let description = "List active or historical Jupiter DCA orders for a wallet"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let status: OrderStatus = input.status == "active" ? .active : .history
        let type: RecurringType = input.recurringType == "price" ? .price : .time
        let resp = try await JupiterApi.getRecurringOrders(
            account: input.userAddress.base58,
            orderStatus: status,
            recurringType: type
        )
        let orders = resp.all.map { o in
            JupiterDCASummary(
                orderKey: o.orderKey, inputMint: o.inputMint, outputMint: o.outputMint,
                inAmountPerCycle: o.inAmountPerCycle, cycleFrequency: o.cycleFrequency,
                inUsed: o.inUsed, outReceived: o.outReceived,
                createdAt: o.createdAt, recurringType: o.recurringType
            )
        }
        return JupiterListDCAOutput(orders: orders, totalItems: resp.totalItems)
    }
}

// MARK: - Cancel DCA order

public struct JupiterCancelDCAInput: Codable, Sendable {
    public let orderKey: String
    public let recurringType: String // "time" | "price"
    public let walletSessionID: String
    public init(orderKey: String, recurringType: String = "time", walletSessionID: String) {
        self.orderKey = orderKey; self.recurringType = recurringType; self.walletSessionID = walletSessionID
    }
}

public struct JupiterCancelDCAOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
}

public struct JupiterCancelDCATool: SwooshTool {
    public typealias Input = JupiterCancelDCAInput
    public typealias Output = JupiterCancelDCAOutput
    public static let name: ToolName = "jupiter.dca.cancel"
    public static let displayName = "Jupiter Cancel DCA"
    public static let description = "Cancel a Jupiter DCA order — builds unsigned cancellation tx"
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
        let resp = try await JupiterApi.cancelRecurringOrder(
            order: input.orderKey, user: user.base58, recurringType: input.recurringType
        )
        return JupiterCancelDCAOutput(
            requestId: resp.requestId,
            unsignedTransactionBase64: resp.transaction
        )
    }
}
