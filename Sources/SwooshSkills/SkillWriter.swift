// SwooshSkills/SkillWriter.swift — 0.9S Agent writes skills from experience
//
// The closed learning loop: after the agent completes a complex task,
// it can synthesize the approach into a reusable SkillDocument.
// This is Hermes's killer feature.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skill writer
// ═══════════════════════════════════════════════════════════════════

/// Creates skill documents from completed agent tasks.
public actor SkillWriter {
    private let store: any SkillStoring

    public init(store: any SkillStoring) {
        self.store = store
    }

    /// Create a skill from a completed task.
    ///
    /// Called by the agent after successfully completing a multi-step task.
    /// The agent provides a summary of what it did and the writer
    /// structures it into a reusable skill.
    public func writeSkill(
        title: String,
        description: String,
        category: SkillCategory,
        steps: [SkillStepInput],
        triggerPatterns: [String],
        toolsUsed: [String],
        tags: [String] = [],
        sessionID: String? = nil,
        traceID: String? = nil,
        taskDescription: String? = nil,
        conversationSnippet: String? = nil
    ) async throws -> SkillDocument {
        let skillSteps = steps.enumerated().map { index, input in
            SkillStep(
                order: index + 1,
                instruction: input.instruction,
                toolID: input.toolID,
                toolParameters: input.toolParameters,
                expectedOutput: input.expectedOutput,
                fallback: input.fallback
            )
        }

        let provenance = SkillProvenance(
            createdBySessionID: sessionID,
            createdByTraceID: traceID,
            createdFromTaskDescription: taskDescription,
            originalConversationSnippet: conversationSnippet,
            source: .agentLearned
        )

        let skill = SkillDocument(
            title: title,
            description: description,
            category: category,
            triggerPatterns: triggerPatterns,
            steps: skillSteps,
            toolsRequired: toolsUsed,
            provenance: provenance,
            tags: tags
        )

        try await store.save(skill)
        return skill
    }

    /// Improve an existing skill based on new experience.
    ///
    /// When a skill is used and the agent finds a better approach,
    /// it can update the skill with improved steps or parameters.
    public func improveSkill(
        id: String,
        newSteps: [SkillStepInput]? = nil,
        additionalTriggers: [String]? = nil,
        additionalTags: [String]? = nil,
        sessionID: String? = nil
    ) async throws {
        guard var skill = try await store.get(id: id) else { return }

        if let newSteps {
            skill.steps = newSteps.enumerated().map { index, input in
                SkillStep(
                    order: index + 1,
                    instruction: input.instruction,
                    toolID: input.toolID,
                    toolParameters: input.toolParameters,
                    expectedOutput: input.expectedOutput,
                    fallback: input.fallback
                )
            }
        }

        if let additionalTriggers {
            skill.triggerPatterns.append(contentsOf: additionalTriggers)
            skill.triggerPatterns = Array(Set(skill.triggerPatterns))  // Dedupe
        }

        if let additionalTags {
            skill.tags.append(contentsOf: additionalTags)
            skill.tags = Array(Set(skill.tags))
        }

        if let sessionID {
            skill.provenance.improvedBySessionIDs.append(sessionID)
        }

        try await store.update(skill)
    }

    /// Check if a similar skill already exists (avoid duplicates).
    public func hasSimilarSkill(title: String) async throws -> SkillDocument? {
        let results = try await store.search(query: title, limit: 3)
        return results.first { $0.title.lowercased() == title.lowercased() }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Input model for step creation
// ═══════════════════════════════════════════════════════════════════

/// Input model for creating skill steps (simpler than SkillStep).
public struct SkillStepInput: Sendable {
    public let instruction: String
    public let toolID: String?
    public let toolParameters: [String: String]?
    public let expectedOutput: String?
    public let fallback: String?

    public init(instruction: String, toolID: String? = nil,
                toolParameters: [String: String]? = nil,
                expectedOutput: String? = nil, fallback: String? = nil) {
        self.instruction = instruction
        self.toolID = toolID
        self.toolParameters = toolParameters
        self.expectedOutput = expectedOutput
        self.fallback = fallback
    }
}
