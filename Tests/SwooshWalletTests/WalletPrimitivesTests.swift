// SwooshWalletTests/WalletPrimitivesTests.swift — Codec and key derivation
//
// Pin the deterministic wallet primitives against well-known vectors so we
// catch silent regressions in base58, EIP-55 checksum, or EVM address
// derivation. Pure round-trips for Solana keys, no signing — those land in
// follow-up tests.

import Testing
import Foundation
import SwooshWallet

@Suite("Wallet primitives")
struct WalletPrimitivesTests {
    @Test("Base58 round-trips a known vector")
    func base58RoundTrip() {
        let text = "Hello World!"
        let bytes = Array(text.utf8)
        let encoded = Base58.encode(bytes)
        #expect(encoded == "2NEpo7TZRRrLZSi2U")
        #expect(Base58.decode(encoded) == bytes)
    }

    @Test("Base58 preserves leading zeros as '1' chars")
    func base58LeadingZeros() {
        let bytes: [UInt8] = [0x00, 0x00, 0x01]
        let encoded = Base58.encode(bytes)
        #expect(encoded == "112")
        #expect(Base58.decode(encoded) == bytes)
    }

    @Test("Hex round-trips with and without 0x prefix")
    func hexRoundTrip() {
        let bytes: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        #expect(Hex.encode(bytes) == "0xdeadbeef")
        #expect(Hex.encode(bytes, prefix: false) == "deadbeef")
        #expect(Hex.decode("0xDEADBEEF") == bytes)
        #expect(Hex.decode("deadbeef") == bytes)
    }

    @Test("EVM keypair derives the canonical address for private scalar 1")
    func evmAddressForScalarOne() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[31] = 0x01
        let pair = try WalletKeyFactory.load(chain: .ethereum, secret: Data(bytes))
        // Canonical EVM address for private key = 1 (see e.g. ethereumbook).
        #expect(pair.address == "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf")
    }

    @Test("EVM keypair derives Vitalik's example address (EIP-155 vector)")
    func evmAddressForKnownVector() throws {
        let secret = Hex.decode("0x4646464646464646464646464646464646464646464646464646464646464646")
        let pair = try WalletKeyFactory.load(chain: .ethereum, secret: Data(secret ?? []))
        #expect(pair.address == "0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F")
    }

    @Test("Solana keypair round-trips through a known seed")
    func solanaRoundTrip() throws {
        let seed = Data(repeating: 0x42, count: 32)
        let pair = try WalletKeyFactory.load(chain: .solana, secret: seed)
        #expect(pair.address.count >= 32)
        // Base58-encoded ed25519 pubkey is always 32–44 chars long.
        #expect(pair.publicKey.count == 32)
        // Re-loading with the canonical 64-byte secret (priv ‖ pub) must match.
        let reloaded = try WalletKeyFactory.load(chain: .solana, secret: pair.secret)
        #expect(reloaded.address == pair.address)
        #expect(reloaded.publicKey == pair.publicKey)
    }

    @Test("Chain metadata covers all four supported chains")
    func chainMetadata() {
        #expect(WalletChain.allCases.count == 4)
        #expect(WalletChain.ethereum.isEVM)
        #expect(WalletChain.base.isEVM)
        #expect(WalletChain.bnb.isEVM)
        #expect(!WalletChain.solana.isEVM)
        #expect(WalletChain.solana.nativeDecimals == 9)
        #expect(WalletChain.ethereum.nativeDecimals == 18)
        #expect(WalletChain.bnb.evmChainID == 56)
        #expect(WalletChain.base.evmChainID == 8453)
    }
}
