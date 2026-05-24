// SwooshScout/Sources.swift — 0.9S Built-in Scout data sources
//
// Device, apps, files, calendar, browser, Git, Xcode, shell, Hermes import.
// Personal (deep-personalization) sources live under
// `PersonalSources/` — one file per source — so this file stays focused
// on the low- and medium-sensitivity sources that ship with `.minimal`
// and `.recommended` depths.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Device source

public struct DeviceSource: ScoutSource {
    public let id = "device"
    public let displayName = "Device Profile"
    public let description = "OS version, CPU, memory, architecture."
    public let sensitivity = Sensitivity.low
    public let requiredPermissions: [String] = []

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        let info = ProcessInfo.processInfo
        var records: [ScoutRecord] = []

        records.append(ScoutRecord(
            sourceID: id, kind: .deviceInfo, sensitivity: .low,
            content: "OS: \(info.operatingSystemVersionString)",
            metadata: ["os_version": info.operatingSystemVersionString]
        ))

        let memGB = Double(info.physicalMemory) / (1024 * 1024 * 1024)
        records.append(ScoutRecord(
            sourceID: id, kind: .deviceInfo, sensitivity: .low,
            content: "Memory: \(Int(memGB)) GB unified memory",
            metadata: ["memory_gb": String(Int(memGB))]
        ))

        #if arch(arm64)
        records.append(ScoutRecord(
            sourceID: id, kind: .deviceInfo, sensitivity: .low,
            content: "Architecture: Apple Silicon (arm64)"
        ))
        #else
        records.append(ScoutRecord(
            sourceID: id, kind: .deviceInfo, sensitivity: .low,
            content: "Architecture: Intel (x86_64)"
        ))
        #endif

        return records
    }
}

// MARK: - Installed apps source

public struct InstalledAppsSource: ScoutSource {
    public let id = "installed_apps"
    public let displayName = "Installed Applications"
    public let description = "Scan /Applications for installed apps."
    public let sensitivity = Sensitivity.low
    public let requiredPermissions: [String] = []

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        let fm = FileManager.default
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
        ]

        var records: [ScoutRecord] = []

        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in contents where item.pathExtension == "app" {
                let name = item.deletingPathExtension().lastPathComponent
                records.append(ScoutRecord(
                    sourceID: id, kind: .installedApp, sensitivity: .low,
                    content: name,
                    metadata: ["path": item.path]
                ))
            }
        }

        return records
    }
}

// MARK: - Running apps source

public struct RunningAppsSource: ScoutSource {
    public let id = "running_apps"
    public let displayName = "Running Applications"
    public let description = "Currently running apps."
    public let sensitivity = Sensitivity.low
    public let requiredPermissions: [String] = []

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(AppKit)
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName,
                  !name.isEmpty,
                  app.activationPolicy == .regular else { return nil }
            return ScoutRecord(
                sourceID: id, kind: .runningApp, sensitivity: .low,
                content: name,
                metadata: [
                    "bundle_id": app.bundleIdentifier ?? "",
                    "is_active": String(app.isActive)
                ]
            )
        }
        #else
        return []
        #endif
    }
}

// MARK: - Project folders source

public struct ProjectFoldersSource: ScoutSource {
    public let id = "project_folders"
    public let displayName = "Project Folders"
    public let description = "Scan selected folders for projects (Swift packages, Git repos, etc.)."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions = ["filesystem.read"]

    private let scanPaths: [URL]

    public init(paths: [URL] = []) {
        self.scanPaths = paths
    }

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        let fm = FileManager.default
        var records: [ScoutRecord] = []

        for path in scanPaths {
            guard let children = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }

                let name = child.lastPathComponent
                guard !name.hasPrefix(".") else { continue }

                // Detect project type
                let hasPackageSwift = fm.fileExists(atPath: child.appending(path: "Package.swift").path)
                let hasGit = fm.fileExists(atPath: child.appending(path: ".git").path)
                let hasPackageJSON = fm.fileExists(atPath: child.appending(path: "package.json").path)
                let hasCargoToml = fm.fileExists(atPath: child.appending(path: "Cargo.toml").path)

                var projectType = "unknown"
                if hasPackageSwift { projectType = "Swift Package" }
                else if hasCargoToml { projectType = "Rust/Cargo" }
                else if hasPackageJSON { projectType = "Node.js" }
                else if hasGit { projectType = "Git repository" }

                if projectType != "unknown" {
                    records.append(ScoutRecord(
                        sourceID: id, kind: .projectInfo, sensitivity: .low,
                        content: "\(name) — \(projectType)",
                        metadata: ["path": child.path, "type": projectType]
                    ))
                }
            }
        }

        return records
    }
}

