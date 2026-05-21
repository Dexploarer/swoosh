// SwooshSTT/STTProtocol.swift — 0.9R STT provider protocol
//
// Common interface for every speech-to-text engine we ship:
//   • SystemSTTProvider (SFSpeechRecognizer — already wired in SwooshUI)
//   • WhisperSTTProvider (WhisperKit / Core ML on Apple Silicon)
//   • Future: cloud (OpenAI Whisper API, Cartesia Sonic-STT, Deepgram)
//
// A `Transcript` always carries the final text + segment-level
// timestamps. Progress updates are surfaced via the optional progress
// callback (live partials).

import Foundation

public protocol STTProviding: Sendable {

    /// Display name shown in the picker.
    var displayName: String { get }

    /// Stable id (e.g. `"system"`, `"whisper-small"`). Used as the
    /// UserDefaults storage key.
    var id: String { get }

    /// True if the provider runs entirely on-device.
    var isLocal: Bool { get }

    /// Transcribe an audio file at `url` (.wav / .m4a / .mp3).
    /// `onProgress` receives partial transcripts as the engine produces
    /// them; final result returned at completion.
    func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> Transcript
}

public struct Transcript: Sendable, Equatable {
    public let text: String
    public let segments: [Segment]
    public let language: String?

    public struct Segment: Sendable, Equatable {
        public let text: String
        public let startSeconds: Double
        public let endSeconds: Double
    }

    public init(text: String, segments: [Segment] = [], language: String? = nil) {
        self.text = text
        self.segments = segments
        self.language = language
    }
}

public enum STTError: Error, CustomStringConvertible {
    case modelUnavailable(String)
    case loadFailed(String)
    case transcribeFailed(String)
    case fileNotFound(URL)

    public var description: String {
        switch self {
        case .modelUnavailable(let m):  return "STT model unavailable: \(m)"
        case .loadFailed(let m):        return "STT load failed: \(m)"
        case .transcribeFailed(let m):  return "STT transcribe failed: \(m)"
        case .fileNotFound(let url):    return "STT audio file not found at \(url.path)"
        }
    }
}
