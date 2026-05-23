// SwooshLocalVoice/LocalTTSResolver.swift — 0.9R Bridge to VoiceRouter
//
// SwooshVoiceProviders.VoiceRouter declares `.kokoroLocal` /
// `.omniVoiceLocal` cases as part of its `TTSChoice` enum, but it
// deliberately doesn't import SwooshLocalVoice (that would invert the
// dependency — VoiceProviders is the smaller, cross-platform module
// and LocalVoice depends on it). This resolver lives on the LocalVoice
// side and maps a `TTSChoice` to a `LocalTTSProvider`.
//
// Usage from the iOS app:
//   if let provider = LocalTTSResolver.provider(for: VoiceRouter.shared.currentTTSChoice) {
//       let result = try await provider.synthesize(text: ..., voiceID: nil, format: .wav)
//   }

import Foundation
import SwooshVoiceProviders

public enum LocalTTSResolver {

    /// Returns a `LocalTTSProvider` instance when `choice` is one of the
    /// on-device cases. Returns nil for cloud/system choices — callers
    /// fall through to `VoiceRouter.activeCloudTTSProvider()`.
    public static func provider(for choice: VoiceRouter.TTSChoice) -> LocalTTSProvider? {
        switch choice {
        case .kokoroLocal:
            return LocalTTSProvider(model: LocalVoiceCatalog.kokoro)
        case .styleTTS2Local:
            return LocalTTSProvider(model: LocalVoiceCatalog.styleTTS2)
        case .pocketTTSLocal:
            return LocalTTSProvider(model: LocalVoiceCatalog.pocketTTS)
        case .omniVoiceLocal:
            return LocalTTSProvider(model: LocalVoiceCatalog.omniVoice)
        case .system, .elevenlabs, .openaiTTS, .cartesia:
            return nil
        }
    }
}
