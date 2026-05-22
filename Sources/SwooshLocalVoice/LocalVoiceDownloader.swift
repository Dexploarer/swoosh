#if os(iOS)

// SwooshLocalVoice/LocalVoiceDownloader.swift — 0.9R Download + cache
//
// Mirrors `LiteRTModelDownloader`: fetches a `LocalVoiceModel`'s weights
// from HuggingFace into the app's caches directory, reports progress
// via `@Observable`, supports cancel + delete.
//
// Cache layout:
//   <caches>/ai.swoosh.localvoice/<model.id>/<model.id>.bin
//
// The byte-count completeness heuristic is the same one Whisper +
// LiteRT downloaders use — re-download if the file is < 95 % of the
// published estimate.

import Foundation

@MainActor
@Observable
public final class LocalVoiceDownloader: NSObject {

    public enum State: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
        case ready(URL)
        case failed(String)
    }

    public private(set) var state: State = .notDownloaded
    public let model: LocalVoiceModel

    private var task: URLSessionDownloadTask?
    private var session: URLSession?

    /// Captured once at init so the URLSession background delegate can
    /// read them without bouncing to the main actor — calling
    /// `MainActor.assumeIsolated` from the session callback queue used
    /// to crash with "Incorrect actor executor assumption".
    nonisolated let cachedTargetURL: URL
    nonisolated let estimatedBytes: Int64

    public init(model: LocalVoiceModel) {
        self.model = model
        self.cachedTargetURL = Self.targetURL(for: model)
        self.estimatedBytes = model.estimatedBytes
        super.init()
        if isCached {
            state = .ready(cachedTargetURL)
        }
    }

    public var cachedURL: URL { cachedTargetURL }

    private static func targetURL(for model: LocalVoiceModel) -> URL {
        cacheDir()
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent("\(model.id).bin")
    }

    public var isCached: Bool {
        let url = cachedURL
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size >= Int64(Double(model.estimatedBytes) * 0.95)
    }

    public func download() {
        if isCached {
            state = .ready(cachedURL)
            return
        }
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.networkServiceType = .responsiveData
        config.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        state = .downloading(progress: 0, bytesWritten: 0, totalBytes: model.estimatedBytes)
        let task = session.downloadTask(with: model.downloadURL)
        self.task = task
        task.resume()
    }

    public func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        state = .notDownloaded
    }

    public func deleteCached() {
        try? FileManager.default.removeItem(at: cachedURL)
        state = .notDownloaded
    }

    static func cacheDir() -> URL {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ai.swoosh.localvoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

extension LocalVoiceDownloader: URLSessionDownloadDelegate {

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Background queue — must NOT touch main-actor state directly.
        // Use the nonisolated `cachedTargetURL` captured at init.
        let target = cachedTargetURL
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: location, to: target)
            Task { @MainActor in self.state = .ready(target) }
        } catch {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : estimatedBytes
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        Task { @MainActor in
            self.state = .downloading(
                progress: progress,
                bytesWritten: totalBytesWritten,
                totalBytes: total
            )
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
    }
}

#endif
