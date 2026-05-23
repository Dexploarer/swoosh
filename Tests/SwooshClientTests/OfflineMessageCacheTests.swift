// Tests/SwooshClientTests/OfflineMessageCacheTests.swift — 0.4A
//
// State-machine tests for `OfflineMessageCache`: append + reload, outbox
// queue ordering, drain-on-success, partial-drain on first failure, and
// tolerance of corrupted JSONL lines. The audit flagged this module as
// untested despite being the iPhone's durability layer.

import Foundation
import Testing
@testable import SwooshClient

@Suite("OfflineMessageCache")
struct OfflineMessageCacheTests {

    // MARK: - Helpers

    private func makeCache() throws -> (OfflineMessageCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-cache-\(UUID().uuidString)", isDirectory: true)
        return (try OfflineMessageCache(root: root), root)
    }

    // MARK: - Append + reload

    @Test("Append survives a re-instantiation of the cache")
    func appendSurvivesReinit() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        await cache.append(.init(sessionID: "s1", role: .user, text: "hello"))
        await cache.append(.init(sessionID: "s1", role: .agent, text: "world"))

        // New cache instance reads the same file.
        let reopened = try OfflineMessageCache(root: root)
        let recent = await reopened.recent(sessionID: "s1")
        #expect(recent.count == 2)
        #expect(recent.map(\.role) == [.user, .agent])
        #expect(recent.map(\.text) == ["hello", "world"])
    }

    @Test("Recent honours the limit and returns the newest tail")
    func recentHonoursLimit() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        for i in 0..<10 {
            await cache.append(.init(sessionID: "s1", role: .user, text: "m\(i)"))
        }
        let recent = await cache.recent(sessionID: "s1", limit: 3)
        #expect(recent.map(\.text) == ["m7", "m8", "m9"])
    }

    // MARK: - Outbox queue + drain

    @Test("Outbox queues retain their order")
    func outboxOrdering() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        await cache.queueOutbox(.init(sessionID: "s1", input: "first"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "second"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "third"))

        let pending = await cache.pendingOutbox(sessionID: "s1")
        #expect(pending.map(\.input) == ["first", "second", "third"])
    }

    @Test("Drain on success flushes the whole queue once")
    func drainOnSuccess() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        await cache.queueOutbox(.init(sessionID: "s1", input: "a"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "b"))

        let executor = SuccessExecutor()
        let flushed = await cache.drainOutbox(via: executor, sessionID: "s1")
        #expect(flushed.map(\.input) == ["a", "b"])
        #expect(await cache.pendingOutbox(sessionID: "s1").isEmpty)

        // Drained items land in the ledger as user+agent pairs.
        let messages = await cache.recent(sessionID: "s1")
        #expect(messages.map(\.role) == [.user, .agent, .user, .agent])
        #expect(messages.map(\.text) == ["a", "echo:a", "b", "echo:b"])
    }

    @Test("Drain stops at the first failure and preserves the remaining tail")
    func drainStopsOnFirstFailure() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        await cache.queueOutbox(.init(sessionID: "s1", input: "a"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "fail-here"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "c"))

        // Executor throws on the second item.
        let executor = FailAtExecutor(failingInput: "fail-here")
        let flushed = await cache.drainOutbox(via: executor, sessionID: "s1")
        #expect(flushed.map(\.input) == ["a"])

        let remaining = await cache.pendingOutbox(sessionID: "s1")
        #expect(remaining.map(\.input) == ["fail-here", "c"])
    }

    // MARK: - Corruption tolerance

    @Test("Corrupted JSONL lines are skipped without crashing")
    func toleratesCorruptedJSONL() async throws {
        let (_, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("s1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("messages.jsonl")

        // Mix valid and garbage lines.
        let valid = CachedMessage(sessionID: "s1", role: .user, text: "ok")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let validLine = try String(data: encoder.encode(valid), encoding: .utf8)!
        let body = [
            "this is not json",
            validLine,
            "{ \"missing\": \"fields\" }",
        ].joined(separator: "\n") + "\n"
        try body.write(to: path, atomically: true, encoding: .utf8)

        let cache = try OfflineMessageCache(root: root)
        let recent = await cache.recent(sessionID: "s1")
        #expect(recent.count == 1)
        #expect(recent.first?.text == "ok")
    }

    // MARK: - Clear

    @Test("Clear wipes both messages and outbox for the session")
    func clearWipesEverything() async throws {
        let (cache, root) = try makeCache()
        defer { try? FileManager.default.removeItem(at: root) }

        await cache.append(.init(sessionID: "s1", role: .user, text: "hi"))
        await cache.queueOutbox(.init(sessionID: "s1", input: "pending"))
        try await cache.clear(sessionID: "s1")

        #expect(await cache.recent(sessionID: "s1").isEmpty)
        #expect(await cache.pendingOutbox(sessionID: "s1").isEmpty)
    }
}

// MARK: - Test executors

private actor SuccessExecutor: SwooshExecutor {
    func run(_ request: ChatRequest) async throws -> ChatResponse {
        ChatResponse(message: "echo:\(request.input)", sessionID: request.sessionID)
    }
}

private actor FailAtExecutor: SwooshExecutor {
    let failingInput: String
    init(failingInput: String) { self.failingInput = failingInput }
    func run(_ request: ChatRequest) async throws -> ChatResponse {
        if request.input == failingInput {
            throw SwooshClientError.transport("simulated failure")
        }
        return ChatResponse(message: "echo:\(request.input)", sessionID: request.sessionID)
    }
}
