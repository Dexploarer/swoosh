// SwooshAPI/AuthMiddleware.swift — Bearer-token check for /api/* routes
//
// Two middleware variants:
//
//   • BearerAuthMiddleware — accepts requests whose `Authorization` header
//     equals "Bearer <token>". Anything else gets 401. Comparison is constant-
//     time so a brute-force probe of /api/agent/chat can't time-leak the
//     token byte by byte.
//   • DenyAllMiddleware — rejects every request unconditionally. Mounted on
//     /api/* when swooshd starts without SWOOSH_API_TOKEN, so a misconfigured
//     daemon binding to 0.0.0.0 still can't expose the agent.

import Foundation
import Hummingbird
import HTTPTypes

public struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    public let token: String
    private let additionalTokens: @Sendable () -> [String]

    public init(token: String, additionalTokens: @escaping @Sendable () -> [String] = { [] }) {
        self.token = token
        self.additionalTokens = additionalTokens
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard swooshBearerTokenMatches(
            authorizationHeader: request.headers[.authorization],
            tokens: [token] + additionalTokens()
        ) else {
            throw HTTPError(.unauthorized, message: "missing or invalid bearer token")
        }
        return try await next(request, context)
    }
}

public func swooshBearerTokenMatches(authorizationHeader: String?, token: String) -> Bool {
    swooshBearerTokenMatches(authorizationHeader: authorizationHeader, tokens: [token])
}

public func swooshBearerTokenMatches(authorizationHeader: String?, tokens: [String]) -> Bool {
    guard let authorizationHeader, authorizationHeader.hasPrefix("Bearer ") else {
        return false
    }
    let bearer = String(authorizationHeader.dropFirst("Bearer ".count))
    return tokens.contains { !$0.isEmpty && constantTimeEquals(bearer, $0) }
}

public struct DenyAllMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        throw HTTPError(.unauthorized, message: "SWOOSH_API_TOKEN not configured on this daemon; /api/* refused")
    }
}

/// Length-and-content comparison that does not short-circuit on the first
/// differing byte. Inputs of different lengths are immediately unequal.
@inline(__always)
private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8)
    let b = Array(rhs.utf8)
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count {
        diff |= a[i] ^ b[i]
    }
    return diff == 0
}
