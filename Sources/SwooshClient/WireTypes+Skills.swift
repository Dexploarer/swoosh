// SwooshClient/WireTypes+Skills.swift — 0.4A Skill summary + CRUD wire types
//
// Wire format for `GET /api/skills`, `GET /api/skills/{id}`,
// `POST /api/skills/search`, `POST /api/skills`, plus the approve / reject
// mutations. Skill trust is gated server-side; the client sees the
// already-projected string.

import Foundation

public struct SkillSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let trust: String

    public init(id: String, title: String, description: String, category: String, trust: String) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.trust = trust
    }
}

public struct SkillsResponse: Codable, Sendable {
    public let skills: [SkillSummary]

    public init(skills: [SkillSummary]) {
        self.skills = skills
    }
}

public struct SkillDetailResponse: Codable, Sendable, Equatable {
    public let skill: SkillSummary
    public let body: String
    public let tags: [String]
    public let triggerPatterns: [String]
    public let toolsRequired: [String]
    public let platforms: [String]
    public let usageCount: Int
    public let successRate: Double
    public let updatedAt: Date

    public init(
        skill: SkillSummary,
        body: String,
        tags: [String],
        triggerPatterns: [String],
        toolsRequired: [String],
        platforms: [String],
        usageCount: Int,
        successRate: Double,
        updatedAt: Date
    ) {
        self.skill = skill
        self.body = body
        self.tags = tags
        self.triggerPatterns = triggerPatterns
        self.toolsRequired = toolsRequired
        self.platforms = platforms
        self.usageCount = usageCount
        self.successRate = successRate
        self.updatedAt = updatedAt
    }
}

public struct SkillSearchRequest: Codable, Sendable, Equatable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct SkillProposeRequest: Codable, Sendable, Equatable {
    public let title: String
    public let description: String
    public let body: String
    public let category: String?
    public let tags: [String]?
    public let triggerPatterns: [String]?

    public init(
        title: String,
        description: String,
        body: String,
        category: String? = nil,
        tags: [String]? = nil,
        triggerPatterns: [String]? = nil
    ) {
        self.title = title
        self.description = description
        self.body = body
        self.category = category
        self.tags = tags
        self.triggerPatterns = triggerPatterns
    }
}

public struct SkillMutationResponse: Codable, Sendable, Equatable {
    public let skill: SkillSummary
    public let message: String

    public init(skill: SkillSummary, message: String) {
        self.skill = skill
        self.message = message
    }
}
