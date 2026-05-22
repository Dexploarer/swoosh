// SwooshLocalVoice/Backends/SherpaOnnxBackend.swift — 0.9R OmniVoice swap point
//
// Placeholder backend for OmniVoice (and other models the upstream
// `k2-fsa/sherpa-onnx` Swift package will eventually serve). Today this
// throws `.backendNotAvailable` so the dispatcher routes OmniVoice to
// `AppleFallbackBackend`; the swap is one line in `LocalVoiceEngine`
// when sherpa-onnx ships its OmniVoice TTS variant.
//
// Why this file exists even when nothing's wired:
//   - The OmniVoice catalog entry is real (k2-fsa published the weights
//     in March 2026), but no Swift package yet drives the inference.
//   - Tests can assert this backend exists and reports unavailability
//     instead of silently falling back, so when sherpa-onnx ships we
//     know exactly which place needs the route change.
//   - Comments here document the contract the future implementation
//     must satisfy so contributors don't reinvent it.

import Foundation

actor SherpaOnnxBackend: Backend {

    static let shared = SherpaOnnxBackend()

    func load(modelPath: URL?, model: LocalVoiceModel) async throws {
        throw LocalVoiceError.backendNotAvailable(
            "sherpa-onnx Swift package not yet wired. \(model.displayName) falls back to Apple TTS."
        )
    }

    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data {
        _ = referenceAudio
        throw LocalVoiceError.backendNotAvailable(
            "sherpa-onnx Swift package not yet wired. \(model.displayName) falls back to Apple TTS."
        )
    }
}
