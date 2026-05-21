// SwooshToolsets/SolanaTools.swift — Solana toolset implementations — 0.4B
// Hard rules: No private keys. No seed phrases. No cookies.
// Airdrop disabled on mainnet. Signing/sending humanOnly.
//
// Build-tool stance: tx_build_sol_transfer / tx_build_spl_transfer
// return a preview-only `SolanaUnsignedTransaction` — a
// `SolanaInstructionPreview` list plus a human summary, but no
// serialized signable message. This is intentional and consistent
// across both build tools: the agent inspects the preview, then the
// signable message is assembled by the wallet at signing time.
import Foundation
import SwooshTools

private func requireSolana(_ deps: ToolDependencies) throws -> any SolanaRPCClient {
    guard let client = deps.solanaClient else { throw ToolError.executionFailed("Solana RPC client not configured") }
    return client
}

public struct SolanaClusterInfoTool: SwooshTool {
    public typealias Input = SolanaClusterInfoInput; public typealias Output = SolanaClusterInfoOutput
    public static let name: ToolName = "solana.cluster_info"; public static let displayName = "Cluster Info"
    public static let description = "Cluster health/version/slot"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        // The latest blockhash doubles as a liveness probe: if the RPC
        // answers, the cluster is reachable. lastValidBlockHeight tracks
        // the chain tip, so we surface it as `slot`.
        do {
            let blockhash = try await client.getLatestBlockhash(cluster: cluster, commitment: .confirmed)
            return SolanaClusterInfoOutput(
                clusterID: input.clusterID,
                healthy: true,
                slot: blockhash.lastValidBlockHeight,
                version: nil)
        } catch {
            return SolanaClusterInfoOutput(clusterID: input.clusterID, healthy: false, slot: nil, version: nil)
        }
    }
}

public struct SolanaAddressValidateTool: SwooshTool {
    public typealias Input = SolanaAddressValidateInput; public typealias Output = SolanaAddressValidateOutput
    public static let name: ToolName = "solana.address_validate"; public static let displayName = "Validate Address"
    public static let description = "Validate base58 pubkey"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let valid = input.address.count >= 32 && input.address.count <= 44
        return SolanaAddressValidateOutput(valid: valid, pubkey: valid ? SolanaPubkey(input.address) : nil)
    }
}

public struct SolanaAccountBalanceTool: SwooshTool {
    public typealias Input = SolanaAccountBalanceInput; public typealias Output = SolanaAccountBalanceOutput
    public static let name: ToolName = "solana.account_balance"; public static let displayName = "SOL Balance"
    public static let description = "SOL balance in lamports"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let lamports = try await client.getBalance(cluster: cluster, pubkey: input.pubkey, commitment: input.commitment)
        return SolanaAccountBalanceOutput(pubkey: input.pubkey, lamports: lamports, commitment: input.commitment)
    }
}

public struct SolanaAccountInfoTool: SwooshTool {
    public typealias Input = SolanaAccountInfoInput; public typealias Output = SolanaAccountInfoOutput
    public static let name: ToolName = "solana.account_info"; public static let displayName = "Account Info"
    public static let description = "Account info"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        return try await client.getAccountInfo(cluster: cluster, input: input)
    }
}

public struct SolanaTokenAccountBalanceTool: SwooshTool {
    public typealias Input = SolanaTokenAccountBalanceInput; public typealias Output = SolanaTokenAccountBalanceOutput
    public static let name: ToolName = "solana.token_account_balance"; public static let displayName = "Token Balance"
    public static let description = "SPL token account balance"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let amount = try await client.getTokenAccountBalance(cluster: cluster, tokenAccount: input.tokenAccount, commitment: input.commitment)
        return SolanaTokenAccountBalanceOutput(tokenAccount: input.tokenAccount, value: amount)
    }
}

public struct SolanaTokenAccountsByOwnerTool: SwooshTool {
    public typealias Input = SolanaTokenAccountsByOwnerInput; public typealias Output = SolanaTokenAccountsByOwnerOutput
    public static let name: ToolName = "solana.token_accounts_by_owner"; public static let displayName = "Token Accounts"
    public static let description = "SPL token accounts"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let accounts = try await client.getTokenAccountsByOwner(cluster: cluster, input: input)
        return SolanaTokenAccountsByOwnerOutput(accounts: accounts)
    }
}

public struct SolanaSignaturesForAddressTool: SwooshTool {
    public typealias Input = SolanaSignaturesForAddressInput; public typealias Output = SolanaSignaturesForAddressOutput
    public static let name: ToolName = "solana.tx_signatures_for_address"; public static let displayName = "Signatures"
    public static let description = "Recent signatures for address"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let sigs = try await client.getSignaturesForAddress(cluster: cluster, input: input)
        return SolanaSignaturesForAddressOutput(signatures: sigs)
    }
}

public struct SolanaGetTransactionTool: SwooshTool {
    public typealias Input = SolanaGetTransactionInput; public typealias Output = SolanaGetTransactionOutput
    public static let name: ToolName = "solana.tx_get_transaction"; public static let displayName = "Get Transaction"
    public static let description = "Get transaction details"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        return try await client.getTransaction(cluster: cluster, input: input)
    }
}

public struct SolanaGetSignatureStatusesTool: SwooshTool {
    public typealias Input = SolanaGetSignatureStatusesInput; public typealias Output = SolanaGetSignatureStatusesOutput
    public static let name: ToolName = "solana.tx_get_signature_statuses"; public static let displayName = "Signature Statuses"
    public static let description = "Confirm transaction status"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let statuses = try await client.getSignatureStatuses(cluster: cluster, signatures: input.signatures, searchTransactionHistory: input.searchTransactionHistory)
        return SolanaGetSignatureStatusesOutput(statuses: statuses)
    }
}

public struct SolanaGetLatestBlockhashTool: SwooshTool {
    public typealias Input = SolanaGetLatestBlockhashInput; public typealias Output = SolanaGetLatestBlockhashOutput
    public static let name: ToolName = "solana.tx_get_latest_blockhash"; public static let displayName = "Latest Blockhash"
    public static let description = "Get recent blockhash"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        return try await client.getLatestBlockhash(cluster: cluster, commitment: input.commitment)
    }
}

public struct SolanaTxSimulateTool: SwooshTool {
    public typealias Input = SolanaTxSimulateInput; public typealias Output = SolanaTxSimulateOutput
    public static let name: ToolName = "solana.tx_simulate"; public static let displayName = "Simulate Tx"
    public static let description = "Simulate transaction"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askFirstTime; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        return try await client.simulateTransaction(cluster: cluster, input: input)
    }
}

// ── Build tools ───────────────────────────────────────────────────

public struct SolanaBuildSOLTransferTool: SwooshTool {
    public typealias Input = SolanaBuildSOLTransferInput; public typealias Output = SolanaBuildSOLTransferOutput
    public static let name: ToolName = "solana.tx_build_sol_transfer"; public static let displayName = "Build SOL Transfer"
    public static let description = "Build unsigned SOL transfer"; public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let isMainnet = input.clusterID.lowercased().contains("mainnet")
        if isMainnet { try await dependencies.firewall.require(.solanaMainnetWrite) }
        let risk = TransactionRiskSummary(network: "Solana-\(input.clusterID)", isMainnet: isMainnet, from: input.from.base58, to: input.to.base58, asset: "SOL", amountHuman: "\(input.lamports.value) lamports", estimatedFeeHuman: nil, warnings: isMainnet ? ["MAINNET transaction"] : [], requiresExplicitUserConfirmation: isMainnet)
        let ix = SolanaInstructionPreview(programID: SolanaPubkey("11111111111111111111111111111111"), name: "SystemProgram.transfer", accounts: [input.from, input.to], humanSummary: "Transfer \(input.lamports.value) lamports")
        let tx = SolanaUnsignedTransaction(clusterID: input.clusterID, feePayer: input.from, instructions: [ix], recentBlockhash: input.recentBlockhash, riskSummary: risk)
        return SolanaBuildSOLTransferOutput(unsignedTransaction: tx, humanPreview: "Transfer \(input.lamports.value) lamports from \(input.from.base58) to \(input.to.base58)")
    }
}

public struct SolanaBuildSPLTransferTool: SwooshTool {
    public typealias Input = SolanaBuildSPLTransferInput; public typealias Output = SolanaBuildSPLTransferOutput
    public static let name: ToolName = "solana.tx_build_spl_transfer"; public static let displayName = "Build SPL Transfer"
    public static let description = "Build unsigned SPL transfer"; public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let isMainnet = input.clusterID.lowercased().contains("mainnet")
        if isMainnet { try await dependencies.firewall.require(.solanaMainnetWrite) }
        let risk = TransactionRiskSummary(network: "Solana-\(input.clusterID)", isMainnet: isMainnet, from: input.owner.base58, to: input.destinationTokenAccount.base58, asset: "SPL", amountHuman: input.amountRaw, estimatedFeeHuman: nil, warnings: isMainnet ? ["MAINNET transaction"] : [], requiresExplicitUserConfirmation: isMainnet)
        // SPL Token program (TokenkegQ...). This is a human-readable
        // *preview* instruction, mirroring SolanaBuildSOLTransferTool —
        // neither tool produces a signable serialized message; the
        // unsigned transaction is for inspection before wallet signing.
        let ix = SolanaInstructionPreview(
            programID: SolanaPubkey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
            name: "Token.transfer",
            accounts: [input.owner, input.destinationTokenAccount, input.mint],
            humanSummary: "Transfer \(input.amountRaw) raw units of mint \(input.mint.base58) to \(input.destinationTokenAccount.base58)")
        let tx = SolanaUnsignedTransaction(clusterID: input.clusterID, feePayer: input.owner, instructions: [ix], recentBlockhash: input.recentBlockhash, riskSummary: risk)
        return SolanaBuildSPLTransferOutput(unsignedTransaction: tx, humanPreview: "SPL transfer of \(input.amountRaw) raw units (mint \(input.mint.base58))")
    }
}

// ── Wallet / signing / sending (humanOnly) ────────────────────────

public struct SolanaWalletConnectTool: SwooshTool {
    public typealias Input = SolanaWalletConnectInput; public typealias Output = SolanaWalletConnectOutput
    public static let name: ToolName = "solana.wallet_connect"; public static let displayName = "Connect Wallet"
    public static let description = "Connect wallet"; public static let permission = SwooshPermission.solanaRequestSignature
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let bridge = dependencies.walletBridge else { throw ToolError.executionFailed("No wallet bridge") }
        let session = try await bridge.connectSolana()
        let accounts = try await bridge.solanaAccounts(sessionID: session)
        return SolanaWalletConnectOutput(walletSessionID: session, connectedAccounts: accounts)
    }
}

public struct SolanaWalletAccountsTool: SwooshTool {
    public typealias Input = SolanaWalletAccountsInput; public typealias Output = SolanaWalletAccountsOutput
    public static let name: ToolName = "solana.wallet_accounts"; public static let displayName = "Wallet Accounts"
    public static let description = "List connected accounts"; public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let session = input.walletSessionID else { return SolanaWalletAccountsOutput(accounts: []) }
        guard let bridge = dependencies.walletBridge else {
            throw ToolError.executionFailed("No wallet bridge configured — cannot list accounts for session \(session)")
        }
        let accounts = try await bridge.solanaAccounts(sessionID: session)
        return SolanaWalletAccountsOutput(accounts: accounts)
    }
}

public struct SolanaTxRequestSignatureTool: SwooshTool {
    public typealias Input = SolanaTxRequestSignatureInput; public typealias Output = SolanaTxRequestSignatureOutput
    public static let name: ToolName = "solana.tx_request_signature"; public static let displayName = "Request Signature"
    public static let description = "Request wallet signature (humanOnly)"; public static let permission = SwooshPermission.solanaRequestSignature
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let bridge = dependencies.walletBridge else { throw ToolError.executionFailed("No wallet bridge") }
        let signed = try await bridge.requestSolanaSignature(transaction: input.unsignedTransaction, sessionID: input.walletSessionID, confirmationText: input.userConfirmationText ?? "")
        return SolanaTxRequestSignatureOutput(signedTransactionBase64: signed, signer: input.unsignedTransaction.feePayer)
    }
}

public struct SolanaTxSendSignedTool: SwooshTool {
    public typealias Input = SolanaTxSendSignedInput; public typealias Output = SolanaTxSendSignedOutput
    public static let name: ToolName = "solana.tx_send_signed"; public static let displayName = "Send Signed Tx"
    public static let description = "Submit signed transaction (humanOnly)"; public static let permission = SwooshPermission.solanaBroadcast
    public static let risk = ToolRisk.critical; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let isMainnet = input.clusterID.lowercased().contains("mainnet")
        if isMainnet { try await dependencies.firewall.require(.solanaMainnetWrite) }
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let sig = try await client.sendTransaction(cluster: cluster, input: input)
        // Recommend checking signature status
        return SolanaTxSendSignedOutput(signature: sig)
    }
}

public struct SolanaRequestAirdropTool: SwooshTool {
    public typealias Input = SolanaRequestAirdropInput; public typealias Output = SolanaRequestAirdropOutput
    public static let name: ToolName = "solana.tx_request_airdrop"; public static let displayName = "Request Airdrop"
    public static let description = "Devnet/testnet airdrop only"; public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.solana
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        // HARD RULE: airdrop disabled on mainnet
        if input.clusterID.lowercased().contains("mainnet") {
            throw ToolError.denied("solana.tx_request_airdrop", "Airdrop is disabled on mainnet")
        }
        let client = try requireSolana(dependencies)
        let cluster = SolanaCluster(id: input.clusterID, rpcURLSecretRef: "default")
        let sig = try await client.requestAirdrop(cluster: cluster, pubkey: input.pubkey, lamports: input.lamports)
        return SolanaRequestAirdropOutput(signature: sig)
    }
}
