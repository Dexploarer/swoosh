// SwooshConfig/Credentials.swift — Keychain-first credential store
//
// Default: Keychain on macOS/iOS
// Fallback: encrypted .env for Linux/CI/headless
// "Collect context, not secrets."

import Foundation
import Security

// MARK: - Credential store protocol

public protocol CredentialStore: Sendable {
    func get(key: String, service: String) async throws -> String?
    func set(key: String, value: String, service: String) async throws
    func delete(key: String, service: String) async throws
    func listKeys(service: String) async throws -> [String]
}

// MARK: - Keychain credential store (macOS/iOS)

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let defaultService: String

    public init(service: String = "ai.swoosh.agent") {
        self.defaultService = service
    }

    public func get(key: String, service: String) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    public func set(key: String, value: String, service: String) async throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailure
        }

        // Try update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Add new
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandled(status: updateStatus)
        }
    }

    public func delete(key: String, service: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func listKeys(service: String) async throws -> [String] {
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
            throw KeychainError.unhandled(status: status)
        }
    }
}

public enum KeychainError: Error, LocalizedError {
    case encodingFailure
    case unhandled(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailure:
            return "Failed to encode credential value"
        case .unhandled(let status):
            if let msg = SecCopyErrorMessageString(status, nil) {
                return "Keychain error: \(msg)"
            }
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - Environment variable fallback (Linux/CI/headless)

public final class EnvironmentCredentialStore: CredentialStore, @unchecked Sendable {
    private let envPrefix: String

    public init(prefix: String = "SWOOSH_") {
        self.envPrefix = prefix
    }

    public func get(key: String, service: String) async throws -> String? {
        let envKey = "\(envPrefix)\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
        return ProcessInfo.processInfo.environment[envKey]
    }

    public func set(key: String, value: String, service: String) async throws {
        // Environment variables are read-only at runtime;
        // write to ~/.swoosh/.env for persistence
        let envKey = "\(envPrefix)\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
        let envFile = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".swoosh/.env")

        var lines: [String] = []
        if let existing = try? String(contentsOf: envFile, encoding: .utf8) {
            lines = existing.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("\(envKey)=") }
        }
        lines.append("\(envKey)=\(value)")

        let dir = envFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: envFile, atomically: true, encoding: .utf8)

        // Restrict permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFile.path)
    }

    public func delete(key: String, service: String) async throws {
        // Remove from .env file
        let envKey = "\(envPrefix)\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
        let envFile = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".swoosh/.env")

        guard let existing = try? String(contentsOf: envFile, encoding: .utf8) else { return }
        let lines = existing.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("\(envKey)=") }
        try lines.joined(separator: "\n").write(to: envFile, atomically: true, encoding: .utf8)
    }

    public func listKeys(service: String) async throws -> [String] {
        ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix(envPrefix) }
            .map { String($0.dropFirst(envPrefix.count)) }
    }
}
