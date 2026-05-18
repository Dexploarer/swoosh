// SwooshTools/SolanaToolTypes.swift — Solana primitive types and wallet bridge
import Foundation
import BigInt
// Note: Lamports is defined in EVMTypes+BigInt.swift (BigInt-backed)

// MARK: - Solana primitive types
// ═══════════════════════════════════════════════════════════════════

public struct SolanaPubkey: Codable, Sendable, Hashable {
    public let base58: String
    public init(_ base58: String) { self.base58 = base58 }
}

public struct SolanaSignature: Codable, Sendable, Hashable {
    public let base58: String
    public init(_ base58: String) { self.base58 = base58 }
}

public struct SolanaCluster: Codable, Sendable, Hashable {
    public let id: String
    public let rpcURLSecretRef: String

    public init(id: String, rpcURLSecretRef: String) {
        self.id = id
        self.rpcURLSecretRef = rpcURLSecretRef
    }

    public var isMainnet: Bool { id.lowercased().contains("mainnet") }

    public static let devnet  = SolanaCluster(id: "devnet",  rpcURLSecretRef: "solana_devnet_rpc")
    public static let testnet = SolanaCluster(id: "testnet", rpcURLSecretRef: "solana_testnet_rpc")
}

public enum SolanaCommitment: String, Codable, Sendable {
    case processed, confirmed, finalized
}

// ── Solana token amount ───────────────────────────────────────────

public struct SolanaTokenAmount: Codable, Sendable {
    public let amount: String
    public let decimals: Int
    public let uiAmountString: String?

    public init(amount: String, decimals: Int, uiAmountString: String? = nil) {
        self.amount = amount
        self.decimals = decimals
        self.uiAmountString = uiAmountString
    }
}

// ── Solana signature info ─────────────────────────────────────────

public struct SolanaSignatureInfo: Codable, Sendable {
    public let signature: SolanaSignature
    public let slot: UInt64
    public let blockTime: Int64?
    public let confirmationStatus: String?
    public let errJSON: String?

    public init(
        signature: SolanaSignature,
        slot: UInt64,
        blockTime: Int64? = nil,
        confirmationStatus: String? = nil,
        errJSON: String? = nil
    ) {
        self.signature = signature
        self.slot = slot
        self.blockTime = blockTime
        self.confirmationStatus = confirmationStatus
        self.errJSON = errJSON
    }
}

// ── Solana signature status ───────────────────────────────────────

public struct SolanaSignatureStatus: Codable, Sendable {
    public let signature: SolanaSignature
    public let slot: UInt64?
    public let confirmationStatus: String?
    public let errJSON: String?

    public init(signature: SolanaSignature, slot: UInt64? = nil, confirmationStatus: String? = nil, errJSON: String? = nil) {
        self.signature = signature
        self.slot = slot
        self.confirmationStatus = confirmationStatus
        self.errJSON = errJSON
    }
}

// ── Solana unsigned transaction ───────────────────────────────────

public struct SolanaUnsignedTransaction: Codable, Sendable {
    public let clusterID: String
    public let feePayer: SolanaPubkey
    public let instructions: [SolanaInstructionPreview]
    public let recentBlockhash: String?
    public let serializedMessageBase64: String?
    public let riskSummary: TransactionRiskSummary

    public init(
        clusterID: String,
        feePayer: SolanaPubkey,
        instructions: [SolanaInstructionPreview],
        recentBlockhash: String? = nil,
        serializedMessageBase64: String? = nil,
        riskSummary: TransactionRiskSummary
    ) {
        self.clusterID = clusterID
        self.feePayer = feePayer
        self.instructions = instructions
        self.recentBlockhash = recentBlockhash
        self.serializedMessageBase64 = serializedMessageBase64
        self.riskSummary = riskSummary
    }
}

public struct SolanaInstructionPreview: Codable, Sendable {
    public let programID: SolanaPubkey
    public let name: String?
    public let accounts: [SolanaPubkey]
    public let humanSummary: String

    public init(programID: SolanaPubkey, name: String? = nil, accounts: [SolanaPubkey], humanSummary: String) {
        self.programID = programID
        self.name = name
        self.accounts = accounts
        self.humanSummary = humanSummary
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Wallet bridge protocol
// ═══════════════════════════════════════════════════════════════════

/// Wallet interaction protocol. No private keys or seed phrases flow through this.
/// Signing happens through WalletConnect, external wallet, or future Keychain module.
public protocol WalletBridge: Sendable {
    // ── EVM ───────────────────────────────────────────────────────
    func connectEVM() async throws -> String // session ID
    func evmAccounts(sessionID: String) async throws -> [EVMAddress]
    func requestEVMSignature(
        transaction: EVMUnsignedTransaction,
        sessionID: String,
        confirmationText: String
    ) async throws -> EVMHexData // signed tx

    // ── Solana ────────────────────────────────────────────────────
    func connectSolana() async throws -> String // session ID
    func solanaAccounts(sessionID: String) async throws -> [SolanaPubkey]
    func requestSolanaSignature(
        transaction: SolanaUnsignedTransaction,
        sessionID: String,
        confirmationText: String
    ) async throws -> String // signed tx base64
}

// MARK: - Token account entry

public struct SolanaTokenAccountEntry: Codable, Sendable {
    public let pubkey: SolanaPubkey
    public let mint: SolanaPubkey
    public let amount: SolanaTokenAmount
    public init(pubkey: SolanaPubkey, mint: SolanaPubkey, amount: SolanaTokenAmount) {
        self.pubkey = pubkey; self.mint = mint; self.amount = amount
    }
}
