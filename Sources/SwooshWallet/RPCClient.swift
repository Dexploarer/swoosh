// SwooshWallet/RPCClient.swift — JSON-RPC clients for Solana + EVM
//
// One actor per (URL, chain). Holds a URLSession and serializes outbound
// JSON-RPC envelopes. The wallet UI never talks to the daemon to fetch
// balances — the phone hits public RPCs directly so balance reads work
// even when swooshd is offline.
//
// Only read paths are exercised here today: getBalance for Solana,
// eth_getBalance for EVM. Sending will land in a follow-up.

import Foundation
import BigInt

public enum RPCError: Error, Sendable {
    case transport(String)
    case decode(String)
    case rpc(code: Int, message: String)
    case unexpectedResponse(String)
}

private struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [JSONValue]
}

private struct JSONRPCResponse<T: Decodable>: Decodable {
    let jsonrpc: String?
    let id: Int?
    let result: T?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

/// Minimal JSON value type for encoding heterogeneous RPC params.
public enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i):    try container.encode(i)
        case .bool(let b):   try container.encode(b)
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

public actor RPCClient {
    public let url: URL
    private let session: URLSession
    private var nextID: Int = 1

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func call<T: Decodable>(
        _ method: String,
        params: [JSONValue],
        as: T.Type = T.self
    ) async throws -> T {
        let id = nextID
        nextID += 1

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let envelope = JSONRPCRequest(id: id, method: method, params: params)
        do {
            request.httpBody = try JSONEncoder().encode(envelope)
        } catch {
            throw RPCError.transport("encode failed: \(error)")
        }

        let data: Data
        do {
            let (responseData, _) = try await session.data(for: request)
            data = responseData
        } catch {
            throw RPCError.transport(error.localizedDescription)
        }

        let response: JSONRPCResponse<T>
        do {
            response = try JSONDecoder().decode(JSONRPCResponse<T>.self, from: data)
        } catch {
            throw RPCError.decode("\(error) — body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        }

        if let err = response.error {
            throw RPCError.rpc(code: err.code, message: err.message)
        }
        guard let result = response.result else {
            throw RPCError.unexpectedResponse("missing result")
        }
        return result
    }
}

// MARK: - Solana

public enum SolanaRPC {
    private struct GetBalanceResult: Decodable {
        let value: UInt64
    }

    /// Lamports for the given base58 address.
    public static func getBalance(client: RPCClient, address: String) async throws -> UInt64 {
        let result: GetBalanceResult = try await client.call(
            "getBalance",
            params: [.string(address)]
        )
        return result.value
    }
}

// MARK: - EVM

public enum EVMRPC {
    /// Wei balance for the given hex address.
    public static func getBalance(client: RPCClient, address: String) async throws -> BigUInt {
        let hexBalance: String = try await client.call(
            "eth_getBalance",
            params: [.string(address), .string("latest")]
        )
        var s = hexBalance
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        if s.isEmpty { return 0 }
        guard let value = BigUInt(s, radix: 16) else {
            throw RPCError.decode("invalid hex balance: \(hexBalance)")
        }
        return value
    }
}
