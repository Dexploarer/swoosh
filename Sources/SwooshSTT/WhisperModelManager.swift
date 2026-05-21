// SwooshSTT/WhisperModelManager.swift — 0.9R Explicit download UI for WhisperKit models
//
// WhisperKit will lazy-download on first transcribe, but a user-facing
// app should let the user decide *when* to pay the 250MB-800MB cost.
// This manager exposes per-model download state and a `download()`
// trigger the picker can wire to a button.
//
// State machine per model:
//   notDownloaded  → tap Download → downloading(progress) → ready
//                                                      ↘ failed(reason)

import Foundation
import WhisperKit

@MainActor
@Observable
public final class WhisperModelManager {

    public enum DownloadState: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    public private(set) var state: [String: DownloadState] = [:]

    public init() {
        // Seed state by checking if each catalog model is already on disk.
        for model in WhisperModel.allCases {
            state[model.rawValue] = isCached(model: model.rawValue) ? .ready : .notDownloaded
        }
    }

    /// Trigger a WhisperKit instantiation, which downloads + compiles
    /// the Core ML weights. Progress is approximated — WhisperKit's
    /// own progress reporter isn't a stream, so we mark .downloading
    /// at start and .ready on finish.
    public func download(_ model: WhisperModel) {
        let id = model.rawValue
        state[id] = .downloading(progress: 0.0)
        Task.detached(priority: .userInitiated) {
            do {
                _ = try await WhisperKit(model: id)
                await MainActor.run { self.state[id] = .ready }
            } catch {
                await MainActor.run {
                    self.state[id] = .failed(String(describing: error))
                }
            }
        }
    }

    /// Remove a model's cached weights to free disk space.
    public func delete(_ model: WhisperModel) {
        let url = whisperCacheDir().appendingPathComponent(model.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        state[model.rawValue] = .notDownloaded
    }

    public func state(of model: WhisperModel) -> DownloadState {
        state[model.rawValue] ?? .notDownloaded
    }

    // MARK: - Cache discovery

    /// WhisperKit caches models under `<app-support>/argmaxinc/models/`.
    /// We can't fully detect compile completion without loading, so we
    /// treat existence of the model dir as "ready" — `WhisperKit()`
    /// re-verifies on instantiation anyway.
    private func isCached(model: String) -> Bool {
        let path = whisperCacheDir().appendingPathComponent(model, isDirectory: true).path
        return FileManager.default.fileExists(atPath: path)
    }

    private func whisperCacheDir() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("whisperkit", isDirectory: true)
    }
}
