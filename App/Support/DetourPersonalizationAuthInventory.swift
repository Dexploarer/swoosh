// DetourPersonalizationAuthInventory.swift — local auth inventory discovery (0.5A)

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
    func authInventory(
        consent: DetourCredentialInheritanceConsent,
        installedApps: Set<String>,
        userName: String,
        git: GitActivityInventory,
        providerLogURL: URL
    ) -> AuthInventory {
        let providerSummary = providerInheritanceSummary(logURL: providerLogURL)
        let legacy = DetourLegacyVaultImporter().importCredentials(
            allowed: consent.keychainCredentials,
            allowUserInteraction: consent.keychainCredentials,
            storeValues: false
        )
        let knownKeys = [
            "OPENAI_API_KEY",
            "OPENROUTER_API_KEY",
            "ELIZAOS_CLOUD_API_KEY",
            "ELIZA_CLOUD_API_KEY",
            "ANTHROPIC_API_KEY",
            "CLAUDE_API_KEY",
            "CLAUDE_CODE_API_KEY",
            "GEMINI_API_KEY",
            "GOOGLE_API_KEY",
            "GOOGLE_GENERATIVE_AI_API_KEY",
            "CODEX_API_KEY",
            "CODEX_AUTH_TOKEN",
            "GITHUB_TOKEN",
            "GITHUB_USER_PAT",
            "GITHUB_AGENT_PAT",
            "DISCORD_API_TOKEN",
            "DISCORD_BOT_TOKEN",
            "TELEGRAM_BOT_TOKEN",
            "TELEGRAM_ALLOWED_CHATS",
            "TELEGRAM_API_ROOT",
            "SLACK_BOT_TOKEN",
            "SLACK_API_TOKEN",
            "SLACK_TEAM_ID",
            "SLACK_CHANNEL_IDS",
            "NOTION_TOKEN",
            "NOTION_API_KEY",
            "LINEAR_API_KEY",
            "LINEAR_ACCESS_TOKEN",
            "AGENTMAIL_API_KEY",
            "X_AUTH_TOKEN",
            "X_CT0",
        ]
        let keychainItems = consent.keychainCredentials ? keychainCredentialMetadata() : []
        let mentionedKeys = credentialKeyMentions(keys: knownKeys)
        let inheritedKeys = Set(legacy.availableKeys).union(legacy.importedKeys)
        let keychainKeys = Set(keychainItems.flatMap(\.keys))
        let allKeys = mentionedKeys.union(inheritedKeys).union(keychainKeys)
        let githubAccounts = githubAccountIdentities(git: git, keychainItems: keychainItems)
        let browserStores = consent.browserCookies ? browserCookieStores(installedApps: installedApps) : []
        let browserAccounts = consent.browserCookies ? browserXAccounts(identityHints: identityHints(userName: userName, git: git)) : []
        let xStatus: String
        if allKeys.isSuperset(of: ["X_AUTH_TOKEN", "X_CT0"]) {
            xStatus = "X_AUTH_TOKEN + X_CT0 candidate found"
        } else if !browserAccounts.isEmpty {
            xStatus = browserAccounts
                .map(browserAccountSummary)
                .joined(separator: ", ")
        } else if !browserStores.isEmpty {
            xStatus = "x.com cookie auth candidate"
        } else {
            xStatus = "needs X_AUTH_TOKEN + X_CT0"
        }
        var imported = Set(providerSummary.discoveredProviders).union(providerSummary.importedProviders)
        if inheritedKeys.contains("OPENAI_API_KEY") {
            imported.insert("openai")
        }
        if inheritedKeys.contains("OPENROUTER_API_KEY") {
            imported.insert("openrouter")
        }
        if inheritedKeys.contains("ELIZAOS_CLOUD_API_KEY") || inheritedKeys.contains("ELIZA_CLOUD_API_KEY") {
            imported.insert("eliza-cloud")
        }
        let summary: String
        if !keychainItems.isEmpty || !browserAccounts.isEmpty {
            let rawKeychainCount = keychainItems.reduce(0) { $0 + max($1.recordCount, 1) }
            let hiddenKeychainCount = max(0, rawKeychainCount - keychainItems.count)
            let keychainSummary: String?
            if keychainItems.isEmpty {
                keychainSummary = nil
            } else if hiddenKeychainCount > 0 {
                keychainSummary = "\(keychainItems.count) Keychain credential groups, \(hiddenKeychainCount) stale duplicates hidden"
            } else {
                keychainSummary = "\(keychainItems.count) Keychain credential records"
            }
            let browserSummary = browserAccounts.isEmpty ? nil : "\(browserAccounts.count) browser account sessions"
            summary = [keychainSummary, browserSummary].compactMap(\.self).joined(separator: ", ")
        } else if legacy.decrypted && !legacy.availableKeys.isEmpty {
            summary = "Legacy Detour auth found: \(legacy.availableKeys.prefix(5).joined(separator: ", "))"
        } else if legacy.vaultFound {
            summary = "Legacy Detour vault found, \(legacy.error ?? "no reusable keys imported")"
        } else if !imported.isEmpty {
            summary = "Model auth found: \(imported.sorted().joined(separator: ", "))"
        } else if !mentionedKeys.isEmpty {
            summary = "Auth keys mentioned: \(mentionedKeys.sorted().prefix(5).joined(separator: ", "))"
        } else if !browserStores.isEmpty {
            summary = "Browser auth stores: \(browserStores.joined(separator: ", "))"
        } else {
            summary = "No reusable auth candidates found"
        }
        return AuthInventory(
            importedProviders: imported,
            browserStores: browserStores,
            mentionedKeys: mentionedKeys,
            keychainKeys: keychainKeys,
            githubAccounts: githubAccounts,
            legacy: legacy,
            credentialFindings: credentialFindings(
                importedProviders: imported,
                browserStores: browserStores,
                allKeys: allKeys,
                keychainItems: keychainItems,
                browserAccounts: browserAccounts,
                githubAccounts: githubAccounts,
                git: git
            ),
            xCookieStatus: xStatus,
            summary: summary
        )
    }

}
