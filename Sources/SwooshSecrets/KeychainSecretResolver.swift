// SwooshSecrets/KeychainSecretResolver.swift — SecretResolving over the Keychain — 0.9R
//
// Adapts a `SecretStoring` (canonically `KeychainSecretStore`) to the
// `SwooshTools.SecretResolving` protocol that crypto tools depend on.
//
// Tools pass a single-string ref (e.g. "hyperliquid.mainnet.pk" or
// "evm_rpc_1"). This adapter parses the ref into a `SecretRef`:
//   - "namespace.key"  → SecretRef(namespace, key)
//   - "name"           → SecretRef(defaultNamespace, name)
//
// Hard rule: the resolved value is returned to the caller and never
// logged, audited, or persisted by this adapter.

import Foundation
import SwooshTools

/// Resolves tool secret refs against a `SecretStoring` backend.
public struct KeychainSecretResolver: SecretResolving {
    private let store: any SecretStoring
    private let defaultNamespace: String

    public init(store: any SecretStoring, defaultNamespace: String = "tool") {
        self.store = store
        self.defaultNamespace = defaultNamespace
    }

    public func resolve(ref: String) async throws -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidInput("Empty secret reference")
        }
        let secretRef = Self.parse(trimmed, defaultNamespace: defaultNamespace)
        do {
            return try await store.get(secretRef)
        } catch let error as SecretError {
            switch error {
            case .notFound(let account):
                throw ToolError.executionFailed("Secret '\(account)' is not configured in the Keychain")
            case .accessDenied(let account):
                throw ToolError.executionFailed("Access to secret '\(account)' was denied")
            default:
                throw ToolError.executionFailed("Could not resolve secret '\(trimmed)'")
            }
        }
    }

    /// Parse a string ref into a `SecretRef`. The first `.`-separated
    /// component is the namespace; the remainder is the key. A ref with
    /// no `.` uses `defaultNamespace`.
    static func parse(_ ref: String, defaultNamespace: String) -> SecretRef {
        guard let dotIndex = ref.firstIndex(of: ".") else {
            return SecretRef(defaultNamespace, ref)
        }
        let namespace = String(ref[ref.startIndex..<dotIndex])
        let key = String(ref[ref.index(after: dotIndex)...])
        if namespace.isEmpty || key.isEmpty {
            return SecretRef(defaultNamespace, ref)
        }
        return SecretRef(namespace, key)
    }
}
