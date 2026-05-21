// SwooshConfig/ConfigStore.swift — Non-secret config and doctor diagnostics
//
// ~/.swoosh/config.yaml equivalent. Secrets go to Keychain, config goes here.

import Foundation

// MARK: - Config store

public struct SwooshConfigStore: Sendable {
    public let configDirectory: URL

    public init(configDirectory: URL? = nil) {
        self.configDirectory = configDirectory ??
            swooshHomeDirectoryForCurrentUser().appending(path: ".swoosh")
    }

    public var configFile: URL { configDirectory.appending(path: "config.json") }
    public var apiTokenFile: URL { configDirectory.appending(path: "api_token") }
    public var stateDB: URL { configDirectory.appending(path: "state.db") }
    public var memoriesDir: URL { configDirectory.appending(path: "memories") }
    public var skillsDir: URL { configDirectory.appending(path: "skills") }
    public var workflowsDir: URL { configDirectory.appending(path: "workflows") }
    public var goalsDir: URL { configDirectory.appending(path: "goals") }
    public var manifestingDir: URL { configDirectory.appending(path: "manifesting") }
    public var scoutDir: URL { configDirectory.appending(path: "scout") }
    public var cronDir: URL { configDirectory.appending(path: "cron") }
    public var logsDir: URL { configDirectory.appending(path: "logs") }
    public var artifactsDir: URL { configDirectory.appending(path: "artifacts") }
    public var mcpDir: URL { configDirectory.appending(path: "mcp") }
    public var workersDir: URL { configDirectory.appending(path: "workers") }
    public var setupReportsDir: URL { configDirectory.appending(path: "setup-reports") }
    public var modelsDir: URL { configDirectory.appending(path: "models") }
    public var checkpointsDir: URL { configDirectory.appending(path: "checkpoints") }
    public var themeFile: URL { configDirectory.appending(path: "theme.json") }

    public var requiredStateDirectories: [URL] {
        [configDirectory, memoriesDir, skillsDir, workflowsDir,
         goalsDir, manifestingDir, scoutDir, cronDir, logsDir,
         artifactsDir, mcpDir, workersDir, setupReportsDir,
         modelsDir, checkpointsDir]
    }

    /// Create all directories if needed.
    public func ensureDirectories() throws {
        for dir in requiredStateDirectories {
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
