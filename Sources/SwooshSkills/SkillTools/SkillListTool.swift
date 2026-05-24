// SwooshSkills/SkillTools/SkillListTool.swift — 0.9S /skill_list
//
// Level-0 catalog only: id, title, description, trust. Body is fetched
// separately via `skill_get`. By default returns the promptable subset
// (reviewed / promoted / frozen) so the agent doesn't see drafts or
// rejected entries.

import Foundation
import SwooshTools

public struct SkillListInput: Codable, Sendable {
    public let promptableOnly: Bool?
    public init(promptableOnly: Bool? = true) { self.promptableOnly = promptableOnly }
}

public struct SkillListOutput: Codable, Sendable {
    public let count: Int
    public let entries: [SkillCatalogEntry]
}

public struct SkillListTool: SwooshTool {
    public typealias Input = SkillListInput
    public typealias Output = SkillListOutput
    public static let name: ToolName = "skill_list"
    public static let displayName = "List skills"
    public static let description = "Catalog of skills the agent can recall — names + descriptions only."
    public static let permission: SwooshPermission = .skillsRead
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let all = try await deps.store.listAll()
        let filtered: [SkillDocument]
        if input.promptableOnly ?? true {
            filtered = all.filter { SkillTrust.promptable.contains($0.trust) }
        } else {
            filtered = all
        }
        let entries = filtered.map(SkillCatalogEntry.init)
        return Output(count: entries.count, entries: entries)
    }
}
