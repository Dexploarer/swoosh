// SwooshLocalVoice/Backends/Backend.swift — 0.9R Backend protocol
//
// One contract every concrete inference backend conforms to. The
// `LocalVoiceEngine` actor holds one Backend at a time, picked by the
// model's id at construction.
//
// All backends must:
//   - load() exactly once before synthesize() succeeds
//   - synthesize() emit WAV bytes (mono, 16-bit, model's defaultSampleRate)
//     so callers can pipe directly into AVAudioPlayer regardless of which
//     backend served the call
//
// Cloning backends honour `referenceAudio` (a WAV/AIFF/CAF/m4a URL); the
// non-cloning ones (Kokoro, Apple fallback) ignore it.

import Foundation

protocol Backend: Sendable {
    func load(modelPath: URL?, model: LocalVoiceModel) async throws
    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data
}
