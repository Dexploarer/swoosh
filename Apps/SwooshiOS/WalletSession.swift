// Apps/SwooshiOS/WalletSession.swift — Observable wallet facade
//
// SwiftUI bridge over `SwooshWallet.WalletStore`. Holds the in-memory
// view-model state (accounts, last-known balances, loading flags) and
// owns the actor that does the actual Keychain + RPC work.

import Foundation
import Observation
import SwooshWallet

@MainActor
@Observable
final class WalletSession {
    let store: WalletStore
    private(set) var accounts: [WalletAccount] = []
    private(set) var balances: [UUID: WalletBalance] = [:]
    private(set) var refreshing: Set<UUID> = []
    private(set) var error: String?
    /// True while the account list is being loaded from the Keychain.
    private(set) var loadingAccounts: Bool = false
    /// True once `reload()` has resolved at least once — lets the UI tell
    /// "still loading" apart from "genuinely empty".
    private(set) var hasLoadedAccounts: Bool = false

    init(store: WalletStore = WalletStore()) {
        self.store = store
    }

    func reload() async {
        loadingAccounts = true
        defer {
            loadingAccounts = false
            hasLoadedAccounts = true
        }
        accounts = await store.accounts()
    }

    func create(chain: WalletChain, label: String) async {
        error = nil
        do {
            let account = try await store.createAccount(chain: chain, label: label)
            await reload()
            await refreshBalance(for: account)
        } catch {
            self.error = "Couldn't create account: \(error)"
        }
    }

    func delete(_ account: WalletAccount) async {
        error = nil
        do {
            try await store.deleteAccount(account)
            balances.removeValue(forKey: account.id)
            await reload()
        } catch {
            self.error = "Couldn't delete account: \(error)"
        }
    }

    func clearError() {
        error = nil
    }

    func refreshAllBalances() async {
        error = nil
        for account in accounts {
            await refreshBalance(for: account)
        }
    }

    func refreshBalance(for account: WalletAccount) async {
        refreshing.insert(account.id)
        defer { refreshing.remove(account.id) }
        do {
            let balance = try await store.refreshBalance(for: account)
            balances[account.id] = balance
        } catch {
            self.error = "RPC error for \(account.chain.displayName): \(error)"
        }
    }
}
