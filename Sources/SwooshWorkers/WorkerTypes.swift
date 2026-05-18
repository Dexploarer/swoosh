// SwooshWorkers/WorkerTypes.swift — 0.7B Board Workers + Subagents
//
// Constrained workers that claim board cards, work in isolated sessions,
// use restricted tools, and report through the board.
// Workers do NOT bypass ToolRegistry, Firewall, or ApprovalCenter.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker lane
// ═══════════════════════════════════════════════════════════════════

public struct WorkerLane: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var description: String
    public var profile: WorkerProfile
    public var toolPolicy: WorkerToolPolicy
    public var budget: WorkerBudget
    public var maxConcurrentRuns: Int
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, name: String, description: String = "",
        profile: WorkerProfile, toolPolicy: WorkerToolPolicy,
        budget: WorkerBudget = .small, maxConcurrentRuns: Int = 1,
        enabled: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.description = description
        self.profile = profile; self.toolPolicy = toolPolicy; self.budget = budget
        self.maxConcurrentRuns = maxConcurrentRuns; self.enabled = enabled
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker profile
// ═══════════════════════════════════════════════════════════════════

public struct WorkerProfile: Codable, Sendable {
    public let id: String
    public var displayName: String
    public var rolePrompt: String
    public var maxContextMessages: Int

    public init(id: String, displayName: String, rolePrompt: String, maxContextMessages: Int = 24) {
        self.id = id; self.displayName = displayName; self.rolePrompt = rolePrompt
        self.maxContextMessages = maxContextMessages
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker tool policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkerToolPolicy: Codable, Sendable {
    public let allowedTools: [String]
    public let deniedTools: [String]
    public let maxRiskWithoutApproval: ToolRisk
    public let allowHumanOnlyTools: Bool
    public let allowToolApprovalResolution: Bool
    public let allowWorkerSpawning: Bool
    public let allowPermissionRequests: Bool

    public init(
        allowedTools: [String] = [], deniedTools: [String] = [],
        maxRiskWithoutApproval: ToolRisk = .readOnly, allowHumanOnlyTools: Bool = false,
        allowToolApprovalResolution: Bool = false, allowWorkerSpawning: Bool = false,
        allowPermissionRequests: Bool = false
    ) {
        self.allowedTools = allowedTools; self.deniedTools = deniedTools
        self.maxRiskWithoutApproval = maxRiskWithoutApproval
        self.allowHumanOnlyTools = allowHumanOnlyTools
        self.allowToolApprovalResolution = allowToolApprovalResolution
        self.allowWorkerSpawning = allowWorkerSpawning
        self.allowPermissionRequests = allowPermissionRequests
    }

    /// Always-denied tools across all worker lanes.
    public static let globalDenied: Set<String> = [
        "file.delete", "git.push", "git.checkout",
        "evm.wallet_connect", "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.wallet_connect", "solana.tx_request_signature", "solana.tx_send_signed",
        "solana.tx_request_airdrop",
        "approval.resolve",
    ]

    public func isAllowed(_ toolName: String) -> Bool {
        if Self.globalDenied.contains(toolName) { return false }
        if deniedTools.contains(toolName) { return false }
        if !allowedTools.isEmpty && !allowedTools.contains(toolName) { return false }
        return true
    }

    // ── Presets ──────────────────────────────────────────────────

    public static let readOnly = WorkerToolPolicy(
        allowedTools: [
            "memory.list_approved", "memory.search", "memory.get",
            "file.list", "file.read", "file.search",
            "git.status", "git.diff", "git.log",
            "swift.package_describe", "swift.diagnostics",
            "board.card.list", "board.card.get", "board.timeline",
        ],
        deniedTools: [
            "file.write", "file.patch", "file.delete",
            "git.commit", "git.push", "git.apply_patch",
            "swift.build", "swift.test",
            "approval.resolve", "workflow.approve_gate",
        ]
    )

    public static let devInspector = WorkerToolPolicy(
        allowedTools: [
            "memory.list_approved", "memory.search",
            "file.list", "file.read", "file.search",
            "git.status", "git.diff", "git.log",
            "swift.package_describe", "swift.diagnostics",
            "board.comment.add", "board.artifact.add",
        ],
        deniedTools: [
            "file.write", "file.patch", "file.delete",
            "git.commit", "git.push", "git.apply_patch",
            "swift.build", "swift.test",
            "approval.resolve", "workflow.approve_gate",
        ]
    )

    public static let devFixer = WorkerToolPolicy(
        allowedTools: [
            "memory.list_approved", "memory.search",
            "file.list", "file.read", "file.search", "file.patch",
            "git.status", "git.diff", "git.log", "git.commit", "git.apply_patch",
            "swift.package_describe", "swift.diagnostics", "swift.build", "swift.test",
            "board.comment.add", "board.artifact.add",
        ],
        deniedTools: ["git.push", "file.delete", "approval.resolve", "workflow.approve_gate"],
        maxRiskWithoutApproval: .low
    )

    public static let blockchainReader = WorkerToolPolicy(
        allowedTools: [
            "evm.account_balance_native", "evm.erc20_balance", "evm.tx_get_receipt",
            "evm.erc20_token_info", "evm.get_block",
            "solana.account_balance", "solana.token_account_balance",
            "solana.tx_get_signature_statuses",
            "board.comment.add", "board.artifact.add",
        ],
        deniedTools: [
            "evm.tx_build_native_transfer", "evm.erc20_build_transfer", "evm.erc20_build_approve",
            "evm.tx_request_signature", "evm.tx_broadcast_signed", "evm.wallet_connect",
            "solana.tx_build_sol_transfer", "solana.tx_build_spl_transfer",
            "solana.tx_request_signature", "solana.tx_send_signed", "solana.wallet_connect",
        ]
    )

    public static let blockchainReviewer = WorkerToolPolicy(
        allowedTools: [
            "evm.account_balance_native", "evm.erc20_balance", "evm.tx_get_receipt",
            "evm.erc20_token_info", "evm.get_block",
            "evm.tx_build_native_transfer", "evm.erc20_build_transfer", "evm.erc20_build_approve",
            "evm.tx_preflight",
            "solana.account_balance", "solana.token_account_balance",
            "solana.tx_get_signature_statuses",
            "solana.tx_build_sol_transfer", "solana.tx_build_spl_transfer",
            "solana.tx_simulate",
            "board.comment.add", "board.artifact.add",
        ],
        deniedTools: [
            "evm.tx_request_signature", "evm.tx_broadcast_signed", "evm.wallet_connect",
            "solana.tx_request_signature", "solana.tx_send_signed", "solana.wallet_connect",
        ],
        maxRiskWithoutApproval: .low
    )
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker budget
// ═══════════════════════════════════════════════════════════════════

public struct WorkerBudget: Codable, Sendable {
    public let maxTurns: Int
    public let maxToolCalls: Int
    public let maxWallClockSeconds: Int
    public let maxTokensApprox: Int?

    public static let small = WorkerBudget(maxTurns: 8, maxToolCalls: 16, maxWallClockSeconds: 300, maxTokensApprox: 60_000)
    public static let medium = WorkerBudget(maxTurns: 16, maxToolCalls: 32, maxWallClockSeconds: 600, maxTokensApprox: 120_000)
    public static let large = WorkerBudget(maxTurns: 32, maxToolCalls: 64, maxWallClockSeconds: 1200, maxTokensApprox: 250_000)

    public init(maxTurns: Int, maxToolCalls: Int, maxWallClockSeconds: Int, maxTokensApprox: Int?) {
        self.maxTurns = maxTurns; self.maxToolCalls = maxToolCalls
        self.maxWallClockSeconds = maxWallClockSeconds; self.maxTokensApprox = maxTokensApprox
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker assignment
// ═══════════════════════════════════════════════════════════════════

public struct WorkerAssignment: Codable, Sendable, Identifiable {
    public let id: String
    public let cardID: String
    public let laneID: String
    public let assignedBy: String
    public var status: WorkerAssignmentStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, cardID: String, laneID: String,
        assignedBy: String = "human", status: WorkerAssignmentStatus = .assigned,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.cardID = cardID; self.laneID = laneID
        self.assignedBy = assignedBy; self.status = status
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum WorkerAssignmentStatus: String, Codable, Sendable {
    case assigned, claimed, running, completed, blocked, cancelled
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker run
// ═══════════════════════════════════════════════════════════════════

public struct WorkerRun: Codable, Sendable, Identifiable {
    public let id: String
    public let assignmentID: String
    public let cardID: String
    public let laneID: String
    public let sessionID: String
    public var status: WorkerRunStatus
    public let startedAt: Date
    public var completedAt: Date?
    public var heartbeatAt: Date?
    public var resultID: String?
    public let budget: WorkerBudget
    public var toolCallCount: Int
    public var turnCount: Int

    public init(
        id: String = UUID().uuidString, assignmentID: String, cardID: String,
        laneID: String, sessionID: String, status: WorkerRunStatus = .pending,
        startedAt: Date = Date(), budget: WorkerBudget = .small
    ) {
        self.id = id; self.assignmentID = assignmentID; self.cardID = cardID
        self.laneID = laneID; self.sessionID = sessionID; self.status = status
        self.startedAt = startedAt; self.budget = budget
        self.toolCallCount = 0; self.turnCount = 0
    }

    public var isBudgetExceeded: Bool {
        toolCallCount >= budget.maxToolCalls || turnCount >= budget.maxTurns
    }

    public var isTimedOut: Bool {
        Date().timeIntervalSince(startedAt) > Double(budget.maxWallClockSeconds)
    }
}

public enum WorkerRunStatus: String, Codable, Sendable {
    case pending, running, pausedForApproval, blocked, completed, failed, cancelled, timedOut, budgetExceeded
}

// ═══════════════════════════════════════════════════════════════════
