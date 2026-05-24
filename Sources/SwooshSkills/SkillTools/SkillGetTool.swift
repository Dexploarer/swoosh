// SwooshSkills/SkillTools/SkillGetTool.swift — 0.9S /skill_get
//
// Level-1 body for one skill. When `filePath` is provided, reads a
// support file under the skill's source directory. The path resolver
// enforces directory containment so a skill cannot read outside its
// own folder.

import Foundation
import SwooshTools

public struct SkillGetInput: Codable, Sendable {
    public let id: String
    public let filePath: String?
    public init(id: String, filePath: String? = nil) {
        self.id = id
        self.filePath = filePath
    }
}

public struct SkillGetOutput: Codable, Sendable {
    public let skill: SkillDocument?
    public let content: String?
    public let filePath: String?
    public let skillDirectory: String?

    public init(skill: SkillDocument?, content: String? = nil, filePath: String? = nil, skillDirectory: String? = nil) {
        self.skill = skill
        self.content = content
        self.filePath = filePath
        self.skillDirectory = skillDirectory
    }
}

public struct SkillGetTool: SwooshTool {
    public typealias Input = SkillGetInput
    public typealias Output = SkillGetOutput
    public static let name: ToolName = "skill_get"
    public static let displayName = "Read a skill"
    public static let description = "Load the full body of a skill by ID."
    public static let permission: SwooshPermission = .skillsRead
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let skill = try await deps.store.get(id: input.id) else {
            return Output(skill: nil)
        }
        guard let filePath = input.filePath else {
            return Output(
                skill: skill,
                content: substituteTemplateVariables(
                    skill.body,
                    skillDirectory: skill.sourceDirectory,
                    sessionID: context.sessionID
                ),
                skillDirectory: skill.sourceDirectory
            )
        }
        let content = try readSupportFile(filePath, from: skill, sessionID: context.sessionID)
        return Output(skill: skill, content: content, filePath: filePath, skillDirectory: skill.sourceDirectory)
    }

    private func readSupportFile(_ path: String, from skill: SkillDocument, sessionID: String) throws -> String {
        guard let dir = skill.sourceDirectory else { throw SkillToolError.noSkillDirectory(skill.id) }
        guard !path.hasPrefix("/") && !path.split(separator: "/").contains("..") else {
            throw SkillToolError.invalidPath(path)
        }
        let root = URL(fileURLWithPath: dir, isDirectory: true).standardizedFileURL
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw SkillToolError.invalidPath(path) }
        let content = try String(contentsOf: url, encoding: .utf8)
        return substituteTemplateVariables(content, skillDirectory: dir, sessionID: sessionID)
    }
}
