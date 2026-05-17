// SwooshNetworkPolicy/NetworkPolicyTypes.swift — 0.8B Network Trust + Policy
//
// Remote server identity, trust, TLS, pinning, and network restrictions.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Remote server trust policy
// ═══════════════════════════════════════════════════════════════════

public struct RemoteServerTrustPolicy: Codable, Sendable {
    public var level: RemoteServerTrustLevel
    public var requireHTTPS: Bool
    public var allowSelfSignedCertificate: Bool
    public var pinnedCertificateFingerprints: [String]
    public var allowedHosts: [String]
    public var deniedHosts: [String]
    public var requireUserApprovalForCapabilityChanges: Bool

    public static let safeDefault = RemoteServerTrustPolicy(
        level: .untrustedRemote, requireHTTPS: true,
        allowSelfSignedCertificate: false, pinnedCertificateFingerprints: [],
        allowedHosts: [], deniedHosts: [],
        requireUserApprovalForCapabilityChanges: true
    )

    public init(level: RemoteServerTrustLevel, requireHTTPS: Bool,
                allowSelfSignedCertificate: Bool, pinnedCertificateFingerprints: [String],
                allowedHosts: [String], deniedHosts: [String],
                requireUserApprovalForCapabilityChanges: Bool) {
        self.level = level; self.requireHTTPS = requireHTTPS
        self.allowSelfSignedCertificate = allowSelfSignedCertificate
        self.pinnedCertificateFingerprints = pinnedCertificateFingerprints
        self.allowedHosts = allowedHosts; self.deniedHosts = deniedHosts
        self.requireUserApprovalForCapabilityChanges = requireUserApprovalForCapabilityChanges
    }

    public func isHostAllowed(_ host: String) -> Bool {
        if deniedHosts.contains(host) { return false }
        if !allowedHosts.isEmpty { return allowedHosts.contains(host) }
        return true
    }

    public func isCertificatePinned(_ fingerprint: String) -> Bool {
        guard !pinnedCertificateFingerprints.isEmpty else { return true }
        return pinnedCertificateFingerprints.contains(fingerprint)
    }
}

public enum RemoteServerTrustLevel: String, Codable, Sendable {
    case untrustedRemote, userApprovedRemote, pinnedRemote, organizationApprovedRemote
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Remote server identity
// ═══════════════════════════════════════════════════════════════════

public struct RemoteServerIdentity: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let endpoint: String
    public let host: String
    public let tlsCertificateFingerprint: String?
    public let authorizationServerIssuer: String?
    public let protectedResourceURI: String?
    public let firstSeenAt: Date
    public var lastSeenAt: Date

    public init(id: String = UUID().uuidString, serverID: String, endpoint: String,
                host: String, tlsCertificateFingerprint: String? = nil,
                authorizationServerIssuer: String? = nil, protectedResourceURI: String? = nil,
                firstSeenAt: Date = Date(), lastSeenAt: Date = Date()) {
        self.id = id; self.serverID = serverID; self.endpoint = endpoint; self.host = host
        self.tlsCertificateFingerprint = tlsCertificateFingerprint
        self.authorizationServerIssuer = authorizationServerIssuer
        self.protectedResourceURI = protectedResourceURI
        self.firstSeenAt = firstSeenAt; self.lastSeenAt = lastSeenAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Network policy
// ═══════════════════════════════════════════════════════════════════

public struct RemoteNetworkPolicy: Codable, Sendable {
    public let allowRemoteHTTP: Bool
    public let allowPrivateNetworkHosts: Bool
    public let allowLocalhostRemoteProfile: Bool
    public let maxResponseBytes: Int
    public let timeoutSeconds: Int

    public static let safeDefault = RemoteNetworkPolicy(
        allowRemoteHTTP: false, allowPrivateNetworkHosts: false,
        allowLocalhostRemoteProfile: true, maxResponseBytes: 1_000_000, timeoutSeconds: 30
    )

    public init(allowRemoteHTTP: Bool, allowPrivateNetworkHosts: Bool,
                allowLocalhostRemoteProfile: Bool, maxResponseBytes: Int, timeoutSeconds: Int) {
        self.allowRemoteHTTP = allowRemoteHTTP; self.allowPrivateNetworkHosts = allowPrivateNetworkHosts
        self.allowLocalhostRemoteProfile = allowLocalhostRemoteProfile
        self.maxResponseBytes = maxResponseBytes; self.timeoutSeconds = timeoutSeconds
    }

    public func isEndpointAllowed(_ endpoint: String) -> Bool {
        if endpoint.hasPrefix("http://") && !allowRemoteHTTP {
            // Allow localhost even without HTTPS
            if endpoint.contains("localhost") || endpoint.contains("127.0.0.1") {
                return allowLocalhostRemoteProfile
            }
            return false
        }
        return true
    }

    private static let privateNetworkPrefixes = ["10.", "172.16.", "172.17.", "172.18.",
        "172.19.", "172.20.", "172.21.", "172.22.", "172.23.", "172.24.",
        "172.25.", "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31.",
        "192.168."]

    public func isPrivateNetworkHost(_ host: String) -> Bool {
        Self.privateNetworkPrefixes.contains { host.hasPrefix($0) }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Identity change detection
// ═══════════════════════════════════════════════════════════════════

public struct IdentityChange: Codable, Sendable {
    public let serverID: String
    public let field: String
    public let oldValue: String?
    public let newValue: String?
    public let detectedAt: Date

    public init(serverID: String, field: String, oldValue: String?, newValue: String?, detectedAt: Date = Date()) {
        self.serverID = serverID; self.field = field
        self.oldValue = oldValue; self.newValue = newValue; self.detectedAt = detectedAt
    }
}

public struct IdentityValidator: Sendable {
    public init() {}

    public func detectChanges(stored: RemoteServerIdentity, current: RemoteServerIdentity) -> [IdentityChange] {
        var changes: [IdentityChange] = []
        if stored.host != current.host {
            changes.append(IdentityChange(serverID: stored.serverID, field: "host", oldValue: stored.host, newValue: current.host))
        }
        if stored.tlsCertificateFingerprint != current.tlsCertificateFingerprint {
            changes.append(IdentityChange(serverID: stored.serverID, field: "tlsCertificateFingerprint",
                oldValue: stored.tlsCertificateFingerprint, newValue: current.tlsCertificateFingerprint))
        }
        if stored.authorizationServerIssuer != current.authorizationServerIssuer {
            changes.append(IdentityChange(serverID: stored.serverID, field: "authorizationServerIssuer",
                oldValue: stored.authorizationServerIssuer, newValue: current.authorizationServerIssuer))
        }
        if stored.protectedResourceURI != current.protectedResourceURI {
            changes.append(IdentityChange(serverID: stored.serverID, field: "protectedResourceURI",
                oldValue: stored.protectedResourceURI, newValue: current.protectedResourceURI))
        }
        return changes
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Network policy audit
// ═══════════════════════════════════════════════════════════════════

public struct NetworkPolicyAuditEvent: Codable, Sendable {
    public let kind: NetworkPolicyAuditKind
    public let serverID: String
    public let message: String
    public let createdAt: Date

    public init(kind: NetworkPolicyAuditKind, serverID: String, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.serverID = serverID; self.message = message; self.createdAt = createdAt
    }
}

public enum NetworkPolicyAuditKind: String, Codable, Sendable {
    case identityChanged, identityVerified, trustChanged
    case pinMismatch, selfSignedRejected, httpRejected
    case privateNetworkRejected, hostDenied
}
