// SwooshDaemon/DaemonMetaTasks.swift — 0.9S Manifester miner + goal judge
//
// Model-backed closures the daemon hands to the manifester (pattern
// miner) and the goal runner (judge). Both fall back to deterministic
// stubs when no meta-provider is configured so the rest of the runtime
// keeps working without a model.
//
// Each closure prompts the model in the same shape (system + user
// messages) and decodes a JSON envelope defensively — code fences and
// extra prose are stripped before decoding.

import Foundation
import SwooshCore
import SwooshGoals
import SwooshManifesting

/// Build the manifester's pattern miner. When `metaProvider` is nil the
/// deterministic miner still emits conservative audit observations. When
/// a provider is supplied, the miner asks it for structured proposals.
@Sendable
func makeMiner(metaProvider: (any SwooshCore.ModelProvider)?) -> Manifester.PatternMiner {
    guard let provider = metaProvider else {
        return Manifester.deterministicMiner
    }
    return { events in
        let condensed = events.prefix(50).map {
            "- [\($0.timestamp.timeIntervalSince1970)] \($0.kind): \($0.summary)"
        }.joined(separator: "\n")
        let system = """
        You are Swoosh's nightly Manifester. Read the user's recent audit
        events and propose at most five new skill drafts or memory
        candidates that would make the agent more useful tomorrow.
        Respond with a JSON array. Each item must be:
        { "kind": "newSkill" | "newMemoryCandidate" | "observation",
          "title": string, "rationale": string, "confidence": 0..1,
          "payload": string }
        No prose outside the JSON.
        """
        let user = """
        Recent audit events (\(events.count) total, most recent first):
        \(condensed)
        """
        let response = try await provider.complete(SwooshCore.ModelCompletionRequest(
            messages: [
                SwooshCore.ChatMessage(role: .system, content: system),
                SwooshCore.ChatMessage(role: .user, content: user),
            ],
            model: nil
        ))
        // Extract the JSON array. Models sometimes wrap it in code
        // fences; strip those and decode defensively.
        let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let data = stripped.data(using: .utf8) else { return [] }
        struct RawProposal: Decodable {
            let kind: String
            let title: String
            let rationale: String
            let confidence: Double?
            let payload: String?
        }
        let decoded = (try? JSONDecoder().decode([RawProposal].self, from: data)) ?? []
        return decoded.compactMap { item in
            let kind: ManifestationProposal.Kind
            switch item.kind {
            case "newSkill": kind = .newSkill
            case "skillImprovement": kind = .skillImprovement
            case "skillMerge": kind = .skillMerge
            case "skillRetire": kind = .skillRetire
            case "newMemoryCandidate": kind = .newMemoryCandidate
            case "memoryConsolidation": kind = .memoryConsolidation
            default: kind = .observation
            }
            return ManifestationProposal(
                kind: kind,
                title: item.title,
                rationale: item.rationale,
                confidence: item.confidence ?? 0.6,
                payloadJSON: item.payload ?? "{}"
            )
        }
    }
}

/// Build the goal runner's judge. Defers to the sentinel-heuristic
/// judge when no provider is available; otherwise asks the model for a
/// structured verdict.
@Sendable
func makeJudge(metaProvider: (any SwooshCore.ModelProvider)?) -> GoalRunner.Judge {
    guard let provider = metaProvider else {
        return GoalRunner.heuristicJudge
    }
    return { goal, observation in
        let system = """
        You are the judge for one of Swoosh's persistent goals. Read the
        user's goal statement and the agent's most recent observation.
        Respond with one JSON object:
        { "verdict": "progressing" | "stuck" | "completed" | "needsUserInput",
          "rationale": string }
        Be conservative — only return "completed" when the agent has
        explicitly produced the deliverable the goal asks for.
        """
        let user = """
        Goal: \(goal.statement)

        Latest observation:
        \(observation)
        """
        let response = try await provider.complete(SwooshCore.ModelCompletionRequest(
            messages: [
                SwooshCore.ChatMessage(role: .system, content: system),
                SwooshCore.ChatMessage(role: .user, content: user),
            ],
            model: nil
        ))
        struct RawVerdict: Decodable {
            let verdict: String
            let rationale: String?
        }
        let stripped = response.content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = stripped.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(RawVerdict.self, from: data)
        else {
            return (.progressing, "judge returned unparseable response")
        }
        let verdict: GoalJudgement
        switch decoded.verdict {
        case "completed": verdict = .completed
        case "stuck": verdict = .stuck
        case "needsUserInput": verdict = .needsUserInput
        default: verdict = .progressing
        }
        return (verdict, decoded.rationale)
    }
}
