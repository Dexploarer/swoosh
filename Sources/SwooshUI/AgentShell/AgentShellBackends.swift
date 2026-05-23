// SwooshUI/AgentShell/AgentShellBackends.swift — 0.9R Real send handlers
//
// Replaces the default echo placeholder on `AgentShellModel.send` with
// production handlers. Two are provided:
//
//   • swooshExecutorBackend — wraps a SwooshExecutor (currently the
//     `RemoteKernelExecutor` over `/api/agent/chat`). Once an in-process
//     LocalKernelExecutor ships, the same handler works without change.
//   • offlineCachedBackend — wraps any executor with an outbox: when the
//     send fails (no daemon reachable), the message is queued locally
//     and replayed on the next successful turn or app launch. See
//     `SwooshClient/OfflineMessageCache.swift`.
//
// Usage at App root:
//   shell.send = AgentShellBackends.offlineCached(
//       executor: RemoteKernelExecutor(client: client),
//       sessionID: "default"
//   )

import Foundation
import SwooshClient
import SwooshModels

public enum AgentShellBackends {

    /// Maps a `ChatResponse.modelUsed` string to a display name when the
    /// response was served by a known on-device fallback model. Return nil
    /// for daemon-served turns so no badge appears. Callers on iOS pass a
    /// closure backed by `LiteRTModelCatalog`; macOS leaves it nil.
    public typealias LocalModelClassifier = @Sendable (String) -> String?

    /// Direct executor backend. No offline buffering — if the daemon is
    /// unreachable, the send surfaces as an error message in the chat.
    public static func swooshExecutor(
        _ executor: any SwooshExecutor,
        sessionID: String = "default",
        localModelClassifier: LocalModelClassifier? = nil
    ) -> AgentSendHandler {
        return { @MainActor text, shell in
            let request = chatRequest(sessionID: sessionID, input: text, shell: shell)
            do {
                let response = try await executor.run(request)
                let localName = localModelClassifier?(response.modelUsed)
                shell.messages.append(
                    .init(role: .agent, text: response.message, localModelName: localName)
                )
            } catch {
                shell.messages.append(
                    .init(role: .agent,
                          text: "⚠ Couldn't reach daemon: \(error.localizedDescription)")
                )
            }
        }
    }

    /// Offline-cached backend: identical to `swooshExecutor` on the happy
    /// path, but queues the user turn in an `OfflineMessageCache` when the
    /// executor throws, and persists every successful turn locally so the
    /// transcript is available across launches even without the daemon.
    ///
    /// `cache` is supplied so the same one can also be loaded at app
    /// startup to restore prior messages — see `SwooshClient`'s
    /// `OfflineMessageCache` for the file location convention.
    public static func offlineCached(
        executor: any SwooshExecutor,
        cache: OfflineMessageCache,
        sessionID: String = "default",
        localModelClassifier: LocalModelClassifier? = nil
    ) -> AgentSendHandler {
        return { @MainActor text, shell in
            // Persist user turn locally immediately so it survives a
            // crash/relaunch even before the server replies.
            await cache.append(
                .init(sessionID: sessionID, role: .user, text: text)
            )

            let request = chatRequest(sessionID: sessionID, input: text, shell: shell)
            do {
                let response = try await executor.run(request)
                let localName = localModelClassifier?(response.modelUsed)
                shell.messages.append(
                    .init(role: .agent, text: response.message, localModelName: localName)
                )
                shell.syncState = .online
                await cache.append(
                    .init(sessionID: sessionID, role: .agent, text: response.message)
                )
                // Successful turn — flush any prior queued sends.
                let flushed = await cache.drainOutbox(via: executor, sessionID: sessionID)
                if !flushed.isEmpty {
                    shell.messages.append(
                        .init(role: .agent,
                              text: "↻ Replayed \(flushed.count) queued message(s).")
                    )
                }
            } catch {
                // Daemon unreachable — queue for later.
                await cache.queueOutbox(
                    .init(
                        sessionID: sessionID,
                        input: text,
                        model: request.model,
                        providerID: request.providerID
                    )
                )
                let pending = await cache.pendingOutbox(sessionID: sessionID).count
                shell.syncState = .queued(pending)
                shell.messages.append(
                    .init(role: .agent,
                          text: "⚠ Offline. Queued for delivery when daemon is back.")
                )
            }
        }
    }

    /// Restore prior chat history from the cache into the shell. Call at
    /// app start, after `shell.send` is configured, so the user sees the
    /// thread they were last looking at — even with no daemon.
    @MainActor
    public static func restore(
        into shell: AgentShellModel,
        from cache: OfflineMessageCache,
        sessionID: String = "default",
        limit: Int = 100
    ) async {
        let cached = await cache.recent(sessionID: sessionID, limit: limit)
        shell.messages = cached.map { record in
            AgentShellMessage(
                id: record.id,
                role: record.role == .user ? .user : .agent,
                text: record.text,
                timestamp: record.timestamp
            )
        }
    }

    /// One-shot boot path used by the macOS host. Builds an
    /// `OfflineMessageCache`, configures the shell's `send` to the
    /// offline-cached backend pointing at the local daemon, restores
    /// prior history, and tries to drain any outbox left over from a
    /// previous offline window.
    ///
    /// Safe to call even when the daemon isn't running — the offline
    /// cache still loads, sends queue, and the user sees yesterday's
    /// transcript immediately.
    @MainActor
    public static func bootLocalDaemon(
        shell: AgentShellModel,
        host: URL? = nil,
        bearerToken: String? = nil,
        sessionID: String = "default"
    ) async {
        // Build cache. If app-support is unavailable (sandboxing edge
        // case), fall back to the temp dir so we at least preserve state
        // for the current launch.
        let cache: OfflineMessageCache
        do {
            cache = try OfflineMessageCache()
        } catch {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ai.swoosh.fallback-cache", isDirectory: true)
            // swiftlint:disable:next force_try
            cache = try! OfflineMessageCache(root: tmp)
        }

        // Restore history immediately so the user sees yesterday's
        // conversation even if the daemon never answers.
        await restore(into: shell, from: cache, sessionID: sessionID)

        // Wire executor + cached backend.
        let endpoint = SwooshDaemonClient.endpoint()
        let baseURL = host ?? endpoint?.baseURL ?? URL(string: "http://127.0.0.1:8787")!
        let token = bearerToken ?? endpoint?.token ?? SwooshDaemonClient.token()
        let client = SwooshAPIClient(baseURL: baseURL, token: token)
        let executor = RemoteKernelExecutor(client: client)
        shell.send = offlineCached(
            executor: executor,
            cache: cache,
            sessionID: sessionID
        )

        // Try to drain any outbox left from a previous offline window
        // without surfacing errors — if the daemon is down, nothing
        // happens and the items remain queued.
        let flushed = await cache.drainOutbox(via: executor, sessionID: sessionID)
        if !flushed.isEmpty {
            shell.syncState = .online
            shell.messages.append(
                .init(role: .agent,
                      text: "↻ Delivered \(flushed.count) message(s) queued while offline.")
            )
        } else {
            // Probe daemon health so the badge reads accurately before
            // the first user send.
            let healthy = await client.health()
            let queued = await cache.pendingOutbox(sessionID: sessionID).count
            shell.syncState = healthy
                ? .online
                : (queued > 0 ? .queued(queued) : .offline)
        }
    }

}

@MainActor
private func chatRequest(sessionID: String, input: String, shell: AgentShellModel) -> ChatRequest {
    guard let route = UnifiedModelCatalog.route(forCatalogID: shell.selectedModelID) else {
        return ChatRequest(sessionID: sessionID, input: input)
    }
    return ChatRequest(
        sessionID: sessionID,
        input: input,
        model: route.modelID,
        providerID: route.providerID
    )
}
