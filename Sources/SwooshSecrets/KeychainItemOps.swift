// SwooshSecrets/KeychainItemOps.swift — 0.9S Shared Security.framework helpers
//
// Low-level Keychain `kSecClassGenericPassword` operations. Used by both
// `KeychainSecretStore` (SwooshSecrets, typed `SecretRef` API) and by
// `KeychainCredentialStore` (SwooshConfig, legacy `key+service` API).
// One implementation of the SecItem dance so a fix in either path
// covers both.

import Foundation
#if canImport(Security)
import Security
#endif

#if canImport(Security)
public enum KeychainItemOps {
    /// Set (or overwrite) a generic-password item. Tries update first;
    /// falls back to add with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    public static func set(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainItemError.saveFailed(account: account, status: status)
        }
    }

    /// Read the value bytes for a generic-password item. Returns `nil`
    /// when the item is not found; throws on any other error.
    public static func get(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainItemError.readFailed(account: account, status: status)
        }
    }

    /// Delete a generic-password item. Treats "not found" as success.
    public static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainItemError.deleteFailed(account: account, status: status)
        }
    }

    /// Test whether an item exists without copying its value out.
    public static func exists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// List all account strings stored under `service`. Returns an
    /// empty array when none are present.
    public static func listAccounts(service: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else { return [] }
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainItemError.listFailed(service: service, status: status)
        }
    }
}

public enum KeychainItemError: Error, Sendable {
    case saveFailed(account: String, status: OSStatus)
    case readFailed(account: String, status: OSStatus)
    case deleteFailed(account: String, status: OSStatus)
    case listFailed(service: String, status: OSStatus)
}
#endif
