// Tests/SwooshSecretsTests/SecretsTests.swift — 0.9P

import Testing
import Foundation
@testable import SwooshSecrets

// ═══════════════════════════════════════════════════════════════════
// MARK: - SecretRef Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("SecretRef")
struct SecretRefTests {

    @Test("Account format is namespace.key")
    func accountFormat() {
        let ref = SecretRef("openai", "api_key")
        #expect(ref.account == "openai.api_key")
    }

    @Test("Description does not reveal value")
    func descriptionNoValue() {
        let ref = SecretRef("openai", "api_key")
        #expect(ref.description == "openai.api_key")
        #expect(!ref.description.contains("sk-"))
    }

    @Test("Equality check")
    func equality() {
        let a = SecretRef("openai", "api_key")
        let b = SecretRef("openai", "api_key")
        #expect(a == b)
    }

    @Test("Inequality for different keys")
    func inequality() {
        let a = SecretRef("openai", "api_key")
        let b = SecretRef("openrouter", "api_key")
        #expect(a != b)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - InMemorySecretStore Tests
// ═══════════════════════════════════════════════════════════════════

@Suite("InMemorySecretStore")
struct InMemorySecretStoreTests {

    @Test("Set and get secret")
    func setAndGet() async throws {
        let store = InMemorySecretStore()
        try await store.set("sk-test-123", ref: SecretRef("openai", "api_key"))
        let value = try await store.get(SecretRef("openai", "api_key"))
        #expect(value == "sk-test-123")
    }

    @Test("Get missing throws notFound")
    func getMissing() async {
        let store = InMemorySecretStore()
        do {
            _ = try await store.get(SecretRef("openai", "api_key"))
            Issue.record("Should throw")
        } catch is SecretError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Delete secret")
    func deleteSecret() async throws {
        let store = InMemorySecretStore()
        try await store.set("val", ref: SecretRef("a", "b"))
        await store.delete(SecretRef("a", "b"))
        do {
            _ = try await store.get(SecretRef("a", "b"))
            Issue.record("Should throw")
        } catch is SecretError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Exists check")
    func existsCheck() async throws {
        let store = InMemorySecretStore()
        let ref = SecretRef("openai", "api_key")
        let before = await store.exists(ref)
        #expect(!before)
        try await store.set("sk-123", ref: ref)
        let after = await store.exists(ref)
        #expect(after)
    }

    @Test("List refs by namespace")
    func listByNamespace() async throws {
        let store = InMemorySecretStore()
        try await store.set("a", ref: SecretRef("openai", "api_key"))
        try await store.set("b", ref: SecretRef("openai", "org_id"))
        try await store.set("c", ref: SecretRef("openrouter", "api_key"))

        let openaiRefs = await store.listRefs(namespace: "openai")
        #expect(openaiRefs.count == 2)

        let allRefs = await store.listRefs(namespace: nil)
        #expect(allRefs.count == 3)
    }

    @Test("List refs never returns values")
    func listRefsNoValues() async throws {
        let store = InMemorySecretStore()
        try await store.set("sk-super-secret-key", ref: SecretRef("openai", "api_key"))
        let refs = await store.listRefs(namespace: nil)
        for ref in refs {
            #expect(!ref.description.contains("sk-super-secret-key"))
            #expect(!ref.account.contains("sk-super-secret-key"))
        }
    }

    @Test("Overwrite existing secret")
    func overwrite() async throws {
        let store = InMemorySecretStore()
        let ref = SecretRef("openai", "api_key")
        try await store.set("old-value", ref: ref)
        try await store.set("new-value", ref: ref)
        let val = try await store.get(ref)
        #expect(val == "new-value")
    }
}
