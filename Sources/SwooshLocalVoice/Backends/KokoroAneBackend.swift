// SwooshLocalVoice/Backends/KokoroAneBackend.swift — 0.9R Real Kokoro
//
// Drives Kokoro-82M through FluidAudio's ANE-optimised CoreML pipeline.
// First-call cold start is 2–3 s (model download + ANE warmup); steady-
// state synthesis is ~22× real-time on an M-series chip and faster than
// real-time on iPhone 14+.
//
// FluidAudio's `KokoroAneManager`:
//   - Downloads the CoreML model bundle from Hugging Face on first run
//     into the app's Caches dir
//   - Loads it onto the Apple Neural Engine
//   - `synthesize(text:)` returns 24 kHz Float32 mono PCM samples
//
// We wrap the samples in a 16-bit WAV header so the rest of the stack
// (LocalTTSProvider → TTSPlayback / StreamingTTSPlayer) plays them via
// AVAudioPlayer without any decode-side branching.

import Foundation
import FluidAudio

actor KokoroAneBackend: Backend {

    static let shared = KokoroAneBackend()

    private var manager: KokoroAneManager?
    private var initialised: Bool = false

    func load(modelPath: URL?, model: LocalVoiceModel) async throws {
        if initialised { return }
        // FluidAudio resolves its own model URLs — we pass our cached
        // path through for parity with the Backend contract but the
        // package owns the on-disk layout.
        _ = modelPath; _ = model
        let manager = KokoroAneManager(defaultVoice: LocalVoiceCatalog.defaultKokoroVoiceID)
        try await manager.initialize(preloadVoices: [LocalVoiceCatalog.defaultKokoroVoiceID])
        self.manager = manager
        self.initialised = true
    }

    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data {
        // Kokoro uses fixed voice packs, not cloning — reference audio
        // is silently ignored here. Users who want cloning pick the
        // StyleTTS2 or PocketTTS catalog entries instead.
        _ = referenceAudio
        if !initialised {
            try await load(modelPath: nil, model: model)
        }
        guard let manager else {
            throw LocalVoiceError.engineNotReady("Kokoro manager nil after initialize")
        }
        // FluidAudio returns a complete 24 kHz mono 16-bit PCM WAV blob
        // (header included). voiceID maps to one of the Kokoro voice
        // packs (e.g. "af_heart"); nil → default voice.
        return try await manager.synthesize(
            text: text,
            voice: voiceID ?? LocalVoiceCatalog.defaultKokoroVoiceID
        )
    }
}
