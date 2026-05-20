// SwooshTools/EVMTypes+BigInt.swift
// EVM quantity types backed by BigInt for arbitrary-precision arithmetic.
// Replaces the previous EVMQuantity string local diagnostic.

import Foundation
import BigInt

// MARK: - EVM Quantity (backed by BigInt)

/// Arbitrary-precision EVM quantity (wei, gwei, etc.)
public struct EVMQuantity: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: BigInt

    public init(_ value: BigInt) { self.value = value }
    public init(_ value: Int) { self.value = BigInt(value) }
    public init(_ value: UInt64) { self.value = BigInt(value) }

    /// Hex string (0x-prefixed), the canonical EVM encoding
    public init(_ hex: String) {
        let h = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        self.value = BigInt(h, radix: 16) ?? BigInt(0)
    }

    public var hexString: String { "0x" + String(value, radix: 16) }
    /// Compatibility alias — prefer hexString in new code
    public var hex: String { hexString }
    public var description: String { value.description }

    /// Convert to ETH from wei
    public var asETH: Double { Double(value) / 1e18 }
    /// Convert to gwei from wei
    public var asGwei: Double { Double(value) / 1e9 }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        self = EVMQuantity(s)
    }

    // Arithmetic helpers
    public static func + (lhs: EVMQuantity, rhs: EVMQuantity) -> EVMQuantity { EVMQuantity(lhs.value + rhs.value) }
    public static func - (lhs: EVMQuantity, rhs: EVMQuantity) -> EVMQuantity { EVMQuantity(lhs.value - rhs.value) }
    public static func * (lhs: EVMQuantity, rhs: EVMQuantity) -> EVMQuantity { EVMQuantity(lhs.value * rhs.value) }
    public static func < (lhs: EVMQuantity, rhs: EVMQuantity) -> Bool { lhs.value < rhs.value }
}

extension EVMQuantity: Comparable {}

// MARK: - Lamports (backed by BigInt for overflow safety)

/// Solana lamport quantity, backed by BigInt
public struct Lamports: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: BigInt

    public init(_ value: BigInt) { self.value = value }
    public init(_ value: UInt64) { self.value = BigInt(value) }
    public init(_ value: Int) { self.value = BigInt(value) }

    /// SOL from lamports
    public var asSOL: Double { Double(value) / 1_000_000_000.0 }
    public var description: String { value.description }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value.description)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        self.value = BigInt(s) ?? BigInt(0)
    }

    public static func + (lhs: Lamports, rhs: Lamports) -> Lamports { Lamports(lhs.value + rhs.value) }
    public static func < (lhs: Lamports, rhs: Lamports) -> Bool { lhs.value < rhs.value }
}

extension Lamports: Comparable {}
