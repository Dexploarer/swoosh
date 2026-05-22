// SwooshToolsets/JupiterMarketTools.swift
// Jupiter Price + Token market-data tools — all read-only, no approval needed.
// Backed by Jupiter's Price and Token API groups.

import Foundation
import SwooshTools

// MARK: - Price tools

public struct JupiterPriceInput: Codable, Sendable {
    /// Comma-separated token mint addresses or symbols (e.g. "SOL,JUP,USDC")
    public let tokenIds: String
    /// Include swap depth / confidence level metadata
    public let includeExtraInfo: Bool
    public init(tokenIds: String, includeExtraInfo: Bool = false) {
        self.tokenIds = tokenIds
        self.includeExtraInfo = includeExtraInfo
    }
}

public struct JupiterPriceOutput: Codable, Sendable {
    public struct TokenPrice: Codable, Sendable {
        public let id: String
        public let priceUSD: String
        public let confidenceLevel: String?
    }
    public let prices: [String: TokenPrice]
    public let timeTakenMs: Double
}

public struct JupiterPriceTool: SwooshTool {
    public typealias Input = JupiterPriceInput
    public typealias Output = JupiterPriceOutput
    public static let name: ToolName = "jupiter.price"
    public static let displayName = "Jupiter Price"
    public static let description = "Get USD prices for one or more Solana tokens via Jupiter"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let response = try await JupiterApi.prices(ids: input.tokenIds)
        var prices: [String: JupiterPriceOutput.TokenPrice] = [:]
        for (key, value) in response {
            guard let usdPrice = value.usdPrice else {
                continue
            }
            prices[key] = JupiterPriceOutput.TokenPrice(
                id: key,
                priceUSD: String(usdPrice),
                confidenceLevel: nil
            )
        }
        return JupiterPriceOutput(prices: prices, timeTakenMs: 0)
    }
}

// MARK: - Token info tools

public struct JupiterTokenInfoInput: Codable, Sendable {
    public let mint: String
    public init(mint: String) { self.mint = mint }
}

public struct JupiterTokenInfoOutput: Codable, Sendable {
    public let address: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let logoURI: String?
    public let tags: [String]
    public let dailyVolumeUSD: Double?
    public let isFrozen: Bool
}

public struct JupiterTokenInfoTool: SwooshTool {
    public typealias Input = JupiterTokenInfoInput
    public typealias Output = JupiterTokenInfoOutput
    public static let name: ToolName = "jupiter.token_info"
    public static let displayName = "Jupiter Token Info"
    public static let description = "Get metadata for a Solana token by mint address"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.token(mint: input.mint)
        return JupiterTokenInfoOutput(
            address: resp.address,
            name: resp.name,
            symbol: resp.symbol,
            decimals: resp.decimals,
            logoURI: resp.logoURI,
            tags: resp.tags ?? [],
            dailyVolumeUSD: resp.dailyVolume,
            isFrozen: resp.freezeAuthority != nil
        )
    }
}

public struct JupiterTradableTokensInput: Codable, Sendable {
    public init() {}
}
public struct JupiterTradableTokensOutput: Codable, Sendable {
    public let mints: [String]
    public let count: Int
}

public struct JupiterTradableTokensTool: SwooshTool {
    public typealias Input = JupiterTradableTokensInput
    public typealias Output = JupiterTradableTokensOutput
    public static let name: ToolName = "jupiter.tradable_tokens"
    public static let displayName = "Jupiter Tradable Tokens"
    public static let description = "Get the list of all tokens tradable on Jupiter"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let mints = try await JupiterApi.tradableTokens()
        return JupiterTradableTokensOutput(mints: mints, count: mints.count)
    }
}
