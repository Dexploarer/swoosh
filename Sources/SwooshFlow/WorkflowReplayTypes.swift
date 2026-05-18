// SwooshFlow/WorkflowReplayTypes.swift — 0.5C Read-Only Replay Types
//
// Manual-only, read-only workflow replay.
// No scheduling, no writes, no signing, no broadcasting.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Replay mode and scope
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowReplayMode: String, Codable, Sendable {
    case readOnlyManual
}

public enum WorkflowReplayScope: String, Codable, Sendable {
    case allSteps
    case readOnlyStepsOnly
    case untilFirstBlockedStep
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Replay request
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowReplayRequest: Codable, Sendable {
    public let draftID: String
    public let providedInputs: [String: JSONValue]
    public let mode: WorkflowReplayMode
    public let scope: WorkflowReplayScope
    public let createdAt: Date

    public init(
        draftID: String, providedInputs: [String: JSONValue] = [:],
        mode: WorkflowReplayMode = .readOnlyManual,
        scope: WorkflowReplayScope = .allSteps,
        createdAt: Date = Date()
    ) {
        self.draftID = draftID; self.providedInputs = providedInputs
        self.mode = mode; self.scope = scope; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Replay policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowReplayPolicy: Sendable {
    public let mode: WorkflowReplayMode
    public let allowedRisks: Set<ToolRisk>
    public let allowedApprovals: [ApprovalPolicy]
    public let maxSteps: Int
    public let maxOutputBytesPerStep: Int
    public let stopOnFailure: Bool

    public init(
        mode: WorkflowReplayMode = .readOnlyManual,
        allowedRisks: Set<ToolRisk> = [.readOnly],
        allowedApprovals: [ApprovalPolicy] = [.never],
        maxSteps: Int = 24,
        maxOutputBytesPerStep: Int = 12_000,
        stopOnFailure: Bool = false
    ) {
        self.mode = mode; self.allowedRisks = allowedRisks
        self.allowedApprovals = allowedApprovals
        self.maxSteps = maxSteps; self.maxOutputBytesPerStep = maxOutputBytesPerStep
        self.stopOnFailure = stopOnFailure
    }

    public static let readOnlyManual = WorkflowReplayPolicy()
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Step execution decision
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowStepExecutionDecision: Codable, Sendable {
    public let action: WorkflowStepExecutionAction
    public let reason: WorkflowStepSkipReason?
    public let message: String

    public init(action: WorkflowStepExecutionAction, reason: WorkflowStepSkipReason? = nil, message: String) {
        self.action = action; self.reason = reason; self.message = message
    }

    public static func skip(_ reason: WorkflowStepSkipReason, _ message: String) -> Self {
        .init(action: .skip, reason: reason, message: message)
    }
    public static func execute(_ message: String = "Read-only tool allowed.") -> Self {
        .init(action: .execute, message: message)
    }
}

public enum WorkflowStepExecutionAction: String, Codable, Sendable {
    case execute, skip, block
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Step execution policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowStepExecutionPolicy: Sendable {

    /// Tools explicitly allowed in read-only replay.
    private static let allowedReadOnlyTools: Set<String> = [
        // Core
        "core.status", "core.explain_context", "core.list_toolsets", "core.list_tools", "core.get_tool_schema",
        // Memory
        "memory.list_approved", "memory.search_approved", "memory.get_approved",
        // Permissions
        "permissions.summary", "permissions.get",
        // Audit
        "audit.tail", "audit.search", "audit.get_event",
        // Workflow read-only
        "workflow.get_draft", "workflow.validate_draft", "workflow.render_plan", "workflow.resolve_inputs",
        // File read-only
        "file.list", "file.read", "file.search",
        // Git read-only
        "git.status", "git.diff", "git.log", "git.branch_list",
        // Swift read-only
        "swift.package_describe", "swift.diagnostics",
        // EVM read-only
        "evm.chain_info", "evm.address_validate", "evm.account_balance_native", "evm.account_nonce",
        "evm.contract_get_code", "evm.contract_call", "evm.contract_get_logs",
        "evm.erc20_balance", "evm.erc20_allowance",
        "evm.abi_encode_call", "evm.abi_decode_result",
        "evm.tx_estimate_gas", "evm.tx_get_receipt", "evm.tx_get_by_hash",
        // Solana read-only
        "solana.cluster_info", "solana.address_validate", "solana.account_balance", "solana.account_info",
        "solana.token_account_balance", "solana.token_accounts_by_owner",
        "solana.tx_signatures_for_address", "solana.tx_get_transaction",
        "solana.tx_get_signature_statuses", "solana.tx_get_latest_blockhash",
    ]

    /// Tools explicitly blocked even if they look read-only.
    private static let explicitlyBlockedTools: Set<String> = [
        "file.write", "file.patch", "file.delete",
        "git.apply_patch", "git.commit", "git.checkout", "git.push",
        "swift.build", "swift.test",
        "vault.approve_candidate", "vault.reject_candidate", "vault.edit_candidate",
        "approvals.resolve",
        "workflow.save_draft", "workflow.update_draft", "workflow.delete_draft", "workflow.run", "workflow.enable",
        "evm.tx_build_native_transfer", "evm.tx_build_contract_call", "evm.erc20_build_transfer", "evm.erc20_build_approve",
        "evm.wallet_connect", "evm.tx_request_signature", "evm.tx_broadcast_signed", "evm.tx_preflight",
        "solana.tx_simulate", "solana.tx_build_sol_transfer", "solana.tx_build_spl_transfer",
        "solana.wallet_connect", "solana.tx_request_signature", "solana.tx_send_signed", "solana.tx_request_airdrop",
    ]

    public init() {}

    public func decide(
        step: WorkflowStepPlan,
        descriptor: ToolDescriptor?,
        policy: WorkflowReplayPolicy
    ) -> WorkflowStepExecutionDecision {
        // Non-tool steps (modelSummarize, humanReview, note) → skip
        guard step.kind == .toolCall || step.kind == .approvalGate else {
            return .skip(.blockedByPolicy, "Only tool-call steps execute in replay.")
        }

        guard let toolName = step.toolName else {
            return .skip(.unsupportedTool, "Step has no tool name.")
        }

        // Explicitly blocked
        if Self.explicitlyBlockedTools.contains(toolName) {
            let reason = skipReason(for: toolName)
            return .skip(reason, "\(toolName) is not allowed in read-only replay.")
        }

        // Must be on the allowlist
        guard Self.allowedReadOnlyTools.contains(toolName) else {
            return .skip(.unsupportedTool, "\(toolName) is not in the read-only allowlist.")
        }

        // Check descriptor if available
        if let desc = descriptor {
            guard policy.allowedRisks.contains(desc.risk) else {
                return .skip(.notReadOnly, "\(toolName) has risk \(desc.risk.rawValue), only readOnly allowed.")
            }
            guard policy.allowedApprovals.contains(desc.approval) else {
                return .skip(.requiresApproval, "\(toolName) requires approval (\(desc.approval)).")
            }
        }

        return .execute()
    }

    /// Map tool name to specific skip reason.
    public func skipReason(for toolName: String) -> WorkflowStepSkipReason {
        if toolName.contains("broadcast") || toolName.contains("send_signed")
            || toolName.contains("request_signature") { return .signingOrBroadcast }
        if toolName.contains("tx_build") || toolName.contains("erc20_build")
            || toolName.contains("wallet_connect") || toolName.contains("airdrop") { return .blockchainWrite }
        if toolName.hasPrefix("file.write") || toolName.hasPrefix("file.patch") { return .writeTool }
        if toolName.hasPrefix("file.delete") { return .destructiveTool }
        if toolName.hasPrefix("git.commit") || toolName.hasPrefix("git.push")
            || toolName.hasPrefix("git.checkout") || toolName.hasPrefix("git.apply") { return .writeTool }
        if toolName.hasPrefix("swift.build") || toolName.hasPrefix("swift.test") { return .notReadOnly }
        if toolName.hasPrefix("vault.") || toolName.hasPrefix("approvals.") { return .humanOnly }
        if toolName.contains("enable") || toolName.contains("schedule") { return .blockedByPolicy }
        return .blockedByPolicy
    }

    /// Check if a tool name is on the read-only allowlist.
    public static func isAllowed(_ toolName: String) -> Bool {
        allowedReadOnlyTools.contains(toolName)
    }
}

// ═══════════════════════════════════════════════════════════════════
