// SwooshToolsets/JupiterSwapTools.swift
// Jupiter DEX swap tools.
// Hard rules: NO private key ingestion — signing flows through WalletBridge only.

import Foundation
import SwooshTools

// MARK: - Input/Output types

public struct JupiterQuoteInput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let amountLamports: String
    public let slippageBps: Int
    public init(inputMint: String, outputMint: String, amountLamports: String, slippageBps: Int = 50) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.amountLamports = amountLamports; self.slippageBps = slippageBps
    }
}

public struct JupiterQuoteOutput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let inAmount: String
    public let outAmount: String
    public let priceImpactPct: String
    public let slippageBps: Int
    public let routeLabel: String
    public let feeLamports: Int
}

/// Full end-to-end swap: quote → build → sign (via WalletBridge) → broadcast
public struct JupiterSwapInput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let amountLamports: String
    public let walletSessionID: String
    public let slippageBps: Int
    public init(inputMint: String, outputMint: String, amountLamports: String,
                walletSessionID: String, slippageBps: Int = 50) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.amountLamports = amountLamports; self.walletSessionID = walletSessionID
        self.slippageBps = slippageBps
    }
}

public struct JupiterSwapOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public let status: String
    public let slot: String?
    public let inAmount: String
    public let outAmount: String
    public let priceImpactPct: String
}

public struct JupiterOrderInput: Codable, Sendable {
    public let inputMint: String
    public let outputMint: String
    public let amountLamports: String
    public let takerAddress: SolanaPubkey
    public let slippageBps: Int
    public init(inputMint: String, outputMint: String, amountLamports: String,
                takerAddress: SolanaPubkey, slippageBps: Int = 50) {
        self.inputMint = inputMint; self.outputMint = outputMint
        self.amountLamports = amountLamports; self.takerAddress = takerAddress
        self.slippageBps = slippageBps
    }
}

public struct JupiterOrderOutput: Codable, Sendable {
    public let requestId: String
    public let unsignedTransactionBase64: String
    public let inAmount: String
    public let outAmount: String
    public let priceImpactPct: String
    public let feeLamports: Int
}

public struct JupiterExecuteInput: Codable, Sendable {
    public let requestId: String
    public let signedTransactionBase64: String
    public init(requestId: String, signedTransactionBase64: String) {
        self.requestId = requestId; self.signedTransactionBase64 = signedTransactionBase64
    }
}

public struct JupiterExecuteOutput: Codable, Sendable {
    public let signature: SolanaSignature?
    public let status: String
    public let slot: String?
    public let inputAmountResult: String?
    public let outputAmountResult: String?
}

public struct JupiterBalancesInput: Codable, Sendable {
    public let account: SolanaPubkey
    public init(account: SolanaPubkey) { self.account = account }
}

public struct JupiterBalancesOutput: Codable, Sendable {
    public let balances: [String: JupiterTokenBalance]
}

public struct JupiterTokenBalance: Codable, Sendable {
    public let amount: String
    public let uiAmount: Double
    public let isFrozen: Bool
}

// MARK: - Tools

/// Read-only quote — no signing, no approval required
public struct JupiterQuoteTool: SwooshTool {
    public typealias Input = JupiterQuoteInput
    public typealias Output = JupiterQuoteOutput
    public static let name: ToolName = "jupiter.quote"
    public static let displayName = "Jupiter Quote"
    public static let description = "Get a swap quote from Jupiter DEX aggregator (read-only)"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await JupiterApi.order(
            inputMint: input.inputMint, outputMint: input.outputMint,
            amount: input.amountLamports, taker: nil,
            platformFeeBps: DtourFeeConfig.defaultBps,
            feeAccount: DtourFeeConfig.feeAccount(for: input.outputMint)
        )
        return JupiterQuoteOutput(
            inputMint: result.inputMint, outputMint: result.outputMint,
            inAmount: result.inAmount, outAmount: result.outAmount,
            priceImpactPct: result.priceImpactPct, slippageBps: result.slippageBps,
            routeLabel: result.routePlan.first?.swapInfo.label ?? result.router ?? "Jupiter",
            feeLamports: result.prioritizationFeeLamports
        )
    }
}

/// End-to-end agent swap: quote → build → sign (WalletBridge) → broadcast.
/// Requires approval every time — shows exact amounts before signing.
public struct JupiterSwapTool: SwooshTool {
    public typealias Input = JupiterSwapInput
    public typealias Output = JupiterSwapOutput
    public static let name: ToolName = "jupiter.swap"
    public static let displayName = "Jupiter Swap"
    public static let description = "Execute a Jupiter DEX swap end-to-end: quote, sign via wallet, broadcast"
    public static let permission = SwooshPermission.solanaBroadcast
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let wallet = dependencies.walletBridge else {
            throw ToolError.executionFailed("No wallet bridge connected — connect a Solana wallet first")
        }

        // 1. Resolve taker address from active wallet session
        let accounts = try await wallet.solanaAccounts(sessionID: input.walletSessionID)
        guard let taker = accounts.first else {
            throw ToolError.executionFailed("No Solana accounts in session \(input.walletSessionID)")
        }

        // 2. Get order + unsigned transaction from Jupiter
        let order = try await JupiterApi.order(
            inputMint: input.inputMint, outputMint: input.outputMint,
            amount: input.amountLamports, taker: taker.base58,
            platformFeeBps: DtourFeeConfig.defaultBps,
            feeAccount: DtourFeeConfig.feeAccount(for: input.outputMint)
        )
        guard let unsignedTx = order.transaction else {
            let detail = order.errorMessage.map { ": \($0)" } ?? ""
            throw ToolError.executionFailed("Jupiter returned no transaction\(detail)")
        }

        // 3. Build a human-readable risk summary for the approval prompt
        let risk = TransactionRiskSummary(
            network: "Solana", isMainnet: true,
            from: taker.base58, to: "Jupiter",
            asset: "\(input.inputMint) → \(input.outputMint)",
            amountHuman: "\(input.amountLamports) lamports → ~\(order.outAmount)",
            estimatedFeeHuman: "\(order.prioritizationFeeLamports) lamports",
            warnings: Double(order.priceImpactPct) ?? 0 > 1.0
                ? ["Price impact \(order.priceImpactPct)%"] : [],
            requiresExplicitUserConfirmation: true
        )

        // 4. Sign via WalletBridge (no private key ever touches this layer)
        let solanaUnsigned = SolanaUnsignedTransaction(
            clusterID: "mainnet-beta",
            feePayer: taker,
            instructions: [SolanaInstructionPreview(
                programID: SolanaPubkey("JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"),
                name: "Jupiter Swap",
                accounts: [taker],
                humanSummary: "Swap \(input.amountLamports) lamports of \(input.inputMint) → \(order.outAmount) of \(input.outputMint) via Jupiter"
            )],
            recentBlockhash: nil,
            serializedMessageBase64: unsignedTx,
            riskSummary: risk
        )
        let signedTx = try await wallet.requestSolanaSignature(
            transaction: solanaUnsigned,
            sessionID: input.walletSessionID,
            confirmationText: "Swap \(input.amountLamports) lamports of \(input.inputMint) → ~\(order.outAmount) of \(input.outputMint). Impact: \(order.priceImpactPct)%"
        )

        // 5. Broadcast
        let resp = try await JupiterApi.execute(
            signedTransaction: signedTx,
            requestId: order.requestId
        )
        guard let sig = resp.signature else {
            throw ToolError.executionFailed("Broadcast returned no signature — status: \(resp.status)")
        }
        return JupiterSwapOutput(
            signature: SolanaSignature(sig),
            status: resp.status,
            slot: resp.slot,
            inAmount: resp.inputAmountResult ?? order.inAmount,
            outAmount: resp.outputAmountResult ?? order.outAmount,
            priceImpactPct: order.priceImpactPct
        )
    }
}

/// Low-level: build unsigned order only (agent sees the tx before deciding to sign)
public struct JupiterBuildOrderTool: SwooshTool {
    public typealias Input = JupiterOrderInput
    public typealias Output = JupiterOrderOutput
    public static let name: ToolName = "jupiter.build_order"
    public static let displayName = "Jupiter Build Order"
    public static let description = "Build an unsigned Jupiter swap transaction (inspect before signing)"
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await JupiterApi.order(
            inputMint: input.inputMint, outputMint: input.outputMint,
            amount: input.amountLamports, taker: input.takerAddress.base58,
            platformFeeBps: DtourFeeConfig.defaultBps,
            feeAccount: DtourFeeConfig.feeAccount(for: input.outputMint)
        )
        guard let tx = result.transaction else {
            let detail = result.errorMessage.map { ": \($0)" } ?? ""
            throw ToolError.executionFailed("Jupiter order returned no transaction\(detail)")
        }
        return JupiterOrderOutput(
            requestId: result.requestId, unsignedTransactionBase64: tx,
            inAmount: result.inAmount, outAmount: result.outAmount,
            priceImpactPct: result.priceImpactPct,
            feeLamports: result.prioritizationFeeLamports
        )
    }
}

/// Low-level: broadcast a pre-signed transaction
public struct JupiterExecuteTool: SwooshTool {
    public typealias Input = JupiterExecuteInput
    public typealias Output = JupiterExecuteOutput
    public static let name: ToolName = "jupiter.execute"
    public static let displayName = "Jupiter Execute Swap"
    public static let description = "Submit a signed Jupiter swap transaction to the Solana network"
    public static let permission = SwooshPermission.solanaBroadcast
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.execute(
            signedTransaction: input.signedTransactionBase64,
            requestId: input.requestId
        )
        return JupiterExecuteOutput(
            signature: resp.signature.map { SolanaSignature($0) },
            status: resp.status, slot: resp.slot,
            inputAmountResult: resp.inputAmountResult,
            outputAmountResult: resp.outputAmountResult
        )
    }
}

/// Read-only: get all SPL token balances for a wallet
public struct JupiterBalancesTool: SwooshTool {
    public typealias Input = JupiterBalancesInput
    public typealias Output = JupiterBalancesOutput
    public static let name: ToolName = "jupiter.balances"
    public static let displayName = "Jupiter Balances"
    public static let description = "Get all SPL token balances for a Solana address via Jupiter"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.balances(account: input.account.base58)
        let balances = resp.balances.mapValues { tb in
            JupiterTokenBalance(amount: tb.amount, uiAmount: tb.uiAmount, isFrozen: tb.isFrozen)
        }
        return JupiterBalancesOutput(balances: balances)
    }
}
