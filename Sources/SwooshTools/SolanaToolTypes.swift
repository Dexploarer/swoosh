// SwooshTools/SolanaToolTypes.swift — Solana Tool I/O Types
import Foundation

// ── solana.cluster_info ───────────────────────────────────────────
public struct SolanaClusterInfoInput: Codable, Sendable {
    public let clusterID: String
    public init(clusterID: String) { self.clusterID = clusterID }
}
public struct SolanaClusterInfoOutput: Codable, Sendable {
    public let clusterID: String; public let healthy: Bool; public let slot: UInt64?; public let version: String?
    public init(clusterID: String, healthy: Bool, slot: UInt64? = nil, version: String? = nil) {
        self.clusterID = clusterID; self.healthy = healthy; self.slot = slot; self.version = version
    }
}

// ── solana.address_validate ───────────────────────────────────────
public struct SolanaAddressValidateInput: Codable, Sendable {
    public let address: String
    public init(address: String) { self.address = address }
}
public struct SolanaAddressValidateOutput: Codable, Sendable {
    public let valid: Bool; public let pubkey: SolanaPubkey?
    public init(valid: Bool, pubkey: SolanaPubkey? = nil) { self.valid = valid; self.pubkey = pubkey }
}

// ── solana.account_balance ────────────────────────────────────────
public struct SolanaAccountBalanceInput: Codable, Sendable {
    public let clusterID: String; public let pubkey: SolanaPubkey; public let commitment: SolanaCommitment
    public init(clusterID: String, pubkey: SolanaPubkey, commitment: SolanaCommitment = .confirmed) {
        self.clusterID = clusterID; self.pubkey = pubkey; self.commitment = commitment
    }
}
public struct SolanaAccountBalanceOutput: Codable, Sendable {
    public let pubkey: SolanaPubkey; public let lamports: Lamports; public let commitment: SolanaCommitment
    public init(pubkey: SolanaPubkey, lamports: Lamports, commitment: SolanaCommitment) {
        self.pubkey = pubkey; self.lamports = lamports; self.commitment = commitment
    }
}

// ── solana.account_info ───────────────────────────────────────────
public struct SolanaAccountInfoInput: Codable, Sendable {
    public let clusterID: String; public let pubkey: SolanaPubkey
    public let commitment: SolanaCommitment; public let encoding: SolanaAccountEncoding
    public init(clusterID: String, pubkey: SolanaPubkey, commitment: SolanaCommitment = .confirmed, encoding: SolanaAccountEncoding = .base64) {
        self.clusterID = clusterID; self.pubkey = pubkey; self.commitment = commitment; self.encoding = encoding
    }
}
public enum SolanaAccountEncoding: String, Codable, Sendable { case base64; case jsonParsed }
public struct SolanaAccountInfoOutput: Codable, Sendable {
    public let pubkey: SolanaPubkey; public let lamports: Lamports?; public let owner: SolanaPubkey?
    public let executable: Bool?; public let rentEpoch: UInt64?; public let rawJSON: String
    public init(pubkey: SolanaPubkey, lamports: Lamports? = nil, owner: SolanaPubkey? = nil, executable: Bool? = nil, rentEpoch: UInt64? = nil, rawJSON: String) {
        self.pubkey = pubkey; self.lamports = lamports; self.owner = owner
        self.executable = executable; self.rentEpoch = rentEpoch; self.rawJSON = rawJSON
    }
}

// ── solana.token_account_balance ──────────────────────────────────
public struct SolanaTokenAccountBalanceInput: Codable, Sendable {
    public let clusterID: String; public let tokenAccount: SolanaPubkey; public let commitment: SolanaCommitment
    public init(clusterID: String, tokenAccount: SolanaPubkey, commitment: SolanaCommitment = .confirmed) {
        self.clusterID = clusterID; self.tokenAccount = tokenAccount; self.commitment = commitment
    }
}
public struct SolanaTokenAccountBalanceOutput: Codable, Sendable {
    public let tokenAccount: SolanaPubkey; public let value: SolanaTokenAmount
    public init(tokenAccount: SolanaPubkey, value: SolanaTokenAmount) {
        self.tokenAccount = tokenAccount; self.value = value
    }
}

// ── solana.token_accounts_by_owner ────────────────────────────────
public struct SolanaTokenAccountsByOwnerInput: Codable, Sendable {
    public let clusterID: String; public let owner: SolanaPubkey
    public let mint: SolanaPubkey?; public let programID: SolanaPubkey?
    public init(clusterID: String, owner: SolanaPubkey, mint: SolanaPubkey? = nil, programID: SolanaPubkey? = nil) {
        self.clusterID = clusterID; self.owner = owner; self.mint = mint; self.programID = programID
    }
}
public struct SolanaTokenAccountsByOwnerOutput: Codable, Sendable {
    public let accounts: [SolanaTokenAccountEntry]
    public init(accounts: [SolanaTokenAccountEntry]) { self.accounts = accounts }
}
public struct SolanaTokenAccountEntry: Codable, Sendable {
    public let pubkey: SolanaPubkey; public let mint: SolanaPubkey; public let amount: SolanaTokenAmount
    public init(pubkey: SolanaPubkey, mint: SolanaPubkey, amount: SolanaTokenAmount) {
        self.pubkey = pubkey; self.mint = mint; self.amount = amount
    }
}

// ── solana.tx_signatures_for_address ──────────────────────────────
public struct SolanaSignaturesForAddressInput: Codable, Sendable {
    public let clusterID: String; public let address: SolanaPubkey
    public let before: SolanaSignature?; public let until: SolanaSignature?
    public let limit: Int?; public let commitment: SolanaCommitment
    public init(clusterID: String, address: SolanaPubkey, before: SolanaSignature? = nil, until: SolanaSignature? = nil, limit: Int? = nil, commitment: SolanaCommitment = .confirmed) {
        self.clusterID = clusterID; self.address = address; self.before = before
        self.until = until; self.limit = limit; self.commitment = commitment
    }
}
public struct SolanaSignaturesForAddressOutput: Codable, Sendable {
    public let signatures: [SolanaSignatureInfo]
    public init(signatures: [SolanaSignatureInfo]) { self.signatures = signatures }
}

// ── solana.tx_get_transaction ─────────────────────────────────────
public struct SolanaGetTransactionInput: Codable, Sendable {
    public let clusterID: String; public let signature: SolanaSignature
    public let commitment: SolanaCommitment; public let maxSupportedTransactionVersion: Int?
    public let encoding: SolanaTransactionEncoding
    public init(clusterID: String, signature: SolanaSignature, commitment: SolanaCommitment = .confirmed, maxSupportedTransactionVersion: Int? = 0, encoding: SolanaTransactionEncoding = .jsonParsed) {
        self.clusterID = clusterID; self.signature = signature; self.commitment = commitment
        self.maxSupportedTransactionVersion = maxSupportedTransactionVersion; self.encoding = encoding
    }
}
public enum SolanaTransactionEncoding: String, Codable, Sendable { case json; case jsonParsed; case base64 }
public struct SolanaGetTransactionOutput: Codable, Sendable {
    public let signature: SolanaSignature; public let rawJSON: String?; public let found: Bool
    public init(signature: SolanaSignature, rawJSON: String? = nil, found: Bool) {
        self.signature = signature; self.rawJSON = rawJSON; self.found = found
    }
}

// ── solana.tx_get_signature_statuses ──────────────────────────────
public struct SolanaGetSignatureStatusesInput: Codable, Sendable {
    public let clusterID: String; public let signatures: [SolanaSignature]; public let searchTransactionHistory: Bool
    public init(clusterID: String, signatures: [SolanaSignature], searchTransactionHistory: Bool = false) {
        self.clusterID = clusterID; self.signatures = signatures; self.searchTransactionHistory = searchTransactionHistory
    }
}
public struct SolanaGetSignatureStatusesOutput: Codable, Sendable {
    public let statuses: [SolanaSignatureStatus]
    public init(statuses: [SolanaSignatureStatus]) { self.statuses = statuses }
}

// ── solana.tx_get_latest_blockhash ────────────────────────────────
public struct SolanaGetLatestBlockhashInput: Codable, Sendable {
    public let clusterID: String; public let commitment: SolanaCommitment
    public init(clusterID: String, commitment: SolanaCommitment = .finalized) {
        self.clusterID = clusterID; self.commitment = commitment
    }
}
public struct SolanaGetLatestBlockhashOutput: Codable, Sendable {
    public let blockhash: String; public let lastValidBlockHeight: UInt64
    public init(blockhash: String, lastValidBlockHeight: UInt64) {
        self.blockhash = blockhash; self.lastValidBlockHeight = lastValidBlockHeight
    }
}

// ── solana.tx_simulate ────────────────────────────────────────────
public struct SolanaTxSimulateInput: Codable, Sendable {
    public let clusterID: String; public let unsignedOrSignedTransactionBase64: String
    public let commitment: SolanaCommitment; public let sigVerify: Bool; public let replaceRecentBlockhash: Bool
    public init(clusterID: String, unsignedOrSignedTransactionBase64: String, commitment: SolanaCommitment = .confirmed, sigVerify: Bool = false, replaceRecentBlockhash: Bool = true) {
        self.clusterID = clusterID; self.unsignedOrSignedTransactionBase64 = unsignedOrSignedTransactionBase64
        self.commitment = commitment; self.sigVerify = sigVerify; self.replaceRecentBlockhash = replaceRecentBlockhash
    }
}
public struct SolanaTxSimulateOutput: Codable, Sendable {
    public let success: Bool; public let logs: [String]; public let unitsConsumed: UInt64?; public let rawJSON: String
    public init(success: Bool, logs: [String], unitsConsumed: UInt64? = nil, rawJSON: String) {
        self.success = success; self.logs = logs; self.unitsConsumed = unitsConsumed; self.rawJSON = rawJSON
    }
}

// ── solana.tx_build_sol_transfer ──────────────────────────────────
public struct SolanaBuildSOLTransferInput: Codable, Sendable {
    public let clusterID: String; public let from: SolanaPubkey; public let to: SolanaPubkey
    public let lamports: Lamports; public let recentBlockhash: String?
    public init(clusterID: String, from: SolanaPubkey, to: SolanaPubkey, lamports: Lamports, recentBlockhash: String? = nil) {
        self.clusterID = clusterID; self.from = from; self.to = to; self.lamports = lamports; self.recentBlockhash = recentBlockhash
    }
}
public struct SolanaBuildSOLTransferOutput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction; public let humanPreview: String
    public init(unsignedTransaction: SolanaUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// ── solana.tx_build_spl_transfer ──────────────────────────────────
public struct SolanaBuildSPLTransferInput: Codable, Sendable {
    public let clusterID: String; public let owner: SolanaPubkey
    public let sourceTokenAccount: SolanaPubkey; public let destinationTokenAccount: SolanaPubkey
    public let mint: SolanaPubkey; public let amountRaw: String; public let decimals: Int; public let recentBlockhash: String?
    public init(clusterID: String, owner: SolanaPubkey, sourceTokenAccount: SolanaPubkey, destinationTokenAccount: SolanaPubkey, mint: SolanaPubkey, amountRaw: String, decimals: Int, recentBlockhash: String? = nil) {
        self.clusterID = clusterID; self.owner = owner; self.sourceTokenAccount = sourceTokenAccount
        self.destinationTokenAccount = destinationTokenAccount; self.mint = mint
        self.amountRaw = amountRaw; self.decimals = decimals; self.recentBlockhash = recentBlockhash
    }
}
public struct SolanaBuildSPLTransferOutput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction; public let humanPreview: String
    public init(unsignedTransaction: SolanaUnsignedTransaction, humanPreview: String) {
        self.unsignedTransaction = unsignedTransaction; self.humanPreview = humanPreview
    }
}

// ── solana.wallet_connect / wallet_accounts ───────────────────────
public struct SolanaWalletConnectInput: Codable, Sendable {
    public let clusterID: String?
    public init(clusterID: String? = nil) { self.clusterID = clusterID }
}
public struct SolanaWalletConnectOutput: Codable, Sendable {
    public let walletSessionID: String; public let connectedAccounts: [SolanaPubkey]
    public init(walletSessionID: String, connectedAccounts: [SolanaPubkey]) {
        self.walletSessionID = walletSessionID; self.connectedAccounts = connectedAccounts
    }
}
public struct SolanaWalletAccountsInput: Codable, Sendable {
    public let walletSessionID: String?
    public init(walletSessionID: String? = nil) { self.walletSessionID = walletSessionID }
}
public struct SolanaWalletAccountsOutput: Codable, Sendable {
    public let accounts: [SolanaPubkey]
    public init(accounts: [SolanaPubkey]) { self.accounts = accounts }
}

// ── solana.tx_request_signature ───────────────────────────────────
public struct SolanaTxRequestSignatureInput: Codable, Sendable {
    public let unsignedTransaction: SolanaUnsignedTransaction; public let walletSessionID: String; public let userConfirmationText: String
    public init(unsignedTransaction: SolanaUnsignedTransaction, walletSessionID: String, userConfirmationText: String) {
        self.unsignedTransaction = unsignedTransaction; self.walletSessionID = walletSessionID; self.userConfirmationText = userConfirmationText
    }
}
public struct SolanaTxRequestSignatureOutput: Codable, Sendable {
    public let signedTransactionBase64: String; public let signer: SolanaPubkey
    public init(signedTransactionBase64: String, signer: SolanaPubkey) {
        self.signedTransactionBase64 = signedTransactionBase64; self.signer = signer
    }
}

// ── solana.tx_send_signed ─────────────────────────────────────────
public struct SolanaTxSendSignedInput: Codable, Sendable {
    public let clusterID: String; public let signedTransactionBase64: String
    public let skipPreflight: Bool; public let preflightCommitment: SolanaCommitment; public let userConfirmationText: String
    public init(clusterID: String, signedTransactionBase64: String, skipPreflight: Bool = false, preflightCommitment: SolanaCommitment = .confirmed, userConfirmationText: String) {
        self.clusterID = clusterID; self.signedTransactionBase64 = signedTransactionBase64
        self.skipPreflight = skipPreflight; self.preflightCommitment = preflightCommitment; self.userConfirmationText = userConfirmationText
    }
}
public struct SolanaTxSendSignedOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public init(signature: SolanaSignature) { self.signature = signature }
}

// ── solana.tx_request_airdrop ─────────────────────────────────────
public struct SolanaRequestAirdropInput: Codable, Sendable {
    public let clusterID: String; public let pubkey: SolanaPubkey; public let lamports: Lamports
    public init(clusterID: String, pubkey: SolanaPubkey, lamports: Lamports) {
        self.clusterID = clusterID; self.pubkey = pubkey; self.lamports = lamports
    }
}
public struct SolanaRequestAirdropOutput: Codable, Sendable {
    public let signature: SolanaSignature
    public init(signature: SolanaSignature) { self.signature = signature }
}
