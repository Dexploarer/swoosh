// SwooshCore/PromptBuilder.swift — 0.9T Privacy boundary
//
// Builds the system prompt from approved-only context. This file used
// to live inside AgentKernel.swift but was hoisted out in 0.9S to
// match the project-root CLAUDE.md, which has always treated
// PromptBuilder as a separate architectural component, and to drop
// AgentKernel.swift below the 400 LOC ceiling.
//
// 0.9T tightens the surface: 3-tuple inputs replaced with named
// `ApprovedMemory` and `SkillCatalogEntry` structs, the return
// 2-tuple replaced with `SystemPrompt` — silences SwiftLint
// large_tuple and produces a sturdier API. Callers map their
// protocol-shaped tuples at the boundary.
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

import Foundation

/// One approved memory passed to the prompt builder. Stable, named
/// shape so the builder's API isn't a 3-tuple (lints flag those).
public struct ApprovedMemory: Sendable {
    public let id: String
    public let text: String
    public let category: String
    public init(id: String, text: String, category: String) {
        self.id = id; self.text = text; self.category = category
    }
}

/// One entry in the Level-0 skill catalog injected into the prompt.
/// Only the (id, title, description) triple ships — the model pulls
/// the body via `skill_get` when it decides a skill applies.
public struct SkillCatalogEntry: Sendable {
    public let id: String
    public let title: String
    public let description: String
    public init(id: String, title: String, description: String) {
        self.id = id; self.title = title; self.description = description
    }
}

/// Output of `PromptBuilder.buildSystemPrompt`. Named struct (not a
/// tuple) so the return type is documented and `large_tuple` stays
/// happy.
public struct SystemPrompt: Sendable {
    public let prompt: String
    public let memoryIDs: [String]
    public init(prompt: String, memoryIDs: [String]) {
        self.prompt = prompt
        self.memoryIDs = memoryIDs
    }
}

public struct PromptBuilder: Sendable {

    public init() {}

    /// Build the system prompt — privacy boundary entry point. The
    /// per-section assembly lives in `*Section(...)` helpers so this
    /// method stays under the function-body-length lint.
    public func buildSystemPrompt(
        approvedMemories: [ApprovedMemory],
        setupReport: String?,
        permissionSummary: String?,
        skillCatalog: [SkillCatalogEntry] = []
    ) -> SystemPrompt {
        var sections: [String] = [Self.identitySection]
        var usedMemoryIDs: [String] = []

        let uniqueMemories = deduplicated(approvedMemories)
        if let memorySection = Self.memoriesSection(uniqueMemories, ids: &usedMemoryIDs) {
            sections.append(memorySection)
        }
        if let report = setupReport, !report.isEmpty {
            sections.append("## Setup Report Summary\n\(report)")
        }
        if let perms = permissionSummary, !perms.isEmpty {
            sections.append("## Permission Profile\n\(perms)")
        }
        if let skillSection = Self.skillsSection(skillCatalog) {
            sections.append(skillSection)
        }
        sections.append(Self.exclusionsSection)

        return SystemPrompt(
            prompt: sections.joined(separator: "\n\n"),
            memoryIDs: usedMemoryIDs
        )
    }

    // MARK: - Section builders

    /// Identity preamble. "Detour" is the user-facing persona; "Swoosh"
    /// is the product / codebase that runs it.
    private static let identitySection = """
    You are Detour, a Swift-native personal agent for macOS and iOS.
    You answer using only context the user has explicitly approved.
    You must not imply access to data the user has not granted.
    You must not reference cookies, browser history, contacts, or secrets.
    If asked what you are or what runs you, you can mention that you
    are Detour, built on the Swoosh runtime.
    """

    private static func memoriesSection(
        _ memories: [ApprovedMemory],
        ids: inout [String]
    ) -> String? {
        guard !memories.isEmpty else { return nil }
        var block = "## Approved Memories\n"
        block += "The following facts were approved by the user:\n\n"
        for mem in memories {
            block += "- [\(mem.category)] \(mem.text)\n"
            ids.append(mem.id)
        }
        return block
    }

    private static func skillsSection(_ catalog: [SkillCatalogEntry]) -> String? {
        guard !catalog.isEmpty else { return nil }
        var block = "## Available Skills\n"
        block += "Reusable procedures the user has approved. Use `skill_get` to load a body.\n\n"
        for skill in catalog {
            block += "- **\(skill.title)** (\(skill.id)) — \(skill.description)\n"
        }
        return block
    }

    /// Auditability statement — explicit list of data sources the
    /// model must NOT have inferred access to. Pinned text so a
    /// reviewer searching for any of these strings finds them.
    private static let exclusionsSection = """
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
    """

    // MARK: - Dedupe

    private func deduplicated(_ memories: [ApprovedMemory]) -> [ApprovedMemory] {
        var seen = Set<String>()
        var result: [ApprovedMemory] = []
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
