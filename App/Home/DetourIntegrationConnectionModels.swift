// DetourIntegrationConnectionModels.swift — all-app connection catalog state (0.5A)

import Foundation

enum DetourIntegrationConnectionState: String, Equatable {
    case verified
    case selected
    case needsSetup
    case detected
    case available

    var label: String {
        switch self {
        case .verified: "Live"
        case .selected: "Selected"
        case .needsSetup: "Needs setup"
        case .detected: "Found"
        case .available: "Available"
        }
    }
}

enum DetourIntegrationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case chat = "Chat"
    case social = "Social"
    case productivity = "Work"
    case platform = "Dev"
    case tools = "Tools"

    var id: String { rawValue }

    func includes(_ category: DetourIntegrationCategory) -> Bool {
        switch self {
        case .all:
            return true
        case .chat:
            return category == .chat
        case .social:
            return category == .social
        case .productivity:
            return category == .productivity
        case .platform:
            return category == .platform
        case .tools:
            return category == .tools
        }
    }
}

struct DetourIntegrationConnection: Identifiable, Equatable {
    var id: String { integration.candidateID }
    var integration: DetourOpenHumanIntegration
    var state: DetourIntegrationConnectionState
    var scope: DetourDelegationRole
    var hasCandidate: Bool
    var detail: String

    var selected: Bool {
        state == .verified || state == .selected || state == .needsSetup
    }

    var adapterID: String? {
        integration.chatAdapterID
    }

    var configurationURL: URL? {
        integration.configurationURL
    }

    var canConnectDirectly: Bool {
        adapterID != nil
    }

    var connectorHealthID: String {
        integration.connectorHealthID
    }
}

struct DetourIntegrationConnectionSnapshot: Equatable {
    var items: [DetourIntegrationConnection]

    var total: Int { items.count }
    var detected: Int { items.filter { $0.state == .detected }.count }
    var selected: Int { items.filter(\.selected).count }
    var needsSetup: Int { items.filter { $0.state == .needsSetup }.count }
    var verified: Int { items.filter { $0.state == .verified }.count }
}

@MainActor
extension OnboardingStore {
    var integrationConnectionSnapshot: DetourIntegrationConnectionSnapshot {
        DetourIntegrationConnectionBuilder.build(
            integrations: DetourOpenHumanIntegrationCatalog.integrations,
            candidates: personalizationResult?.setupCandidates ?? [],
            approvedIDs: approvedSetupCandidateIDs,
            deniedIDs: deniedSetupCandidateIDs,
            scopes: setupCandidateScopes,
            report: setupApplicationReport
        )
    }

    func connectIntegration(_ integration: DetourOpenHumanIntegration) {
        let candidate = catalogCandidate(for: integration)
        ensureCatalogCandidate(candidate)
        var approved = approvedSetupCandidateIDs
        var denied = deniedSetupCandidateIDs
        var scopes = setupCandidateScopes
        approved.insert(candidate.id)
        denied.remove(candidate.id)
        scopes[candidate.id] = candidate.scope
        for related in relatedCredentialCandidates(for: candidate, integration: integration) {
            approved.insert(related.id)
            denied.remove(related.id)
            scopes[related.id] = related.scope
        }
        approvedSetupCandidateIDs = approved
        deniedSetupCandidateIDs = denied
        setupCandidateScopes = scopes
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    func setIntegrationScope(_ integration: DetourOpenHumanIntegration, role: DetourDelegationRole) {
        let candidate = catalogCandidate(for: integration)
        ensureCatalogCandidate(candidate)
        var approved = approvedSetupCandidateIDs
        var denied = deniedSetupCandidateIDs
        var scopes = setupCandidateScopes
        scopes[candidate.id] = role
        approved.insert(candidate.id)
        denied.remove(candidate.id)
        setupCandidateScopes = scopes
        approvedSetupCandidateIDs = approved
        deniedSetupCandidateIDs = denied
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    private func ensureCatalogCandidate(_ candidate: DetourSetupCandidate) {
        if personalizationResult == nil {
            personalizationResult = DetourPersonalizationScanResult(
                summary: "",
                signals: [],
                accessItems: [],
                accounts: [],
                goals: [],
                schedules: [],
                plugins: [],
                questions: [],
                setupCandidates: [candidate],
                relationshipCandidates: [],
                delegationProfiles: [],
                completedAt: Date(),
                scoutSucceeded: false,
                agentContextSucceeded: false,
                credentialInheritanceSucceeded: false
            )
            return
        }
        guard var result = personalizationResult,
              !result.setupCandidates.contains(where: { $0.id == candidate.id }) else { return }
        result.setupCandidates.append(candidate)
        personalizationResult = result
    }

    private func relatedCredentialCandidates(
        for candidate: DetourSetupCandidate,
        integration: DetourOpenHumanIntegration
    ) -> [DetourSetupCandidate] {
        guard let candidates = personalizationResult?.setupCandidates else { return [] }
        let keys = Set(candidate.credentialKeys ?? [])
        if !keys.isEmpty {
            return candidates.filter { item in
                item.category == .account || item.id.hasPrefix("credential.")
            }
            .filter { item in
                guard let itemKeys = item.credentialKeys else { return false }
                return !keys.isDisjoint(with: itemKeys)
            }
        }
        guard integration.slug == "twitter" else { return [] }
        return candidates.filter { item in
            item.selected && (item.id.hasPrefix("credential.x.") || item.id == "credential.x")
        }
    }

    private func catalogCandidate(for integration: DetourOpenHumanIntegration) -> DetourSetupCandidate {
        let existing = personalizationResult?.setupCandidates.first { candidate in
            DetourIntegrationConnectionBuilder.aliases(for: integration).contains(candidate.id)
        }
        if let existing {
            return existing
        }
        return DetourSetupCandidate(
            id: integration.candidateID,
            category: .connector,
            title: integration.name,
            detail: "\(integration.category.rawValue) app available through OAuth.",
            source: "App catalog",
            recommended: false,
            selected: false,
            prompt: "Connect \(integration.name)?",
            foundCount: nil,
            credentialProviderID: nil,
            credentialKeys: nil,
            scope: integration.defaultScope
        )
    }
}

private enum DetourIntegrationConnectionBuilder {
    static func build(
        integrations: [DetourOpenHumanIntegration],
        candidates: [DetourSetupCandidate],
        approvedIDs: Set<String>,
        deniedIDs: Set<String>,
        scopes: [String: DetourDelegationRole],
        report: DetourSetupApplicationReport?
    ) -> DetourIntegrationConnectionSnapshot {
        let items = integrations.map { integration in
            let ids = integration.setupCandidateAliases
            let candidate = candidates.first { ids.contains($0.id) }
            let selected = ids.contains { approvedIDs.contains($0) }
            let detected = candidate?.recommended == true || candidate?.selected == true
            let state = state(
                integration: integration,
                selected: selected,
                detected: detected,
                denied: ids.allSatisfy { deniedIDs.contains($0) },
                report: report
            )
            return DetourIntegrationConnection(
                integration: integration,
                state: state,
                scope: scopes[candidate?.id ?? integration.candidateID] ?? candidate?.scope ?? integration.defaultScope,
                hasCandidate: candidate != nil,
                detail: detail(for: state, category: integration.category)
            )
        }
        return DetourIntegrationConnectionSnapshot(items: items.sorted(by: sort))
    }

    static func aliases(for integration: DetourOpenHumanIntegration) -> [String] {
        integration.setupCandidateAliases
    }

    private static func state(
        integration: DetourOpenHumanIntegration,
        selected: Bool,
        detected: Bool,
        denied: Bool,
        report: DetourSetupApplicationReport?
    ) -> DetourIntegrationConnectionState {
        if selected, let reportState = reportState(for: integration, report: report) {
            switch reportState {
            case .connected:
                return .verified
            case .failed, .needsAction:
                return .needsSetup
            case .checking, .enabled:
                return .selected
            case .removed:
                return .available
            }
        }
        if selected { return .selected }
        if detected && !denied { return .detected }
        return .available
    }

    private static func reportState(
        for integration: DetourOpenHumanIntegration,
        report: DetourSetupApplicationReport?
    ) -> DetourSetupApplicationState? {
        let keys = aliases(for: integration).map { $0.replacingOccurrences(of: "connector.", with: "") }
        return report?.items.first { item in
            let value = "\(item.id) \(item.title)".lowercased()
            return keys.contains { value.contains($0) } || value.contains(integration.name.lowercased())
        }?.state
    }

    private static func detail(
        for state: DetourIntegrationConnectionState,
        category: DetourIntegrationCategory
    ) -> String {
        switch state {
        case .verified:
            return "Ready"
        case .selected:
            return "Ready to test"
        case .needsSetup:
            return "Fix setup"
        case .detected:
            return "Found here"
        case .available:
            return category.rawValue
        }
    }

    private static func sort(_ lhs: DetourIntegrationConnection, _ rhs: DetourIntegrationConnection) -> Bool {
        let left = "\(order(lhs.state))|\(lhs.integration.category.rawValue)|\(lhs.integration.name)"
        let right = "\(order(rhs.state))|\(rhs.integration.category.rawValue)|\(rhs.integration.name)"
        return left < right
    }

    private static func order(_ state: DetourIntegrationConnectionState) -> Int {
        switch state {
        case .needsSetup: 0
        case .verified: 1
        case .selected: 2
        case .detected: 3
        case .available: 4
        }
    }
}

extension DetourOpenHumanIntegration {
    var setupCandidateAliases: [String] {
        switch slug {
        case "twitter":
            return ["connector.twitter", "connector.x"]
        case "googledrive":
            return ["connector.google-drive", "connector.googledrive"]
        default:
            return [candidateID]
        }
    }

    var connectorHealthID: String {
        switch slug {
        case "twitter", "facebook", "instagram", "reddit":
            return "x"
        case "microsoft_teams":
            return "teams"
        case "whatsapp":
            return "whatsapp"
        default:
            return slug
        }
    }

    var defaultScope: DetourDelegationRole {
        switch category {
        case .chat, .social:
            return .user
        case .productivity, .platform, .tools:
            return .agent
        }
    }

    var chatAdapterID: String? {
        switch slug {
        case "discord", "telegram", "github", "linear", "slack", "webex", "mattermost":
            return slug
        case "twitter", "facebook", "instagram", "reddit":
            return "zernioSocial"
        case "microsoft_teams":
            return "teams"
        case "whatsapp":
            return "whatsApp"
        default:
            return nil
        }
    }

    var configurationURL: URL? {
        let value: String?
        switch slug {
        case "discord", "discordbot":
            value = "https://discord.com/developers/applications"
        case "telegram":
            value = "https://t.me/BotFather"
        case "github":
            value = "https://github.com/settings/tokens"
        case "slack", "slackbot":
            value = "https://api.slack.com/apps"
        case "linear":
            value = "https://linear.app/settings/api"
        case "notion":
            value = "https://www.notion.so/profile/integrations"
        case "twitter":
            value = "https://developer.x.com/en/portal/dashboard"
        case "gmail", "googlecalendar", "googledocs", "googledrive", "googlesheets", "googleslides":
            value = "https://console.cloud.google.com/apis/credentials"
        default:
            value = nil
        }
        return value.flatMap(URL.init(string:))
    }
}
