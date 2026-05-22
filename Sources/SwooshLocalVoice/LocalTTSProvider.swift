// SwooshLocalVoice/LocalTTSProvider.swift — 0.9R On-device TTS provider
//
// Conforms to `SwooshVoiceProviders.TTSProviding` so VoiceRouter can
// pick it like any cloud provider — the only differences are
// `isCloud = false` and `signupURL = nil`. The provider drives a
// `LocalVoiceEngine` for the actual synthesis, so the model behind the
// audio is whatever the engine's backend says.
//
// One provider instance per model — `LocalTTSProvider(model: .kokoro)`
// vs `.omniVoice`. The VoiceRouter holds one of each.

import Foundation
import SwooshVoiceProviders

public struct LocalTTSProvider: TTSProviding {

    public let model: LocalVoiceModel
    public nonisolated let id: String
    public nonisolated let displayName: String
    public nonisolated let isCloud: Bool = false
    public nonisolated let signupURL: URL? = nil
    public nonisolated let supportsStreaming: Bool = true

    private let engine: LocalVoiceEngine

    public init(model: LocalVoiceModel) {
        self.model = model
        self.id = "local.\(model.id)"
        self.displayName = "On-device · \(model.displayName)"
        self.engine = LocalVoiceEngine(model: model)
    }

    public func synthesize(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) async throws -> TTSResult {
        let wav = try await engine.synthesize(text: text, voiceID: voiceID)
        return TTSResult(audioData: wav, mimeType: TTSAudioFormat.wav.mimeType, voiceUsed: voiceID)
    }

    public func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error> {
        engine.synthesizeStream(text: text, voiceID: voiceID)
    }

    // MARK: - Cloning-aware synthesis (StyleTTS2, PocketTTS)

    /// Synthesize using a reference audio for the cloning backends.
    /// Pass a 3–10 s WAV/AIFF/CAF/m4a URL the user has previously
    /// recorded or imported. Non-cloning backends ignore the reference.
    public func synthesize(
        text: String,
        referenceAudio: URL,
        voiceID: String? = nil
    ) async throws -> TTSResult {
        let wav = try await engine.synthesize(
            text: text,
            voiceID: voiceID,
            referenceAudio: referenceAudio
        )
        return TTSResult(audioData: wav, mimeType: TTSAudioFormat.wav.mimeType, voiceUsed: voiceID)
    }

    /// Synthesize using a previously-saved clone from `LocalVoiceCloneStore`.
    /// Routes through the engine with `voiceID = "clone:<id>"` so the
    /// PocketTTS backend can load the persisted enrollment blob instead
    /// of re-extracting from audio.
    public func synthesize(
        text: String,
        cloneID: String
    ) async throws -> TTSResult {
        let wav = try await engine.synthesize(
            text: text,
            voiceID: "clone:\(cloneID)",
            referenceAudio: nil
        )
        return TTSResult(
            audioData: wav,
            mimeType: TTSAudioFormat.wav.mimeType,
            voiceUsed: "clone:\(cloneID)"
        )
    }

    /// True for catalog entries that meaningfully consume reference audio.
    public var supportsVoiceCloning: Bool { model.supportsVoiceCloning }
}
