// SwooshFlow/WorkflowDryRunEngine.swift — 0.5B Dry Run Engine
//
// Planning and simulation only. No tools execute. No side effects.
// Resolves variables, validates steps, checks permissions/approvals,
// detects blocked steps, maps cached outputs, renders report.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Input resolver
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowInputResolving: Sendable {
    func resolveInputs(
        draft: WorkflowDraft05A,
        providedInputs: [String: JSONValue],
        provenance: WorkflowProvenance?
    ) -> WorkflowInputResolutionResult
}

public struct DefaultWorkflowInputResolver: WorkflowInputResolving, Sendable {
    public init() {}

    public func resolveInputs(
        draft: WorkflowDraft05A,
        providedInputs: [String: JSONValue],
        provenance: WorkflowProvenance?
    ) -> WorkflowInputResolutionResult {
        var resolved: [ResolvedWorkflowVariable] = []
        var prompts: [WorkflowInputPrompt] = []

        for variable in draft.variables {
            // 1. Provided input wins
            if let provided = providedInputs[variable.name] {
                resolved.append(ResolvedWorkflowVariable(
                    name: variable.name, type: variable.type,
                    value: provided, source: .providedInput, isResolved: true
                ))
                continue
            }
            // 2. Default value
            if let defaultVal = variable.defaultValue {
                resolved.append(ResolvedWorkflowVariable(
                    name: variable.name, type: variable.type,
                    value: defaultVal, source: .defaultValue, isResolved: true
                ))
                continue
            }
            // 3. Provenance hint (only for approvedRootID from source trace)
            if variable.type == .approvedRootID, let prov = provenance,
               !prov.sourceToolTraceIDs.isEmpty {
                // Cannot invent a root, so still prompt
            }
            // 4. Missing required → prompt
            if variable.required {
                prompts.append(WorkflowInputPrompt(
                    variableName: variable.name,
                    variableType: variable.type,
                    prompt: "Provide value for \(variable.name) (\(variable.type.rawValue))",
                    defaultValue: variable.defaultValue,
                    required: true,
                    source: .missingRequiredVariable
                ))
                resolved.append(ResolvedWorkflowVariable(
                    name: variable.name, type: variable.type,
                    source: .unresolved, isResolved: false
                ))
            } else {
                // Optional unresolved → null
                resolved.append(ResolvedWorkflowVariable(
                    name: variable.name, type: variable.type,
                    value: .null, source: .unresolved, isResolved: true
                ))
            }
        }

        return WorkflowInputResolutionResult(
            resolvedVariables: resolved,
            prompts: prompts,
            isComplete: prompts.isEmpty
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Template renderer
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowTemplateRendering: Sendable {
    func render(template: JSONValue, variables: [ResolvedWorkflowVariable]) throws -> JSONValue
}

public struct DefaultWorkflowTemplateRenderer: WorkflowTemplateRendering, Sendable {
    public init() {}

    /// Patterns that are NEVER allowed in templates.
    private static let blockedPatterns = [
        "{{ shell(", "{{ env.", "{{ readFile(", "{{ exec(",
        "$(",  "$((",  "`",
    ]

    public func render(template: JSONValue, variables: [ResolvedWorkflowVariable]) throws -> JSONValue {
        switch template {
        case .string(let s):
            try validateNoInjection(s)
            return .string(try replaceVariables(in: s, variables: variables))
        case .object(let dict):
            var result: [String: JSONValue] = [:]
            for (key, value) in dict {
                result[key] = try render(template: value, variables: variables)
            }
            return .object(result)
        case .array(let arr):
            return .array(try arr.map { try render(template: $0, variables: variables) })
        default:
            return template
        }
    }

    private func validateNoInjection(_ s: String) throws {
        for pattern in Self.blockedPatterns {
            if s.contains(pattern) {
                throw WorkflowDryRunError.templateInjectionBlocked(pattern)
            }
        }
    }

    private func replaceVariables(
        in template: String, variables: [ResolvedWorkflowVariable]
    ) throws -> String {
        var result = template
        // Find all {{variableName}} placeholders
        let regex = try NSRegularExpression(pattern: #"\{\{(\w+)\}\}"#)
        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))

        // Process in reverse to preserve ranges
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: template),
                  let nameRange = Range(match.range(at: 1), in: template) else { continue }
            let varName = String(template[nameRange])
            guard let resolved = variables.first(where: { $0.name == varName }) else {
                throw WorkflowDryRunError.unknownVariable(varName)
            }
            if !resolved.isResolved {
                throw WorkflowDryRunError.unresolvedRequiredVariable(varName)
            }
            let replacement: String
            switch resolved.value {
            case .string(let s): replacement = s
            case .int(let i): replacement = String(i)
            case .double(let d): replacement = String(d)
            case .bool(let b): replacement = String(b)
            case .null, .none: replacement = "null"
            default: replacement = "null"
            }
            result = result.replacingCharacters(in: fullRange, with: replacement)
        }
        return result
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Permission planner
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowPermissionPlanning: Sendable {
    func check(plan: WorkflowExecutionPlan, permissionStates: [SwooshPermission: PermissionState]) -> WorkflowPermissionReport
}

public struct DefaultWorkflowPermissionPlanner: WorkflowPermissionPlanning, Sendable {
    public init() {}

    public func check(
        plan: WorkflowExecutionPlan,
        permissionStates: [SwooshPermission: PermissionState]
    ) -> WorkflowPermissionReport {
        var checks: [WorkflowPermissionCheck] = []
        var allAvailable = true

        // Collect unique permissions across steps
        var permToSteps: [SwooshPermission: [String]] = [:]
        for step in plan.steps {
            for perm in step.requiredPermissions {
                permToSteps[perm, default: []].append(step.id)
            }
        }

        for (perm, stepIDs) in permToSteps {
            let state = permissionStates[perm] ?? .notRequested
            let result: WorkflowPermissionCheckResult
            switch state {
            case .granted: result = .available
            case .denied: result = .denied; allAvailable = false
            case .pending: result = .requiresApproval; allAvailable = false
            case .notRequested: result = .missing; allAvailable = false
            }
            checks.append(WorkflowPermissionCheck(
                permission: perm, currentState: state,
                requiredForStepIDs: stepIDs,
                reason: "Required for \(stepIDs.count) step(s)",
                result: result
            ))
        }

        return WorkflowPermissionReport(requirements: checks, allAvailable: allAvailable)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Approval planner
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowApprovalPlanning: Sendable {
    func check(plan: WorkflowExecutionPlan) -> WorkflowApprovalReport
}

public struct DefaultWorkflowApprovalPlanner: WorkflowApprovalPlanning, Sendable {
    public init() {}

    public func check(plan: WorkflowExecutionPlan) -> WorkflowApprovalReport {
        var requirements: [WorkflowApprovalRequirement] = []

        for step in plan.steps {
            switch step.approval {
            case .askEveryTime, .askFirstTime, .askForRiskAtLeast:
                requirements.append(WorkflowApprovalRequirement(
                    stepID: step.id, toolName: step.toolName,
                    risk: step.risk, approvalPolicy: step.approval,
                    reason: "\(step.toolName ?? step.title) requires approval before execution"
                ))
            case .humanOnly:
                requirements.append(WorkflowApprovalRequirement(
                    stepID: step.id, toolName: step.toolName,
                    risk: step.risk, approvalPolicy: .humanOnly,
                    reason: "\(step.toolName ?? step.title) is human-only and cannot execute in workflows"
                ))
            case .never, .disabled:
                break
            }
        }

        return WorkflowApprovalReport(
            requirements: requirements,
            humanApprovalRequired: !requirements.isEmpty
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cached replay
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowCachedReplaying: Sendable {
    func replay(
        draft: WorkflowDraft05A,
        plan: WorkflowExecutionPlan,
        sourceTraces: [ToolCallTrace]
    ) -> WorkflowCachedReplayReport
}

public struct DefaultWorkflowCachedReplay: WorkflowCachedReplaying, Sendable {
    /// Patterns to redact from cached outputs.
    private static let secretPatterns = [
        "API_KEY", "SECRET", "TOKEN", "PASSWORD", "PRIVATE_KEY",
        "SEED_PHRASE", "MNEMONIC", "COOKIE", "SESSION_ID",
    ]

    public init() {}

    public func replay(
        draft: WorkflowDraft05A,
        plan: WorkflowExecutionPlan,
        sourceTraces: [ToolCallTrace]
    ) -> WorkflowCachedReplayReport {
        var mapped: [WorkflowCachedReplayStep] = []
        var traceByID: [String: ToolCallTrace] = [:]
        var tracesByTool: [String: [ToolCallTrace]] = [:]
        for trace in sourceTraces {
            traceByID[trace.id] = trace
            tracesByTool[trace.toolName, default: []].append(trace)
        }

        var usedTraceIDs: Set<String> = []

        for step in draft.steps {
            // 1. Match by sourceTraceID
            if let traceID = step.sourceTraceID, let trace = traceByID[traceID] {
                mapped.append(makeCachedStep(stepID: step.id, trace: trace))
                usedTraceIDs.insert(traceID)
                continue
            }
            // 2. Match by toolName fallback
            if let toolName = step.toolName,
               let candidates = tracesByTool[toolName],
               let firstUnused = candidates.first(where: { !usedTraceIDs.contains($0.id) }) {
                mapped.append(makeCachedStep(stepID: step.id, trace: firstUnused))
                usedTraceIDs.insert(firstUnused.id)
                continue
            }
        }

        let unmapped = sourceTraces.filter { !usedTraceIDs.contains($0.id) }.map(\.id)

        return WorkflowCachedReplayReport(
            sourceSessionID: draft.provenance.sourceSessionID,
            mappedSteps: mapped,
            unmappedSourceToolTraceIDs: unmapped
        )
    }

    private func makeCachedStep(stepID: String, trace: ToolCallTrace) -> WorkflowCachedReplayStep {
        let preview = redactSecrets(trace.outputPreview ?? "(no output)")
        return WorkflowCachedReplayStep(
            stepID: stepID,
            sourceToolTraceID: trace.id,
            cachedOutputPreview: String(preview.prefix(500)),
            cachedStatus: trace.status
        )
    }

    private func redactSecrets(_ text: String) -> String {
        var result = text
        for pattern in Self.secretPatterns {
            if result.uppercased().contains(pattern) {
                result = result.replacingOccurrences(
                    of: pattern, with: "[REDACTED]",
                    options: .caseInsensitive
                )
            }
        }
        return result
    }
}

// ═══════════════════════════════════════════════════════════════════
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
