// SwooshToolsets/JupiterTokenTools.swift
// Jupiter Token API — metadata, discovery, and market lookups.
// All read-only, no approval needed.

import Foundation
import SwooshTools
import JupSwift

// MARK: - Shared output types

public struct JupiterTokenInfo: Codable, Sendable {
    public let address: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let logoURI: String?
    public let tags: [String]
    public let dailyVolumeUSD: Double?
    public let hasFreeze: Bool    // freeze authority present
    public let hasMint: Bool      // mint authority present
}

private func toInfo(_ r: TokenInfoResponse) -> JupiterTokenInfo {
    JupiterTokenInfo(
        address: r.address, name: r.name, symbol: r.symbol, decimals: r.decimals,
        logoURI: r.logoURI, tags: r.tags ?? [], dailyVolumeUSD: r.dailyVolume,
        hasFreeze: r.freezeAuthority != nil, hasMint: r.mintAuthority != nil
    )
}

// MARK: - Tagged tokens (e.g. "lst", "meme", "verified")

public struct JupiterTaggedTokensInput: Codable, Sendable {
    /// Jupiter token tag, e.g. "lst", "meme", "strict", "verified"
    public let tag: String
    public init(tag: String) { self.tag = tag }
}

public struct JupiterTaggedTokensOutput: Codable, Sendable {
    public let tokens: [JupiterTokenInfo]
    public let count: Int
}

public struct JupiterTaggedTokensTool: SwooshTool {
    public typealias Input = JupiterTaggedTokensInput
    public typealias Output = JupiterTaggedTokensOutput
    public static let name: ToolName = "jupiter.tokens.tagged"
    public static let displayName = "Jupiter Tagged Tokens"
    public static let description = "Get all Jupiter tokens with a specific tag (e.g. 'lst', 'meme', 'strict')"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.taggedTokens(for: input.tag)
        let tokens = resp.map(toInfo)
        return JupiterTaggedTokensOutput(tokens: tokens, count: tokens.count)
    }
}

// MARK: - New tokens

public struct JupiterNewTokensInput: Codable, Sendable {
    public init() {}
}

public struct JupiterNewTokenInfo: Codable, Sendable {
    public let mint: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let logoURI: String?
    public let createdAt: String
    public let knownMarkets: [String]
    public let hasFreeze: Bool
    public let hasMint: Bool
}

public struct JupiterNewTokensOutput: Codable, Sendable {
    public let tokens: [JupiterNewTokenInfo]
    public let count: Int
}

public struct JupiterNewTokensTool: SwooshTool {
    public typealias Input = JupiterNewTokensInput
    public typealias Output = JupiterNewTokensOutput
    public static let name: ToolName = "jupiter.tokens.new"
    public static let displayName = "Jupiter New Tokens"
    public static let description = "Get recently listed tokens on Jupiter"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.newTokens()
        let tokens = resp.map { t in
            JupiterNewTokenInfo(
                mint: t.mint, name: t.name, symbol: t.symbol, decimals: t.decimals,
                logoURI: t.logoURI, createdAt: t.createdAt, knownMarkets: t.knownMarkets,
                hasFreeze: t.freezeAuthority != nil, hasMint: t.mintAuthority != nil
            )
        }
        return JupiterNewTokensOutput(tokens: tokens, count: tokens.count)
    }
}

// MARK: - Market mints (tokens in a specific liquidity pool)

public struct JupiterMarketMintsInput: Codable, Sendable {
    /// Market/pool address
    public let market: String
    public init(market: String) { self.market = market }
}

public struct JupiterMarketMintsOutput: Codable, Sendable {
    public let mints: [String]
    public let count: Int
}

public struct JupiterMarketMintsTool: SwooshTool {
    public typealias Input = JupiterMarketMintsInput
    public typealias Output = JupiterMarketMintsOutput
    public static let name: ToolName = "jupiter.tokens.market_mints"
    public static let displayName = "Jupiter Market Mints"
    public static let description = "Get token mint addresses in a specific Jupiter liquidity market"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let mints = try await JupiterApi.market(market: input.market)
        return JupiterMarketMintsOutput(mints: mints, count: mints.count)
    }
}

// MARK: - All tokens (paginated by caller — returns full list)

public struct JupiterAllTokensInput: Codable, Sendable {
    /// Max tokens to return (default 200, max 2000 to avoid memory pressure)
    public let limit: Int
    public init(limit: Int = 200) { self.limit = max(1, min(limit, 2000)) }
}

public struct JupiterAllTokensOutput: Codable, Sendable {
    public let tokens: [JupiterTokenInfo]
    public let total: Int
    public let truncated: Bool
}

public struct JupiterAllTokensTool: SwooshTool {
    public typealias Input = JupiterAllTokensInput
    public typealias Output = JupiterAllTokensOutput
    public static let name: ToolName = "jupiter.tokens.all"
    public static let displayName = "Jupiter All Tokens"
    public static let description = "Get the full Jupiter token list (use limit to control response size)"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.allTokens()
        let total = resp.count
        let slice = Array(resp.prefix(input.limit))
        return JupiterAllTokensOutput(
            tokens: slice.map(toInfo),
            total: total,
            truncated: slice.count < total
        )
    }
}
