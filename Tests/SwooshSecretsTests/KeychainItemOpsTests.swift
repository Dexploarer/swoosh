// Tests/SwooshSecretsTests/KeychainItemOpsTests.swift
//
// Pins the shared SecItem helper. Each test uses a unique service
// string so parallel runs don't share Keychain state.

import Testing
import Foundation
@testable import SwooshSecrets

@Suite("KeychainItemOps")
struct KeychainItemOpsTests {

    private func uniqueService() -> String {
        "ai.swoosh.tests.\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func cleanup(service: String, accounts: [String]) {
        for account in accounts {
            try? KeychainItemOps.delete(service: service, account: account)
        }
    }

    @Test("set then get returns the same bytes")
    func setGetRoundTrip() throws {
        let service = uniqueService()
        let account = "alpha"
        defer { cleanup(service: service, accounts: [account]) }
        try KeychainItemOps.set(Data([0xCA, 0xFE]), service: service, account: account)
        let read = try KeychainItemOps.get(service: service, account: account)
        #expect(read == Data([0xCA, 0xFE]))
    }

    @Test("get returns nil for absent account")
    func getAbsentReturnsNil() throws {
        let service = uniqueService()
        let read = try KeychainItemOps.get(service: service, account: "missing")
        #expect(read == nil)
    }

    @Test("set overwrites an existing value")
    func setOverwrites() throws {
        let service = uniqueService()
        let account = "beta"
        defer { cleanup(service: service, accounts: [account]) }
        try KeychainItemOps.set(Data([0x01]), service: service, account: account)
        try KeychainItemOps.set(Data([0x02, 0x03]), service: service, account: account)
        #expect(try KeychainItemOps.get(service: service, account: account) == Data([0x02, 0x03]))
    }

    @Test("delete is idempotent for missing accounts")
    func deleteIdempotent() throws {
        let service = uniqueService()
        // No item present → treated as success.
        try KeychainItemOps.delete(service: service, account: "ghost")
    }

    @Test("exists tracks set + delete")
    func existsFlips() throws {
        let service = uniqueService()
        let account = "gamma"
        defer { cleanup(service: service, accounts: [account]) }
        #expect(!KeychainItemOps.exists(service: service, account: account))
        try KeychainItemOps.set(Data([0xFF]), service: service, account: account)
        #expect(KeychainItemOps.exists(service: service, account: account))
        try KeychainItemOps.delete(service: service, account: account)
        #expect(!KeychainItemOps.exists(service: service, account: account))
    }

    @Test("listAccounts returns every account written under the service")
    func listAccounts() throws {
        let service = uniqueService()
        defer { cleanup(service: service, accounts: ["one", "two", "three"]) }
        try KeychainItemOps.set(Data([0x01]), service: service, account: "one")
        try KeychainItemOps.set(Data([0x02]), service: service, account: "two")
        try KeychainItemOps.set(Data([0x03]), service: service, account: "three")
        let accounts = try KeychainItemOps.listAccounts(service: service)
        #expect(Set(accounts) == Set(["one", "two", "three"]))
    }
}
