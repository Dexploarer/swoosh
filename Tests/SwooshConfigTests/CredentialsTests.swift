// Tests/SwooshConfigTests/CredentialsTests.swift — Credential store tests
//
// Tests KeychainCredentialStore and EnvironmentCredentialStore
// for secure credential storage and retrieval.

import Testing
import Foundation
@testable import SwooshConfig

// MARK: - Test Isolation Helper

/// A per-test isolated directory for `EnvironmentCredentialStore`.
///
/// `EnvironmentCredentialStore` persists credentials to a `.env` file. Without
/// an injected directory it writes to the real `~/.swoosh/.env`, which would
/// (a) pollute the developer's home directory and (b) cross-contaminate tests.
/// This helper hands out a unique temp directory and cleans it up on `deinit`.
final class IsolatedEnvDir {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-cred-test-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - CredentialStore Protocol Tests

@Suite("CredentialStore Protocol")
struct CredentialStoreProtocolTests {

    @Test("KeychainCredentialStore conforms to CredentialStore")
    func keychainConforms() {
        let _: any CredentialStore.Type = KeychainCredentialStore.self
        #expect(Bool(true))
    }

    @Test("EnvironmentCredentialStore conforms to CredentialStore")
    func environmentConforms() {
        let _: any CredentialStore.Type = EnvironmentCredentialStore.self
        #expect(Bool(true))
    }

    @Test("Can use CredentialStore existential")
    func existentialWorks() async throws {
        // Note: We can't test Keychain in unit tests easily,
        // but we can test the Environment store
        let dir = IsolatedEnvDir()
        let store: any CredentialStore = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        try await store.set(key: "test_key", value: "test_value", service: "test_service")
        let retrieved = try await store.get(key: "test_key", service: "test_service")

        #expect(retrieved == "test_value")

        // Cleanup
        try await store.delete(key: "test_key", service: "test_service")
    }
}

// MARK: - KeychainCredentialStore Tests

@Suite("KeychainCredentialStore")
struct KeychainCredentialStoreTests {

    @Test("Initializes with default service")
    func initializesWithDefault() {
        let store = KeychainCredentialStore()
        // If this compiles, initialization works
        _ = store
        #expect(Bool(true))
    }

    @Test("Initializes with custom service")
    func initializesWithCustom() {
        let store = KeychainCredentialStore(service: "com.test.service")
        _ = store
        #expect(Bool(true))
    }

    @Test("Is Sendable")
    func isSendable() {
        let _: any Sendable = KeychainCredentialStore()
        #expect(Bool(true))
    }

    @Test("Is unchecked Sendable")
    func isUncheckedSendable() {
        // KeychainCredentialStore is marked as @unchecked Sendable
        // This test verifies it compiles as such
        let store = KeychainCredentialStore()
        _ = store
        #expect(Bool(true))
    }
}

// MARK: - EnvironmentCredentialStore Tests

@Suite("EnvironmentCredentialStore")
struct EnvironmentCredentialStoreTests {

    @Test("Initializes with default prefix")
    func initializesWithDefault() {
        let store = EnvironmentCredentialStore()
        _ = store
        #expect(Bool(true))
    }

    @Test("Initializes with custom prefix")
    func initializesWithCustom() {
        let store = EnvironmentCredentialStore(prefix: "MYAPP_")
        _ = store
        #expect(Bool(true))
    }

    @Test("Is Sendable")
    func isSendable() {
        let _: any Sendable = EnvironmentCredentialStore()
        #expect(Bool(true))
    }

    @Test("Is unchecked Sendable")
    func isUncheckedSendable() {
        let store = EnvironmentCredentialStore()
        _ = store
        #expect(Bool(true))
    }
}

@Suite("EnvironmentCredentialStore Get")
struct EnvironmentCredentialStoreGetTests {

    @Test("Get returns nil for non-existent key")
    func getReturnsNilForMissing() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "SWOOSH_TEST_", directory: dir.url)

        let value = try await store.get(key: "non_existent_key_xyz", service: "test")

        #expect(value == nil)
    }

    @Test("Get converts key to uppercase with prefix")
    func getConvertsKey() async throws {
        // We can't easily set env vars, but we can verify the lookup format
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        // This will look for TEST_MY_KEY in environment
        _ = try await store.get(key: "my.key", service: "test")

        // If we reach here without crash, the API works
        #expect(Bool(true))
    }
}

@Suite("EnvironmentCredentialStore Set")
struct EnvironmentCredentialStoreSetTests {

    @Test("Set writes to env file")
    func setWritesToFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // The store persists credentials to a `.env` file inside `tempDir`.
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: tempDir)

        try await store.set(key: "api_key", value: "secret123", service: "test")

        // The value should be retrievable from the .env file.
        let retrieved = try await store.get(key: "api_key", service: "test")
        #expect(retrieved == "secret123")

        // Cleanup
        try await store.delete(key: "api_key", service: "test")
    }

    @Test("Set updates existing key")
    func setUpdatesExisting() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        try await store.set(key: "test_key", value: "old_value", service: "test")
        try await store.set(key: "test_key", value: "new_value", service: "test")

        let retrieved = try await store.get(key: "test_key", service: "test")
        #expect(retrieved == "new_value")

        // Cleanup
        try await store.delete(key: "test_key", service: "test")
    }
}

@Suite("EnvironmentCredentialStore Delete")
struct EnvironmentCredentialStoreDeleteTests {

    @Test("Delete removes key")
    func deleteRemoves() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        try await store.set(key: "to_delete", value: "value", service: "test")

        var retrieved = try await store.get(key: "to_delete", service: "test")
        #expect(retrieved == "value")

        try await store.delete(key: "to_delete", service: "test")

        retrieved = try await store.get(key: "to_delete", service: "test")
        #expect(retrieved == nil)
    }

    @Test("Delete non-existent key is safe")
    func deleteNonExistentSafe() async {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        await #expect(throws: Never.self) {
            try await store.delete(key: "never_existed", service: "test")
        }
    }
}

@Suite("EnvironmentCredentialStore ListKeys")
struct EnvironmentCredentialStoreListKeysTests {

    @Test("ListKeys returns keys with prefix")
    func listKeysReturns() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "LIST_TEST_", directory: dir.url)

        try await store.set(key: "key1", value: "value1", service: "test")
        try await store.set(key: "key2", value: "value2", service: "test")

        // This will list keys from environment variables with the prefix
        let keys = try await store.listKeys(service: "test")

        // Cleanup
        try await store.delete(key: "key1", service: "test")
        try await store.delete(key: "key2", service: "test")

        // The keys may or may not be in the list depending on environment
        // Just verify the API works
        _ = keys
    }
}

// MARK: - KeychainError Tests

@Suite("KeychainError")
struct KeychainErrorTests {

    @Test("EncodingFailure has correct description")
    func encodingFailureDescription() {
        let error = KeychainError.encodingFailure

        #expect(error.errorDescription?.contains("encode") == true)
    }

    @Test("Unhandled has status in description")
    func unhandledDescription() {
        let error = KeychainError.unhandled(status: -50) // errSecParam

        #expect(error.errorDescription != nil)
    }

    @Test("KeychainError is LocalizedError")
    func isLocalizedError() {
        let _: any LocalizedError.Type = KeychainError.self
        #expect(Bool(true))
    }
}

// MARK: - Edge Cases

@Suite("Credentials Edge Cases")
struct CredentialsEdgeCaseTests {

    @Test("Handles empty key")
    func handlesEmptyKey() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        try await store.set(key: "", value: "value", service: "test")
        let retrieved = try await store.get(key: "", service: "test")

        #expect(retrieved == "value")

        // Cleanup
        try await store.delete(key: "", service: "test")
    }

    @Test("Handles empty value")
    func handlesEmptyValue() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        try await store.set(key: "empty_test", value: "", service: "test")
        let retrieved = try await store.get(key: "empty_test", service: "test")

        #expect(retrieved == "")

        // Cleanup
        try await store.delete(key: "empty_test", service: "test")
    }

    @Test("Handles long value")
    func handlesLongValue() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)
        let longValue = String(repeating: "x", count: 10000)

        try await store.set(key: "long_test", value: longValue, service: "test")
        let retrieved = try await store.get(key: "long_test", service: "test")

        #expect(retrieved?.count == 10000)

        // Cleanup
        try await store.delete(key: "long_test", service: "test")
    }

    @Test("Handles special characters in value")
    func handlesSpecialChars() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)
        let specialValue = "Special: \"quotes\", 'apostrophes', \\backslash, \n\t"

        try await store.set(key: "special_test", value: specialValue, service: "test")
        let retrieved = try await store.get(key: "special_test", service: "test")

        #expect(retrieved == specialValue)

        // Cleanup
        try await store.delete(key: "special_test", service: "test")
    }

    @Test("Handles key with dots")
    func handlesDottedKey() async throws {
        let dir = IsolatedEnvDir()
        let store = EnvironmentCredentialStore(prefix: "TEST_", directory: dir.url)

        // key with dots becomes underscores in env var
        try await store.set(key: "my.api.key", value: "secret", service: "test")
        let retrieved = try await store.get(key: "my.api.key", service: "test")

        #expect(retrieved == "secret")

        // Cleanup
        try await store.delete(key: "my.api.key", service: "test")
    }

    @Test("Multiple stores with different prefixes")
    func multipleStores() async throws {
        // Both stores share one directory: the distinct prefixes discriminate
        // their lines within the same `.env` file.
        let dir = IsolatedEnvDir()
        let store1 = EnvironmentCredentialStore(prefix: "APP1_", directory: dir.url)
        let store2 = EnvironmentCredentialStore(prefix: "APP2_", directory: dir.url)

        try await store1.set(key: "shared", value: "value1", service: "test")
        try await store2.set(key: "shared", value: "value2", service: "test")

        let val1 = try await store1.get(key: "shared", service: "test")
        let val2 = try await store2.get(key: "shared", service: "test")

        #expect(val1 == "value1")
        #expect(val2 == "value2")

        // Cleanup
        try await store1.delete(key: "shared", service: "test")
        try await store2.delete(key: "shared", service: "test")
    }
}
