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

// MARK: - Tool registry actor

/// Typed tool registry with firewall, audit, and approval integration.
/// No tool can bypass the firewall. Every call is audited.
public actor ToolRegistry {
    private var tools: [ToolName: any AnySwooshTool] = [:]
    private var enabledToolsets: Set<ToolsetID> = Set(ToolsetID.allCases)
    private let firewall: any Firewall
    private let audit: any AuditLogging
    private let approvals: any ApprovalRequesting
    private let safetyConfig: SwooshSafetyConfig

    public init(
        firewall: any Firewall,
        audit: any AuditLogging,
        approvals: any ApprovalRequesting,
        safetyConfig: SwooshSafetyConfig = .v04A
    ) {
        self.firewall = firewall
        self.audit = audit
        self.approvals = approvals
        self.safetyConfig = safetyConfig
    }

    public func register(_ tool: any AnySwooshTool) {
        tools[ToolName(tool.descriptor.name)] = tool
    }

    public func listAvailable(
        context: ToolContext
    ) async -> [ToolDescriptor] {
        tools.values
            .filter { enabledToolsets.contains($0.descriptor.toolset) }
            .map(\.descriptor)
    }

    public func listToolsets() -> [ToolsetID] {
        Array(enabledToolsets).sorted { $0.rawValue < $1.rawValue }
    }

    public func enableToolset(_ id: ToolsetID) {
        enabledToolsets.insert(id)
    }

    public func disableToolset(_ id: ToolsetID) {
        enabledToolsets.remove(id)
    }

    public func getToolSchema(name: ToolName) -> ToolDescriptor? {
        tools[name]?.descriptor
    }

    public func call(
        name: ToolName,
        input: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        guard let tool = tools[name] else {
            throw ToolError.notFound(name.rawValue)
        }

        let descriptor = tool.descriptor

        // 1. Check toolset is enabled
        guard enabledToolsets.contains(descriptor.toolset) else {
            throw ToolError.toolsetDisabled(descriptor.toolset.rawValue)
        }

        // 2. Check approval policy allows model invocation
        if context.isModelInvocation && !descriptor.approval.modelCanInvoke {
            try await audit.append(AuditEntry(
                kind: .toolCallDenied,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "humanOnly tool cannot be invoked by model",
                success: false
            ))
            throw ToolError.humanOnly(descriptor.name)
        }

        // 3. Firewall permission check (no bypass)
        do {
            try await firewall.require(descriptor.permission)
        } catch {
            try await audit.append(AuditEntry(
                kind: .toolCallDenied,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "Permission denied: \(descriptor.permission.rawValue)",
                success: false
            ))
            throw error
        }

        // 4. Approval check
        if descriptor.approval.requiresUserApproval {
            try await approvals.requireApproval(
                ToolApprovalRequest(
                    toolName: descriptor.name,
                    risk: descriptor.risk,
                    inputPreview: input.redactedPreview(),
                    sessionID: context.sessionID
                )
            )
        }

        // 5. Audit: started
        try await audit.append(AuditEntry(
            kind: .toolCallStarted,
            toolName: descriptor.name,
            sessionID: context.sessionID,
            detail: "Calling \(descriptor.name)"
        ))

        // 6. Execute
        do {
            let output = try await tool.callJSON(input, context: context)
            try await audit.append(AuditEntry(
                kind: .toolCallSucceeded,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "Completed \(descriptor.name)"
            ))
            return output
        } catch {
            try await audit.append(AuditEntry(
                kind: .toolCallFailed,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "Failed \(descriptor.name): \(error.localizedDescription)",
                success: false
            ))
            throw error
        }
    }

    // MARK: - 0.4B: Execute from ToolExecutionRequest → ToolExecutionResult

    /// Execute a tool from a ToolExecutionRequest, returning a ToolExecutionResult.
    /// This is the primary entry point for the agent tool loop.
    /// All errors are caught and returned as result statuses — the agent loop does not throw.
    public func execute(
        request: ToolExecutionRequest,
        context: ToolContext
    ) async -> ToolExecutionResult {
        let startedAt = Date()

        guard let tool = tools[ToolName(request.toolName)] else {
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .failed, errorMessage: "Tool not found: \(request.toolName)"
            )
        }

        let descriptor = tool.descriptor

        // 1. Toolset check
        guard enabledToolsets.contains(descriptor.toolset) else {
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .disabled, errorMessage: "Toolset \(descriptor.toolset.rawValue) is disabled"
            )
        }

        // 2. disabled check
        if descriptor.approval == .disabled {
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .disabled, errorMessage: "\(request.toolName) is disabled"
            )
        }

        // 3. humanOnly check
        if context.isModelInvocation && !descriptor.approval.modelCanInvoke {
            try? await audit.append(AuditEntry(
                kind: .toolCallDenied, toolName: descriptor.name, sessionID: context.sessionID,
                detail: "humanOnly tool \(descriptor.name) cannot be invoked by model", success: false
            ))
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .blockedByPermission,
                errorMessage: "\(request.toolName) is human-only and cannot be executed by the model"
            )
        }

        // 4. Firewall permission
        do {
            try await firewall.require(descriptor.permission)
        } catch {
            try? await audit.append(AuditEntry(
                kind: .toolCallDenied, toolName: descriptor.name, sessionID: context.sessionID,
                detail: "Permission denied: \(descriptor.permission.rawValue)", success: false
            ))
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .blockedByPermission, errorMessage: "Permission \(descriptor.permission.rawValue) not granted"
            )
        }

        // 5. Approval check (for tools where model CAN invoke but approval is required)
        if descriptor.approval.requiresUserApproval && descriptor.approval.modelCanInvoke {
            let approvalReq = ToolApprovalRequest(
                toolName: descriptor.name, risk: descriptor.risk,
                inputPreview: request.arguments.redactedPreview(), sessionID: context.sessionID
            )
            do {
                try await approvals.requireApproval(approvalReq)
            } catch let error as ToolError {
                if case .pendingApproval(let approvalID) = error {
                    return ToolExecutionResult(
                        requestID: request.id, toolName: request.toolName,
                        status: .pendingApproval, approvalID: approvalID
                    )
                }
                return ToolExecutionResult(
                    requestID: request.id, toolName: request.toolName,
                    status: .deniedByUser, errorMessage: "Approval denied"
                )
            } catch {
                return ToolExecutionResult(
                    requestID: request.id, toolName: request.toolName,
                    status: .pendingApproval, errorMessage: "Approval required"
                )
            }
        }

        // 6. Audit: started
        try? await audit.append(AuditEntry(
            kind: .toolCallStarted, toolName: descriptor.name, sessionID: context.sessionID,
            detail: "Calling \(descriptor.name)"
        ))

        // 7. Execute
        do {
            let output = try await tool.callJSON(request.arguments, context: context)
            let finishedAt = Date()
            try? await audit.append(AuditEntry(
                kind: .toolCallSucceeded, toolName: descriptor.name, sessionID: context.sessionID,
                detail: "Completed \(descriptor.name)"
            ))
            let trace = ToolCallTrace(
                sessionID: context.sessionID, requestID: request.id, toolName: request.toolName,
                origin: request.origin, risk: descriptor.risk, permission: descriptor.permission,
                approvalPolicy: descriptor.approval, status: .succeeded,
                startedAt: startedAt, finishedAt: finishedAt,
                inputPreview: request.arguments.redactedPreview(),
                outputPreview: output.redactedPreview()
            )
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .succeeded, output: output, trace: trace
            )
        } catch {
            let finishedAt = Date()
            try? await audit.append(AuditEntry(
                kind: .toolCallFailed, toolName: descriptor.name, sessionID: context.sessionID,
                detail: "Failed \(descriptor.name): \(error.localizedDescription)", success: false
            ))
            let trace = ToolCallTrace(
                sessionID: context.sessionID, requestID: request.id, toolName: request.toolName,
                origin: request.origin, risk: descriptor.risk, permission: descriptor.permission,
                approvalPolicy: descriptor.approval, status: .failed,
                startedAt: startedAt, finishedAt: finishedAt,
                inputPreview: request.arguments.redactedPreview()
            )
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .failed, errorMessage: error.localizedDescription, trace: trace
            )
        }
    }
}

public enum ToolError: Error, Sendable {
    case notFound(String)
    case denied(String, String)
    case invalidInput(String)
    case humanOnly(String)
    case toolsetDisabled(String)
    case executionFailed(String)
    case disabled(String)
    case pendingApproval(String)
    case policyViolation(String)
}
