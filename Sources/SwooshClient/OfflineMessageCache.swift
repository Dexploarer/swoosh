// SwooshClient/OfflineMessageCache.swift — 0.9R Cross-launch chat cache + outbox
//
// Persists chat turns and queues outgoing sends when the daemon is
// unreachable. Both iPhone and Mac use the same file format; the cache
// is the same shape on every platform (iOS doesn't have `Process` and
// must not import anything kernel-side, so this lives in `SwooshClient`).
//
// Two ledgers per session:
//   • messages.jsonl — append-only history (user + agent turns)
//   • outbox.jsonl   — pending user sends that hit "daemon offline"
//
// File location convention:
//   • macOS:  ~/Library/Application Support/ai.swoosh.agent/cache/<session>/
//   • iOS:    <container>/Library/Application Support/cache/<session>/
//
// Concurrency: actor-isolated. All reads/writes serialize through it.
//
// This is the practical floor for offline support — a full HLC + CloudKit
// merge (see Docs/iOS-Kernel-and-Sync.md) layers on top of these files
// without changing the wire types.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Records
// ═══════════════════════════════════════════════════════════════════

public struct CachedMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sessionID: String
    public let role: Role
    public let text: String
    public let timestamp: Date

    public enum Role: String, Codable, Sendable {
        case user, agent, system
    }

    public init(
        id: UUID = UUID(),
        sessionID: String,
        role: Role,
        text: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// A user send that couldn't reach the daemon and is queued for retry.
public struct OutboxItem: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sessionID: String
    public let input: String
    public let queuedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        input: String,
        queuedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.input = input
        self.queuedAt = queuedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cache
// ═══════════════════════════════════════════════════════════════════

public actor OfflineMessageCache {

    private let root: URL
    private let fm = FileManager.default

    // In-memory mirrors keyed by session — populated on first touch.
    private var loaded: Set<String> = []
    private var messages: [String: [CachedMessage]] = [:]
    private var outbox:   [String: [OutboxItem]] = [:]

    // ── Init ─────────────────────────────────────────────────────────

    /// Build at the default app-support location (`ai.swoosh.agent/cache`).
    public init() throws {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.root = base.appendingPathComponent("ai.swoosh.agent/cache", isDirectory: true)
        try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// Build at an explicit root (mostly for tests).
    public init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    // ── Read ─────────────────────────────────────────────────────────

    /// Most-recent `limit` messages for a session, oldest-first.
    public func recent(sessionID: String, limit: Int = 100) -> [CachedMessage] {
        loadIfNeeded(sessionID: sessionID)
        let all = messages[sessionID] ?? []
        if all.count <= limit { return all }
        return Array(all.suffix(limit))
    }

    /// All currently queued sends for a session, oldest-first.
    public func pendingOutbox(sessionID: String) -> [OutboxItem] {
        loadIfNeeded(sessionID: sessionID)
        return outbox[sessionID] ?? []
    }

    // ── Append ───────────────────────────────────────────────────────

    /// Append a message to the session ledger and flush to disk.
    public func append(_ message: CachedMessage) {
        loadIfNeeded(sessionID: message.sessionID)
        messages[message.sessionID, default: []].append(message)
        appendJSONL(message, to: messagesURL(sessionID: message.sessionID))
    }

    /// Queue a send that couldn't reach the daemon.
    public func queueOutbox(_ item: OutboxItem) {
        loadIfNeeded(sessionID: item.sessionID)
        outbox[item.sessionID, default: []].append(item)
        appendJSONL(item, to: outboxURL(sessionID: item.sessionID))
    }

    // ── Drain ────────────────────────────────────────────────────────

    /// Try to flush every queued send through `executor`. On success the
    /// agent's reply is appended to the message ledger like a normal turn.
    /// Failed items remain in the outbox in order; the first failure stops
    /// the drain (so user sees the same order they queued in).
    ///
    /// Returns the items that were successfully flushed. Caller can use
    /// the count to surface a "↻ replayed N messages" hint.
    @discardableResult
    public func drainOutbox(
        via executor: any SwooshExecutor,
        sessionID: String
    ) async -> [OutboxItem] {
        loadIfNeeded(sessionID: sessionID)
        let queue = outbox[sessionID] ?? []
        guard !queue.isEmpty else { return [] }

        var flushed: [OutboxItem] = []
        for item in queue {
            do {
                let response = try await executor.run(
                    ChatRequest(sessionID: item.sessionID, input: item.input)
                )
                // Both sides land in the ledger so the transcript reads
                // naturally on next launch.
                append(.init(sessionID: item.sessionID, role: .user, text: item.input))
                append(.init(sessionID: item.sessionID, role: .agent, text: response.message))
                flushed.append(item)
            } catch {
                // Stop on first failure — preserve send order.
                break
            }
        }

        if !flushed.isEmpty {
            // Remove flushed items from the queue and rewrite the file.
            let remaining = (outbox[sessionID] ?? []).filter { item in
                !flushed.contains(where: { $0.id == item.id })
            }
            outbox[sessionID] = remaining
            rewriteJSONL(remaining, to: outboxURL(sessionID: sessionID))
        }
        return flushed
    }

    // ── Maintenance ──────────────────────────────────────────────────

    /// Clear everything for one session (history + outbox).
    public func clear(sessionID: String) throws {
        messages[sessionID] = []
        outbox[sessionID] = []
        try? fm.removeItem(at: messagesURL(sessionID: sessionID))
        try? fm.removeItem(at: outboxURL(sessionID: sessionID))
    }

    // ── Files ────────────────────────────────────────────────────────

    private func sessionDir(_ sessionID: String) -> URL {
        let safe = sessionID.replacingOccurrences(of: "/", with: "_")
        let dir = root.appendingPathComponent(safe, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func messagesURL(sessionID: String) -> URL {
        sessionDir(sessionID).appendingPathComponent("messages.jsonl")
    }

    private func outboxURL(sessionID: String) -> URL {
        sessionDir(sessionID).appendingPathComponent("outbox.jsonl")
    }

    private func loadIfNeeded(sessionID: String) {
        guard !loaded.contains(sessionID) else { return }
        loaded.insert(sessionID)
        messages[sessionID] = readJSONL(messagesURL(sessionID: sessionID))
        outbox[sessionID]   = readJSONL(outboxURL(sessionID: sessionID))
    }

    private func readJSONL<T: Decodable>(_ url: URL) -> [T] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(T.self, from: d)
        }
    }

    private func appendJSONL<T: Encodable>(_ item: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return }
        let line = data + Data([0x0A])  // newline
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    private func rewriteJSONL<T: Encodable>(_ items: [T], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = items
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}
