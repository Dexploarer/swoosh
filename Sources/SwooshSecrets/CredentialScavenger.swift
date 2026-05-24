// SwooshSecrets/CredentialScavenger.swift — 0.9S Multi-source credential discovery
//
// Inspired by CodexBar's provider credential resolution chain.
// Discovers API keys, OAuth tokens, and session credentials from:
//   1. macOS Keychain (third-party app items, silently)
//   2. Environment variables
//   3. Known config files on disk
//   4. Browser cookies (Chromium Safe Storage decryption)
//
// Never logs or stores raw secret values. Returns opaque DiscoveredCredential
// structs that can be imported into SwooshSecrets' own keychain namespace.

import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// ═══════════════════════════════════════════════════════════════════
// MARK: - Public types
// ═══════════════════════════════════════════════════════════════════

/// Where a credential was found.
public enum CredentialSource: String, Sendable, Codable, CaseIterable {
    case keychainThirdParty   // Another app's keychain item
    case environment          // Shell environment variable
    case configFile           // JSON/TOML file on disk
    case browserCookie        // Chromium/Safari cookie DB
    case swooshKeychain       // Already in our own keychain
}

/// A provider we know how to scavenge credentials for.
public enum KnownProvider: String, Sendable, CaseIterable, Codable {
    case openAI       = "openai"
    case openRouter   = "openrouter"
    case elizaCloud   = "eliza-cloud"

    public var displayName: String {
        switch self {
        case .openAI:     return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .elizaCloud: return "Eliza Cloud"
        }
    }
}

/// A credential discovered from an external source.
public struct DiscoveredCredential: Sendable {
    public let provider: KnownProvider
    public let source: CredentialSource
    public let credentialKind: CredentialKind
    /// The raw secret value. Held transiently — import into Swoosh keychain and discard.
    public let value: String

    public enum CredentialKind: String, Sendable {
        case apiKey
        case oauthToken
        case sessionCookie
        case bearerToken
    }

    public init(provider: KnownProvider, source: CredentialSource,
                kind: CredentialKind, value: String) {
        self.provider = provider
        self.source = source
        self.credentialKind = kind
        self.value = value
    }

    /// The SecretRef to use when importing into Swoosh's own keychain.
    public var swooshRef: SecretRef {
        SecretRef(provider.rawValue, "api_key")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Credential Scavenger (orchestrator)
// ═══════════════════════════════════════════════════════════════════

public enum CredentialScavenger {

    /// Discover all available credentials across all sources.
    /// Returns one credential per provider (first-found wins by priority).
    public static func discoverAll() -> [DiscoveredCredential] {
        var found: [KnownProvider: DiscoveredCredential] = [:]

        // Priority order: Swoosh keychain > env > config file > third-party keychain
        // (We don't overwrite if already found at higher priority)

        // 1. Environment variables (highest priority after own keychain)
        for cred in EnvironmentScavenger.scan() {
            if found[cred.provider] == nil { found[cred.provider] = cred }
        }

        // 2. Config files on disk
        for cred in ConfigFileScavenger.scan() {
            if found[cred.provider] == nil { found[cred.provider] = cred }
        }

        // 3. Third-party keychain items (silent, no UI prompt)
        #if canImport(Security)
        for cred in KeychainScavenger.scan() {
            if found[cred.provider] == nil { found[cred.provider] = cred }
        }
        #endif

        return Array(found.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    /// Import all discovered credentials into the given secret store.
    /// Returns the list of providers that were newly imported.
    public static func importAll(
        into store: any SecretStoring,
        overwrite: Bool = false
    ) async throws -> [KnownProvider] {
        let discovered = discoverAll()
        var imported: [KnownProvider] = []

        for cred in discovered {
            let ref = cred.swooshRef
            let alreadyExists = (try? await store.exists(ref)) ?? false
            if alreadyExists && !overwrite { continue }

            try await store.set(cred.value, ref: ref)
            imported.append(cred.provider)
        }

        return imported
    }
}
