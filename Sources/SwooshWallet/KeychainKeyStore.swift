// SwooshWallet/KeychainKeyStore.swift — Biometric-gated Keychain store
//
// Stores the secret material for each WalletAccount as a generic password
// item. Items are pinned to:
//   • kSecAttrAccessibleWhenUnlockedThisDeviceOnly  — never syncs, never
//     restorable from an iCloud backup of a different device
//   • SecAccessControl with .userPresence (biometric or passcode prompt)
//     so each load triggers Face ID / passcode confirmation
//
// We deliberately use a *generic* password item (not a kSecClassKey backed
// by Secure Enclave) because:
//   • Solana ed25519 isn't a Secure Enclave key type.
//   • EVM signing needs the raw secp256k1 scalar — Secure Enclave only
//     exposes ECDSA-P256, not secp256k1.
// The biometric ACL gives us the same UX guarantee — every read prompts
// the user — without lying about the cryptographic primitive.
//
// Account metadata (chain, address, label) is *not* stored here. It lives
// in WalletStore's UserDefaults index. Addresses are public; only secrets
// belong behind biometric auth.

import Foundation
import LocalAuthentication

public actor KeychainKeyStore {
    public enum StoreError: Error, Sendable {
        case unhandled(OSStatus)
        case duplicate
        case notFound
        case unreadable
        case accessControlFailed
    }

    public let service: String

    public init(service: String = "ai.swoosh.wallet") {
        self.service = service
    }

    public func save(secret: Data, for account: WalletAccount) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            &error
        ) else {
            throw StoreError.accessControlFailed
        }

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account.id.uuidString,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessControl as String: access,
            kSecValueData as String:        secret,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw StoreError.duplicate
        default:
            throw StoreError.unhandled(status)
        }
    }

    public func load(account: WalletAccount, prompt: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account.id.uuidString,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw StoreError.unreadable }
            return data
        case errSecItemNotFound:
            throw StoreError.notFound
        default:
            throw StoreError.unhandled(status)
        }
    }

    public func delete(account: WalletAccount) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw StoreError.unhandled(status)
        }
    }
}
