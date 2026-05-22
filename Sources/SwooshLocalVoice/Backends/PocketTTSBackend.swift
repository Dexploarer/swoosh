// SwooshLocalVoice/Backends/PocketTTSBackend.swift — 0.9R Persistent cloning
//
// Drives `FluidAudio.PocketTtsManager`. Two-step cloning model:
//   1. `cloneVoice(from: audioURL)` → `PocketTtsVoiceData` (enrollment)
//   2. `synthesize(text:voiceData:)` reuses the enrollment for every
//      subsequent turn — no need to re-process the reference audio.
//
// This backend wraps that into a single `synthesize(...)` call: pass a
// `referenceAudio` URL and we enroll-then-synthesize in one shot. For
// callers that want to save and reuse the voice across launches,
// `LocalVoiceCloneStore` (separate file) persists the `PocketTtsVoiceData`
// blob keyed by user-chosen name.
//
// Without a `referenceAudio`, PocketTTS uses its built-in default voice
// (English) so the backend still produces audio without a clone.

import Foundation
import FluidAudio

actor PocketTTSBackend: Backend {

    static let shared = PocketTTSBackend()

    private var manager: PocketTtsManager?

    func load(modelPath: URL?, model: LocalVoiceModel) async throws {
        if manager != nil { return }
        _ = modelPath; _ = model
        let mgr = PocketTtsManager()
        try await mgr.initialize()
        manager = mgr
    }

    func synthesize(
        text: String,
        voiceID: String?,
        referenceAudio: URL?,
        model: LocalVoiceModel
    ) async throws -> Data {
        if manager == nil {
            try await load(modelPath: nil, model: model)
        }
        guard let manager else {
            throw LocalVoiceError.engineNotReady("PocketTTS manager nil after initialize")
        }

        // Priority 1: voiceID looks like a saved clone id (prefix
        // `clone:`) — load the enrollment blob from the persistent
        // store and reuse it. No re-extraction.
        if let voiceID, voiceID.hasPrefix("clone:") {
            let cloneID = String(voiceID.dropFirst("clone:".count))
            if let voiceData = try await Self.loadStoredVoiceData(cloneID: cloneID) {
                return try await manager.synthesize(text: text, voiceData: voiceData)
            }
        }

        // Priority 2: explicit reference URL — clone and synthesize in
        // one shot. Caller is responsible for caching if they want.
        if let referenceAudio {
            let voiceData = try await manager.cloneVoice(from: referenceAudio)
            return try await manager.synthesize(text: text, voiceData: voiceData)
        }

        // Priority 3: built-in default / named voice pack.
        return try await manager.synthesize(text: text, voice: voiceID)
    }

    /// Load a previously-persisted `PocketTtsVoiceData` blob from the
    /// shared store. Returns nil when the clone id doesn't exist on disk.
    /// Uses the `PocketCloneEnvelope` Codable wrapper since
    /// PocketTtsVoiceData itself isn't Codable upstream.
    static func loadStoredVoiceData(cloneID: String) async throws -> PocketTtsVoiceData? {
        guard let bytes = try await LocalVoiceCloneStore.shared.voiceDataBytes(id: cloneID) else {
            return nil
        }
        let envelope = try JSONDecoder().decode(PocketCloneEnvelope.self, from: bytes)
        return envelope.toVoiceData()
    }
}

/// Codable wrapper for the cloning-only fields of PocketTtsVoiceData.
/// FluidAudio doesn't export Codable conformance, so we round-trip
/// `audioPrompt` + `promptLength` (the two fields cloning populates;
/// `cacheSnapshot` is reserved for shipped voice packs and stays nil
/// on the cloning path).
struct PocketCloneEnvelope: Codable, Sendable {
    let audioPrompt: [Float]
    let promptLength: Int

    init(_ data: PocketTtsVoiceData) {
        self.audioPrompt = data.audioPrompt
        self.promptLength = data.promptLength
    }

    func toVoiceData() -> PocketTtsVoiceData {
        PocketTtsVoiceData(
            audioPrompt: audioPrompt,
            promptLength: promptLength,
            cacheSnapshot: nil
        )
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
