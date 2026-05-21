// SwooshTools/SolanaRPCTypes.swift — Solana RPC input/output types
//
// These types bridge the Solana tool definitions to the RPC client protocol.
// Each Input/Output matches what SolanaTools.swift expects.

import Foundation

// MARK: - Cluster info

public struct SolanaClusterInfoInput: Codable, Sendable {
    public let clusterID: String
    public init(clusterID: String) { self.clusterID = clusterID }
}

public struct SolanaClusterInfoOutput: Codable, Sendable {
    public let clusterID: String
    public let healthy: Bool
    public let slot: UInt64?
    public let version: String?
    public init(clusterID: String, healthy: Bool = true, slot: UInt64? = nil, version: String? = nil) {
        self.clusterID = clusterID; self.healthy = healthy; self.slot = slot; self.version = version
    }
}

// MARK: - Address validation

public struct SolanaAddressValidateInput: Codable, Sendable {
    public let address: String
    public init(address: String) { self.address = address }
}

public struct SolanaAddressValidateOutput: Codable, Sendable {
    public let valid: Bool
    public let pubkey: SolanaPubkey?
    public init(valid: Bool = false, pubkey: SolanaPubkey? = nil) { self.valid = valid; self.pubkey = pubkey }
}

// MARK: - Account balance

public struct SolanaAccountBalanceInput: Codable, Sendable {
    public let pubkey: SolanaPubkey
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(pubkey: SolanaPubkey, clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.pubkey = pubkey; self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaAccountBalanceOutput: Codable, Sendable {
    public let pubkey: SolanaPubkey
    public let lamports: Lamports
    public let commitment: SolanaCommitment
    public init(pubkey: SolanaPubkey, lamports: Lamports, commitment: SolanaCommitment = .confirmed) {
        self.pubkey = pubkey; self.lamports = lamports; self.commitment = commitment
    }
}

// MARK: - Account info

public struct SolanaAccountInfoInput: Codable, Sendable {
    public let pubkey: SolanaPubkey
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(pubkey: SolanaPubkey, clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.pubkey = pubkey; self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaAccountInfoOutput: Codable, Sendable {
    public let lamports: UInt64
    public let owner: String
    public let data: String
    public let executable: Bool
    public init(lamports: UInt64, owner: String, data: String, executable: Bool) {
        self.lamports = lamports; self.owner = owner; self.data = data; self.executable = executable
    }
}

// MARK: - Token account balance

public struct SolanaTokenAccountBalanceInput: Codable, Sendable {
    public let tokenAccount: SolanaPubkey
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(tokenAccount: SolanaPubkey, clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.tokenAccount = tokenAccount; self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaTokenAccountBalanceOutput: Codable, Sendable {
    public let tokenAccount: SolanaPubkey
    public let value: SolanaTokenAmount
    public init(tokenAccount: SolanaPubkey, value: SolanaTokenAmount) {
        self.tokenAccount = tokenAccount; self.value = value
    }
}

// MARK: - Token accounts by owner

public struct SolanaTokenAccountsByOwnerInput: Codable, Sendable {
    public let owner: SolanaPubkey
    public let clusterID: String
    public let mint: SolanaPubkey?
    public let programId: SolanaPubkey?
    public init(owner: SolanaPubkey, clusterID: String = "devnet", mint: SolanaPubkey? = nil, programId: SolanaPubkey? = nil) {
        self.owner = owner; self.clusterID = clusterID; self.mint = mint; self.programId = programId
    }
}

public struct SolanaTokenAccountsByOwnerOutput: Codable, Sendable {
    public let accounts: [SolanaTokenAccountEntry]
    public init(accounts: [SolanaTokenAccountEntry] = []) { self.accounts = accounts }
}

// MARK: - Signatures for address

public struct SolanaSignaturesForAddressInput: Codable, Sendable {
    public let address: SolanaPubkey
    public let clusterID: String
    public let limit: Int
    public let before: SolanaSignature?
    public init(address: SolanaPubkey, clusterID: String = "devnet", limit: Int = 20, before: SolanaSignature? = nil) {
        self.address = address; self.clusterID = clusterID; self.limit = limit; self.before = before
    }
}

public struct SolanaSignaturesForAddressOutput: Codable, Sendable {
    public let signatures: [SolanaSignatureInfo]
    public init(signatures: [SolanaSignatureInfo] = []) { self.signatures = signatures }
}

// MARK: - Get transaction

public struct SolanaGetTransactionInput: Codable, Sendable {
    public let signature: SolanaSignature
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(signature: SolanaSignature, clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.signature = signature; self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaGetTransactionOutput: Codable, Sendable {
    public let slot: UInt64
    public let meta: SolanaTransactionMeta?
    public struct SolanaTransactionMeta: Codable, Sendable {
        public let fee: UInt64
        public let err: String?
        public init(fee: UInt64, err: String?) { self.fee = fee; self.err = err }
    }
    public init(slot: UInt64, meta: SolanaTransactionMeta?) { self.slot = slot; self.meta = meta }
}

// MARK: - Signature statuses

public struct SolanaGetSignatureStatusesInput: Codable, Sendable {
    public let signatures: [SolanaSignature]
    public let clusterID: String
    public let searchTransactionHistory: Bool
    public init(signatures: [SolanaSignature], clusterID: String = "devnet", searchTransactionHistory: Bool = false) {
        self.signatures = signatures; self.clusterID = clusterID; self.searchTransactionHistory = searchTransactionHistory
    }
}

public struct SolanaGetSignatureStatusesOutput: Codable, Sendable {
    public let statuses: [SolanaSignatureStatus?]
    public init(statuses: [SolanaSignatureStatus?] = []) { self.statuses = statuses }
}

// MARK: - Latest blockhash

public struct SolanaGetLatestBlockhashInput: Codable, Sendable {
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaGetLatestBlockhashOutput: Codable, Sendable {
    public let blockhash: String
    public let lastValidBlockHeight: UInt64
    public init(blockhash: String, lastValidBlockHeight: UInt64) {
        self.blockhash = blockhash; self.lastValidBlockHeight = lastValidBlockHeight
    }
}

// MARK: - Simulate transaction

public struct SolanaTxSimulateInput: Codable, Sendable {
    public let transaction: String
    public let clusterID: String
    public let commitment: SolanaCommitment
    public init(transaction: String, clusterID: String = "devnet", commitment: SolanaCommitment = .confirmed) {
        self.transaction = transaction; self.clusterID = clusterID; self.commitment = commitment
    }
}

public struct SolanaTxSimulateOutput: Codable, Sendable {
    public let err: String?
    public let logs: [String]
    public let unitsConsumed: UInt64?
    public init(err: String?, logs: [String], unitsConsumed: UInt64?) {
        self.err = err; self.logs = logs; self.unitsConsumed = unitsConsumed
    }
}

// MARK: - Build SOL transfer

public struct SolanaBuildSOLTransferInput: Codable, Sendable {
    public let from: SolanaPubkey
    public let to: SolanaPubkey
    public let lamports: Lamports
    public let clusterID: String
    public let recentBlockhash: String?
    public init(from: SolanaPubkey, to: SolanaPubkey, lamports: Lamports, clusterID: String = "devnet", recentBlockhash: String? = nil) {
        self.from = from; self.to = to; self.lamports = lamports; self.clusterID = clusterID; self.recentBlockhash = recentBlockhash
    }
}

public struct SolanaBuildSOLTransferOutput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction
    public let humanPreview: String
    public init(unsignedTransaction: SolanaUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// MARK: - Build SPL transfer

public struct SolanaBuildSPLTransferInput: Codable, Sendable {
    public let owner: SolanaPubkey
    public let destinationTokenAccount: SolanaPubkey
    public let mint: SolanaPubkey
    public let amountRaw: String
    public let clusterID: String
    public let recentBlockhash: String?
    public init(owner: SolanaPubkey, destinationTokenAccount: SolanaPubkey, mint: SolanaPubkey, amountRaw: String, clusterID: String = "devnet", recentBlockhash: String? = nil) {
        self.owner = owner; self.destinationTokenAccount = destinationTokenAccount; self.mint = mint; self.amountRaw = amountRaw; self.clusterID = clusterID; self.recentBlockhash = recentBlockhash
    }
}

public struct SolanaBuildSPLTransferOutput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction
    public let humanPreview: String
    public init(unsignedTransaction: SolanaUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// MARK: - Wallet connect

public struct SolanaWalletConnectInput: Codable, Sendable {
    public let dappName: String
    public init(dappName: String) { self.dappName = dappName }
}

public struct SolanaWalletConnectOutput: Codable, Sendable {
    public let walletSessionID: String
    public let connectedAccounts: [SolanaPubkey]
    public init(walletSessionID: String, connectedAccounts: [SolanaPubkey] = []) {
        self.walletSessionID = walletSessionID; self.connectedAccounts = connectedAccounts
    }
}

// MARK: - Wallet accounts

public struct SolanaWalletAccountsInput: Codable, Sendable {
    public let walletSessionID: String?
    public init(walletSessionID: String? = nil) { self.walletSessionID = walletSessionID }
}

public struct SolanaWalletAccountsOutput: Codable, Sendable {
    public let accounts: [SolanaPubkey]
    public init(accounts: [SolanaPubkey] = []) { self.accounts = accounts }
}

// MARK: - Transaction request signature

public struct SolanaTxRequestSignatureInput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction
    public let walletSessionID: String
    public let userConfirmationText: String?
    public init(unsignedTransaction: SolanaUnsignedTransaction, walletSessionID: String, userConfirmationText: String? = nil) {
        self.unsignedTransaction = unsignedTransaction; self.walletSessionID = walletSessionID; self.userConfirmationText = userConfirmationText
    }
}

public struct SolanaTxRequestSignatureOutput: Codable, Sendable {
    public let signedTransactionBase64: String
    public let signer: SolanaPubkey
    public init(signedTransactionBase64: String, signer: SolanaPubkey) {
        self.signedTransactionBase64 = signedTransactionBase64; self.signer = signer
    }
}

// MARK: - Transaction send signed

public struct SolanaTxSendSignedInput: Codable, Sendable {
    public let signedTransaction: String
    public let clusterID: String
    public let skipPreflight: Bool
    public init(signedTransaction: String, clusterID: String = "devnet", skipPreflight: Bool = false) {
        self.signedTransaction = signedTransaction; self.clusterID = clusterID; self.skipPreflight = skipPreflight
    }
}

public struct SolanaTxSendSignedOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public init(signature: SolanaSignature) { self.signature = signature }
}

// MARK: - Request airdrop

public struct SolanaRequestAirdropInput: Codable, Sendable {
    public let pubkey: SolanaPubkey
    public let lamports: Lamports
    public let clusterID: String
    public init(pubkey: SolanaPubkey, lamports: Lamports, clusterID: String = "devnet") {
        self.pubkey = pubkey; self.lamports = lamports; self.clusterID = clusterID
    }
}

public struct SolanaRequestAirdropOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public init(signature: SolanaSignature) { self.signature = signature }
}
