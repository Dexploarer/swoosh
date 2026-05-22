// SwooshSTT/SystemFileSTTProvider.swift — 0.9R SFSpeechRecognizer for files
//
// Apple's SFSpeechRecognizer supports both live mic (handled by
// SwooshUI.SpeechCapture) and one-shot file transcription via
// `SFSpeechURLRecognitionRequest`. This provider covers the file path
// so the unified `STTProviding` interface works end-to-end without
// any download or model management — Apple ships the engine for free.

import Foundation
import Speech

public actor SystemFileSTTProvider: STTProviding {

    public nonisolated let displayName = "Apple Speech (system)"
    public nonisolated let id = "system"
    public nonisolated let isLocal = true

    public init() {}

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw STTError.fileNotFound(audioURL)
        }

        // Request authorization once.
        let status = await SFSpeechRecognizer.currentAuthStatus()
        guard status == .authorized else {
            throw STTError.modelUnavailable("Speech recognition not authorized")
        }

        let locale = languageHint.flatMap(Locale.init(identifier:)) ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw STTError.modelUnavailable("recognizer unavailable for \(locale.identifier)")
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = onProgress != nil
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    // 1110 = no speech detected — surface as empty transcript.
                    let ns = error as NSError
                    if ns.code == 1110 {
                        continuation.resume(returning: Transcript(text: ""))
                    } else {
                        continuation.resume(throwing: STTError.transcribeFailed(error.localizedDescription))
                    }
                    return
                }
                guard let result else { return }
                if !result.isFinal, let cb = onProgress {
                    let partial = result.bestTranscription.formattedString
                    Task { @MainActor in cb(partial) }
                    return
                }
                if result.isFinal {
                    let segments = result.bestTranscription.segments.map {
                        Transcript.Segment(
                            text: $0.substring,
                            startSeconds: $0.timestamp,
                            endSeconds: $0.timestamp + $0.duration
                        )
                    }
                    continuation.resume(returning: Transcript(
                        text: result.bestTranscription.formattedString,
                        segments: segments,
                        language: locale.identifier
                    ))
                }
            }
        }
    }
}

// MARK: - Auth wrapper

private extension SFSpeechRecognizer {
    static func currentAuthStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }
}
