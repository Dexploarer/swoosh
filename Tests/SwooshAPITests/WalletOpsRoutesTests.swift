// Tests/SwooshAPITests/WalletOpsRoutesTests.swift — Tier 1
//
// Wire-level coverage for /api/wallet/accounts/* CRUD + balance refresh.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

private func sampleAccount(
    id: String = "acc-1",
    chain: String = "solana",
    label: String = "Main"
) -> WalletAccountSummary {
    WalletAccountSummary(
        id: id,
        chain: chain,
        address: "ABC123XYZ456",
        truncatedAddress: "ABC1…3456",
        label: label,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Suite("Wallet ops routes")
struct WalletOpsRoutesTests {

    @Test("GET /api/wallet/accounts returns the source list")
    func listAccounts() async throws {
        let sources = SwooshAPIRuntimeSources(
            walletAccounts: {
                WalletAccountsResponse(accounts: [sampleAccount(id: "a"), sampleAccount(id: "b")])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/wallet/accounts", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try walletTestDecoder().decode(WalletAccountsResponse.self, from: Data(buffer: response.body))
                #expect(body.accounts.map(\.id) == ["a", "b"])
            }
        }
    }

    @Test("POST /api/wallet/accounts creates an account")
    func createAccount() async throws {
        let received = WalletCreateBox()
        let sources = SwooshAPIRuntimeSources(
            createWalletAccount: { request in
                await received.set(request)
                return WalletAccountResponse(
                    account: sampleAccount(id: "new", chain: request.chain, label: request.label),
                    message: "Wallet account created."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(WalletCreateAccountRequest(
                chain: "ethereum",
                label: "Trading"
            ))
            try await client.execute(
                uri: "/api/wallet/accounts", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try walletTestDecoder().decode(WalletAccountResponse.self, from: Data(buffer: response.body))
                #expect(decoded.account.chain == "ethereum")
                #expect(decoded.account.label == "Trading")
            }
        }
        #expect(await received.value?.chain == "ethereum")
        #expect(await received.value?.label == "Trading")
    }

    @Test("DELETE /api/wallet/accounts/:id removes the account")
    func deleteAccount() async throws {
        let captured = WalletIDBox()
        let sources = SwooshAPIRuntimeSources(
            deleteWalletAccount: { id in
                await captured.set(id)
                return WalletAccountsResponse(accounts: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/wallet/accounts/abc", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try walletTestDecoder().decode(WalletAccountsResponse.self, from: Data(buffer: response.body))
                #expect(body.accounts.isEmpty)
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("PATCH /api/wallet/accounts/:id renames the account")
    func renameAccount() async throws {
        let receivedID = WalletIDBox()
        let receivedBody = WalletRenameBox()
        let sources = SwooshAPIRuntimeSources(
            renameWalletAccount: { id, body in
                await receivedID.set(id)
                await receivedBody.set(body)
                return WalletAccountResponse(
                    account: sampleAccount(id: id, label: body.label),
                    message: "Wallet renamed."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(WalletRenameRequest(label: "Hot"))
            try await client.execute(
                uri: "/api/wallet/accounts/abc", method: .patch,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try walletTestDecoder().decode(WalletAccountResponse.self, from: Data(buffer: response.body))
                #expect(decoded.account.label == "Hot")
            }
        }
        #expect(await receivedID.value == "abc")
        #expect(await receivedBody.value?.label == "Hot")
    }

    @Test("POST /api/wallet/accounts/:id/balance refreshes balance")
    func refreshBalance() async throws {
        let captured = WalletIDBox()
        let sources = SwooshAPIRuntimeSources(
            refreshWalletBalance: { id in
                await captured.set(id)
                return WalletBalanceResponse(
                    account: sampleAccount(id: id),
                    rawAmount: "1500000000",
                    formatted: "1.5 SOL",
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_100)
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/wallet/accounts/abc/balance", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try walletTestDecoder().decode(WalletBalanceResponse.self, from: Data(buffer: response.body))
                #expect(decoded.formatted == "1.5 SOL")
            }
        }
        #expect(await captured.value == "abc")
    }
}

private actor WalletIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor WalletCreateBox {
    private var stored: WalletCreateAccountRequest?
    func set(_ value: WalletCreateAccountRequest) { stored = value }
    var value: WalletCreateAccountRequest? { stored }
}

private actor WalletRenameBox {
    private var stored: WalletRenameRequest?
    func set(_ value: WalletRenameRequest) { stored = value }
    var value: WalletRenameRequest? { stored }
}

private func walletTestDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
