// SwooshWallet/WalletStore.swift — Wallet facade — 0.9A
//
// Holds:
//   • the per-chain metadata index (JSON-encoded WalletAccount list)
//     persisted in UserDefaults — addresses + labels only, never secrets
//   • a KeychainKeyStore for the secret material
//   • an RPC-client cache, one per chain, optionally overridden
//
// The iOS app's @Observable WalletSession wraps an instance of this so
// SwiftUI views can drive create/list/balance flows without touching
// Keychain APIs directly.

import Foundation
import BigInt

public actor WalletStore {
    public enum Defaults {
        public static let accountsKey = "ai.swoosh.wallet.accounts.v1"
        public static let rpcOverridePrefix = "ai.swoosh.wallet.rpc."
    }

    private let keychain: KeychainKeyStore
    private let userDefaults: UserDefaults
    private var rpcOverrides: [WalletChain: URL] = [:]
    private var rpcClients: [WalletChain: MultiEndpointRPC] = [:]

    public init(
        keychain: KeychainKeyStore = KeychainKeyStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.rpcOverrides = Self.loadRPCOverrides(from: userDefaults)
    }

    // MARK: - Account index

    public func accounts() -> [WalletAccount] {
        guard let data = userDefaults.data(forKey: Defaults.accountsKey),
              let list = try? JSONDecoder().decode([WalletAccount].self, from: data) else {
            return []
        }
        return list
    }

    /// Persist the account index to UserDefaults. JSONEncoder failure is
    /// theoretically impossible for `[WalletAccount]` (every field is a
    /// `Codable` value type) but if it ever happened, silently writing an
    /// empty blob would mean every account vanishes on next launch with
    /// the secret material orphaned in the Keychain forever. Throwing
    /// `EncodingError` here makes the failure visible to the caller.
    private func writeAccounts(_ list: [WalletAccount]) throws {
        let data = try JSONEncoder().encode(list)
        userDefaults.set(data, forKey: Defaults.accountsKey)
    }

    // MARK: - Create / import

    /// Generate a fresh keypair for the given chain. Public address is
    /// returned synchronously; the secret is written to the Keychain with
    /// biometric ACL. Caller is responsible for surfacing the address.
    public func createAccount(chain: WalletChain, label: String) async throws -> WalletAccount {
        let pair = try WalletKeyFactory.generate(chain: chain)
        let account = WalletAccount(chain: chain, address: pair.address, label: label)
        try await keychain.save(secret: pair.secret, for: account)
        var list = accounts()
        list.append(account)
        try writeAccounts(list)
        return account
    }

    /// Rename a stored account. Returns `false` when the account ID
    /// doesn't match any persisted record so the caller can surface a
    /// "not found" UI state instead of silently doing nothing.
    @discardableResult
    public func rename(account: WalletAccount, to label: String) throws -> Bool {
        var list = accounts()
        guard let idx = list.firstIndex(where: { $0.id == account.id }) else { return false }
        list[idx].label = label
        try writeAccounts(list)
        return true
    }

    public func deleteAccount(_ account: WalletAccount) async throws {
        try await keychain.delete(account: account)
        var list = accounts()
        list.removeAll(where: { $0.id == account.id })
        try writeAccounts(list)
    }

    // MARK: - Balance reads

    public func refreshBalance(for account: WalletAccount) async throws -> WalletBalance {
        let client = rpcClient(for: account.chain)
        switch account.chain {
        case .solana:
            let lamports = try await SolanaRPC.getBalance(client: client, address: account.address)
            return WalletBalance(
                account: account,
                rawAmount: String(lamports),
                formatted: formatNative(value: BigUInt(lamports), chain: account.chain)
            )
        case .ethereum, .base, .bnb:
            let wei = try await EVMRPC.getBalance(client: client, address: account.address)
            return WalletBalance(
                account: account,
                rawAmount: wei.description,
                formatted: formatNative(value: wei, chain: account.chain)
            )
        }
    }

    // MARK: - RPC config

    public func rpcOverride(for chain: WalletChain) -> URL? {
        rpcOverrides[chain]
    }

    public func setRPCOverride(_ url: URL?, for chain: WalletChain) {
        let key = Defaults.rpcOverridePrefix + chain.rawValue
        if let url {
            rpcOverrides[chain] = url
            userDefaults.set(url.absoluteString, forKey: key)
        } else {
            rpcOverrides.removeValue(forKey: chain)
            userDefaults.removeObject(forKey: key)
        }
        rpcClients.removeValue(forKey: chain)
    }

    public func rpcURL(for chain: WalletChain) -> URL {
        rpcOverrides[chain] ?? chain.defaultRPCURL
    }

    private func rpcClient(for chain: WalletChain) -> MultiEndpointRPC {
        if let cached = rpcClients[chain] { return cached }
        let primary = rpcURL(for: chain)
        // If the user has set an override, ignore the chain's fallback list —
        // their endpoint is the source of truth.
        let fallbacks = rpcOverrides[chain] == nil ? chain.fallbackRPCURLs : []
        let client = MultiEndpointRPC(primary: primary, fallbacks: fallbacks)
        rpcClients[chain] = client
        return client
    }

    private static func loadRPCOverrides(from defaults: UserDefaults) -> [WalletChain: URL] {
        var map: [WalletChain: URL] = [:]
        for chain in WalletChain.allCases {
            let key = Defaults.rpcOverridePrefix + chain.rawValue
            if let raw = defaults.string(forKey: key), let url = URL(string: raw) {
                map[chain] = url
            }
        }
        return map
    }

    // MARK: - Formatting

    public nonisolated func formatNative(value: BigUInt, chain: WalletChain) -> String {
        let decimals = chain.nativeDecimals
        let divisor = BigUInt(10).power(decimals)
        let whole = value / divisor
        let remainder = value % divisor

        let remainderStr = String(remainder)
        let paddedRemainder = String(repeating: "0", count: max(0, decimals - remainderStr.count)) + remainderStr
        let trimmed = paddedRemainder.prefix(6).reversed().drop(while: { $0 == "0" }).reversed()
        let suffix = String(trimmed)
        let formatted = suffix.isEmpty ? "\(whole)" : "\(whole).\(suffix)"
        return "\(formatted) \(chain.nativeSymbol)"
    }
}
