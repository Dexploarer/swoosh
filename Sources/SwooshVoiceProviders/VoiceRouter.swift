// SwooshVoiceProviders/VoiceRouter.swift — 0.9R Unified voice-stack dispatcher
//
// One actor that owns the user's current voice choices, instantiates
// the right STT / TTS / music providers on demand, and lets the app
// mix-and-match across providers.
//
// Selection is settings-driven via UserDefaults:
//   swoosh.voice.sttEngine     — "system" | "whisper"
//   swoosh.voice.whisperModel  — WhisperModel rawValue
//   swoosh.voice.ttsEngine     — "system" | "elevenlabs" | "openai-tts" | "cartesia"
//   swoosh.voice.systemVoiceID — AVSpeechSynthesisVoice identifier
//   swoosh.voice.musicProvider — "suno" | "elevenlabs-music" | "stable-audio"
//
// API:
//   let router = VoiceRouter.shared
//   let tts = try router.activeTTSProvider()
//   try await router.playback.speak("hi", with: tts)
//   let stt = try router.activeSTTProvider()                  // returns a Provider with current engine
//   let music = try router.activeMusicProvider()              // user's picked music gen
//
// Switching is reactive — change the UserDefaults key and the next
// `activeXProvider()` call returns the new provider.

import Foundation
import SwooshMusic
@_exported import SwooshSecrets
import SwooshSTT

@MainActor
@Observable
public final class VoiceRouter {

    public static let shared = VoiceRouter()

    public let playback = TTSPlayback()
    public let streamingPlayer = StreamingTTSPlayer()

    public init() {}

    // MARK: - TTS

    public enum TTSChoice: String, Sendable, CaseIterable, Identifiable {
        case system
        case elevenlabs
        case openaiTTS    = "openai-tts"
        case cartesia
        /// On-device TTS via `SwooshLocalVoice` — Kokoro 82M (English+Mandarin, fixed voice packs).
        case kokoroLocal  = "kokoro-local"
        /// On-device zero-shot voice cloning via `SwooshLocalVoice` — StyleTTS2 LibriTTS.
        case styleTTS2Local = "styletts2-local"
        /// On-device persistent voice cloning via `SwooshLocalVoice` — PocketTTS.
        case pocketTTSLocal = "pockettts-local"
        /// On-device TTS via `SwooshLocalVoice` — OmniVoice (600+ languages,
        /// voice cloning). Routed by the device policy on smaller iPhones.
        case omniVoiceLocal = "omnivoice-local"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .system:           return "Apple voices (system)"
            case .elevenlabs:       return "ElevenLabs"
            case .openaiTTS:        return "OpenAI TTS"
            case .cartesia:         return "Cartesia Sonic"
            case .kokoroLocal:      return "Kokoro (on-device)"
            case .styleTTS2Local:   return "StyleTTS2 (on-device, zero-shot clone)"
            case .pocketTTSLocal:   return "PocketTTS (on-device, persistent clone)"
            case .omniVoiceLocal:   return "OmniVoice (on-device, 600+ langs)"
            }
        }
        public var requiresAPIKey: Bool {
            switch self {
            case .system, .kokoroLocal, .styleTTS2Local, .pocketTTSLocal, .omniVoiceLocal:
                return false
            case .elevenlabs, .openaiTTS, .cartesia:
                return true
            }
        }
        /// True for engines that don't reach the network. Used by the
        /// chat path to decide whether a TTS pick is offline-capable.
        public var isLocal: Bool {
            switch self {
            case .system, .kokoroLocal, .styleTTS2Local, .pocketTTSLocal, .omniVoiceLocal:
                return true
            case .elevenlabs, .openaiTTS, .cartesia:
                return false
            }
        }
        /// True for engines that can synthesise an arbitrary cloned voice
        /// from a reference audio file. Drives the "Clone a voice" UI.
        public var supportsCloning: Bool {
            switch self {
            case .styleTTS2Local, .pocketTTSLocal, .omniVoiceLocal, .elevenlabs, .cartesia:
                return true
            case .system, .kokoroLocal, .openaiTTS:
                return false
            }
        }
        public var providerID: String { rawValue }
    }

    public var currentTTSChoice: TTSChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.voice.ttsEngine") ?? "system"
            return TTSChoice(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.voice.ttsEngine") }
    }

    /// Build the active TTS provider conforming to `TTSProviding`.
    /// Returns nil for `.system` (which lives in SwooshUI's `TTSEngine`)
    /// and for the on-device choices (which need the SwooshLocalVoice
    /// module — wired by `activeTTSProvider()` in module clients).
    public func activeCloudTTSProvider() throws -> (any TTSProviding)? {
        switch currentTTSChoice {
        case .system, .kokoroLocal, .styleTTS2Local, .pocketTTSLocal, .omniVoiceLocal:
            return nil
        case .elevenlabs:
            return ElevenLabsTTSProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("elevenlabs")
            )
        case .openaiTTS:
            return OpenAITTSProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("openai")
            )
        case .cartesia:
            return CartesiaTTSProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("cartesia")
            )
        }
    }

    // MARK: - STT

    public enum STTChoice: String, Sendable, CaseIterable, Identifiable {
        case system
        case whisper

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .system:  return "Apple Speech (system)"
            case .whisper: return "Whisper (on-device)"
            }
        }
    }

    public var currentSTTChoice: STTChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.voice.sttEngine") ?? "system"
            return STTChoice(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.voice.sttEngine") }
    }

    public var currentWhisperModel: WhisperModel {
        let raw = UserDefaults.standard.string(forKey: "swoosh.voice.whisperModel") ?? "openai_whisper-small"
        return WhisperModel(rawValue: raw) ?? .smallMultilingual
    }

    /// Build the active **file-transcription** STT provider. For live-mic
    /// dictation, keep using `SwooshUI.SpeechCapture` directly — its
    /// AVAudioEngine integration is purpose-built for low-latency mic
    /// capture and isn't replaceable by a file-based provider.
    public func activeSTTProvider() -> any STTProviding {
        switch currentSTTChoice {
        case .system:
            return SystemFileSTTProvider()
        case .whisper:
            return WhisperSTTProvider(model: currentWhisperModel)
        }
    }

    // MARK: - Music

    public enum MusicChoice: String, Sendable, CaseIterable, Identifiable {
        case suno
        case elevenlabsMusic = "elevenlabs-music"
        case stableAudio     = "stable-audio"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .suno:             return "Suno"
            case .elevenlabsMusic:  return "ElevenLabs Music"
            case .stableAudio:      return "Stable Audio"
            }
        }
        public var keychainID: String {
            switch self {
            case .suno:             return "suno"
            case .elevenlabsMusic:  return "elevenlabs"
            case .stableAudio:      return "stability"
            }
        }
    }

    public var currentMusicChoice: MusicChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.voice.musicProvider") ?? "suno"
            return MusicChoice(rawValue: raw) ?? .suno
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.voice.musicProvider") }
    }

    /// Type-erased music provider — caller-side never sees the
    /// concrete adapter, so switching providers in Settings is one
    /// `UserDefaults` flip away.
    public func activeMusicProvider() throws -> any MusicProviding {
        switch currentMusicChoice {
        case .suno:
            return SunoMusicProvider(apiKeyProvider: KeychainAPIKeyProvider.for("suno"))
        case .elevenlabsMusic:
            return ElevenLabsMusicProvider(apiKeyProvider: KeychainAPIKeyProvider.for("elevenlabs"))
        case .stableAudio:
            return StableAudioProvider(apiKeyProvider: KeychainAPIKeyProvider.for("stability"))
        }
    }

    // MARK: - Provider configuration check

    /// True when the user has provided an API key for the currently
    /// active TTS choice. Use to disable speak buttons gracefully.
    public func isCurrentTTSConfigured() -> Bool {
        let choice = currentTTSChoice
        if !choice.requiresAPIKey { return true }
        return KeychainAPIKeyProvider.isConfigured(providerID: choice.providerID)
    }

    public func isCurrentMusicConfigured() -> Bool {
        KeychainAPIKeyProvider.isConfigured(providerID: currentMusicChoice.keychainID)
    }
}
