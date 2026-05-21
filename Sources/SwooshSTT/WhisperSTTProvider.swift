// SwooshSTT/WhisperSTTProvider.swift — 0.9R WhisperKit-backed STT
//
// WhisperKit is Apple-Silicon-optimised, runs entirely on-device via
// Core ML, and downloads model weights on first use from the Argmax
// HuggingFace mirror. Three model sizes ship out of the box:
//   • whisper-tiny           (~40 MB)   — sketches; high WER
//   • whisper-small          (~250 MB)  — default, good multilingual
//   • whisper-large-v3-turbo (~800 MB)  — best accuracy; recommended
//                                          for transcription of recordings
//
// Models download lazily on first transcribe call; subsequent calls
// reuse the cached weights. WhisperKit handles the download + Core
// ML compilation itself; we just hand off audio.

import Foundation
import WhisperKit

public actor WhisperSTTProvider: STTProviding {

    public nonisolated let displayName: String
    public nonisolated let id: String
    public nonisolated let isLocal: Bool = true

    /// Model variant string WhisperKit recognises (e.g. `"openai_whisper-small"`,
    /// `"openai_whisper-large-v3-turbo"`).
    public let model: String

    private var kit: WhisperKit?

    public init(model: WhisperModel = .smallMultilingual) {
        self.model = model.rawValue
        self.id = "whisper.\(model.rawValue)"
        self.displayName = model.displayName
    }

    /// Ensure the WhisperKit instance is built + the model is downloaded.
    /// First call can take 30–60 s for a fresh download; subsequent
    /// calls return immediately.
    public func warmup() async throws {
        _ = try await kitOrLoad()
    }

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw STTError.fileNotFound(audioURL)
        }
        let kit = try await kitOrLoad()
        let options = DecodingOptions(
            language: languageHint,
            withoutTimestamps: false
        )
        do {
            let results = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )
            let segments = results.flatMap { result in
                result.segments.map {
                    Transcript.Segment(
                        text: $0.text,
                        startSeconds: Double($0.start),
                        endSeconds: Double($0.end)
                    )
                }
            }
            let text = results.map(\.text).joined(separator: " ")
            return Transcript(
                text: text,
                segments: segments,
                language: results.first?.language
            )
        } catch {
            throw STTError.transcribeFailed(String(describing: error))
        }
    }

    private func kitOrLoad() async throws -> WhisperKit {
        if let kit { return kit }
        do {
            STTLogger.whisper.info("loading model=\(self.model, privacy: .public)")
            let started = Date()
            let new = try await WhisperKit(model: model)
            let elapsed = Date().timeIntervalSince(started)
            STTLogger.whisper.info("loaded in \(String(format: "%.2f", elapsed), privacy: .public) s")
            self.kit = new
            return new
        } catch {
            STTLogger.whisper.error("load failed: \(error.localizedDescription, privacy: .public)")
            throw STTError.loadFailed(String(describing: error))
        }
    }
}

// MARK: - Catalog

public enum WhisperModel: String, Sendable, CaseIterable {
    case tinyEnglish        = "openai_whisper-tiny.en"
    case smallEnglish       = "openai_whisper-small.en"
    case smallMultilingual  = "openai_whisper-small"
    case largeV3Turbo       = "openai_whisper-large-v3-turbo"

    public var displayName: String {
        switch self {
        case .tinyEnglish:       return "Whisper Tiny (English)"
        case .smallEnglish:      return "Whisper Small (English)"
        case .smallMultilingual: return "Whisper Small (Multilingual)"
        case .largeV3Turbo:      return "Whisper Large v3 Turbo"
        }
    }

    public var estimatedSizeMB: Int {
        switch self {
        case .tinyEnglish:       return 40
        case .smallEnglish:      return 250
        case .smallMultilingual: return 250
        case .largeV3Turbo:      return 800
        }
    }
}
