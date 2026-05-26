// DetourPersonalizationInventoryModels.swift — personalization setup models (0.5A)

import Foundation

struct ChatAdapterToggleRecord: Codable {
    var kind: String
    var enabled: Bool
}

struct AppUsageSummary {
    var displayName: String
    var duration: TimeInterval
}

struct AppUsageInventory {
    var requested: Bool
    var topApps: [AppUsageSummary]
    var summary: String

    var topAppNames: Set<String> {
        Set(topApps.map { $0.displayName.lowercased() })
    }

    static let notRequested = AppUsageInventory(requested: false, topApps: [], summary: "App usage not allowed")
}

struct AppFocusEventLine: Decodable {
    var displayName: String
    var startedAt: Date
    var endedAt: Date
}

struct GitActivityInventory {
    var requested: Bool
    var repositories: [GitRepositoryActivity]
    var gitUserName: String?
    var gitUserEmail: String?
    var summary: String

    static let notRequested = GitActivityInventory(
        requested: false,
        repositories: [],
        gitUserName: nil,
        gitUserEmail: nil,
        summary: "Git history not allowed"
    )
}

struct GitRepositoryActivity {
    var name: String
    var path: String
    var latestCommitDate: Date
    var latestSubject: String
    var commitCount: Int
}

struct GitCommitSignal {
    var date: Date
    var subject: String
}

struct ContactInventory {
    var requested: Bool
    var authorized: Bool
    var totalCount: Int
    var names: [String]
    var organizations: [String]
    var summary: String

    static let notRequested = ContactInventory(
        requested: false,
        authorized: false,
        totalCount: 0,
        names: [],
        organizations: [],
        summary: "Contacts not allowed"
    )
}

struct MessageInventory {
    var requested: Bool
    var databaseExists: Bool
    var databaseReadable: Bool
    var relationships: [MessageRelationshipSignal]
    var chatDatabaseStatus: String
    var summary: String

    static let notRequested = MessageInventory(
        requested: false,
        databaseExists: false,
        databaseReadable: false,
        relationships: [],
        chatDatabaseStatus: "Messages not allowed",
        summary: "Messages not allowed"
    )
}

struct MessageRelationshipSignal {
    var handle: String
    var messageCount: Int
    var lastDateRaw: String?
}

struct ProviderInheritanceSummary {
    var discoveredProviders: [String]
    var importedProviders: [String]
    var browserStores: [String]
}

struct ProviderInheritCommand {
    var executable: URL
    var argumentsPrefix: [String]
    var currentDirectory: URL
}


struct CredentialMetadataRule {
    var providerID: String
    var providerName: String
    var terms: [String]
    var keys: [String]
    var defaultScope: DetourDelegationRole
    var importableProviderID: String?
}

struct KeychainCredentialMetadata {
    var providerID: String
    var providerName: String
    var displayLabel: String
    var detail: String
    var keys: [String]
    var scope: DetourDelegationRole
    var importableProviderID: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var recordCount: Int
}

struct BrowserAccountFinding {
    var browser: String
    var profile: String
    var profileEmail: String?
    var profileName: String?
    var account: String
    var evidence: String
    var scope: DetourDelegationRole
}

struct ChromiumProfileMetadata {
    var email: String?
    var name: String?
}

struct ChromiumBrowserProfile {
    var browser: String
    var profile: String
    var profileEmail: String?
    var profileName: String?
    var profileRoot: URL
    var historyURL: URL
    var loginDataURL: URL
    var cookiesURL: URL
}

struct GitHubAccountIdentity {
    var login: String
    var email: String?
    var source: String
    var scope: DetourDelegationRole

    var displayLabel: String {
        if let email, !login.localizedCaseInsensitiveContains(email) {
            return "\(login) (\(email))"
        }
        return login
    }
}

struct AuthCredentialFinding {
    var id: String
    var title: String
    var detail: String
    var source: String
    var providerID: String?
    var keys: [String]
    var count: Int
    var scope: DetourDelegationRole
}

struct AuthInventory {
    var importedProviders: Set<String>
    var browserStores: [String]
    var mentionedKeys: Set<String>
    var keychainKeys: Set<String>
    var githubAccounts: [GitHubAccountIdentity]
    var legacy: DetourLegacyCredentialImportResult
    var credentialFindings: [AuthCredentialFinding]
    var xCookieStatus: String
    var summary: String

    var browserCookieStoresFound: Bool {
        !browserStores.isEmpty
    }

    func hasAny(_ keys: [String]) -> Bool {
        let inherited = Set(legacy.availableKeys).union(legacy.importedKeys)
        return !mentionedKeys.isDisjoint(with: keys)
            || !keychainKeys.isDisjoint(with: keys)
            || !inherited.isDisjoint(with: keys)
    }

    var legacyVaultDetail: String {
        if legacy.decrypted && !legacy.importedKeys.isEmpty {
            return "imported \(legacy.importedKeys.count) credential names"
        }
        if legacy.decrypted && !legacy.availableKeys.isEmpty {
            return "found \(legacy.availableKeys.count) credential names"
        }
        if legacy.decrypted {
            return "found, no matching credential names"
        }
        return legacy.error ?? "found, unlock needed"
    }
}

extension Array where Element == DetourSetupCandidate {
    func uniquedByID() -> [DetourSetupCandidate] {
        var seen = Set<String>()
        return filter { candidate in
            seen.insert(candidate.id).inserted
        }
    }
}

extension Array where Element == AuthCredentialFinding {
    func uniquedByID() -> [AuthCredentialFinding] {
        var seen = Set<String>()
        return filter { finding in
            seen.insert(finding.id).inserted
        }
    }
}

extension Array where Element == String {
    func joinedNonEmpty(separator: String) -> String? {
        let value = joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension CharacterSet {
    static let detourPersonalizationHexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}
