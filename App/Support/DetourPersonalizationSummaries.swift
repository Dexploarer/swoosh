// DetourPersonalizationSummaries.swift — personalization summary and recommendation builders (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

@MainActor
extension DetourPersonalizationRunner {
    func signalSummaries(
        apps: AppInventory,
        appUsage: AppUsageInventory,
        git: GitActivityInventory,
        contacts: ContactInventory,
        messages: MessageInventory,
        auth: AuthInventory,
        agentContextSignals: Set<String>
    ) -> [String] {
        [
            "\(apps.names.count) installed apps",
            appUsage.summary,
            git.summary,
            contacts.summary,
            messages.summary,
            auth.summary,
            agentContextSignals.isEmpty ? nil : "agent-context matched \(agentContextSignals.sorted().prefix(6).joined(separator: ", "))",
        ].compactMap { $0 }.filter { !$0.isEmpty }
    }

    func accountSummaries(
        auth: AuthInventory,
        git: GitActivityInventory,
        contacts: ContactInventory
    ) -> [String] {
        var accounts: [String] = []
        for finding in auth.credentialFindings {
            let owner = finding.scope == .agent ? "agent perspective" : "user perspective"
            accounts.append("\(finding.title) - found for \(owner)")
        }
        if auth.legacy.decrypted && !auth.legacy.availableKeys.isEmpty {
            accounts.append("Legacy Detour vault: \(auth.legacy.availableKeys.count) credential candidates")
        } else if auth.legacy.vaultFound {
            accounts.append("Legacy Detour vault: \(auth.legacy.error ?? "needs unlock")")
        }
        if !auth.importedProviders.isEmpty {
            accounts.append("Model access found: \(auth.importedProviders.sorted().joined(separator: ", "))")
        }
        if auth.hasAny(["GITHUB_USER_PAT", "GITHUB_TOKEN"]) {
            let owner = auth.githubAccounts.first(where: { $0.scope == .user })?.displayLabel
            accounts.append("GitHub user account found\(owner.map { ": \($0)" } ?? "")")
        }
        if auth.hasAny(["GITHUB_AGENT_PAT"]) {
            let owner = auth.githubAccounts.first(where: { $0.scope == .agent })?.displayLabel
            accounts.append("GitHub agent account found\(owner.map { ": \($0)" } ?? "")")
        }
        if auth.hasAny(["DISCORD_API_TOKEN", "DISCORD_BOT_TOKEN"]) {
            accounts.append("Discord account access found")
        }
        if auth.hasAny(["TELEGRAM_BOT_TOKEN"]) {
            accounts.append("Telegram bot access found")
        }
        if auth.hasAny(["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"]) {
            accounts.append("Slack workspace access found")
        }
        if auth.hasAny(["NOTION_TOKEN", "NOTION_API_KEY"]) {
            accounts.append("Notion workspace access found")
        }
        if auth.hasAny(["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"]) {
            accounts.append("Linear workspace access found")
        }
        if auth.hasAny(["AGENTMAIL_API_KEY"]) {
            accounts.append("AgentMail API key found")
        }
        if auth.browserCookieStoresFound {
            accounts.append("Signed-in browser sessions found: \(auth.browserStores.joined(separator: ", "))")
        }
        if let gitUser = [git.gitUserName, git.gitUserEmail].compactMap(\.self).joinedNonEmpty(separator: " ") {
            accounts.append("Git author: \(gitUser)")
        }
        if contacts.totalCount > 0 {
            accounts.append("Contacts: \(contacts.totalCount) people")
        }
        if accounts.isEmpty {
            accounts.append("No reusable auth candidates found yet")
        }
        return accounts
    }

    func credentialFindings(
        importedProviders: Set<String>,
        browserStores: [String],
        allKeys: Set<String>,
        keychainItems: [KeychainCredentialMetadata],
        browserAccounts: [BrowserAccountFinding],
        githubAccounts: [GitHubAccountIdentity],
        git: GitActivityInventory
    ) -> [AuthCredentialFinding] {
        var findings: [AuthCredentialFinding] = []
        let githubUserOwner = githubOwnerLabel(scope: .user, git: git, keychainItems: keychainItems, githubAccounts: githubAccounts)
        let githubAgentOwner = githubOwnerLabel(scope: .agent, git: git, keychainItems: keychainItems, githubAccounts: githubAccounts)
        appendCredentialFinding(
            id: "credential.openai",
            title: "OpenAI API key",
            source: importedProviders.contains("openai") ? "Keychain/local auth" : "local config",
            providerID: "openai",
            keys: ["OPENAI_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: "openai",
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.openrouter",
            title: "OpenRouter API key",
            source: importedProviders.contains("openrouter") ? "Keychain/local auth" : "local config",
            providerID: "openrouter",
            keys: ["OPENROUTER_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: "openrouter",
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.eliza-cloud",
            title: "Eliza Cloud API key",
            source: importedProviders.contains("eliza-cloud") ? "Keychain/local auth" : "local config",
            providerID: "eliza-cloud",
            keys: ["ELIZAOS_CLOUD_API_KEY", "ELIZA_CLOUD_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: "eliza-cloud",
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.anthropic",
            title: "Claude API key",
            source: "local auth",
            providerID: nil,
            keys: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "CLAUDE_CODE_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.gemini",
            title: "Gemini API key",
            source: "local auth",
            providerID: nil,
            keys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.codex",
            title: "Codex auth",
            source: "local auth",
            providerID: nil,
            keys: ["CODEX_API_KEY", "CODEX_AUTH_TOKEN", "OPENAI_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.github-user",
            title: "GitHub user account",
            source: "local auth",
            providerID: nil,
            keys: ["GITHUB_USER_PAT", "GITHUB_TOKEN"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .user,
            ownerLabel: githubUserOwner,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.github-agent",
            title: "GitHub agent account",
            source: "local auth",
            providerID: nil,
            keys: ["GITHUB_AGENT_PAT"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            ownerLabel: githubAgentOwner,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.discord",
            title: "Discord account",
            source: "local auth",
            providerID: nil,
            keys: ["DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: allKeys.contains("DISCORD_BOT_TOKEN") ? .agent : .user,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.telegram",
            title: "Telegram account",
            source: "local auth",
            providerID: nil,
            keys: ["TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_CHATS", "TELEGRAM_API_ROOT"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.slack",
            title: "Slack workspace account",
            source: "local auth",
            providerID: nil,
            keys: ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN", "SLACK_TEAM_ID", "SLACK_CHANNEL_IDS"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.notion",
            title: "Notion workspace account",
            source: "local auth",
            providerID: nil,
            keys: ["NOTION_TOKEN", "NOTION_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .user,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.linear",
            title: "Linear workspace account",
            source: "local auth",
            providerID: nil,
            keys: ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .user,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.agentmail",
            title: "AgentMail API key",
            source: "local auth",
            providerID: nil,
            keys: ["AGENTMAIL_API_KEY"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .agent,
            to: &findings
        )
        appendCredentialFinding(
            id: "credential.x",
            title: "X account",
            source: browserStores.isEmpty ? "local auth" : "browser auth",
            providerID: nil,
            keys: ["X_AUTH_TOKEN", "X_CT0"],
            allKeys: allKeys,
            importedProviders: importedProviders,
            importedProviderID: nil,
            scope: .user,
            to: &findings
        )
        for item in keychainItems {
            findings.append(AuthCredentialFinding(
                id: "credential.keychain.\(item.providerID).\(stableIDComponent(item.displayLabel))",
                title: keychainCredentialTitle(item),
                detail: keychainCredentialDetail(item),
                source: "Keychain",
                providerID: item.importableProviderID,
                keys: item.keys,
                count: max(item.recordCount, 1),
                scope: item.scope
            ))
        }
        for account in browserAccounts {
            let accountTitle = browserAccountTitle(account)
            findings.append(AuthCredentialFinding(
                id: "credential.x.\(stableIDComponent(account.account)).\(stableIDComponent(account.browser)).\(stableIDComponent(account.profile))",
                title: accountTitle,
                detail: browserAccountDetail(account),
                source: "browser auth",
                providerID: nil,
                keys: [],
                count: 1,
                scope: account.scope
            ))
        }
        if !browserStores.isEmpty {
            for browser in browserStores where browserAccounts.allSatisfy({ $0.browser != browser }) {
                findings.append(AuthCredentialFinding(
                    id: "credential.browser-session.\(stableIDComponent(browser))",
                    title: "browser session store in \(browser)",
                    detail: "cookie store metadata found",
                    source: "browser auth",
                    providerID: nil,
                    keys: [],
                    count: 1,
                    scope: .user
                ))
            }
        }
        return findings.uniquedByID()
    }

    func appendCredentialFinding(
        id: String,
        title: String,
        source: String,
        providerID: String?,
        keys: [String],
        allKeys: Set<String>,
        importedProviders: Set<String>,
        importedProviderID: String?,
        scope: DetourDelegationRole,
        ownerLabel: String? = nil,
        to findings: inout [AuthCredentialFinding]
    ) {
        let matchedKeys = keys.filter { allKeys.contains($0) }
        let providerMatched = importedProviderID.map { importedProviders.contains($0) } ?? false
        guard providerMatched || !matchedKeys.isEmpty else { return }
        let baseDetail = matchedKeys.isEmpty
            ? "credential found"
            : "credential found in \(plainCredentialSource(source))"
        let detail = [baseDetail, ownerLabel.map { "belongs to \($0)" }]
            .compactMap(\.self)
            .joined(separator: "; ")
        findings.append(AuthCredentialFinding(
            id: id,
            title: ownerLabel.map { "\(title): \($0)" } ?? title,
            detail: detail,
            source: source,
            providerID: providerID,
            keys: matchedKeys,
            count: max(matchedKeys.count, providerMatched ? 1 : 0),
            scope: scope
        ))
    }

    func keychainCredentialTitle(_ item: KeychainCredentialMetadata) -> String {
        if item.providerID == "github", let owner = githubOwnerLabel(fromKeychainLabel: item.displayLabel) {
            return "GitHub credential in Keychain: \(owner)"
        }
        return "\(item.providerName) credential in Keychain: \(item.displayLabel)"
    }

    func keychainCredentialDetail(_ item: KeychainCredentialMetadata) -> String {
        guard item.providerID == "github",
              let owner = githubOwnerLabel(fromKeychainLabel: item.displayLabel) else {
            return item.detail
        }
        return "\(item.detail); belongs to \(owner)"
    }

    func plainCredentialSource(_ source: String) -> String {
        switch source {
        case "local config":
            "local setup"
        case "local auth":
            "local sign-in"
        case "browser auth":
            "the browser"
        case "Keychain/local auth":
            "Keychain"
        default:
            source
        }
    }

}
