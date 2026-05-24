// SwooshSkills/SkillMatcher.swift — 0.9S Contextual skill matching
//
// Given a task description, find the most relevant skills from the store.
// Uses keyword matching, category inference, and usage statistics.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill matcher
// ═══════════════════════════════════════════════════════════════════

/// Matches tasks to existing skills for contextual loading.
public actor SkillMatcher {
    private let store: any SkillStoring

    public init(store: any SkillStoring) {
        self.store = store
    }

    /// Find skills relevant to a task description.
    /// Returns skills ranked by relevance, limited to `maxResults`.
    public func match(
        taskDescription: String,
        category: SkillCategory? = nil,
        maxResults: Int = 5
    ) async throws -> [SkillMatch] {
        // Strategy 1: FTS search on task description
        let searchResults = try await store.search(query: taskDescription, limit: maxResults * 2)

        // Strategy 2: Category filter if specified
        let categoryResults: [SkillDocument]
        if let cat = category {
            categoryResults = try await store.findByCategory(cat)
        } else {
            let inferred = inferCategory(from: taskDescription)
            categoryResults = try await store.findByCategory(inferred)
        }

        // Strategy 3: Trigger pattern matching
        let allSkills = try await store.listAll()
        let triggerMatches = allSkills.filter { skill in
            skill.triggerPatterns.contains { pattern in
                taskDescription.localizedCaseInsensitiveContains(pattern)
            }
        }

        // Merge and score
        var scored: [String: (SkillDocument, Double)] = [:]

        for skill in searchResults {
            scored[skill.id, default: (skill, 0)].1 += 10.0
        }

        for skill in categoryResults {
            scored[skill.id, default: (skill, 0)].1 += 5.0
        }

        for skill in triggerMatches {
            scored[skill.id, default: (skill, 0)].1 += 15.0  // Trigger match is strongest
        }

        // Boost by success rate and usage
        for (id, var entry) in scored {
            entry.1 += entry.0.successRate * 3.0
            if entry.0.usageCount > 10 { entry.1 += 2.0 }   // Battle-tested
            scored[id] = entry
        }

        return scored.values
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map { SkillMatch(skill: $0.0, relevanceScore: $0.1) }
    }

    /// Infer the most likely category from a task description.
    private func inferCategory(from description: String) -> SkillCategory {
        let lower = description.lowercased()
        let categoryKeywords: [(SkillCategory, [String])] = [
            (.coding, ["code", "implement", "function", "class", "struct", "swift", "write code"]),
            (.debugging, ["bug", "fix", "error", "crash", "debug", "issue", "broken"]),
            (.deployment, ["deploy", "build", "release", "ship", "production", "ci/cd"]),
            (.testing, ["test", "spec", "assert", "coverage", "verify"]),
            (.documentation, ["document", "readme", "doc", "explain", "comment"]),
            (.refactoring, ["refactor", "clean", "simplify", "extract", "rename"]),
            (.research, ["research", "investigate", "look up", "find", "search"]),
            (.git, ["git", "commit", "branch", "merge", "rebase", "push", "pull"]),
            (.browser, ["browse", "scrape", "crawl", "web page", "url"]),
            (.systemAdmin, ["server", "ssh", "permission", "install", "configure"]),
            (.dataAnalysis, ["analyze", "data", "parse", "aggregate", "statistics"]),
            (.communication, ["email", "message", "notify", "send", "slack"]),
            (.media, ["image", "audio", "video", "screenshot", "record"]),
        ]

        var bestCategory = SkillCategory.general
        var bestScore = 0

        for (category, keywords) in categoryKeywords {
            let score = keywords.filter { lower.contains($0) }.count
            if score > bestScore {
                bestScore = score
                bestCategory = category
            }
        }

        return bestCategory
    }
}

/// A skill match with a relevance score.
public struct SkillMatch: Sendable {
    public let skill: SkillDocument
    public let relevanceScore: Double
}
