// SwooshProviders/ProviderInfra.swift — Model role, health, errors, PKCE, JSON helpers
import Foundation
import SwooshTools
import CryptoKit

// MARK: - Model role / route
// ═══════════════════════════════════════════════════════════════════

public enum ModelRole: String, Codable, Sendable, CaseIterable {
    case primaryChat, coding, fastLocal
    case memoryExtraction, summarization
    case embedding, workflowPlanning, toolCallRepair
}

public struct ProviderRoute: Codable, Sendable, Identifiable {
    public let id: String
    public let role: ModelRole
    public let providerID: ProviderID
    public let model: String
    public let priority: Int
    public var enabled: Bool

    public init(id: String = UUID().uuidString, role: ModelRole, providerID: ProviderID,
                model: String, priority: Int = 50, enabled: Bool = true) {
        self.id = id; self.role = role; self.providerID = providerID
        self.model = model; self.priority = priority; self.enabled = enabled
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider health
// ═══════════════════════════════════════════════════════════════════

public enum ProviderHealthStatus: String, Codable, Sendable {
    case healthy, degraded, unreachable, unconfigured, authMissing
}

public struct ProviderHealth: Codable, Sendable {
    public let providerID: ProviderID
    public let status: ProviderHealthStatus
    public let latencyMs: Int?
    public let lastChecked: Date
    public let message: String?

    public init(providerID: ProviderID, status: ProviderHealthStatus,
                latencyMs: Int? = nil, lastChecked: Date = Date(), message: String? = nil) {
        self.providerID = providerID; self.status = status
        self.latencyMs = latencyMs; self.lastChecked = lastChecked; self.message = message
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider errors
// ═══════════════════════════════════════════════════════════════════

public enum ProviderError: Error, Sendable {
    case notConfigured(ProviderID)
    case authMissing(ProviderID, String)
    case requestFailed(ProviderID, String)
    case responseParseFailed(ProviderID, String)
    case rateLimited(ProviderID, retryAfterSeconds: Int?)
    /// The credential's plan/usage quota is exhausted (distinct from a
    /// transient rate-limit). `message` is human-readable; `resetsAt` is
    /// the recovery time when the upstream reports one. Surfaced verbatim
    /// to the user so "you hit your plan cap, resets May 31" replaces an
    /// opaque 500.
    case quotaExceeded(ProviderID, message: String, resetsAt: Date?)
    case modelNotAvailable(ProviderID, String)
    case unsupportedEndpoint(ProviderID, String)
    case allRoutesFailed([ProviderAttemptError])
    case networkError(ProviderID, String)
}

public struct ProviderAttemptError: Sendable {
    public let route: ProviderRoute
    public let error: Error

    public init(route: ProviderRoute, error: Error) {
        self.route = route; self.error = error
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider audit
// ═══════════════════════════════════════════════════════════════════

public struct ProviderAuditEvent: Codable, Sendable {
    public let kind: ProviderAuditKind
    public let providerID: ProviderID
    public let message: String
    public let createdAt: Date

    public init(kind: ProviderAuditKind, providerID: ProviderID,
                message: String, createdAt: Date = Date()) {
        self.kind = kind; self.providerID = providerID
        self.message = message; self.createdAt = createdAt
    }
}

public enum ProviderAuditKind: String, Codable, Sendable {
    case added, enabled, disabled
    case authStarted, authCompleted, authFailed, secretStored
    case testStarted, testSucceeded, testFailed
    case callStarted, callStreamStarted, callSucceeded, callFailed
    case routeSelected, routeFallback, allRoutesFailed
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - PKCE (real CryptoKit S256)
// ═══════════════════════════════════════════════════════════════════

public enum PKCE {
    /// Generate a cryptographically random code verifier
    public static func verifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Generate S256 code challenge: BASE64URL(SHA256(verifier))
    public static func challengeS256(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - JSONValue helpers
// ═══════════════════════════════════════════════════════════════════

extension JSONValue {
    public func toAnyForJSON() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let arr): return arr.map { $0.toAnyForJSON() }
        case .object(let dict): return dict.mapValues { $0.toAnyForJSON() }
        }
    }
}
