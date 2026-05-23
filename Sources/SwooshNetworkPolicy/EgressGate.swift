// SwooshNetworkPolicy/EgressGate.swift — 0.1A Allow/deny actor + audit fanout
//
// `EgressGate` is the default `NetworkPolicy` implementation. The
// decision rules are intentionally tiny:
//
//   1. If the host matches a denylist entry → deny.
//   2. Otherwise, if the allowlist is non-nil AND the host does not match
//      an allowlist entry → deny.
//   3. Otherwise → allow.
//
// "Match" is exact lowercase match, plus a leading-dot wildcard
// (`".example.com"` matches `api.example.com` and `example.com` but not
// `notexample.com`). HTTPS-only mode rejects any non-`https` scheme up
// front so callers don't have to special-case insecure URLs.
//
// Every decision (allow or deny) is fanned out to an optional
// `AuditLogging` sink so reviewers can see what the agent reached out to
// and what was blocked. The auditor is optional because the daemon owns
// the only concrete `AuditLogging`; library callers and tests can pass
// `nil` and the gate stays useful as a pure decision actor.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Configuration
// ═══════════════════════════════════════════════════════════════════

public struct EgressGateConfiguration: Sendable, Equatable {
    /// nil = no allowlist; any host that isn't explicitly denied is
    /// allowed. Non-nil = strict mode; only matching hosts pass.
    public let allowlist: [String]?
    /// Hosts (exact or `.suffix`) that are always denied.
    public let denylist: [String]
    /// When true, any scheme other than `https` is denied up front.
    public let httpsOnly: Bool

    public init(
        allowlist: [String]? = nil,
        denylist: [String] = [],
        httpsOnly: Bool = false
    ) {
        self.allowlist = allowlist?.map { $0.lowercased() }
        self.denylist = denylist.map { $0.lowercased() }
        self.httpsOnly = httpsOnly
    }

    public static let permissive = EgressGateConfiguration()
    public static func strict(allowlist: [String], denylist: [String] = []) -> EgressGateConfiguration {
        EgressGateConfiguration(allowlist: allowlist, denylist: denylist, httpsOnly: true)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Actor
// ═══════════════════════════════════════════════════════════════════

public actor EgressGate: NetworkPolicy {
    private var configuration: EgressGateConfiguration
    private let auditor: (any AuditLogging)?

    public init(
        configuration: EgressGateConfiguration = .permissive,
        auditor: (any AuditLogging)? = nil
    ) {
        self.configuration = configuration
        self.auditor = auditor
    }

    public func reconfigure(_ configuration: EgressGateConfiguration) {
        self.configuration = configuration
    }

    public func currentConfiguration() -> EgressGateConfiguration {
        configuration
    }

    public func evaluate(_ request: EgressRequest) async -> EgressDecision {
        let decision = decide(request)
        await fanout(decision: decision, for: request)
        return decision
    }

    // MARK: - Decision logic

    private func decide(_ request: EgressRequest) -> EgressDecision {
        if configuration.httpsOnly && request.scheme != "https" {
            return .deny(reason: "Non-HTTPS scheme '\(request.scheme)' denied by policy.")
        }
        let host = request.host.lowercased()
        for pattern in configuration.denylist where Self.hostMatches(host, pattern: pattern) {
            return .deny(reason: "Host '\(host)' is on the denylist (matched '\(pattern)').")
        }
        if let allowlist = configuration.allowlist {
            let allowed = allowlist.contains { Self.hostMatches(host, pattern: $0) }
            if !allowed {
                return .deny(reason: "Host '\(host)' is not on the allowlist.")
            }
        }
        return .allow
    }

    nonisolated private static func hostMatches(_ host: String, pattern: String) -> Bool {
        if pattern == host { return true }
        if pattern.hasPrefix(".") {
            let suffix = pattern.dropFirst()
            return host == suffix || host.hasSuffix(pattern)
        }
        return false
    }

    // MARK: - Audit fanout

    private func fanout(decision: EgressDecision, for request: EgressRequest) async {
        guard let auditor else { return }
        let kind: AuditEntryKind
        let detail: String
        let success: Bool
        switch decision {
        case .allow:
            kind = .egressAllowed
            detail = "egress.allow \(request.scheme)://\(request.host) [\(request.purpose)]"
            success = true
        case let .deny(reason):
            kind = .egressDenied
            detail = "egress.deny \(request.scheme)://\(request.host) [\(request.purpose)]: \(reason)"
            success = false
        }
        let entry = AuditEntry(
            kind: kind,
            toolName: "network.policy",
            detail: detail,
            success: success
        )
        try? await auditor.append(entry)
    }
}
