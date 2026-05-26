// DetourLegacyVaultImporter.swift — legacy Detour vault credential import (0.5A)

import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct DetourLegacyCredentialImportResult: Codable, Equatable {
    var vaultFound: Bool
    var decrypted: Bool
    var importedKeys: [String]
    var availableKeys: [String]
    var error: String?
}

struct DetourLegacyVaultImporter {
    private let fileManager = FileManager.default

    func importCredentials(
        allowed: Bool,
        allowUserInteraction: Bool = false,
        allowedKeys: Set<String>? = nil,
        storeValues: Bool = true
    ) -> DetourLegacyCredentialImportResult {
        guard allowed else {
            return DetourLegacyCredentialImportResult(
                vaultFound: false,
                decrypted: false,
                importedKeys: [],
                availableKeys: [],
                error: "not allowed"
            )
        }

        guard let vaultURL = legacyVaultURL(), fileManager.fileExists(atPath: vaultURL.path) else {
            return DetourLegacyCredentialImportResult(
                vaultFound: false,
                decrypted: false,
                importedKeys: [],
                availableKeys: [],
                error: nil
            )
        }

        do {
            let store = try JSONDecoder().decode(LegacyVaultStore.self, from: Data(contentsOf: vaultURL))
            guard let key = legacyMasterKey(for: vaultURL, allowUserInteraction: allowUserInteraction) else {
                return DetourLegacyCredentialImportResult(
                    vaultFound: true,
                    decrypted: false,
                    importedKeys: [],
                    availableKeys: Array(store.entries.keys).sorted(),
                    error: "legacy master key unavailable"
                )
            }

            var imported: [String] = []
            var available: [String] = []
            for legacyKey in legacyCredentialKeys {
                guard allowedKeys?.contains(legacyKey) ?? true else { continue }
                guard let entry = store.entries[legacyKey] else { continue }
                available.append(legacyKey)
                guard let value = try value(for: entry, key: legacyKey, masterKey: key),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                if storeValues {
                    for account in swooshAccounts(for: legacyKey) {
                        try setKeychainValue(value, service: "ai.swoosh.secrets", account: account)
                    }
                    imported.append(legacyKey)
                }
            }

            return DetourLegacyCredentialImportResult(
                vaultFound: true,
                decrypted: true,
                importedKeys: imported.sorted(),
                availableKeys: available.sorted(),
                error: nil
            )
        } catch {
            return DetourLegacyCredentialImportResult(
                vaultFound: true,
                decrypted: false,
                importedKeys: [],
                availableKeys: [],
                error: error.localizedDescription
            )
        }
    }

    private func legacyVaultURL() -> URL? {
        if let stateDir = ProcessInfo.processInfo.environment["ELIZA_STATE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stateDir.isEmpty {
            return URL(fileURLWithPath: stateDir).appending(path: "vault.json")
        }
        let namespace = ProcessInfo.processInfo.environment["ELIZA_NAMESPACE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = ".\(namespace?.isEmpty == false ? namespace! : "eliza")"
        return fileManager.homeDirectoryForCurrentUser.appending(path: folder).appending(path: "vault.json")
    }

    private func legacyMasterKey(for vaultURL: URL, allowUserInteraction: Bool) -> SymmetricKey? {
        let services = ["eliza", "milady"]
        let keys = services.compactMap { service in
            readLegacyMasterKey(
                service: service,
                account: "vault.masterKey",
                allowUserInteraction: allowUserInteraction
            )
        }
        return keys.first { probe(masterKey: $0, vaultURL: vaultURL) }
    }

    private func readLegacyMasterKey(
        service: String,
        account: String,
        allowUserInteraction: Bool
    ) -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let encoded = String(data: data, encoding: .utf8),
              let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
              decoded.count == 32 else {
            return nil
        }
        return SymmetricKey(data: decoded)
    }

    private func probe(masterKey: SymmetricKey, vaultURL: URL) -> Bool {
        guard let store = try? JSONDecoder().decode(LegacyVaultStore.self, from: Data(contentsOf: vaultURL)) else {
            return false
        }
        guard let secret = store.entries.first(where: { $0.value.kind == "secret" }) else {
            return true
        }
        return (try? value(for: secret.value, key: secret.key, masterKey: masterKey)) != nil
    }

    private func value(for entry: LegacyVaultEntry, key: String, masterKey: SymmetricKey) throws -> String? {
        switch entry.kind {
        case "value":
            return entry.value
        case "secret":
            guard let ciphertext = entry.ciphertext else { return nil }
            return try decrypt(ciphertext: ciphertext, aad: key, masterKey: masterKey)
        default:
            return nil
        }
    }

    private func decrypt(ciphertext: String, aad: String, masterKey: SymmetricKey) throws -> String {
        let parts = ciphertext.split(separator: ":").map(String.init)
        guard parts.count == 4,
              parts[0] == "v1",
              let nonceData = Data(base64Encoded: parts[1]),
              let tagData = Data(base64Encoded: parts[2]),
              let cipherData = Data(base64Encoded: parts[3]) else {
            throw DetourLegacyVaultError.malformedCiphertext
        }
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: cipherData,
            tag: tagData
        )
        let data = try AES.GCM.open(sealedBox, using: masterKey, authenticating: Data(aad.utf8))
        guard let value = String(data: data, encoding: .utf8) else {
            throw DetourLegacyVaultError.invalidPlaintext
        }
        return value
    }

    private func setKeychainValue(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw DetourLegacyVaultError.keychainWriteFailed(addStatus)
        }
    }

    private func swooshAccounts(for legacyKey: String) -> [String] {
        switch legacyKey {
        case "OPENAI_API_KEY":
            ["openai.api_key", "legacy.OPENAI_API_KEY"]
        case "OPENROUTER_API_KEY":
            ["openrouter.api_key", "legacy.OPENROUTER_API_KEY"]
        case "ELIZAOS_CLOUD_API_KEY", "ELIZA_CLOUD_API_KEY":
            ["eliza-cloud.api_key", "legacy.\(legacyKey)"]
        case "DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN":
            ["discord.bot_token", "legacy.\(legacyKey)"]
        case "TELEGRAM_BOT_TOKEN":
            ["telegram.bot_token", "legacy.TELEGRAM_BOT_TOKEN"]
        case "GITHUB_TOKEN", "GITHUB_USER_PAT":
            ["github.user_pat", "legacy.\(legacyKey)"]
        case "GITHUB_AGENT_PAT":
            ["github.agent_pat", "legacy.GITHUB_AGENT_PAT"]
        case "SLACK_BOT_TOKEN", "SLACK_API_TOKEN":
            ["slack.bot_token", "legacy.\(legacyKey)"]
        case "SLACK_TEAM_ID":
            ["slack.team_id", "legacy.SLACK_TEAM_ID"]
        case "SLACK_CHANNEL_IDS":
            ["slack.channel_ids", "legacy.SLACK_CHANNEL_IDS"]
        case "NOTION_TOKEN", "NOTION_API_KEY":
            ["notion.token", "legacy.\(legacyKey)"]
        case "LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN":
            ["linear.api_key", "legacy.\(legacyKey)"]
        case "AGENTMAIL_API_KEY":
            ["agentmail.api_key", "legacy.AGENTMAIL_API_KEY"]
        case "X_AUTH_TOKEN":
            ["x.auth_token", "legacy.X_AUTH_TOKEN"]
        case "X_CT0":
            ["x.ct0", "legacy.X_CT0"]
        default:
            ["legacy.\(legacyKey)"]
        }
    }

    private var legacyCredentialKeys: [String] {
        [
            "OPENAI_API_KEY",
            "OPENROUTER_API_KEY",
            "ELIZAOS_CLOUD_API_KEY",
            "ELIZA_CLOUD_API_KEY",
            "DISCORD_API_TOKEN",
            "DISCORD_BOT_TOKEN",
            "TELEGRAM_BOT_TOKEN",
            "GITHUB_TOKEN",
            "GITHUB_USER_PAT",
            "GITHUB_AGENT_PAT",
            "X_AUTH_TOKEN",
            "X_CT0",
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
            "IMESSAGE_ENABLED",
            "DISCORD_AUTO_REPLY",
            "TELEGRAM_AUTO_REPLY",
            "CONTINUOUS_IMPROVEMENT_ENABLED",
            "CONTINUOUS_IMPROVEMENT_INTERVAL_MS",
        ]
    }
}

private struct LegacyVaultStore: Decodable {
    var entries: [String: LegacyVaultEntry]
}

private struct LegacyVaultEntry: Decodable {
    var kind: String
    var value: String?
    var ciphertext: String?
}

private enum DetourLegacyVaultError: Error {
    case malformedCiphertext
    case invalidPlaintext
    case keychainWriteFailed(OSStatus)
}
