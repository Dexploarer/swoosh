// DetourStateStore.swift — JSON-backed Detour profile and app configuration (0.5A)

import Foundation

enum DetourVoiceIdentifier {
    static let omniVoiceLocal = "omnivoice-local"
}

struct DetourProfile: Codable, Equatable {
    var schemaVersion: Int
    var userName: String
    var agentName: String?
    var onboardingStage: PersistedOnboardingStage
    var onboardingCompleted: Bool
    var wantsOtherAppleDevices: Bool?
    var voiceRecognition: DetourVoiceRecognition
    var credentialInheritance: DetourCredentialInheritanceConsent
    var approvedSetupCandidateIDs: [String]
    var deniedSetupCandidateIDs: [String]
    var setupCandidateScopes: [String: DetourDelegationRole]
    var delegationProfiles: [DetourDelegationProfile]
    var selectedDeviceKinds: [DetourDeviceKind]
    var remoteInstances: [DetourRemoteInstance]
    var updatedAt: Date

    init(
        schemaVersion: Int = 1,
        userName: String,
        agentName: String?,
        onboardingStage: PersistedOnboardingStage,
        onboardingCompleted: Bool,
        wantsOtherAppleDevices: Bool?,
        voiceRecognition: DetourVoiceRecognition,
        credentialInheritance: DetourCredentialInheritanceConsent = DetourCredentialInheritanceConsent(),
        approvedSetupCandidateIDs: [String] = [],
        deniedSetupCandidateIDs: [String] = [],
        setupCandidateScopes: [String: DetourDelegationRole] = [:],
        delegationProfiles: [DetourDelegationProfile] = [],
        selectedDeviceKinds: [DetourDeviceKind],
        remoteInstances: [DetourRemoteInstance],
        updatedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.userName = userName
        self.agentName = agentName
        self.onboardingStage = onboardingStage
        self.onboardingCompleted = onboardingCompleted
        self.wantsOtherAppleDevices = wantsOtherAppleDevices
        self.voiceRecognition = voiceRecognition
        self.credentialInheritance = credentialInheritance
        self.approvedSetupCandidateIDs = approvedSetupCandidateIDs
        self.deniedSetupCandidateIDs = deniedSetupCandidateIDs
        self.setupCandidateScopes = setupCandidateScopes
        self.delegationProfiles = delegationProfiles
        self.selectedDeviceKinds = selectedDeviceKinds
        self.remoteInstances = remoteInstances
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        userName = try container.decode(String.self, forKey: .userName)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingStage = try container.decodeIfPresent(PersistedOnboardingStage.self, forKey: .onboardingStage)
            ?? (onboardingCompleted ? .complete : .choosingVoice)
        wantsOtherAppleDevices = try container.decodeIfPresent(Bool.self, forKey: .wantsOtherAppleDevices)
        voiceRecognition = try container.decodeIfPresent(DetourVoiceRecognition.self, forKey: .voiceRecognition)
            ?? DetourVoiceRecognition.defaultRecognition()
        credentialInheritance = try container.decodeIfPresent(
            DetourCredentialInheritanceConsent.self,
            forKey: .credentialInheritance
        ) ?? DetourCredentialInheritanceConsent()
        approvedSetupCandidateIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .approvedSetupCandidateIDs
        ) ?? []
        deniedSetupCandidateIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .deniedSetupCandidateIDs
        ) ?? []
        setupCandidateScopes = try container.decodeIfPresent(
            [String: DetourDelegationRole].self,
            forKey: .setupCandidateScopes
        ) ?? [:]
        delegationProfiles = try container.decodeIfPresent(
            [DetourDelegationProfile].self,
            forKey: .delegationProfiles
        ) ?? []
        selectedDeviceKinds = try container.decodeIfPresent([DetourDeviceKind].self, forKey: .selectedDeviceKinds) ?? []
        remoteInstances = try container.decodeIfPresent([DetourRemoteInstance].self, forKey: .remoteInstances) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

struct DetourVoiceRecognition: Codable, Equatable {
    var enabled: Bool
    var wakeWord: String
    var enrollmentPhrase: String?
    var sampleRelativePath: String?
    var enrolledAt: Date?

    static func defaultRecognition(agentName: String = "Detour") -> DetourVoiceRecognition {
        DetourVoiceRecognition(
            enabled: false,
            wakeWord: "Hey \(agentName)",
            enrollmentPhrase: nil,
            sampleRelativePath: nil,
            enrolledAt: nil
        )
    }
}

struct DetourCredentialInheritanceConsent: Codable, Equatable {
    var keychainCredentials: Bool
    var browserCookies: Bool
    var appUsage: Bool
    var gitHistory: Bool
    var contacts: Bool
    var messages: Bool
    var accountDelegation: Bool

    init(
        keychainCredentials: Bool = false,
        browserCookies: Bool = false,
        appUsage: Bool = false,
        gitHistory: Bool = false,
        contacts: Bool = false,
        messages: Bool = false,
        accountDelegation: Bool = false
    ) {
        self.keychainCredentials = keychainCredentials
        self.browserCookies = browserCookies
        self.appUsage = appUsage
        self.gitHistory = gitHistory
        self.contacts = contacts
        self.messages = messages
        self.accountDelegation = accountDelegation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keychainCredentials = try container.decodeIfPresent(Bool.self, forKey: .keychainCredentials) ?? false
        browserCookies = try container.decodeIfPresent(Bool.self, forKey: .browserCookies) ?? false
        appUsage = try container.decodeIfPresent(Bool.self, forKey: .appUsage) ?? false
        gitHistory = try container.decodeIfPresent(Bool.self, forKey: .gitHistory) ?? false
        contacts = try container.decodeIfPresent(Bool.self, forKey: .contacts) ?? false
        messages = try container.decodeIfPresent(Bool.self, forKey: .messages) ?? false
        accountDelegation = try container.decodeIfPresent(Bool.self, forKey: .accountDelegation) ?? false
    }

    static func fullPersonalization() -> DetourCredentialInheritanceConsent {
        DetourCredentialInheritanceConsent(
            keychainCredentials: true,
            browserCookies: true,
            appUsage: true,
            gitHistory: true,
            contacts: true,
            messages: true,
            accountDelegation: true
        )
    }
}

enum DetourDelegationRole: String, Codable, Equatable {
    case user
    case agent
}

struct DetourDelegationProfile: Codable, Equatable {
    var role: DetourDelegationRole
    var displayName: String
    var accountLabels: [String]
    var context: String
}

enum PersistedOnboardingStage: String, Codable, Equatable {
    case askingName
    case askingAgentName
    case renamingAgent
    case choosingVoice
    case askingVoiceRecognition
    case enrollingVoice
    case settingWakeWord
    case askingDeviceSetup
    case choosingDevices
    case showingPairingQRCode
    case askingPersonalizationScan
    case askingCredentialInheritance
    case runningPersonalizationScan
    case reviewingPersonalizationScan
    case askingPersonalizationQuestion
    case complete
}

struct DetourConfig: Codable, Equatable {
    struct Speech: Codable, Equatable {
        var voiceIdentifier: String?
        var rateMultiplier: Double
        var pitchMultiplier: Double
    }

    var schemaVersion: Int
    var speech: Speech
    var updatedAt: Date

    static func defaultConfig() -> DetourConfig {
        DetourConfig(
            schemaVersion: 1,
            speech: Speech(
                voiceIdentifier: DetourVoiceIdentifier.omniVoiceLocal,
                rateMultiplier: 0.92,
                pitchMultiplier: 1.02
            ),
            updatedAt: .now
        )
    }
}

final class DetourStateStore {
    private let fileManager: FileManager
    private let directories: DetourDirectories
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.directories = DetourPaths.directories(home: home)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    var rootDirectory: URL {
        directories.root
    }

    func prepareDirectories() throws {
        try fileManager.createDirectory(at: directories.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directories.logs, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directories.voice, withIntermediateDirectories: true)
    }

    var voiceEnrollmentSampleURL: URL {
        directories.voiceEnrollmentSample
    }

    var voiceEnrollmentSampleRelativePath: String {
        DetourPaths.voiceEnrollmentSampleRelativePath
    }

    func loadProfile() throws -> DetourProfile? {
        guard fileManager.fileExists(atPath: directories.profile.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: directories.profile)
        return try decoder.decode(DetourProfile.self, from: data)
    }

    func saveProfile(_ profile: DetourProfile) throws {
        try prepareDirectories()
        let data = try encoder.encode(profile)
        try data.write(to: directories.profile, options: [.atomic])
    }

    func loadConfig() throws -> DetourConfig? {
        guard fileManager.fileExists(atPath: directories.config.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: directories.config)
        return try decoder.decode(DetourConfig.self, from: data)
    }

    func saveConfig(_ config: DetourConfig) throws {
        try prepareDirectories()
        let data = try encoder.encode(config)
        try data.write(to: directories.config, options: [.atomic])
    }

    func loadPersonalizationReport() throws -> DetourPersonalizationScanResult? {
        let url = directories.root.appending(path: "personalization-report.json")
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return sanitizedPersonalizationReport(try decoder.decode(DetourPersonalizationScanResult.self, from: data))
    }

    func deletePersonalizationReport() throws {
        let url = directories.root.appending(path: "personalization-report.json")
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    func sanitizedPersonalizationReport(
        _ report: DetourPersonalizationScanResult
    ) -> DetourPersonalizationScanResult {
        var copy = report
        copy.setupCandidates = collapsedBrowserAccountCandidates(
            collapsedStaleKeychainCandidates(report.setupCandidates)
        )
        return copy
    }

    private func collapsedStaleKeychainCandidates(
        _ candidates: [DetourSetupCandidate]
    ) -> [DetourSetupCandidate] {
        var groups: [String: [DetourSetupCandidate]] = [:]
        for candidate in candidates {
            guard let key = keychainCandidateGroupKey(candidate) else { continue }
            groups[key, default: []].append(candidate)
        }

        var emitted = Set<String>()
        var output: [DetourSetupCandidate] = []
        for candidate in candidates {
            guard let key = keychainCandidateGroupKey(candidate) else {
                output.append(candidate)
                continue
            }
            guard emitted.insert(key).inserted, let group = groups[key] else { continue }
            output.append(collapsedKeychainCandidate(group))
        }
        return output
    }

    private func collapsedKeychainCandidate(_ group: [DetourSetupCandidate]) -> DetourSetupCandidate {
        guard group.count > 1 else { return group[0] }
        var selected = preferredKeychainCandidate(group)
        let label = keychainCandidateLabel(selected.title).map(staleCredentialFamilyLabel)
        if let label {
            selected.title = keychainCandidateTitle(selected.title, label: label)
        }
        let keys = Set(group.flatMap { $0.credentialKeys ?? [] }).sorted()
        if !keys.isEmpty {
            selected.credentialKeys = keys
        }
        let hidden = group.count - 1
        let duplicateText = "\(hidden) stale duplicate\(hidden == 1 ? "" : "s") hidden"
        selected.detail = selected.detail.contains("stale duplicate")
            ? selected.detail
            : "\(selected.detail); \(duplicateText)"
        selected.foundCount = max(group.compactMap(\.foundCount).max() ?? 1, group.count)
        selected.selected = group.contains { $0.selected }
        return selected
    }

    private func preferredKeychainCandidate(_ group: [DetourSetupCandidate]) -> DetourSetupCandidate {
        group.sorted { lhs, rhs in
            let lhsLabel = keychainCandidateLabel(lhs.title) ?? lhs.title
            let rhsLabel = keychainCandidateLabel(rhs.title) ?? rhs.title
            let lhsCanonical = lhsLabel == staleCredentialFamilyLabel(lhsLabel)
            let rhsCanonical = rhsLabel == staleCredentialFamilyLabel(rhsLabel)
            if lhsCanonical != rhsCanonical {
                return lhsCanonical
            }
            return lhs.title < rhs.title
        }.first ?? group[0]
    }

    private func keychainCandidateGroupKey(_ candidate: DetourSetupCandidate) -> String? {
        guard candidate.source == "Keychain",
              candidate.id.hasPrefix("credential.keychain."),
              let label = keychainCandidateLabel(candidate.title) else {
            return nil
        }
        let providerID = candidate.id.split(separator: ".").dropFirst(2).first.map(String.init) ?? candidate.title
        if ["anthropic", "codex", "gemini", "openai"].contains(providerID) {
            return [
                providerID,
                candidate.scope?.rawValue ?? "",
                (candidate.credentialKeys ?? []).sorted().joined(separator: ",")
            ].joined(separator: "\u{1f}")
        }
        return [
            providerID,
            staleCredentialFamilyLabel(label).lowercased(),
            candidate.scope?.rawValue ?? "",
            (candidate.credentialKeys ?? []).sorted().joined(separator: ",")
        ].joined(separator: "\u{1f}")
    }

    private func keychainCandidateLabel(_ title: String) -> String? {
        guard let range = title.range(of: ": ") else { return nil }
        return String(title[range.upperBound...])
    }

    private func keychainCandidateTitle(_ title: String, label: String) -> String {
        guard let range = title.range(of: ": ") else { return title }
        return "\(title[..<range.upperBound])\(label)"
    }

    private func staleCredentialFamilyLabel(_ label: String) -> String {
        let lowercased = label.lowercased()
        guard lowercased.contains("credential")
            || lowercased.contains("auth")
            || lowercased.contains("safe storage")
            || lowercased.contains("token") else {
            return label
        }
        guard let dashIndex = label.lastIndex(of: "-") else { return label }
        let suffix = label[label.index(after: dashIndex)...]
        guard suffix.count >= 6,
              suffix.count <= 16,
              suffix.unicodeScalars.allSatisfy({ CharacterSet.detourHexDigits.contains($0) }) else {
            return label
        }
        return String(label[..<dashIndex])
    }

    private func collapsedBrowserAccountCandidates(
        _ candidates: [DetourSetupCandidate]
    ) -> [DetourSetupCandidate] {
        var groups: [String: [DetourSetupCandidate]] = [:]
        for candidate in candidates {
            guard let key = browserAccountGroupKey(candidate) else { continue }
            groups[key, default: []].append(candidate)
        }

        var emitted = Set<String>()
        var output: [DetourSetupCandidate] = []
        for candidate in candidates {
            guard let key = browserAccountGroupKey(candidate) else {
                output.append(candidate)
                continue
            }
            guard emitted.insert(key).inserted, let group = groups[key] else { continue }
            output.append(collapsedBrowserAccountCandidate(group))
        }
        return output
    }

    private func collapsedBrowserAccountCandidate(_ group: [DetourSetupCandidate]) -> DetourSetupCandidate {
        guard group.count > 1 else { return group[0] }
        var selected = group.sorted { $0.title < $1.title }.first ?? group[0]
        let profileDetails = group
            .map(\.detail)
            .map(browserAccountProfileLabel)
            .uniquedPreservingOrder()
        if !profileDetails.isEmpty {
            selected.detail = profileDetails.joined(separator: ", ")
        }
        selected.foundCount = max(group.compactMap(\.foundCount).max() ?? 1, group.count)
        selected.selected = group.contains { $0.selected }
        selected.scope = group.first(where: { $0.scope != nil })?.scope ?? selected.scope
        return selected
    }

    private func browserAccountGroupKey(_ candidate: DetourSetupCandidate) -> String? {
        guard candidate.id.hasPrefix("credential.x.") else { return nil }
        let account = browserAccountLabel(candidate).lowercased()
        guard !account.isEmpty else { return nil }
        return "x\u{1f}\(account)"
    }

    private func browserAccountLabel(_ candidate: DetourSetupCandidate) -> String {
        if let range = candidate.title.range(of: " for @") {
            return String(candidate.title[range.upperBound...])
                .split(separator: " ")
                .first
                .map(String.init) ?? candidate.title
        }
        if let range = candidate.title.range(of: " profile ") {
            return String(candidate.title[range.upperBound...])
        }
        return candidate.title
    }

    private func browserAccountProfileLabel(_ detail: String) -> String {
        if let range = detail.range(of: ";") {
            return String(detail[..<range.lowerBound])
        }
        return detail
    }
}

private extension CharacterSet {
    static let detourHexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in self {
            guard seen.insert(value).inserted else { continue }
            output.append(value)
        }
        return output
    }
}
