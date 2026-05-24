// SwooshScout/ExternalSources.swift — 0.9S Git, Shell, and Hermes scout sources
//
// Medium-sensitivity sources that read shell-visible artifacts (`.git`,
// `PATH`, Hermes imports). Run at `.recommended` depth and above. No OS
// permission prompts.
import Foundation

// MARK: - Git repos source

public struct GitReposSource: ScoutSource {
    public let id = "git_repos"
    public let displayName = "Git Repositories"
    public let description = "Detect Git repos and recent activity."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions = ["filesystem.read"]

    private let scanPaths: [URL]

    public init(paths: [URL] = []) {
        self.scanPaths = paths
    }

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        var records: [ScoutRecord] = []
        let fm = FileManager.default

        for path in scanPaths {
            guard let children = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) else { continue }

            for child in children {
                let gitDir = child.appending(path: ".git")
                guard fm.fileExists(atPath: gitDir.path) else { continue }

                // Read remote URL
                let configPath = gitDir.appending(path: "config")
                let remote = extractGitRemote(configPath: configPath)

                records.append(ScoutRecord(
                    sourceID: id, kind: .gitRepo, sensitivity: .low,
                    content: "\(child.lastPathComponent)\(remote.map { " → \($0)" } ?? "")",
                    metadata: [
                        "path": child.path,
                        "remote": remote ?? ""
                    ]
                ))
            }
        }

        return records
    }

    private func extractGitRemote(configPath: URL) -> String? {
        guard let config = try? String(contentsOf: configPath, encoding: .utf8) else { return nil }
        let lines = config.components(separatedBy: .newlines)
        var inOrigin = false
        for line in lines {
            if line.contains("[remote \"origin\"]") { inOrigin = true; continue }
            if inOrigin && line.trimmingCharacters(in: .whitespaces).hasPrefix("url") {
                return line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("[") && inOrigin { break }
        }
        return nil
    }
}

// MARK: - Shell environment source

public struct ShellEnvironmentSource: ScoutSource {
    public let id = "shell_env"
    public let displayName = "Shell Environment"
    public let description = "Detect shell, PATH tools, and developer environment."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions: [String] = []

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }
    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        var records: [ScoutRecord] = []
        let env = ProcessInfo.processInfo.environment

        // Shell
        if let shell = env["SHELL"] {
            records.append(ScoutRecord(
                sourceID: id, kind: .shellEnvironment, sensitivity: .low,
                content: "Shell: \(shell)"
            ))
        }

        // Detect common dev tools via PATH
        let knownTools = ["git", "swift", "python3", "node", "npm", "cargo", "docker",
                          "brew", "go", "ruby", "ffmpeg", "ripgrep", "jq", "gh"]
        var found: [String] = []
        for tool in knownTools {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [tool]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                found.append(tool)
            }
        }

        if !found.isEmpty {
            records.append(ScoutRecord(
                sourceID: id, kind: .shellEnvironment, sensitivity: .low,
                content: "Tools in PATH: \(found.joined(separator: ", "))"
            ))
        }

        return records
    }
}

// MARK: - Hermes import source

public struct HermesImportSource: ScoutSource {
    public let id = "hermes_import"
    public let displayName = "Hermes Agent Import"
    public let description = "Detect and preview import from ~/.hermes."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions = ["filesystem.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        let hermesDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".hermes")
        return FileManager.default.fileExists(atPath: hermesDir.path) ? .granted : .denied
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        try await checkPermission()
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        let fm = FileManager.default
        let hermesDir = fm.homeDirectoryForCurrentUser.appending(path: ".hermes")
        guard fm.fileExists(atPath: hermesDir.path) else { return [] }

        var records: [ScoutRecord] = []

        // Check what exists
        let possibleImports: [(String, String)] = [
            ("config.yaml", "Configuration"),
            ("memories", "Memories"),
            ("skills", "Skills"),
            ("sessions", "Session transcripts"),
            ("cron", "Cron jobs → workflow candidates"),
            (".env", "Credentials (⚠ requires confirmation)"),
        ]

        for (item, label) in possibleImports {
            let path = hermesDir.appending(path: item)
            if fm.fileExists(atPath: path.path) {
                records.append(ScoutRecord(
                    sourceID: id, kind: .hermesImport, sensitivity: item == ".env" ? .high : .medium,
                    content: "\(label): found at \(path.path)",
                    metadata: ["item": item, "path": path.path]
                ))
            }
        }

        return records
    }
}
