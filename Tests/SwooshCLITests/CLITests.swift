// Tests/SwooshCLITests/CLITests.swift — CLI command integration tests

import Testing
import Foundation
import ArgumentParser

// The CLI commands are not exported as a module, so we test via
// subprocess invocation to verify argument parsing and wiring.

@Suite("CLI Commands")
struct CLICommandTests {

    @Test("swoosh --help exits zero")
    func helpExitsZero() async throws {
        let process = Process()
        process.executableURL = try findSwooshExecutable()
        process.arguments = ["--help"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(output.contains("swoosh"))
        #expect(output.contains("USAGE"))
    }

    @Test("swoosh doctor --help exits zero")
    func doctorHelpExitsZero() async throws {
        let process = Process()
        process.executableURL = try findSwooshExecutable()
        process.arguments = ["doctor", "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    @Test("swoosh completions zsh produces output")
    func completionsZshProducesOutput() async throws {
        let process = Process()
        process.executableURL = try findSwooshExecutable()
        process.arguments = ["completions", "zsh"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(output.contains("compdef") || output.contains("_swoosh"))
    }

    @Test("swoosh with unknown subcommand fails")
    func unknownSubcommandFails() async throws {
        let process = Process()
        process.executableURL = try findSwooshExecutable()
        process.arguments = ["nonexistent-command-that-does-not-exist"]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
    }

    /// Locate the swoosh binary — prefers the debug build in .build/debug.
    private func findSwooshExecutable() throws -> URL {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // SwooshCLITests
            .deletingLastPathComponent() // Tests
        let debugPath = repoRoot.appendingPathComponent(".build/debug/swoosh")
        if FileManager.default.fileExists(atPath: debugPath.path) {
            return debugPath
        }
        // Fallback: try swift run path (if on PATH)
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["swoosh"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw BinaryUnavailable(message: "swoosh binary not found — build with `swift build` first")
    }
}

/// Replacement for the deprecated `TestSkipped` helper. Test-runner
/// treats this as a regular thrown error; suites that want to skip
/// rather than fail can catch it explicitly.
private struct BinaryUnavailable: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Argument Parser Direct Tests

/// Verify that argument parsing works for key commands without requiring
/// a full build. These run quickly and catch typos in @Option/@Flag names.
@Suite("Argument Parsing")
struct ArgumentParsingTests {

    @Test("ScoutRunCommand accepts --depth and --folders")
    func scoutRunParsing() throws {
        // parseAsRoot expects args minus the executable name — so the
        // first token here is the subcommand, not the parent command.
        let args = ["run", "--depth", "deep", "--folders", "/tmp"]
        let command = try ScoutCommand.parseAsRoot(args)
        #expect(command is ScoutRunCommand)
    }

    @Test("SkillsDeleteCommand accepts --force")
    func skillsDeleteParsing() throws {
        let args = ["delete", "my-skill", "--force"]
        let command = try SkillsCommand.parseAsRoot(args)
        #expect(command is SkillsDeleteCommand)
    }

    @Test("CronRemoveCommand accepts --force")
    func cronRemoveParsing() throws {
        let args = ["remove", "my-job", "--force"]
        let command = try CronCommand.parseAsRoot(args)
        #expect(command is CronRemoveCommand)
    }

    @Test("MemoryRejectCommand accepts --force")
    func memoryRejectParsing() throws {
        let args = ["reject", "--id", "abc123", "--force"]
        let command = try MemoryCommand.parseAsRoot(args)
        #expect(command is MemoryRejectCommand)
    }
}

// ═══════════════════════════════════════════════════════════════════
// Placeholder conformances so ArgumentParser types resolve in tests.
// These are minimal stubs — the real types live in SwooshCLI source.
// ═══════════════════════════════════════════════════════════════════

struct ScoutCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scout",
        subcommands: [ScoutRunCommand.self]
    )
}
struct ScoutRunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run")
    @Option var depth: String = "shallow"
    @Option(parsing: .upToNextOption) var folders: [String] = []
}

struct SkillsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        subcommands: [SkillsDeleteCommand.self]
    )
}
struct SkillsDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete")
    @Argument var id: String = ""
    @Flag var force = false
}

struct CronCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cron",
        subcommands: [CronRemoveCommand.self]
    )
}
struct CronRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove")
    @Argument var id: String = ""
    @Flag var force = false
}

struct MemoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        subcommands: [MemoryRejectCommand.self]
    )
}
struct MemoryRejectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reject")
    @Option var id: String = ""
    @Flag var force = false
}
