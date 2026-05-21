// SwooshToolsets/EVMABI.swift — Minimal EVM ABI encoding/decoding helpers — 0.9R
//
// Shared, dependency-light helpers used by the EVM toolset and the
// concrete EVM RPC client. No external ABI library — just the static
// function selectors and 32-byte word packing the ERC-20 / common
// read paths need.
//
// Hard rule: no private-key material flows through these helpers.

import Foundation
import SwooshTools
import BigInt

enum EVMABI {
    // ── Known ERC-20 function selectors (first 4 bytes of keccak256 of
    //    the canonical signature). These are fixed protocol constants. ──
    /// `balanceOf(address)`
    static let selectorBalanceOf = "70a08231"
    /// `allowance(address,address)`
    static let selectorAllowance = "dd62ed3e"
    /// `transfer(address,uint256)`
    static let selectorTransfer = "a9059cbb"
    /// `approve(address,uint256)`
    static let selectorApprove = "095ea7b3"
    /// `decimals()`
    static let selectorDecimals = "313ce567"

    /// Left-pad a hex string (no 0x) to a 32-byte (64-hex-char) word.
    static func word(_ hex: String) -> String {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let lowered = clean.lowercased()
        guard lowered.count <= 64 else { return String(lowered.suffix(64)) }
        return String(repeating: "0", count: 64 - lowered.count) + lowered
    }

    /// Encode an EVM address into a 32-byte word (right-aligned).
    static func addressWord(_ address: EVMAddress) -> String {
        word(address.hex)
    }

    /// Encode an arbitrary-precision unsigned integer into a 32-byte word.
    static func uintWord(_ value: BigInt) -> String {
        word(String(value, radix: 16))
    }

    // ── ERC-20 calldata builders ──────────────────────────────────────

    /// `transfer(address to, uint256 amount)` calldata (0x-prefixed).
    static func encodeTransfer(to: EVMAddress, amount: BigInt) -> EVMHexData {
        EVMHexData("0x" + selectorTransfer + addressWord(to) + uintWord(amount))
    }

    /// `approve(address spender, uint256 amount)` calldata (0x-prefixed).
    static func encodeApprove(spender: EVMAddress, amount: BigInt) -> EVMHexData {
        EVMHexData("0x" + selectorApprove + addressWord(spender) + uintWord(amount))
    }

    /// `balanceOf(address owner)` calldata (0x-prefixed).
    static func encodeBalanceOf(owner: EVMAddress) -> EVMHexData {
        EVMHexData("0x" + selectorBalanceOf + addressWord(owner))
    }

    /// `allowance(address owner, address spender)` calldata (0x-prefixed).
    static func encodeAllowance(owner: EVMAddress, spender: EVMAddress) -> EVMHexData {
        EVMHexData("0x" + selectorAllowance + addressWord(owner) + addressWord(spender))
    }

    /// `decimals()` calldata (0x-prefixed).
    static func encodeDecimals() -> EVMHexData {
        EVMHexData("0x" + selectorDecimals)
    }

    // ── Result decoding ───────────────────────────────────────────────

    /// Decode a single uint256 ABI return value into a BigInt.
    /// Returns 0 for empty / `0x` results.
    static func decodeUint(_ data: EVMHexData) -> BigInt {
        let clean = data.hex.hasPrefix("0x") ? String(data.hex.dropFirst(2)) : data.hex
        guard !clean.isEmpty else { return BigInt(0) }
        // Read the first 32-byte word.
        let firstWord = String(clean.prefix(64))
        return BigInt(firstWord, radix: 16) ?? BigInt(0)
    }

    /// Decode the nth (0-based) 32-byte word as a BigInt.
    static func decodeWord(_ data: EVMHexData, index: Int) -> BigInt {
        let clean = data.hex.hasPrefix("0x") ? String(data.hex.dropFirst(2)) : data.hex
        let start = index * 64
        guard start + 64 <= clean.count else { return BigInt(0) }
        let lower = clean.index(clean.startIndex, offsetBy: start)
        let upper = clean.index(lower, offsetBy: 64)
        return BigInt(String(clean[lower..<upper]), radix: 16) ?? BigInt(0)
    }

    // ── Generic typed argument encoding (for evm.abi_encode_call) ──────

    /// Encode a single positional argument of the given Solidity type.
    /// Supports `address`, `bool`, `uint*`, `int*` (head only — no
    /// dynamic types). Throws `ToolError.invalidInput` on anything else
    /// so the tool never returns silently-wrong calldata.
    static func encodeArgument(type: String, value: String) throws -> String {
        let t = type.trimmingCharacters(in: .whitespaces).lowercased()
        let v = value.trimmingCharacters(in: .whitespaces)
        if t == "address" {
            let clean = v.hasPrefix("0x") ? String(v.dropFirst(2)) : v
            guard clean.count == 40, clean.allSatisfy({ $0.isHexDigit }) else {
                throw ToolError.invalidInput("Invalid address argument '\(value)'")
            }
            return word(clean)
        }
        if t == "bool" {
            let isTrue = (v.lowercased() == "true" || v == "1")
            return word(isTrue ? "1" : "0")
        }
        if t.hasPrefix("uint") || t.hasPrefix("int") {
            // Parse the bit width — "int" / "uint" default to 256.
            let isSigned = t.hasPrefix("int")
            let widthStr = String(t.dropFirst(isSigned ? 3 : 4))
            let width = widthStr.isEmpty ? 256 : (Int(widthStr) ?? 256)
            // Accept decimal or 0x-hex.
            let parsed: BigInt?
            if v.hasPrefix("0x") {
                parsed = BigInt(String(v.dropFirst(2)), radix: 16)
            } else {
                parsed = BigInt(v)
            }
            guard var big = parsed else {
                throw ToolError.invalidInput("Invalid \(t) argument '\(value)'")
            }
            if !isSigned {
                guard big >= 0 else {
                    throw ToolError.invalidInput("uint cannot be negative: '\(value)'")
                }
            } else if big < 0 {
                // Solidity signed integers use two's complement — add 2^width
                // to map negatives into the unsigned word representation.
                big += BigInt(1) << width
            }
            return uintWord(big)
        }
        throw ToolError.invalidInput(
            "evm.abi_encode_call does not support Solidity type '\(type)' yet — supported: address, bool, uint*, int*")
    }

    /// Decode the nth (0-based) 32-byte word of an ABI result into a
    /// human-readable string of the given Solidity type. Supports only
    /// static head types (`address`, `bool`, `uint*`, `int*`). Throws
    /// `ToolError.invalidInput` for unsupported types so the tool never
    /// emits a silently-wrong value.
    static func decodeArgument(type: String, data: EVMHexData, index: Int) throws -> String {
        let t = type.trimmingCharacters(in: .whitespaces).lowercased()
        let clean = data.hex.hasPrefix("0x") ? String(data.hex.dropFirst(2)) : data.hex
        let start = index * 64
        guard start + 64 <= clean.count else {
            throw ToolError.invalidInput("ABI result is shorter than \(index + 1) word(s)")
        }
        let lower = clean.index(clean.startIndex, offsetBy: start)
        let upper = clean.index(lower, offsetBy: 64)
        let wordHex = String(clean[lower..<upper])
        if t == "address" {
            return "0x" + String(wordHex.suffix(40))
        }
        if t == "bool" {
            let value = BigInt(wordHex, radix: 16) ?? BigInt(0)
            return value == 0 ? "false" : "true"
        }
        if t.hasPrefix("uint") {
            return (BigInt(wordHex, radix: 16) ?? BigInt(0)).description
        }
        if t.hasPrefix("int") {
            // Two's complement over 256 bits.
            let raw = BigInt(wordHex, radix: 16) ?? BigInt(0)
            let signBit = BigInt(1) << 255
            if raw >= signBit {
                return (raw - (BigInt(1) << 256)).description
            }
            return raw.description
        }
        throw ToolError.invalidInput(
            "evm.abi_decode_result does not support Solidity type '\(type)' yet — supported: address, bool, uint*, int*")
    }

    /// Compute the 4-byte function selector for a canonical signature
    /// such as `transfer(address,uint256)`.
    static func functionSelector(_ signature: String) -> String {
        let normalized = signature
            .replacingOccurrences(of: " ", with: "")
        let hash = Keccak256.hash(Array(normalized.utf8))
        return hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
