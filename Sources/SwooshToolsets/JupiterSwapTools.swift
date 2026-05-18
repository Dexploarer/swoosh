// SwooshToolsets/JupiterSwapTools.swift
// Jupiter DEX swap tools powered by JupSwift.
// Hard rules: NO private key ingestion. Signing is humanOnly.
// Agent can query routes and build orders; execution requires human approval.

import Foundation
import SwooshTools
import JupSwift

// MARK: - Input/Output types

public struct JupiterQuoteInput: Codable, Sendable {
    public let inputMint: String        // SPL mint address or "SOL"
    public let outputMint: String       // SPL mint address or "SOL"
    public let amountLamports: String   // amount in smallest unit (string to avoid overflow)
    public let slippageBps: Int         // slippage in basis points (e.g. 50 = 0.5%)
    public init(inputMint: String, outputMint: String, amountLamports: String, slippageBps: Int = 50) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.amountLamports = amountLamports; self.slippageBps = slippageBps
    }
}

public struct JupiterQuoteOutput: Codable, Sendable {
    public let inputAmount: String
    public let outputAmount: String
    public let priceImpactPct: Double
    public let marketInfos: [String]
    public let routeLabel: String
}

public struct JupiterOrderInput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let amountLamports: String
    public let takerAddress: SolanaPubkey
    public let slippageBps: Int
    public init(inputMint: String, outputMint: String, amountLamports: String, takerAddress: SolanaPubkey, slippageBps: Int = 50) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.amountLamports = amountLamports; self.takerAddress = takerAddress
        self.slippageBps = slippageBps
    }
}

public struct JupiterOrderOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
    public let inputAmount: String
    public let outputAmount: String
    public let priceImpactPct: Double
    public let expiresAt: Date?
}

public struct JupiterExecuteInput: Codable, Sendable {
    public let requestId: String
    public let signedTransactionBase64: String  // must be human-signed
    public init(requestId: String, signedTransactionBase64: String) {
        self.requestId = requestId; self.signedTransactionBase64 = signedTransactionBase64
    }
}

public struct JupiterExecuteOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public let status: String
}

public struct JupiterBalancesInput: Codable, Sendable {
    public let account: SolanaPubkey
    public init(account: SolanaPubkey) { self.account = account }
}

public struct JupiterBalancesOutput: Codable, Sendable {
    public let tokens: [JupiterTokenBalance]
}

public struct JupiterTokenBalance: Codable, Sendable {
    public let mint: String
    public let symbol: String
    public let uiAmount: Double
    public let usdValue: Double?
}

// MARK: - Tools

/// Get a Jupiter swap quote (read-only, no approval needed)
public struct JupiterQuoteTool: SwooshTool {
    public typealias Input = JupiterQuoteInput
    public typealias Output = JupiterQuoteOutput
    public static let name: ToolName = "jupiter.quote"
    public static let displayName = "Jupiter Quote"
    public static let description = "Get a swap quote from Jupiter DEX aggregator"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await JupiterApi.order(
            inputMint: input.inputMint,
            outputMint: input.outputMint,
            amount: input.amountLamports,
            taker: ""  // empty for quote-only
        )
        return JupiterQuoteOutput(
            inputAmount: input.amountLamports,
            outputAmount: "\(result.outAmount ?? 0)",
            priceImpactPct: result.priceImpactPct ?? 0,
            marketInfos: result.routePlan?.map { $0.swapInfo?.label ?? "unknown" } ?? [],
            routeLabel: result.routePlan?.first?.swapInfo?.label ?? "Jupiter"
        )
    }
}

/// Build a Jupiter swap order (produces unsigned tx, humanOnly to execute)
public struct JupiterBuildOrderTool: SwooshTool {
    public typealias Input = JupiterOrderInput
    public typealias Output = JupiterOrderOutput
    public static let name: ToolName = "jupiter.build_order"
    public static let displayName = "Jupiter Build Order"
    public static let description = "Build an unsigned Jupiter swap transaction for human review"
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await JupiterApi.order(
            inputMint: input.inputMint,
            outputMint: input.outputMint,
            amount: input.amountLamports,
            taker: input.takerAddress.base58
        )
        guard let tx = result.transaction, let reqId = result.requestId else {
            throw ToolError.executionFailed("Jupiter order returned no transaction")
        }
        return JupiterOrderOutput(
            requestId: reqId,
            unsignedTransactionBase64: tx,
            inputAmount: input.amountLamports,
            outputAmount: "\(result.outAmount ?? 0)",
            priceImpactPct: result.priceImpactPct ?? 0,
            expiresAt: nil
        )
    }
}

/// Execute a Jupiter swap — humanOnly, requires pre-signed transaction
public struct JupiterExecuteTool: SwooshTool {
    public typealias Input = JupiterExecuteInput
    public typealias Output = JupiterExecuteOutput
    public static let name: ToolName = "jupiter.execute"
    public static let displayName = "Jupiter Execute Swap"
    public static let description = "Submit a human-signed Jupiter swap transaction to the network"
    public static let permission = SwooshPermission.solanaBroadcast
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.humanOnly
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        return try await withCheckedThrowingContinuation { cont in
            JupiterApi.execute(
                signedTransaction: input.signedTransactionBase64,
                requestId: input.requestId
            ) { result in
                switch result {
                case .success(let resp):
                    cont.resume(returning: JupiterExecuteOutput(
                        signature: SolanaSignature(resp.signature ?? ""),
                        status: resp.status ?? "submitted"
                    ))
                case .failure(let error):
                    cont.resume(throwing: ToolError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
}

/// Get Jupiter token balances for a wallet
public struct JupiterBalancesTool: SwooshTool {
    public typealias Input = JupiterBalancesInput
    public typealias Output = JupiterBalancesOutput
    public static let name: ToolName = "jupiter.balances"
    public static let displayName = "Jupiter Balances"
    public static let description = "Get all token balances for a Solana address via Jupiter"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await JupiterApi.balances(account: input.account.base58)
        let tokens = result.tokens?.map { t in
            JupiterTokenBalance(
                mint: t.mint ?? "",
                symbol: t.symbol ?? "?",
                uiAmount: t.uiAmount ?? 0,
                usdValue: t.usdValue
            )
        } ?? []
        return JupiterBalancesOutput(tokens: tokens)
    }
}
