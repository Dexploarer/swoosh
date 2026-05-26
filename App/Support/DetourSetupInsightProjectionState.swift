// DetourSetupInsightProjectionState.swift — setup insight state helpers (0.5A)

import Foundation

struct DetourSetupInsightCandidateGroup {
    var publicID: String
    var candidates: [DetourSetupCandidate]

    var representative: DetourSetupCandidate { candidates[0] }
}

extension DetourSetupInsightProjection {
    static func candidateGroups(_ candidates: [DetourSetupCandidate]) -> [DetourSetupInsightCandidateGroup] {
        var buckets: [String: [DetourSetupCandidate]] = [:]
        var order: [String] = []
        for candidate in candidates {
            let key = candidateGroupKey(candidate)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(candidate)
        }
        var publicBuckets: [String: DetourSetupInsightCandidateGroup] = [:]
        var publicOrder: [String] = []
        for key in order {
            guard let values = buckets[key], let first = values.first else { continue }
            let publicID = publicCandidateID(for: first, groupCount: values.count)
            if publicBuckets[publicID] == nil {
                publicOrder.append(publicID)
                publicBuckets[publicID] = DetourSetupInsightCandidateGroup(publicID: publicID, candidates: values)
            } else if var existing = publicBuckets[publicID] {
                existing.candidates.append(contentsOf: values)
                publicBuckets[publicID] = existing
            }
        }
        return publicOrder.compactMap { publicBuckets[$0] }
    }

    static func candidateRawIDsByPublicID(_ candidates: [DetourSetupCandidate]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for group in candidateGroups(candidates) {
            for id in group.candidates.map(\.id) where result[group.publicID, default: []].contains(id) == false {
                result[group.publicID, default: []].append(id)
            }
        }
        return result
    }

    static func publicCandidateID(for candidate: DetourSetupCandidate) -> String {
        publicCandidateID(for: candidate, groupCount: 1)
    }

    private static func publicCandidateID(for candidate: DetourSetupCandidate, groupCount: Int) -> String {
        let components = sanitizedCandidateIDComponents(candidate)
        return DetourSetupInsightRedaction.stableID(
            prefix: "candidate",
            components: [candidate.category.rawValue, candidateGroupKey(candidate), "\(groupCount)", stableDigest(components)]
        )
    }

    static func insightStatus(from item: DetourSetupApplicationItem) -> DetourSetupInsightStatus {
        if item.state == .connected && !isLiveRuntimeVerified(item) {
            return .using
        }
        return insightStatus(from: item.state)
    }

    static func insightStatus(from state: DetourSetupApplicationState) -> DetourSetupInsightStatus {
        switch state {
        case .checking:
            return .pending
        case .connected:
            return .verified
        case .enabled:
            return .using
        case .needsAction:
            return .blocked
        case .removed:
            return .removed
        case .failed:
            return .failed
        }
    }

    private static func isLiveRuntimeVerified(_ item: DetourSetupApplicationItem) -> Bool {
        (item.id.hasPrefix("connector.") && item.id.hasSuffix(".health"))
            || (item.id.hasPrefix("mcp.") && item.id.hasSuffix(".configured"))
    }

    private static func sanitizedCandidateIDComponents(_ candidate: DetourSetupCandidate) -> [String] {
        [
            candidate.category.rawValue,
            candidate.title,
            candidate.detail,
            candidate.source,
            candidate.prompt ?? "",
            (candidate.credentialKeys ?? []).sorted().joined(separator: " "),
            candidate.scope?.rawValue ?? "",
        ]
            .map(DetourSetupInsightRedaction.display)
            .filter { !$0.isEmpty }
    }

    private static func candidateGroupKey(_ candidate: DetourSetupCandidate) -> String {
        if let xHandle = xAccountHandle(candidate) {
            return "x.\(xHandle.lowercased())"
        }
        guard shouldGroupKeychainCredential(candidate) else {
            return stableIDPayload(candidate)
        }
        let keys = (candidate.credentialKeys ?? []).sorted().joined(separator: " ")
        let provider = candidate.credentialProviderID
            ?? keys.nilIfEmpty
            ?? credentialProviderName(candidate)
        return "keychain.\(provider.lowercased())"
    }

    private static func shouldGroupKeychainCredential(_ candidate: DetourSetupCandidate) -> Bool {
        let text = stableIDPayload(candidate).lowercased()
        return candidate.id.hasPrefix("credential.")
            && text.contains("keychain")
            && !text.contains("x session")
            && !text.contains("browser")
    }

    private static func stableIDPayload(_ candidate: DetourSetupCandidate) -> String {
        [
            candidate.id,
            candidate.category.rawValue,
            candidate.title,
            candidate.detail,
            candidate.source,
        ].joined(separator: "|")
    }

    private static func credentialProviderName(_ candidate: DetourSetupCandidate) -> String {
        let title = DetourSetupInsightRedaction.display(candidate.title).lowercased()
        for provider in ["openai", "claude", "gemini", "codex", "github", "discord", "telegram", "agentmail"] {
            if title.contains(provider) { return provider }
        }
        return "saved-access"
    }

    static func xAccountHandle(_ candidate: DetourSetupCandidate) -> String? {
        let text = stableIDPayload(candidate)
        guard text.lowercased().contains("x session") else { return nil }
        var searchStart = text.startIndex
        while let marker = text[searchStart...].range(of: "@") {
            if marker.lowerBound > text.startIndex {
                let previous = text[text.index(before: marker.lowerBound)]
                if previous.isLetter || previous.isNumber || previous == "." || previous == "_" || previous == "-" {
                    searchStart = marker.upperBound
                    continue
                }
            }
            var handle = ""
            for character in text[marker.upperBound...] {
                guard character.isLetter || character.isNumber || character == "_" else { break }
                handle.append(character)
            }
            if (1...15).contains(handle.count) {
                return "@\(handle.lowercased())"
            }
            searchStart = marker.upperBound
        }
        return nil
    }

    private static func stableDigest(_ components: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in components.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
