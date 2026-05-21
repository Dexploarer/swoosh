// Tests/SwooshVaultTests/VaultTests.swift — MemoryVault domain + actor
//
// MemoryVault is the user-governed memory system. Every operation must
// be observable, undoable, and audited. These tests verify the data
// model, CRUD operations, expiry, context exclusion, and that mutations
// flow through the audit log.

import Testing
import Foundation
@testable import SwooshVault
@testable import SwooshTools
@testable import SwooshFirewall

// MARK: - MemoryConfidence

@Suite("MemoryConfidence")
struct MemoryConfidenceTests {

    @Test("Comparable ordering low < medium < high < certain")
    func ordering() {
        #expect(MemoryConfidence.low < .medium)
        #expect(MemoryConfidence.medium < .high)
        #expect(MemoryConfidence.high < .certain)
        #expect(MemoryConfidence.low < .certain)
    }

    @Test("Equality")
    func equality() {
        #expect(MemoryConfidence.high == .high)
        #expect(MemoryConfidence.high != .medium)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let value = MemoryConfidence.certain
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(MemoryConfidence.self, from: data)
        #expect(decoded == .certain)
    }

    @Test("Raw values are stable strings")
    func rawValues() {
        #expect(MemoryConfidence.low.rawValue == "low")
        #expect(MemoryConfidence.medium.rawValue == "medium")
        #expect(MemoryConfidence.high.rawValue == "high")
        #expect(MemoryConfidence.certain.rawValue == "certain")
    }
}

// MARK: - MemorySource

@Suite("MemorySource")
struct MemorySourceTests {

    @Test("Stores all fields")
    func storesFields() {
        let date = Date()
        let source = MemorySource(
            sessionID: "sess-1",
            platform: "macos",
            date: date,
            description: "test source"
        )
        #expect(source.sessionID == "sess-1")
        #expect(source.platform == "macos")
        #expect(source.date == date)
        #expect(source.description == "test source")
    }

    @Test("Optional fields default to nil")
    func defaultsNil() {
        let source = MemorySource(description: "minimal")
        #expect(source.sessionID == nil)
        #expect(source.platform == nil)
        #expect(source.description == "minimal")
    }

    @Test("Codable round-trip")
    func codable() throws {
        let source = MemorySource(sessionID: "s", platform: "ios", description: "d")
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(MemorySource.self, from: data)
        #expect(decoded.sessionID == "s")
        #expect(decoded.platform == "ios")
        #expect(decoded.description == "d")
    }
}

// MARK: - MemoryItem

@Suite("MemoryItem")
struct MemoryItemTests {

    @Test("Default initialization")
    func defaults() {
        let item = MemoryItem(
            category: .preference,
            content: "Likes dark mode",
            source: MemorySource(description: "scout")
        )
        #expect(item.confidence == .medium)
        #expect(item.useCount == 0)
        #expect(item.lastUsedAt == nil)
        #expect(item.expiresAt == nil)
        #expect(item.isSensitive == false)
        #expect(item.excludedContexts.isEmpty)
    }

    @Test("Identifiable id is stable")
    func idStable() {
        let uuid = UUID()
        let item = MemoryItem(
            id: uuid,
            category: .preference,
            content: "x",
            source: MemorySource(description: "s")
        )
        #expect(item.id == uuid)
    }

    @Test("Codable round-trip")
    func codable() throws {
        let item = MemoryItem(
            category: .preference,
            content: "Uses zsh",
            confidence: .high,
            source: MemorySource(description: "scout"),
            useCount: 3,
            isSensitive: false,
            excludedContexts: ["public-demo"]
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MemoryItem.self, from: data)
        #expect(decoded.content == "Uses zsh")
        #expect(decoded.confidence == .high)
        #expect(decoded.useCount == 3)
        #expect(decoded.excludedContexts == ["public-demo"])
    }
}

// MARK: - MemoryVault store / recall

private func makeItem(
    _ content: String,
    category: MemoryCategory = .preference,
    expiresAt: Date? = nil,
    excludedContexts: [String] = []
) -> MemoryItem {
    MemoryItem(
        category: category,
        content: content,
        source: MemorySource(description: "test"),
        expiresAt: expiresAt,
        excludedContexts: excludedContexts
    )
}

@Suite("MemoryVault Store and Recall")
struct MemoryVaultStoreTests {

    @Test("Empty vault returns no memories")
    func emptyVault() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        #expect(await vault.allMemories().isEmpty)
        #expect(await vault.recall(query: "anything").isEmpty)
    }

    @Test("Store adds an item")
    func storeAdds() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        let item = makeItem("Likes vim")
        await vault.store(item)

        let all = await vault.allMemories()
        #expect(all.count == 1)
        #expect(all[0].id == item.id)
    }

    @Test("Store emits memoryApproved audit entry")
    func storeAudits() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        await vault.store(makeItem("audit me"))

        let entries = await audit.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].kind == .memoryApproved)
        #expect(entries[0].detail.contains("audit me"))
    }

    @Test("Recall matches case-insensitive substring")
    func recallMatches() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("Likes DARK mode"))
        await vault.store(makeItem("Uses zsh shell"))

        let hits = await vault.recall(query: "dark")
        #expect(hits.count == 1)
        #expect(hits[0].content.contains("DARK"))
    }

    @Test("Recall respects limit")
    func recallLimit() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        for i in 0..<10 {
            await vault.store(makeItem("item \(i) matches query"))
        }
        let hits = await vault.recall(query: "matches", limit: 3)
        #expect(hits.count == 3)
    }

    @Test("Recall sorts by useCount descending")
    func recallSortsByUseCount() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let lowID = UUID()
        let hiID = UUID()
        await vault.store(MemoryItem(
            id: lowID, category: .preference, content: "match low",
            source: MemorySource(description: "s"), useCount: 1
        ))
        await vault.store(MemoryItem(
            id: hiID, category: .preference, content: "match high",
            source: MemorySource(description: "s"), useCount: 10
        ))

        let hits = await vault.recall(query: "match")
        #expect(hits.count == 2)
        #expect(hits[0].id == hiID)
        #expect(hits[1].id == lowID)
    }

    @Test("Recall excludes expired items")
    func recallSkipsExpired() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("fresh", expiresAt: Date().addingTimeInterval(3600)))
        await vault.store(makeItem("stale", expiresAt: Date().addingTimeInterval(-3600)))

        let allFresh = await vault.recall(query: "fresh")
        let allStale = await vault.recall(query: "stale")
        #expect(allFresh.count == 1)
        #expect(allStale.isEmpty)
    }

    @Test("Recall excludes items with matching excludedContexts")
    func recallRespectsContextExclusion() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("private info", excludedContexts: ["public-demo"]))

        let withContext = await vault.recall(query: "private", context: "public-demo")
        let withoutContext = await vault.recall(query: "private", context: "internal")
        #expect(withContext.isEmpty)
        #expect(withoutContext.count == 1)
    }
}

@Suite("MemoryVault Queries")
struct MemoryVaultQueryTests {

    @Test("memory(id:) returns the item")
    func memoryByID() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("findable")
        await vault.store(item)
        let found = await vault.memory(id: item.id)
        #expect(found?.id == item.id)
    }

    @Test("memory(id:) returns nil for unknown id")
    func memoryUnknownID() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        #expect(await vault.memory(id: UUID()) == nil)
    }

    @Test("memoriesByCategory filters")
    func memoriesByCategory() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("a pref", category: .preference))
        await vault.store(makeItem("a tool", category: .toolQuirk))

        let prefs = await vault.memoriesByCategory(.preference)
        let tools = await vault.memoriesByCategory(.toolQuirk)
        #expect(prefs.count == 1)
        #expect(tools.count == 1)
    }

    @Test("allMemories sorts newest first")
    func allMemoriesSorted() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let older = MemoryItem(
            category: .preference, content: "older",
            source: MemorySource(description: "s"),
            createdAt: Date(timeIntervalSinceNow: -100)
        )
        let newer = MemoryItem(
            category: .preference, content: "newer",
            source: MemorySource(description: "s"),
            createdAt: Date()
        )
        await vault.store(older)
        await vault.store(newer)

        let all = await vault.allMemories()
        #expect(all[0].content == "newer")
        #expect(all[1].content == "older")
    }
}

// MARK: - MemoryVault mutations

@Suite("MemoryVault Mutations")
struct MemoryVaultMutationTests {

    @Test("Update mutates only specified fields")
    func partialUpdate() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("original")
        await vault.store(item)

        await vault.update(id: item.id, content: "edited")
        let updated = await vault.memory(id: item.id)
        #expect(updated?.content == "edited")
        #expect(updated?.confidence == .medium) // unchanged
        #expect(updated?.category == .preference) // unchanged
    }

    @Test("Update mutates confidence and category")
    func updateConfidence() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("x")
        await vault.store(item)
        await vault.update(id: item.id, confidence: .certain, category: .toolQuirk)
        let updated = await vault.memory(id: item.id)
        #expect(updated?.confidence == .certain)
        #expect(updated?.category == .toolQuirk)
    }

    @Test("Update unknown id is a no-op")
    func updateUnknown() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.update(id: UUID(), content: "ignored")
        #expect(await vault.allMemories().isEmpty)
    }

    @Test("Update emits memoryEdited audit entry")
    func updateAudits() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        let item = makeItem("x")
        await vault.store(item)
        await vault.update(id: item.id, content: "y")

        let kinds = await audit.allEntries().map(\.kind)
        #expect(kinds.contains(.memoryEdited))
    }

    @Test("Delete removes the item")
    func deleteRemoves() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("doomed")
        await vault.store(item)
        await vault.delete(id: item.id)
        #expect(await vault.memory(id: item.id) == nil)
    }

    @Test("Delete emits memoryRejected audit entry")
    func deleteAudits() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        let item = makeItem("doomed")
        await vault.store(item)
        await vault.delete(id: item.id)

        let kinds = await audit.allEntries().map(\.kind)
        #expect(kinds.contains(.memoryRejected))
    }

    @Test("Delete unknown id is a no-op")
    func deleteUnknown() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        await vault.delete(id: UUID())
        // Only no entries (no memoryRejected event since nothing was removed)
        let entries = await audit.allEntries()
        #expect(entries.isEmpty)
    }

    @Test("markUsed increments use count and sets lastUsedAt")
    func markUsed() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("popular")
        await vault.store(item)
        await vault.markUsed(id: item.id)
        await vault.markUsed(id: item.id)
        let updated = await vault.memory(id: item.id)
        #expect(updated?.useCount == 2)
        #expect(updated?.lastUsedAt != nil)
    }

    @Test("markUsed unknown id is a no-op")
    func markUsedUnknown() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.markUsed(id: UUID())
        #expect(await vault.allMemories().isEmpty)
    }
}

// MARK: - Exclusion

@Suite("MemoryVault Context Exclusion")
struct MemoryVaultExclusionTests {

    @Test("exclude adds context to excludedContexts")
    func excludeAdds() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("x")
        await vault.store(item)
        await vault.exclude(id: item.id, from: "demo")
        let updated = await vault.memory(id: item.id)
        #expect(updated?.excludedContexts == ["demo"])
    }

    @Test("exclude is idempotent")
    func excludeIdempotent() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        let item = makeItem("x")
        await vault.store(item)
        await vault.exclude(id: item.id, from: "demo")
        await vault.exclude(id: item.id, from: "demo")
        let updated = await vault.memory(id: item.id)
        #expect(updated?.excludedContexts == ["demo"])
    }

    @Test("exclude unknown id is a no-op")
    func excludeUnknown() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.exclude(id: UUID(), from: "demo")
        #expect(await vault.allMemories().isEmpty)
    }
}

// MARK: - Expiry

@Suite("MemoryVault Pruning")
struct MemoryVaultPruningTests {

    @Test("pruneExpired removes expired items")
    func pruneExpired() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("fresh", expiresAt: Date().addingTimeInterval(3600)))
        await vault.store(makeItem("stale", expiresAt: Date().addingTimeInterval(-3600)))
        await vault.store(makeItem("no-expiry"))

        await vault.pruneExpired()
        let remaining = await vault.allMemories()
        #expect(remaining.count == 2)
        #expect(remaining.contains { $0.content == "fresh" })
        #expect(remaining.contains { $0.content == "no-expiry" })
        #expect(!remaining.contains { $0.content == "stale" })
    }

    @Test("pruneExpired audits each removal")
    func pruneAudits() async {
        let audit = SwooshAuditLog()
        let vault = MemoryVault(auditLog: audit)
        await vault.store(makeItem("stale-1", expiresAt: Date().addingTimeInterval(-1)))
        await vault.store(makeItem("stale-2", expiresAt: Date().addingTimeInterval(-1)))
        await vault.pruneExpired()

        let rejected = await audit.allEntries().filter { $0.kind == .memoryRejected }
        #expect(rejected.count == 2)
    }

    @Test("pruneExpired with no expired items is a no-op")
    func pruneNoOp() async {
        let vault = MemoryVault(auditLog: SwooshAuditLog())
        await vault.store(makeItem("fresh", expiresAt: Date().addingTimeInterval(3600)))
        await vault.pruneExpired()
        #expect(await vault.allMemories().count == 1)
    }
}
