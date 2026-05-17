// Tests/SwooshMCPAuthTests/MCPAuthTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshMCPAuth
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Auth Discovery Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Auth Discovery")
struct AuthDiscoveryTests {

    @Test("Protected resource metadata parses")
    func protectedResourceMetadata() {
        let m = MCPProtectedResourceMetadata(
            resource: "https://linear.example/mcp",
            authorizationServers: ["https://auth.linear.example"],
            scopesSupported: ["issues:read", "comments:write"]
        )
        #expect(m.authorizationServers.count == 1)
        #expect(m.scopesSupported?.count == 2)
    }

    @Test("Auth server metadata validates PKCE")
    func authServerValidatesPKCE() {
        let m = MCPAuthorizationServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token",
            codeChallengeMethodsSupported: ["S256"]
        )
        #expect(m.supportsPKCES256)
    }

    @Test("Missing PKCE support detected")
    func missingPKCE() {
        let m = MCPAuthorizationServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token",
            codeChallengeMethodsSupported: ["plain"]
        )
        #expect(!m.supportsPKCES256)
    }

    @Test("Non-HTTPS issuer detected")
    func nonHTTPSIssuer() {
        let m = MCPAuthorizationServerMetadata(
            issuer: "http://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token"
        )
        #expect(!m.issuerIsHTTPS)
    }

    @Test("Auth service validates HTTPS issuer")
    func serviceValidatesHTTPS() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let m = MCPAuthorizationServerMetadata(
            issuer: "http://bad.example.com",
            authorizationEndpoint: "https://bad.example.com/authorize",
            tokenEndpoint: "https://bad.example.com/token"
        )
        do {
            try await svc.validateAuthServerMetadata(m)
            Issue.record("Should throw")
        } catch is MCPAuthError {}
    }

    @Test("Auth service validates PKCE support")
    func serviceValidatesPKCE() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let m = MCPAuthorizationServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: "https://auth.example.com/authorize",
            tokenEndpoint: "https://auth.example.com/token",
            codeChallengeMethodsSupported: ["plain"]
        )
        do {
            try await svc.validateAuthServerMetadata(m)
            Issue.record("Should throw")
        } catch is MCPAuthError {}
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - PKCE Tests
// ═══════════════════════════════════════════════════════════════

@Suite("PKCE")
struct PKCETests {

    @Test("PKCE generates verifier and challenge")
    func generatesPair() {
        let pair = MCPPKCEPair.generate()
        #expect(!pair.codeVerifier.isEmpty)
        #expect(!pair.codeChallenge.isEmpty)
        #expect(pair.method == "S256")
    }

    @Test("PKCE with specific verifier")
    func specificVerifier() {
        let pair = MCPPKCEPair.generate(verifier: "test-verifier-value")
        #expect(pair.codeVerifier == "test-verifier-value")
        #expect(pair.codeChallenge.hasPrefix("S256_"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Resource Indicator Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Resource Indicators")
struct ResourceIndicatorTests {

    @Test("Resource indicator created")
    func indicatorCreated() {
        let ri = MCPResourceIndicator(canonicalURI: "https://linear.example/mcp")
        #expect(ri.canonicalURI == "https://linear.example/mcp")
    }

    @Test("Token audience stores resource indicator")
    func tokenAudienceStored() {
        let ri = MCPResourceIndicator(canonicalURI: "https://linear.example/mcp")
        let aud = MCPTokenAudience(resourceIndicator: ri, serverID: "linear")
        #expect(aud.serverID == "linear")
        #expect(aud.resourceIndicator == ri)
    }

    @Test("Token for server A cannot be validated for server B")
    func crossServerTokenRejected() async throws {
        let store = InMemoryMCPTokenStore()
        let svc = MCPAuthService(tokenStore: store)
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp",
            scopes: ["issues:read"]
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "test-code", returnedState: session.state)

        let valid = try await svc.validateTokenAudience(serverID: "linear", expectedResource: "https://linear.example/mcp")
        #expect(valid)

        let invalid = try await svc.validateTokenAudience(serverID: "linear", expectedResource: "https://github.example/mcp")
        #expect(!invalid)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Auth Flow Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Auth Flow")
struct AuthFlowTests {

    @Test("Start auth creates session")
    func startCreatesSession() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp",
            scopes: ["issues:read"]
        )
        #expect(session.serverID == "linear")
        #expect(!session.state.isEmpty)
        #expect(session.pkceVerifierSecretRef.hasPrefix("keychain://"))
        #expect(session.resourceIndicator.canonicalURI == "https://linear.example/mcp")
    }

    @Test("Exchange code stores token as Keychain ref")
    func exchangeStoresRef() async throws {
        let store = InMemoryMCPTokenStore()
        let svc = MCPAuthService(tokenStore: store)
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp",
            scopes: ["issues:read"]
        )
        let token = try await svc.exchangeCode(sessionID: session.id, code: "test-code", returnedState: session.state)
        #expect(token.accessTokenSecretRef.hasPrefix("keychain://"))
        #expect(token.refreshTokenSecretRef?.hasPrefix("keychain://") ?? false)
        let stored = try await store.loadToken(serverID: "linear")
        #expect(stored != nil)
    }

    @Test("State mismatch fails")
    func stateMismatchFails() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        do {
            _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: "wrong-state")
            Issue.record("Should throw")
        } catch MCPAuthError.stateMismatch {}
    }

    @Test("Session destroyed after exchange")
    func sessionDestroyedAfterExchange() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: session.state)
        let after = await svc.getSession(session.id)
        #expect(after == nil) // Session destroyed = verifier gone
    }

    @Test("Session not found fails")
    func sessionNotFoundFails() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        do {
            _ = try await svc.exchangeCode(sessionID: "nonexistent", code: "code", returnedState: "state")
            Issue.record("Should throw")
        } catch MCPAuthError.sessionNotFound {}
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Token Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Token Store")
struct TokenStoreTests {

    @Test("Save and load token")
    func saveAndLoad() async throws {
        let store = InMemoryMCPTokenStore()
        let token = MCPStoredToken(
            accessTokenSecretRef: "keychain://access_linear",
            audience: MCPTokenAudience(
                resourceIndicator: MCPResourceIndicator(canonicalURI: "https://linear.example/mcp"),
                serverID: "linear"
            )
        )
        try await store.saveToken(token, for: "linear")
        let loaded = try await store.loadToken(serverID: "linear")
        #expect(loaded?.accessTokenSecretRef == "keychain://access_linear")
    }

    @Test("Token stores refs not raw values")
    func storesRefs() async throws {
        let store = InMemoryMCPTokenStore()
        let token = MCPStoredToken(
            accessTokenSecretRef: "keychain://access_linear",
            refreshTokenSecretRef: "keychain://refresh_linear",
            audience: MCPTokenAudience(
                resourceIndicator: MCPResourceIndicator(canonicalURI: "https://linear.example/mcp"),
                serverID: "linear"
            )
        )
        try await store.saveToken(token, for: "linear")
        let loaded = try await store.loadToken(serverID: "linear")!
        #expect(loaded.accessTokenSecretRef.hasPrefix("keychain://"))
        #expect(loaded.refreshTokenSecretRef?.hasPrefix("keychain://") ?? false)
    }

    @Test("Delete token")
    func deleteToken() async throws {
        let store = InMemoryMCPTokenStore()
        let token = MCPStoredToken(
            accessTokenSecretRef: "keychain://access_linear",
            audience: MCPTokenAudience(
                resourceIndicator: MCPResourceIndicator(canonicalURI: "https://linear.example/mcp"),
                serverID: "linear"
            )
        )
        try await store.saveToken(token, for: "linear")
        try await store.deleteToken(serverID: "linear")
        let loaded = try await store.loadToken(serverID: "linear")
        #expect(loaded == nil)
    }

    @Test("Token expiry detection")
    func tokenExpiry() {
        let expired = MCPStoredToken(
            accessTokenSecretRef: "keychain://x",
            expiresAt: Date().addingTimeInterval(-100),
            audience: MCPTokenAudience(
                resourceIndicator: MCPResourceIndicator(canonicalURI: "https://x"),
                serverID: "x"
            )
        )
        #expect(expired.isExpired)
    }

    @Test("Token needs refresh")
    func tokenNeedsRefresh() {
        let nearExpiry = MCPStoredToken(
            accessTokenSecretRef: "keychain://x",
            expiresAt: Date().addingTimeInterval(60), // 60 seconds left, < 5min skew
            audience: MCPTokenAudience(
                resourceIndicator: MCPResourceIndicator(canonicalURI: "https://x"),
                serverID: "x"
            )
        )
        #expect(nearExpiry.needsRefresh)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Token Refresh/Revoke Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Token Lifecycle")
struct TokenLifecycleTests {

    @Test("Revoke deletes refs")
    func revokeDeletes() async throws {
        let store = InMemoryMCPTokenStore()
        let svc = MCPAuthService(tokenStore: store)
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: session.state)
        try await svc.revokeToken(serverID: "linear")
        let loaded = try await store.loadToken(serverID: "linear")
        #expect(loaded == nil)
    }

    @Test("Token status valid")
    func statusValid() async throws {
        let store = InMemoryMCPTokenStore()
        let svc = MCPAuthService(tokenStore: store)
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: session.state)
        let status = try await svc.getTokenStatus(serverID: "linear")
        #expect(status == .valid)
    }

    @Test("Token status not found")
    func statusNotFound() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let status = try await svc.getTokenStatus(serverID: "none")
        #expect(status == .notFound)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Scope Strategy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Scope Strategy")
struct ScopeStrategyTests {

    @Test("Minimal scope strategy defaults")
    func minimalDefaults() {
        let s = MCPScopeStrategy.minimal
        #expect(s.preferredScopes.isEmpty)
        #expect(s.requiredScopes.isEmpty)
        #expect(!s.requestAllSupportedIfUnknown)
        #expect(s.allowStepUpAuthorization)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Auth Audit Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Auth Audit")
struct AuthAuditTests {

    @Test("Audit records auth events without secrets")
    func auditNoSecrets() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: session.state)
        let log = await svc.getAuditLog()
        #expect(log.count >= 2)
        for event in log {
            #expect(!event.message.contains("keychain://"))
            #expect(!event.message.lowercased().contains("token="))
            #expect(!event.message.lowercased().contains("bearer"))
        }
    }

    @Test("Audit records token exchange")
    func auditTokenExchange() async throws {
        let svc = MCPAuthService(tokenStore: InMemoryMCPTokenStore())
        let session = try await svc.startAuthFlow(
            serverID: "linear", endpoint: "https://linear.example/mcp", scopes: []
        )
        _ = try await svc.exchangeCode(sessionID: session.id, code: "code", returnedState: session.state)
        let log = await svc.getAuditLog()
        #expect(log.contains { $0.kind == .tokenExchanged })
        #expect(log.contains { $0.kind == .tokenStored })
    }
}
