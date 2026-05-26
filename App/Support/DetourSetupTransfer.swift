// DetourSetupTransfer.swift — portable onboarding setup bundle (0.5A)

import Foundation

struct DetourSetupTransferBundle: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var sourcePlatform: String
    var userName: String
    var agentName: String?
    var speechVoiceIdentifier: String?
    var speechRateMultiplier: Double
    var speechPitchMultiplier: Double
    var voiceRecognition: VoiceRecognition
    var credentialInheritance: CredentialInheritance
    var approvedSetupCandidateIDs: [String]
    var deniedSetupCandidateIDs: [String]
    var setupCandidateScopes: [String: String]?
    var delegationProfiles: [DelegationProfile]
    var selectedDeviceKinds: [String]
    var wantsOtherAppleDevices: Bool?
    var onboardingCompleted: Bool
    var exportedAt: Date

    struct VoiceRecognition: Codable, Equatable, Sendable {
        var enabled: Bool
        var wakeWord: String
        var enrollmentPhrase: String?
        var enrolledAt: Date?
    }

    struct CredentialInheritance: Codable, Equatable, Sendable {
        var keychainCredentials: Bool
        var browserCookies: Bool
        var appUsage: Bool
        var gitHistory: Bool
        var contacts: Bool
        var messages: Bool
        var accountDelegation: Bool
    }

    struct DelegationProfile: Codable, Equatable, Sendable {
        var role: String
        var displayName: String
        var accountLabels: [String]
        var context: String
    }

    func encodedForURL() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeURLPayload(_ value: String) throws -> DetourSetupTransferBundle {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized) else {
            throw DetourSetupTransferError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DetourSetupTransferBundle.self, from: data)
    }
}

enum DetourSetupTransferError: Error {
    case invalidPayload
}

struct DetourPairingSetupEnvelope: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var host: String
    var apiToken: String?
    var pairedTokenExpiresAt: Date?
    var setupBundle: DetourSetupTransferBundle
    var confirmationCode: String
    var issuedAt: Date
    var expiresAt: Date
}
