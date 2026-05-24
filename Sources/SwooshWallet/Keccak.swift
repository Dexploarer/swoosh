// SwooshWallet/Keccak.swift — Keccak256 wrapper around CryptoSwift — 0.9A
//
// EVM addresses are last 20 bytes of keccak256(uncompressed pubkey without
// the 0x04 prefix). Tiny wrapper so callers don't need to import CryptoSwift.

import Foundation
import CryptoSwift

public enum Keccak {
    public static func hash256(_ bytes: [UInt8]) -> [UInt8] {
        SHA3(variant: .keccak256).calculate(for: bytes)
    }
}
