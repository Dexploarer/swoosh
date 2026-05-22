// SwooshLocalVoice/Backends/StyleTTS2Backend.swift — 0.9R Zero-shot cloning
//
// Drives `FluidAudio.StyleTTS2Manager` (LibriTTS-trained zero-shot).
// Cloning model: pass a reference WAV (3–10 s of clean speech) on each
// `synthesize()` call. Per-call API means no enrollment step — callers
// can hot-swap voices freely.
//
// Output: `[Float]` mono 24 kHz, wrapped into a WAV blob via WAVEncoder
// so the rest of the stack stays format-agnostic.
//
// Without `referenceAudio`, returns `.synthesisFailed` — StyleTTS2 has
// no built-in default voice; cloning IS the model's contract.

import Foundation
import FluidAudio

actor StyleTTS2Backend: Backend {

    static let shared = StyleTTS2Backend()

    private var manager: StyleTTS2Manager?

    func load(modelPath: URL?, model: LocalVoiceModel) async throws {
        if manager != nil { return }
        _ = modelPath; _ = model
        let mgr = StyleTTS2Manager()
        try await mgr.initialize()
        manager = mgr
    }

    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data {
        _ = voiceID  // StyleTTS2 has no fixed voice ids; identity comes
                     // entirely from the reference audio.
        if manager == nil {
            try await load(modelPath: nil, model: model)
        }
        guard let manager else {
            throw LocalVoiceError.engineNotReady("StyleTTS2 manager nil after initialize")
        }
        guard let referenceAudio else {
            throw LocalVoiceError.synthesisFailed(
                "StyleTTS2 requires a reference audio URL. Pass one via " +
                "LocalTTSProvider.synthesize(text:referenceAudio:...) to enroll a voice."
            )
        }
        let samples = try await manager.synthesize(
            text: text,
            referenceAudioURL: referenceAudio
        )
        return WAVEncoder.encodeFloat32Mono(samples, sampleRate: model.defaultSampleRate)
    }
}
