// SwooshSkills/SkillTools.swift — 0.9S Tool-surface common types
//
// Seven tools the agent (or user via CLI) can invoke. Each lives in its
// own file under `SkillTools/` so this monolith stayed under the 400
// LOC ceiling after the audit follow-up split:
//
//   • skill_list     — Level-0 catalog (id, title, description, trust)
//   • skill_get      — Level-1 body for a specific skill
//   • skill_search   — Relevance-ranked match against a query
//   • skill_propose  — Model emits a draft (lands as `.draft`, never auto-promoted)
//   • skill_install  — Install an agentskills-style SKILL.md (file / URL / github:)
//   • skill_manage   — Create/update/delete drafts + support files
//   • skill_approve  — User promotes draft → reviewed/promoted/frozen (humanOnly)
//
// `skill_approve` is firewalled at the `humanOnly` approval level so
// the model can't auto-promote skills it wrote — same trust contract
// as the memory pipeline.

import Foundation
import SwooshTools

// MARK: - Common dependencies

public struct SkillToolDependencies: Sendable {
    public let store: any SkillStoring
    public let writer: SkillWriter
    public let matcher: SkillMatcher
    public let installer: SkillInstaller

    public init(store: any SkillStoring) {
        self.store = store
        self.writer = SkillWriter(store: store)
        self.matcher = SkillMatcher(store: store)
        self.installer = SkillInstaller(store: store)
    }
}

// MARK: - Shared errors

public enum SkillToolError: Error, Sendable, LocalizedError {
    case notFound(String)
    case noSkillDirectory(String)
    case invalidPath(String)
    case missingField(String)
    case pinned(String)
    case invalidSkill(String)
    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "skill not found: \(id)"
        case .noSkillDirectory(let id): return "skill has no support-file directory: \(id)"
        case .invalidPath(let path): return "invalid skill support-file path: \(path)"
        case .missingField(let field): return "missing field: \(field)"
        case .pinned(let id): return "skill is pinned and cannot be deleted: \(id)"
        case .invalidSkill(let reason): return "invalid skill: \(reason)"
        }
    }
}

// MARK: - Shared helpers

/// Expand `${SWOOSH_SKILL_DIR}` / `${SWOOSH_SESSION_ID}` (plus the
/// `HERMES_*` aliases for ported agentskills bodies) in a skill body or
/// support file. Internal so the get + manage tool files can share it
/// without duplicating the substitution table.
func substituteTemplateVariables(_ content: String, skillDirectory: String?, sessionID: String) -> String {
    content
        .replacingOccurrences(of: "${SWOOSH_SKILL_DIR}", with: skillDirectory ?? "")
        .replacingOccurrences(of: "${HERMES_SKILL_DIR}", with: skillDirectory ?? "")
        .replacingOccurrences(of: "${SWOOSH_SESSION_ID}", with: sessionID)
        .replacingOccurrences(of: "${HERMES_SESSION_ID}", with: sessionID)
}
