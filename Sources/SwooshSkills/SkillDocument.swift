// SwooshSkills/SkillDocument.swift — Self-improving skill model
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

    public init(
        title: String,
        description: String,
        category: SkillCategory = .general,
        triggerPatterns: [String] = [],
        steps: [SkillStep] = [],
        toolsRequired: [String] = [],
        provenance: SkillProvenance = SkillProvenance(),
        tags: [String] = []
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
