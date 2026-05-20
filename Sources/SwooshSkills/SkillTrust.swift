// SwooshSkills/SkillTrust.swift — Trust gating for skills
//
// Skills enter the agent's prompt only after the user has accepted them,
// the same rule the memory pipeline already enforces. Model-proposed
// drafts sit in an inbox until promoted; nothing crosses into the prompt
// without a `.reviewed`+ stamp.

import Foundation

public enum SkillTrust: String, Codable, Sendable, CaseIterable, Comparable {
    /// Model- or curator-proposed. Sits in the inbox; never enters prompts.
    case draft
    /// User has seen this skill, has not rejected it, but hasn't explicitly
    /// approved either. Enters prompts but flagged as unverified.
    case reviewed
    /// User has explicitly approved. Full prompt-level trust.
    case promoted
    /// User has marked canonical. The manifester is not allowed to mutate
    /// this skill on its own — only explicit user edits do.
    case frozen
    /// User has rejected. Stays in the store for audit, never reaches a prompt.
    case rejected

    public static func < (lhs: SkillTrust, rhs: SkillTrust) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ trust: SkillTrust) -> Int {
        switch trust {
        case .rejected: return -1
        case .draft:    return 0
        case .reviewed: return 1
        case .promoted: return 2
        case .frozen:   return 3
        }
    }

    /// Trust levels that may enter the agent's prompt catalog.
    public static let promptable: Set<SkillTrust> = [.reviewed, .promoted, .frozen]
}
