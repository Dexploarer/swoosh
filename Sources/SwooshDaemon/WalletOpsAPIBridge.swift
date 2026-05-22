// SwooshDaemon/WalletOpsAPIBridge.swift — Wallet ops ↔ HTTP API
//
// CRUD on `WalletStore` accounts plus balance refresh. Higher-level
// ops (sign / send / swap) flow through the agent tool surface; the
// API caller drives those via POST /api/tools/:name/execute.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshWallet

extension SwooshDaemon {

    static func walletAccountSummary(_ account: WalletAccount) -> WalletAccountSummary {
        WalletAccountSummary(
            id: account.id.uuidString,
            chain: account.chain.rawValue,
            address: account.address,
            truncatedAddress: account.truncatedAddress,
            label: account.label,
            createdAt: account.createdAt
        )
    }

    static func walletAccountsResponse(store: WalletStore) async -> WalletAccountsResponse {
        let accounts = await store.accounts()
            .sorted { $0.createdAt < $1.createdAt }
        return WalletAccountsResponse(accounts: accounts.map(walletAccountSummary))
    }

    static func createWalletAccountResponse(
        store: WalletStore,
        request: WalletCreateAccountRequest
    ) async throws -> WalletAccountResponse {
        guard let chain = WalletChain(rawValue: request.chain) else {
            throw APIError.badRequest("unknown chain: \(request.chain)")
        }
        let trimmedLabel = request.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw APIError.badRequest("wallet label is empty")
        }
        let account: WalletAccount
        do {
            account = try await store.createAccount(chain: chain, label: trimmedLabel)
        } catch {
            throw APIError.badRequest("could not create wallet: \(error.localizedDescription)")
        }
        return WalletAccountResponse(
            account: walletAccountSummary(account),
            message: "Wallet account created."
        )
    }

    static func deleteWalletAccountResponse(
        store: WalletStore,
        id: String
    ) async throws -> WalletAccountsResponse {
        guard let account = await findWalletAccount(store: store, id: id) else {
            throw APIError.notFound("wallet account not found: \(id)")
        }
        do {
            try await store.deleteAccount(account)
        } catch {
            throw APIError.badRequest("could not delete wallet: \(error.localizedDescription)")
        }
        return await walletAccountsResponse(store: store)
    }

    static func renameWalletAccountResponse(
        store: WalletStore,
        id: String,
        request: WalletRenameRequest
    ) async throws -> WalletAccountResponse {
        let trimmedLabel = request.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw APIError.badRequest("wallet label is empty")
        }
        guard let account = await findWalletAccount(store: store, id: id) else {
            throw APIError.notFound("wallet account not found: \(id)")
        }
        await store.rename(account: account, to: trimmedLabel)
        guard let refreshed = await findWalletAccount(store: store, id: id) else {
            throw APIError.notFound("wallet account disappeared after rename: \(id)")
        }
        return WalletAccountResponse(
            account: walletAccountSummary(refreshed),
            message: "Wallet renamed."
        )
    }

    static func refreshWalletBalanceResponse(
        store: WalletStore,
        id: String
    ) async throws -> WalletBalanceResponse {
        guard let account = await findWalletAccount(store: store, id: id) else {
            throw APIError.notFound("wallet account not found: \(id)")
        }
        let balance: WalletBalance
        do {
            balance = try await store.refreshBalance(for: account)
        } catch {
            throw APIError.badRequest("could not refresh balance: \(error.localizedDescription)")
        }
        return WalletBalanceResponse(
            account: walletAccountSummary(balance.account),
            rawAmount: balance.rawAmount,
            formatted: balance.formatted,
            fetchedAt: balance.fetchedAt
        )
    }

    // MARK: - private

    private static func findWalletAccount(store: WalletStore, id: String) async -> WalletAccount? {
        // Exact UUID or exact label only — prefix matching is ambiguous and
        // can target the wrong account when two UUIDs share a prefix.
        let accounts = await store.accounts()
        return accounts.first { $0.id.uuidString == id || $0.label == id }
    }
}
