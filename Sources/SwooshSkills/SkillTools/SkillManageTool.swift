// SwooshSkills/SkillTools/SkillManageTool.swift — 0.9S /skill_manage
//
// Create / update / delete drafts and their support files. Approval is
// `askEveryTime`. Drafts remain hidden until approved (see
// `skill_approve`). Support-file writes are confined to each skill's
// own directory via `supportFileURL` containment checks.

import Foundation
import SwooshTools

public enum SkillManageAction: String, Codable, Sendable {
    case create
    case update
    case delete
    case writeFile
    case removeFile
}

public struct SkillManageInput: Codable, Sendable {
    public let action: SkillManageAction
    public let id: String?
    public let title: String?
    public let description: String?
    public let body: String?
    public let category: String?
    public let tags: [String]?
    public let triggerPatterns: [String]?
    public let filePath: String?
    public let fileContent: String?

    public init(
        action: SkillManageAction,
        id: String? = nil,
        title: String? = nil,
        description: String? = nil,
        body: String? = nil,
        category: String? = nil,
        tags: [String]? = nil,
        triggerPatterns: [String]? = nil,
        filePath: String? = nil,
        fileContent: String? = nil
    ) {
        self.action = action
        self.id = id
        self.title = title
        self.description = description
        self.body = body
        self.category = category
        self.tags = tags
        self.triggerPatterns = triggerPatterns
        self.filePath = filePath
        self.fileContent = fileContent
    }
}

public struct SkillManageOutput: Codable, Sendable {
    public let id: String?
    public let message: String
}

public struct SkillManageTool: SwooshTool {
    public typealias Input = SkillManageInput
    public typealias Output = SkillManageOutput
    public static let name: ToolName = "skill_manage"
    public static let displayName = "Manage skill drafts"
    public static let description = "Create or update draft skills and their support files. Drafts remain hidden until approved."
    public static let permission: SwooshPermission = .skillsWrite
    public static let risk: ToolRisk = .medium
    public static let approval: ApprovalPolicy = .askEveryTime
    public static let toolset: ToolsetID = .skills

    private let deps: SkillToolDependencies
    public init(dependencies: SkillToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        switch input.action {
        case .create:
            return try await create(input, sessionID: context.sessionID)
        case .update:
            return try await update(input)
        case .delete:
            guard let id = input.id else { throw SkillToolError.missingField("id") }
            guard let skill = try await deps.store.get(id: id) else { throw SkillToolError.notFound(id) }
            guard !skill.pinned else { throw SkillToolError.pinned(id) }
            try await deps.store.delete(id: id)
            return Output(id: id, message: "deleted")
        case .writeFile:
            return try await writeFile(input)
        case .removeFile:
            return try await removeFile(input)
        }
    }

    private func create(_ input: SkillManageInput, sessionID: String) async throws -> Output {
        guard let title = input.title, let description = input.description, let body = input.body else {
            throw SkillToolError.missingField("title, description, body")
        }
        let category = SkillCategory(rawValue: input.category ?? "general") ?? .general
        let skill = SkillDocument(
            title: title,
            description: description,
            category: category,
            triggerPatterns: input.triggerPatterns ?? [],
            provenance: SkillProvenance(createdBySessionID: sessionID, source: .agentLearned),
            tags: input.tags ?? [],
            trust: .draft,
            body: body
        )
        try await deps.store.save(skill)
        return Output(id: skill.id, message: "draft created")
    }

    private func update(_ input: SkillManageInput) async throws -> Output {
        guard let id = input.id else { throw SkillToolError.missingField("id") }
        guard var skill = try await deps.store.get(id: id) else { throw SkillToolError.notFound(id) }
        if let title = input.title { skill.title = title }
        if let description = input.description { skill.description = description }
        if let body = input.body { skill.body = body }
        if let category = input.category { skill.category = SkillCategory(rawValue: category) ?? skill.category }
        if let tags = input.tags { skill.tags = tags }
        if let triggers = input.triggerPatterns { skill.triggerPatterns = triggers }
        if !SkillGuard(allowImportedSkills: true).validate(skill).filter(\.blocksSkillInstall).isEmpty {
            throw SkillToolError.invalidSkill("security scan failed")
        }
        try await deps.store.update(skill)
        return Output(id: id, message: "updated")
    }

    private func writeFile(_ input: SkillManageInput) async throws -> Output {
        guard let id = input.id else { throw SkillToolError.missingField("id") }
        guard var skill = try await deps.store.get(id: id) else { throw SkillToolError.notFound(id) }
        guard let filePath = input.filePath, let content = input.fileContent else {
            throw SkillToolError.missingField("filePath, fileContent")
        }
        let dir = try ensureSkillDirectory(&skill)
        let url = try supportFileURL(filePath, under: dir)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        skill.supportingFiles = listSupportFiles(in: dir)
        try await deps.store.update(skill)
        return Output(id: id, message: "file written")
    }

    private func removeFile(_ input: SkillManageInput) async throws -> Output {
        guard let id = input.id else { throw SkillToolError.missingField("id") }
        guard var skill = try await deps.store.get(id: id) else { throw SkillToolError.notFound(id) }
        guard let filePath = input.filePath else { throw SkillToolError.missingField("filePath") }
        guard let sourceDirectory = skill.sourceDirectory else { throw SkillToolError.noSkillDirectory(id) }
        let dir = URL(fileURLWithPath: sourceDirectory, isDirectory: true)
        let url = try supportFileURL(filePath, under: dir)
        try FileManager.default.removeItem(at: url)
        skill.supportingFiles = listSupportFiles(in: dir)
        try await deps.store.update(skill)
        return Output(id: id, message: "file removed")
    }

    private func ensureSkillDirectory(_ skill: inout SkillDocument) throws -> URL {
        if let sourceDirectory = skill.sourceDirectory {
            return URL(fileURLWithPath: sourceDirectory, isDirectory: true)
        }
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/skill-assets", isDirectory: true)
        #else
        let base = ((try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("ai.swoosh.agent/skill-assets", isDirectory: true)
        #endif
        let dir = base.appendingPathComponent(skill.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try skill.body.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        skill.sourceDirectory = dir.path
        return dir
    }

    private func supportFileURL(_ path: String, under directory: URL) throws -> URL {
        guard !path.hasPrefix("/") && !path.split(separator: "/").contains("..") else {
            throw SkillToolError.invalidPath(path)
        }
        let root = directory.standardizedFileURL
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw SkillToolError.invalidPath(path) }
        return url
    }

    private func listSupportFiles(in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent != "SKILL.md" {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            files.append(String(url.path.dropFirst(directory.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        return files.sorted()
    }
}
