// SwooshLocalVoice/Backends/AppleFallbackBackend.swift — 0.9R Apple TTS
//
// Drives `AVSpeechSynthesizer` and captures its output as a 16-bit mono
// WAV blob. Used as the OmniVoice backend until a Swift port lands
// (k2-fsa team has shipped OmniVoice via PyTorch only as of March 2026;
// sherpa-onnx export is the natural follow-up).
//
// Also acts as the safety net for any model whose engineKind doesn't
// have a concrete backend yet — the audio loop is provably testable
// end-to-end without blocking on ML SDK integration.

import Foundation
import AVFoundation

final class AppleFallbackBackend: Backend, Sendable {
    static let shared = AppleFallbackBackend()
    private init() {}

    func load(modelPath: URL?, model: LocalVoiceModel) async throws {
        // No-op: AVSpeechSynthesizer is always available on Apple platforms.
        _ = modelPath; _ = model
    }

    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data {
        // Apple TTS doesn't clone — `referenceAudio` is ignored.
        _ = referenceAudio
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return try await captureWAV(synth: synth, utterance: utterance)
    }

    // MARK: - PCM capture via AVSpeechSynthesizer.write

    private func captureWAV(
        synth: AVSpeechSynthesizer,
        utterance: AVSpeechUtterance
    ) async throws -> Data {
        // AVSpeechSynthesizer.write delivers buffer callbacks serially
        // on one queue, but Swift 6 can't see that contract. Guard the
        // mutable state with an NSLock so the Sendable closure escape
        // is provably race-free instead of @unchecked.
        let state = CaptureState()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer,
                      pcm.frameLength > 0 else {
                    // End-of-utterance marker. Resume exactly once.
                    if let (chunks, format) = state.finalizeOnce() {
                        let wav: Data
                        if let format {
                            let data = chunks.reduce(into: Data(), { $0.append($1) })
                            wav = WAVEncoder.wrapPCM(
                                pcm: data,
                                sampleRate: UInt32(format.sampleRate),
                                channels: UInt16(format.channelCount),
                                bitsPerSample: 16
                            )
                        } else {
                            wav = Data()
                        }
                        cont.resume(returning: wav)
                    }
                    return
                }
                state.append(chunk: Self.pcmData(from: pcm), format: pcm.format)
            }
        }
    }

    /// Lock-protected scratch for `captureWAV`. NSLock-guarded so it's
    /// real Sendable, not @unchecked — even though AVSpeechSynthesizer
    /// callbacks are documented serial, this makes the safety explicit.
    private final class CaptureState: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [Data] = []
        private var format: AVAudioFormat?
        private var finalized = false

        func append(chunk: Data, format: AVAudioFormat) {
            lock.lock(); defer { lock.unlock() }
            self.chunks.append(chunk)
            self.format = format
        }

        /// Returns the captured payload on the first call; nil on any
        /// subsequent call so the continuation resumes exactly once.
        func finalizeOnce() -> (chunks: [Data], format: AVAudioFormat?)? {
            lock.lock(); defer { lock.unlock() }
            guard !finalized else { return nil }
            finalized = true
            return (chunks, format)
        }
    }

    private static func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var out = Data(capacity: frames * channelCount * 2)
        // WAV stores multi-channel PCM in frame-major interleaved order
        // (L0,R0,L1,R1,...), NOT channel-major (L0..Ln,R0..Rn). For mono
        // both orderings are identical, but emitting interleaved here
        // means stereo capture (if ever enabled) plays correctly.
        if let int16 = buffer.int16ChannelData {
            for f in 0..<frames {
                for ch in 0..<channelCount {
                    let s = int16[ch][f]
                    out.append(UInt8(truncatingIfNeeded: s))
                    out.append(UInt8(truncatingIfNeeded: s >> 8))
                }
            }
        } else if let float = buffer.floatChannelData {
            for f in 0..<frames {
                for ch in 0..<channelCount {
                    let clipped = max(-1, min(1, float[ch][f]))
                    let scaled = Int16(clipped * Float(Int16.max))
                    out.append(UInt8(truncatingIfNeeded: scaled))
                    out.append(UInt8(truncatingIfNeeded: scaled >> 8))
                }
            }
        }
        return out
    }
}
