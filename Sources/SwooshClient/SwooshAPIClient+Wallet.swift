// SwooshClient/SwooshAPIClient+Wallet.swift — 0.4A Wallet ops endpoints
//
// Wire methods for `GET /api/wallet/accounts`, `POST /api/wallet/accounts`,
// the per-account `PATCH` / `DELETE`, and the `POST
// /api/wallet/accounts/{id}/balance` refresh. The dashboard endpoint
// (`GET /api/wallet`) lives on the core client because it predates the
// tier-1 ops push.

import Foundation

extension SwooshAPIClient {
    public func walletAccounts() async throws -> WalletAccountsResponse {
        let request = try makeRequest(method: "GET", path: "api/wallet/accounts", body: nil)
        return try await execute(request, as: WalletAccountsResponse.self)
    }

    public func createWalletAccount(_ body: WalletCreateAccountRequest) async throws -> WalletAccountResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/wallet/accounts", body: encoded)
        return try await execute(request, as: WalletAccountResponse.self)
    }

    public func deleteWalletAccount(id: String) async throws -> WalletAccountsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/wallet/accounts/\(encodedID)", body: nil)
        return try await execute(request, as: WalletAccountsResponse.self)
    }

    public func renameWalletAccount(id: String, body: WalletRenameRequest) async throws -> WalletAccountResponse {
        let encodedID = try pathComponent(id)
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "PATCH", path: "api/wallet/accounts/\(encodedID)", body: encoded)
        return try await execute(request, as: WalletAccountResponse.self)
    }

    public func refreshWalletBalance(id: String) async throws -> WalletBalanceResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/wallet/accounts/\(encodedID)/balance", body: nil)
        return try await execute(request, as: WalletBalanceResponse.self)
    }
}
