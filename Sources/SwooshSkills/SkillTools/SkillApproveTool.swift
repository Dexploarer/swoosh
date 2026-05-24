// SwooshSkills/SkillTools/SkillApproveTool.swift — 0.9S /skill_approve
//
// HumanOnly. Promotes a draft skill to `.reviewed`, `.promoted`, or
// `.frozen`. The trust gate (`SkillTrust.promptable`) decides which
// stamps let a skill enter the agent's prompt catalog.

import Foundation
import SwooshTools

public struct SkillApproveInput: Codable, Sendable {
    public let id: String
    public let trust: SkillTrust
    public init(id: String, trust: SkillTrust) { self.id = id; self.trust = trust }
}

public struct SkillApproveOutput: Codable, Sendable {
    public let id: String
    public let newTrust: SkillTrust
}

public struct SkillApproveTool: SwooshTool {
    public typealias Input = SkillApproveInput
    public typealias Output = SkillApproveOutput
    public static let name: ToolName = "skill_approve"
    public static let displayName = "Approve a skill"
    public static let description = "Promote a draft skill to reviewed/promoted/frozen. Only a human may call this."
    public static let permission: SwooshPermission = .skillsWrite
    public static let risk: ToolRisk = .medium
    public static let approval: ApprovalPolicy = .humanOnly
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard var skill = try await deps.store.get(id: input.id) else {
            throw SkillToolError.notFound(input.id)
        }
        skill.trust = input.trust
        try await deps.store.update(skill)
        return Output(id: skill.id, newTrust: skill.trust)
    }
}
