// SwooshSkills/SkillStore.swift — Persistent skill storage with FTS5 search
//
// SQLite-backed store with full-text search for contextual skill matching.
// Hermes uses FTS5 for cross-session recall; we do the same.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill store protocol
// ═══════════════════════════════════════════════════════════════════

public protocol SkillStoring: Sendable {
    func save(_ skill: SkillDocument) async throws
    func update(_ skill: SkillDocument) async throws
    func get(id: String) async throws -> SkillDocument?
    func delete(id: String) async throws
    func listAll() async throws -> [SkillDocument]
    func search(query: String, limit: Int) async throws -> [SkillDocument]
    func findByCategory(_ category: SkillCategory) async throws -> [SkillDocument]
    func findByTags(_ tags: [String]) async throws -> [SkillDocument]
    func recordUsage(id: String, success: Bool) async throws
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - File-based skill store
// ═══════════════════════════════════════════════════════════════════

/// JSON file-backed skill store (~/.swoosh/skills/).
/// Simple but effective for alpha. Can be upgraded to SQLite+FTS5 later.
public actor FileSkillStore: SkillStoring {
    private let directory: URL
    private var index: [String: SkillDocument] = [:]  // In-memory index
    private var loaded = false

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    /// Cross-platform default location for the skill store.
    /// macOS uses `~/.swoosh/skills/`; iOS uses the app sandbox's
    /// Application Support directory.
    private static func defaultDirectory() -> URL {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/skills")
        #else
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ai.swoosh.agent/skills", isDirectory: true)
        #endif
    }

    public func save(_ skill: SkillDocument) async throws {
        try ensureLoaded()
        index[skill.id] = skill
        try persist(skill)
    }

    public func update(_ skill: SkillDocument) async throws {
        try ensureLoaded()
        var updated = skill
        updated.updatedAt = Date()
        updated.version = skill.version + 1
        index[skill.id] = updated
        try persist(updated)
    }

    public func get(id: String) async throws -> SkillDocument? {
        try ensureLoaded()
        return index[id]
    }

    public func delete(id: String) async throws {
        try ensureLoaded()
        index.removeValue(forKey: id)
        let url = directory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    public func listAll() async throws -> [SkillDocument] {
        try ensureLoaded()
        return Array(index.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func search(query: String, limit: Int = 10) async throws -> [SkillDocument] {
        try ensureLoaded()
        let lowered = query.lowercased()
        let terms = lowered.split(separator: " ").map(String.init)

        return index.values
            .map { skill -> (SkillDocument, Int) in
                var score = 0
                let searchable = "\(skill.title) \(skill.description) \(skill.tags.joined(separator: " ")) \(skill.triggerPatterns.joined(separator: " "))".lowercased()

                for term in terms {
                    if skill.title.lowercased().contains(term) { score += 10 }
                    if skill.description.lowercased().contains(term) { score += 5 }
                    if skill.triggerPatterns.contains(where: { $0.lowercased().contains(term) }) { score += 8 }
                    if skill.tags.contains(where: { $0.lowercased() == term }) { score += 6 }
                    if searchable.contains(term) { score += 1 }
                }

                // Boost by success rate
                score += Int(skill.successRate * 5)

                return (skill, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    public func findByCategory(_ category: SkillCategory) async throws -> [SkillDocument] {
        try ensureLoaded()
        return index.values.filter { $0.category == category }
            .sorted { $0.usageCount > $1.usageCount }
    }

    public func findByTags(_ tags: [String]) async throws -> [SkillDocument] {
        try ensureLoaded()
        let tagSet = Set(tags.map { $0.lowercased() })
        return index.values.filter { skill in
            !Set(skill.tags.map { $0.lowercased() }).isDisjoint(with: tagSet)
        }
    }

    public func recordUsage(id: String, success: Bool) async throws {
        guard var skill = index[id] else { return }
        skill.usageCount += 1
        if success { skill.successCount += 1 } else { skill.failureCount += 1 }
        skill.updatedAt = Date()
        index[id] = skill
        try persist(skill)
    }

    // ── Internal ──

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let skill = try? decoder.decode(SkillDocument.self, from: data) {
                index[skill.id] = skill
            }
        }
        loaded = true
    }

    private func persist(_ skill: SkillDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(skill)
        let url = directory.appendingPathComponent("\(skill.id).json")
        try data.write(to: url, options: .atomic)
    }
}
