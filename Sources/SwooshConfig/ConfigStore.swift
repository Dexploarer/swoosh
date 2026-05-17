// SwooshConfig/ConfigStore.swift — Non-secret config and doctor diagnostics
//
// ~/.swoosh/config.yaml equivalent. Secrets go to Keychain, config goes here.

import Foundation

// MARK: - Config store

public struct SwooshConfigStore: Sendable {
    public let configDirectory: URL

    public init(configDirectory: URL? = nil) {
        self.configDirectory = configDirectory ??
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".swoosh")
    }

    public var configFile: URL { configDirectory.appending(path: "config.json") }
    public var stateDB: URL { configDirectory.appending(path: "state.db") }
    public var memoriesDir: URL { configDirectory.appending(path: "memories") }
    public var skillsDir: URL { configDirectory.appending(path: "skills") }
    public var workflowsDir: URL { configDirectory.appending(path: "workflows") }
    public var logsDir: URL { configDirectory.appending(path: "logs") }
    public var artifactsDir: URL { configDirectory.appending(path: "artifacts") }
    public var mcpDir: URL { configDirectory.appending(path: "mcp") }
    public var workersDir: URL { configDirectory.appending(path: "workers") }
    public var setupReportsDir: URL { configDirectory.appending(path: "setup-reports") }
    public var themeFile: URL { configDirectory.appending(path: "theme.json") }

    /// Create all directories if needed.
    public func ensureDirectories() throws {
        let dirs = [configDirectory, memoriesDir, skillsDir, workflowsDir,
                    logsDir, artifactsDir, mcpDir, workersDir, setupReportsDir]
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Load config from disk.
    public func load<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Save config to disk.
    public func save<T: Encodable>(_ value: T) throws {
        try ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: configFile, options: .atomic)
    }
}

// MARK: - Doctor diagnostics

public struct DoctorResult: Sendable {
    public struct Check: Sendable {
        public let category: String
        public let name: String
        public let status: CheckStatus
        public let fix: String?

        public init(category: String, name: String, status: CheckStatus, fix: String? = nil) {
            self.category = category
            self.name = name
            self.status = status
            self.fix = fix
        }
    }

    public enum CheckStatus: Sendable {
        case passed(details: String)
        case warning(message: String)
        case failed(error: String)
    }

    public let checks: [Check]
    public let timestamp: Date

    public var allPassed: Bool {
        checks.allSatisfy {
            if case .passed = $0.status { return true }
            if case .warning = $0.status { return true }
            return false
        }
    }

    public var failures: [Check] {
        checks.filter { if case .failed = $0.status { return true }; return false }
    }
}

/// Run comprehensive diagnostics.
public struct SwooshDoctor {
    public let config: SwooshConfigStore
    public let credentials: CredentialStore
    public let hardware: HardwareProfile

    public init(config: SwooshConfigStore, credentials: CredentialStore, hardware: HardwareProfile) {
        self.config = config
        self.credentials = credentials
        self.hardware = hardware
    }

    public func runAll() async -> DoctorResult {
        var checks: [DoctorResult.Check] = []

        // System checks
        checks.append(DoctorResult.Check(
            category: "System",
            name: "Apple Silicon",
            status: hardware.hasAppleSilicon
                ? .passed(details: hardware.cpuName)
                : .warning(message: "Intel detected — local MLX models may be slow or unavailable")
        ))

        checks.append(DoctorResult.Check(
            category: "System",
            name: "Memory",
            status: hardware.totalMemoryGB >= 8
                ? .passed(details: "\(Int(hardware.totalMemoryGB)) GB unified memory")
                : .warning(message: "Less than 8 GB — local models may not fit")
        ))

        checks.append(DoctorResult.Check(
            category: "System",
            name: "Disk space",
            status: hardware.availableDiskGB >= 10
                ? .passed(details: "\(Int(hardware.availableDiskGB)) GB available")
                : .warning(message: "Low disk space — model downloads may fail")
        ))

        checks.append(DoctorResult.Check(
            category: "System",
            name: "Git",
            status: hardware.hasGit
                ? .passed(details: "Installed")
                : .failed(error: "Git not found"),
            fix: "Install Xcode Command Line Tools: xcode-select --install"
        ))

        checks.append(DoctorResult.Check(
            category: "System",
            name: "Xcode Tools",
            status: hardware.hasXcodeTools
                ? .passed(details: "Installed")
                : .warning(message: "Not found — some developer tools won't work"),
            fix: "xcode-select --install"
        ))

        // Directory checks
        let fm = FileManager.default
        checks.append(DoctorResult.Check(
            category: "Config",
            name: "Swoosh directory",
            status: fm.fileExists(atPath: config.configDirectory.path)
                ? .passed(details: config.configDirectory.path)
                : .failed(error: "~/.swoosh not found"),
            fix: "Run: swoosh setup quick"
        ))

        checks.append(DoctorResult.Check(
            category: "Config",
            name: "Config file",
            status: fm.fileExists(atPath: config.configFile.path)
                ? .passed(details: "Found")
                : .warning(message: "No config file — using defaults"),
            fix: "Run: swoosh setup quick"
        ))

        // Credential checks
        let providerKeys = (try? await credentials.listKeys(service: "ai.swoosh.providers")) ?? []
        checks.append(DoctorResult.Check(
            category: "Model",
            name: "Provider credentials",
            status: providerKeys.isEmpty
                ? .failed(error: "No provider API keys configured")
                : .passed(details: "\(providerKeys.count) provider(s) configured"),
            fix: "Run: swoosh model"
        ))

        // Local model checks
        let localModels = hardware.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
        checks.append(DoctorResult.Check(
            category: "Model",
            name: "Local MLX capacity",
            status: hardware.hasAppleSilicon && !localModels.isEmpty
                ? .passed(details: "Can run: \(localModels.map(\.sizeLabel).joined(separator: ", "))")
                : .warning(message: "No recommended local models for this hardware")
        ))

        // Daemon check
        checks.append(checkDaemon())

        // Keychain access
        do {
            _ = try await credentials.listKeys(service: "ai.swoosh.test")
            checks.append(DoctorResult.Check(
                category: "Security",
                name: "Keychain access",
                status: .passed(details: "Readable")
            ))
        } catch {
            checks.append(DoctorResult.Check(
                category: "Security",
                name: "Keychain access",
                status: .failed(error: error.localizedDescription),
                fix: "Check Keychain Access.app permissions"
            ))
        }

        // Optional tools
        checks.append(DoctorResult.Check(
            category: "Optional",
            name: "Docker",
            status: hardware.hasDocker
                ? .passed(details: "Installed")
                : .warning(message: "Not installed — only needed for sandboxed terminal")
        ))

        checks.append(DoctorResult.Check(
            category: "Optional",
            name: "Node.js",
            status: hardware.hasNode
                ? .passed(details: "Installed")
                : .warning(message: "Not installed — only needed for Node MCP servers")
        ))

        checks.append(DoctorResult.Check(
            category: "Optional",
            name: "Python",
            status: hardware.hasPython
                ? .passed(details: "Installed")
                : .warning(message: "Not installed — only needed for Python worker tools")
        ))

        return DoctorResult(checks: checks, timestamp: Date())
    }

    private func checkDaemon() -> DoctorResult.Check {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")

        if FileManager.default.fileExists(atPath: launchAgentPath.path) {
            return DoctorResult.Check(
                category: "Daemon",
                name: "swooshd LaunchAgent",
                status: .passed(details: "Installed")
            )
        } else {
            return DoctorResult.Check(
                category: "Daemon",
                name: "swooshd LaunchAgent",
                status: .failed(error: "Not installed"),
                fix: "Run: swoosh daemon install"
            )
        }
    }
}
