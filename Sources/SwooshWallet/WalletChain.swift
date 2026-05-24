// SwooshWallet/WalletChain.swift — Supported chains + RPC endpoints — 0.9A
//
// The iOS app's in-app wallet supports four chains. Solana uses ed25519
// (CryptoKit Curve25519.Signing), the EVM chains share secp256k1 + Keccak256
// address derivation. Each chain carries its mainnet RPC URL and native
// asset metadata so the wallet UI can render balances without consulting
// the daemon. RPC URLs default to public endpoints — users can override
// via WalletStore.setRPCOverride to point at Helius / Alchemy / their own.

import Foundation

public enum WalletChain: String, Codable, Sendable, CaseIterable, Hashable {
    case solana
    case ethereum
    case base
    case bnb

    public var displayName: String {
        switch self {
        case .solana:   "Solana"
        case .ethereum: "Ethereum"
        case .base:     "Base"
        case .bnb:      "BNB Chain"
        }
    }

    public var nativeSymbol: String {
        switch self {
        case .solana:   "SOL"
        case .ethereum: "ETH"
        case .base:     "ETH"
        case .bnb:      "BNB"
        }
    }

    /// Decimal places of the native asset's smallest unit.
    public var nativeDecimals: Int {
        switch self {
        case .solana:   9  // lamports
        case .ethereum, .base, .bnb: 18  // wei
        }
    }

    /// Stable color hint for UI rendering (hex RGB, no #).
    public var tintHex: String {
        switch self {
        case .solana:   "9945FF"
        case .ethereum: "627EEA"
        case .base:     "0052FF"
        case .bnb:      "F0B90B"
        }
    }

    /// EIP-155 chain ID for EVM chains. nil for Solana.
    public var evmChainID: Int? {
        switch self {
        case .solana:   nil
        case .ethereum: 1
        case .base:     8453
        case .bnb:      56
        }
    }

    /// Whether the chain uses Ethereum-style secp256k1 + keccak256 addressing.
    public var isEVM: Bool { evmChainID != nil }

    /// Public RPC endpoint used by default. Production deployments should
    /// override these with paid endpoints (Helius for Solana, Alchemy /
    /// public-node providers for EVM). Read paths only; we never push
    /// signed txs without explicit per-account confirmation.
    ///
    /// Defaults favor PublicNode where possible — `api.mainnet-beta.solana.com`
    /// and `eth.llamarpc.com` are both heavily rate-limited from consumer
    /// IPs and were the source of phantom "RPC error" surfaces on first
    /// account creation.
    public var defaultRPCURL: URL {
        switch self {
        case .solana:   URL(string: "https://solana-rpc.publicnode.com")!
        case .ethereum: URL(string: "https://ethereum-rpc.publicnode.com")!
        case .base:     URL(string: "https://base-rpc.publicnode.com")!
        case .bnb:      URL(string: "https://bsc-rpc.publicnode.com")!
        }
    }

    /// Backup endpoints tried in order when `defaultRPCURL` fails. Keeps
    /// the original chain-official endpoints around so we degrade rather
    /// than fail outright if PublicNode is down.
    public var fallbackRPCURLs: [URL] {
        switch self {
        case .solana:
            return [URL(string: "https://api.mainnet-beta.solana.com")!]
        case .ethereum:
            return [URL(string: "https://eth.llamarpc.com")!,
                    URL(string: "https://rpc.ankr.com/eth")!]
        case .base:
            return [URL(string: "https://mainnet.base.org")!]
        case .bnb:
            return [URL(string: "https://bsc-dataseed.binance.org")!,
                    URL(string: "https://bsc-dataseed1.defibit.io")!]
        }
    }
}
