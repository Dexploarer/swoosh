// DetourIOSInstaller.swift - paired iPhone build/install helper (0.5A)

import Foundation
import OSLog

private let detourIOSInstallerLog = Logger(subsystem: "ai.swoosh.detour.mac", category: "IOSInstall")

struct DetourIOSInstallResult {
    let succeeded: Bool
    let title: String
    let detail: String
}

enum DetourIOSInstaller {
    static func installOnFirstPairedIPhone() -> DetourIOSInstallResult {
        do {
            let projectRoot = projectRoot()
            let derivedData = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".detour", isDirectory: true)
                .appendingPathComponent("DerivedDataPhoneInstall", isDirectory: true)
            let app = derivedData
                .appendingPathComponent("Build", isDirectory: true)
                .appendingPathComponent("Products", isDirectory: true)
                .appendingPathComponent("Debug-iphoneos", isDirectory: true)
                .appendingPathComponent("Detour.app", isDirectory: true)

            let device = try firstPairedIPhone()
            try buildIOSApp(projectRoot: projectRoot, derivedData: derivedData)
            try install(app: app, deviceID: device.identifier)

            return DetourIOSInstallResult(
                succeeded: true,
                title: "Installed",
                detail: "Detour is installed on \(device.name)."
            )
        } catch {
            detourIOSInstallerLog.error("[DetourIOSInstaller] install failed error=\(error.localizedDescription, privacy: .public)")
            return DetourIOSInstallResult(
                succeeded: false,
                title: "Install Failed",
                detail: error.localizedDescription
            )
        }
    }

    private static func firstPairedIPhone() throws -> IOSDevice {
        let output = try temporaryJSONURL(prefix: "detour-devices")
        defer { try? FileManager.default.removeItem(at: output) }

        try run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", output.path(percentEncoded: false)]
        )

        let data = try Data(contentsOf: output)
        let envelope = try JSONDecoder().decode(DeviceListEnvelope.self, from: data)
        guard let device = envelope.result.devices.first(where: { device in
            device.hardwareProperties.deviceType == "iPhone"
                && device.connectionProperties.pairingState == "paired"
        }) else {
            throw DetourIOSInstallError.noPairedIPhone
        }
        return IOSDevice(identifier: device.identifier, name: device.deviceProperties.name)
    }

    private static func buildIOSApp(projectRoot: URL, derivedData: URL) throws {
        try run(
            "/usr/bin/xcodebuild",
            arguments: [
                "-project", projectRoot.appendingPathComponent("Swoosh.xcodeproj").path(percentEncoded: false),
                "-scheme", "SwooshiOS",
                "-destination", "generic/platform=iOS",
                "-configuration", "Debug",
                "-derivedDataPath", derivedData.path(percentEncoded: false),
                "build"
            ],
            currentDirectory: projectRoot
        )
    }

    private static func install(app: URL, deviceID: String) throws {
        guard FileManager.default.fileExists(atPath: app.path(percentEncoded: false)) else {
            throw DetourIOSInstallError.missingBuiltApp
        }

        try run(
            "/usr/bin/xcrun",
            arguments: [
                "devicectl", "device", "install", "app",
                "--device", deviceID,
                app.path(percentEncoded: false)
            ]
        )
    }

    private static func run(_ executable: String, arguments: [String], currentDirectory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let log = try logFileHandle()
        defer { try? log.close() }
        process.standardOutput = log
        process.standardError = log

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DetourIOSInstallError.commandFailed(arguments.joined(separator: " "))
        }
    }

    private static func projectRoot() -> URL {
        if let root = ProcessInfo.processInfo.environment["DETOUR_PROJECT_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func temporaryJSONURL(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
    }

    private static func logFileHandle() throws -> FileHandle {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".detour", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ios-install.log")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n--- \(Date()) ---\n".utf8))
        return handle
    }
}

private struct IOSDevice {
    let identifier: String
    let name: String
}

private struct DeviceListEnvelope: Decodable {
    let result: DeviceListResult
}

private struct DeviceListResult: Decodable {
    let devices: [DeviceListDevice]
}

private struct DeviceListDevice: Decodable {
    let identifier: String
    let connectionProperties: DeviceConnectionProperties
    let deviceProperties: DeviceProperties
    let hardwareProperties: HardwareProperties
}

private struct DeviceConnectionProperties: Decodable {
    let pairingState: String
}

private struct DeviceProperties: Decodable {
    let name: String
}

private struct HardwareProperties: Decodable {
    let deviceType: String
}

private enum DetourIOSInstallError: LocalizedError {
    case noPairedIPhone
    case missingBuiltApp
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPairedIPhone:
            "No paired iPhone is available to install to."
        case .missingBuiltApp:
            "The iPhone app build did not produce Detour.app."
        case .commandFailed(let command):
            "Command failed: \(command). See ~/.detour/logs/ios-install.log."
        }
    }
}
