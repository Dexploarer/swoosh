// SwooshSecrets/CredentialScavenger.swift — 0.9S Multi-source credential discovery
//
// Inspired by CodexBar's provider credential resolution chain.
// Discovers API keys, OAuth tokens, and session credentials from:
//   1. Environment variables
//   2. Known config files on disk
//   3. macOS Keychain when the foreground caller grants access
//   4. Browser cookie access checks when the foreground caller grants access
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
    case anthropic    = "anthropic"
    case gemini       = "gemini"
    case codex        = "codex"

    public var displayName: String {
        switch self {
        case .openAI:     return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .elizaCloud: return "Eliza Cloud"
        case .anthropic:  return "Claude"
        case .gemini:     return "Gemini"
        case .codex:      return "Codex"
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

public struct CredentialScavengerAccess: Sendable, Codable, Equatable {
    public var environment: Bool
    public var configFiles: Bool
    public var keychainCredentials: Bool
    public var promptForKeychainAccess: Bool
    public var browserCookies: Bool

    public init(
        environment: Bool = true,
        configFiles: Bool = true,
        keychainCredentials: Bool = false,
        promptForKeychainAccess: Bool = false,
        browserCookies: Bool = false
    ) {
        self.environment = environment
        self.configFiles = configFiles
        self.keychainCredentials = keychainCredentials
        self.promptForKeychainAccess = promptForKeychainAccess
        self.browserCookies = browserCookies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environment = try container.decodeIfPresent(Bool.self, forKey: .environment) ?? true
        configFiles = try container.decodeIfPresent(Bool.self, forKey: .configFiles) ?? true
        keychainCredentials = try container.decodeIfPresent(Bool.self, forKey: .keychainCredentials) ?? false
        promptForKeychainAccess = try container.decodeIfPresent(Bool.self, forKey: .promptForKeychainAccess) ?? false
        browserCookies = try container.decodeIfPresent(Bool.self, forKey: .browserCookies) ?? false
    }

    public static let defaultLocal = CredentialScavengerAccess()
}

public struct BrowserCookieAccessSummary: Sendable, Codable, Equatable {
    public let accessibleBrowsers: [String]
    public let allowed: Bool

    public init(accessibleBrowsers: [String], allowed: Bool) {
        self.accessibleBrowsers = accessibleBrowsers
        self.allowed = allowed
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Credential Scavenger (orchestrator)
// ═══════════════════════════════════════════════════════════════════

public enum CredentialScavenger {

    /// Discover all available credentials across all sources.
    /// Returns one credential per provider (first-found wins by priority).
    public static func discoverAll(
        access: CredentialScavengerAccess = .defaultLocal
    ) -> [DiscoveredCredential] {
        var found: [KnownProvider: DiscoveredCredential] = [:]

        // Priority order: env > config file > third-party keychain
        // (We don't overwrite if already found at higher priority)

        if access.environment {
            for cred in EnvironmentScavenger.scan() {
                if found[cred.provider] == nil { found[cred.provider] = cred }
            }
        }

        if access.configFiles {
            for cred in ConfigFileScavenger.scan() {
                if found[cred.provider] == nil { found[cred.provider] = cred }
            }
        }

        if access.keychainCredentials {
            #if canImport(Security)
            for cred in KeychainScavenger.scan(allowUserInteraction: access.promptForKeychainAccess) {
                if found[cred.provider] == nil { found[cred.provider] = cred }
            }
            #endif
        }

        return Array(found.values).sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    public static func browserCookieAccess(
        access: CredentialScavengerAccess = .defaultLocal
    ) -> BrowserCookieAccessSummary {
        guard access.browserCookies else {
            return BrowserCookieAccessSummary(accessibleBrowsers: [], allowed: false)
        }
        return BrowserCookieAccessSummary(
            accessibleBrowsers: KeychainScavenger.accessibleBrowsers(),
            allowed: true
        )
    }

    /// Import all discovered credentials into the given secret store.
    /// Returns the list of providers that were newly imported.
    public static func importAll(
        into store: any SecretStoring,
        overwrite: Bool = false,
        access: CredentialScavengerAccess = .defaultLocal
    ) async throws -> [KnownProvider] {
        let discovered = discoverAll(access: access)
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
