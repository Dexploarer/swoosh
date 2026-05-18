// SwooshTools/Tool.swift — The Typed Tool Contract (0.4A)
//
// Every tool in Swoosh is a Swift type. Typed at compile time.
// Permissioned. Replayable. Auditable.
//
// 0.4A rule: Every tool is typed. Every risky action is permissioned.
// Every sensitive action is auditable.

import Foundation

// MARK: - Tool name

public struct ToolName: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public init(stringLiteral value: String) { self.rawValue = value }
}

// MARK: - Toolset ID

public enum ToolsetID: String, Codable, Sendable, CaseIterable {
    case core
    case memory
    case permissions
    case scout
    case audit
    case files
    case git
    case swiftDev
    case xcode
    case web
    case browser
    case apple
    case workflow
    case evm
    case solana
    case hyperliquid
    case uniswap
    case mcp
}

// MARK: - SwooshTool protocol (typed)

/// A typed, permissioned, replayable tool that an agent can invoke.
/// Every tool has a typed Input/Output, permission, risk, and approval policy.
public protocol SwooshTool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var name: ToolName { get }
    static var displayName: String { get }
    static var description: String { get }
    static var permission: SwooshPermission { get }
    static var risk: ToolRisk { get }
    static var approval: ApprovalPolicy { get }
    static var toolset: ToolsetID { get }

    func call(
        _ input: Input,
        context: ToolContext
    ) async throws -> Output
}

// MARK: - Type-erased wrapper

/// Type-erased wrapper for tools so the registry can hold heterogeneous tools.
public protocol AnySwooshTool: Sendable {
    var descriptor: ToolDescriptor { get }

    func callJSON(
        _ input: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue
}

// MARK: - Concrete type erasure

/// Wraps any SwooshTool into an AnySwooshTool for registry storage.
public struct TypeErasedTool<T: SwooshTool>: AnySwooshTool {
    private let tool: T

    public init(_ tool: T) { self.tool = tool }

    public var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: T.name.rawValue,
            name: T.name.rawValue,
            displayName: T.displayName,
            description: T.description,
            inputSchema: JSONSchema(type: "object", description: "Input for \(T.name.rawValue)"),
            outputSchema: JSONSchema(type: "object", description: "Output for \(T.name.rawValue)"),
            permission: T.permission,
            risk: T.risk,
            approval: T.approval,
            toolset: T.toolset
        )
    }

    public func callJSON(
        _ input: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        let data = try JSONEncoder().encode(input)
        let typedInput = try JSONDecoder().decode(T.Input.self, from: data)
        let output = try await tool.call(typedInput, context: context)
        let outputData = try JSONEncoder().encode(output)
        return try JSONDecoder().decode(JSONValue.self, from: outputData)
    }
}

// MARK: - Tool descriptor

public struct ToolDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let inputSchema: JSONSchema
    public let outputSchema: JSONSchema
    public let permission: SwooshPermission
    public let risk: ToolRisk
    public let approval: ApprovalPolicy
    public let toolset: ToolsetID

    public init(
        id: String,
        name: String,
        displayName: String,
        description: String,
        inputSchema: JSONSchema,
        outputSchema: JSONSchema,
        permission: SwooshPermission,
        risk: ToolRisk,
        approval: ApprovalPolicy,
        toolset: ToolsetID
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.permission = permission
        self.risk = risk
        self.approval = approval
        self.toolset = toolset
    }
}

// MARK: - Tool context

public struct ToolContext: Sendable {
    public let sessionID: String
    public let safetyConfig: SwooshSafetyConfig
    public let isModelInvocation: Bool
    public let callerIdentity: String

    public init(
        sessionID: String,
        safetyConfig: SwooshSafetyConfig = .v04A,
        isModelInvocation: Bool = true,
        callerIdentity: String = "agent"
    ) {
        self.sessionID = sessionID
        self.safetyConfig = safetyConfig
        self.isModelInvocation = isModelInvocation
        self.callerIdentity = callerIdentity
    }
}

// MARK: - Firewall protocol

/// Permission enforcement boundary. No tool bypasses this.
public protocol Firewall: Sendable {
    func require(_ permission: SwooshPermission) async throws
    func isGranted(_ permission: SwooshPermission) async -> Bool
}

// MARK: - Audit logging protocol

public protocol AuditLogging: Sendable {
    func append(_ event: AuditEntry) async throws
    func tail(limit: Int) async -> [AuditEntry]
    func search(query: String, limit: Int) async -> [AuditEntry]
    func getEvent(id: String) async -> AuditEntry?
}

public struct AuditEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let kind: AuditEntryKind
    public let toolName: String?
    public let sessionID: String?
    public let detail: String
    public let success: Bool

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: AuditEntryKind,
        toolName: String? = nil,
        sessionID: String? = nil,
        detail: String,
        success: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.toolName = toolName
        self.sessionID = sessionID
        self.detail = detail
        self.success = success
    }
}

public enum AuditEntryKind: String, Codable, Sendable {
    case toolCallStarted
    case toolCallSucceeded
    case toolCallFailed
    case toolCallDenied
    case memoryProposed
    case memoryApproved
    case memoryRejected
    case memoryEdited
    case permissionGranted
    case permissionDenied
    case approvalGranted
    case approvalDenied
    case workflowStarted
    case workflowCompleted
    case safetyViolation
}

// MARK: - JSONValue extensions

extension JSONValue {
    /// Returns a redacted preview suitable for audit logs.
    /// Truncates long strings, replaces known sensitive patterns.
    public func redactedPreview(maxLength: Int = 200) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              var text = String(data: data, encoding: .utf8) else {
            return "<unserializable>"
        }
        // Redact known sensitive patterns
        let sensitivePatterns = [
            "private_key", "privateKey", "seed_phrase", "seedPhrase",
            "mnemonic", "password", "secret", "cookie", "token"
        ]
        for pattern in sensitivePatterns {
            if text.localizedCaseInsensitiveContains(pattern) {
                let regexPattern = "\"\(pattern)\"\\s*:\\s*\"[^\"]*\""
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                    text = regex.stringByReplacingMatches(
                        in: text,
                        range: NSRange(text.startIndex..., in: text),
                        withTemplate: "\"\(pattern)\":\"[REDACTED]\""
                    )
                }
            }
        }
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text
    }
}

