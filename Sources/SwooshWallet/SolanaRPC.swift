// SwooshWallet/SolanaRPC.swift — Solana JSON-RPC convenience helpers — 0.9A
//
// Only read paths are exercised here today: `getBalance` returns lamports
// for a base58 address. Sending lands in a follow-up slice — see
// `WalletStore.refreshBalance` for the call site.

import Foundation

public enum SolanaRPC {
    private struct GetBalanceResult: Decodable {
        let value: UInt64
    }

    /// Lamports for the given base58 address.
    public static func getBalance(
        client: MultiEndpointRPC, address: String
    ) async throws -> UInt64 {
        let result: GetBalanceResult = try await client.call(
            "getBalance",
            params: [.string(address)]
        )
        return result.value
    }
}
