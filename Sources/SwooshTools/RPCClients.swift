// SwooshTools/RPCClients.swift — Blockchain RPC Client Protocols
//
// These protocols abstract the JSON-RPC layer for EVM and Solana.
// Concrete implementations live outside SwooshTools.
// No private keys flow through these protocols.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - EVM RPC client
// ═══════════════════════════════════════════════════════════════════

public protocol EVMRPCClient: Sendable {
    func chainID(config: EVMRPCConfig) async throws -> EVMChainID
    func blockNumber(config: EVMRPCConfig) async throws -> EVMQuantity
    func getBalance(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity
    func getTransactionCount(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMQuantity
    func getCode(config: EVMRPCConfig, address: EVMAddress, block: EVMBlockParameter) async throws -> EVMHexData
    func call(config: EVMRPCConfig, call: EVMContractCallInput) async throws -> EVMHexData
    func estimateGas(config: EVMRPCConfig, tx: EVMTxEstimateGasInput) async throws -> EVMQuantity
    func getLogs(config: EVMRPCConfig, filter: EVMGetLogsInput) async throws -> [EVMLog]
    func sendRawTransaction(config: EVMRPCConfig, signedTransaction: EVMHexData) async throws -> EVMHexData
    func getTransactionReceipt(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> EVMTransactionReceipt?
    func getTransactionByHash(config: EVMRPCConfig, transactionHash: EVMHexData) async throws -> String? // raw JSON
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Solana RPC client
// ═══════════════════════════════════════════════════════════════════

public protocol SolanaRPCClient: Sendable {
    func getBalance(cluster: SolanaCluster, pubkey: SolanaPubkey, commitment: SolanaCommitment) async throws -> Lamports
    func getAccountInfo(cluster: SolanaCluster, input: SolanaAccountInfoInput) async throws -> SolanaAccountInfoOutput
    func getTokenAccountBalance(cluster: SolanaCluster, tokenAccount: SolanaPubkey, commitment: SolanaCommitment) async throws -> SolanaTokenAmount
    func getTokenAccountsByOwner(cluster: SolanaCluster, input: SolanaTokenAccountsByOwnerInput) async throws -> [SolanaTokenAccountEntry]
    func getSignaturesForAddress(cluster: SolanaCluster, input: SolanaSignaturesForAddressInput) async throws -> [SolanaSignatureInfo]
    func getTransaction(cluster: SolanaCluster, input: SolanaGetTransactionInput) async throws -> SolanaGetTransactionOutput
    func getSignatureStatuses(cluster: SolanaCluster, signatures: [SolanaSignature], searchTransactionHistory: Bool) async throws -> [SolanaSignatureStatus]
    func getLatestBlockhash(cluster: SolanaCluster, commitment: SolanaCommitment) async throws -> SolanaGetLatestBlockhashOutput
    func simulateTransaction(cluster: SolanaCluster, input: SolanaTxSimulateInput) async throws -> SolanaTxSimulateOutput
    func sendTransaction(cluster: SolanaCluster, input: SolanaTxSendSignedInput) async throws -> SolanaSignature
    func requestAirdrop(cluster: SolanaCluster, pubkey: SolanaPubkey, lamports: Lamports) async throws -> SolanaSignature
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - File access protocol
// ═══════════════════════════════════════════════════════════════════

/// Abstraction for sandboxed file access via approved bookmarks.
public protocol FileAccessing: Sendable {
    func resolveBookmark(id: String) async throws -> URL
    func listDirectory(root: URL, relativePath: String?, includeHidden: Bool, maxDepth: Int) async throws -> [FileEntry]
    func readFile(root: URL, relativePath: String, maxBytes: Int?) async throws -> (content: String, truncated: Bool, redaction: RedactionReport?)
    func writeFile(root: URL, relativePath: String, content: String, createBackup: Bool) async throws -> (bytesWritten: Int64, backupPath: String?)
    func deleteFile(root: URL, relativePath: String) async throws
    func searchFiles(root: URL, query: String, filePattern: String?, maxResults: Int?) async throws -> [FileSearchMatch]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Process runner protocol
// ═══════════════════════════════════════════════════════════════════

/// Abstraction for running shell processes (git, swift, etc.).
public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult
}

public struct ProcessResult: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Secret resolving (Keychain abstraction)
// ═══════════════════════════════════════════════════════════════════

/// Resolves secret references (e.g. Keychain labels) into their raw values.
/// Implementations live in SwooshSecrets; tools never store the value.
public protocol SecretResolving: Sendable {
    /// Resolve a named secret reference. Throws if not found or access denied.
    func resolve(ref: String) async throws -> String
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool dependencies
// ═══════════════════════════════════════════════════════════════════

/// All dependencies needed by tool implementations. Injected at registration.
public struct ToolDependencies: Sendable {
    public let firewall: any Firewall
    public let audit: any AuditLogging
    public let approvals: any ApprovalRequesting
    public let safetyConfig: SwooshSafetyConfig
    public let fileAccess: any FileAccessing
    public let processRunner: any ProcessRunning
    public let evmClient: (any EVMRPCClient)?
    public let solanaClient: (any SolanaRPCClient)?
    public let walletBridge: (any WalletBridge)?
    /// Resolves Keychain secret refs — used by trade tools that need a private key at call time.
    public let secrets: any SecretResolving

    public init(
        firewall: any Firewall,
        audit: any AuditLogging,
        approvals: any ApprovalRequesting,
        safetyConfig: SwooshSafetyConfig = .defaultAgent,
        fileAccess: any FileAccessing,
        processRunner: any ProcessRunning,
        evmClient: (any EVMRPCClient)? = nil,
        solanaClient: (any SolanaRPCClient)? = nil,
        walletBridge: (any WalletBridge)? = nil,
        secrets: any SecretResolving = NullSecretResolver()
    ) {
        self.firewall = firewall
        self.audit = audit
        self.approvals = approvals
        self.safetyConfig = safetyConfig
        self.fileAccess = fileAccess
        self.processRunner = processRunner
        self.evmClient = evmClient
        self.solanaClient = solanaClient
        self.walletBridge = walletBridge
        self.secrets = secrets
    }
}

/// Resolver used when no secret store is configured.
public struct NullSecretResolver: SecretResolving {
    public init() {}
    public func resolve(ref: String) async throws -> String {
        throw ToolError.executionFailed("No SecretResolver configured — cannot access secret '\(ref)'")
    }
}
