// Tests/SwooshClientTests/CachedExecutorTests.swift — 0.4A
//
// Behavioural tests for `CachedExecutor` — the wrapper that adds an
// offline ledger + outbox to any `SwooshExecutor`. The audit flagged
// this module as untested; these tests pin the queue-on-failure,
// drain-on-success, and single-append-per-outbox-item invariants.

import Foundation
import Testing
@testable import SwooshClient

@Suite("CachedExecutor")
struct CachedExecutorTests {

    // MARK: - Helpers

    private func makeCache() throws -> (OfflineMessageCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-exec-\(UUID().uuidString)", isDirectory: true)
        return (try OfflineMessageCache(root: root), root)
    }

    // MARK: - Happy path

    @Test("Successful run appends user + agent turns to the ledger")
    func successAppendsUserAndAgent() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = SuccessExecutor()
        let executor = CachedExecutor(inner: inner, cache: cache, sessionID: "s1")

        let response = try await executor.run(ChatRequest(sessionID: "s1", input: "hi"))
        #expect(response.message == "echo:hi")

        let messages = await cache.recent(sessionID: "s1")
        #expect(messages.map(\.role) == [.user, .agent])
        #expect(messages.map(\.text) == ["hi", "echo:hi"])
    }

    // MARK: - Offline / outbox

    @Test("Transport failure queues the turn and re-throws")
    func failureQueuesAndRethrows() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = AlwaysFailExecutor()
        let executor = CachedExecutor(inner: inner, cache: cache, sessionID: "s1")

        do {
            _ = try await executor.run(ChatRequest(sessionID: "s1", input: "offline-send"))
            Issue.record("expected throw")
        } catch is SwooshClientError {
            // expected
        }

        // User turn is still preserved in the ledger so the UI can
        // render it; agent turn was never appended.
        let messages = await cache.recent(sessionID: "s1")
        #expect(messages.map(\.role) == [.user])
        #expect(messages.map(\.text) == ["offline-send"])

        // The outbox has the pending send.
        let pending = await cache.pendingOutbox(sessionID: "s1")
        #expect(pending.map(\.input) == ["offline-send"])
        #expect(await executor.pendingOutboxCount() == 1)
    }

    // MARK: - Drain invariant

    @Test("Successful turn drains the outbox without double-appending the new turn")
    func drainOnSuccessNoDoubleAppend() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        // Seed the outbox with two pending sends.
        await cache.queueOutbox(.init(sessionID: "s1", input: "queued-1"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "queued-2"))

        let inner = SuccessExecutor()
        let executor = CachedExecutor(inner: inner, cache: cache, sessionID: "s1")
        let recorder = SyncStateRecorder()
        await executor.setSyncObserver { state in recorder.record(state) }

        let response = try await executor.run(ChatRequest(sessionID: "s1", input: "live-turn"))
        #expect(response.message == "echo:live-turn")

        // The live turn should appear once as user + once as agent.
        // The two outbox items each appear exactly once as user + once
        // as agent. Total: 6 messages, order: live-user, live-agent,
        // q1-user, q1-agent, q2-user, q2-agent.
        let messages = await cache.recent(sessionID: "s1")
        #expect(messages.map(\.role) == [.user, .agent, .user, .agent, .user, .agent])
        #expect(messages.map(\.text) == [
            "live-turn", "echo:live-turn",
            "queued-1", "echo:queued-1",
            "queued-2", "echo:queued-2",
        ])

        // No duplicate user-of-live-turn from drain reusing inner.
        let liveTurnCount = messages.filter { $0.text == "live-turn" }.count
        #expect(liveTurnCount == 1)

        // Outbox is empty after drain.
        #expect(await executor.pendingOutboxCount() == 0)

        // Observer saw exactly one `.online(flushed: 2)` transition.
        #expect(recorder.snapshot() == [.online(flushed: 2)])
    }

    @Test("Manual drainOutbox flushes without sending a new turn")
    func manualDrainOutbox() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        await cache.queueOutbox(.init(sessionID: "s1", input: "queued"))

        let inner = SuccessExecutor()
        let executor = CachedExecutor(inner: inner, cache: cache, sessionID: "s1")

        let flushed = await executor.drainOutbox()
        #expect(flushed.map(\.input) == ["queued"])
        #expect(await executor.pendingOutboxCount() == 0)
        let messages = await cache.recent(sessionID: "s1")
        #expect(messages.map(\.text) == ["queued", "echo:queued"])
    }

    @Test("Sync observer reports queued state on transport failure")
    func observerReportsQueued() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = AlwaysFailExecutor()
        let executor = CachedExecutor(inner: inner, cache: cache, sessionID: "s1")
        let recorder = SyncStateRecorder()
        await executor.setSyncObserver { state in recorder.record(state) }

        _ = try? await executor.run(ChatRequest(sessionID: "s1", input: "first"))
        _ = try? await executor.run(ChatRequest(sessionID: "s1", input: "second"))

        #expect(recorder.snapshot() == [.queued(1), .queued(2)])
    }
}

// Thread-safe synchronous recorder for `CachedExecutorSyncState` events.
// Using NSLock instead of an actor keeps the observer closure
// synchronous and preserves the exact order events fire in.
private final class SyncStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CachedExecutorSyncState] = []
    func record(_ state: CachedExecutorSyncState) {
        lock.lock(); defer { lock.unlock() }
        events.append(state)
    }
    func snapshot() -> [CachedExecutorSyncState] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

// MARK: - Test executors

private actor SuccessExecutor: SwooshExecutor {
    func run(_ request: ChatRequest) async throws -> ChatResponse {
        ChatResponse(message: "echo:\(request.input)", sessionID: request.sessionID)
    }
}

private actor AlwaysFailExecutor: SwooshExecutor {
    func run(_ request: ChatRequest) async throws -> ChatResponse {
        throw SwooshClientError.transport("offline")
    }
}
