// OnboardingStoreSetupInsights.swift — setup insight projection bridge (0.5A)

import Foundation

enum DetourSetupInsightPermissionRoute {
    case credentialConfiguration
    case fullDiskAccess
    case contacts
}

struct DetourSetupInsightCredentialConfiguration {
    var publicID: String
    var title: String
    var keys: [String]
    var scope: DetourDelegationRole?
}

@MainActor
extension OnboardingStore {
    var setupInsightSnapshot: DetourSetupInsightSnapshot {
        DetourSetupInsightProjection.snapshot(DetourSetupInsightProjectionInput(
            result: personalizationResult,
            approvedCandidateIDs: approvedSetupCandidateIDs,
            deniedCandidateIDs: deniedSetupCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            report: setupApplicationReport,
            userName: userName,
            agentName: agentName
        ))
    }

    var setupInsightHasContent: Bool {
        !setupInsightSnapshot.sections.allSatisfy(\.items.isEmpty)
    }

    func setSetupInsightCandidateApproval(publicID: String, approved: Bool) {
        for rawID in setupInsightCandidateIDs(publicID: publicID) {
            setPersonalizationCandidateApproval(id: rawID, approved: approved)
        }
    }

    func removeSetupInsightCandidateFromContext(publicID: String) {
        let rawIDs = setupInsightCandidateIDs(publicID: publicID)
        guard !rawIDs.isEmpty else { return }
        for rawID in rawIDs {
            approvedSetupCandidateIDs.remove(rawID)
            deniedSetupCandidateIDs.insert(rawID)
            setupCandidateScopes.removeValue(forKey: rawID)
        }
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    func setupInsightConfiguredCredentialKeys(publicID: String) -> [String] {
        let rawIDs = setupInsightCandidateIDs(publicID: publicID)
        guard let candidates = personalizationResult?.setupCandidates.filter({ rawIDs.contains($0.id) }) else {
            return []
        }
        return Array(Set(candidates.flatMap(configurationKeys(for:)))).sorted()
    }

    func setSetupInsightCandidateScope(publicID: String, role: DetourDelegationRole) {
        for rawID in setupInsightCandidateIDs(publicID: publicID) {
            setPersonalizationCandidateScope(id: rawID, role: role)
        }
    }

    func setupInsightPermissionRoute(publicID: String) -> DetourSetupInsightPermissionRoute? {
        guard let rawID = setupInsightCandidateIDs(publicID: publicID).first else { return nil }
        switch rawID {
        case "connector.imessage", "context.messages":
            return .fullDiskAccess
        case "context.contacts":
            return .contacts
        default:
            return setupInsightConfiguration(publicID: publicID) == nil ? nil : .credentialConfiguration
        }
    }

    func setupInsightConfiguration(publicID: String) -> DetourSetupInsightCredentialConfiguration? {
        let rawIDs = setupInsightCandidateIDs(publicID: publicID)
        guard let candidates = personalizationResult?.setupCandidates.filter({ rawIDs.contains($0.id) }),
              let candidate = candidates.first else {
            return nil
        }
        let keys = configurationKeys(for: candidate)
        guard !keys.isEmpty else { return nil }
        return DetourSetupInsightCredentialConfiguration(
            publicID: publicID,
            title: candidate.title,
            keys: keys,
            scope: candidate.scope
        )
    }

    func prepareSetupInsightDoctor(publicID: String) {
        guard setupInsightReportItemID(publicID: publicID) != nil else { return }
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    func reopenPersonalizationSetup() {
        guard step != .complete else { return }
        step = personalizationResult == nil ? .askingPersonalizationScan : .reviewingPersonalizationScan
        saveProfile(onboardingCompleted: false)
    }

    private func setupInsightCandidateIDs(publicID: String) -> [String] {
        if let ids = setupInsightCandidateRawIDsByPublicID[publicID] {
            return ids
        }
        guard personalizationResult?.setupCandidates.contains(where: { $0.id == publicID }) == true else {
            return []
        }
        return [publicID]
    }

    private var setupInsightCandidateRawIDsByPublicID: [String: [String]] {
        guard let candidates = personalizationResult?.setupCandidates else { return [:] }
        return DetourSetupInsightProjection.candidateRawIDsByPublicID(candidates)
    }

    private func setupInsightReportItemID(publicID: String) -> String? {
        guard publicID.hasPrefix("report."),
              let index = Int(publicID.dropFirst("report.".count)),
              let items = setupApplicationReport?.items,
              items.indices.contains(index) else { return nil }
        return items[index].id
    }

    private func configurationKeys(for candidate: DetourSetupCandidate) -> [String] {
        switch candidate.id {
        case "connector.discord":
            return ["DISCORD_BOT_TOKEN"]
        case "connector.telegram":
            return ["TELEGRAM_BOT_TOKEN"]
        case "connector.github", "mcp.github":
            return ["GITHUB_USER_PAT"]
        case "connector.slack", "mcp.slack":
            return ["SLACK_BOT_TOKEN", "SLACK_TEAM_ID"]
        case "connector.notion", "mcp.notion":
            return ["NOTION_TOKEN"]
        case "connector.linear", "mcp.linear":
            return ["LINEAR_API_KEY"]
        case "connector.agentmail", "mcp.agentmail":
            return ["AGENTMAIL_API_KEY"]
        case "model.openai":
            return ["OPENAI_API_KEY"]
        case "model.openrouter":
            return ["OPENROUTER_API_KEY"]
        case "model.eliza-cloud":
            return ["ELIZA_CLOUD_API_KEY"]
        case "model.anthropic":
            return ["ANTHROPIC_API_KEY"]
        case "model.gemini":
            return ["GEMINI_API_KEY"]
        case "model.codex":
            return ["CODEX_AUTH_TOKEN"]
        default:
            guard !candidate.id.hasPrefix("credential.") else { return [] }
            return candidate.credentialKeys ?? []
        }
    }
}
