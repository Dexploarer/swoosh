// DetourPersonalizationConnectorSetup.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func connectorSetupItem(
        _ candidate: DetourSetupCandidate,
        approved: [DetourSetupCandidate]
    ) -> DetourSetupApplicationItem {
        switch candidate.id {
        case "connector.discord":
            return credentialBackedConnectorItem(
                candidate,
                approved: approved,
                keys: ["DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN"],
                ready: "Discord is enabled. Detour found a Discord credential and will verify the live connector during Apply setup.",
                missing: "Discord is enabled, but it still needs a Discord bot token before it can send or read messages."
            )
        case "connector.telegram":
            return credentialBackedConnectorItem(
                candidate,
                approved: approved,
                keys: ["TELEGRAM_BOT_TOKEN"],
                ready: "Telegram is enabled. Detour found a bot token and will verify the live connector during Apply setup.",
                missing: "Telegram is enabled, but it still needs a bot token before it can send or read messages."
            )
        case "connector.github":
            return credentialBackedConnectorItem(
                candidate,
                approved: approved,
                keys: ["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"],
                ready: "GitHub is enabled. Detour found a GitHub credential and will verify it through the live agent path during Apply setup.",
                missing: "GitHub is enabled, but it still needs a GitHub account or token before it can check issues and PRs."
            )
        case "connector.agentmail":
            return credentialBackedConnectorItem(
                candidate,
                approved: approved,
                keys: ["AGENTMAIL_API_KEY"],
                ready: "AgentMail is enabled. Detour found an API key and will verify the inbox through the live agent path during Apply setup.",
                missing: "AgentMail is enabled, but it still needs an API key or agent sign-up with email verification before the agent can send and receive email."
            )
        case "connector.x":
            let hasXAccount = approved.contains { $0.id.hasPrefix("credential.x.") || $0.id == "credential.x" }
            return DetourSetupApplicationItem(
                id: "setup.\(candidate.id)",
                title: candidate.title,
                detail: hasXAccount
                    ? "X is enabled. Detour found a signed-in browser account for social context."
                    : "X is enabled, but it still needs a signed-in browser account before it can use social context.",
                state: hasXAccount ? .enabled : .needsAction
            )
        case "connector.imessage":
            let detail = candidate.detail.lowercased()
            let ready = detail.contains("readable") || detail.contains("relationships")
            let present = detail.contains("present") || detail.contains("chat.db")
            return DetourSetupApplicationItem(
                id: "setup.\(candidate.id)",
                title: candidate.title,
                detail: ready
                    ? "iMessage is enabled. Detour can read local message context."
                    : present
                        ? "iMessage is enabled, but macOS may still need Full Disk Access before Detour can read message history."
                        : "iMessage is enabled, but no readable message database was found yet.",
                state: ready ? .enabled : .needsAction
            )
        default:
            return DetourSetupApplicationItem(
                id: "setup.\(candidate.id)",
                title: candidate.title,
                detail: "\(candidate.title) is enabled. Detour saved the connector choice and will finish any service-specific setup when credentials are available.",
                state: .enabled
            )
        }
    }

    func installSelectedConnectorPlugins(
        candidates: [DetourSetupCandidate],
        approvedCandidateIDs: Set<String>
    ) -> [DetourSetupApplicationItem] {
        let approved = candidates.filter { approvedCandidateIDs.contains($0.id) }
        let specs = approved
            .filter { $0.category == .connector }
            .map { connectorPluginSpec(candidateID: $0.id) }
            .sorted { $0.displayName < $1.displayName }
        guard !specs.isEmpty else { return [] }
        let runtimeTools = liveRuntimeToolNames()
        return specs.map { verifyConnectorRuntime($0, approved: approved, runtimeTools: runtimeTools) }
    }
}
