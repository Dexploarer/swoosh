// SwooshFiles/ApprovedRoot.swift — Approved root model (0.4C)
//
// Every file/git/swift tool operates inside an approved root.
// No absolute paths outside registered roots.

import Foundation

public struct ApprovedRoot: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let bookmarkData: Data?
    public let absolutePath: String
    public let createdAt: Date
    public let allowedRead: Bool
    public let allowedWrite: Bool

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        bookmarkData: Data? = nil,
        absolutePath: String,
        createdAt: Date = Date(),
        allowedRead: Bool = true,
        allowedWrite: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.absolutePath = absolutePath
        self.createdAt = createdAt
        self.allowedRead = allowedRead
        self.allowedWrite = allowedWrite
    }
}

// MARK: - Approved root store protocol

public protocol ApprovedRootStore: Sendable {
    func add(_ root: ApprovedRoot) async throws
    func remove(id: String) async throws
    func get(id: String) async -> ApprovedRoot?
    func list() async -> [ApprovedRoot]
    func findByPath(_ path: String) async -> ApprovedRoot?
}

// MARK: - In-memory store

public actor InMemoryRootStore: ApprovedRootStore {
    private var roots: [String: ApprovedRoot] = [:]

    public init() {}

    public func add(_ root: ApprovedRoot) { roots[root.id] = root }
    public func remove(id: String) { roots.removeValue(forKey: id) }
    public func get(id: String) -> ApprovedRoot? { roots[id] }
    public func list() -> [ApprovedRoot] { Array(roots.values).sorted { $0.displayName < $1.displayName } }
    public func findByPath(_ path: String) -> ApprovedRoot? {
        roots.values.first { $0.absolutePath == path }
    }
}
