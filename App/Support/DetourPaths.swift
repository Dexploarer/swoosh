// DetourPaths.swift — canonical local Detour state locations (0.5A)

import Foundation

struct DetourDirectories: Equatable {
    let root: URL
    let logs: URL
    let voice: URL
    let voiceEnrollmentSample: URL
    let profile: URL
    let config: URL
}

enum DetourPaths {
    static let directoryName = ".detour"
    static let profileFileName = "profile.json"
    static let configFileName = "config.json"
    static let logsDirectoryName = "logs"
    static let voiceDirectoryName = "voice"
    static let voiceEnrollmentSampleFileName = "enrollment.m4a"
    static let voiceEnrollmentSampleRelativePath = "\(voiceDirectoryName)/\(voiceEnrollmentSampleFileName)"

    static func directories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DetourDirectories {
        let root = home.appendingPathComponent(directoryName, isDirectory: true)
        let voice = root.appendingPathComponent(voiceDirectoryName, isDirectory: true)
        return DetourDirectories(
            root: root,
            logs: root.appendingPathComponent(logsDirectoryName, isDirectory: true),
            voice: voice,
            voiceEnrollmentSample: voice.appendingPathComponent(voiceEnrollmentSampleFileName, isDirectory: false),
            profile: root.appendingPathComponent(profileFileName, isDirectory: false),
            config: root.appendingPathComponent(configFileName, isDirectory: false)
        )
    }

    static func ensureDirectories(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> DetourDirectories {
        let resolved = directories(home: home)
        try fileManager.createDirectory(at: resolved.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resolved.logs, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resolved.voice, withIntermediateDirectories: true)
        return resolved
    }
}
