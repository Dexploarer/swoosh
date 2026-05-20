// SwooshSkills/SkillCatalog.swift — Level-0 catalog view for prompt injection
//
// Hermes-style progressive disclosure: only the (name, description) pair
// of every promotable skill enters the system prompt — the model decides
// whether to load the full body via the `skill_get` tool. Keeps tokens
// cheap even with a large library.

import Foundation

/// Minimal skill view that the agent sees in its system prompt catalog.
public struct SkillCatalogEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let trust: SkillTrust
    public let category: SkillCategory
    public let tags: [String]
    public let triggerPatterns: [String]

    public init(
        id: String,
        title: String,
        description: String,
        trust: SkillTrust,
        category: SkillCategory,
        tags: [String] = [],
        triggerPatterns: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.trust = trust
        self.category = category
        self.tags = tags
        self.triggerPatterns = triggerPatterns
    }

    public init(_ skill: SkillDocument) {
        self.init(
            id: skill.id,
            title: skill.title,
            description: skill.description,
            trust: skill.trust,
            category: skill.category,
            tags: skill.tags,
            triggerPatterns: skill.triggerPatterns
        )
    }
}

/// Loads the catalog of skills the agent is allowed to see right now.
/// Implementations apply `SkillTrust.promptable` and any platform filter.
public protocol SkillCatalogLoading: Sendable {
    func loadPromptCatalog() async throws -> [SkillCatalogEntry]
}

/// Empty catalog. Default when no store is wired — keeps existing call
/// sites (CLI, tests) unaffected by the new prompt branch.
public struct EmptySkillCatalog: SkillCatalogLoading {
    public init() {}
    public func loadPromptCatalog() async throws -> [SkillCatalogEntry] { [] }
}

/// Adapter that converts a `SkillStoring` into a prompt-ready catalog,
/// applying the trust + platform filter. `platform` accepts the same raw
/// strings used in `SkillDocument.platforms` so the catalog can keep
/// SwooshTools out of its dependency graph.
public actor SkillStoreCatalog: SkillCatalogLoading {
    private let store: any SkillStoring
    private let platform: String
    private let activeToolsets: Set<String>
    private let activeTools: Set<String>

    public init(store: any SkillStoring, platform: String, activeToolsets: Set<String> = [], activeTools: Set<String> = []) {
        self.store = store
        self.platform = platform
        self.activeToolsets = activeToolsets
        self.activeTools = activeTools
    }

    public func loadPromptCatalog() async throws -> [SkillCatalogEntry] {
        let all = try await store.listAll()
        return all
            .filter { SkillTrust.promptable.contains($0.trust) }
            .filter { $0.platforms.contains(platform) }
            .filter { skill in skill.requiredToolsets.allSatisfy(activeToolsets.contains) }
            .filter { skill in skill.requiredTools.allSatisfy(activeTools.contains) }
            .filter { skill in Set(skill.fallbackToolsets).isDisjoint(with: activeToolsets) }
            .filter { skill in Set(skill.fallbackTools).isDisjoint(with: activeTools) }
            .map(SkillCatalogEntry.init)
    }
}
