#if os(iOS)

// SwooshLocalLLM/FallbackExecutor.swift — 0.9R Remote → local routing
//
// SwooshExecutor that prefers the paired daemon (RemoteKernelExecutor)
// but transparently falls back to the on-device LiteRT model when the
// daemon throws. Used on iOS so chat keeps working when the Mac is off,
// the Wi-Fi is gone, or the user is on the road.
//
// Routing rules:
//   1. If `enableLocalFallback` is false, behave exactly like the inner
//      executor — never reach for the local model.
//   2. On a successful remote turn, return it.
//   3. On a remote failure with `enableLocalFallback` true:
//        a. Ensure the local model is loaded (download + initialise if
//           it hasn't happened yet — caller is expected to have nudged
//           this via `prewarm()` so the first failure isn't a 60s wait).
//        b. Generate via the local executor and return.
//   4. If the local path also fails, rethrow the original remote error
//      (so users see the more actionable network message, not a model
//      load error).

import Foundation
import SwooshClient

public actor FallbackExecutor: SwooshExecutor {

    private let remote: any SwooshExecutor
    private let local: LiteRTLocalExecutor
    private let downloader: LiteRTModelDownloader
    public var enableLocalFallback: Bool

    @MainActor public init(
        remote: any SwooshExecutor,
        model: LiteRTModel = LiteRTModelCatalog.defaultModel,
        enableLocalFallback: Bool = true
    ) {
        self.remote = remote
        self.local = LiteRTLocalExecutor(model: model)
        self.downloader = LiteRTModelDownloader(model: model)
        self.enableLocalFallback = enableLocalFallback
    }

    /// Kick off model download in the background so the first fallback
    /// doesn't pay the full latency tax. Safe to call repeatedly.
    @MainActor public func prewarm() async {
        if !downloader.isCached {
            downloader.download()
        }
    }

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        do {
            return try await remote.run(request)
        } catch let remoteError {
            guard enableLocalFallback else { throw remoteError }
            do {
                let path = await MainActor.run { downloader.cachedURL }
                let cached = await MainActor.run { downloader.isCached }
                guard cached else {
                    // Model isn't downloaded — surface the remote error
                    // since we can't fulfill the request locally either.
                    throw remoteError
                }
                try await local.ensureReady(modelPath: path)
                return try await local.run(request)
            } catch {
                // Both paths failed — rethrow the original remote error.
                throw remoteError
            }
        }
    }

    public func setLocalFallback(_ enabled: Bool) {
        enableLocalFallback = enabled
    }
}

#endif
