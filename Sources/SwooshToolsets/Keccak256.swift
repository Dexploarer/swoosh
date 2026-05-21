// SwooshToolsets/Keccak256.swift — Pure-Swift Keccak-256 — 0.9R
//
// Extracted so both UniswapTools (CREATE2 pool address derivation) and
// EVMABI (function-selector computation) share one implementation.
// No external crypto dependency.

import Foundation

enum Keccak256: Sendable {
    /// Keccak-256 digest (32 bytes) of the given input bytes.
    static func hash(_ input: [UInt8]) -> [UInt8] {
        let rate = 136
        var state = [UInt64](repeating: 0, count: 25)
        var offset = 0

        while input.count - offset >= rate {
            absorb(Array(input[offset..<(offset + rate)]), into: &state)
            permute(&state)
            offset += rate
        }

        var block = Array(repeating: UInt8(0), count: rate)
        let remaining = input.count - offset
        if remaining > 0 {
            for i in 0..<remaining {
                block[i] = input[offset + i]
            }
        }
        block[remaining] ^= 0x01
        block[rate - 1] ^= 0x80
        absorb(block, into: &state)
        permute(&state)

        var output: [UInt8] = []
        output.reserveCapacity(32)
        for lane in state.prefix(4) {
            for shift in stride(from: 0, to: 64, by: 8) {
                output.append(UInt8((lane >> UInt64(shift)) & 0xff))
            }
        }
        return Array(output.prefix(32))
    }

    private static func absorb(_ block: [UInt8], into state: inout [UInt64]) {
        for laneIndex in 0..<(block.count / 8) {
            var lane = UInt64(0)
            for byteIndex in 0..<8 {
                lane |= UInt64(block[laneIndex * 8 + byteIndex]) << UInt64(byteIndex * 8)
            }
            state[laneIndex] ^= lane
        }
    }

    private static func permute(_ state: inout [UInt64]) {
        let roundConstants: [UInt64] = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
            0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
            0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
            0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
            0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
            0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
            0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
            0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
        ]
        let rotations = [
            0, 1, 62, 28, 27,
            36, 44, 6, 55, 20,
            3, 10, 43, 25, 39,
            41, 45, 15, 21, 8,
            18, 2, 61, 56, 14,
        ]

        for roundConstant in roundConstants {
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }

            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], by: 1)
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + 5 * y] ^= d[x]
                }
            }

            var b = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(state[x + 5 * y], by: rotations[x + 5 * y])
                }
            }

            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + 5 * y] = b[x + 5 * y] ^ ((~b[((x + 1) % 5) + 5 * y]) & b[((x + 2) % 5) + 5 * y])
                }
            }

            state[0] ^= roundConstant
        }
    }

    private static func rotl(_ value: UInt64, by offset: Int) -> UInt64 {
        guard offset != 0 else { return value }
        return (value << UInt64(offset)) | (value >> UInt64(64 - offset))
    }
}
