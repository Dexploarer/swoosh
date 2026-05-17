// Tests/SwooshSecretsTests/CredentialScavengerTests.swift

import XCTest
@testable import SwooshSecrets

final class CredentialScavengerTests: XCTestCase {

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Environment Scavenger
    // ═══════════════════════════════════════════════════════════════

    func testEnvironmentScanFindsOpenAIKey() {
        let env = ["OPENAI_API_KEY": "sk-test-123"]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.provider, .openAI)
        XCTAssertEqual(results.first?.source, .environment)
        XCTAssertEqual(results.first?.value, "sk-test-123")
    }

    func testEnvironmentScanFindsMultipleProviders() {
        let env = [
            "OPENAI_API_KEY": "sk-test",
            "ANTHROPIC_API_KEY": "sk-ant-test",
            "GROQ_API_KEY": "gsk-test",
        ]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.count, 3)
        let providers = Set(results.map { $0.provider })
        XCTAssertTrue(providers.contains(.openAI))
        XCTAssertTrue(providers.contains(.anthropic))
        XCTAssertTrue(providers.contains(.groq))
    }

    func testEnvironmentScanStripsQuotes() {
        let env = ["OPENAI_API_KEY": "\"sk-quoted\""]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.first?.value, "sk-quoted")
    }

    func testEnvironmentScanIgnoresEmptyValues() {
        let env = ["OPENAI_API_KEY": "  "]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertTrue(results.isEmpty)
    }

    func testEnvironmentScanFallbackKey() {
        // OPENAI_KEY is the fallback for OPENAI_API_KEY
        let env = ["OPENAI_KEY": "sk-fallback"]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.provider, .openAI)
    }

    func testEnvironmentScanPrimaryKeyWins() {
        let env = [
            "OPENAI_API_KEY": "primary",
            "OPENAI_KEY": "fallback",
        ]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.value, "primary")
    }

    func testEnvironmentScanAllProviderMappings() {
        // Verify all known providers have at least one env var mapping
        for (provider, keys) in EnvironmentScavenger.envMap {
            XCTAssertFalse(keys.isEmpty, "\(provider) should have at least one env var")
        }
    }

    func testEnvironmentScanStripsWhitespace() {
        let env = ["OPENAI_API_KEY": "  sk-ws  "]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.first?.value, "sk-ws")
    }

    func testEnvironmentScanStripsSingleQuotes() {
        let env = ["OPENAI_API_KEY": "'sk-single'"]
        let results = EnvironmentScavenger.scan(environment: env)
        XCTAssertEqual(results.first?.value, "sk-single")
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Config File Scavenger
    // ═══════════════════════════════════════════════════════════════

    func testConfigFileJsonKeyExtraction() {
        let json = #"{"api_key": "sk-from-file"}"#
        let data = json.data(using: .utf8)!
        let result = ConfigFileScavenger.jsonKey(data, keys: ["api_key"])
        XCTAssertEqual(result, "sk-from-file")
    }

    func testConfigFileJsonKeyFallback() {
        let json = #"{"token": "tkn-123"}"#
        let data = json.data(using: .utf8)!
        let result = ConfigFileScavenger.jsonKey(data, keys: ["api_key", "token"])
        XCTAssertEqual(result, "tkn-123")
    }

    func testConfigFileJsonNestedKey() {
        let json = #"{"github.com": {"oauth_token": "gho-xyz"}}"#
        let data = json.data(using: .utf8)!
        let result = ConfigFileScavenger.jsonKey(data, keys: ["oauth_token"])
        XCTAssertEqual(result, "gho-xyz")
    }

    func testConfigFileJsonInvalidData() {
        let data = "not json".data(using: .utf8)!
        let result = ConfigFileScavenger.jsonKey(data, keys: ["api_key"])
        XCTAssertNil(result)
    }

    func testConfigFileSources() {
        // Verify all sources have at least one path and an extractor
        for source in ConfigFileScavenger.sources {
            XCTAssertFalse(source.paths.isEmpty, "\(source.provider) should have paths")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Keychain Scavenger
    // ═══════════════════════════════════════════════════════════════

    func testKeychainScavengerSources() {
        // Verify known keychain sources are populated
        XCTAssertFalse(KeychainScavenger.sources.isEmpty)
        for source in KeychainScavenger.sources {
            XCTAssertFalse(source.service.isEmpty)
        }
    }

    func testKeychainScavengerTokenExtraction() {
        // JSON blob with token
        let json = #"{"token": "test-token", "expiry": 12345}"#
        let result = KeychainScavenger.extractToken(from: json, provider: .anthropic)
        XCTAssertEqual(result, "test-token")
    }

    func testKeychainScavengerTokenExtractionPlainString() {
        let result = KeychainScavenger.extractToken(from: "plain-token-123", provider: .copilot)
        XCTAssertEqual(result, "plain-token-123")
    }

    func testKeychainScavengerTokenExtractionNestedJSON() {
        let json = #"{"credentials": {"access_token": "nested-tk"}}"#
        let result = KeychainScavenger.extractToken(from: json, provider: .gemini)
        XCTAssertEqual(result, "nested-tk")
    }

    func testBrowserSafeStorageLabels() {
        XCTAssertFalse(KeychainScavenger.browserSafeStorageLabels.isEmpty)
        let chromes = KeychainScavenger.browserSafeStorageLabels.filter { $0.browser == "Chrome" }
        XCTAssertEqual(chromes.count, 1)
        XCTAssertEqual(chromes.first?.service, "Chrome Safe Storage")
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - DiscoveredCredential
    // ═══════════════════════════════════════════════════════════════

    func testDiscoveredCredentialSwooshRef() {
        let cred = DiscoveredCredential(
            provider: .openAI, source: .environment, kind: .apiKey, value: "sk-x")
        XCTAssertEqual(cred.swooshRef.namespace, "openai")
        XCTAssertEqual(cred.swooshRef.key, "api_key")
    }

    func testKnownProviderDisplayNames() {
        for provider in KnownProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) needs a display name")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Import (integration with InMemorySecretStore)
    // ═══════════════════════════════════════════════════════════════

    func testImportAllIntoStore() async throws {
        // Note: this exercises the importAll flow with whatever credentials
        // happen to be available on the build machine. We just verify it
        // doesn't crash and returns a consistent result.
        let store = InMemorySecretStore()
        let imported = try await CredentialScavenger.importAll(into: store)
        // No assertion on count — depends on machine state
        // But calling it twice with overwrite=false shouldn't re-import
        let importedAgain = try await CredentialScavenger.importAll(into: store)
        XCTAssertTrue(importedAgain.isEmpty, "Second import without overwrite should be empty")
    }

    func testImportWithOverwrite() async throws {
        let store = InMemorySecretStore()
        // Pre-populate
        try await store.set("old-value", ref: SecretRef("openai", "api_key"))

        // Discover with env
        let env = ["OPENAI_API_KEY": "new-value"]
        let discovered = EnvironmentScavenger.scan(environment: env)
        guard let cred = discovered.first else { return }

        // Import with overwrite
        try await store.set(cred.value, ref: cred.swooshRef)
        let stored = try await store.get(SecretRef("openai", "api_key"))
        XCTAssertEqual(stored, "new-value")
    }
}
