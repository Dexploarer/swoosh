// SwooshVoiceProviders/TTSProviding.swift — 0.9R Cloud TTS provider protocol
//
// Common interface for every TTS engine — system (AVSpeechSynthesizer
// in SwooshUI), cloud (ElevenLabs, OpenAI, Cartesia), local generators
// (future Orpheus/Kokoro). Each provider returns audio bytes for a
// given text + voice; the caller plays them through AVAudioPlayer.
//
// API key story: each cloud provider reads its key from `SecretStoring`
// (Keychain). The picker UI in SwooshUI prompts the user to enter the
// key on first selection.

import Foundation

public protocol TTSProviding: Sendable {

    /// Display name in the picker.
    var displayName: String { get }

    /// Stable id ("elevenlabs", "openai-tts", "cartesia"). Used as
    /// UserDefaults storage key.
    var id: String { get }

    /// Whether this provider needs a remote API call (true) or runs
    /// fully on-device (false). System TTS is the only false case today.
    var isCloud: Bool { get }

    /// Where the user can obtain an API key for this provider. nil for
    /// providers that don't need a key (system).
    var signupURL: URL? { get }

    /// True when this provider can stream the response chunk-by-chunk.
    /// When false, `synthesizeStream` emits a single chunk = the full
    /// response. Lets clients adapt UI (waveform live-update vs blob).
    var supportsStreaming: Bool { get }

    /// Synthesize `text` into raw audio bytes. The MIME type defines
    /// the format (e.g. `audio/mpeg`, `audio/wav`).
    func synthesize(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) async throws -> TTSResult

    /// Streaming variant — yields audio bytes as the network delivers
    /// them. Default impl below wraps `synthesize` in a single-chunk
    /// stream so any provider conforms automatically.
    func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error>
}

public extension TTSProviding {
    /// Default streaming impl — wraps the blocking `synthesize` call
    /// in a single-chunk stream. Providers with real streaming
    /// endpoints override this.
    func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await synthesize(text: text, voiceID: voiceID, format: format)
                    continuation.yield(result.audioData)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    var supportsStreaming: Bool { true }
    var signupURL: URL? { nil }
}

public struct TTSResult: Sendable {
    public let audioData: Data
    public let mimeType: String
    public let voiceUsed: String?

    public init(audioData: Data, mimeType: String, voiceUsed: String? = nil) {
        self.audioData = audioData
        self.mimeType = mimeType
        self.voiceUsed = voiceUsed
    }
}

public enum TTSAudioFormat: String, Sendable {
    case mp3
    case wav
    case opus
    case aac
    /// Raw 16-bit signed little-endian PCM at 44.1 kHz mono. Lowest-
    /// latency streaming path (zero decode cost). Currently used by
    /// `CartesiaTTSProvider` when callers want minimum first-byte time.
    case pcm

    public var mimeType: String {
        switch self {
        case .mp3:  return "audio/mpeg"
        case .wav:  return "audio/wav"
        case .opus: return "audio/opus"
        case .aac:  return "audio/aac"
        case .pcm:  return "audio/L16"
        }
    }

    /// True when frames are raw PCM samples — the streaming player can
    /// skip the AVAudioFile decode path entirely.
    public var isRawPCM: Bool { self == .pcm }
}

public struct TTSVoice: Sendable, Hashable, Identifiable {
    public let id: String          // Provider-specific id
    public let displayName: String // Human label
    public let language: String?
    public let preview: URL?       // Optional preview clip URL

    public init(id: String, displayName: String, language: String? = nil, preview: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.preview = preview
    }
}

public enum TTSError: Error, CustomStringConvertible {
    case missingAPIKey(String)
    case requestFailed(String)
    case decodeFailed(String)
    case voiceNotFound(String)

    public var description: String {
        switch self {
        case .missingAPIKey(let p):  return "Missing API key for \(p). Add it in Settings → Voice → \(p)."
        case .requestFailed(let m):  return "TTS request failed: \(m)"
        case .decodeFailed(let m):   return "TTS response decode failed: \(m)"
        case .voiceNotFound(let v):  return "TTS voice not found: \(v)"
        }
    }
}
