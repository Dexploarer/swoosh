// SwooshSecrets/KeychainScavenger.swift — 0.9S Third-party keychain credential discovery
//
// Reads compatible provider credentials stored by other apps in the macOS Keychain.

import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum KeychainScavenger {

    /// Known third-party keychain item locations.
    struct KeychainSource {
        let provider: KnownProvider
        let service: String
        let account: String?
        let kind: DiscoveredCredential.CredentialKind
    }

    static let sources: [KeychainSource] = []

    #if canImport(Security)
    public static func scan(allowUserInteraction: Bool = false) -> [DiscoveredCredential] {
        var found: [KnownProvider: DiscoveredCredential] = [:]

        for source in sources {
            if allowUserInteraction {
                if let value = readValue(
                    service: source.service,
                    account: source.account,
                    allowUserInteraction: true
                ) {
                    let token = extractToken(from: value, provider: source.provider)
                    found[source.provider] = DiscoveredCredential(
                        provider: source.provider,
                        source: .keychainThirdParty,
                        kind: source.kind,
                        value: token
                    )
                }
            } else {
                switch preflight(service: source.service, account: source.account) {
                case .allowed:
                    if let value = readValue(
                        service: source.service,
                        account: source.account,
                        allowUserInteraction: false
                    ) {
                        let token = extractToken(from: value, provider: source.provider)
                        found[source.provider] = DiscoveredCredential(
                            provider: source.provider,
                            source: .keychainThirdParty,
                            kind: source.kind,
                            value: token
                        )
                    }
                case .interactionRequired, .notFound, .failure:
                    continue
                }
            }
        }

        for credential in scanGenericProviderItems(
            allowUserInteraction: allowUserInteraction
        ) where found[credential.provider] == nil {
            found[credential.provider] = credential
        }

        return Array(found.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    // ── Preflight check (no UI) ──

    enum PreflightOutcome {
        case allowed
        case interactionRequired
        case notFound
        case failure(Int)
    }

    /// Check if a keychain item can be read without prompting the user.
    /// Uses LAContext.interactionNotAllowed + kSecUseAuthenticationUIFail.
    static func preflight(service: String, account: String?) -> PreflightOutcome {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]

        applyNoUIPolicy(to: &query)

        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:              return .allowed
        case errSecItemNotFound:         return .notFound
        case errSecInteractionNotAllowed: return .interactionRequired
        default:                          return .failure(Int(status))
        }
    }

    /// Read the actual secret value from keychain (only call after preflight succeeds).
    static func readValue(service: String, account: String?, allowUserInteraction: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        applyInteractionPolicy(to: &query, allowUserInteraction: allowUserInteraction)

        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func scanGenericProviderItems(allowUserInteraction: Bool) -> [DiscoveredCredential] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        applyInteractionPolicy(to: &query, allowUserInteraction: allowUserInteraction)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return [] }

        let items: [[String: Any]]
        if let array = result as? [[String: Any]] {
            items = array
        } else if let dictionary = result as? [String: Any] {
            items = [dictionary]
        } else {
            return []
        }

        var found: [KnownProvider: DiscoveredCredential] = [:]
        for item in items {
            guard let credential = credential(from: item),
                  found[credential.provider] == nil else {
                continue
            }
            found[credential.provider] = credential
        }
        return Array(found.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    static func credential(from item: [String: Any]) -> DiscoveredCredential? {
        let metadata = [
            stringAttribute(kSecAttrService, item),
            stringAttribute(kSecAttrAccount, item),
            stringAttribute(kSecAttrLabel, item),
            stringAttribute(kSecAttrDescription, item),
            stringAttribute(kSecAttrComment, item),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        guard let provider = provider(from: metadata),
              let data = item[kSecValueData as String] as? Data,
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        let raw = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return nil
        }
        let token = extractToken(from: raw, provider: provider)
        guard looksLikeAPIKey(token, provider: provider) else { return nil }
        return DiscoveredCredential(
            provider: provider,
            source: .keychainThirdParty,
            kind: .apiKey,
            value: token
        )
    }

    static func provider(from metadata: String) -> KnownProvider? {
        let metadata = metadata.lowercased()
        if containsAny(["anthropic", "claude"], in: metadata) {
            return .anthropic
        }
        if containsAny(["gemini", "google ai", "generative ai"], in: metadata) {
            return .gemini
        }
        if containsAny(["codex"], in: metadata) {
            return .codex
        }
        if containsAny(["openrouter", "open router"], in: metadata) {
            return .openRouter
        }
        if containsAny(["eliza-cloud", "eliza cloud", "elizacloud"], in: metadata) {
            return .elizaCloud
        }
        if containsAny(["openai", "open ai", "open_ai"], in: metadata) {
            return .openAI
        }
        return nil
    }

    static func looksLikeAPIKey(_ value: String, provider: KnownProvider) -> Bool {
        switch provider {
        case .openAI:
            return value.hasPrefix("sk-")
        case .openRouter:
            return value.hasPrefix("sk-or-") || value.hasPrefix("sk-")
        case .elizaCloud:
            return value.hasPrefix("sk-") || value.count >= 24
        case .anthropic:
            return value.hasPrefix("sk-ant-") || value.hasPrefix("sk-")
        case .gemini:
            return value.hasPrefix("AIza") || value.count >= 32
        case .codex:
            return value.count >= 24
        }
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func stringAttribute(_ key: CFString, _ item: [String: Any]) -> String? {
        item[key as String] as? String
    }

    /// Apply the no-UI-prompt policy.
    /// Uses LAContext.interactionNotAllowed plus the runtime-resolved
    /// kSecUseAuthenticationUIFail constant (avoids deprecation warnings).
    private static func applyNoUIPolicy(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = resolvedUIFailPolicy as CFString
    }

    private static func applyInteractionPolicy(to query: inout [String: Any], allowUserInteraction: Bool) {
        guard !allowUserInteraction else { return }
        applyNoUIPolicy(to: &query)
    }

    /// Resolve kSecUseAuthenticationUIFail at runtime to avoid deprecation.
    private static let resolvedUIFailPolicy: String = {
        let path = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(path, RTLD_NOW) else { return "u_AuthUIF" }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else { return "u_AuthUIF" }
        let ptr = symbol.assumingMemoryBound(to: CFString?.self)
        return (ptr.pointee as String?) ?? "u_AuthUIF"
    }()

    /// Extract a usable token from a raw keychain value.
    /// Some apps store JSON blobs; others store plain tokens.
    static func extractToken(from raw: String, provider: KnownProvider) -> String {
        // Try JSON first
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["token", "access_token", "oauth_token", "api_key",
                        "apiKey", "accessToken", "oauthToken"]
            for key in keys {
                if let val = obj[key] as? String, !val.isEmpty { return val }
            }
            // Nested: {"credentials": {"token": "..."}}
            for (_, nested) in obj {
                if let dict = nested as? [String: Any] {
                    for key in keys {
                        if let val = dict[key] as? String, !val.isEmpty { return val }
                    }
                }
            }
        }
        // Plain string token
        return raw
    }

    #else
    // Non-macOS: no keychain scanning
    public static func scan(allowUserInteraction: Bool = false) -> [DiscoveredCredential] { [] }
    #endif
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Browser cookie safe-storage labels
// ═══════════════════════════════════════════════════════════════════

extension KeychainScavenger {
    /// Chromium browser Safe Storage keychain labels.
    /// Used to check if cookie decryption is possible without prompts.
    public static let browserSafeStorageLabels: [(browser: String, service: String, account: String)] = [
        ("Chrome",         "Chrome Safe Storage",             "Chrome"),
        ("Brave",          "Brave Safe Storage",              "Brave"),
        ("Edge",           "Microsoft Edge Safe Storage",     "Microsoft Edge"),
        ("Arc",            "Arc Safe Storage",                "Arc"),
        ("Vivaldi",        "Vivaldi Safe Storage",            "Vivaldi"),
        ("Opera",          "Opera Safe Storage",              "Opera"),
        ("Chromium",       "Chromium Safe Storage",           "Chromium"),
    ]

    /// Check which browsers have accessible Safe Storage keys (for cookie decryption).
    #if canImport(Security)
    public static func accessibleBrowsers() -> [String] {
        browserSafeStorageLabels.compactMap { (browser, service, account) in
            switch preflight(service: service, account: account) {
            case .allowed: return browser
            default:       return nil
            }
        }
    }
    #else
    public static func accessibleBrowsers() -> [String] { [] }
    #endif
}
