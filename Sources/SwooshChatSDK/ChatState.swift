// SwooshChatSDK/ChatState.swift — Subscriptions, dedupe, locks, and state
import Foundation

public enum ChatLockResult: Sendable, Equatable {
    case acquired
    case conflict
}

public enum ChatLockConflictPolicy: Sendable {
    case drop
    case force
}

public protocol ChatStateAdapter: Sendable {
    func isSubscribed(threadID: ChatThreadID) async throws -> Bool
    func subscribe(threadID: ChatThreadID) async throws
    func unsubscribe(threadID: ChatThreadID) async throws
    func getThreadState<T: Decodable & Sendable>(_ type: T.Type, threadID: ChatThreadID) async throws -> T?
    func setThreadState<T: Encodable & Sendable>(_ value: T, threadID: ChatThreadID, replace: Bool, ttl: TimeInterval?) async throws
    func acquireLock(threadID: ChatThreadID, ttl: TimeInterval, force: Bool) async throws -> ChatLockResult
    func releaseLock(threadID: ChatThreadID) async throws
    func hasSeenMessage(id: String) async throws -> Bool
    func markMessageSeen(id: String, ttl: TimeInterval) async throws
}

public actor InMemoryChatStateAdapter: ChatStateAdapter {
    private var subscriptions: Set<ChatThreadID> = []
    private var states: [ChatThreadID: StoredState] = [:]
    private var locks: [ChatThreadID: Date] = [:]
    private var seenMessages: [String: Date] = [:]

    public init() {}

    public func isSubscribed(threadID: ChatThreadID) -> Bool {
        subscriptions.contains(threadID)
    }

    public func subscribe(threadID: ChatThreadID) {
        subscriptions.insert(threadID)
    }

    public func unsubscribe(threadID: ChatThreadID) {
        subscriptions.remove(threadID)
    }

    public func getThreadState<T: Decodable & Sendable>(_ type: T.Type, threadID: ChatThreadID) throws -> T? {
        guard let stored = states[threadID], stored.expiresAt.map({ $0 > Date() }) ?? true else {
            states.removeValue(forKey: threadID)
            return nil
        }
        return try JSONDecoder().decode(T.self, from: stored.data)
    }

    public func setThreadState<T: Encodable & Sendable>(_ value: T, threadID: ChatThreadID, replace: Bool, ttl: TimeInterval?) throws {
        let data = try JSONEncoder().encode(value)
        states[threadID] = StoredState(data: data, expiresAt: ttl.map { Date().addingTimeInterval($0) })
    }

    public func acquireLock(threadID: ChatThreadID, ttl: TimeInterval, force: Bool) -> ChatLockResult {
        let now = Date()
        if let expires = locks[threadID], expires > now, !force {
            return .conflict
        }
        locks[threadID] = now.addingTimeInterval(ttl)
        return .acquired
    }

    public func releaseLock(threadID: ChatThreadID) {
        locks.removeValue(forKey: threadID)
    }

    public func hasSeenMessage(id: String) -> Bool {
        let now = Date()
        seenMessages = seenMessages.filter { $0.value > now }
        return seenMessages[id] != nil
    }

    public func markMessageSeen(id: String, ttl: TimeInterval) {
        seenMessages[id] = Date().addingTimeInterval(ttl)
    }
}

private struct StoredState: Sendable {
    let data: Data
    let expiresAt: Date?
}
