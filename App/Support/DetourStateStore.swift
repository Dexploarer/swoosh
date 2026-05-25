// DetourStateStore.swift — JSON-backed Detour profile and app configuration (0.5A)

import Foundation

struct DetourProfile: Codable, Equatable {
    var schemaVersion: Int
    var userName: String
    var agentName: String?
    var onboardingStage: PersistedOnboardingStage
    var onboardingCompleted: Bool
    var wantsOtherAppleDevices: Bool?
    var voiceRecognition: DetourVoiceRecognition
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
                voiceIdentifier: DetourNativeVoiceCatalog.defaultVoiceIdentifier(),
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
}
