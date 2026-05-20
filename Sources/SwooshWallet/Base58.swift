// SwooshWallet/Base58.swift — Bitcoin/Solana base58 codec (no checksum)
//
// Solana addresses are bare base58 of the 32-byte ed25519 public key.
// This is the same alphabet Bitcoin uses; we deliberately omit the b58check
// envelope since Solana doesn't use it. Implementation is the standard
// repeated-division-by-58 with leading-zero-byte preservation as '1' chars.

import Foundation

public enum Base58 {
    public static let alphabet: [UInt8] = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8
    )

    public static func encode(_ bytes: [UInt8]) -> String {
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 { leadingZeros += 1 } else { break }
        }

        var digits = [UInt8]()
        digits.reserveCapacity(bytes.count * 138 / 100 + 1)

        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        var output = [UInt8](repeating: alphabet[0], count: leadingZeros)
        for digit in digits.reversed() {
            output.append(alphabet[Int(digit)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    public static func decode(_ string: String) -> [UInt8]? {
        var indexes = [UInt8: Int]()
        for (i, c) in alphabet.enumerated() { indexes[c] = i }

        let bytes = Array(string.utf8)
        var leadingOnes = 0
        for b in bytes {
            if b == alphabet[0] { leadingOnes += 1 } else { break }
        }

        var digits = [UInt8]()
        for b in bytes {
            guard let value = indexes[b] else { return nil }
            var carry = value
            for i in 0..<digits.count {
                carry += Int(digits[i]) * 58
                digits[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                digits.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }

        var output = [UInt8](repeating: 0, count: leadingOnes)
        output.append(contentsOf: digits.reversed())
        return output
    }
}
