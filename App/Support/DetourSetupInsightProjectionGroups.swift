// DetourSetupInsightProjectionGroups.swift — grouped setup insight copy (0.5A)

import Foundation

extension DetourSetupInsightProjection {
    static func groupTitle(_ group: DetourSetupInsightCandidateGroup) -> String {
        if let handle = xAccountHandle(group.representative) {
            return "X account \(handle)"
        }
        guard group.candidates.count > 1, group.representative.id.hasPrefix("credential.") else {
            return DetourSetupInsightRedaction.display(group.representative.title)
        }
        return "\(credentialProviderDisplayName(group.representative)) saved access"
    }

    static func groupDetail(
        _ group: DetourSetupInsightCandidateGroup,
        owner: DetourSetupInsightOwner,
        input: DetourSetupInsightProjectionInput
    ) -> String {
        let ownerLabel = DetourSetupInsightRedaction.ownerLabel(
            owner,
            userName: input.userName,
            agentName: input.agentName
        )
        guard group.candidates.count > 1, group.representative.id.hasPrefix("credential.") else {
            let base = DetourSetupInsightRedaction.display(group.representative.detail)
            return groupNeedsScope(group) ? "\(base) Owner: \(ownerLabel)." : base
        }
        if let handle = xAccountHandle(group.representative) {
            let browsers = Set(group.candidates.map(\.title).compactMap(browserName)).sorted()
            let browserText = browsers.isEmpty ? "browser profiles" : browsers.joined(separator: ", ")
            return "Found signed-in X account \(handle) in \(group.candidates.count) \(browserText) profile\(group.candidates.count == 1 ? "" : "s"). Owner: \(ownerLabel)."
        }
        return "Found \(group.candidates.count) related saved access items. Detour will use only the ones you approve and scope. Owner: \(ownerLabel)."
    }

    static func groupRole(
        _ group: DetourSetupInsightCandidateGroup,
        input: DetourSetupInsightProjectionInput
    ) -> DetourDelegationRole? {
        group.candidates.compactMap { input.setupCandidateScopes[$0.id] ?? $0.scope }.first
    }

    private static func groupNeedsScope(_ group: DetourSetupInsightCandidateGroup) -> Bool {
        group.candidates.contains { candidate in
            candidate.scope != nil
                || candidate.prompt != nil
                || candidate.credentialProviderID != nil
                || candidate.credentialKeys?.isEmpty == false
                || candidate.id.hasPrefix("credential.")
        }
    }

    private static func credentialProviderDisplayName(_ candidate: DetourSetupCandidate) -> String {
        let value = [candidate.title, candidate.detail, candidate.source].joined(separator: " ").lowercased()
        if value.contains("openai") { return "OpenAI" }
        if value.contains("claude") || value.contains("anthropic") { return "Claude" }
        if value.contains("gemini") { return "Gemini" }
        if value.contains("codex") { return "Codex" }
        if value.contains("github") { return "GitHub" }
        if value.contains("discord") { return "Discord" }
        if value.contains("telegram") { return "Telegram" }
        if value.contains("agentmail") { return "AgentMail" }
        return "Saved"
    }

    private static func browserName(_ value: String) -> String? {
        ["Chrome", "Arc", "Safari", "Brave", "Edge", "Firefox"].first { value.localizedCaseInsensitiveContains($0) }
    }
}
