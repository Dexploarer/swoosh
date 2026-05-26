// DetourOnboardingSetupConfiguration.swift — Detour onboarding setup configuration actions (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
#if canImport(Security)
import Security
#endif

enum DetourOnboardingSetupConfigurationError: LocalizedError {
    case invalidAgentMailAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidAgentMailAPIKey:
            "That does not look like a working AgentMail API key. Use the key from AgentMail sign-up or the AgentMail console, not an inbox, account, or user ID."
        }
    }
}

extension DetourOnboardingContentView {
    func openPermissionSettings(for publicID: String) {
        guard let route = store.setupInsightPermissionRoute(publicID: publicID) else { return }
        switch route {
        case .credentialConfiguration:
            configureCredentials(for: publicID)
        case .fullDiskAccess:
            openFullDiskAccessSettings()
        case .contacts:
            requestContactsAccess()
        }
    }

    func configureCredentials(for publicID: String) {
        guard let configuration = store.setupInsightConfiguration(publicID: publicID) else { return }
        let alert = NSAlert()
        alert.messageText = "Configure \(configuration.title)"
        alert.informativeText = "Detour saves these values in your Mac Keychain and checks them through Apply setup."
        let fields = configurationFields(keys: configuration.keys)
        alert.accessoryView = configurationForm(fields: fields)
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let values = try configurationValues(fields: fields)
            guard !values.isEmpty else { return }
            for (key, value) in values {
                try saveSecret(value, accounts: secretAccounts(for: key))
            }
            store.setSetupInsightCandidateApproval(publicID: publicID, approved: true)
            if let role = configuration.scope {
                store.setSetupInsightCandidateScope(publicID: publicID, role: role)
            }
            reloadPersonalizationViews()
        } catch {
            showConfigurationError(error.localizedDescription)
        }
    }

    func configurationValues(fields: [(String, NSTextField)]) throws -> [(String, String)] {
        try fields.compactMap { pair -> (String, String)? in
            let key = pair.0
            let value = pair.1.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if key == "AGENTMAIL_API_KEY" {
                try validateAgentMailAPIKey(value)
            }
            return (key, value)
        }
    }

    func validateAgentMailAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24,
              !trimmed.contains("@"),
              !trimmed.localizedCaseInsensitiveContains("inbox"),
              !trimmed.localizedCaseInsensitiveContains("account") else {
            throw DetourOnboardingSetupConfigurationError.invalidAgentMailAPIKey
        }
    }

    func removeSetupCredentialContext(for publicID: String) {
        do {
            let keys = store.setupInsightConfiguredCredentialKeys(publicID: publicID)
            for account in keys.flatMap(secretAccounts(for:)) {
                try deleteSecret(account: account)
            }
            store.removeSetupInsightCandidateFromContext(publicID: publicID)
            reloadPersonalizationViews()
        } catch {
            showConfigurationError("Detour could not remove this setup item.")
        }
    }

    func configurationFields(keys: [String]) -> [(String, NSTextField)] {
        keys.map { key in
            let field: NSTextField = secretLikeKey(key) ? NSSecureTextField() : NSTextField()
            field.placeholderString = configurationLabel(for: key)
            field.isBordered = true
            return (key, field)
        }
    }

    func configurationForm(fields: [(String, NSTextField)]) -> NSView {
        let rowHeight: CGFloat = 38
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: CGFloat(fields.count) * rowHeight))
        for (index, pair) in fields.enumerated() {
            let label = NSTextField(labelWithString: configurationLabel(for: pair.0))
            label.frame = NSRect(x: 0, y: CGFloat(fields.count - index - 1) * rowHeight + 7, width: 132, height: 20)
            pair.1.frame = NSRect(x: 142, y: CGFloat(fields.count - index - 1) * rowHeight + 2, width: 278, height: 28)
            view.addSubview(label)
            view.addSubview(pair.1)
        }
        return view
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        store.prepareForPermissionRestart()
        reloadPersonalizationViews()
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        NSWorkspace.shared.open(url)
        showPermissionRestartPrompt()
    }

    func requestContactsAccess() {
        #if canImport(Contacts)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            openContactsSettings()
            return
        }
        CNContactStore().requestAccess(for: .contacts) { [weak self] granted, _ in
            DispatchQueue.main.async {
                granted ? self?.runPersonalizationScanFromUI() : self?.openContactsSettings()
            }
        }
        #else
        showConfigurationError("Contacts are not available on this Mac.")
        #endif
    }

    func openContactsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func saveSecret(_ value: String, accounts: [String]) throws {
        #if canImport(Security)
        guard let data = value.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError)
        }
        for account in accounts {
            try saveSecretData(data, account: account)
        }
        #else
        throw NSError(domain: NSOSStatusErrorDomain, code: -4)
        #endif
    }

    func deleteSecret(account: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.swoosh.secrets",
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        #else
        throw NSError(domain: NSOSStatusErrorDomain, code: -4)
        #endif
    }

    func secretAccounts(for key: String) -> [String] {
        switch key {
        case "OPENAI_API_KEY":
            return ["openai.api_key", "legacy.OPENAI_API_KEY"]
        case "OPENROUTER_API_KEY":
            return ["openrouter.api_key", "legacy.OPENROUTER_API_KEY"]
        case "ELIZAOS_CLOUD_API_KEY", "ELIZA_CLOUD_API_KEY":
            return ["eliza-cloud.api_key", "legacy.\(key)"]
        case "DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN":
            return ["discord.bot_token", "legacy.\(key)"]
        case "TELEGRAM_BOT_TOKEN":
            return ["telegram.bot_token", "legacy.TELEGRAM_BOT_TOKEN"]
        case "GITHUB_TOKEN", "GITHUB_USER_PAT":
            return ["github.user_pat", "legacy.\(key)"]
        case "SLACK_BOT_TOKEN", "SLACK_API_TOKEN":
            return ["slack.bot_token", "legacy.\(key)"]
        case "SLACK_TEAM_ID":
            return ["slack.team_id", "legacy.SLACK_TEAM_ID"]
        case "NOTION_TOKEN", "NOTION_API_KEY":
            return ["notion.token", "legacy.\(key)"]
        case "LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN":
            return ["linear.api_key", "legacy.\(key)"]
        case "AGENTMAIL_API_KEY":
            return ["agentmail.api_key", "legacy.AGENTMAIL_API_KEY"]
        case "ANTHROPIC_API_KEY":
            return ["anthropic.api_key", "legacy.ANTHROPIC_API_KEY"]
        case "GEMINI_API_KEY":
            return ["gemini.api_key", "legacy.GEMINI_API_KEY"]
        case "CODEX_AUTH_TOKEN":
            return ["codex.auth_token", "legacy.CODEX_AUTH_TOKEN"]
        default:
            return ["legacy.\(key)"]
        }
    }

    func configurationLabel(for key: String) -> String {
        switch key {
        case "DISCORD_BOT_TOKEN": return "Discord bot token"
        case "TELEGRAM_BOT_TOKEN": return "Telegram bot token"
        case "GITHUB_USER_PAT": return "GitHub token"
        case "SLACK_BOT_TOKEN": return "Slack bot token"
        case "SLACK_TEAM_ID": return "Slack team ID"
        case "NOTION_TOKEN": return "Notion token"
        case "LINEAR_API_KEY": return "Linear API key"
        case "AGENTMAIL_API_KEY": return "AgentMail API key from sign-up or console"
        case "OPENAI_API_KEY": return "OpenAI API key"
        case "OPENROUTER_API_KEY": return "OpenRouter API key"
        case "ELIZA_CLOUD_API_KEY": return "Eliza Cloud key"
        case "ANTHROPIC_API_KEY": return "Claude API key"
        case "GEMINI_API_KEY": return "Gemini API key"
        case "CODEX_AUTH_TOKEN": return "Codex auth token"
        default: return key
        }
    }

    func secretLikeKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return upper.contains("TOKEN") || upper.contains("KEY") || upper.contains("SECRET") || upper.contains("PAT")
    }

    #if canImport(Security)
    func saveSecretData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.swoosh.secrets",
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    #endif

    func showConfigurationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
