// Tests/SwooshSecretsTests/KeychainAPIKeyProviderTests.swift
//
// Pins the closure-factory + read/write/delete cycle for
// `KeychainAPIKeyProvider`. Each test uses a unique provider id so
// parallel runs don't share Keychain state.

import Testing
import Foundation
@testable import SwooshSecrets

@Suite("KeychainAPIKeyProvider")
struct KeychainAPIKeyProviderTests {

    private func uniqueProviderID() -> String {
        "test-\(UUID().uuidString.prefix(8).lowercased())"
    }

    @Test("Service constant matches SwooshKit convention")
    func serviceConstant() {
        #expect(KeychainAPIKeyProvider.service == "ai.swoosh.secrets")
    }

    @Test("Write then read returns the same value")
    func writeReadRoundTrip() async throws {
        let id = uniqueProviderID()
        defer { KeychainAPIKeyProvider.delete(providerID: id) }
        #expect(KeychainAPIKeyProvider.write(providerID: id, value: "sk-roundtrip"))
        let value = try await KeychainAPIKeyProvider.read(providerID: id)
        #expect(value == "sk-roundtrip")
    }

    @Test("for(_:) returns a closure that reads on every call")
    func closureFactoryReadsHot() async throws {
        let id = uniqueProviderID()
        defer { KeychainAPIKeyProvider.delete(providerID: id) }
        KeychainAPIKeyProvider.write(providerID: id, value: "first")
        let provider = KeychainAPIKeyProvider.for(id)
        #expect(try await provider() == "first")
        KeychainAPIKeyProvider.write(providerID: id, value: "rotated")
        #expect(try await provider() == "rotated")
    }

    @Test("read throws MissingAPIKey for absent provider")
    func readMissingThrows() async {
        let id = uniqueProviderID()
        // No write — should throw immediately.
        do {
            _ = try await KeychainAPIKeyProvider.read(providerID: id)
            Issue.record("expected MissingAPIKey")
        } catch let error as MissingAPIKey {
            #expect(error.providerID == id)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("delete is idempotent")
    func deleteIdempotent() {
        let id = uniqueProviderID()
        // Delete with nothing present should not throw.
        KeychainAPIKeyProvider.delete(providerID: id)
        KeychainAPIKeyProvider.delete(providerID: id)
        #expect(!KeychainAPIKeyProvider.isConfigured(providerID: id))
    }

    @Test("isConfigured tracks write+delete cycle")
    func isConfiguredFlips() {
        let id = uniqueProviderID()
        defer { KeychainAPIKeyProvider.delete(providerID: id) }
        #expect(!KeychainAPIKeyProvider.isConfigured(providerID: id))
        KeychainAPIKeyProvider.write(providerID: id, value: "x")
        #expect(KeychainAPIKeyProvider.isConfigured(providerID: id))
        KeychainAPIKeyProvider.delete(providerID: id)
        #expect(!KeychainAPIKeyProvider.isConfigured(providerID: id))
    }
}
