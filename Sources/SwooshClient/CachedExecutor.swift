// SwooshClient/CachedExecutor.swift — Offline-aware executor decorator
//
// Wraps any `SwooshExecutor` with:
//   • Local append-only message ledger via `OfflineMessageCache`.
//   • Outbox queue for sends that hit "daemon unreachable".
//   • Automatic drain on the next successful turn.
//
// Cross-platform — both the macOS shell (via `AgentShellBackends`) and
// the iOS `ChatScreen` use this. The iPhone gains durable chat history
// across launches and offline send-then-deliver out of the box.
//
//   let inner = RemoteKernelExecutor(client: client)
//   let exec  = try CachedExecutor(inner: inner, sessionID: "default")
//   try await exec.run(ChatRequest(input: "hello"))

import Foundation

public actor CachedExecutor: SwooshExecutor {

    private let inner: any SwooshExecutor
    private let cache: OfflineMessageCache
    private let sessionID: String

    // Sync-state observer. Set this from the host (the shell, ChatScreen)
    // to receive transitions between online / offline / queued.
    public var onSyncStateChange: (@Sendable (CachedExecutorSyncState) -> Void)?

    public init(
        inner: any SwooshExecutor,
        cache: OfflineMessageCache,
        sessionID: String = "default"
    ) {
        self.inner = inner
        self.cache = cache
        self.sessionID = sessionID
    }

    /// Convenience: builds a default-location cache.
    public init(
        inner: any SwooshExecutor,
        sessionID: String = "default"
    ) throws {
        self.inner = inner
        self.cache = try OfflineMessageCache()
        self.sessionID = sessionID
    }

    public func setSyncObserver(_ observer: (@Sendable (CachedExecutorSyncState) -> Void)?) {
        self.onSyncStateChange = observer
    }

    // ── Executor protocol ───────────────────────────────────────────

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        let effectiveSession = request.sessionID.isEmpty ? sessionID : request.sessionID

        // Persist the user turn immediately so it survives a crash even
        // before the server replies.
        await cache.append(
            .init(sessionID: effectiveSession, role: .user, text: request.input)
        )

        do {
            let response = try await inner.run(request)
            await cache.append(
                .init(sessionID: effectiveSession,
                      role: .agent,
                      text: response.message)
            )
            // Successful turn — drain any earlier outbox.
            let flushed = await cache.drainOutbox(via: inner, sessionID: effectiveSession)
            onSyncStateChange?(.online(flushed: flushed.count))
            return response
        } catch {
            // Daemon unreachable — queue for later, re-throw so the
            // caller can render their own error UI.
            await cache.queueOutbox(
                .init(sessionID: effectiveSession, input: request.input)
            )
            let pending = await cache.pendingOutbox(sessionID: effectiveSession).count
            onSyncStateChange?(.queued(pending))
            throw error
        }
    }

    // ── Read-side helpers ──────────────────────────────────────────

    public func recentMessages(limit: Int = 100) async -> [CachedMessage] {
        await cache.recent(sessionID: sessionID, limit: limit)
    }

    public func pendingOutboxCount() async -> Int {
        await cache.pendingOutbox(sessionID: sessionID).count
    }

    /// Manually attempt to drain the outbox without sending a new turn.
    /// Useful from a pull-to-refresh or "reconnect" tap.
    @discardableResult
    public func drainOutbox() async -> [OutboxItem] {
        let flushed = await cache.drainOutbox(via: inner, sessionID: sessionID)
        let pending = await cache.pendingOutbox(sessionID: sessionID).count
        if pending == 0 {
            onSyncStateChange?(.online(flushed: flushed.count))
        } else {
            onSyncStateChange?(.queued(pending))
        }
        return flushed
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sync state
// ═══════════════════════════════════════════════════════════════════

/// State transitions the cached executor surfaces to its host.
public enum CachedExecutorSyncState: Sendable, Equatable {
    /// Last call succeeded. `flushed` is the count of outbox items that
    /// were also delivered as a side effect.
    case online(flushed: Int)
    /// Daemon unreachable; `n` items now waiting in the outbox.
    case queued(Int)
}
