// SwooshSkills/SkillTools/SkillProposeTool.swift — 0.9S /skill_propose
//
// Model-writable. The draft lands as `.draft` and never enters prompts
// until a human promotes it via `skill_approve` (humanOnly). Same trust
// contract as memory candidates.

import Foundation
import SwooshTools

public struct SkillProposeInput: Codable, Sendable {
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

public struct SkillProposeOutput: Codable, Sendable {
    public let id: String
    public let trust: SkillTrust
}

public struct SkillProposeTool: SwooshTool {
    public typealias Input = SkillProposeInput
    public typealias Output = SkillProposeOutput
    public static let name: ToolName = "skill_propose"
    public static let displayName = "Propose a new skill"
    public static let description = "Save a draft skill for the user to review. The draft never enters prompts until promoted."
    public static let permission: SwooshPermission = .skillsWrite
    public static let risk: ToolRisk = .medium
    /// Drafts are model-writable but never auto-promoted; the approve
    /// path is `humanOnly`. So `propose` can be `auto` — it produces a
    /// draft, not a live skill.
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let category = SkillCategory(rawValue: input.category ?? "general") ?? .general
        var skill = SkillDocument(
            title: input.title,
            description: input.description,
            category: category,
            triggerPatterns: input.triggerPatterns ?? [],
            steps: [],
            toolsRequired: [],
            provenance: SkillProvenance(
                createdBySessionID: context.sessionID,
                source: .agentLearned
            ),
            tags: input.tags ?? [],
            trust: .draft,
            body: input.body
        )
        skill.updatedAt = Date()
        try await deps.store.save(skill)
        return Output(id: skill.id, trust: skill.trust)
    }
}
