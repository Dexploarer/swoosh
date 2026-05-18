// SwooshSkills/SkillGuard.swift — Skill safety validation
//
// Validates skills before execution. Checks tool permissions,
// ensures steps don't violate firewall rules, and prevents
// skills from becoming attack vectors.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill guard
// ═══════════════════════════════════════════════════════════════════

/// Validates skill safety before execution.
public struct SkillGuard: Sendable {
    /// Allowed tool IDs. Skills requiring tools not in this set are rejected.
    public let allowedTools: Set<String>
    /// Maximum number of steps per skill.
    public let maxSteps: Int
    /// Whether to allow skills from external/imported sources.
    public let allowImportedSkills: Bool

    public init(
        allowedTools: Set<String> = [],
        maxSteps: Int = 50,
        allowImportedSkills: Bool = false
    ) {
        self.allowedTools = allowedTools
        self.maxSteps = maxSteps
        self.allowImportedSkills = allowImportedSkills
    }

    /// Validate a skill. Returns violations if any.
    public func validate(_ skill: SkillDocument) -> [SkillViolation] {
        var violations: [SkillViolation] = []

        // Check step count
        if skill.steps.count > maxSteps {
            violations.append(.tooManySteps(count: skill.steps.count, max: maxSteps))
        }

        // Check tool permissions
        if !allowedTools.isEmpty {
            for tool in skill.toolsRequired where !allowedTools.contains(tool) {
                violations.append(.disallowedTool(toolID: tool))
            }

            for step in skill.steps {
                if let toolID = step.toolID, !allowedTools.contains(toolID) {
                    violations.append(.disallowedToolInStep(stepOrder: step.order, toolID: toolID))
                }
            }
        }

        // Check provenance
        if !allowImportedSkills && skill.provenance.source == .imported {
            violations.append(.importedSkillNotAllowed)
        }

        // Check for suspicious patterns in instructions
        for step in skill.steps {
            if containsSuspiciousPattern(step.instruction) {
                violations.append(.suspiciousInstruction(stepOrder: step.order,
                                                          reason: "Contains potentially dangerous command pattern"))
            }
        }

        return violations
    }

    /// Check if a skill is safe to execute.
    public func isSafe(_ skill: SkillDocument) -> Bool {
        validate(skill).isEmpty
    }

    private func containsSuspiciousPattern(_ instruction: String) -> Bool {
        let suspicious = [
            "rm -rf /",
            "sudo rm",
            "chmod 777",
            "curl | bash",
            "curl | sh",
            "eval(",
            "exec(",
            "> /dev/sda",
            "mkfs.",
            "dd if=",
            ":(){:|:&};:",    // Fork bomb
        ]
        let lower = instruction.lowercased()
        return suspicious.contains { lower.contains($0) }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Violations
// ═══════════════════════════════════════════════════════════════════

public enum SkillViolation: Sendable, CustomStringConvertible {
    case tooManySteps(count: Int, max: Int)
    case disallowedTool(toolID: String)
    case disallowedToolInStep(stepOrder: Int, toolID: String)
    case importedSkillNotAllowed
    case suspiciousInstruction(stepOrder: Int, reason: String)

    public var description: String {
        switch self {
        case .tooManySteps(let count, let max):
            return "Skill has \(count) steps (max \(max))"
        case .disallowedTool(let toolID):
            return "Skill requires disallowed tool: \(toolID)"
        case .disallowedToolInStep(let order, let toolID):
            return "Step \(order) uses disallowed tool: \(toolID)"
        case .importedSkillNotAllowed:
            return "Imported skills are not allowed by policy"
        case .suspiciousInstruction(let order, let reason):
            return "Step \(order): \(reason)"
        }
    }
}
