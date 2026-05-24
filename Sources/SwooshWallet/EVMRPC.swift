// SwooshWallet/EVMRPC.swift — Ethereum-family JSON-RPC helpers — 0.9A
//
// Only read paths are exercised today: `eth_getBalance` returns the
// hex-encoded wei balance, which this helper decodes to BigUInt after
// stripping the `0x` prefix.

import Foundation
import BigInt

public enum EVMRPC {
    /// Wei balance for the given hex address.
    public static func getBalance(
        client: MultiEndpointRPC, address: String
    ) async throws -> BigUInt {
        let hexBalance: String = try await client.call(
            "eth_getBalance",
            params: [.string(address), .string("latest")]
        )
        var hex = hexBalance
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex = String(hex.dropFirst(2))
        }
        if hex.isEmpty { return 0 }
        guard let value = BigUInt(hex, radix: 16) else {
            throw RPCError.decode("invalid hex balance: \(hexBalance)")
        }
        return value
    }
}
