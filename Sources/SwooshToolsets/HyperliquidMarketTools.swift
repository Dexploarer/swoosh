// SwooshToolsets/HyperliquidMarketTools.swift
// Hyperliquid market data tools — all read-only, no private key, no approval.
// Uses HyperliquidClient(environment:) — the keyless init.

import Foundation
import SwooshTools
import HyperliquidSwift

// MARK: - Shared read-only client factory

enum HyperliquidReadClient {
    static func client(testnet: Bool) throws -> HyperliquidClient {
        try HyperliquidClient(environment: testnet ? .testnet : .mainnet)
    }
}

// MARK: - All mid prices

public struct HLAllMidsInput: Codable, Sendable {
    public let testnet: Bool
    public init(testnet: Bool = false) { self.testnet = testnet }
}

public struct HLAllMidsOutput: Codable, Sendable {
    /// coin → USD price string
    public let prices: [String: String]
}

public struct HLAllMidsTool: SwooshTool {
    public typealias Input = HLAllMidsInput
    public typealias Output = HLAllMidsOutput
    public static let name: ToolName = "hyperliquid.all_mids"
    public static let displayName = "Hyperliquid All Mids"
    public static let description = "Get mid prices for all Hyperliquid markets"
    public static let permission = SwooshPermission.networkRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try HyperliquidReadClient.client(testnet: input.testnet)
        let mids = try await client.getAllMids()
        return HLAllMidsOutput(prices: mids.mapValues { "\($0)" })
    }
}

// MARK: - L2 Order book

public struct HLL2BookInput: Codable, Sendable {
    public let coin: String
    public let testnet: Bool
    public init(coin: String, testnet: Bool = false) { self.coin = coin; self.testnet = testnet }
}

public struct HLL2Level: Codable, Sendable {
    public let px: String
    public let sz: String
    public let n: Int
}

public struct HLL2BookOutput: Codable, Sendable {
    public let coin: String
    public let bids: [HLL2Level]
    public let asks: [HLL2Level]
}

public struct HLL2BookTool: SwooshTool {
    public typealias Input = HLL2BookInput
    public typealias Output = HLL2BookOutput
    public static let name: ToolName = "hyperliquid.l2_book"
    public static let displayName = "Hyperliquid L2 Book"
    public static let description = "Get the L2 order book (bids/asks) for a Hyperliquid market"
    public static let permission = SwooshPermission.networkRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try HyperliquidReadClient.client(testnet: input.testnet)
        let book = try await client.getL2Book(coin: input.coin)
        // levels[0] = bids, levels[1] = asks per Hyperliquid API spec
        let bids = (book.levels.first ?? []).map { HLL2Level(px: $0.px.description, sz: $0.sz.description, n: $0.n) }
        let asks = (book.levels.dropFirst().first ?? []).map { HLL2Level(px: $0.px.description, sz: $0.sz.description, n: $0.n) }
        return HLL2BookOutput(coin: input.coin, bids: bids, asks: asks)
    }
}

// MARK: - User state (portfolio / positions)

public struct HLUserStateInput: Codable, Sendable {
    public let address: String
    public let testnet: Bool
    public init(address: String, testnet: Bool = false) { self.address = address; self.testnet = testnet }
}

public struct HLPosition: Codable, Sendable {
    public let coin: String
    public let szi: String
    public let entryPx: String?
    public let unrealizedPnl: String
    public let leverage: String
    public let marginUsed: String
    public let isLong: Bool
}

public struct HLUserStateOutput: Codable, Sendable {
    public let address: String
    public let accountValue: String
    public let totalMarginUsed: String
    public let positions: [HLPosition]
}

public struct HLUserStateTool: SwooshTool {
    public typealias Input = HLUserStateInput
    public typealias Output = HLUserStateOutput
    public static let name: ToolName = "hyperliquid.user_state"
    public static let displayName = "Hyperliquid User State"
    public static let description = "Get portfolio, positions and margin info for a Hyperliquid address"
    public static let permission = SwooshPermission.networkRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try HyperliquidReadClient.client(testnet: input.testnet)
        let state = try await client.getUserState(address: input.address)
        let positions = state.assetPositions.map { ap in
            HLPosition(
                coin: ap.position.coin,
                szi: ap.position.szi.description,
                entryPx: ap.position.entryPx?.description,
                unrealizedPnl: ap.position.unrealizedPnl.description,
                leverage: ap.position.leverage.description,
                marginUsed: ap.position.marginUsed.description,
                isLong: ap.position.isLong
            )
        }
        return HLUserStateOutput(
            address: input.address,
            accountValue: "\(state.crossMarginSummary.accountValue)",
            totalMarginUsed: "\(state.crossMarginSummary.totalMarginUsed)",
            positions: positions
        )
    }
}

// MARK: - Open orders

public struct HLOpenOrdersInput: Codable, Sendable {
    public let address: String
    public let testnet: Bool
    public init(address: String, testnet: Bool = false) { self.address = address; self.testnet = testnet }
}

public struct HLOpenOrderSummary: Codable, Sendable {
    public let coin: String
    public let oid: UInt64
    public let side: String
    public let limitPx: String
    public let sz: String
    public let origSz: String
    public let timestamp: Int64
}

public struct HLOpenOrdersOutput: Codable, Sendable {
    public let orders: [HLOpenOrderSummary]
}

public struct HLOpenOrdersTool: SwooshTool {
    public typealias Input = HLOpenOrdersInput
    public typealias Output = HLOpenOrdersOutput
    public static let name: ToolName = "hyperliquid.open_orders"
    public static let displayName = "Hyperliquid Open Orders"
    public static let description = "Get open orders for a Hyperliquid address"
    public static let permission = SwooshPermission.networkRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try HyperliquidReadClient.client(testnet: input.testnet)
        let orders = try await client.getOpenOrders(address: input.address)
        let summaries = orders.map { o in
            HLOpenOrderSummary(
                coin: o.coin, oid: o.oid,
                side: o.side == .buy ? "B" : "A",
                limitPx: "\(o.limitPx)", sz: "\(o.sz)",
                origSz: "\(o.origSz)", timestamp: o.timestamp
            )
        }
        return HLOpenOrdersOutput(orders: summaries)
    }
}

// MARK: - User fills (trade history)

public struct HLUserFillsInput: Codable, Sendable {
    public let address: String
    public let testnet: Bool
    public init(address: String, testnet: Bool = false) { self.address = address; self.testnet = testnet }
}

public struct HLFill: Codable, Sendable {
    public let coin: String
    public let side: String
    public let px: String
    public let sz: String
    public let fee: String
    public let closedPnl: String
    public let time: Int64
    public let oid: UInt64
    public let hash: String
}

public struct HLUserFillsOutput: Codable, Sendable {
    public let fills: [HLFill]
}

public struct HLUserFillsTool: SwooshTool {
    public typealias Input = HLUserFillsInput
    public typealias Output = HLUserFillsOutput
    public static let name: ToolName = "hyperliquid.user_fills"
    public static let displayName = "Hyperliquid User Fills"
    public static let description = "Get trade fill history for a Hyperliquid address"
    public static let permission = SwooshPermission.networkRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.hyperliquid

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try HyperliquidReadClient.client(testnet: input.testnet)
        let fills = try await client.getUserFills(address: input.address)
        let mapped = fills.map { f in
            HLFill(
                coin: f.coin, side: f.side == .buy ? "B" : "A",
                px: "\(f.px)", sz: "\(f.sz)", fee: "\(f.fee)",
                closedPnl: "\(f.closedPnl)", time: f.time, oid: f.oid, hash: f.hash
            )
        }
        return HLUserFillsOutput(fills: mapped)
    }
}
