// SwooshWorkers/WorkerLaneDefaults.swift — 0.7B Default Worker Lanes

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Default lane factory
// ═══════════════════════════════════════════════════════════════════

public enum WorkerLaneDefaults {

    public static func all() -> [WorkerLane] {
        [human, reader, devInspector, devFixer, reviewer, workflowOperator, blockchainReader, blockchainReviewer]
    }

    public static let human = WorkerLane(
        id: "human", name: "Human", description: "Manual human work. No agent execution.",
        profile: WorkerProfile(id: "human", displayName: "Human", rolePrompt: "Manual task for human."),
        toolPolicy: WorkerToolPolicy(),
        budget: WorkerBudget(maxTurns: 0, maxToolCalls: 0, maxWallClockSeconds: 0, maxTokensApprox: nil),
        enabled: true
    )

    public static let reader = WorkerLane(
        id: "swoosh.reader", name: "Reader",
        description: "Read-only memory, file, git, and board access.",
        profile: WorkerProfile(
            id: "swoosh.reader", displayName: "Reader",
            rolePrompt: "You read and summarize. Never modify files, commit, or approve."
        ),
        toolPolicy: .readOnly, budget: .small
    )

    public static let devInspector = WorkerLane(
        id: "swoosh.dev-inspector", name: "Developer Inspector",
        description: "Read-only developer project inspection.",
        profile: WorkerProfile(
            id: "swoosh.dev-inspector", displayName: "Developer Inspector",
            rolePrompt: """
            You inspect Swift/macOS projects. Use only read-only tools.
            Summarize findings, identify likely next steps, and never modify files.
            """
        ),
        toolPolicy: .devInspector, budget: .small
    )

    public static let devFixer = WorkerLane(
        id: "swoosh.dev-fixer", name: "Developer Fixer",
        description: "Can inspect, build, test, patch, and commit with approval.",
        profile: WorkerProfile(
            id: "swoosh.dev-fixer", displayName: "Developer Fixer",
            rolePrompt: """
            You fix code issues. You may build, test, patch files, and commit changes.
            Write operations require approval. Never push, delete files, or approve your own gates.
            """
        ),
        toolPolicy: .devFixer, budget: .medium
    )

    public static let reviewer = WorkerLane(
        id: "swoosh.reviewer", name: "Reviewer",
        description: "Read-only review with board commenting.",
        profile: WorkerProfile(
            id: "swoosh.reviewer", displayName: "Reviewer",
            rolePrompt: "You review code, audit trails, and board cards. Add comments. Never write or approve."
        ),
        toolPolicy: .readOnly, budget: .small
    )

    public static let workflowOperator = WorkerLane(
        id: "swoosh.workflow-operator", name: "Workflow Operator",
        description: "Can read, dry-run, and replay read-only workflows.",
        profile: WorkerProfile(
            id: "swoosh.workflow-operator", displayName: "Workflow Operator",
            rolePrompt: "You operate workflows. Read, dry-run, replay read-only steps. Never approve gates or arm triggers."
        ),
        toolPolicy: WorkerToolPolicy(
            allowedTools: [
                "workflow.list", "workflow.get", "workflow.dry_run", "workflow.replay",
                "workflow.render_plan", "board.comment.add", "board.artifact.add",
            ],
            deniedTools: [
                "workflow.approve_gate", "workflow.execute", "workflow.enable",
                "trigger.create", "trigger.arm", "trigger.validate",
                "approval.resolve",
            ]
        ),
        budget: .medium
    )

    public static let blockchainReader = WorkerLane(
        id: "swoosh.blockchain-reader", name: "Blockchain Reader",
        description: "Read-only EVM/Solana data access.",
        profile: WorkerProfile(
            id: "swoosh.blockchain-reader", displayName: "Blockchain Reader",
            rolePrompt: "You read blockchain state: balances, receipts, token info. Never build, sign, or broadcast transactions."
        ),
        toolPolicy: .blockchainReader, budget: .small
    )

    public static let blockchainReviewer = WorkerLane(
        id: "swoosh.blockchain-reviewer", name: "Blockchain Reviewer",
        description: "Can build transaction previews with approval. Cannot sign or broadcast.",
        profile: WorkerProfile(
            id: "swoosh.blockchain-reviewer", displayName: "Blockchain Reviewer",
            rolePrompt: """
            You review blockchain transactions. You may build transaction previews for human review.
            Never sign, broadcast, or access private keys, seed phrases, or wallet secrets.
            """
        ),
        toolPolicy: .blockchainReviewer, budget: .medium
    )
}
