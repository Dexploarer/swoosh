// DetourPersonalizationRelationshipSummaries.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func relationshipCandidates(
        contacts: ContactInventory,
        messages: MessageInventory
    ) -> [DetourRelationshipCandidate] {
        var candidates: [DetourRelationshipCandidate] = []
        for name in contacts.names.prefix(30) {
            candidates.append(DetourRelationshipCandidate(
                id: "contact.\(stableIDComponent(name))",
                displayName: name,
                source: "Contacts",
                tags: ["contact", "user-acquaintance"],
                messageCount: nil,
                lastSeenDescription: nil,
                selected: true
            ))
        }
        for signal in messages.relationships.prefix(40) {
            candidates.append(DetourRelationshipCandidate(
                id: "imessage.\(stableIDComponent(signal.handle))",
                displayName: signal.handle,
                source: "iMessage",
                tags: ["imessage", "message-contact"],
                messageCount: signal.messageCount,
                lastSeenDescription: messageDateDescription(raw: signal.lastDateRaw),
                selected: true
            ))
        }
        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.displayName.lowercased()).inserted
        }
    }

    func delegationProfiles(
        userName: String,
        agentName: String,
        auth: AuthInventory,
        git: GitActivityInventory
    ) -> [DetourDelegationProfile] {
        let userAccounts = [
            auth.hasAny(["GITHUB_USER_PAT", "GITHUB_TOKEN"])
                ? "GitHub \(auth.githubAccounts.first(where: { $0.scope == .user })?.displayLabel ?? "user")"
                : nil,
            git.gitUserEmail.map { "Git author \($0)" },
            auth.browserCookieStoresFound ? "browser sessions" : nil,
        ].compactMap(\.self)
        let agentAccounts = [
            auth.hasAny(["GITHUB_AGENT_PAT"])
                ? "GitHub \(auth.githubAccounts.first(where: { $0.scope == .agent })?.displayLabel ?? "agent")"
                : nil,
            auth.hasAny(["DISCORD_BOT_TOKEN"]) ? "Discord bot" : nil,
            auth.hasAny(["TELEGRAM_BOT_TOKEN"]) ? "Telegram bot" : nil,
        ].compactMap(\.self)
        return [
            DetourDelegationProfile(
                role: .user,
                displayName: userName.isEmpty ? "User" : userName,
                accountLabels: userAccounts,
                context: "acts with personal voice, personal inboxes, and user-owned sessions"
            ),
            DetourDelegationProfile(
                role: .agent,
                displayName: agentName,
                accountLabels: agentAccounts,
                context: "acts with agent accounts, automation tokens, and tool-specific identity"
            ),
        ]
    }

    func questionRecommendations(
        agentName: String,
        installedApps: Set<String>,
        auth: AuthInventory,
        contacts: ContactInventory
    ) -> [String] {
        var questions = [
            "Which goals should \(agentName) protect time for first?",
            "Which accounts should \(agentName) use as you, and which as itself?",
            "Which people or projects matter most?"
        ]
        if hasBrowser(installedApps) || auth.browserCookieStoresFound {
            questions.append("Should \(agentName) use browser history and cookies for setup?")
        }
        if contacts.totalCount > 0 {
            questions.append("Which contacts should \(agentName) treat as high priority?")
        }
        return Array(questions.prefix(5))
    }
}
