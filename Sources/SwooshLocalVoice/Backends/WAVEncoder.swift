// SwooshLocalVoice/Backends/WAVEncoder.swift — 0.9R PCM → WAV helper
//
// Every backend returns WAV bytes so callers don't have to branch on
// format. This helper handles the two common input shapes:
//   - `[Float]` 24/22 kHz mono (Kokoro / OmniVoice native output)
//   - `[Data]` chunks of pre-encoded 16-bit PCM (Apple AVSpeechSynthesizer)
//
// Output: a single-chunk WAV blob (RIFF/WAVE/fmt /data) ready for
// `AVAudioPlayer(data:)`.

import Foundation

enum WAVEncoder {

    /// Encode 32-bit float mono PCM (range [-1, 1]) as a 16-bit WAV.
    /// Clipping samples outside [-1, 1] to avoid integer overflow.
    static func encodeFloat32Mono(_ samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            let scaled = Int16(clipped * Float(Int16.max))
            pcm.append(UInt8(truncatingIfNeeded: scaled))
            pcm.append(UInt8(truncatingIfNeeded: scaled >> 8))
        }
        return wrapPCM(pcm: pcm, sampleRate: UInt32(sampleRate), channels: 1, bitsPerSample: 16)
    }

    /// Wrap a raw 16-bit PCM `Data` blob (already in interleaved frames)
    /// in a single-chunk WAV header.
    static func wrapPCM(
        pcm: Data,
        sampleRate: UInt32,
        channels: UInt16,
        bitsPerSample: UInt16
    ) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(UInt32(chunkSize))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(UInt32(16))                  // fmt chunk size
        header.appendLE(UInt16(1))                   // audio format = PCM
        header.appendLE(channels)
        header.appendLE(sampleRate)
        header.appendLE(byteRate)
        header.appendLE(blockAlign)
        header.appendLE(bitsPerSample)
        header.append(contentsOf: "data".utf8)
        header.appendLE(dataSize)
        header.append(pcm)
        return header
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
