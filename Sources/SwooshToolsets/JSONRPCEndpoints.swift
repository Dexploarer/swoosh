// SwooshToolsets/JSONRPCEndpoints.swift — RPC endpoint resolution — 0.9R
//
// Maps an `EVMRPCConfig` / `SolanaCluster` to a concrete HTTPS URL.
//
// Resolution order:
//   1. Non-"default" `rpcURLSecretRef` → resolved via `SecretResolving`
//      (Keychain). Lets the user point a chain at a private/paid RPC.
//   2. Env override — `SWOOSH_EVM_RPC_<chainID>` / `SWOOSH_SOLANA_RPC_<id>`.
//   3. Well-known public RPC fallback per chain.
//
// Hard rule: only an endpoint URL is resolved here — never a key.

import Foundation
import SwooshTools

enum RPCEndpointResolver {
    // ── EVM ───────────────────────────────────────────────────────────

    /// Well-known public JSON-RPC endpoints, keyed by EVM chain ID.
    static func defaultEVMURL(chainID: Int) -> String? {
        switch chainID {
        case 1:        return "https://ethereum-rpc.publicnode.com"
        case 11155111: return "https://ethereum-sepolia-rpc.publicnode.com"
        case 137:      return "https://polygon-bor-rpc.publicnode.com"
        case 42161:    return "https://arbitrum-one-rpc.publicnode.com"
        case 8453:     return "https://base-rpc.publicnode.com"
        case 10:       return "https://optimism-rpc.publicnode.com"
        case 56:       return "https://bsc-rpc.publicnode.com"
        case 43114:    return "https://avalanche-c-chain-rpc.publicnode.com"
        default:       return nil
        }
    }

    /// Resolve the JSON-RPC URL for an EVM chain.
    static func resolveEVM(
        config: EVMRPCConfig,
        secrets: any SecretResolving,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> URL {
        let chainID = config.chainID.value
        // 1. Explicit secret ref (non-default).
        let ref = config.rpcURLSecretRef
        if !ref.isEmpty, ref != "default" {
            let raw = try await secrets.resolve(ref: ref)
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.executionFailed("EVM RPC secret '\(ref)' is not a valid URL")
            }
            return url
        }
        // 2. Env override.
        if let envURL = environment["SWOOSH_EVM_RPC_\(chainID)"],
           let url = URL(string: envURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        // 3. Public fallback.
        guard let fallback = defaultEVMURL(chainID: chainID),
              let url = URL(string: fallback) else {
            throw ToolError.executionFailed(
                "No RPC endpoint for EVM chain \(chainID) — set SWOOSH_EVM_RPC_\(chainID) or a Keychain ref")
        }
        return url
    }

    // ── Solana ────────────────────────────────────────────────────────

    /// Well-known public Solana RPC endpoints, keyed by cluster id.
    static func defaultSolanaURL(clusterID: String) -> String? {
        switch clusterID.lowercased() {
        case "mainnet", "mainnet-beta", "mainnetbeta":
            return "https://api.mainnet-beta.solana.com"
        case "devnet":
            return "https://api.devnet.solana.com"
        case "testnet":
            return "https://api.testnet.solana.com"
        default:
            return nil
        }
    }

    /// Resolve the JSON-RPC URL for a Solana cluster.
    static func resolveSolana(
        cluster: SolanaCluster,
        secrets: any SecretResolving,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> URL {
        let ref = cluster.rpcURLSecretRef
        // 1. Explicit secret ref (non-default).
        if !ref.isEmpty, ref != "default" {
            let raw = try await secrets.resolve(ref: ref)
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.executionFailed("Solana RPC secret '\(ref)' is not a valid URL")
            }
            return url
        }
        // 2. Env override.
        let envKey = "SWOOSH_SOLANA_RPC_\(cluster.id.uppercased().replacingOccurrences(of: "-", with: "_"))"
        if let envURL = environment[envKey],
           let url = URL(string: envURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url
        }
        // 3. Public fallback.
        guard let fallback = defaultSolanaURL(clusterID: cluster.id),
              let url = URL(string: fallback) else {
            throw ToolError.executionFailed(
                "No RPC endpoint for Solana cluster '\(cluster.id)' — set \(envKey) or a Keychain ref")
        }
        return url
    }
}
