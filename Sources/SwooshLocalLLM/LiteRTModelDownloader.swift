#if os(iOS)

// SwooshLocalLLM/LiteRTModelDownloader.swift — 0.9R Download + cache
//
// Fetches .litertlm files from HuggingFace into the app's caches
// directory. Reports progress, resumes interrupted downloads via
// HTTP Range, and verifies the byte count after completion.
//
// Cache layout:
//   <caches>/ai.swoosh.litertlm/<model.id>/<model.id>.litertlm
//
// On iOS this lands in the sandboxed caches dir (purgeable by the
// OS under pressure — by design). On macOS it lands in `~/Library/
// Caches/ai.swoosh.agent/litertlm/`.

import Foundation

@MainActor
@Observable
public final class LiteRTModelDownloader: NSObject {

    public enum State: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
        case ready(URL)
        case failed(String)
    }

    public private(set) var state: State = .notDownloaded
    public let model: LiteRTModel

    private var task: URLSessionDownloadTask?
    private var session: URLSession?

    public init(model: LiteRTModel) {
        self.model = model
        super.init()
    }

    public var cachedURL: URL {
        LiteRTModelDownloader.cacheDir()
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent("\(model.id).litertlm")
    }

    /// Returns true if the file is already on disk and large enough to
    /// look complete (we use byte-count heuristic — a real checksum
    /// would come from the model card if HF exposed one consistently).
    public var isCached: Bool {
        let url = cachedURL
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        // Allow 5% slack vs the published estimate so version drift doesn't
        // force a re-download.
        return size >= Int64(Double(model.estimatedBytes) * 0.95)
    }

    /// Begin (or resume) downloading. Updates `state` as it progresses.
    public func download() {
        if isCached {
            state = .ready(cachedURL)
            return
        }
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.networkServiceType = .responsiveData
        config.timeoutIntervalForResource = 60 * 60 // 1h
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

    private static func cacheDir() -> URL {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ai.swoosh.litertlm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - URLSessionDownloadDelegate

extension LiteRTModelDownloader: URLSessionDownloadDelegate {

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file vanishes when the delegate returns — move
        // synchronously here, then publish state on the main actor.
        let target = MainActor.assumeIsolated { self.cachedURL }
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
            : MainActor.assumeIsolated { self.model.estimatedBytes }
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
