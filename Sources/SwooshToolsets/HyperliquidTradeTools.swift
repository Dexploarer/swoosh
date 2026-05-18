// SwooshToolsets/HyperliquidTradeTools.swift
// Hyperliquid trading tools — order placement, cancel, modify, account management.
// Security model: HyperliquidClient requires a private key. We load it from
// SwooshSecrets (Keychain) via a secret ref — it never appears in tool inputs.
// All write ops are askEveryTime. Transfers/withdrawals are critical.

import Foundation
import SwooshTools
import HyperliquidSwift

// MARK: - Shared authenticated client builder

/// Builds an authenticated HyperliquidClient from a Keychain secret ref.
/// The private key hex is read from the Keychain at call time, never stored in memory longer than needed.
func hyperliquidAuthClient(
    secretRef: String,
    testnet: Bool,
    secrets: any SecretResolving
) async throws -> HyperliquidClient {
    let keyHex = try await secrets.resolve(ref: secretRef)
    guard !keyHex.isEmpty else {
        throw ToolError.executionFailed("Hyperliquid private key not found in Keychain (ref: \(secretRef))")
    }
    return try HyperliquidClient(privateKeyHex: keyHex, environment: testnet ? .testnet : .mainnet)
}

// MARK: - Place limit order

public struct HLLimitOrderInput: Codable, Sendable {
    public let coin: String
    public let isBuy: Bool
    public let size: Decimal
    public let limitPrice: Decimal
    public let reduceOnly: Bool
    public let privateKeySecretRef: String   // Keychain ref, e.g. "hyperliquid.mainnet.pk"
    public let testnet: Bool
    public init(coin: String, isBuy: Bool, size: Decimal, limitPrice: Decimal,
                reduceOnly: Bool = false, privateKeySecretRef: String, testnet: Bool = false) {
        self.coin = coin; self.isBuy = isBuy; self.size = size; self.limitPrice = limitPrice
        self.reduceOnly = reduceOnly; self.privateKeySecretRef = privateKeySecretRef; self.testnet = testnet
    }
}

public struct HLOrderOutput: Codable, Sendable {
    public let status: String
    public let statuses: [String]
}

public struct HLLimitOrderTool: SwooshTool {
    public typealias Input = HLLimitOrderInput
    public typealias Output = HLOrderOutput
    public static let name: ToolName = "hyperliquid.limit_order"
    public static let displayName = "Hyperliquid Limit Order"
    public static let description = "Place a limit order on Hyperliquid perp or spot market"
    public static let permission = SwooshPermission.hyperliquidTrade
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try await hyperliquidAuthClient(
            secretRef: input.privateKeySecretRef, testnet: input.testnet,
            secrets: dependencies.secrets
        )
        let resp = input.isBuy
            ? try await client.limitBuy(coin: input.coin, sz: input.size, px: input.limitPrice, reduceOnly: input.reduceOnly)
            : try await client.limitSell(coin: input.coin, sz: input.size, px: input.limitPrice, reduceOnly: input.reduceOnly)
        return HLOrderOutput(
            status: resp.dictionary["status"] as? String ?? "ok",
            statuses: (resp.dictionary["statuses"] as? [Any])?.compactMap { "\($0)" } ?? []
        )
    }
}

// MARK: - Place market order

public struct HLMarketOrderInput: Codable, Sendable {
    public let coin: String
    public let isBuy: Bool
    public let size: Decimal
    public let slippage: Decimal
    public let reduceOnly: Bool
    public let privateKeySecretRef: String
    public let testnet: Bool
    public init(coin: String, isBuy: Bool, size: Decimal, slippage: Decimal = 0.05,
                reduceOnly: Bool = false, privateKeySecretRef: String, testnet: Bool = false) {
        self.coin = coin; self.isBuy = isBuy; self.size = size; self.slippage = slippage
        self.reduceOnly = reduceOnly; self.privateKeySecretRef = privateKeySecretRef; self.testnet = testnet
    }
}

public struct HLMarketOrderTool: SwooshTool {
    public typealias Input = HLMarketOrderInput
    public typealias Output = HLOrderOutput
    public static let name: ToolName = "hyperliquid.market_order"
    public static let displayName = "Hyperliquid Market Order"
    public static let description = "Place a market order on Hyperliquid (fills immediately at best available price)"
    public static let permission = SwooshPermission.hyperliquidTrade
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try await hyperliquidAuthClient(
            secretRef: input.privateKeySecretRef, testnet: input.testnet,
            secrets: dependencies.secrets
        )
        let resp = input.isBuy
            ? try await client.marketBuy(coin: input.coin, sz: input.size, slippage: input.slippage, reduceOnly: input.reduceOnly)
            : try await client.marketSell(coin: input.coin, sz: input.size, slippage: input.slippage, reduceOnly: input.reduceOnly)
        return HLOrderOutput(
            status: resp.dictionary["status"] as? String ?? "ok",
            statuses: (resp.dictionary["statuses"] as? [Any])?.compactMap { "\($0)" } ?? []
        )
    }
}

// MARK: - Cancel order

public struct HLCancelOrderInput: Codable, Sendable {
    public let coin: String
    public let oid: UInt64
    public let privateKeySecretRef: String
    public let testnet: Bool
    public init(coin: String, oid: UInt64, privateKeySecretRef: String, testnet: Bool = false) {
        self.coin = coin; self.oid = oid; self.privateKeySecretRef = privateKeySecretRef; self.testnet = testnet
    }
}

public struct HLCancelOutput: Codable, Sendable {
    public let status: String
}

public struct HLCancelOrderTool: SwooshTool {
    public typealias Input = HLCancelOrderInput
    public typealias Output = HLCancelOutput
    public static let name: ToolName = "hyperliquid.cancel_order"
    public static let displayName = "Hyperliquid Cancel Order"
    public static let description = "Cancel a Hyperliquid order by order ID"
    public static let permission = SwooshPermission.hyperliquidTrade
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try await hyperliquidAuthClient(
            secretRef: input.privateKeySecretRef, testnet: input.testnet,
            secrets: dependencies.secrets
        )
        let resp = try await client.cancelOrder(coin: input.coin, oid: input.oid)
        return HLCancelOutput(status: resp.dictionary["status"] as? String ?? "ok")
    }
}

// MARK: - Cancel all orders for a coin

public struct HLCancelAllInput: Codable, Sendable {
    public let coin: String?    // nil = cancel all across all coins
    public let privateKeySecretRef: String
    public let testnet: Bool
    public init(coin: String? = nil, privateKeySecretRef: String, testnet: Bool = false) {
        self.coin = coin; self.privateKeySecretRef = privateKeySecretRef; self.testnet = testnet
    }
}

public struct HLCancelAllTool: SwooshTool {
    public typealias Input = HLCancelAllInput
    public typealias Output = HLCancelOutput
    public static let name: ToolName = "hyperliquid.cancel_all"
    public static let displayName = "Hyperliquid Cancel All"
    public static let description = "Cancel all open orders for a coin (or all coins if coin is nil)"
    public static let permission = SwooshPermission.hyperliquidTrade
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try await hyperliquidAuthClient(
            secretRef: input.privateKeySecretRef, testnet: input.testnet,
            secrets: dependencies.secrets
        )
        let resp = input.coin != nil
            ? try await client.cancelAllOrders(coin: input.coin!)
            : try await client.cancelAllOrders()
        return HLCancelOutput(status: resp.dictionary["status"] as? String ?? "ok")
    }
}

// MARK: - Update leverage

public struct HLUpdateLeverageInput: Codable, Sendable {
    public let coin: String
    public let leverage: Int
    public let isCross: Bool
    public let privateKeySecretRef: String
    public let testnet: Bool
    public init(coin: String, leverage: Int, isCross: Bool = true, privateKeySecretRef: String, testnet: Bool = false) {
        self.coin = coin; self.leverage = leverage; self.isCross = isCross
        self.privateKeySecretRef = privateKeySecretRef; self.testnet = testnet
    }
}

public struct HLUpdateLeverageTool: SwooshTool {
    public typealias Input = HLUpdateLeverageInput
    public typealias Output = HLCancelOutput
    public static let name: ToolName = "hyperliquid.update_leverage"
    public static let displayName = "Hyperliquid Update Leverage"
    public static let description = "Update position leverage for a Hyperliquid market"
    public static let permission = SwooshPermission.hyperliquidTrade
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try await hyperliquidAuthClient(
            secretRef: input.privateKeySecretRef, testnet: input.testnet,
            secrets: dependencies.secrets
        )
        let resp = try await client.updateLeverage(coin: input.coin, leverage: input.leverage, isCross: input.isCross)
        return HLCancelOutput(status: resp.dictionary["status"] as? String ?? "ok")
    }
}
