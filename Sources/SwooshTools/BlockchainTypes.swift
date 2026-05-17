// SwooshTools/BlockchainTypes.swift — Shared EVM and Solana types
//
// Hard rules:
// 1. No private-key or seed-phrase ingestion.
// 2. No browser-cookie ingestion.
// 3. No signing without human approval.
// 4. No broadcasting without human approval.
// 5. No mainnet write without explicit permission.
// 6. No unlimited ERC-20 approval without explicit warning.
// 7. No autonomous swaps/trades in 0.4A.
// 8. Build tools return unsigned transactions only.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Transaction risk summary (shared)
// ═══════════════════════════════════════════════════════════════════

public struct TransactionRiskSummary: Codable, Sendable {
    public let network: String
    public let isMainnet: Bool
    public let from: String
    public let to: String?
    public let asset: String?
    public let amountHuman: String?
    public let estimatedFeeHuman: String?
    public let warnings: [String]
    public let requiresExplicitUserConfirmation: Bool

    public init(
        network: String,
        isMainnet: Bool,
        from: String,
        to: String?,
        asset: String?,
        amountHuman: String?,
        estimatedFeeHuman: String?,
        warnings: [String],
        requiresExplicitUserConfirmation: Bool
    ) {
        self.network = network
        self.isMainnet = isMainnet
        self.from = from
        self.to = to
        self.asset = asset
        self.amountHuman = amountHuman
        self.estimatedFeeHuman = estimatedFeeHuman
        self.warnings = warnings
        self.requiresExplicitUserConfirmation = requiresExplicitUserConfirmation
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - EVM primitive types
// ═══════════════════════════════════════════════════════════════════

public struct EVMChainID: Codable, Sendable, Hashable {
    public let value: Int
    public init(_ value: Int) { self.value = value }

    /// Ethereum mainnet
    public static let mainnet = EVMChainID(1)
    /// Sepolia testnet
    public static let sepolia = EVMChainID(11155111)
    /// Polygon mainnet
    public static let polygon = EVMChainID(137)
    /// Arbitrum One
    public static let arbitrum = EVMChainID(42161)
    /// Base
    public static let base = EVMChainID(8453)

    public var isMainnet: Bool {
        [1, 137, 42161, 8453, 10, 56, 43114, 250].contains(value)
    }
}

public struct EVMAddress: Codable, Sendable, Hashable {
    public let hex: String
    public init(_ hex: String) { self.hex = hex.lowercased() }
}

public struct EVMHexData: Codable, Sendable, Hashable {
    public let hex: String
    public init(_ hex: String) { self.hex = hex }
}

public struct EVMQuantity: Codable, Sendable, Hashable {
    public let hex: String
    public init(_ hex: String) { self.hex = hex }

    /// Create from a decimal UInt64.
    public init(decimal: UInt64) {
        self.hex = "0x" + String(decimal, radix: 16)
    }
}

public enum EVMBlockTag: String, Codable, Sendable {
    case latest
    case earliest
    case pending
    case safe
    case finalized
}

public enum EVMBlockParameter: Codable, Sendable {
    case tag(EVMBlockTag)
    case number(EVMQuantity)
}

public struct EVMRPCConfig: Codable, Sendable {
    public let chainID: EVMChainID
    public let rpcURLSecretRef: String

    public init(chainID: EVMChainID, rpcURLSecretRef: String) {
        self.chainID = chainID
        self.rpcURLSecretRef = rpcURLSecretRef
    }
}

// ── EVM log ───────────────────────────────────────────────────────

public struct EVMLog: Codable, Sendable {
    public let address: EVMAddress
    public let topics: [EVMHexData]
    public let data: EVMHexData
    public let blockNumber: EVMQuantity?
    public let transactionHash: EVMHexData?

    public init(
        address: EVMAddress,
        topics: [EVMHexData],
        data: EVMHexData,
        blockNumber: EVMQuantity? = nil,
        transactionHash: EVMHexData? = nil
    ) {
        self.address = address
        self.topics = topics
        self.data = data
        self.blockNumber = blockNumber
        self.transactionHash = transactionHash
    }
}

// ── EVM unsigned transaction ──────────────────────────────────────

public struct EVMUnsignedTransaction: Codable, Sendable {
    public let chainID: EVMChainID
    public let from: EVMAddress
    public let to: EVMAddress?
    public let valueWei: EVMQuantity?
    public let data: EVMHexData?
    public let gasLimit: EVMQuantity?
    public let maxFeePerGas: EVMQuantity?
    public let maxPriorityFeePerGas: EVMQuantity?
    public let nonce: EVMQuantity?
    public let riskSummary: TransactionRiskSummary

    public init(
        chainID: EVMChainID,
        from: EVMAddress,
        to: EVMAddress?,
        valueWei: EVMQuantity?,
        data: EVMHexData?,
        gasLimit: EVMQuantity?,
        maxFeePerGas: EVMQuantity?,
        maxPriorityFeePerGas: EVMQuantity?,
        nonce: EVMQuantity?,
        riskSummary: TransactionRiskSummary
    ) {
        self.chainID = chainID
        self.from = from
        self.to = to
        self.valueWei = valueWei
        self.data = data
        self.gasLimit = gasLimit
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.nonce = nonce
        self.riskSummary = riskSummary
    }
}

// ── EVM transaction receipt ───────────────────────────────────────

public struct EVMTransactionReceipt: Codable, Sendable {
    public let transactionHash: EVMHexData
    public let blockNumber: EVMQuantity?
    public let status: EVMQuantity?
    public let gasUsed: EVMQuantity?
    public let contractAddress: EVMAddress?
    public let logs: [EVMLog]

    public init(
        transactionHash: EVMHexData,
        blockNumber: EVMQuantity? = nil,
        status: EVMQuantity? = nil,
        gasUsed: EVMQuantity? = nil,
        contractAddress: EVMAddress? = nil,
        logs: [EVMLog] = []
    ) {
        self.transactionHash = transactionHash
        self.blockNumber = blockNumber
        self.status = status
        self.gasUsed = gasUsed
        self.contractAddress = contractAddress
        self.logs = logs
    }
}

// ═══════════════════════════════════════════════════════════════════
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

    public var isMainnet: Bool {
        id.lowercased().contains("mainnet")
    }

    public static let devnet = SolanaCluster(id: "devnet", rpcURLSecretRef: "solana_devnet_rpc")
    public static let testnet = SolanaCluster(id: "testnet", rpcURLSecretRef: "solana_testnet_rpc")
}

public enum SolanaCommitment: String, Codable, Sendable {
    case processed
    case confirmed
    case finalized
}

public struct Lamports: Codable, Sendable, Hashable {
    public let value: UInt64
    public init(_ value: UInt64) { self.value = value }
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
