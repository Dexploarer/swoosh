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
    private let stakeGate: (any StakeGating)?
    private let receiptTracker: (any ReceiptTracking)?

    public init(
        firewall: any Firewall,
        audit: any AuditLogging,
        approvals: any ApprovalRequesting,
        safetyConfig: SwooshSafetyConfig = .defaultAgent,
        stakeGate: (any StakeGating)? = nil,
        receiptTracker: (any ReceiptTracking)? = nil
    ) {
        self.firewall = firewall
        self.audit = audit
        self.approvals = approvals
        self.safetyConfig = safetyConfig
        self.stakeGate = stakeGate
        self.receiptTracker = receiptTracker
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

    /// Unregister a previously-registered tool by name. Used by the plugin
    /// host to drop a plugin's tools from the catalog when it's disabled,
    /// so the model doesn't keep seeing them. No-op if the name isn't
    /// registered. Returns true if a tool was removed.
    @discardableResult
    public func unregister(name: ToolName) -> Bool {
        tools.removeValue(forKey: name) != nil
    }

    public func listAvailable(
        context: ToolContext
    ) async -> [ToolDescriptor] {
        tools.values
            .filter { enabledToolsets.contains($0.descriptor.toolset) }
            .filter { descriptorAllowedInCatalog($0.descriptor, context: context) }
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
        let effectiveContext = context.withSafetyConfig(safetyConfig)

        // 1. Check toolset is enabled
        guard enabledToolsets.contains(descriptor.toolset) else {
            throw ToolError.toolsetDisabled(descriptor.toolset.rawValue)
        }

        if descriptor.approval == .disabled {
            throw ToolError.disabled(descriptor.name)
        }

        // 2. Check approval policy allows model invocation
        if effectiveContext.isModelInvocation && descriptor.approval == .humanOnly && !canModelPromptHumanOnly(descriptor) {
            try await audit.append(AuditEntry(
                kind: .toolCallDenied,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "humanOnly tool cannot be invoked by model",
                success: false
            ))
            throw ToolError.humanOnly(descriptor.name)
        }

        if let denial = tradingSafetyDenial(for: descriptor) {
            try await audit.append(AuditEntry(
                kind: .toolCallDenied,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: denial,
                success: false
            ))
            throw ToolError.policyViolation(denial)
        }

        if let denial = policyDenial(for: descriptor, context: effectiveContext) {
            try await audit.append(AuditEntry(
                kind: .toolCallDenied,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: denial,
                success: false
            ))
            throw ToolError.policyViolation(denial)
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

        // 3.5. Token gate — only premium actions (launching tokens)
        if descriptor.isTokenGated, let gate = stakeGate {
            do {
                try await gate.requireStake(
                    wallet: context.walletAddress,
                    toolsetID: descriptor.toolset.rawValue
                )
            } catch {
                try await audit.append(AuditEntry(
                    kind: .toolCallDenied,
                    toolName: descriptor.name,
                    sessionID: context.sessionID,
                    detail: "$DTOUR stake required to launch tokens via \(descriptor.displayName)",
                    success: false
                ))
                throw error
            }
        }

        // 4. Approval check
        if approvalRequired(for: descriptor, context: effectiveContext) {
            try await approvals.requireApproval(
                ToolApprovalRequest(
                    toolName: descriptor.name,
                    risk: descriptor.risk,
                    permission: descriptor.permission,
                    approvalPolicy: descriptor.approval,
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
            let output = try await tool.callJSON(input, context: effectiveContext)
            let successEntryID = UUID().uuidString
            try await audit.append(AuditEntry(
                id: successEntryID,
                kind: .toolCallSucceeded,
                toolName: descriptor.name,
                sessionID: context.sessionID,
                detail: "Completed \(descriptor.name)"
            ))
            // 6b. Track receipt for rebate + anchoring (crypto toolsets)
            if descriptor.toolset.isCrypto, !context.walletAddress.isEmpty {
                try? await receiptTracker?.trackReceipt(
                    auditEntryID: successEntryID,
                    toolName: descriptor.name,
                    toolsetID: descriptor.toolset.rawValue,
                    wallet: context.walletAddress
                )
            }
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
        let effectiveContext = context.withSafetyConfig(safetyConfig)

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
        if effectiveContext.isModelInvocation && descriptor.approval == .humanOnly && !canModelPromptHumanOnly(descriptor) {
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

        if let denial = tradingSafetyDenial(for: descriptor) {
            try? await audit.append(AuditEntry(
                kind: .toolCallDenied, toolName: descriptor.name, sessionID: context.sessionID,
                detail: denial, success: false
            ))
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .blockedByPermission,
                errorMessage: denial
            )
        }

        if let denial = policyDenial(for: descriptor, context: effectiveContext) {
            try? await audit.append(AuditEntry(
                kind: .toolCallDenied, toolName: descriptor.name, sessionID: context.sessionID,
                detail: denial, success: false
            ))
            return ToolExecutionResult(
                requestID: request.id, toolName: request.toolName,
                status: .blockedByPermission,
                errorMessage: denial
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

        // 4.5. Token gate — only premium actions (launching tokens)
        if descriptor.isTokenGated, let gate = stakeGate {
            do {
                try await gate.requireStake(
                    wallet: context.walletAddress,
                    toolsetID: descriptor.toolset.rawValue
                )
            } catch {
                try? await audit.append(AuditEntry(
                    kind: .toolCallDenied, toolName: descriptor.name, sessionID: context.sessionID,
                    detail: "$DTOUR stake required to launch tokens via \(descriptor.displayName)", success: false
                ))
                return ToolExecutionResult(
                    requestID: request.id, toolName: request.toolName,
                    status: .blockedByPermission,
                    errorMessage: "Launching tokens requires $DTOUR stake. Stake at https://dtour.ai/stake"
                )
            }
        }

        // 5. Approval check
        if approvalRequired(for: descriptor, context: effectiveContext) {
            let approvalReq = ToolApprovalRequest(
                toolName: descriptor.name, risk: descriptor.risk,
                permission: descriptor.permission,
                approvalPolicy: descriptor.approval,
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
            let output = try await tool.callJSON(request.arguments, context: effectiveContext)
            let finishedAt = Date()
            let successEntryID = UUID().uuidString
            try? await audit.append(AuditEntry(
                id: successEntryID,
                kind: .toolCallSucceeded, toolName: descriptor.name, sessionID: context.sessionID,
                detail: "Completed \(descriptor.name)"
            ))
            // Track receipt for rebate + anchoring (crypto toolsets)
            if descriptor.toolset.isCrypto, !context.walletAddress.isEmpty {
                try? await receiptTracker?.trackReceipt(
                    auditEntryID: successEntryID,
                    toolName: descriptor.name,
                    toolsetID: descriptor.toolset.rawValue,
                    wallet: context.walletAddress
                )
            }
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

    private func descriptorAllowedInCatalog(_ descriptor: ToolDescriptor, context: ToolContext) -> Bool {
        guard context.isModelInvocation else { return true }
        guard descriptor.approval != .disabled else { return false }
        guard tradingSafetyDenial(for: descriptor) == nil else { return false }
        if humanPromptedTradingAllowsModelInvocation(for: descriptor) {
            return true
        }
        return context.toolPolicy.modelInvocationDenial(for: descriptor) == nil
    }

    private func policyDenial(for descriptor: ToolDescriptor, context: ToolContext) -> String? {
        guard context.isModelInvocation else { return nil }
        if descriptor.approval == .disabled {
            return "\(descriptor.name) is disabled"
        }
        if safetyConfig.modelSelfApprovalEnabled {
            return nil
        }
        if humanPromptedTradingAllowsModelInvocation(for: descriptor) {
            return nil
        }
        return context.toolPolicy.modelInvocationDenial(for: descriptor)
    }

    private func approvalRequired(for descriptor: ToolDescriptor, context: ToolContext) -> Bool {
        if context.isModelInvocation && safetyConfig.modelSelfApprovalEnabled {
            return false
        }
        if context.isModelInvocation && humanPromptedTradingAllowsModelInvocation(for: descriptor) {
            return true
        }
        switch descriptor.approval {
        case .never:
            break
        case .askFirstTime, .askEveryTime:
            return true
        case .askForRiskAtLeast(let minimumRisk):
            return descriptor.risk >= minimumRisk
        case .humanOnly, .disabled:
            return false
        }
        return context.isModelInvocation &&
            context.toolPolicy.requireApprovalForMediumRiskAndAbove &&
            descriptor.risk >= .medium
    }

    private func canModelPromptHumanOnly(_ descriptor: ToolDescriptor) -> Bool {
        safetyConfig.modelSelfApprovalEnabled || humanPromptedTradingAllowsModelInvocation(for: descriptor)
    }

    private func humanPromptedTradingAllowsModelInvocation(for descriptor: ToolDescriptor) -> Bool {
        safetyConfig.humanPromptedTradingEnabled && descriptor.isTradingWriteTool
    }

    private func tradingSafetyDenial(for descriptor: ToolDescriptor) -> String? {
        guard descriptor.isTradingWriteTool else { return nil }
        guard safetyConfig.humanPromptedTradingEnabled || safetyConfig.autonomousTradingEnabled else {
            return "\(descriptor.name) requires human-prompted or autonomous trading to be enabled"
        }
        return nil
    }
}

private extension ToolDescriptor {
    var isTradingWriteTool: Bool {
        switch permission {
        case .evmBuildTransaction,
             .evmRequestSignature,
             .evmBroadcast,
             .evmMainnetWrite,
             .solanaBuildTransaction,
             .solanaRequestSignature,
             .solanaBroadcast,
             .solanaMainnetWrite,
             .hyperliquidTrade,
             .hyperliquidTransfer:
            return true
        default:
            return false
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
    case notImplemented(String)
}
