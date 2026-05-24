// SwooshSecrets/KeychainScavenger.swift — 0.9S Third-party keychain credential discovery
//
// Reads credentials stored by other apps in the macOS Keychain WITHOUT
// triggering UI prompts. Uses LAContext.interactionNotAllowed + the
// kSecUseAuthenticationUIFail technique from CodexBar's KeychainNoUIQuery.
//
// This only works for items where the user has already granted access
// (e.g. via Keychain Access.app "Always Allow") or where the item has
// no ACL restrictions.

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
    public static func scan() -> [DiscoveredCredential] {
        var results: [DiscoveredCredential] = []

        for source in sources {
            switch preflight(service: source.service, account: source.account) {
            case .allowed:
                if let value = readValue(service: source.service, account: source.account) {
                    // For OAuth JSON blobs, try to extract the token
                    let token = extractToken(from: value, provider: source.provider)
                    results.append(DiscoveredCredential(
                        provider: source.provider,
                        source: .keychainThirdParty,
                        kind: source.kind,
                        value: token
                    ))
                }
            case .interactionRequired, .notFound, .failure:
                continue
            }
        }

        return results
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
    static func readValue(service: String, account: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        applyNoUIPolicy(to: &query)

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

    /// Apply the no-UI-prompt policy.
    /// Uses LAContext.interactionNotAllowed plus the runtime-resolved
    /// kSecUseAuthenticationUIFail constant (avoids deprecation warnings).
    private static func applyNoUIPolicy(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = resolvedUIFailPolicy as CFString
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
    public static func scan() -> [DiscoveredCredential] { [] }
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
