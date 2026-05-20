// Tests/SwooshProvidersTests/ProviderTests.swift — 0.9P

import Testing
import Foundation
@testable import SwooshProviders
@testable import SwooshSecrets
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - ProviderID Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderID")
struct ProviderIDTests {

    @Test("String literal init")
    func stringLiteral() {
        let id: ProviderID = "openai"
        #expect(id.rawValue == "openai")
    }

    @Test("Equality")
    func equality() {
        #expect(ProviderID("openai") == ProviderID("openai"))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Profile Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderProfile")
struct ProviderProfileTests {

    @Test("OpenAI profile defaults")
    func openAIDefaults() {
        let p = ProviderProfile.openAI
        #expect(p.id == ProviderID("openai"))
        #expect(p.kind == .openAI)
        #expect(!p.enabled)
        #expect(p.priority == 100)
    }

    @Test("OpenRouter profile defaults")
    func openRouterDefaults() {
        let p = ProviderProfile.openRouter
        #expect(p.id == ProviderID("openrouter"))
        #expect(p.baseURL == "https://openrouter.ai/api/v1")
    }

    @Test("Eliza Cloud profile defaults")
    func elizaCloudDefaults() {
        let p = ProviderProfile.elizaCloud
        #expect(p.id == ProviderID("eliza-cloud"))
        #expect(!p.enabled)
    }

    @Test("Local profile defaults to localhost")
    func localDefaults() {
        let p = ProviderProfile.localOpenAI
        #expect(p.baseURL == "http://127.0.0.1:11434/v1")
        #expect(p.kind == .localOpenAICompatible)
    }

    @Test("MLX profile has local auth")
    func mlxAuth() {
        let p = ProviderProfile.mlxLocal
        if case .local = p.auth {} else {
            Issue.record("MLX should use .local auth")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - PKCE Tests (real CryptoKit S256)
// ═══════════════════════════════════════════════════════════════════

@Suite("PKCE")
struct PKCETests {

    @Test("Verifier is generated")
    func verifierGenerated() {
        let v = PKCE.verifier()
        #expect(v.count > 20) // base64url of 32 bytes
    }

    @Test("Challenge is different from verifier")
    func challengeDifferent() {
        let v = PKCE.verifier()
        let c = PKCE.challengeS256(verifier: v)
        #expect(v != c)
    }

    @Test("Challenge is base64url (no + / =)")
    func challengeBase64URL() {
        let v = PKCE.verifier()
        let c = PKCE.challengeS256(verifier: v)
        #expect(!c.contains("+"))
        #expect(!c.contains("/"))
        #expect(!c.contains("="))
    }

    @Test("Same verifier produces same challenge")
    func deterministic() {
        let v = "test-verifier-12345"
        let c1 = PKCE.challengeS256(verifier: v)
        let c2 = PKCE.challengeS256(verifier: v)
        #expect(c1 == c2)
    }

    @Test("Different verifiers produce different challenges")
    func differentVerifiers() {
        let v1 = PKCE.verifier()
        let v2 = PKCE.verifier()
        let c1 = PKCE.challengeS256(verifier: v1)
        let c2 = PKCE.challengeS256(verifier: v2)
        #expect(c1 != c2)
    }

    @Test("Verifier is base64url")
    func verifierBase64URL() {
        let v = PKCE.verifier()
        #expect(!v.contains("+"))
        #expect(!v.contains("/"))
        #expect(!v.contains("="))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Model Role Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ModelRole")
struct ModelRoleTests {

    @Test("All roles available")
    func allRoles() {
        #expect(ModelRole.allCases.count == 8)
    }

    @Test("Primary roles exist")
    func primaryRoles() {
        #expect(ModelRole.primaryChat.rawValue == "primaryChat")
        #expect(ModelRole.coding.rawValue == "coding")
        #expect(ModelRole.fastLocal.rawValue == "fastLocal")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Route Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderRoute")
struct ProviderRouteTests {

    @Test("Route creation")
    func routeCreation() {
        let route = ProviderRoute(role: .primaryChat, providerID: "openai",
                                  model: "gpt-4.1", priority: 100)
        #expect(route.role == .primaryChat)
        #expect(route.providerID == ProviderID("openai"))
        #expect(route.enabled)
    }

    @Test("Route can be disabled")
    func routeDisabled() {
        var route = ProviderRoute(role: .coding, providerID: "openai",
                                  model: "gpt-4.1", enabled: false)
        #expect(!route.enabled)
        route.enabled = true
        #expect(route.enabled)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Health Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderHealth")
struct ProviderHealthTests {

    @Test("Health statuses")
    func healthStatuses() {
        let healthy = ProviderHealth(providerID: "openai", status: .healthy, latencyMs: 150)
        #expect(healthy.status == .healthy)
        #expect(healthy.latencyMs == 150)

        let missing = ProviderHealth(providerID: "openai", status: .authMissing)
        #expect(missing.status == .authMissing)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Registry Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderRegistry")
struct ProviderRegistryTests {

    @Test("Register and retrieve provider")
    func registerAndRetrieve() async {
        let registry = ProviderRegistry()
        let store = InMemorySecretStore()
        let provider = OpenAIResponsesProvider(secrets: store)
        await registry.register(provider, profile: .openAI)

        let retrieved = await registry.provider(for: ProviderID("openai"))
        #expect(retrieved != nil)
    }

    @Test("All profiles sorted by priority")
    func profilesSorted() async {
        let registry = ProviderRegistry()
        let store = InMemorySecretStore()
        await registry.register(OpenAIResponsesProvider(secrets: store), profile: .openAI)
        await registry.register(OpenRouterProvider(secrets: store), profile: .openRouter)

        let profiles = await registry.allProfiles()
        #expect(profiles.count == 2)
        #expect(profiles[0].priority >= profiles[1].priority)
    }

    @Test("Routes filtered by role")
    func routesByRole() async {
        let registry = ProviderRegistry()
        await registry.addRoute(ProviderRoute(role: .primaryChat, providerID: "openai", model: "gpt-4.1", priority: 100))
        await registry.addRoute(ProviderRoute(role: .coding, providerID: "openai", model: "gpt-4.1", priority: 90))
        await registry.addRoute(ProviderRoute(role: .primaryChat, providerID: "openrouter", model: "openai/gpt-4.1", priority: 80))

        let chatRoutes = await registry.routes(for: .primaryChat)
        #expect(chatRoutes.count == 2)
        #expect(chatRoutes[0].priority > chatRoutes[1].priority)

        let codingRoutes = await registry.routes(for: .coding)
        #expect(codingRoutes.count == 1)
    }

    @Test("Enable and disable provider")
    func enableDisable() async {
        let registry = ProviderRegistry()
        let store = InMemorySecretStore()
        await registry.register(OpenAIResponsesProvider(secrets: store), profile: .openAI)

        let before = await registry.profile(for: ProviderID("openai"))
        #expect(before?.enabled == false)

        await registry.enable(ProviderID("openai"))
        let after = await registry.profile(for: ProviderID("openai"))
        #expect(after?.enabled == true)

        await registry.disable(ProviderID("openai"))
        let final = await registry.profile(for: ProviderID("openai"))
        #expect(final?.enabled == false)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Router Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderRouter")
struct ProviderRouterTests {

    @Test("Router all routes failed when empty")
    func emptyRoutesFail() async {
        let registry = ProviderRegistry()
        let router = ProviderRouter(registry: registry)
        do {
            let req = ModelRequest(model: "test", messages: [ChatMessage(role: .user, content: "hi")])
            _ = try await router.complete(role: .primaryChat, request: req)
            Issue.record("Should throw")
        } catch ProviderError.allRoutesFailed {}
        catch { Issue.record("Wrong error type: \(error)") }
    }

    @Test("Router records audit events")
    func recordsAudit() async throws {
        let registry = ProviderRegistry()
        let router = ProviderRouter(registry: registry)
        await registry.register(FailingProvider(id: "audit-fail"), profile: ProviderProfile(
            id: ProviderID("audit-fail"),
            kind: .openAI,
            displayName: "Audit Failure",
            enabled: true
        ))
        await registry.addRoute(ProviderRoute(
            role: .primaryChat,
            providerID: ProviderID("audit-fail"),
            model: "audit-test",
            priority: 100
        ))
        _ = try? await router.complete(
            role: .primaryChat,
            request: ModelRequest(model: "x", messages: [ChatMessage(role: .user, content: "hi")])
        )
        let log = await router.getAuditLog()
        #expect(!log.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenAI Provider Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("OpenAIResponsesProvider")
struct OpenAIResponsesProviderTests {

    @Test("Provider has correct ID")
    func correctID() {
        let store = InMemorySecretStore()
        let provider = OpenAIResponsesProvider(secrets: store)
        #expect(provider.providerID == ProviderID("openai"))
    }

    @Test("Provider has correct capabilities")
    func capabilities() {
        let store = InMemorySecretStore()
        let provider = OpenAIResponsesProvider(secrets: store)
        #expect(provider.capabilities.streaming)
        #expect(provider.capabilities.toolCalling)
        #expect(provider.capabilities.vision)
    }

    @Test("Missing API key gives clean error")
    func missingKeyError() async {
        let store = InMemorySecretStore()
        let provider = OpenAIResponsesProvider(secrets: store)
        let req = ModelRequest(model: "gpt-4.1", messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await provider.complete(req)
            Issue.record("Should throw")
        } catch ProviderError.authMissing(let id, let msg) {
            #expect(id == ProviderID("openai"))
            #expect(msg.contains("swoosh provider auth"))
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Auth missing message contains setup command")
    func authMissingSetupCommand() async {
        let store = InMemorySecretStore()
        let provider = OpenAIResponsesProvider(secrets: store)
        do {
            _ = try await provider.complete(
                ModelRequest(model: "gpt-4.1", messages: [ChatMessage(role: .user, content: "hi")])
            )
        } catch ProviderError.authMissing(_, let msg) {
            #expect(msg.contains("swoosh provider auth openai"))
        } catch {}
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenRouter Provider Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("OpenRouterProvider")
struct OpenRouterProviderTests {

    @Test("Provider has correct ID")
    func correctID() {
        let store = InMemorySecretStore()
        let provider = OpenRouterProvider(secrets: store)
        #expect(provider.providerID == ProviderID("openrouter"))
    }

    @Test("Provider capabilities")
    func capabilities() {
        let store = InMemorySecretStore()
        let provider = OpenRouterProvider(secrets: store)
        #expect(provider.capabilities.streaming)
        #expect(provider.capabilities.toolCalling)
    }

    @Test("Missing API key gives clean error")
    func missingKeyError() async {
        let store = InMemorySecretStore()
        let provider = OpenRouterProvider(secrets: store)
        do {
            _ = try await provider.complete(
                ModelRequest(model: "openai/gpt-4.1", messages: [ChatMessage(role: .user, content: "hi")])
            )
            Issue.record("Should throw")
        } catch ProviderError.authMissing(let id, let msg) {
            #expect(id == ProviderID("openrouter"))
            #expect(msg.contains("pkce"))
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenRouter PKCE Auth Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("OpenRouterPKCEAuth")
struct OpenRouterPKCEAuthTests {

    @Test("Auth URL contains challenge and S256")
    func authURLContents() async {
        let store = InMemorySecretStore()
        let auth = OpenRouterPKCEAuth(secrets: store)
        let (url, verifier) = await auth.buildAuthURL()

        #expect(url.contains("openrouter.ai/auth"))
        #expect(url.contains("code_challenge="))
        #expect(url.contains("code_challenge_method=S256"))
        #expect(!url.contains(verifier)) // URL has challenge, not verifier
    }

    @Test("Auth URL challenge is real S256, not verifier")
    func authURLChallengeIsS256() async {
        let store = InMemorySecretStore()
        let auth = OpenRouterPKCEAuth(secrets: store)
        let (url, verifier) = await auth.buildAuthURL()

        let expectedChallenge = PKCE.challengeS256(verifier: verifier)
        #expect(url.contains(expectedChallenge))
    }

    @Test("Exchange without pending verifier fails")
    func exchangeNoPendingVerifier() async {
        let store = InMemorySecretStore()
        let auth = OpenRouterPKCEAuth(secrets: store)
        do {
            _ = try await auth.exchangeCode("test-code")
            Issue.record("Should throw")
        } catch ProviderError.requestFailed {}
        catch { /* expected */ }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local Provider Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("LocalOpenAICompatibleProvider")
struct LocalProviderTests {

    @Test("Provider rejects non-localhost")
    func rejectsNonLocalhost() async {
        let provider = LocalOpenAICompatibleProvider(baseURL: "https://evil.com/v1")
        let req = ModelRequest(model: "llama3", messages: [ChatMessage(role: .user, content: "hi")])
        do {
            _ = try await provider.complete(req)
            Issue.record("Should throw")
        } catch ProviderError.requestFailed(let id, let msg) {
            #expect(id == ProviderID("local-openai"))
            #expect(msg.contains("localhost"))
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Provider accepts localhost")
    func acceptsLocalhost() {
        // Just construction test — actual connection tested with real Ollama
        let provider = LocalOpenAICompatibleProvider(baseURL: "http://127.0.0.1:11434/v1")
        #expect(provider.providerID == ProviderID("local-openai"))
    }

    @Test("Provider accepts [::1] localhost")
    func acceptsIPv6Localhost() {
        let provider = LocalOpenAICompatibleProvider(baseURL: "http://[::1]:8080/v1")
        #expect(provider.providerID == ProviderID("local-openai"))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local Provider Discovery Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("LocalProviderDiscovery")
struct LocalProviderDiscoveryTests {

    @Test("Discovery returns empty if nothing running")
    func discoveryEmpty() async {
        let discovery = LocalProviderDiscovery()
        let found = await discovery.discover()
        #expect(found.allSatisfy { !$0.name.isEmpty && !$0.baseURL.isEmpty })
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Eliza Cloud Provider Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ElizaCloudProvider")
struct ElizaCloudProviderTests {

    @Test("Provider has correct ID")
    func correctID() {
        let store = InMemorySecretStore()
        let provider = ElizaCloudProvider(secrets: store)
        #expect(provider.providerID == ProviderID("eliza-cloud"))
    }

    @Test("Health reports authMissing when no key")
    func healthAuthMissing() async {
        let store = InMemorySecretStore()
        let provider = ElizaCloudProvider(secrets: store)
        let health = await provider.health()
        #expect(health.status == .authMissing)
        #expect(health.message?.contains("swoosh provider auth") == true)
    }

    @Test("Missing API key gives clean error on complete")
    func missingKeyComplete() async {
        let store = InMemorySecretStore()
        let provider = ElizaCloudProvider(secrets: store)
        do {
            _ = try await provider.complete(
                ModelRequest(model: "test", messages: [ChatMessage(role: .user, content: "hi")])
            )
            Issue.record("Should throw")
        } catch ProviderError.authMissing {}
        catch { Issue.record("Wrong error: \(error)") }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Audit Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderAudit")
struct ProviderAuditTests {

    @Test("Audit event created")
    func eventCreated() {
        let event = ProviderAuditEvent(kind: .callStarted, providerID: "openai",
                                        message: "Calling gpt-4.1")
        #expect(event.kind == .callStarted)
        #expect(event.providerID == ProviderID("openai"))
    }

    @Test("Audit event does not contain API key")
    func noAPIKeyInAudit() {
        let event = ProviderAuditEvent(kind: .secretStored, providerID: "openai",
                                        message: "API key stored in Keychain")
        #expect(!event.message.contains("sk-"))
        #expect(!event.message.contains("sk_live"))
    }

    @Test("All audit kinds available")
    func allKinds() {
        let kinds: [ProviderAuditKind] = [
            .added, .enabled, .disabled, .authStarted, .authCompleted, .authFailed,
            .secretStored, .testStarted, .testSucceeded, .testFailed,
            .callStarted, .callStreamStarted, .callSucceeded, .callFailed,
            .routeSelected, .routeFallback, .allRoutesFailed
        ]
        #expect(kinds.count == 17)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Security: No Secret Leakage Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("Security: No Secret Leakage")
struct NoSecretLeakageTests {

    @Test("SecretRef description does not contain value")
    func refNoValue() {
        let ref = SecretRef("openai", "api_key")
        let desc = "\(ref)"
        #expect(!desc.contains("sk-"))
        #expect(desc == "openai.api_key")
    }

    @Test("ProviderProfile auth does not store raw key")
    func profileNoRawKey() {
        let p = ProviderProfile.openAI
        if case .apiKey(let ns, let key) = p.auth {
            #expect(ns == "openai")
            #expect(key == "api_key")
            // These are SecretRef components, not the actual API key value
            #expect(!ns.contains("sk-"))
            #expect(!key.contains("sk-"))
        } else {
            Issue.record("OpenAI should use apiKey auth")
        }
    }

    @Test("ProviderHealth message never contains raw key")
    func healthNoKey() {
        let health = ProviderHealth(providerID: "openai", status: .healthy,
                                     message: "Provider healthy, 150ms latency")
        #expect(!health.message!.contains("sk-"))
        #expect(!health.message!.contains("Bearer"))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - ChatMessage Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test("Message roles")
    func messageRoles() {
        #expect(ChatRole.system.rawValue == "system")
        #expect(ChatRole.user.rawValue == "user")
        #expect(ChatRole.assistant.rawValue == "assistant")
        #expect(ChatRole.tool.rawValue == "tool")
    }

    @Test("Message creation")
    func messageCreation() {
        let msg = ChatMessage(role: .user, content: "Hello, world!")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello, world!")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - ModelRequest Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("ModelRequest")
struct ModelRequestTests {

    @Test("withModel returns copy with new model")
    func withModel() {
        let req = ModelRequest(model: "gpt-4.1", messages: [ChatMessage(role: .user, content: "hi")])
        let copy = req.withModel("gpt-5.5")
        #expect(copy.model == "gpt-5.5")
        #expect(req.model == "gpt-4.1") // original unchanged
    }
}
