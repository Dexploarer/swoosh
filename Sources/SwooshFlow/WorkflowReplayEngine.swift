// SwooshFlow/WorkflowReplayEngine.swift — 0.5C Read-Only Replay Engine
//
// Replays workflow drafts using only read-only tools.
// Uses ToolRegistry for execution — never bypasses Firewall.
// No writes, no signing, no broadcasting, no scheduling.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool executing protocol (abstracts ToolRegistry)
// ═══════════════════════════════════════════════════════════════════

/// Abstraction over ToolRegistry for testability.
/// In production, this wraps ToolRegistry.
/// In tests, it records calls without real execution.
public protocol WorkflowToolExecuting: Sendable {
    func execute(toolName: String, arguments: JSONValue, origin: ToolCallOrigin, sessionID: String) async throws -> ToolExecutionResult
    func getDescriptor(toolName: String) async -> ToolDescriptor?
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Output redaction
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowOutputRedactor: Sendable {
    private static let secretPatterns = [
        "API_KEY", "SECRET", "TOKEN", "PASSWORD", "PRIVATE_KEY",
        "SEED_PHRASE", "MNEMONIC", "COOKIE", "SESSION_ID",
        "sk-", "sk_live_", "sk_test_",
    ]

    public init() {}

    public func redactAndTruncate(_ output: String, maxBytes: Int) -> String {
        var result = output
        for pattern in Self.secretPatterns {
            if result.uppercased().contains(pattern.uppercased()) {
                result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .caseInsensitive)
            }
        }
        if result.utf8.count > maxBytes {
            let truncated = String(result.prefix(maxBytes))
            result = truncated + "\n… (output truncated at \(maxBytes) bytes)"
        }
        return result
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Run renderer
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRunRenderer: Sendable {
    public init() {}

    public func renderReport(run: WorkflowRun05C, steps: [WorkflowStepRun]) -> String {
        var md = "# Read-Only Workflow Replay: \(run.draftName)\n\n"
        md += "**Status:** \(run.status.rawValue)  \n"
        md += "**Mode:** \(run.mode.rawValue)  \n\n"

        let executed = steps.filter { $0.status == .succeeded }
        let skipped = steps.filter { $0.status == .skipped || $0.status == .blocked }
        let failed = steps.filter { $0.status == .failed }

        if !executed.isEmpty {
            md += "## Executed Steps\n\n"
            for step in executed {
                md += "✓ **\(step.title)**"
                if let tool = step.toolName { md += " (`\(tool)`)" }
                if let out = step.outputPreview { md += "\n  → \(String(out.prefix(200)))" }
                md += "\n\n"
            }
        }

        if !skipped.isEmpty {
            md += "## Skipped Steps\n\n"
            for step in skipped {
                md += "- **\(step.title)**"
                if let tool = step.toolName { md += " (`\(tool)`)" }
                if let reason = step.skipReason { md += " — \(reason.rawValue)" }
                md += "\n"
            }
            md += "\n"
        }

        if !failed.isEmpty {
            md += "## Failed Steps\n\n"
            for step in failed {
                md += "✗ **\(step.title)**"
                if let err = step.errorMessage { md += ": \(err)" }
                md += "\n"
            }
            md += "\n"
        }

        md += "---\n"
        md += "**Safety:** This replay executed read-only steps only. "
        md += "No files were modified. No git writes were performed. "
        md += "No build/test commands were run. "
        md += "No blockchain transactions were built, signed, or broadcast.\n"
        return md
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Replay engine
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowReplayEngine: Sendable {
    private let draftStore: any WorkflowDraftStoring
    private let runStore: any WorkflowRunStoring
    private let toolExecutor: any WorkflowToolExecuting
    private let inputResolver: any WorkflowInputResolving
    private let templateRenderer: any WorkflowTemplateRendering
    private let policy: WorkflowReplayPolicy
    private let stepPolicy: WorkflowStepExecutionPolicy
    private let redactor: WorkflowOutputRedactor
    private let renderer: WorkflowRunRenderer

    public init(
        draftStore: any WorkflowDraftStoring,
        runStore: any WorkflowRunStoring,
        toolExecutor: any WorkflowToolExecuting,
        inputResolver: any WorkflowInputResolving = DefaultWorkflowInputResolver(),
        templateRenderer: any WorkflowTemplateRendering = DefaultWorkflowTemplateRenderer(),
        policy: WorkflowReplayPolicy = .readOnlyManual,
        stepPolicy: WorkflowStepExecutionPolicy = WorkflowStepExecutionPolicy(),
        redactor: WorkflowOutputRedactor = WorkflowOutputRedactor(),
        renderer: WorkflowRunRenderer = WorkflowRunRenderer()
    ) {
        self.draftStore = draftStore; self.runStore = runStore
        self.toolExecutor = toolExecutor; self.inputResolver = inputResolver
        self.templateRenderer = templateRenderer; self.policy = policy
        self.stepPolicy = stepPolicy; self.redactor = redactor; self.renderer = renderer
    }

    public func replay(_ request: WorkflowReplayRequest) async throws -> WorkflowReplayReport {
        // 1. Load draft
        guard let draft = try await draftStore.getDraft(id: request.draftID) else {
            throw WorkflowReplayError.draftNotFound(request.draftID)
        }

        // 2. Resolve inputs
        let inputResolution = inputResolver.resolveInputs(
            draft: draft, providedInputs: request.providedInputs, provenance: draft.provenance
        )

        // 3. Create run record
        let runID = UUID().uuidString
        var run = WorkflowRun05C(
            id: runID, draftID: draft.id, draftName: draft.name,
            status: .running, inputs: request.providedInputs
        )
        try await runStore.saveRun(run)

        // 4. Execute steps
        var stepRuns: [WorkflowStepRun] = []

        for step in draft.steps.prefix(policy.maxSteps) {
            let descriptor = await toolExecutor.getDescriptor(toolName: step.toolName ?? "")

            // Build step plan for policy check
            let stepPlan = WorkflowStepPlan(
                sourceStepID: step.id, index: step.index,
                title: step.title, kind: step.kind,
                toolName: step.toolName,
                requiredPermissions: step.requiredPermissions,
                risk: step.risk, approval: step.approval
            )

            let decision = stepPolicy.decide(step: stepPlan, descriptor: descriptor, policy: policy)

            switch decision.action {
            case .execute:
                let stepRun = await executeStep(
                    step: step, runID: runID, inputResolution: inputResolution
                )
                stepRuns.append(stepRun)
                try await runStore.saveStepRun(stepRun)

                if policy.stopOnFailure && stepRun.status == .failed { break }

            case .skip, .block:
                let stepRun = WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title,
                    toolName: step.toolName,
                    status: decision.action == .block ? .blocked : .skipped,
                    skipReason: decision.reason
                )
                stepRuns.append(stepRun)
                try await runStore.saveStepRun(stepRun)

                if request.scope == .untilFirstBlockedStep
                    && (decision.action == .block || decision.action == .skip) {
                    break
                }
            }
        }

        // 5. Compute status
        let status = computeRunStatus(stepRuns)
        run.status = status
        run.completedAt = Date()
        run.stepRunIDs = stepRuns.map(\.id)
        run.summaryMarkdown = renderer.renderReport(run: run, steps: stepRuns)
        try await runStore.updateRun(run)

        // 6. Build report
        return WorkflowReplayReport(
            runID: runID, draftID: draft.id, draftName: draft.name,
            status: status,
            executedSteps: stepRuns.filter { $0.status == .succeeded },
            skippedSteps: stepRuns.filter { $0.status == .skipped || $0.status == .blocked },
            failedSteps: stepRuns.filter { $0.status == .failed },
            summaryMarkdown: renderer.renderReport(run: run, steps: stepRuns)
        )
    }

    // MARK: - Step execution

    private func executeStep(
        step: WorkflowStep05A, runID: String,
        inputResolution: WorkflowInputResolutionResult
    ) async -> WorkflowStepRun {
        guard let toolName = step.toolName else {
            return WorkflowStepRun(
                runID: runID, sourceStepID: step.id,
                index: step.index, title: step.title,
                status: .skipped, skipReason: .unsupportedTool
            )
        }

        // Render arguments
        var renderedArgs: JSONValue = .null
        if let template = step.argumentsTemplate {
            do {
                renderedArgs = try templateRenderer.render(
                    template: template, variables: inputResolution.resolvedVariables
                )
            } catch {
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .failed, startedAt: Date(), completedAt: Date(),
                    errorMessage: "Failed to render arguments: \(error)"
                )
            }
        }

        // Execute through tool executor (ToolRegistry wrapper)
        let startedAt = Date()
        do {
            let result = try await toolExecutor.execute(
                toolName: toolName, arguments: renderedArgs,
                origin: .workflow, sessionID: "workflow:\(runID)"
            )

            switch result.status {
            case .succeeded:
                let outputStr = outputToString(result.output)
                let redacted = redactor.redactAndTruncate(outputStr, maxBytes: policy.maxOutputBytesPerStep)
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .succeeded, startedAt: startedAt, completedAt: Date(),
                    outputPreview: redacted
                )
            case .failed:
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .failed, startedAt: startedAt, completedAt: Date(),
                    errorMessage: result.errorMessage ?? "Tool execution failed"
                )
            case .blockedByPermission:
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .skipped, skipReason: .missingPermission
                )
            case .pendingApproval, .deniedByUser:
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .skipped, skipReason: .requiresApproval
                )
            case .disabled:
                return WorkflowStepRun(
                    runID: runID, sourceStepID: step.id,
                    index: step.index, title: step.title, toolName: toolName,
                    status: .skipped, skipReason: .blockedByPolicy
                )
            }
        } catch {
            return WorkflowStepRun(
                runID: runID, sourceStepID: step.id,
                index: step.index, title: step.title, toolName: toolName,
                status: .failed, startedAt: startedAt, completedAt: Date(),
                errorMessage: "Execution error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func computeRunStatus(_ steps: [WorkflowStepRun]) -> WorkflowRunStatus05C {
        let hasSkipped = steps.contains { $0.status == .skipped || $0.status == .blocked }
        let hasFailed = steps.contains { $0.status == .failed }
        let allFailed = steps.allSatisfy { $0.status == .failed }

        if allFailed && !steps.isEmpty { return .failed }
        if hasFailed { return .failed }
        if hasSkipped { return .completedWithSkippedSteps }
        return .completed
    }

    private func outputToString(_ output: JSONValue?) -> String {
        guard let output else { return "(no output)" }
        switch output {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "(null)"
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(output),
               let s = String(data: data, encoding: .utf8) { return s }
            return "(complex output)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowReplayError: Error, Sendable {
    case draftNotFound(String)
    case inputResolutionFailed(String)
    case policyViolation(String)
}
