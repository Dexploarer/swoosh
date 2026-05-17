// SwooshTools/Types.swift — Shared lightweight value types
//
// These are referenced by Tool.swift and the rest of the codebase.
// Kept minimal and Sendable for actor isolation.
//
// NOTE: ToolsetID is now an enum in Tool.swift (0.4A)
// NOTE: Permission is now SwooshPermission (0.4A)
// NOTE: RiskLevel is now ToolRisk (0.4A)
// NOTE: ToolDescriptor is now in Tool.swift (0.4A)
// NOTE: ToolContext is now in Tool.swift (0.4A)
// NOTE: AuditEvent is now AuditEntry/AuditEntryKind (0.4A)
// NOTE: ApprovalEngine is now ApprovalRequesting (0.4A)
// NOTE: AuditLog is now AuditLogging (0.4A)
// NOTE: ToolError is now in Tool.swift (0.4A)

import Foundation

// MARK: - Identifiers

public struct SessionID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct SkillID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ProviderID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - JSON primitives

/// A lightweight JSON value type used for tool arguments and results.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self)   { self = .bool(b) }
        else if let i = try? container.decode(Int.self)    { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .double(d) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:           try container.encodeNil()
        case .bool(let v):    try container.encode(v)
        case .int(let v):     try container.encode(v)
        case .double(let v):  try container.encode(v)
        case .string(let v):  try container.encode(v)
        case .array(let v):   try container.encode(v)
        case .object(let v):  try container.encode(v)
        }
    }
}

/// Minimal JSON Schema representation for tool input definitions.
/// Uses indirect storage to support recursive `items` and `properties`.
public final class JSONSchema: Codable, Sendable, Equatable {
    public let type: String
    public let properties: [String: JSONSchema]?
    public let required: [String]?
    public let description: String?
    public let items: JSONSchema?
    public let enumValues: [String]?

    public init(
        type: String,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        description: String? = nil,
        items: JSONSchema? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.description = description
        self.items = items
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, properties, required, description, items
        case enumValues = "enum"
    }

    public static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        lhs.type == rhs.type &&
        lhs.properties == rhs.properties &&
        lhs.required == rhs.required &&
        lhs.description == rhs.description &&
        lhs.items == rhs.items &&
        lhs.enumValues == rhs.enumValues
    }
}

// MARK: - Messages

public enum ChatRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
    case tool
}

public struct ChatMessage: Codable, Sendable, Identifiable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let toolCallID: String?
    public let createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, content: String, toolCallID: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.createdAt = createdAt
    }
}

public struct ToolCall: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String = UUID().uuidString, name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Model routing

public enum ModelRoute: Codable, Sendable {
    /// Let the router decide (Foundation → MLX → remote)
    case auto
    /// Force local Foundation Models
    case foundation
    /// Force local MLX model
    case mlx(model: String)
    /// Force a specific remote provider
    case remote(provider: String, model: String)
    /// Try local first, fallback to remote
    case localFirst(fallback: String)
}

// MARK: - Agent budget

public struct AgentBudget: Codable, Sendable {
    public let maxTurns: Int
    public let maxCostUSD: Double
    public let maxDuration: TimeInterval

    public init(maxTurns: Int = 50, maxCostUSD: Double = 5.0, maxDuration: TimeInterval = 600) {
        self.maxTurns = maxTurns
        self.maxCostUSD = maxCostUSD
        self.maxDuration = maxDuration
    }

    public static let `default` = AgentBudget()
}

// MARK: - Memory categories (shared between SwooshVault and SwooshTools)

public enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case fact
    case preference
    case project
    case person
    case place
    case workflow
    case toolQuirk
    case reusableDecision
    case failedAssumption
    case sensitive
    case expiring
}

// MARK: - Legacy type aliases (for backward compat during 0.4A migration)

@available(*, deprecated, renamed: "SwooshPermission")
public typealias Permission = SwooshPermission

@available(*, deprecated, renamed: "ToolRisk")
public typealias RiskLevel = ToolRisk

