// SwooshSecrets/KeychainAPIKeyProvider.swift — 0.9R Keychain-bound key provider
//
// Closes the loop for cloud providers — instead of each call site wiring
// its own keychain reader, pass `KeychainAPIKeyProvider.for(...)` and the
// provider self-sources its key on every call (hot-swappable).
//
// Convention: keys live under service `ai.swoosh.secrets`, account is
// `ai.swoosh.<providerID>` (e.g. "ai.swoosh.openai", "ai.swoosh.fal").
// One key per provider, shared across voice + capability routers — entering
// an OpenAI key in any picker unlocks every OpenAI-backed surface.

import Foundation
import Security

public enum KeychainAPIKeyProvider {

    /// The Keychain service used for all Swoosh-provider keys.
    public static let service: String = "ai.swoosh.secrets"

    /// Closure factory bound to one provider id. The returned closure
    /// reads from Keychain on demand and throws `MissingAPIKey` if absent.
    public static func `for`(_ providerID: String) -> @Sendable () async throws -> String {
        return {
            try await read(providerID: providerID)
        }
    }

    /// Direct read — synchronous Keychain query wrapped in async for
    /// uniformity. Throws on absence.
    public static func read(providerID: String) async throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "ai.swoosh.\(providerID)",
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            throw MissingAPIKey(providerID: providerID)
        }
        return value
    }

    /// Write or replace a key. Returns true on success.
    @discardableResult
    public static func write(providerID: String, value: String) -> Bool {
        let account = "ai.swoosh.\(providerID)"
        // Delete any existing entry first so we don't get errSecDuplicateItem.
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addAttrs: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   Data(value.utf8),
        ]
        return SecItemAdd(addAttrs as CFDictionary, nil) == errSecSuccess
    }

    /// Delete the stored key. Idempotent.
    public static func delete(providerID: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "ai.swoosh.\(providerID)",
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// True when a non-empty key is present.
    public static func isConfigured(providerID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "ai.swoosh.\(providerID)",
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, !data.isEmpty
        else { return false }
        return true
    }
}

public struct MissingAPIKey: Error, CustomStringConvertible {
    public let providerID: String
    public var description: String {
        "No API key for \(providerID). Add it in Settings → Voice → Provider keys."
    }
}
