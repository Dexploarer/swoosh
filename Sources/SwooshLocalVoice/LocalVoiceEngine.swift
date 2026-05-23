// SwooshLocalVoice/LocalVoiceEngine.swift — 0.9R Inference dispatcher
//
// Actor that turns text + a `LocalVoiceModel` into WAV bytes. Routes to
// a concrete `Backend` based on the model id:
//
//   • `kokoro-82m-v1`   →  KokoroAneBackend (real ANE inference via FluidAudio)
//   • `omnivoice-v1`    →  AppleFallbackBackend (Apache 2.0 OmniVoice was
//                          released March 2026; no Swift wrapper yet —
//                          sherpa-onnx export pending. Fallback keeps the
//                          audio loop honest end-to-end.)
//   • anything else     →  AppleFallbackBackend
//
// The dispatcher is the only place that knows which backend serves which
// model — adding a new engine is one switch case + one file.

import Foundation

public actor LocalVoiceEngine {

    public enum LoadState: Sendable, Equatable {
        case unloaded
        case loading
        case ready
        case failed(String)
    }

    public private(set) var loadState: LoadState = .unloaded
    public let model: LocalVoiceModel

    /// In-flight load task. Concurrent callers await this instead of
    /// returning early on `.loading`, which previously let `synthesize`
    /// race past an incomplete load and call the backend before the
    /// model file was warm.
    private var pendingLoad: Task<Void, Error>?

    public init(model: LocalVoiceModel) {
        self.model = model
    }

    /// Bring the model up. The Apple fallback "loads" instantly; the
    /// Kokoro ANE backend downloads + warms up CoreML (~2–3 s cold).
    /// Idempotent — concurrent callers await the same in-flight task
    /// and observe the same success / failure outcome.
    public func load(modelPath: URL?) async throws {
        if loadState == .ready { return }
        if let pending = pendingLoad {
            try await pending.value
            return
        }
        loadState = .loading
        let task = Task<Void, Error> { [model, backend] in
            try await backend.load(modelPath: modelPath, model: model)
        }
        pendingLoad = task
        do {
            try await task.value
            loadState = .ready
        } catch {
            loadState = .failed("\(error)")
            pendingLoad = nil
            throw error
        }
        pendingLoad = nil
    }

    /// Synthesize → WAV bytes (mono, 16-bit, model.defaultSampleRate).
    /// `referenceAudio` is consumed by cloning backends (StyleTTS2,
    /// PocketTTS) and silently ignored by the others.
    public func synthesize(
        text: String,
        voiceID: String? = nil,
        referenceAudio: URL? = nil
    ) async throws -> Data {
        if loadState != .ready {
            try await load(modelPath: nil)
        }
        return try await backend.synthesize(
            text: text,
            voiceID: voiceID,
            referenceAudio: referenceAudio,
            model: model
        )
    }

    /// Streaming variant. The Kokoro backend is non-streaming (it's a
    /// non-autoregressive 3-stage pipeline); the Apple-fallback also
    /// returns the whole WAV at once. Stream emits a single chunk for
    /// both. When a real streaming backend lands (CosyVoice2, Moshi),
    /// add the path inside this method.
    public nonisolated func synthesizeStream(
        text: String,
        voiceID: String? = nil,
        referenceAudio: URL? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await self.synthesize(
                        text: text,
                        voiceID: voiceID,
                        referenceAudio: referenceAudio
                    )
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Backend dispatch (the routing point)

    /// Picks the concrete backend for the engine's model. New backends
    /// drop in here:
    ///   case "moshi-v1":     return MoshiBackend.shared
    ///   case "cosyvoice-v2": return CosyVoiceBackend.shared
    private var backend: any Backend {
        switch model.id {
        case LocalVoiceCatalog.kokoro.id:
            return KokoroAneBackend.shared
        case LocalVoiceCatalog.styleTTS2.id:
            // Zero-shot cloning via FluidAudio's StyleTTS2 (LibriTTS).
            return StyleTTS2Backend.shared
        case LocalVoiceCatalog.pocketTTS.id:
            // Persistent cloning via FluidAudio's PocketTTS (cloneVoice
            // produces a reusable PocketTtsVoiceData enrollment blob).
            return PocketTTSBackend.shared
        case LocalVoiceCatalog.omniVoice.id:
            // OmniVoice (Xiaomi/k2-fsa, March 2026): no Swift inference
            // package yet. sherpa-onnx will gain Swift support in a
            // subsequent release; until then we fall back to Apple TTS
            // so the path is functional and the user is told via the
            // UI banner.
            return AppleFallbackBackend.shared
        default:
            return AppleFallbackBackend.shared
        }
    }
}
