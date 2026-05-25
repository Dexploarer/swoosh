// DetouriOSStateStore.swift — JSON-backed iPhone onboarding and pairing state (0.5A)

import Foundation

enum DetouriOSOnboardingStep: String, Codable, Equatable, Sendable {
    case askingName
    case askingAgentName
    case renamingAgent
    case choosingVoice
    case settingWakeWord
    case askingVoiceRecognition
    case enrollingVoice
    case askingDeviceSetup
    case choosingDevices
    case complete
}

enum DetouriOSDeviceKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case macBook
    case macMini
    case iPhone
    case iPad
    case appleWatch
    case iMac
    case macStudio
    case visionPro
    case remoteDetour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macBook:
            "MacBook"
        case .macMini:
            "Mac mini"
        case .iPhone:
            "iPhone"
        case .iPad:
            "iPad"
        case .appleWatch:
            "Apple Watch"
        case .iMac:
            "iMac"
        case .macStudio:
            "Mac Studio"
        case .visionPro:
            "Apple Vision Pro"
        case .remoteDetour:
            "Remote Detour"
        }
    }

    var symbolName: String {
        switch self {
        case .macBook:
            "macbook"
        case .macMini:
            "macmini"
        case .iPhone:
            "iphone"
        case .iPad:
            "ipad"
        case .appleWatch:
            "applewatch"
        case .iMac:
            "desktopcomputer"
        case .macStudio:
            "macstudio"
        case .visionPro:
            "visionpro"
        case .remoteDetour:
            "server.rack"
        }
    }
}

enum DetouriOSReachability: String, Codable, Equatable {
    case unknown
    case checking
    case reachable
    case unreachable
}

struct DetouriOSVoiceRecognition: Codable, Equatable {
    var enabled: Bool
    var wakeWord: String
    var enrollmentPhrase: String?
    var sampleRelativePath: String?
    var enrolledAt: Date?

    static func defaultRecognition(agentName: String = "Detour") -> DetouriOSVoiceRecognition {
        DetouriOSVoiceRecognition(
            enabled: false,
            wakeWord: "Hey \(agentName)",
            enrollmentPhrase: nil,
            sampleRelativePath: nil,
            enrolledAt: nil
        )
    }
}

struct DetouriOSRemoteInstance: Codable, Equatable, Hashable {
    var host: String
    var sshUser: String
    var sshPort: Int
}

struct DetouriOSPairedMac: Codable, Equatable {
    var host: String
    var pairedAt: Date
    var lastReachability: DetouriOSReachability

    var hostURL: URL? {
        URL(string: host)
    }
}

struct DetouriOSProfile: Codable, Equatable {
    var schemaVersion: Int
    var userName: String
    var agentName: String?
    var onboardingStage: DetouriOSOnboardingStep
    var onboardingCompleted: Bool
    var wantsOtherAppleDevices: Bool?
    var voiceRecognition: DetouriOSVoiceRecognition
    var selectedDeviceKinds: [DetouriOSDeviceKind]
    var remoteInstances: [DetouriOSRemoteInstance]
    var pairedMac: DetouriOSPairedMac?
    var updatedAt: Date

    init(
        schemaVersion: Int = 1,
        userName: String,
        agentName: String?,
        onboardingStage: DetouriOSOnboardingStep,
        onboardingCompleted: Bool,
        wantsOtherAppleDevices: Bool?,
        voiceRecognition: DetouriOSVoiceRecognition,
        selectedDeviceKinds: [DetouriOSDeviceKind],
        remoteInstances: [DetouriOSRemoteInstance],
        pairedMac: DetouriOSPairedMac?,
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
        self.pairedMac = pairedMac
        self.updatedAt = updatedAt
    }
}

struct DetouriOSConfig: Codable, Equatable {
    struct Speech: Codable, Equatable {
        var voiceIdentifier: String?
        var rateMultiplier: Double
        var pitchMultiplier: Double
    }

    var schemaVersion: Int
    var speech: Speech
    var updatedAt: Date

    static func defaultConfig() -> DetouriOSConfig {
        DetouriOSConfig(
            schemaVersion: 1,
            speech: Speech(
                voiceIdentifier: DetouriOSVoiceCatalog.defaultVoiceIdentifier(),
                rateMultiplier: 0.92,
                pitchMultiplier: 1.02
            ),
            updatedAt: .now
        )
    }
}

final class DetouriOSStateStore {
    private let fileManager: FileManager
    private let directories: DetouriOSDirectories
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directories = DetouriOSPaths.directories(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    var voiceEnrollmentSampleURL: URL {
        directories.voiceEnrollmentSample
    }

    var voiceEnrollmentSampleRelativePath: String {
        DetouriOSPaths.voiceEnrollmentSampleRelativePath
    }

    func prepareDirectories() throws {
        try fileManager.createDirectory(at: directories.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directories.logs, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directories.voice, withIntermediateDirectories: true)
    }

    func loadProfile() throws -> DetouriOSProfile? {
        guard fileManager.fileExists(atPath: directories.profile.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: directories.profile)
        return try decoder.decode(DetouriOSProfile.self, from: data)
    }

    func saveProfile(_ profile: DetouriOSProfile) throws {
        try prepareDirectories()
        let data = try encoder.encode(profile)
        try data.write(to: directories.profile, options: [.atomic])
    }

    func loadConfig() throws -> DetouriOSConfig? {
        guard fileManager.fileExists(atPath: directories.config.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: directories.config)
        return try decoder.decode(DetouriOSConfig.self, from: data)
    }

    func saveConfig(_ config: DetouriOSConfig) throws {
        try prepareDirectories()
        let data = try encoder.encode(config)
        try data.write(to: directories.config, options: [.atomic])
    }
}

struct DetouriOSDirectories {
    let root: URL
    let profile: URL
    let config: URL
    let logs: URL
    let voice: URL
    let voiceEnrollmentSample: URL
}

enum DetouriOSPaths {
    static let voiceEnrollmentSampleRelativePath = "voice/enrollment.m4a"

    static func directories(fileManager: FileManager) -> DetouriOSDirectories {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = base.appendingPathComponent("Detour", isDirectory: true)
        let voice = root.appendingPathComponent("voice", isDirectory: true)
        return DetouriOSDirectories(
            root: root,
            profile: root.appendingPathComponent("profile.json", isDirectory: false),
            config: root.appendingPathComponent("config.json", isDirectory: false),
            logs: root.appendingPathComponent("logs", isDirectory: true),
            voice: voice,
            voiceEnrollmentSample: root.appendingPathComponent(voiceEnrollmentSampleRelativePath, isDirectory: false)
        )
    }
}
