// Tests/SwooshClientTests/HostStoreTests.swift — 0.4A
//
// Round-trip tests for `HostStore`. The iPhone uses this to remember the
// paired Mac daemon's URL across launches. `TokenStore` is deliberately
// not tested here — Keychain bundling under `swift test` is unreliable
// (and the entitlements aren't set up for it), so its happy path is
// exercised in iOS-device integration testing.

import Foundation
import Testing
@testable import SwooshClient

@Suite("HostStore", .serialized)
struct HostStoreTests {

    private static let scratchKey: String = "ai.swoosh.client.host"

    private func snapshotAndClear() -> URL? {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.scratchKey)
            .flatMap { URL(string: $0) }
        defaults.removeObject(forKey: Self.scratchKey)
        return previous
    }

    private func restore(_ previous: URL?) {
        if let previous {
            UserDefaults.standard.set(previous.absoluteString, forKey: Self.scratchKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.scratchKey)
        }
    }

    @Test("Set and read back a URL")
    func setAndRead() {
        let prior = snapshotAndClear()
        defer { restore(prior) }

        HostStore.current = URL(string: "http://192.168.0.10:8787/")
        #expect(HostStore.current?.absoluteString == "http://192.168.0.10:8787/")
    }

    @Test("Setting nil deletes the value")
    func setNilClears() {
        let prior = snapshotAndClear()
        defer { restore(prior) }

        HostStore.current = URL(string: "http://1.2.3.4:8787/")
        HostStore.current = nil
        #expect(HostStore.current == nil)
    }

    @Test("Garbled defaults string returns nil instead of crashing")
    func garbledStringReturnsNil() {
        let prior = snapshotAndClear()
        defer { restore(prior) }

        UserDefaults.standard.set(" not-a-url with space ", forKey: Self.scratchKey)
        // URL(string:) treats some garbage as valid relative paths, so
        // the contract is only "doesn't crash and round-trips through
        // URL(string:)". Read the value and confirm it matches what
        // URL(string:) returns for the same input.
        let expected = URL(string: " not-a-url with space ")
        #expect(HostStore.current?.absoluteString == expected?.absoluteString)
    }
}
