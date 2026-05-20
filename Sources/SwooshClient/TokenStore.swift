// SwooshClient/TokenStore.swift — Keychain-backed bearer-token storage
//
// Stores the API bearer token used to talk to swooshd. The same module
// works on macOS and iOS — both have Security.framework Keychain APIs.
// The host URL preference goes through UserDefaults instead since it
// isn't sensitive and benefits from being app-group-shareable on iOS.

import Foundation
#if canImport(Security)
import Security
#endif

/// Keychain-backed storage for the swooshd bearer token.
public enum TokenStore {
    public static let service: String = "ai.swoosh.client"
    public static let account: String = "api_token"

    /// Persist a token, replacing any previous one.
    public static func save(_ token: String) throws {
        #if canImport(Security)
        // Wipe any existing entry first so SecItemAdd can't collide.
        SecItemDelete(baseQuery() as CFDictionary)

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = Data(token.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError.keychain(status: status)
        }
        #else
        throw TokenStoreError.unsupported
        #endif
    }

    /// Read the stored token, if one exists.
    public static func load() -> String? {
        #if canImport(Security)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    /// Wipe the stored token. No-op if nothing is stored.
    public static func delete() {
        #if canImport(Security)
        SecItemDelete(baseQuery() as CFDictionary)
        #endif
    }

    #if canImport(Security)
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
    #endif
}

public enum TokenStoreError: Error, Sendable, LocalizedError {
    case keychain(status: OSStatus)
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)"
        case .unsupported:
            return "Keychain is not available on this platform"
        }
    }
}

/// User-defaults storage for the swooshd base URL — not sensitive.
public enum HostStore {
    public static let defaultsKey: String = "ai.swoosh.client.host"

    public static var current: URL? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let url = URL(string: raw) else { return nil }
            return url
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }
}
