// SwooshFlow/WorkflowDryRunEngineExec.swift — Blocked step detection, rendering, engine
import Foundation
import SwooshTools

// MARK: - Blocked step detector
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowBlockedStepDetector: Sendable {
    private static let signingBroadcastTools: Set<String> = [
        "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.tx_request_signature", "solana.tx_send_signed",
    ]
    private static let humanOnlyTools: Set<String> = [
        "vault.approve_candidate", "vault.reject_candidate",
        "permission.request",
    ]
    private static let destructiveTools: Set<String> = [
        "git.push", "file.delete",
    ]

    public init() {}

    public func detect(plan: WorkflowExecutionPlan) -> [WorkflowBlockedStep] {
        var blocked: [WorkflowBlockedStep] = []
        for step in plan.steps {
            guard let tool = step.toolName else { continue }

            if Self.signingBroadcastTools.contains(tool) {
                blocked.append(WorkflowBlockedStep(
                    stepID: step.id, title: step.title,
                    reason: .signingOrBroadcast,
                    details: "\(tool) cannot execute in dry run or workflow"
                ))
            } else if Self.humanOnlyTools.contains(tool) {
                blocked.append(WorkflowBlockedStep(
                    stepID: step.id, title: step.title,
                    reason: .humanOnlyTool,
                    details: "\(tool) requires human interaction"
                ))
            } else if Self.destructiveTools.contains(tool) && step.kind == .toolCall {
                blocked.append(WorkflowBlockedStep(
                    stepID: step.id, title: step.title,
                    reason: .destructiveTool,
                    details: "\(tool) is destructive and blocked in dry run"
                ))
            }
        }
        return blocked
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plan renderer
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowPlanRenderer: Sendable {
    public init() {}

    public func renderMarkdown(
        draft: WorkflowDraft05A,
        plan: WorkflowExecutionPlan,
        validation: WorkflowValidationResult,
        permissionReport: WorkflowPermissionReport,
        approvalReport: WorkflowApprovalReport,
        cachedReplay: WorkflowCachedReplayReport?
    ) -> String {
        var md = "# Workflow Dry Run: \(draft.name)\n\n"
        md += "**Status:** Plan generated. No tools executed.  \n"
        md += "**Risk:** \(plan.estimatedRisk.rawValue)  \n"
        md += "**Executable in 0.5B:** No  \n\n"

        // Validation
        md += "## Validation\n\n"
        if validation.isValid {
            md += "✓ Draft structure valid\n"
        } else {
            for err in validation.errors { md += "✗ \(err.message)\n" }
        }
        for warn in validation.warnings { md += "⚠ \(warn.message)\n" }
        md += "\n"

        // Variables
        if !plan.variables.isEmpty {
            md += "## Variables\n\n"
            for v in plan.variables {
                let status = v.isResolved ? "✓" : "✗"
                let val = v.value.map { "\($0)" } ?? "unresolved"
                md += "- \(status) **\(v.name)** (\(v.type.rawValue)): \(val)\n"
            }
            md += "\n"
        }

        // Permissions
        md += "## Permissions\n\n"
        for check in permissionReport.requirements {
            let icon: String
            switch check.result {
            case .available: icon = "✓"
            case .requiresApproval: icon = "?"
            case .denied: icon = "✗"
            case .unavailable, .missing: icon = "○"
            }
            md += "- \(icon) \(check.permission.rawValue): \(check.result.rawValue)\n"
        }
        md += "\n"

        // Steps
        md += "## Steps\n\n"
        for step in plan.steps {
            md += "\(step.index). **\(step.title)**"
            if let tool = step.toolName { md += " (`\(tool)`)" }
            md += "\n   Status: \(step.status.rawValue)"
            if step.risk != .readOnly { md += " | Risk: \(step.risk.rawValue)" }
            if let cached = step.cachedOutputPreview {
                md += "\n   Cached: \(cached.prefix(120))"
            }
            md += "\n\n"
        }

        // Approvals
        if !approvalReport.requirements.isEmpty {
            md += "## Approvals Required\n\n"
            for req in approvalReport.requirements {
                md += "- \(req.toolName ?? req.stepID): \(req.reason)\n"
            }
            md += "\n"
        }

        // Cached replay warning
        if let cached = cachedReplay {
            md += "---\n⚠ \(cached.warning)\n"
        }

        md += "\n---\n*No tools were executed during this dry run.*\n"
        return md
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Dry-run engine
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowDryRunEngine: Sendable {
    private let draftStore: any WorkflowDraftStoring
    private let inputResolver: any WorkflowInputResolving
    private let templateRenderer: any WorkflowTemplateRendering
    private let validator: WorkflowValidator
    private let permissionPlanner: any WorkflowPermissionPlanning
    private let approvalPlanner: any WorkflowApprovalPlanning
    private let cachedReplay: any WorkflowCachedReplaying
    private let blockedDetector: WorkflowBlockedStepDetector
    private let planRenderer: WorkflowPlanRenderer

    public init(
        draftStore: any WorkflowDraftStoring,
        inputResolver: any WorkflowInputResolving = DefaultWorkflowInputResolver(),
        templateRenderer: any WorkflowTemplateRendering = DefaultWorkflowTemplateRenderer(),
        validator: WorkflowValidator = WorkflowValidator(),
        permissionPlanner: any WorkflowPermissionPlanning = DefaultWorkflowPermissionPlanner(),
        approvalPlanner: any WorkflowApprovalPlanning = DefaultWorkflowApprovalPlanner(),
        cachedReplay: any WorkflowCachedReplaying = DefaultWorkflowCachedReplay(),
        blockedDetector: WorkflowBlockedStepDetector = WorkflowBlockedStepDetector(),
        planRenderer: WorkflowPlanRenderer = WorkflowPlanRenderer()
    ) {
        self.draftStore = draftStore; self.inputResolver = inputResolver
        self.templateRenderer = templateRenderer; self.validator = validator
        self.permissionPlanner = permissionPlanner; self.approvalPlanner = approvalPlanner
        self.cachedReplay = cachedReplay; self.blockedDetector = blockedDetector
        self.planRenderer = planRenderer
    }

    public func dryRun(
        _ request: WorkflowDryRunRequest,
        permissionStates: [SwooshPermission: PermissionState] = [:],
        sourceTraces: [ToolCallTrace] = []
    ) async throws -> WorkflowDryRunReport {
        // 1. Load draft
        guard let draft = try await draftStore.getDraft(id: request.draftID) else {
            throw WorkflowDryRunError.draftNotFound(request.draftID)
        }

        // 2. Validate
        let validation = validator.validate(draft)

        // 3. Resolve inputs
        let inputResolution = inputResolver.resolveInputs(
            draft: draft, providedInputs: request.providedInputs,
            provenance: draft.provenance
        )

        // 4. Build step plans
        var stepPlans: [WorkflowStepPlan] = []
        for step in draft.steps {
            var resolvedArgs: JSONValue? = nil
            if let template = step.argumentsTemplate {
                resolvedArgs = try? templateRenderer.render(
                    template: template, variables: inputResolution.resolvedVariables
                )
            }

            let status = determineStepStatus(step: step, inputResolution: inputResolution)

            stepPlans.append(WorkflowStepPlan(
                sourceStepID: step.id, index: step.index,
                title: step.title, kind: step.kind,
                toolName: step.toolName, resolvedArgumentsPreview: resolvedArgs,
                requiredPermissions: step.requiredPermissions,
                risk: step.risk, approval: step.approval,
                status: status
            ))
        }

        // 5. Build execution plan (always not executable in 0.5B)
        let plan = WorkflowExecutionPlan(
            draftID: draft.id, steps: stepPlans,
            variables: inputResolution.resolvedVariables,
            requiredPermissions: draft.requiredPermissions,
            estimatedRisk: WorkflowRisk.compute(from: draft.steps),
            isExecutableInCurrentMilestone: false
        )

        // 6. Check permissions
        let permReport = permissionPlanner.check(plan: plan, permissionStates: permissionStates)

        // 7. Check approvals
        let approvalReport = approvalPlanner.check(plan: plan)

        // 8. Detect blocked steps
        let blocked = blockedDetector.detect(plan: plan)

        // 9. Cached replay (if requested)
        var cachedReport: WorkflowCachedReplayReport? = nil
        if request.mode == .cachedReplay && !sourceTraces.isEmpty {
            cachedReport = cachedReplay.replay(
                draft: draft, plan: plan, sourceTraces: sourceTraces
            )
            // Annotate step plans with cached output
            for (i, step) in stepPlans.enumerated() {
                if let cached = cachedReport?.mappedSteps.first(where: { $0.stepID == step.sourceStepID }) {
                    stepPlans[i].cachedOutputPreview = cached.cachedOutputPreview
                }
            }
        }

        // 10. Render markdown
        let summary = planRenderer.renderMarkdown(
            draft: draft, plan: plan,
            validation: validation,
            permissionReport: permReport,
            approvalReport: approvalReport,
            cachedReplay: cachedReport
        )

        return WorkflowDryRunReport(
            draftID: draft.id, draftName: draft.name,
            mode: request.mode, plan: plan,
            validation: validation,
            unresolvedInputs: inputResolution.prompts,
            permissionReport: permReport,
            approvalReport: approvalReport,
            risk: plan.estimatedRisk,
            blockedSteps: blocked,
            cachedReplay: cachedReport,
            summaryMarkdown: summary
        )
    }

    private func determineStepStatus(
        step: WorkflowStep05A, inputResolution: WorkflowInputResolutionResult
    ) -> WorkflowStepPlanStatus {
        // Check if any required variable is unresolved
        if !inputResolution.isComplete {
            if let template = step.argumentsTemplate, case .string(let s) = template {
                for prompt in inputResolution.prompts {
                    if s.contains("{{\(prompt.variableName)}}") {
                        return .missingInput
                    }
                }
            }
        }

        // Approval-gated steps
        switch step.approval {
        case .askEveryTime, .askFirstTime, .askForRiskAtLeast: return .approvalRequired
        case .humanOnly: return .blocked
        case .disabled: return .unsupported
        case .never: break
        }

        return .ready
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowDryRunError: Error, Sendable {
    case draftNotFound(String)
    case unresolvedRequiredVariable(String)
    case unknownVariable(String)
    case templateInjectionBlocked(String)
    case invalidVariableType(String)
}
