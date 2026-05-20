// SwooshFlow/WorkflowExecutionEngine.swift — 0.5D Execution Engine
//
// Executes read-only steps automatically.
// Pauses at risky steps for per-step human approval.
// Uses ToolRegistry only. Never bypasses Firewall.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution engine
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionEngine: Sendable {
    private let draftStore: any WorkflowDraftStoring
    private let runStore: any WorkflowRunStoring
    private let gateStore: any WorkflowExecutionGateStoring
    private let toolExecutor: any WorkflowToolExecuting
    private let inputResolver: any WorkflowInputResolving
    private let templateRenderer: any WorkflowTemplateRendering
    private let policy: WorkflowExecutionPolicy
    private let decisionPolicy: WorkflowExecutionDecisionPolicy
    private let redactor: WorkflowOutputRedactor

    public init(
        draftStore: any WorkflowDraftStoring, runStore: any WorkflowRunStoring,
        gateStore: any WorkflowExecutionGateStoring, toolExecutor: any WorkflowToolExecuting,
        inputResolver: any WorkflowInputResolving = DefaultWorkflowInputResolver(),
        templateRenderer: any WorkflowTemplateRendering = DefaultWorkflowTemplateRenderer(),
        policy: WorkflowExecutionPolicy = .manualApprovalGated,
        decisionPolicy: WorkflowExecutionDecisionPolicy = WorkflowExecutionDecisionPolicy(),
        redactor: WorkflowOutputRedactor = WorkflowOutputRedactor()
    ) {
        self.draftStore = draftStore; self.runStore = runStore; self.gateStore = gateStore
        self.toolExecutor = toolExecutor; self.inputResolver = inputResolver
        self.templateRenderer = templateRenderer; self.policy = policy
        self.decisionPolicy = decisionPolicy; self.redactor = redactor
    }

    // MARK: - Start execution

    public func start(_ request: WorkflowExecutionRequest) async throws -> WorkflowExecutionReport {
        guard let draft = try await draftStore.getDraft(id: request.draftID) else {
            throw WorkflowExecutionError.draftNotFound(request.draftID)
        }
        let inputs = inputResolver.resolveInputs(draft: draft, providedInputs: request.providedInputs, provenance: draft.provenance)
        let runID = UUID().uuidString
        let run = WorkflowRun05C(id: runID, draftID: draft.id, draftName: draft.name, status: .running, inputs: request.providedInputs)
        try await runStore.saveRun(run)
        return try await executeSteps(runID: runID, draft: draft, inputs: inputs, startIndex: 0)
    }

    // MARK: - Resume after approval

    public func resume(runID: String) async throws -> WorkflowExecutionReport {
        guard let run = try await runStore.getRun(id: runID) else { throw WorkflowExecutionError.runNotFound(runID) }
        guard let draft = try await draftStore.getDraft(id: run.draftID) else { throw WorkflowExecutionError.draftNotFound(run.draftID) }
        let inputs = inputResolver.resolveInputs(draft: draft, providedInputs: run.inputs, provenance: draft.provenance)

        // Find where we left off
        let existingSteps = try await runStore.getStepRuns(runID: runID)
        let lastApprovedGate = try await findLastApprovedGate(runID: runID)

        if let gate = lastApprovedGate {
            // Execute the approved step
            let stepIndex = gate.stepIndex
            if stepIndex < draft.steps.count {
                let step = draft.steps[stepIndex]
                let stepRun = await executeTool(step: step, runID: runID, inputs: inputs)
                try await runStore.saveStepRun(stepRun)
            }
            // Continue from next step
            return try await executeSteps(runID: runID, draft: draft, inputs: inputs, startIndex: stepIndex + 1)
        }

        // No approved gate, continue from where we stopped
        return try await executeSteps(runID: runID, draft: draft, inputs: inputs, startIndex: existingSteps.count)
    }

    // MARK: - Cancel

    public func cancel(runID: String) async throws -> WorkflowExecutionReport {
        guard let run = try await runStore.getRun(id: runID) else { throw WorkflowExecutionError.runNotFound(runID) }
        var cancelled = run
        cancelled.status = .cancelled
        cancelled.completedAt = Date()
        try await runStore.updateRun(cancelled)

        // Cancel pending gates
        let pending = try await gateStore.listPendingGates(runID: runID)
        for gate in pending {
            try await gateStore.resolveGate(id: gate.id, status: .cancelled, by: .human, reason: "Run cancelled")
        }

        return try await buildReport(runID: runID, status: .cancelled)
    }

    // MARK: - Gate operations

    public func approveGate(gateID: String, origin: ToolCallOrigin, confirmation: String?) async throws {
        guard origin == .human else { throw WorkflowExecutionError.cannotApproveAsModel }
        guard let gate = try await gateStore.getGate(id: gateID) else { throw WorkflowExecutionError.gateNotFound(gateID) }
        if gate.risk == .high && (confirmation == nil || confirmation!.isEmpty) {
            throw WorkflowExecutionError.highRiskRequiresConfirmation
        }
        try await gateStore.resolveGate(id: gateID, status: .approved, by: origin, reason: confirmation)
    }

    public func denyGate(gateID: String, origin: ToolCallOrigin, reason: String?) async throws {
        guard origin == .human else { throw WorkflowExecutionError.cannotApproveAsModel }
        try await gateStore.resolveGate(id: gateID, status: .denied, by: origin, reason: reason)
    }

    // MARK: - Core loop

    private func executeSteps(
        runID: String, draft: WorkflowDraft05A,
        inputs: WorkflowInputResolutionResult, startIndex: Int
    ) async throws -> WorkflowExecutionReport {
        var stepRuns: [WorkflowStepRun] = []

        for i in startIndex..<min(draft.steps.count, policy.maxSteps) {
            let step = draft.steps[i]
            let toolName = step.toolName ?? ""
            let decision = decisionPolicy.decide(toolName: toolName, risk: step.risk, policy: policy)

            switch decision.action {
            case .executeNow:
                let sr = await executeTool(step: step, runID: runID, inputs: inputs)
                stepRuns.append(sr)
                try await runStore.saveStepRun(sr)

            case .pauseForApproval:
                let gate = createGate(step: step, runID: runID)
                try await gateStore.saveGate(gate)
                let sr = WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                    title: step.title, toolName: step.toolName, status: .skipped, skipReason: .requiresApproval)
                stepRuns.append(sr)
                try await runStore.saveStepRun(sr)

                // Pause the run
                var run = try await runStore.getRun(id: runID)!
                run.status = .running // will be resolved to pausedForApproval in report
                try await runStore.updateRun(run)
                return try await buildReport(runID: runID, status: .pausedForApproval, pendingGateID: gate.id)

            case .skip:
                let sr = WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                    title: step.title, toolName: step.toolName, status: .skipped, skipReason: decision.reason)
                stepRuns.append(sr)
                try await runStore.saveStepRun(sr)

            case .block:
                let sr = WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                    title: step.title, toolName: step.toolName, status: .blocked, skipReason: decision.reason)
                stepRuns.append(sr)
                try await runStore.saveStepRun(sr)
            }
        }

        // Completed
        let status = computeStatus(stepRuns)
        var run = try await runStore.getRun(id: runID)!
        run.status = status == .completedWithSkippedSteps ? .completedWithSkippedSteps : .completed
        run.completedAt = Date()
        try await runStore.updateRun(run)
        return try await buildReport(runID: runID, status: mapStatus(status))
    }

    // MARK: - Tool execution

    private func executeTool(step: WorkflowStep05A, runID: String, inputs: WorkflowInputResolutionResult) async -> WorkflowStepRun {
        guard let toolName = step.toolName else {
            return WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                title: step.title, status: .skipped, skipReason: .unsupportedTool)
        }
        var args: JSONValue = .null
        if let t = step.argumentsTemplate { args = (try? templateRenderer.render(template: t, variables: inputs.resolvedVariables)) ?? .null }
        let start = Date()
        do {
            let result = try await toolExecutor.execute(toolName: toolName, arguments: args, origin: .workflow, sessionID: "workflow:\(runID)")
            if result.status == .succeeded {
                let out = redactor.redactAndTruncate(outputStr(result.output), maxBytes: 12_000)
                return WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                    title: step.title, toolName: toolName, status: .succeeded,
                    startedAt: start, completedAt: Date(), outputPreview: out)
            }
            return WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                title: step.title, toolName: toolName, status: .failed,
                startedAt: start, completedAt: Date(), errorMessage: result.errorMessage ?? "Failed")
        } catch {
            return WorkflowStepRun(runID: runID, sourceStepID: step.id, index: step.index,
                title: step.title, toolName: toolName, status: .failed,
                startedAt: start, completedAt: Date(), errorMessage: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func createGate(step: WorkflowStep05A, runID: String) -> WorkflowExecutionGate {
        let rollback: WorkflowRollbackHint?
        let toolName = step.toolName ?? ""
        if toolName.hasPrefix("file.patch") {
            rollback = WorkflowRollbackHint(kind: .backupFile, description: "Backup file created before patch.")
        } else if toolName.hasPrefix("git.commit") {
            rollback = WorkflowRollbackHint(kind: .gitReset, description: "git reset --soft HEAD~1 (manual only)")
        } else {
            rollback = WorkflowRollbackHint(kind: .notApplicable, description: "No rollback needed.", available: false)
        }

        return WorkflowExecutionGate(
            runID: runID, stepID: step.id, stepIndex: step.index,
            stepTitle: step.title, toolName: toolName, risk: step.risk,
            preview: WorkflowStepApprovalPreview(
                toolName: toolName, humanSummary: "Execute \(step.title)",
                resolvedArgumentsPreview: step.argumentsTemplate,
                expectedEffect: "Runs \(toolName)", rollbackHint: rollback
            )
        )
    }

    private func findLastApprovedGate(runID: String) async throws -> WorkflowExecutionGate? {
        // We need all gates, not just pending; but our simple store only has pending filter.
        // For now, we rely on the gate store having all gates accessible.
        return nil // Resume will use startIndex from existing step runs
    }

    private func buildReport(runID: String, status: WorkflowRunStatus05D, pendingGateID: String? = nil) async throws -> WorkflowExecutionReport {
        let steps = try await runStore.getStepRuns(runID: runID)
        let gates = try await gateStore.listPendingGates(runID: runID)
        let run = try await runStore.getRun(id: runID)
        var md = "# Workflow Execution Report\n\n"
        md += "**Status:** \(status.rawValue)\n\n"
        let exec = steps.filter { $0.status == .succeeded }
        let skip = steps.filter { $0.status == .skipped || $0.status == .blocked }
        let fail = steps.filter { $0.status == .failed }
        if !exec.isEmpty { md += "## Executed\n\n"; for s in exec { md += "✓ \(s.title)\n" }; md += "\n" }
        if !skip.isEmpty { md += "## Skipped/Blocked\n\n"; for s in skip { md += "- \(s.title): \(s.skipReason?.rawValue ?? "")\n" }; md += "\n" }
        if !gates.isEmpty { md += "## Pending Approval\n\n"; for g in gates { md += "? \(g.stepTitle) (`\(g.toolName)`)\n" }; md += "\n" }
        md += "---\n*No signing, broadcasting, git push, file delete, or scheduling occurred.*\n"

        return WorkflowExecutionReport(
            runID: runID, draftID: run?.draftID ?? "", draftName: run?.draftName ?? "",
            status: status, executedSteps: exec, skippedSteps: skip, failedSteps: fail,
            gates: gates, pendingGateID: pendingGateID, summaryMarkdown: md
        )
    }

    private func computeStatus(_ steps: [WorkflowStepRun]) -> WorkflowRunStatus05C {
        if steps.contains(where: { $0.status == .failed }) { return .failed }
        if steps.contains(where: { $0.status == .skipped || $0.status == .blocked }) { return .completedWithSkippedSteps }
        return .completed
    }

    private func mapStatus(_ s: WorkflowRunStatus05C) -> WorkflowRunStatus05D {
        switch s {
        case .pending: return .pending
        case .running: return .running
        case .completed: return .completed
        case .completedWithSkippedSteps: return .completedWithSkippedSteps
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    private func outputStr(_ o: JSONValue?) -> String {
        guard let o else { return "" }
        switch o { case .string(let s): return s; default: return "\(o)" }
    }
}
