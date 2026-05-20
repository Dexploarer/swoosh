// SwooshWallet/WalletStore.swift — Wallet facade
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
    private var rpcClients: [WalletChain: RPCClient] = [:]

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

    private func writeAccounts(_ list: [WalletAccount]) {
        let data = (try? JSONEncoder().encode(list)) ?? Data()
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
        writeAccounts(list)
        return account
    }

    public func rename(account: WalletAccount, to label: String) {
        var list = accounts()
        guard let idx = list.firstIndex(where: { $0.id == account.id }) else { return }
        list[idx].label = label
        writeAccounts(list)
    }

    public func deleteAccount(_ account: WalletAccount) async throws {
        try await keychain.delete(account: account)
        var list = accounts()
        list.removeAll(where: { $0.id == account.id })
        writeAccounts(list)
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

    private func rpcClient(for chain: WalletChain) -> RPCClient {
        if let cached = rpcClients[chain] { return cached }
        let client = RPCClient(url: rpcURL(for: chain))
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
