// SwooshConfig/Credentials.swift — 0.9S Keychain-first credential store
//
// Default: Keychain on macOS/iOS (delegates to SwooshSecrets.KeychainItemOps)
// Fallback: encrypted .env for Linux/CI/headless
// "Collect context, not secrets."

import Foundation
import Security
import SwooshSecrets

// MARK: - Credential store protocol

public protocol CredentialStore: Sendable {
    func get(key: String, service: String) async throws -> String?
    func set(key: String, value: String, service: String) async throws
    func delete(key: String, service: String) async throws
    func listKeys(service: String) async throws -> [String]
}

// MARK: - Keychain credential store (macOS/iOS)
//
// Thin façade over `SwooshSecrets.KeychainItemOps`. Keeps the legacy
// `key+service` API surface intact (the setup graph and CLI chat path
// depend on it) but routes every SecItem call through the same code
// path as `SwooshSecrets.KeychainSecretStore`.

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let defaultService: String

    public init(service: String = "ai.swoosh.agent") {
        self.defaultService = service
    }

    public func get(key: String, service: String) async throws -> String? {
        do {
            guard let data = try KeychainItemOps.get(service: service, account: key) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch let KeychainItemError.readFailed(_, status) {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func set(key: String, value: String, service: String) async throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailure
        }
        do {
            try KeychainItemOps.set(data, service: service, account: key)
        } catch let KeychainItemError.saveFailed(_, status) {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func delete(key: String, service: String) async throws {
        do {
            try KeychainItemOps.delete(service: service, account: key)
        } catch let KeychainItemError.deleteFailed(_, status) {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func listKeys(service: String) async throws -> [String] {
        do {
            return try KeychainItemOps.listAccounts(service: service)
        } catch let KeychainItemError.listFailed(_, status) {
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
    private let envFile: URL

    /// - Parameters:
    ///   - prefix: Environment-variable name prefix (e.g. `SWOOSH_`).
    ///   - directory: Directory holding the persistent `.env` file. Defaults to
    ///     `~/.swoosh`. Injectable so tests (and embedders) can isolate state.
    public init(prefix: String = "SWOOSH_", directory: URL? = nil) {
        self.envPrefix = prefix
        let baseDir = directory ??
            swooshHomeDirectoryForCurrentUser().appending(path: ".swoosh")
        self.envFile = baseDir.appending(path: ".env")
    }

    /// The environment-variable name for a logical credential key.
    private func envKey(for key: String) -> String {
        "\(envPrefix)\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
    }

    /// Encode a value so it is safe to store on a single `.env` line.
    /// The `.env` format is line-oriented, so any control characters that
    /// would break the line structure are backslash-escaped.
    private func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Reverse of `escape` — decode a stored `.env` value.
    private func unescape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\" else { out.append(ch); continue }
            switch iterator.next() {
            case "n": out += "\n"
            case "r": out += "\r"
            case "t": out += "\t"
            case "\\": out += "\\"
            case let other?: out.append("\\"); out.append(other)
            case nil: out.append("\\")
            }
        }
        return out
    }

    /// Parse the `.env` file into ordered `KEY=VALUE` pairs (values decoded).
    private func readEnvFile() -> [(key: String, value: String)] {
        guard let existing = try? String(contentsOf: envFile, encoding: .utf8) else { return [] }
        return existing
            .components(separatedBy: "\n")
            .compactMap { line in
                guard let eq = line.firstIndex(of: "=") else { return nil }
                let name = String(line[line.startIndex..<eq])
                guard !name.isEmpty else { return nil }
                let value = String(line[line.index(after: eq)...])
                return (name, unescape(value))
            }
    }

    /// Serialize ordered `KEY=VALUE` pairs into `.env` file text.
    private func serialize(_ entries: [(key: String, value: String)]) -> String {
        entries.map { "\($0.key)=\(escape($0.value))" }.joined(separator: "\n")
    }

    public func get(key: String, service: String) async throws -> String? {
        let name = envKey(for: key)
        // The persistent `.env` file is the canonical store written by `set`;
        // it wins over the process environment. Fall back to process env so
        // values injected by the launching shell remain visible.
        if let entry = readEnvFile().last(where: { $0.key == name }) {
            return entry.value
        }
        return ProcessInfo.processInfo.environment[name]
    }

    public func set(key: String, value: String, service: String) async throws {
        // Environment variables are read-only at runtime;
        // write to the `.env` file for persistence.
        let name = envKey(for: key)

        var entries = readEnvFile().filter { $0.key != name }
        entries.append((key: name, value: value))

        let dir = envFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try serialize(entries).write(to: envFile, atomically: true, encoding: .utf8)

        // Restrict permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envFile.path)
    }

    public func delete(key: String, service: String) async throws {
        // Remove from `.env` file
        let name = envKey(for: key)

        let entries = readEnvFile()
        guard entries.contains(where: { $0.key == name }) else { return }
        let remaining = entries.filter { $0.key != name }
        try serialize(remaining).write(to: envFile, atomically: true, encoding: .utf8)
    }

    public func listKeys(service: String) async throws -> [String] {
        // Keys from the persistent `.env` file plus any matching the prefix in
        // the process environment, de-duplicated.
        var names = Set<String>()
        for entry in readEnvFile() where entry.key.hasPrefix(envPrefix) {
            names.insert(entry.key)
        }
        for envName in ProcessInfo.processInfo.environment.keys where envName.hasPrefix(envPrefix) {
            names.insert(envName)
        }
        return names.map { String($0.dropFirst(envPrefix.count)) }
    }
}
