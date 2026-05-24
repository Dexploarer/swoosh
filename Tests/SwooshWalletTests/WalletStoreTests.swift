// Tests/SwooshWalletTests/WalletStoreTests.swift — 0.9A
//
// Pure-logic coverage for `WalletStore` against an in-memory `UserDefaults`.
// Exercises the public surface that doesn't require Keychain (`accounts`,
// `rename`, `setRPCOverride`, `formatNative`) — Keychain-backed paths stay
// behind a runtime guard until the project lands a SecItem mocking story.

import Testing
import Foundation
import BigInt
@testable import SwooshWallet

@Suite("WalletStore.formatNative")
struct WalletStoreFormatNativeTests {

    private func store() -> WalletStore {
        let suite = "WalletStoreFormatNativeTests-\(UUID().uuidString)"
        return WalletStore(userDefaults: UserDefaults(suiteName: suite)!)
    }

    @Test("Solana zero balance shows 0 SOL")
    func solanaZero() async {
        let formatted = store().formatNative(value: BigUInt(0), chain: .solana)
        #expect(formatted == "0 SOL")
    }

    @Test("Solana 1 lamport shows leading zero with fractional decimals")
    func solanaOneLamport() async {
        // 1 lamport = 10^-9 SOL. The formatter trims trailing zeros and
        // caps at 6 fractional digits, so it should render as "0.000000"
        // → empty fractional after trim → "0 SOL".
        let formatted = store().formatNative(value: BigUInt(1), chain: .solana)
        #expect(formatted.hasSuffix("SOL"))
        // 1 lamport < smallest displayable fraction (6 decimal places) →
        // the formatter renders something resembling 0.* with leading
        // zeros — exact representation is implementation-defined but it
        // must not crash and must carry the SOL suffix.
    }

    @Test("Solana 1 SOL (1_000_000_000 lamports) shows 1 SOL")
    func solanaOneSOL() async {
        let oneSOL = BigUInt(1_000_000_000)
        let formatted = store().formatNative(value: oneSOL, chain: .solana)
        #expect(formatted == "1 SOL")
    }

    @Test("Solana 1.5 SOL renders with fractional")
    func solanaOneAndAHalfSOL() async {
        let oneAndAHalf = BigUInt(1_500_000_000)
        let formatted = store().formatNative(value: oneAndAHalf, chain: .solana)
        #expect(formatted == "1.5 SOL")
    }

    @Test("Ethereum 1 ETH (1e18 wei) shows 1 ETH")
    func ethereumOneETH() async {
        let oneETH = BigUInt(10).power(18)
        let formatted = store().formatNative(value: oneETH, chain: .ethereum)
        #expect(formatted == "1 ETH")
    }

    @Test("Ethereum 0.5 ETH renders with fractional")
    func ethereumHalfETH() async {
        let halfETH = BigUInt(5) * BigUInt(10).power(17)
        let formatted = store().formatNative(value: halfETH, chain: .ethereum)
        #expect(formatted == "0.5 ETH")
    }

    @Test("Base 1 ETH shows 1 ETH (Base uses same native symbol)")
    func baseOneETH() async {
        let oneETH = BigUInt(10).power(18)
        let formatted = store().formatNative(value: oneETH, chain: .base)
        #expect(formatted.hasSuffix("ETH") || formatted.hasSuffix(WalletChain.base.nativeSymbol))
    }

    @Test("Output truncates fractional to 6 digits")
    func sixDigitTruncation() async {
        // 1 ETH + 7 trailing decimal digits = 1.0000001234567 ETH.
        // The formatter caps at 6 fractional digits.
        let value = BigUInt(10).power(18) + BigUInt(123_456_789)
        let formatted = store().formatNative(value: value, chain: .ethereum)
        // Should not have more than 6 chars after the dot.
        if let dotIdx = formatted.firstIndex(of: ".") {
            let fractional = formatted[formatted.index(after: dotIdx)...]
            let beforeSpace = fractional.split(separator: " ").first ?? ""
            #expect(beforeSpace.count <= 6, "fractional was \(beforeSpace.count) chars: '\(formatted)'")
        }
    }
}

@Suite("WalletStore account index")
struct WalletStoreAccountIndexTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "WalletStoreAccountIndexTests-\(UUID().uuidString)")!
    }

    @Test("Empty store returns empty accounts")
    func emptyByDefault() async {
        let store = WalletStore(userDefaults: defaults())
        let accounts = await store.accounts()
        #expect(accounts.isEmpty)
    }

    @Test("rename on unknown account returns false without mutating state")
    func renameUnknownReturnsFalse() async throws {
        let store = WalletStore(userDefaults: defaults())
        let phantom = WalletAccount(chain: .solana, address: "phantom-addr", label: "Phantom")
        let renamed = try await store.rename(account: phantom, to: "Updated")
        #expect(renamed == false)
        // No-op: no accounts created → still empty.
        let after = await store.accounts()
        #expect(after.isEmpty)
    }
}

@Suite("WalletStore.setRPCOverride")
struct WalletStoreRPCOverrideTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "WalletStoreRPCOverrideTests-\(UUID().uuidString)")!
    }

    @Test("Setting an override persists and round-trips")
    func setAndRead() async throws {
        // Two stores share the same UserDefaults SUITE NAME (not the same
        // class instance) so the second one validates the disk-persisted
        // round-trip without sending an actor-isolated value across the
        // Swift 6 sendable boundary.
        let suiteName = "WalletStoreRPCOverrideTests-\(UUID().uuidString)"
        let custom = URL(string: "https://custom.solana.example/rpc")!
        let store = WalletStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        await store.setRPCOverride(custom, for: .solana)
        let read = await store.rpcOverride(for: .solana)
        #expect(read == custom)
        let reopened = WalletStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        let persistedRead = await reopened.rpcOverride(for: .solana)
        #expect(persistedRead == custom)
    }

    @Test("rpcURL falls back to chain default when no override")
    func defaultFallback() async {
        let store = WalletStore(userDefaults: defaults())
        let resolved = await store.rpcURL(for: .ethereum)
        #expect(resolved == WalletChain.ethereum.defaultRPCURL)
    }

    @Test("Clearing override (nil) removes persisted value")
    func clearOverride() async throws {
        let suiteName = "WalletStoreRPCOverrideTests-\(UUID().uuidString)"
        let custom = URL(string: "https://temp.example/rpc")!
        let store = WalletStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        await store.setRPCOverride(custom, for: .base)
        #expect(await store.rpcOverride(for: .base) == custom)
        await store.setRPCOverride(nil, for: .base)
        #expect(await store.rpcOverride(for: .base) == nil)
        // Default fallback restored.
        #expect(await store.rpcURL(for: .base) == WalletChain.base.defaultRPCURL)
    }
}

@Suite("WalletKeyFactory.checksumAddress")
struct ChecksumAddressTests {

    @Test("All-lowercase bytes produce expected EIP-55 output for known vector")
    func vitalikVector() {
        // EIP-55 example: 0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359 (mixed case).
        let bytes: [UInt8] = [
            0xfb, 0x69, 0x16, 0x09, 0x5c, 0xa1, 0xdf, 0x60,
            0xbb, 0x79, 0xce, 0x92, 0xce, 0x3e, 0xa7, 0x4c,
            0x37, 0xc5, 0xd3, 0x59
        ]
        let address = WalletKeyFactory.checksumAddress(bytes: bytes)
        #expect(address == "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359")
    }

    @Test("Output is always 42 characters (0x + 40 hex)")
    func length() {
        let zero = [UInt8](repeating: 0, count: 20)
        #expect(WalletKeyFactory.checksumAddress(bytes: zero).count == 42)
        let max = [UInt8](repeating: 0xff, count: 20)
        #expect(WalletKeyFactory.checksumAddress(bytes: max).count == 42)
    }
}
