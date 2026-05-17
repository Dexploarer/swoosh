// SwooshMCPAuth/MCPAuthService.swift — 0.8B Auth Service
//
// OAuth flow orchestration, token storage, refresh, revocation.
// Tokens stored as Keychain refs only. No raw values in state.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Token store protocol
// ═══════════════════════════════════════════════════════════════════

public protocol MCPTokenStoring: Sendable {
    func saveToken(_ token: MCPStoredToken, for serverID: String) async throws
    func loadToken(serverID: String) async throws -> MCPStoredToken?
    func deleteToken(serverID: String) async throws
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - In-memory token store (Keychain ref simulation)
// ═══════════════════════════════════════════════════════════════════

public actor InMemoryMCPTokenStore: MCPTokenStoring {
    private var tokens: [String: MCPStoredToken] = [:]

    public init() {}

    public func saveToken(_ token: MCPStoredToken, for serverID: String) { tokens[serverID] = token }
    public func loadToken(serverID: String) -> MCPStoredToken? { tokens[serverID] }
    public func deleteToken(serverID: String) { tokens.removeValue(forKey: serverID) }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Auth errors
// ═══════════════════════════════════════════════════════════════════

public enum MCPAuthError: Error, Sendable {
    case serverNotFound(String)
    case discoveryFailed(String)
    case pkceNotSupported
    case issuerNotHTTPS(String)
    case stateMismatch
    case sessionExpired(String)
    case sessionNotFound(String)
    case tokenNotFound(String)
    case tokenExpired(String)
    case tokenAudienceMismatch(expected: String, actual: String)
    case refreshFailed(String)
    case revocationFailed(String)
    case resourceIndicatorMissing
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Auth service
// ═══════════════════════════════════════════════════════════════════

public actor MCPAuthService {
    private let tokenStore: any MCPTokenStoring
    private var sessions: [String: MCPAuthSession] = [:]
    private var auditLog: [MCPAuthAuditEvent] = []

    public init(tokenStore: any MCPTokenStoring) {
        self.tokenStore = tokenStore
    }

    // ── Discovery ─────────────────────────────────────────────────

    public func validateAuthServerMetadata(_ metadata: MCPAuthorizationServerMetadata) throws {
        guard metadata.issuerIsHTTPS else {
            throw MCPAuthError.issuerNotHTTPS(metadata.issuer)
        }
        guard metadata.supportsPKCES256 else {
            throw MCPAuthError.pkceNotSupported
        }
        appendAudit(.init(kind: .discoveryCompleted, serverID: metadata.issuer, message: "Auth server validated"))
    }

    // ── Auth start ────────────────────────────────────────────────

    public func startAuthFlow(
        serverID: String, endpoint: String, scopes: [String],
        redirectURI: String = "swoosh://oauth/callback"
    ) throws -> MCPAuthSession {
        let resource = MCPResourceIndicator(canonicalURI: endpoint)
        let pkce = MCPPKCEPair.generate()
        let state = UUID().uuidString

        let session = MCPAuthSession(
            serverID: serverID, state: state,
            pkceVerifierSecretRef: "keychain://pkce_\(serverID)_\(state)",
            resourceIndicator: resource, requestedScopes: scopes,
            redirectURI: redirectURI
        )
        sessions[session.id] = session
        appendAudit(.init(kind: .authStarted, serverID: serverID, message: "OAuth flow started"))
        return session
    }

    // ── Token exchange ────────────────────────────────────────────

    public func exchangeCode(
        sessionID: String, code: String, returnedState: String
    ) async throws -> MCPStoredToken {
        guard let session = sessions[sessionID] else {
            throw MCPAuthError.sessionNotFound(sessionID)
        }
        guard !session.isExpired else {
            sessions.removeValue(forKey: sessionID)
            throw MCPAuthError.sessionExpired(sessionID)
        }
        guard session.state == returnedState else {
            throw MCPAuthError.stateMismatch
        }

        // In production: call token endpoint with code + verifier + resource
        // For now: create token with Keychain refs
        let token = MCPStoredToken(
            accessTokenSecretRef: "keychain://access_\(session.serverID)",
            refreshTokenSecretRef: "keychain://refresh_\(session.serverID)",
            expiresAt: Date().addingTimeInterval(3600),
            scopes: session.requestedScopes,
            audience: MCPTokenAudience(
                resourceIndicator: session.resourceIndicator,
                serverID: session.serverID
            )
        )

        try await tokenStore.saveToken(token, for: session.serverID)
        sessions.removeValue(forKey: sessionID) // Destroy session after exchange
        appendAudit(.init(kind: .tokenExchanged, serverID: session.serverID, message: "Token exchanged"))
        appendAudit(.init(kind: .tokenStored, serverID: session.serverID, message: "Token stored in Keychain"))
        return token
    }

    // ── Token validation ──────────────────────────────────────────

    public func validateTokenAudience(serverID: String, expectedResource: String) async throws -> Bool {
        guard let token = try await tokenStore.loadToken(serverID: serverID) else {
            throw MCPAuthError.tokenNotFound(serverID)
        }
        return token.audience.resourceIndicator.canonicalURI == expectedResource
    }

    // ── Token refresh ─────────────────────────────────────────────

    public func refreshIfNeeded(serverID: String) async throws -> MCPStoredToken {
        guard let token = try await tokenStore.loadToken(serverID: serverID) else {
            throw MCPAuthError.tokenNotFound(serverID)
        }
        guard token.needsRefresh else { return token }
        guard token.refreshTokenSecretRef != nil else {
            throw MCPAuthError.refreshFailed("No refresh token")
        }

        // In production: call token endpoint with refresh_token + resource
        let refreshed = MCPStoredToken(
            accessTokenSecretRef: "keychain://access_\(serverID)_refreshed",
            refreshTokenSecretRef: token.refreshTokenSecretRef,
            expiresAt: Date().addingTimeInterval(3600),
            scopes: token.scopes,
            audience: token.audience
        )

        try await tokenStore.saveToken(refreshed, for: serverID)
        appendAudit(.init(kind: .tokenRefreshed, serverID: serverID, message: "Token refreshed"))
        return refreshed
    }

    // ── Revocation ────────────────────────────────────────────────

    public func revokeToken(serverID: String) async throws {
        try await tokenStore.deleteToken(serverID: serverID)
        appendAudit(.init(kind: .tokenRevoked, serverID: serverID, message: "Token revoked and deleted"))
    }

    // ── Token status ──────────────────────────────────────────────

    public func getTokenStatus(serverID: String) async throws -> MCPTokenStatus {
        guard let token = try await tokenStore.loadToken(serverID: serverID) else {
            return .notFound
        }
        if token.isExpired { return .expired }
        if token.needsRefresh { return .needsRefresh }
        return .valid
    }

    // ── Session management ────────────────────────────────────────

    public func getSession(_ id: String) -> MCPAuthSession? { sessions[id] }
    public func destroySession(_ id: String) { sessions.removeValue(forKey: id) }

    // ── Audit ─────────────────────────────────────────────────────

    private func appendAudit(_ event: MCPAuthAuditEvent) { auditLog.append(event) }
    public func getAuditLog() -> [MCPAuthAuditEvent] { auditLog }
}

public enum MCPTokenStatus: String, Codable, Sendable {
    case notFound, valid, needsRefresh, expired, revoked
}
