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
