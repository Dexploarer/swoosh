// SwooshSkills/SkillTools.swift — Tool surface for the skill pillar
//
// Five tools the agent (or user via CLI) can invoke:
//
//   • skill_list       — Level-0 catalog (id, title, description, trust)
//   • skill_get        — Level-1 body for a specific skill
//   • skill_search     — Relevance-ranked match against a query
//   • skill_propose    — Model emits a draft (lands as `.draft`, humanOnly)
//   • skill_approve    — User promotes draft → reviewed/promoted/frozen
//
// `skill_propose` and `skill_approve` are firewalled at the `humanOnly`
// approval level so the model can't auto-promote skills it wrote — same
// trust contract as memory candidates.

import Foundation
import SwooshTools

// MARK: - Common dependencies

public struct SkillToolDependencies: Sendable {
    public let store: any SkillStoring
    public let writer: SkillWriter
    public let matcher: SkillMatcher
    public let installer: SkillInstaller

    public init(store: any SkillStoring) {
        self.store = store
        self.writer = SkillWriter(store: store)
        self.matcher = SkillMatcher(store: store)
        self.installer = SkillInstaller(store: store)
    }
}

// MARK: - skill_list

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

// MARK: - skill_get

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
                content: substituteTemplateVariables(skill.body, skillDirectory: skill.sourceDirectory, sessionID: context.sessionID),
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

// MARK: - skill_search

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

// MARK: - skill_propose

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

// MARK: - skill_install

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
        let result = try await deps.installer.install(source: input.source, name: input.name, trust: input.trust ?? .reviewed)
        return Output(result: result)
    }
}

// MARK: - skill_manage

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
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/skill-assets/\(skill.id)", isDirectory: true)
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

// MARK: - skill_approve

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

public enum SkillToolError: Error, Sendable, LocalizedError {
    case notFound(String)
    case noSkillDirectory(String)
    case invalidPath(String)
    case missingField(String)
    case pinned(String)
    case invalidSkill(String)
    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "skill not found: \(id)"
        case .noSkillDirectory(let id): return "skill has no support-file directory: \(id)"
        case .invalidPath(let path): return "invalid skill support-file path: \(path)"
        case .missingField(let field): return "missing field: \(field)"
        case .pinned(let id): return "skill is pinned and cannot be deleted: \(id)"
        case .invalidSkill(let reason): return "invalid skill: \(reason)"
        }
    }
}

private func substituteTemplateVariables(_ content: String, skillDirectory: String?, sessionID: String) -> String {
    content
        .replacingOccurrences(of: "${SWOOSH_SKILL_DIR}", with: skillDirectory ?? "")
        .replacingOccurrences(of: "${HERMES_SKILL_DIR}", with: skillDirectory ?? "")
        .replacingOccurrences(of: "${SWOOSH_SESSION_ID}", with: sessionID)
        .replacingOccurrences(of: "${HERMES_SESSION_ID}", with: sessionID)
}
