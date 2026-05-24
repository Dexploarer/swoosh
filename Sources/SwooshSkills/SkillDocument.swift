// SwooshSkills/SkillDocument.swift — 0.9S Self-improving skill model
//
// Hermes-inspired closed learning loop: the agent writes skill
// documents from completed tasks, stores them, and loads them
// contextually when similar tasks arise.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill document
// ═══════════════════════════════════════════════════════════════════

/// A reusable skill created from agent experience.
public struct SkillDocument: Codable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var description: String
    public var category: SkillCategory
    public var triggerPatterns: [String]          // Keywords or regex that match this skill
    public var steps: [SkillStep]                // Ordered execution steps
    public var toolsRequired: [String]           // Tool IDs needed
    public var provenance: SkillProvenance        // Where this skill came from
    public var usageCount: Int
    public var successCount: Int
    public var failureCount: Int
    public var successRate: Double {
        guard usageCount > 0 else { return 0 }
        return Double(successCount) / Double(usageCount)
    }
    public var tags: [String]
    public let createdAt: Date
    public var updatedAt: Date
    public var version: Int

    /// Trust gate — see `SkillTrust`. Skills below `.reviewed` never enter
    /// the agent's prompt catalog.
    public var trust: SkillTrust
    /// Markdown body the model reads. Holds the human-readable procedure;
    /// `steps` carries the typed execution plan when one exists.
    public var body: String
    /// Platforms on which this skill is allowed to load. Mirrors the same
    /// shape `SwooshTool.platforms` uses; populated as `["macOS","iOS","linux"]`
    /// raw strings so the schema doesn't depend on SwooshTools.
    public var platforms: Set<String>
    /// Optional pointer to a SwooshFlow workflow that executes this skill
    /// deterministically. When set, the runtime can invoke the workflow
    /// instead of asking the model to follow `body` step-by-step.
    public var workflowID: String?
    public var sourceDirectory: String?
    public var supportingFiles: [String]
    public var relatedSkills: [String]
    public var requiredToolsets: [String]
    public var requiredTools: [String]
    public var fallbackToolsets: [String]
    public var fallbackTools: [String]
    public var requiredEnvironmentVariables: [SkillEnvironmentRequirement]
    public var configRequirements: [SkillConfigRequirement]
    public var pinned: Bool

    public init(
        title: String,
        description: String,
        category: SkillCategory = .general,
        triggerPatterns: [String] = [],
        steps: [SkillStep] = [],
        toolsRequired: [String] = [],
        provenance: SkillProvenance = SkillProvenance(),
        tags: [String] = [],
        trust: SkillTrust = .draft,
        body: String = "",
        platforms: Set<String> = ["macOS", "iOS", "linux"],
        workflowID: String? = nil,
        sourceDirectory: String? = nil,
        supportingFiles: [String] = [],
        relatedSkills: [String] = [],
        requiredToolsets: [String] = [],
        requiredTools: [String] = [],
        fallbackToolsets: [String] = [],
        fallbackTools: [String] = [],
        requiredEnvironmentVariables: [SkillEnvironmentRequirement] = [],
        configRequirements: [SkillConfigRequirement] = [],
        pinned: Bool = false
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.category = category
        self.triggerPatterns = triggerPatterns
        self.steps = steps
        self.toolsRequired = toolsRequired
        self.provenance = provenance
        self.usageCount = 0
        self.successCount = 0
        self.failureCount = 0
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
        self.version = 1
        self.trust = trust
        self.body = body
        self.platforms = platforms
        self.workflowID = workflowID
        self.sourceDirectory = sourceDirectory
        self.supportingFiles = supportingFiles
        self.relatedSkills = relatedSkills
        self.requiredToolsets = requiredToolsets
        self.requiredTools = requiredTools
        self.fallbackToolsets = fallbackToolsets
        self.fallbackTools = fallbackTools
        self.requiredEnvironmentVariables = requiredEnvironmentVariables
        self.configRequirements = configRequirements
        self.pinned = pinned
    }

    // Backward-compat decoding: skills persisted before the trust/body/
    // platforms/workflowID fields existed should still load. Default trust
    // for legacy records is `.reviewed` so a pre-existing skill library
    // doesn't silently disappear from prompts after the upgrade.
    private enum CodingKeys: String, CodingKey {
        case id, title, description, category, triggerPatterns, steps
        case toolsRequired, provenance, usageCount, successCount, failureCount
        case tags, createdAt, updatedAt, version
        case trust, body, platforms, workflowID
        case sourceDirectory, supportingFiles, relatedSkills
        case requiredToolsets, requiredTools, fallbackToolsets, fallbackTools
        case requiredEnvironmentVariables, configRequirements, pinned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decode(String.self, forKey: .description)
        self.category = try c.decode(SkillCategory.self, forKey: .category)
        self.triggerPatterns = try c.decode([String].self, forKey: .triggerPatterns)
        self.steps = try c.decode([SkillStep].self, forKey: .steps)
        self.toolsRequired = try c.decode([String].self, forKey: .toolsRequired)
        self.provenance = try c.decode(SkillProvenance.self, forKey: .provenance)
        self.usageCount = try c.decode(Int.self, forKey: .usageCount)
        self.successCount = try c.decode(Int.self, forKey: .successCount)
        self.failureCount = try c.decode(Int.self, forKey: .failureCount)
        self.tags = try c.decode([String].self, forKey: .tags)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.version = try c.decode(Int.self, forKey: .version)
        self.trust     = (try? c.decode(SkillTrust.self, forKey: .trust))      ?? .reviewed
        self.body      = (try? c.decode(String.self,     forKey: .body))       ?? ""
        self.platforms = (try? c.decode(Set<String>.self, forKey: .platforms)) ?? ["macOS", "iOS", "linux"]
        self.workflowID = try? c.decode(String.self, forKey: .workflowID)
        self.sourceDirectory = try? c.decode(String.self, forKey: .sourceDirectory)
        self.supportingFiles = (try? c.decode([String].self, forKey: .supportingFiles)) ?? []
        self.relatedSkills = (try? c.decode([String].self, forKey: .relatedSkills)) ?? []
        self.requiredToolsets = (try? c.decode([String].self, forKey: .requiredToolsets)) ?? []
        self.requiredTools = (try? c.decode([String].self, forKey: .requiredTools)) ?? []
        self.fallbackToolsets = (try? c.decode([String].self, forKey: .fallbackToolsets)) ?? []
        self.fallbackTools = (try? c.decode([String].self, forKey: .fallbackTools)) ?? []
        self.requiredEnvironmentVariables = (try? c.decode([SkillEnvironmentRequirement].self, forKey: .requiredEnvironmentVariables)) ?? []
        self.configRequirements = (try? c.decode([SkillConfigRequirement].self, forKey: .configRequirements)) ?? []
        self.pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }
}

public struct SkillEnvironmentRequirement: Codable, Sendable, Hashable {
    public let name: String
    public let prompt: String?
    public let help: String?
    public let requiredFor: String?

    public init(name: String, prompt: String? = nil, help: String? = nil, requiredFor: String? = nil) {
        self.name = name
        self.prompt = prompt
        self.help = help
        self.requiredFor = requiredFor
    }
}

public struct SkillConfigRequirement: Codable, Sendable, Hashable {
    public let key: String
    public let description: String?
    public let defaultValue: String?
    public let prompt: String?
    public let url: String?

    public init(key: String, description: String? = nil, defaultValue: String? = nil, prompt: String? = nil, url: String? = nil) {
        self.key = key
        self.description = description
        self.defaultValue = defaultValue
        self.prompt = prompt
        self.url = url
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill step
// ═══════════════════════════════════════════════════════════════════

/// A single step within a skill.
public struct SkillStep: Codable, Sendable, Identifiable {
    public let id: String
    public var order: Int
    public var instruction: String               // What to do
    public var toolID: String?                   // Which tool to use (optional)
    public var toolParameters: [String: String]? // Pre-filled parameters
    public var expectedOutput: String?           // What success looks like
    public var fallback: String?                 // What to do if this step fails

    public init(order: Int, instruction: String,
                toolID: String? = nil, toolParameters: [String: String]? = nil,
                expectedOutput: String? = nil, fallback: String? = nil) {
        self.id = UUID().uuidString
        self.order = order
        self.instruction = instruction
        self.toolID = toolID
        self.toolParameters = toolParameters
        self.expectedOutput = expectedOutput
        self.fallback = fallback
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill category
// ═══════════════════════════════════════════════════════════════════

public enum SkillCategory: String, Codable, Sendable, CaseIterable {
    case general
    case coding
    case debugging
    case deployment
    case documentation
    case testing
    case refactoring
    case research
    case dataAnalysis
    case systemAdmin
    case git
    case browser
    case communication
    case media
    case custom
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill provenance
// ═══════════════════════════════════════════════════════════════════

/// Tracks where a skill came from.
public struct SkillProvenance: Codable, Sendable {
    public var createdBySessionID: String?
    public var createdByTraceID: String?
    public var createdFromTaskDescription: String?
    public var originalConversationSnippet: String?
    public var improvedBySessionIDs: [String]
    public var source: ProvenanceSource

    public enum ProvenanceSource: String, Codable, Sendable {
        case agentLearned       // Agent wrote it from experience
        case userCreated        // User wrote it manually
        case imported           // Imported from external source
        case builtIn            // Ships with Swoosh
    }

    public init(
        createdBySessionID: String? = nil,
        createdByTraceID: String? = nil,
        createdFromTaskDescription: String? = nil,
        originalConversationSnippet: String? = nil,
        improvedBySessionIDs: [String] = [],
        source: ProvenanceSource = .agentLearned
    ) {
        self.createdBySessionID = createdBySessionID
        self.createdByTraceID = createdByTraceID
        self.createdFromTaskDescription = createdFromTaskDescription
        self.originalConversationSnippet = originalConversationSnippet
        self.improvedBySessionIDs = improvedBySessionIDs
        self.source = source
    }
}
