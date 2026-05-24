// SwooshSkills/SkillTools/SkillSearchTool.swift — 0.9S /skill_search
//
// Relevance-ranked match against a free-text query. Delegates to
// `SkillMatcher`, which consults the SQLite FTS5 index on the store.

import Foundation
import SwooshTools

public struct SkillSearchInput: Codable, Sendable {
    public let query: String
    public let limit: Int?
    public init(query: String, limit: Int? = 5) { self.query = query; self.limit = limit }
}

public struct SkillSearchOutput: Codable, Sendable {
    public let matches: [SkillCatalogEntry]
}

public struct SkillSearchTool: SwooshTool {
    public typealias Input = SkillSearchInput
    public typealias Output = SkillSearchOutput
    public static let name: ToolName = "skill_search"
    public static let displayName = "Search skills"
    public static let description = "Find skills relevant to a task description."
    public static let permission: SwooshPermission = .skillsRead
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let matches = try await deps.matcher.match(
            taskDescription: input.query,
            maxResults: input.limit ?? 5
        )
        return Output(matches: matches.map { SkillCatalogEntry($0.skill) })
    }
}
