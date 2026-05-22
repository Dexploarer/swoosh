// SwooshWallet/RPCClient.swift — JSON-RPC clients for Solana + EVM
//
// One actor per (URL, chain). Holds a URLSession and serializes outbound
// JSON-RPC envelopes. The wallet UI never talks to the daemon to fetch
// balances — the phone hits public RPCs directly so balance reads work
// even when swooshd is offline.
//
// Only read paths are exercised here today: getBalance for Solana,
// eth_getBalance for EVM. Sending will land in a follow-up.
//
// Robustness: requests are bounded by a 15 s timeout, non-2xx HTTP
// responses are surfaced as `RPCError.transport` (not silently parsed as
// JSON-RPC, which used to throw a misleading `decode` error when a
// rate-limited endpoint returned an HTML 429 body), and `MultiEndpointRPC`
// composes a primary client with an ordered list of fallbacks so a single
// flaky endpoint can't fail the whole balance refresh.

import Foundation
import BigInt
import os

private let rpcLog = Logger(subsystem: "ai.swoosh", category: "wallet.rpc")

public enum RPCError: Error, Sendable {
    case transport(String)
    case decode(String)
    case rpc(code: Int, message: String)
    case unexpectedResponse(String)
    case httpStatus(Int, body: String)
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
    private let timeoutSeconds: TimeInterval
    private var nextID: Int = 1

    public init(
        url: URL,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 15
    ) {
        self.url = url
        self.session = session
        self.timeoutSeconds = timeoutSeconds
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
        request.timeoutInterval = timeoutSeconds

        let envelope = JSONRPCRequest(id: id, method: method, params: params)
        do {
            request.httpBody = try JSONEncoder().encode(envelope)
        } catch {
            throw RPCError.transport("encode failed: \(error)")
        }

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            let pair = try await session.data(for: request)
            data = pair.0
            response = pair.1
        } catch {
            rpcLog.error("transport \(self.url.host ?? "?", privacy: .public) \(method, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw RPCError.transport(error.localizedDescription)
        }
        let elapsed = Date().timeIntervalSince(started)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(256), encoding: .utf8) ?? "<binary>"
            rpcLog.error("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) HTTP \(http.statusCode) (\(String(format: "%.2f", elapsed)) s)")
            throw RPCError.httpStatus(http.statusCode, body: body)
        }

        let decoded: JSONRPCResponse<T>
        do {
            decoded = try JSONDecoder().decode(JSONRPCResponse<T>.self, from: data)
        } catch {
            let body = String(data: data.prefix(256), encoding: .utf8) ?? "<binary>"
            rpcLog.error("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) decode failed: \(body, privacy: .public)")
            throw RPCError.decode("\(error) — body: \(body)")
        }

        if let err = decoded.error {
            throw RPCError.rpc(code: err.code, message: err.message)
        }
        guard let result = decoded.result else {
            throw RPCError.unexpectedResponse("missing result")
        }
        rpcLog.debug("\(self.url.host ?? "?", privacy: .public) \(method, privacy: .public) ok (\(String(format: "%.2f", elapsed)) s)")
        return result
    }
}

// MARK: - Multi-endpoint client

/// Tries `primary`, then each entry in `fallbacks` in order, swallowing
/// transient errors (timeout, HTTP 5xx/429, decode of non-JSON bodies)
/// and returning the first successful result. JSON-RPC application errors
/// (a structured `error` block) are returned to the caller without
/// trying fallbacks — those are real errors, not endpoint problems.
public actor MultiEndpointRPC {
    public let primary: RPCClient
    public let fallbacks: [RPCClient]

    public init(primary: URL, fallbacks: [URL], session: URLSession = .shared, timeoutSeconds: TimeInterval = 15) {
        self.primary = RPCClient(url: primary, session: session, timeoutSeconds: timeoutSeconds)
        self.fallbacks = fallbacks.map { RPCClient(url: $0, session: session, timeoutSeconds: timeoutSeconds) }
    }

    public func call<T: Decodable & Sendable>(
        _ method: String,
        params: [JSONValue],
        as: T.Type = T.self
    ) async throws -> T {
        var lastError: Error?
        for client in [primary] + fallbacks {
            do {
                return try await client.call(method, params: params, as: T.self)
            } catch let err as RPCError {
                switch err {
                case .rpc:
                    // application-level error, do not fallback
                    throw err
                default:
                    lastError = err
                    rpcLog.info("falling back from \(client.url.host ?? "?", privacy: .public)")
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? RPCError.transport("no endpoints available")
    }
}

// MARK: - Solana

public enum SolanaRPC {
    private struct GetBalanceResult: Decodable {
        let value: UInt64
    }

    /// Lamports for the given base58 address.
    public static func getBalance(client: MultiEndpointRPC, address: String) async throws -> UInt64 {
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
    public static func getBalance(client: MultiEndpointRPC, address: String) async throws -> BigUInt {
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
