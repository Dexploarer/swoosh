// SwooshWallet/MultiEndpointRPC.swift — Primary + fallback orchestrator — 0.9A
//
// Wraps a primary `RPCClient` and an ordered list of fallback clients.
// Transient transport / HTTP / decode errors fall through to the next
// endpoint; only JSON-RPC application errors (a structured `error` block
// returned by the server) propagate to the caller without trying the
// fallbacks — application errors are real, endpoint problems are not.

import Foundation
import os

private let multiRPCLog = Logger(subsystem: "ai.swoosh", category: "wallet.rpc")

/// Tries `primary`, then each entry in `fallbacks` in order, swallowing
/// transient errors (timeout, HTTP 5xx/429, decode of non-JSON bodies)
/// and returning the first successful result. JSON-RPC application errors
/// (a structured `error` block) are returned to the caller without
/// trying fallbacks — those are real errors, not endpoint problems.
public actor MultiEndpointRPC {
    public let primary: RPCClient
    public let fallbacks: [RPCClient]

    public init(
        primary: URL,
        fallbacks: [URL],
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 15
    ) {
        self.primary = RPCClient(
            url: primary, session: session, timeoutSeconds: timeoutSeconds
        )
        self.fallbacks = fallbacks.map {
            RPCClient(url: $0, session: session, timeoutSeconds: timeoutSeconds)
        }
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
                    // application-level error, do not fall back
                    throw err
                default:
                    lastError = err
                    multiRPCLog.info(
                        "falling back from \(client.url.host ?? "?", privacy: .public)"
                    )
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
