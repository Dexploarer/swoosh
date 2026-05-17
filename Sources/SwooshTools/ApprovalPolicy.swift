// SwooshTools/ApprovalPolicy.swift — Risk and Approval Model
//
// Every tool declares risk and approval policy.
// Read broadly. Build safely. Simulate first.
// Sign only with human approval. Broadcast only with human approval.

import Foundation

// MARK: - Tool risk

public enum ToolRisk: String, Codable, Sendable, Comparable, CaseIterable {
    case readOnly
    case low
    case medium
    case high
    case critical

    private var ordinal: Int {
        switch self {
        case .readOnly: return 0
        case .low:      return 1
        case .medium:   return 2
        case .high:     return 3
        case .critical: return 4
        }
    }

    public static func < (lhs: ToolRisk, rhs: ToolRisk) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

// MARK: - Approval policy

public enum ApprovalPolicy: Codable, Sendable, Equatable {
    case never
    case askFirstTime
    case askEveryTime
    case askForRiskAtLeast(ToolRisk)
    case humanOnly
    case disabled

    public var requiresUserApproval: Bool {
        switch self {
        case .never:
            return false
        case .askFirstTime, .askEveryTime, .askForRiskAtLeast, .humanOnly:
            return true
        case .disabled:
            return true
        }
    }

    /// Whether this tool can be invoked by the model at all (vs. human-only).
    public var modelCanInvoke: Bool {
        switch self {
        case .humanOnly, .disabled:
            return false
        default:
            return true
        }
    }
}

// MARK: - Approval request

public struct ToolApprovalRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let risk: ToolRisk
    public let inputPreview: String
    public let sessionID: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        risk: ToolRisk,
        inputPreview: String,
        sessionID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.risk = risk
        self.inputPreview = inputPreview
        self.sessionID = sessionID
        self.createdAt = createdAt
    }
}

// MARK: - Approval decision

public enum ApprovalDecision: String, Codable, Sendable {
    case approveOnce
    case approveForSession
    case deny
}

// MARK: - Approval requesting protocol

/// Implemented by the runtime to present approval UI.
public protocol ApprovalRequesting: Sendable {
    func requireApproval(_ request: ToolApprovalRequest) async throws
    func listPending() async -> [ToolApprovalRequest]
    func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws
}

// MARK: - Codable conformance for ApprovalPolicy

extension ApprovalPolicy {
    private enum CodingKeys: String, CodingKey {
        case type, minimumRisk
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "never":           self = .never
        case "askFirstTime":    self = .askFirstTime
        case "askEveryTime":    self = .askEveryTime
        case "askForRiskAtLeast":
            let risk = try container.decode(ToolRisk.self, forKey: .minimumRisk)
            self = .askForRiskAtLeast(risk)
        case "humanOnly":       self = .humanOnly
        case "disabled":        self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown ApprovalPolicy type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never:           try container.encode("never", forKey: .type)
        case .askFirstTime:    try container.encode("askFirstTime", forKey: .type)
        case .askEveryTime:    try container.encode("askEveryTime", forKey: .type)
        case .askForRiskAtLeast(let risk):
            try container.encode("askForRiskAtLeast", forKey: .type)
            try container.encode(risk, forKey: .minimumRisk)
        case .humanOnly:       try container.encode("humanOnly", forKey: .type)
        case .disabled:        try container.encode("disabled", forKey: .type)
        }
    }
}
