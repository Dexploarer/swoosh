// SwooshVault/Vault.swift — Memory Vault
//
// Swoosh lets the user govern what it remembers.
// Transparent. Editable. Deletable. Auditable. Confidence-scored.

import Foundation
import SwooshTools

// MARK: - Memory item

public struct MemoryItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public var category: MemoryCategory
    public var content: String
    public var confidence: MemoryConfidence
    public var source: MemorySource
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var expiresAt: Date?
    public var isSensitive: Bool
    public var excludedContexts: [String]

    public init(
        id: UUID = UUID(),
        category: MemoryCategory,
        content: String,
        confidence: MemoryConfidence = .medium,
        source: MemorySource,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        expiresAt: Date? = nil,
        isSensitive: Bool = false,
        excludedContexts: [String] = []
    ) {
        self.id = id
        self.category = category
        self.content = content
        self.confidence = confidence
        self.source = source
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.expiresAt = expiresAt
        self.isSensitive = isSensitive
        self.excludedContexts = excludedContexts
    }
}


// MARK: - Categories
// MemoryCategory is defined in SwooshTools/Types.swift


public enum MemoryConfidence: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high
    case certain

    public static func < (lhs: MemoryConfidence, rhs: MemoryConfidence) -> Bool {
        let order: [MemoryConfidence] = [.low, .medium, .high, .certain]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct MemorySource: Codable, Sendable {
    public let sessionID: String?
    public let platform: String?
    public let date: Date
    public let description: String

    public init(sessionID: String? = nil, platform: String? = nil, date: Date = Date(), description: String) {
        self.sessionID = sessionID
        self.platform = platform
        self.date = date
        self.description = description
    }
}

// MARK: - Vault actor

/// The user-governed memory system.
/// Every memory is inspectable, editable, deletable, and auditable.
public actor MemoryVault {
    private var memories: [UUID: MemoryItem] = [:]
    private let auditLog: any AuditLogging

    public init(auditLog: any AuditLogging) {
        self.auditLog = auditLog
    }

    // ── Read ───────────────────────────────────────────────────────

    public func recall(query: String, context: String? = nil, limit: Int = 20) -> [MemoryItem] {
        let now = Date()
        return memories.values
            .filter { item in
                // Exclude expired
                if let exp = item.expiresAt, exp < now { return false }
                // Exclude by context
                if let ctx = context, item.excludedContexts.contains(ctx) { return false }
                // Simple text match (real impl would use embeddings / FTS)
                return item.content.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.useCount > $1.useCount }
            .prefix(limit)
            .map { $0 }
    }

    public func allMemories() -> [MemoryItem] {
        Array(memories.values).sorted { $0.createdAt > $1.createdAt }
    }

    public func memory(id: UUID) -> MemoryItem? {
        memories[id]
    }

    public func memoriesByCategory(_ category: MemoryCategory) -> [MemoryItem] {
        memories.values.filter { $0.category == category }.sorted { $0.createdAt > $1.createdAt }
    }

    // ── Write ──────────────────────────────────────────────────────

    public func store(_ item: MemoryItem) async {
        memories[item.id] = item
        try? await auditLog.append(AuditEntry(kind: .memoryApproved, detail: "Stored: \(item.content.prefix(80))"))
    }

    public func update(id: UUID, content: String? = nil, confidence: MemoryConfidence? = nil, category: MemoryCategory? = nil) async {
        guard var item = memories[id] else { return }
        if let c = content { item.content = c }
        if let conf = confidence { item.confidence = conf }
        if let cat = category { item.category = cat }
        memories[id] = item
        try? await auditLog.append(AuditEntry(kind: .memoryEdited, detail: "Updated: \(item.id)"))
    }

    public func delete(id: UUID) async {
        if let item = memories.removeValue(forKey: id) {
            try? await auditLog.append(AuditEntry(kind: .memoryRejected, detail: "Deleted: \(item.content.prefix(80))"))
        }
    }

    public func markUsed(id: UUID) {
        guard var item = memories[id] else { return }
        item.useCount += 1
        item.lastUsedAt = Date()
        memories[id] = item
    }

    // ── Exclude ────────────────────────────────────────────────────

    public func exclude(id: UUID, from context: String) {
        guard var item = memories[id] else { return }
        if !item.excludedContexts.contains(context) {
            item.excludedContexts.append(context)
            memories[id] = item
        }
    }

    // ── Expiry ─────────────────────────────────────────────────────

    public func pruneExpired() async {
        let now = Date()
        let expired = memories.filter { _, item in
            if let exp = item.expiresAt { return exp < now }
            return false
        }
        for (id, item) in expired {
            memories.removeValue(forKey: id)
            try? await auditLog.append(AuditEntry(kind: .memoryRejected, detail: "Expired: \(item.content.prefix(80))"))
        }
    }
}
