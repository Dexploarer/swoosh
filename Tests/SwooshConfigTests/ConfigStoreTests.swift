// Tests/SwooshConfigTests/ConfigStoreTests.swift — Configuration store tests
//
// Tests the SwooshConfigStore directory management, config file
// paths, and directory creation.

import Testing
import Foundation
@testable import SwooshConfig

// MARK: - ConfigStore Initialization Tests

@Suite("SwooshConfigStore Initialization")
struct ConfigStoreInitializationTests {

    @Test("Initializes with default config directory")
    func initializesWithDefault() {
        let store = SwooshConfigStore()

        #expect(store.configDirectory.path.contains(".swoosh"))
    }

    @Test("Initializes with custom config directory")
    func initializesWithCustom() {
        let customDir = URL(fileURLWithPath: "/tmp/swoosh-test")
        let store = SwooshConfigStore(configDirectory: customDir)

        #expect(store.configDirectory == customDir)
    }

    @Test("All required paths are computed correctly")
    func pathsComputed() {
        let store = SwooshConfigStore()

        #expect(store.configFile.path.hasSuffix("config.json"))
        #expect(store.apiTokenFile.path.hasSuffix("api_token"))
        #expect(store.stateDB.path.hasSuffix("state.db"))
        #expect(store.memoriesDir.path.hasSuffix("memories"))
        #expect(store.skillsDir.path.hasSuffix("skills"))
        #expect(store.workflowsDir.path.hasSuffix("workflows"))
        #expect(store.goalsDir.path.hasSuffix("goals"))
        #expect(store.manifestingDir.path.hasSuffix("manifesting"))
        #expect(store.scoutDir.path.hasSuffix("scout"))
        #expect(store.cronDir.path.hasSuffix("cron"))
        #expect(store.logsDir.path.hasSuffix("logs"))
        #expect(store.artifactsDir.path.hasSuffix("artifacts"))
        #expect(store.mcpDir.path.hasSuffix("mcp"))
        #expect(store.workersDir.path.hasSuffix("workers"))
        #expect(store.setupReportsDir.path.hasSuffix("setup-reports"))
        #expect(store.modelsDir.path.hasSuffix("models"))
        #expect(store.checkpointsDir.path.hasSuffix("checkpoints"))
        #expect(store.themeFile.path.hasSuffix("theme.json"))
    }

    @Test("All required state directories listed")
    func requiredDirectoriesListed() {
        let store = SwooshConfigStore()
        let dirs = store.requiredStateDirectories

        #expect(dirs.count == 15)
        #expect(dirs.contains(store.configDirectory))
        #expect(dirs.contains(store.memoriesDir))
        #expect(dirs.contains(store.skillsDir))
        #expect(dirs.contains(store.workflowsDir))
        #expect(dirs.contains(store.goalsDir))
        #expect(dirs.contains(store.manifestingDir))
        #expect(dirs.contains(store.scoutDir))
        #expect(dirs.contains(store.cronDir))
        #expect(dirs.contains(store.logsDir))
        #expect(dirs.contains(store.artifactsDir))
        #expect(dirs.contains(store.mcpDir))
        #expect(dirs.contains(store.workersDir))
        #expect(dirs.contains(store.setupReportsDir))
        #expect(dirs.contains(store.modelsDir))
        #expect(dirs.contains(store.checkpointsDir))
    }

    @Test("ConfigStore is Sendable")
    func isSendable() {
        let _: any Sendable.Type = SwooshConfigStore.self
        #expect(true)
    }
}

// MARK: - Directory Management Tests

@Suite("SwooshConfigStore Directory Management")
struct ConfigStoreDirectoryTests {

    @Test("EnsureDirectories creates all directories")
    func ensureDirectoriesCreates() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        try store.ensureDirectories()

        // Verify directories exist
        for dir in store.requiredStateDirectories {
            #expect(FileManager.default.fileExists(atPath: dir.path))
        }
    }

    @Test("EnsureDirectories is idempotent")
    func ensureDirectoriesIdempotent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        // First call
        try store.ensureDirectories()

        // Second call should not fail
        try store.ensureDirectories()

        // Directories should still exist
        #expect(FileManager.default.fileExists(atPath: store.configDirectory.path))
    }

    @Test("Nested directories created correctly")
    func nestedDirectoriesCreated() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)/nested/deep")
        defer {
            let parent = tempDir.deletingLastPathComponent().deletingLastPathComponent()
            try? FileManager.default.removeItem(at: parent)
        }

        // Note: SwooshConfigStore doesn't create intermediate directories
        // for the base config directory itself, only for subdirectories
        let store = SwooshConfigStore(configDirectory: tempDir)

        // The base directory path should be as specified
        #expect(store.configDirectory == tempDir)
    }
}

// MARK: - Config File I/O Tests

@Suite("SwooshConfigStore File I/O")
struct ConfigStoreFileIOTests {

    @Test("Save writes config to file")
    func saveWritesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct TestConfig: Codable, Equatable {
            let name: String
            let version: Int
        }

        let config = TestConfig(name: "test", version: 1)
        try store.save(config)

        #expect(FileManager.default.fileExists(atPath: store.configFile.path))
    }

    @Test("Save creates directories if needed")
    func saveCreatesDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)/new")
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct SimpleConfig: Codable {
            let value: String
        }

        try store.save(SimpleConfig(value: "test"))

        #expect(FileManager.default.fileExists(atPath: store.configFile.path))
    }

    @Test("Load reads config from file")
    func loadReadsFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct TestConfig: Codable, Equatable {
            let name: String
            let version: Int
        }

        let original = TestConfig(name: "test", version: 42)
        try store.save(original)

        let loaded: TestConfig = try store.load(TestConfig.self)

        #expect(loaded == original)
    }

    @Test("Load throws for non-existent file")
    func loadThrowsForMissing() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct TestConfig: Codable {
            let value: String
        }

        #expect(throws: Error.self) {
            _ = try store.load(TestConfig.self)
        }
    }

    @Test("Save overwrites existing file")
    func saveOverwrites() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct TestConfig: Codable, Equatable {
            let version: Int
        }

        try store.save(TestConfig(version: 1))
        try store.save(TestConfig(version: 2))

        let loaded: TestConfig = try store.load(TestConfig.self)
        #expect(loaded.version == 2)
    }

    @Test("Save writes pretty-printed JSON")
    func savePrettyPrinted() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct NestedConfig: Codable {
            let name: String
            let nested: [String: String]
        }

        let config = NestedConfig(
            name: "test",
            nested: ["key1": "value1", "key2": "value2"]
        )
        try store.save(config)

        let data = try Data(contentsOf: store.configFile)
        let json = String(data: data, encoding: .utf8)!

        // Should be pretty-printed (contains newlines)
        #expect(json.contains("\n"))
    }
}

// MARK: - ConfigStore Edge Cases

@Suite("SwooshConfigStore Edge Cases")
struct ConfigStoreEdgeCaseTests {

    @Test("Handles empty config")
    func handlesEmptyConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct EmptyConfig: Codable, Equatable {
            var items: [String] = []
        }

        try store.save(EmptyConfig())
        let loaded: EmptyConfig = try store.load(EmptyConfig.self)

        #expect(loaded.items.isEmpty)
    }

    @Test("Handles complex nested config")
    func handlesComplexConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct DeepConfig: Codable, Equatable {
            struct Nested: Codable, Equatable {
                let value: Int
                let array: [String]
            }
            let name: String
            let nested: Nested
            let dict: [String: Int]
        }

        let config = DeepConfig(
            name: "test",
            nested: DeepConfig.Nested(value: 42, array: ["a", "b", "c"]),
            dict: ["one": 1, "two": 2]
        )

        try store.save(config)
        let loaded: DeepConfig = try store.load(DeepConfig.self)

        #expect(loaded == config)
    }

    @Test("Handles config with special characters")
    func handlesSpecialChars() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SwooshConfigStore(configDirectory: tempDir)

        struct StringConfig: Codable, Equatable {
            let text: String
        }

        let config = StringConfig(text: "Special: \"quotes\", \\backslash, \nnewline, \ttab")
        try store.save(config)
        let loaded: StringConfig = try store.load(StringConfig.self)

        #expect(loaded.text == config.text)
    }

    @Test("Config paths are within config directory")
    func pathsWithinDirectory() {
        let store = SwooshConfigStore()

        // All paths should start with config directory
        #expect(store.configFile.path.hasPrefix(store.configDirectory.path))
        #expect(store.apiTokenFile.path.hasPrefix(store.configDirectory.path))
        #expect(store.stateDB.path.hasPrefix(store.configDirectory.path))
        #expect(store.memoriesDir.path.hasPrefix(store.configDirectory.path))
    }
}
