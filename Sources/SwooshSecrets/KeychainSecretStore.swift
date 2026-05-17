// SwooshSecrets/KeychainSecretStore.swift — 0.9P Real Keychain Integration
//
// Actual macOS Keychain via Security.framework. No raw secrets in memory longer
// than necessary. Never log, audit, or debug-bundle secret values.

import Foundation
#if canImport(Security)
import Security
#endif

// ═══════════════════════════════════════════════════════════════════
// MARK: - Secret ref
// ═══════════════════════════════════════════════════════════════════

public struct SecretRef: Codable, Sendable, Hashable, CustomStringConvertible {
    public let namespace: String
    public let key: String

    public init(_ namespace: String, _ key: String) {
        self.namespace = namespace; self.key = key
    }

    public var account: String { "\(namespace).\(key)" }
    public var description: String { account } // Never prints value
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Protocol
// ═══════════════════════════════════════════════════════════════════

public protocol SecretStoring: Sendable {
    func set(_ value: String, ref: SecretRef) async throws
    func get(_ ref: SecretRef) async throws -> String
    func delete(_ ref: SecretRef) async throws
    func exists(_ ref: SecretRef) async throws -> Bool
    func listRefs(namespace: String?) async throws -> [SecretRef]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum SecretError: Error, Sendable {
    case notFound(String)
    case accessDenied(String)
    case saveFailed(String, OSStatus)
    case deleteFailed(String, OSStatus)
    case encodingFailed(String)
    case keychainUnavailable
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Real Keychain store
// ═══════════════════════════════════════════════════════════════════

#if canImport(Security)
public actor KeychainSecretStore: SecretStoring {
    private let service: String

    public init(service: String = "ai.swoosh.secrets") {
        self.service = service
    }

    public func set(_ value: String, ref: SecretRef) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretError.encodingFailed(ref.account)
        }

        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref.account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            // Add new
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw SecretError.saveFailed(ref.account, status)
        }
    }

    public func get(_ ref: SecretRef) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw SecretError.notFound(ref.account)
            }
            throw SecretError.accessDenied(ref.account)
        }
        return value
    }

    public func delete(_ ref: SecretRef) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.deleteFailed(ref.account, status)
        }
    }

    public func exists(_ ref: SecretRef) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref.account,
            kSecReturnData as String: false,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func listRefs(namespace: String?) throws -> [SecretRef] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound { return [] }
            return []
        }

        var refs: [SecretRef] = []
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            let parts = account.split(separator: ".", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let ref = SecretRef(String(parts[0]), String(parts[1]))
            if let ns = namespace {
                if ref.namespace == ns { refs.append(ref) }
            } else {
                refs.append(ref)
            }
        }
        return refs
    }
}
#endif

// ═══════════════════════════════════════════════════════════════════
// MARK: - In-memory store (for tests only)
// ═══════════════════════════════════════════════════════════════════

public actor InMemorySecretStore: SecretStoring {
    private var secrets: [String: String] = [:]

    public init() {}

    public func set(_ value: String, ref: SecretRef) { secrets[ref.account] = value }

    public func get(_ ref: SecretRef) throws -> String {
        guard let v = secrets[ref.account] else { throw SecretError.notFound(ref.account) }
        return v
    }

    public func delete(_ ref: SecretRef) { secrets.removeValue(forKey: ref.account) }

    public func exists(_ ref: SecretRef) -> Bool { secrets[ref.account] != nil }

    public func listRefs(namespace: String?) -> [SecretRef] {
        secrets.keys.compactMap { account in
            let parts = account.split(separator: ".", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let ref = SecretRef(String(parts[0]), String(parts[1]))
            if let ns = namespace { return ref.namespace == ns ? ref : nil }
            return ref
        }
    }
}
