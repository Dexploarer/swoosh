// Apps/SwooshiOS/WalletSession.swift — Observable wallet facade
//
// SwiftUI bridge over `SwooshWallet.WalletStore`. Holds the in-memory
// view-model state (accounts, last-known balances, loading flags) and
// owns the actor that does the actual Keychain + RPC work.
//
// Error model: there are two distinct error surfaces.
//   • `error`         — account-management failures (create/delete).
//                       These are real, they block sheet dismissal, and
//                       they should be rare. Setter is intentional.
//   • `balanceErrors` — per-account balance-fetch failures. Public-RPC
//                       rate limits are common enough that these get
//                       demoted to a soft per-row badge instead of a
//                       modal-blocking error. The account itself was
//                       still created successfully.
//
// This split fixes the bug where creating a wallet — which works fine —
// produced an "RPC error" toast because the immediate balance refresh
// hit a rate-limited public endpoint.

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
    /// Account-management errors (create/delete). Surfaces in the modal
    /// sheets and blocks dismissal.
    private(set) var error: String?
    /// Balance-fetch errors keyed by account.id. Surfaces as a small
    /// "balance unavailable, tap to retry" badge on the account row.
    /// Never blocks creation flow.
    private(set) var balanceErrors: [UUID: String] = [:]
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
            // Balance refresh is best-effort — the account is created and
            // persisted regardless of whether the public RPC responds.
            await refreshBalance(for: account)
        } catch {
            self.error = "Couldn't create account: \(humanize(error))"
        }
    }

    func delete(_ account: WalletAccount) async {
        error = nil
        do {
            try await store.deleteAccount(account)
            balances.removeValue(forKey: account.id)
            balanceErrors.removeValue(forKey: account.id)
            await reload()
        } catch {
            self.error = "Couldn't delete account: \(humanize(error))"
        }
    }

    func clearError() {
        error = nil
    }

    func refreshAllBalances() async {
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
            balanceErrors.removeValue(forKey: account.id)
        } catch {
            // Per-account soft error. Does NOT touch `self.error`.
            balanceErrors[account.id] = humanize(error)
        }
    }

    // MARK: - Helpers

    /// Translate the raw `RPCError`/network errors into a one-liner the UI
    /// can show. Public-RPC rate limits are the single most common cause
    /// of "RPC errors" reported by users, so we name them explicitly.
    private func humanize(_ error: Error) -> String {
        if let rpc = error as? RPCError {
            switch rpc {
            case .transport(let msg):
                return "Network unavailable — \(msg)"
            case .httpStatus(let code, _):
                if code == 429 {
                    return "Public RPC rate-limited. Set a custom endpoint in Settings."
                }
                return "RPC returned HTTP \(code)."
            case .decode:
                return "RPC returned an unexpected response. The endpoint may be down."
            case .rpc(let code, let msg):
                return "RPC error \(code): \(msg)"
            case .unexpectedResponse(let msg):
                return msg
            }
        }
        return error.localizedDescription
    }
}
