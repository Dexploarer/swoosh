// SwooshMCPAuth/MCPAuthTypes.swift — 0.8B Remote MCP OAuth + PKCE
//
// Auth for protected remote MCP servers. Tokens in Keychain only.
// No raw tokens in config, database, logs, or audit.

import Foundation
import CryptoKit
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Auth configuration
// ═══════════════════════════════════════════════════════════════════

public struct MCPAuthConfiguration: Codable, Sendable {
    public var mode: MCPAuthMode
    public var authorizationServerURL: String?
    public var protectedResourceMetadataURL: String?
    public var clientID: String?
    public var registrationMode: MCPClientRegistrationMode
    public var requestedScopes: [String]
    public var resourceIndicator: MCPResourceIndicator?

    public static let unconfigured = MCPAuthConfiguration(
        mode: .unknown, registrationMode: .metadataDocument, requestedScopes: []
    )

    public init(mode: MCPAuthMode, authorizationServerURL: String? = nil,
                protectedResourceMetadataURL: String? = nil, clientID: String? = nil,
                registrationMode: MCPClientRegistrationMode = .metadataDocument,
                requestedScopes: [String] = [], resourceIndicator: MCPResourceIndicator? = nil) {
        self.mode = mode; self.authorizationServerURL = authorizationServerURL
        self.protectedResourceMetadataURL = protectedResourceMetadataURL
        self.clientID = clientID; self.registrationMode = registrationMode
        self.requestedScopes = requestedScopes; self.resourceIndicator = resourceIndicator
    }
}

public enum MCPAuthMode: String, Codable, Sendable {
    case none, bearerToken, oauthAuthorizationCodePKCE, staticToken, unknown
}

public enum MCPClientRegistrationMode: String, Codable, Sendable {
    case metadataDocument, dynamicClientRegistration, preregistered, manual
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Resource indicator
// ═══════════════════════════════════════════════════════════════════

public struct MCPResourceIndicator: Codable, Sendable, Hashable {
    public let canonicalURI: String

    public init(canonicalURI: String) { self.canonicalURI = canonicalURI }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Protected resource metadata
// ═══════════════════════════════════════════════════════════════════

public struct MCPProtectedResourceMetadata: Codable, Sendable {
    public let resource: String
    public let authorizationServers: [String]
    public let scopesSupported: [String]?

    public init(resource: String, authorizationServers: [String], scopesSupported: [String]? = nil) {
        self.resource = resource; self.authorizationServers = authorizationServers
        self.scopesSupported = scopesSupported
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Authorization server metadata
// ═══════════════════════════════════════════════════════════════════

public struct MCPAuthorizationServerMetadata: Codable, Sendable {
    public let issuer: String
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let revocationEndpoint: String?
    public let registrationEndpoint: String?
    public let scopesSupported: [String]?
    public let codeChallengeMethodsSupported: [String]

    public init(issuer: String, authorizationEndpoint: String, tokenEndpoint: String,
                revocationEndpoint: String? = nil, registrationEndpoint: String? = nil,
                scopesSupported: [String]? = nil, codeChallengeMethodsSupported: [String] = ["S256"]) {
        self.issuer = issuer; self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint; self.revocationEndpoint = revocationEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.scopesSupported = scopesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
    }

    public var supportsPKCES256: Bool { codeChallengeMethodsSupported.contains("S256") }

    public var issuerIsHTTPS: Bool { issuer.hasPrefix("https://") }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - PKCE
// ═══════════════════════════════════════════════════════════════════

public struct MCPPKCEPair: Sendable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let method: String

    public init(codeVerifier: String, codeChallenge: String, method: String = "S256") {
        self.codeVerifier = codeVerifier; self.codeChallenge = codeChallenge; self.method = method
    }

    /// Generate a PKCE pair.
    public static func generate(verifier: String? = nil) -> MCPPKCEPair {
        let v = verifier ?? randomVerifier()
        let digest = SHA256.hash(data: Data(v.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return MCPPKCEPair(codeVerifier: v, codeChallenge: challenge)
    }

    private static func randomVerifier(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

public enum MCPPKCEError: Error, Sendable {
    case serverDoesNotAdvertisePKCE
    case s256Unsupported
    case verifierGenerationFailed
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Scope strategy
// ═══════════════════════════════════════════════════════════════════

public struct MCPScopeStrategy: Codable, Sendable {
    public let preferredScopes: [String]
    public let requiredScopes: [String]
    public let requestAllSupportedIfUnknown: Bool
    public let allowStepUpAuthorization: Bool

    public static let minimal = MCPScopeStrategy(
        preferredScopes: [], requiredScopes: [],
        requestAllSupportedIfUnknown: false, allowStepUpAuthorization: true
    )

    public init(preferredScopes: [String], requiredScopes: [String],
                requestAllSupportedIfUnknown: Bool, allowStepUpAuthorization: Bool) {
        self.preferredScopes = preferredScopes; self.requiredScopes = requiredScopes
        self.requestAllSupportedIfUnknown = requestAllSupportedIfUnknown
        self.allowStepUpAuthorization = allowStepUpAuthorization
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Auth session
// ═══════════════════════════════════════════════════════════════════

public struct MCPAuthSession: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let state: String
    /// Keychain ref for PKCE verifier — never raw
    public let pkceVerifierSecretRef: String
    public let pkceCodeChallenge: String
    public let pkceMethod: String
    public let resourceIndicator: MCPResourceIndicator
    public let requestedScopes: [String]
    public let redirectURI: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: String = UUID().uuidString, serverID: String, state: String,
                pkceVerifierSecretRef: String, pkceCodeChallenge: String, pkceMethod: String = "S256",
                resourceIndicator: MCPResourceIndicator,
                requestedScopes: [String], redirectURI: String,
                createdAt: Date = Date(), expiresAt: Date = Date().addingTimeInterval(600)) {
        self.id = id; self.serverID = serverID; self.state = state
        self.pkceVerifierSecretRef = pkceVerifierSecretRef
        self.pkceCodeChallenge = pkceCodeChallenge; self.pkceMethod = pkceMethod
        self.resourceIndicator = resourceIndicator; self.requestedScopes = requestedScopes
        self.redirectURI = redirectURI; self.createdAt = createdAt; self.expiresAt = expiresAt
    }

    public var isExpired: Bool { Date() > expiresAt }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stored token
// ═══════════════════════════════════════════════════════════════════

public struct MCPStoredToken: Codable, Sendable {
    /// Keychain ref — never the raw token value
    public let accessTokenSecretRef: String
    /// Keychain ref — never the raw token value
    public let refreshTokenSecretRef: String?
    public let tokenType: String
    public let expiresAt: Date?
    public let scopes: [String]
    public let audience: MCPTokenAudience
    public let issuedAt: Date

    public init(accessTokenSecretRef: String, refreshTokenSecretRef: String? = nil,
                tokenType: String = "Bearer", expiresAt: Date? = nil,
                scopes: [String] = [], audience: MCPTokenAudience, issuedAt: Date = Date()) {
        self.accessTokenSecretRef = accessTokenSecretRef
        self.refreshTokenSecretRef = refreshTokenSecretRef; self.tokenType = tokenType
        self.expiresAt = expiresAt; self.scopes = scopes; self.audience = audience
        self.issuedAt = issuedAt
    }

    public var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }

    public var needsRefresh: Bool {
        guard let exp = expiresAt else { return false }
        return exp.timeIntervalSinceNow < 300 // 5 min skew
    }
}

public struct MCPTokenAudience: Codable, Sendable, Hashable {
    public let resourceIndicator: MCPResourceIndicator
    public let serverID: String

    public init(resourceIndicator: MCPResourceIndicator, serverID: String) {
        self.resourceIndicator = resourceIndicator; self.serverID = serverID
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Auth audit
// ═══════════════════════════════════════════════════════════════════

public struct MCPAuthAuditEvent: Codable, Sendable {
    public let kind: MCPAuthAuditKind
    public let serverID: String
    public let message: String
    public let createdAt: Date

    public init(kind: MCPAuthAuditKind, serverID: String, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.serverID = serverID; self.message = message; self.createdAt = createdAt
    }
}

public enum MCPAuthAuditKind: String, Codable, Sendable {
    case discoveryStarted, discoveryCompleted, discoveryFailed
    case authStarted, callbackReceived, tokenExchanged, tokenStored
    case tokenRefreshed, tokenRevoked, authFailed
    case sessionCreated, sessionExpired, sessionDestroyed
}
