// SwooshFlow/WorkflowValidator.swift — Draft validation (0.5A)
//
// Validates drafts before save/export. Enforces 0.5A safety invariants.

import Foundation
import SwooshTools

// MARK: - Validation result

public struct WorkflowValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let warnings: [WorkflowValidationWarning]
    public let errors: [WorkflowValidationError]

    public init(isValid: Bool, warnings: [WorkflowValidationWarning], errors: [WorkflowValidationError]) {
        self.isValid = isValid; self.warnings = warnings; self.errors = errors
    }
}

public struct WorkflowValidationWarning: Codable, Sendable, Identifiable {
    public let id: String
    public let message: String
    public let stepID: String?

    public init(id: String = UUID().uuidString, message: String, stepID: String? = nil) {
        self.id = id; self.message = message; self.stepID = stepID
    }
}

public struct WorkflowValidationError: Codable, Sendable, Identifiable {
    public let id: String
    public let message: String
    public let stepID: String?

    public init(id: String = UUID().uuidString, message: String, stepID: String? = nil) {
        self.id = id; self.message = message; self.stepID = stepID
    }
}

// MARK: - Validator

public struct WorkflowValidator: Sendable {
    private let knownTools: Set<String>

    public init(knownTools: Set<String> = []) {
        self.knownTools = knownTools
    }

    /// Never-executable in ANY version.
    private static let neverExecutableTools: Set<String> = [
        "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.tx_request_signature", "solana.tx_send_signed",
        "evm.wallet_connect", "solana.wallet_connect",
        "git.push", "file.delete",
    ]

    /// Human-only tools that cannot be automated steps.
    private static let humanOnlyTools: Set<String> = [
        "vault.approve_candidate", "vault.reject_candidate",
        "permission.request",
    ]

    public func validate(_ draft: WorkflowDraft05A) -> WorkflowValidationResult {
        var warnings: [WorkflowValidationWarning] = []
        var errors: [WorkflowValidationError] = []

        // 1. Name must exist
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.init(message: "Workflow name is required"))
        }

        // 2. Trigger must be manual in 0.5A
        if case .deferred(let p) = draft.trigger {
            warnings.append(.init(message: "Trigger '\(p.humanDescription)' is deferred. Only manual triggers are supported in 0.5A."))
        }

        // 3. Validate steps
        for step in draft.steps {
            guard let toolName = step.toolName else { continue }

            // Unknown tool check
            if !knownTools.isEmpty && !knownTools.contains(toolName) {
                errors.append(.init(message: "Unknown tool: \(toolName)", stepID: step.id))
            }

            // Never-executable check
            if Self.neverExecutableTools.contains(toolName) && step.kind == .toolCall {
                errors.append(.init(
                    message: "Tool '\(toolName)' cannot be an executable step. Must be humanReview or note.",
                    stepID: step.id
                ))
            }

            // Human-only check
            if Self.humanOnlyTools.contains(toolName) && step.kind == .toolCall {
                errors.append(.init(
                    message: "Tool '\(toolName)' is humanOnly and cannot be automated.",
                    stepID: step.id
                ))
            }

            // Critical risk warning
            if step.risk == .critical {
                warnings.append(.init(
                    message: "Step '\(step.title)' has critical risk.",
                    stepID: step.id
                ))
            }
        }

        // 4. Permissions must be listed
        if draft.requiredPermissions.isEmpty && draft.steps.contains(where: { !$0.requiredPermissions.isEmpty }) {
            warnings.append(.init(message: "Steps require permissions but no workflow-level permissions are listed."))
        }

        // 5. Provenance must exist
        if draft.provenance.sourceSessionID.isEmpty {
            errors.append(.init(message: "Provenance is missing source session ID."))
        }

        // 6. Must have at least one step
        if draft.steps.isEmpty {
            errors.append(.init(message: "Workflow must have at least one step."))
        }

        return WorkflowValidationResult(
            isValid: errors.isEmpty,
            warnings: warnings,
            errors: errors
        )
    }
}
