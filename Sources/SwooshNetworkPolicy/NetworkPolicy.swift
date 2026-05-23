// SwooshNetworkPolicy/NetworkPolicy.swift — 0.1A Egress policy types
//
// The per-host outbound HTTP gate. Composes with `SwooshFirewall`'s coarse
// `.networkAccess` permission: firewall says "may this tool use the network
// at all?", policy says "may this specific host/scheme be reached for this
// purpose, right now?".
//
// The protocol surface stays small on purpose. Decisions are inputs
// (purpose + host + port + scheme + method); the actor implementation
// owns the rules and audit fanout.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Egress request
// ═══════════════════════════════════════════════════════════════════

/// Everything the gate needs to evaluate a single outbound request.
///
/// Built from a `URLRequest` by `PolicyEnforcedURLSession`; can also be
/// constructed directly when callers want to evaluate a policy without
/// owning a `URLRequest` (for example, dry-running plugin manifests).
public struct EgressRequest: Sendable, Equatable {
    public let host: String
    public let port: Int?
    public let scheme: String
    public let method: String
    /// Short label identifying which subsystem is reaching out — used in
    /// audit fanout and helps reviewers tell `provider:openai` from
    /// `rpc:solana` without correlating against the call site.
    public let purpose: String

    public init(host: String, port: Int?, scheme: String, method: String, purpose: String) {
        self.host = host
        self.port = port
        self.scheme = scheme
        self.method = method
        self.purpose = purpose
    }

    /// Best-effort construction from a `URLRequest`. Returns nil when the
    /// request URL has no host — the caller should treat that as a
    /// configuration error, not a denial.
    public init?(request: URLRequest, purpose: String) {
        guard let url = request.url, let host = url.host, !host.isEmpty else {
            return nil
        }
        self.host = host.lowercased()
        self.port = url.port
        self.scheme = (url.scheme ?? "https").lowercased()
        self.method = (request.httpMethod ?? "GET").uppercased()
        self.purpose = purpose
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Decision
// ═══════════════════════════════════════════════════════════════════

public enum EgressDecision: Sendable, Equatable {
    case allow
    case deny(reason: String)

    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Error
// ═══════════════════════════════════════════════════════════════════

public struct EgressDeniedError: Error, Sendable, Equatable, CustomStringConvertible {
    public let request: EgressRequest
    public let reason: String

    public init(request: EgressRequest, reason: String) {
        self.request = request
        self.reason = reason
    }

    public var description: String {
        "EgressDenied(\(request.scheme)://\(request.host) [\(request.purpose)]): \(reason)"
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Protocol
// ═══════════════════════════════════════════════════════════════════

/// Implementations must be `Sendable` so the gate can be stored on
/// actors, providers, and tool registries without re-wrapping.
public protocol NetworkPolicy: Sendable {
    func evaluate(_ request: EgressRequest) async -> EgressDecision
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Bypass policy (default for back-compat)
// ═══════════════════════════════════════════════════════════════════

/// Permissive policy that allows everything. Useful as a default when a
/// caller has not yet been configured with a real policy, and as a
/// sentinel in tests that want to bypass the gate explicitly.
public struct AllowAllNetworkPolicy: NetworkPolicy {
    public init() {}
    public func evaluate(_ request: EgressRequest) async -> EgressDecision { .allow }
}

/// Denial-of-default policy. Useful in deeply locked-down environments
/// (CI runners that should never hit the open internet) and in tests
/// that want to assert "this code path must not reach the network".
public struct DenyAllNetworkPolicy: NetworkPolicy {
    public let reason: String
    public init(reason: String = "All egress denied by policy.") { self.reason = reason }
    public func evaluate(_ request: EgressRequest) async -> EgressDecision {
        .deny(reason: reason)
    }
}
