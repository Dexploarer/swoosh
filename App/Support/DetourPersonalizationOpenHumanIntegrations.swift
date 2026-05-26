// DetourPersonalizationOpenHumanIntegrations.swift — OpenHuman integration candidates (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func addOpenHumanIntegrationCandidates(
        installedApps: Set<String>,
        auth: AuthInventory,
        to candidates: inout [DetourSetupCandidate]
    ) {
        for integration in DetourOpenHumanIntegrationCatalog.integrations {
            let keys = openHumanCredentialKeys(integration.slug)
            let detected = openHumanIntegrationDetected(
                integration,
                installedApps: installedApps,
                auth: auth,
                keys: keys
            )
            candidates.append(candidate(
                id: integration.candidateID,
                category: .connector,
                title: integration.name,
                detail: openHumanIntegrationDetail(integration, detected: detected),
                source: "OpenHuman Composio catalog",
                recommended: detected,
                prompt: "Connect \(integration.name)?",
                credentialKeys: keys.isEmpty ? nil : keys,
                scope: openHumanIntegrationScope(integration)
            ))
        }
    }

    private func openHumanIntegrationDetected(
        _ integration: DetourOpenHumanIntegration,
        installedApps: Set<String>,
        auth: AuthInventory,
        keys: [String]
    ) -> Bool {
        if !keys.isEmpty, auth.hasAny(keys) {
            return true
        }
        if integration.slug == "twitter", auth.hasXBrowserSession {
            return true
        }
        let name = integration.name.lowercased()
        let slug = integration.slug.replacingOccurrences(of: "_", with: " ")
        return installedApps.contains { app in
            app.contains(name) || app.contains(slug)
        }
    }

    private func openHumanIntegrationDetail(
        _ integration: DetourOpenHumanIntegration,
        detected: Bool
    ) -> String {
        if detected {
            return "\(integration.category.rawValue) app found here"
        }
        return "\(integration.category.rawValue) app available through OAuth"
    }

    private func openHumanCredentialKeys(_ slug: String) -> [String] {
        switch slug {
        case "discord", "discordbot":
            return ["DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN"]
        case "github":
            return ["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"]
        case "gitlab":
            return ["GITLAB_TOKEN"]
        case "hugging_face":
            return ["HF_TOKEN", "HUGGINGFACE_TOKEN"]
        case "linear":
            return ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"]
        case "notion":
            return ["NOTION_TOKEN", "NOTION_API_KEY"]
        case "openai":
            return ["OPENAI_API_KEY"]
        case "slack", "slackbot":
            return ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"]
        case "telegram":
            return ["TELEGRAM_BOT_TOKEN"]
        case "twitter":
            return ["X_AUTH_TOKEN", "X_CT0"]
        case "vercel":
            return ["VERCEL_TOKEN"]
        default:
            return []
        }
    }

    private func openHumanIntegrationScope(_ integration: DetourOpenHumanIntegration) -> DetourDelegationRole {
        switch integration.category {
        case .chat, .social:
            return .user
        case .platform, .productivity, .tools:
            return .agent
        }
    }
}

private extension AuthInventory {
    var hasXBrowserSession: Bool {
        credentialFindings.contains { finding in
            finding.id.hasPrefix("credential.x.") || finding.id == "credential.x"
        } || xCookieStatus.localizedCaseInsensitiveContains("x.com")
            || xCookieStatus.localizedCaseInsensitiveContains("x session")
    }
}
