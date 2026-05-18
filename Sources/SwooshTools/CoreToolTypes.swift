// SwooshTools/CoreToolTypes.swift — Input/Output types for Core, Memory, Vault,
// Permissions, Approvals, Scout, and Audit toolsets.
//
// Every tool has typed input and output. No loose JSON blobs.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Core tools
// ═══════════════════════════════════════════════════════════════════

// core.status
public struct CoreStatusInput: Codable, Sendable {}

public struct CoreStatusOutput: Codable, Sendable {
    public let version: String
    public let mode: String
    public let statePlane: String
    public let approvedMemoryCount: Int
    public let pendingMemoryCandidateCount: Int
    public let enabledToolsets: [String]

    public init(
        version: String,
        mode: String,
        statePlane: String,
        approvedMemoryCount: Int,
        pendingMemoryCandidateCount: Int,
        enabledToolsets: [String]
    ) {
        self.version = version
        self.mode = mode
        self.statePlane = statePlane
        self.approvedMemoryCount = approvedMemoryCount
        self.pendingMemoryCandidateCount = pendingMemoryCandidateCount
        self.enabledToolsets = enabledToolsets
    }
}

// core.explain_context
public struct ExplainContextInput: Codable, Sendable {
    public let sessionID: String
    public let messageID: String?

    public init(sessionID: String, messageID: String? = nil) {
        self.sessionID = sessionID
        self.messageID = messageID
    }
}

public struct ExplainContextOutput: Codable, Sendable {
    public let approvedMemoryIDs: [String]
    public let setupReportID: String?
    public let permissionSummary: String
    public let excludedSources: [String]
    public let modelUsed: String?

    public init(
        approvedMemoryIDs: [String],
        setupReportID: String?,
        permissionSummary: String,
        excludedSources: [String],
        modelUsed: String?
    ) {
        self.approvedMemoryIDs = approvedMemoryIDs
        self.setupReportID = setupReportID
        self.permissionSummary = permissionSummary
        self.excludedSources = excludedSources
        self.modelUsed = modelUsed
    }
}

// core.list_toolsets
public struct ListToolsetsInput: Codable, Sendable {
    public init() {}
}

public struct ListToolsetsOutput: Codable, Sendable {
    public let toolsets: [String]

    public init(toolsets: [String]) {
        self.toolsets = toolsets
    }
}

// core.list_tools
public struct ListToolsInput: Codable, Sendable {
    public let toolset: String?

    public init(toolset: String? = nil) {
        self.toolset = toolset
    }
}

public struct ListToolsOutput: Codable, Sendable {
    public let tools: [ToolDescriptor]

    public init(tools: [ToolDescriptor]) {
        self.tools = tools
    }
}

// core.get_tool_schema
public struct GetToolSchemaInput: Codable, Sendable {
    public let toolName: String

    public init(toolName: String) {
        self.toolName = toolName
    }
}

public struct GetToolSchemaOutput: Codable, Sendable {
    public let descriptor: ToolDescriptor?

    public init(descriptor: ToolDescriptor?) {
        self.descriptor = descriptor
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Memory types
// ═══════════════════════════════════════════════════════════════════

public struct ApprovedMemory: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let category: MemoryCategory
    public let sensitivity: Sensitivity
    public let confidence: Double
    public let createdAt: Date
    public let lastUsedAt: Date?

    public init(
        id: String,
        text: String,
        category: MemoryCategory,
        sensitivity: Sensitivity = .normal,
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public enum Sensitivity: String, Codable, Sendable {
    case normal
    case sensitive
    case secret
}

public struct EvidencePointer: Codable, Sendable {
    public let sourceID: String
    public let recordID: String?
    public let sessionID: String?
    public let description: String

    public init(sourceID: String, recordID: String? = nil, sessionID: String? = nil, description: String) {
        self.sourceID = sourceID
        self.recordID = recordID
        self.sessionID = sessionID
        self.description = description
    }
}

public enum CandidateStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case edited
}

public struct MemoryCandidate: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let category: MemoryCategory
    public let sensitivity: Sensitivity
    public let confidence: Double
    public let evidence: [EvidencePointer]
    public let status: CandidateStatus
    public let createdAt: Date

    public init(
        id: String,
        text: String,
        category: MemoryCategory,
        sensitivity: Sensitivity,
        confidence: Double,
        evidence: [EvidencePointer],
        status: CandidateStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.evidence = evidence
        self.status = status
        self.createdAt = createdAt
    }
}

// ── memory.list_approved ──────────────────────────────────────────

public struct ListApprovedMemoriesInput: Codable, Sendable {
    public let category: MemoryCategory?
    public let limit: Int?

    public init(category: MemoryCategory? = nil, limit: Int? = nil) {
        self.category = category
        self.limit = limit
    }
}

public struct ListApprovedMemoriesOutput: Codable, Sendable {
    public let memories: [ApprovedMemory]

    public init(memories: [ApprovedMemory]) {
        self.memories = memories
    }
}

// ── memory.search_approved ────────────────────────────────────────

public struct SearchApprovedMemoriesInput: Codable, Sendable {
    public let query: String
    public let category: MemoryCategory?
    public let limit: Int?

    public init(query: String, category: MemoryCategory? = nil, limit: Int? = nil) {
        self.query = query
        self.category = category
        self.limit = limit
    }
}

public struct SearchApprovedMemoriesOutput: Codable, Sendable {
    public let results: [ApprovedMemorySearchResult]

    public init(results: [ApprovedMemorySearchResult]) {
        self.results = results
    }
}

public struct ApprovedMemorySearchResult: Codable, Sendable {
    public let memory: ApprovedMemory
    public let score: Double
    public let reason: String

    public init(memory: ApprovedMemory, score: Double, reason: String) {
        self.memory = memory
        self.score = score
        self.reason = reason
    }
}

// ── memory.get_approved ───────────────────────────────────────────

public struct GetApprovedMemoryInput: Codable, Sendable {
    public let memoryID: String

    public init(memoryID: String) {
        self.memoryID = memoryID
    }
}

public struct GetApprovedMemoryOutput: Codable, Sendable {
    public let memory: ApprovedMemory?

    public init(memory: ApprovedMemory?) {
        self.memory = memory
    }
}

// ═══════════════════════════════════════════════════════════════════
