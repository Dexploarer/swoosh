// SwooshWallet/Hex.swift — Hex encoding helpers — 0.9A
//
// EVM addresses and signatures are hex with a 0x prefix. RPC responses
// return quantities and storage data as hex-prefixed strings too. These
// helpers keep the wallet free of a generic hex SPM dep.

import Foundation

public enum Hex {
    public static func encode(_ bytes: [UInt8], prefix: Bool = true) -> String {
        var out = prefix ? "0x" : ""
        out.reserveCapacity(out.count + bytes.count * 2)
        for byte in bytes {
            out.append(hexChar(byte >> 4))
            out.append(hexChar(byte & 0x0F))
        }
        return out
    }

    public static func decode(_ string: String) -> [UInt8]? {
        var s = Substring(string)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        if s.count % 2 == 1 { s = "0" + s }
        var out = [UInt8]()
        out.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            let chunk = String(s[index..<next])
            guard let byte = UInt8(chunk, radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    @inline(__always)
    private static func hexChar(_ nibble: UInt8) -> Character {
        Character(UnicodeScalar(nibble < 10 ? nibble + 0x30 : nibble + 0x57))
    }
}
