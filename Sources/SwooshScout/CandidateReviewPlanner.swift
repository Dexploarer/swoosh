// SwooshScout/CandidateReviewPlanner.swift — Memory candidate consolidation

import Foundation

public struct CandidateReviewPlanner: Sendable {
    public init() {}

    public func plan(
        candidates: [MemoryCandidate],
        existingMemories: [ExistingMemorySummary],
        minimumConfidence: Double = 0.0
    ) -> [MemoryCandidate] {
        let existing = Set(existingMemories.map { key(text: $0.text, category: $0.category) })
        var bestByKey: [String: MemoryCandidate] = [:]

        for candidate in candidates where candidate.confidence >= minimumConfidence {
            let candidateKey = key(text: candidate.text, category: candidate.category)
            if existing.contains(candidateKey) { continue }
            guard let current = bestByKey[candidateKey] else {
                bestByKey[candidateKey] = candidate
                continue
            }
            if candidate.confidence > current.confidence ||
                (candidate.confidence == current.confidence && candidate.evidence.count > current.evidence.count) {
                bestByKey[candidateKey] = candidate
            }
        }

        return bestByKey.values.sorted { lhs, rhs in
            if lhs.sensitivity != rhs.sensitivity { return lhs.sensitivity < rhs.sensitivity }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.text < rhs.text
        }
    }

    private func key(text: String, category: String) -> String {
        "\(normalize(category))|\(normalize(text))"
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
