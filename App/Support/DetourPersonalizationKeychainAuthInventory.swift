// DetourPersonalizationKeychainAuthInventory.swift — personalization setup services (0.5A)

import Foundation
#if canImport(Security)
import Security
#endif

@MainActor
extension DetourPersonalizationRunner {
    func providerInheritanceSummary(logURL: URL) -> ProviderInheritanceSummary {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8),
              let line = text.split(separator: "\n").last(where: { $0.contains("imported=") }) else {
            return ProviderInheritanceSummary(discoveredProviders: [], importedProviders: [], browserStores: [])
        }
        var discovered: [String] = []
        var imported: [String] = []
        var browsers: [String] = []
        for segment in line.split(separator: " ") {
            if segment.hasPrefix("discovered=") {
                discovered = String(segment.dropFirst("discovered=".count))
                    .split(separator: ",")
                    .map(String.init)
                    .filter { $0 != "none" }
            }
            if segment.hasPrefix("imported=") {
                imported = String(segment.dropFirst("imported=".count))
                    .split(separator: ",")
                    .map(String.init)
                    .filter { $0 != "none" }
            }
            if segment.hasPrefix("browsers=") {
                browsers = String(segment.dropFirst("browsers=".count))
                    .split(separator: ",")
                    .map(String.init)
                    .filter { $0 != "none" }
            }
        }
        return ProviderInheritanceSummary(discoveredProviders: discovered, importedProviders: imported, browserStores: browsers)
    }

    func browserCookieStores(installedApps: Set<String>) -> [String] {
        let home = fileManager.homeDirectoryForCurrentUser
        var browsers = Set(
            chromiumBrowserProfiles()
                .filter { fileManager.fileExists(atPath: $0.cookiesURL.path) }
                .map(\.browser)
        )
        let stores: [(String, URL)] = [
            ("Safari", home.appending(path: "Library/Cookies/Cookies.binarycookies")),
            ("Firefox", home.appending(path: "Library/Application Support/Firefox/Profiles")),
        ]
        for (browser, url) in stores where fileManager.fileExists(atPath: url.path) {
            browsers.insert(browser)
        }
        if browsers.isEmpty && hasBrowser(installedApps) {
            return []
        }
        return browsers.sorted()
    }

    func keychainCredentialMetadata() -> [KeychainCredentialMetadata] {
        #if canImport(Security)
        let classes: [CFString] = [kSecClassGenericPassword, kSecClassInternetPassword]
        var records: [KeychainCredentialMetadata] = []
        for secClass in classes {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess else { continue }
            let items: [[String: Any]]
            if let array = result as? [[String: Any]] {
                items = array
            } else if let dictionary = result as? [String: Any] {
                items = [dictionary]
            } else {
                continue
            }
            records.append(contentsOf: items.compactMap { keychainCredentialMetadata(from: $0) })
        }
        var seen = Set<String>()
        let uniqueRecords = records
            .sorted { $0.displayLabel < $1.displayLabel }
            .filter { seen.insert("\($0.providerID):\($0.displayLabel):\($0.detail)").inserted }
        return collapsedKeychainCredentials(uniqueRecords)
        #else
        return []
        #endif
    }

    func keychainCredentialMetadata(from item: [String: Any]) -> KeychainCredentialMetadata? {
        let values = keychainMetadataValues(item)
        let metadata = values.joined(separator: " ")
        let lowercased = metadata.lowercased()
        let uppercased = metadata.uppercased()
        guard let rule = credentialMetadataRules.first(where: { rule in
            rule.terms.contains { lowercased.contains($0) }
                || rule.keys.contains { uppercased.contains($0) }
        }) else {
            return nil
        }
        let matchedKeys = rule.keys.filter { uppercased.contains($0) }
        if keychainRuleRequiresExplicitKey(rule), matchedKeys.isEmpty {
            return nil
        }
        let keys = matchedKeys.isEmpty ? Array(rule.keys.prefix(1)) : matchedKeys
        let displayLabel = keychainDisplayLabel(values: values, fallback: rule.providerName)
        let scope = keychainScope(defaultScope: rule.defaultScope, metadata: lowercased)
        return KeychainCredentialMetadata(
            providerID: rule.providerID,
            providerName: rule.providerName,
            displayLabel: displayLabel,
            detail: "metadata matched \(keys.joined(separator: ", "))",
            keys: keys,
            scope: scope,
            importableProviderID: rule.importableProviderID,
            createdAt: keychainDate(item[kSecAttrCreationDate as String]),
            modifiedAt: keychainDate(item[kSecAttrModificationDate as String]),
            recordCount: 1
        )
    }

    func keychainRuleRequiresExplicitKey(_ rule: CredentialMetadataRule) -> Bool {
        ["discord", "telegram", "slack", "notion", "linear", "agentmail"].contains(rule.providerID)
    }

    func collapsedKeychainCredentials(_ records: [KeychainCredentialMetadata]) -> [KeychainCredentialMetadata] {
        let grouped = Dictionary(grouping: records) { record in
            [
                record.providerID,
                keychainCredentialFamilyLabel(record.displayLabel).lowercased(),
                record.importableProviderID ?? "",
                record.scope.rawValue,
                record.keys.sorted().joined(separator: ",")
            ].joined(separator: "\u{1f}")
        }
        return grouped.values.map { group in
            var selected = preferredKeychainCredential(from: group)
            let totalRecords = group.reduce(0) { $0 + max($1.recordCount, 1) }
            let familyLabel = keychainCredentialFamilyLabel(selected.displayLabel)
            let keys = Set(group.flatMap(\.keys)).sorted()
            selected.displayLabel = totalRecords > 1 ? familyLabel : selected.displayLabel
            selected.keys = keys
            selected.recordCount = totalRecords
            if totalRecords > 1 {
                let hidden = totalRecords - 1
                selected.detail = "metadata matched \(keys.joined(separator: ", ")); \(hidden) stale duplicate\(hidden == 1 ? "" : "s") hidden"
            }
            return selected
        }
        .sorted {
            if $0.providerName != $1.providerName {
                return $0.providerName < $1.providerName
            }
            return $0.displayLabel < $1.displayLabel
        }
    }

    func preferredKeychainCredential(from records: [KeychainCredentialMetadata]) -> KeychainCredentialMetadata {
        records.sorted { lhs, rhs in
            let lhsCanonical = lhs.displayLabel == keychainCredentialFamilyLabel(lhs.displayLabel)
            let rhsCanonical = rhs.displayLabel == keychainCredentialFamilyLabel(rhs.displayLabel)
            if lhsCanonical != rhsCanonical {
                return lhsCanonical
            }
            let lhsDate = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
            let rhsDate = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.displayLabel < rhs.displayLabel
        }.first ?? records[0]
    }

    func keychainCredentialFamilyLabel(_ label: String) -> String {
        let lowercased = label.lowercased()
        guard lowercased.contains("credential")
            || lowercased.contains("auth")
            || lowercased.contains("safe storage")
            || lowercased.contains("token") else {
            return label
        }
        guard let dashIndex = label.lastIndex(of: "-") else { return label }
        let suffix = label[label.index(after: dashIndex)...]
        guard suffix.count >= 6,
              suffix.count <= 16,
              suffix.unicodeScalars.allSatisfy({ CharacterSet.detourPersonalizationHexDigits.contains($0) }) else {
            return label
        }
        return String(label[..<dashIndex])
    }

    func keychainDate(_ raw: Any?) -> Date? {
        raw as? Date
    }

    var credentialMetadataRules: [CredentialMetadataRule] {
        [
            CredentialMetadataRule(
                providerID: "codex",
                providerName: "Codex",
                terms: ["codex", ".codex", "chatgpt"],
                keys: ["CODEX_AUTH_TOKEN", "CODEX_API_KEY", "OPENAI_API_KEY"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "anthropic",
                providerName: "Claude",
                terms: ["claude", "anthropic"],
                keys: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "CLAUDE_CODE_API_KEY"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "gemini",
                providerName: "Gemini",
                terms: ["gemini", "google ai", "generativelanguage", "google generative ai"],
                keys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "openrouter",
                providerName: "OpenRouter",
                terms: ["openrouter", "open router"],
                keys: ["OPENROUTER_API_KEY"],
                defaultScope: .agent,
                importableProviderID: "openrouter"
            ),
            CredentialMetadataRule(
                providerID: "eliza-cloud",
                providerName: "Eliza Cloud",
                terms: ["eliza-cloud", "eliza cloud", "elizacloud", "elizaos"],
                keys: ["ELIZAOS_CLOUD_API_KEY", "ELIZA_CLOUD_API_KEY"],
                defaultScope: .agent,
                importableProviderID: "eliza-cloud"
            ),
            CredentialMetadataRule(
                providerID: "openai",
                providerName: "OpenAI",
                terms: ["openai", "open ai", "open_ai"],
                keys: ["OPENAI_API_KEY"],
                defaultScope: .agent,
                importableProviderID: "openai"
            ),
            CredentialMetadataRule(
                providerID: "github",
                providerName: "GitHub",
                terms: ["github", "github.com"],
                keys: ["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"],
                defaultScope: .user,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "discord",
                providerName: "Discord",
                terms: ["discord", "discord.com"],
                keys: ["DISCORD_API_TOKEN", "DISCORD_BOT_TOKEN"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "telegram",
                providerName: "Telegram",
                terms: ["telegram", "telegram.org", "t.me"],
                keys: ["TELEGRAM_BOT_TOKEN"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "slack",
                providerName: "Slack",
                terms: ["slack", "slack.com"],
                keys: ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN", "SLACK_TEAM_ID", "SLACK_CHANNEL_IDS"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "notion",
                providerName: "Notion",
                terms: ["notion", "notion.so"],
                keys: ["NOTION_TOKEN", "NOTION_API_KEY"],
                defaultScope: .user,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "linear",
                providerName: "Linear",
                terms: ["linear", "linear.app"],
                keys: ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"],
                defaultScope: .user,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "agentmail",
                providerName: "AgentMail",
                terms: ["agentmail", "agent mail", "agentmail.to"],
                keys: ["AGENTMAIL_API_KEY"],
                defaultScope: .agent,
                importableProviderID: nil
            ),
            CredentialMetadataRule(
                providerID: "x",
                providerName: "X",
                terms: ["twitter", "twitter.com", "x.com"],
                keys: ["X_AUTH_TOKEN", "X_CT0"],
                defaultScope: .user,
                importableProviderID: nil
            ),
        ]
    }

    func keychainMetadataValues(_ item: [String: Any]) -> [String] {
        #if canImport(Security)
        let keys = [
            kSecAttrService,
            kSecAttrAccount,
            kSecAttrLabel,
            kSecAttrDescription,
            kSecAttrComment,
            kSecAttrServer,
            kSecAttrPath,
            kSecAttrGeneric,
        ]
        return keys.compactMap { key in
            safeCredentialMetadataValue(item[key as String])
        }
        #else
        return []
        #endif
    }

    func keychainDisplayLabel(values: [String], fallback: String) -> String {
        values.first(where: { !$0.isEmpty }) ?? fallback
    }

    func keychainScope(defaultScope: DetourDelegationRole, metadata: String) -> DetourDelegationRole {
        if metadata.contains("agent") || metadata.contains("bot") || metadata.contains("detour") || metadata.contains("swoosh") {
            return .agent
        }
        if metadata.contains("user") || metadata.contains("personal") {
            return .user
        }
        return defaultScope
    }

    func safeCredentialMetadataValue(_ raw: Any?) -> String? {
        let string: String?
        if let raw = raw as? String {
            string = raw
        } else if let data = raw as? Data {
            string = String(data: data, encoding: .utf8)
        } else {
            string = nil
        }
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let lowercased = trimmed.lowercased()
        let secretPrefixes = ["sk-", "ghp_", "gho_", "github_pat_", "xox", "aiza"]
        if secretPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return nil
        }
        if trimmed.count > 96 && !trimmed.contains(" ") {
            return nil
        }
        return trimmed
    }
}
