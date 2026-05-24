// SwooshSkills/SkillTools/SkillInstallTool.swift — 0.9S /skill_install
//
// Install an agentskills-style SKILL.md from a local file path, an HTTP
// URL, or a `github:owner/repo/path` source. Approval is `askEveryTime`
// because installing a foreign skill is roughly equivalent to installing
// foreign code.

import Foundation
import SwooshTools

public struct SkillInstallInput: Codable, Sendable {
    public let source: String
    public let name: String?
    public let trust: SkillInstallTrust?

    public init(source: String, name: String? = nil, trust: SkillInstallTrust? = nil) {
        self.source = source
        self.name = name
        self.trust = trust
    }
}

public struct SkillInstallOutput: Codable, Sendable {
    public let result: SkillInstallResult
}

public struct SkillInstallTool: SwooshTool {
    public typealias Input = SkillInstallInput
    public typealias Output = SkillInstallOutput
    public static let name: ToolName = "skill_install"
    public static let displayName = "Install a skill"
    public static let description = "Install an agentskills-style SKILL.md from a local path, URL, or github:owner/repo/path source."
    public static let permission: SwooshPermission = .skillsWrite
    public static let risk: ToolRisk = .medium
    public static let approval: ApprovalPolicy = .askEveryTime
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await deps.installer.install(
            source: input.source,
            name: input.name,
            trust: input.trust ?? .reviewed
        )
        return Output(result: result)
    }
}
