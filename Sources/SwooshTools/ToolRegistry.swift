// SwooshTools/ToolRegistry.swift — Tool registry actor and extensions
import Foundation

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
        safetyConfig: SwooshSafetyConfig = .defaultAgent
    ) {
        self.firewall = firewall
        self.audit = audit
        self.approvals = approvals
        self.safetyConfig = safetyConfig
    }

    /// Register a tool. Tools whose `platforms` set does not include the
    /// current host platform are silently dropped — the model's catalog
    /// shouldn't list anything we can't actually execute. Returns true if
    /// the tool was registered, false if it was filtered out.
    @discardableResult
    public func register(_ tool: any AnySwooshTool) -> Bool {
        let descriptor = tool.descriptor
        guard descriptor.platforms.contains(ToolPlatform.current) else {
            return false
        }
        tools[ToolName(descriptor.name)] = tool
        return true
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
                    permission: descriptor.permission,
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
                permission: descriptor.permission,
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

public struct RegistryWorkflowStepExecutor: WorkflowStepExecuting {
    private let registry: ToolRegistry

    public init(registry: ToolRegistry) {
        self.registry = registry
    }

    public func executeWorkflowStep(
        toolName: String,
        arguments: JSONValue,
        context: ToolContext
    ) async throws -> ToolExecutionResult {
        await registry.execute(
            request: ToolExecutionRequest(
                toolName: toolName,
                arguments: arguments,
                origin: .workflow,
                sessionID: context.sessionID
            ),
            context: context
        )
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
