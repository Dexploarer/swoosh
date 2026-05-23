// SwooshNetworkPolicy/PolicyEnforcedURLSession.swift — 0.1A URLSession wrapper
//
// Thin wrapper around `URLSession` that consults a `NetworkPolicy` before
// every request. Callers should construct the wrapper once at startup
// (the daemon does so from its bearer-resolved configuration) and pass
// it down to subsystems that previously called `URLSession.shared`
// directly.
//
// The shape mirrors the two `URLSession.data(for:)` / `URLSession.bytes(for:)`
// methods used across the codebase so the migration is mechanical:
//
//   - `data(for:purpose:)`  → replaces `session.data(for:)`
//   - `bytes(for:purpose:)` → replaces `session.bytes(for:)`
//
// On denial, both methods throw `EgressDeniedError` so callers can
// distinguish policy failures from network/server failures.

import Foundation

public struct PolicyEnforcedURLSession: Sendable {
    private let session: URLSession
    private let policy: any NetworkPolicy

    public init(session: URLSession = .shared, policy: any NetworkPolicy) {
        self.session = session
        self.policy = policy
    }

    /// Construct the policy-bypass wrapper used by tests + callers that
    /// have not been migrated to a real policy yet.
    public static func bypass(session: URLSession = .shared) -> PolicyEnforcedURLSession {
        PolicyEnforcedURLSession(session: session, policy: AllowAllNetworkPolicy())
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Data
    // ═══════════════════════════════════════════════════════════════

    public func data(for request: URLRequest, purpose: String) async throws -> (Data, URLResponse) {
        try await preflight(request: request, purpose: purpose)
        return try await session.data(for: request)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Streaming
    // ═══════════════════════════════════════════════════════════════

    public func bytes(
        for request: URLRequest,
        purpose: String
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await preflight(request: request, purpose: purpose)
        return try await session.bytes(for: request)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Preflight
    // ═══════════════════════════════════════════════════════════════

    /// Exposed so callers that have already built an `EgressRequest`
    /// (workflow validators, plugin manifests) can re-use the same gate
    /// without going through `URLRequest`.
    public func preflight(_ request: EgressRequest) async throws {
        let decision = await policy.evaluate(request)
        if case let .deny(reason) = decision {
            throw EgressDeniedError(request: request, reason: reason)
        }
    }

    private func preflight(request: URLRequest, purpose: String) async throws {
        guard let egress = EgressRequest(request: request, purpose: purpose) else {
            // Missing host is a configuration error, not a policy denial —
            // URLSession would throw shortly anyway, but the explicit
            // signal helps the caller log it. Use a synthetic request so
            // the denial carries the purpose context the caller passed in.
            let synthetic = EgressRequest(
                host: "<unknown>",
                port: nil,
                scheme: request.url?.scheme?.lowercased() ?? "https",
                method: (request.httpMethod ?? "GET").uppercased(),
                purpose: purpose
            )
            throw EgressDeniedError(request: synthetic, reason: "Request URL has no host.")
        }
        try await preflight(egress)
    }
}
