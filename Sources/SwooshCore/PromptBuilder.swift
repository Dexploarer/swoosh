// SwooshCore/PromptBuilder.swift — 0.9S Privacy boundary
//
// Builds the system prompt from approved-only context. This file used
// to live inside AgentKernel.swift but was hoisted out in 0.9S to
// match the project-root CLAUDE.md, which has always treated
// PromptBuilder as a separate architectural component, and to drop
// AgentKernel.swift below the 400 LOC ceiling.
//
// Hard privacy rules enforced here:
// - Approved memories: YES
// - Setup report summary: YES
// - Permission summary: YES
// - Skill catalog (Level-0 titles only): YES
// - Rejected memory candidates: NEVER
// - Raw Scout records: NEVER
// - Cookies / browser history / contacts: NEVER
// - Secrets / SSH keys / API keys: NEVER
//
// The `ResponseAuditRecord` (defined in AgentKernel.swift) carries
// four `*Excluded` flags that the kernel sets to `true` after every
// turn so /why can prove these rules were honoured.

import Foundation

/// Builds the system prompt from approved-only context.
/// This is the critical privacy boundary:
/// - Approved memories: YES
/// - Setup report summary: YES
/// - Permission summary: YES
/// - Rejected candidates: NEVER
/// - Raw Scout records: NEVER
/// - Cookies: NEVER
/// - Secrets: NEVER
public struct PromptBuilder: Sendable {

    public init() {}

    public func buildSystemPrompt(
        approvedMemories: [(id: String, text: String, category: String)],
        setupReport: String?,
        permissionSummary: String?,
        skillCatalog: [(id: String, title: String, description: String)] = []
    ) -> (prompt: String, memoryIDs: [String]) {

        var sections: [String] = []
        var usedMemoryIDs: [String] = []

        // Identity. "Detour" is the agent's user-facing persona; "Swoosh"
        // is the product / codebase that runs it. The model should always
        // self-identify as Detour.
        sections.append("""
        You are Detour, a Swift-native personal agent for macOS and iOS.
        You answer using only context the user has explicitly approved.
        You must not imply access to data the user has not granted.
        You must not reference cookies, browser history, contacts, or secrets.
        If asked what you are or what runs you, you can mention that you
        are Detour, built on the Swoosh runtime.
        """)

        // Approved memories
        let uniqueMemories = deduplicated(approvedMemories)
        if !uniqueMemories.isEmpty {
            var memBlock = "## Approved Memories\n"
            memBlock += "The following facts were approved by the user:\n\n"
            for mem in uniqueMemories {
                memBlock += "- [\(mem.category)] \(mem.text)\n"
                usedMemoryIDs.append(mem.id)
            }
            sections.append(memBlock)
        }

        // Setup report
        if let report = setupReport, !report.isEmpty {
            sections.append("## Setup Report Summary\n\(report)")
        }

        // Permission summary
        if let perms = permissionSummary, !perms.isEmpty {
            sections.append("## Permission Profile\n\(perms)")
        }

        // Skill catalog (Level-0 progressive disclosure)
        // Only the (title, description) pair is injected. The model
        // pulls the full body via `skill_get` when it decides a skill
        // applies. Draft / rejected skills never reach this list — the
        // catalog loader enforces the SkillTrust.promptable filter.
        if !skillCatalog.isEmpty {
            var skillBlock = "## Available Skills\n"
            skillBlock += "Reusable procedures the user has approved. Use `skill_get` to load a body.\n\n"
            for skill in skillCatalog {
                skillBlock += "- **\(skill.title)** (\(skill.id)) — \(skill.description)\n"
            }
            sections.append(skillBlock)
        }

        // Exclusion statement (for auditability)
        sections.append("""
        ## Data Exclusions
        The following data sources are NOT available in this context:
        - Rejected memory candidates
        - Raw Scout scan records
        - Browser cookies
        - Browser history
        - Contacts, mail, messages
        - SSH keys, API keys, secrets
        - Files outside approved folders
        - Draft / rejected skill candidates
        """)

        let prompt = sections.joined(separator: "\n\n")
        return (prompt, usedMemoryIDs)
    }

    private func deduplicated(
        _ memories: [(id: String, text: String, category: String)]
    ) -> [(id: String, text: String, category: String)] {
        var seen = Set<String>()
        var result: [(id: String, text: String, category: String)] = []
        for memory in memories {
            let key = "\(normalize(memory.category))\u{1F}\(normalize(memory.text))"
            if seen.insert(key).inserted {
                result.append(memory)
            }
        }
        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
