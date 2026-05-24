// SwooshWallet/WalletAccount.swift — Public-side account record — 0.9A
//
// One row per (chain, address) pair the user has saved. Addresses are
// public — these can live in UserDefaults / JSON without ACL. Secret
// keys for these accounts live in KeychainKeyStore, keyed by id.

import Foundation

public struct WalletAccount: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let chain: WalletChain
    public let address: String
    public var label: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        chain: WalletChain,
        address: String,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chain = chain
        self.address = address
        self.label = label
        self.createdAt = createdAt
    }

    /// Convenience truncation for the wallet list ("0x1234…abcd").
    public var truncatedAddress: String {
        guard address.count > 12 else { return address }
        let head = address.prefix(6)
        let tail = address.suffix(4)
        return "\(head)…\(tail)"
    }
}

/// A balance read for one account. Stored only in memory; refreshed on
/// pull-to-refresh.
public struct WalletBalance: Sendable, Equatable {
    public let account: WalletAccount
    public let rawAmount: String  // smallest unit, e.g. lamports / wei
    public let formatted: String  // human, e.g. "1.234 SOL"
    public let fetchedAt: Date

    public init(account: WalletAccount, rawAmount: String, formatted: String, fetchedAt: Date = Date()) {
        self.account = account
        self.rawAmount = rawAmount
        self.formatted = formatted
        self.fetchedAt = fetchedAt
    }
}
