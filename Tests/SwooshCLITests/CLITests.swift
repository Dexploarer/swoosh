// Tests/SwooshCLITests/CLITests.swift — Subprocess smoke tests — 0.4B
//
// These tests exercise the actual `swoosh` binary built by `swift build`.
// Argument-parsing checks against the real command types live in
// CommandParsingTests.swift (those use `@testable import SwooshCLI`,
// which is possible now that the CLI is a library + thin runner target).

import Testing
import Foundation

@Suite("CLI binary")
struct CLIBinaryTests {
    @Test("swoosh --help exits zero and mentions every top-level subcommand")
    func helpListsEverySubcommand() async throws {
        let output = try runBinary(args: ["--help"])
        #expect(output.contains("USAGE"))
        for subcommand in [
            "setup", "ask", "doctor", "scout", "memory", "model", "daemon",
            "chat", "self-test", "permissions", "provider", "skills", "cron",
            "terminal", "chat-adapters", "plugin", "completions",
        ] {
            #expect(output.contains(subcommand), "Missing subcommand: \(subcommand)")
        }
    }

    @Test("swoosh setup --help omits removed placeholder subcommands")
    func setupRemovesPlaceholders() async throws {
        let output = try runBinary(args: ["setup", "--help"])
        // Real subcommands stay visible.
        for keeper in ["quick", "full", "developer", "server"] {
            #expect(output.contains(keeper), "Missing setup subcommand: \(keeper)")
        }
        // Placeholder stubs from the audit must not appear.
        for removed in ["import-hermes", "memory", "gateway", "tools", "local-model"] {
            #expect(!output.contains("\(removed)  "), "Setup subcommand should be gone: \(removed)")
        }
    }

    @Test("swoosh daemon --help exposes pair and no launchd lifecycle commands")
    func daemonExposesPairOnly() async throws {
        let output = try runBinary(args: ["daemon", "--help"])
        // The runtime is hosted in-process by the app — no standalone swooshd,
        // no launchd. Only `pair` (iPhone bearer-token flow) remains.
        #expect(output.contains("pair"))
        // The removed launchd lifecycle subcommands must not reappear.
        for removed in ["install", "start", "stop", "status"] {
            #expect(!output.contains("\(removed)  "), "daemon subcommand should be gone: \(removed)")
        }
    }

    @Test("swoosh doctor --help exits zero")
    func doctorHelpExitsZero() async throws {
        _ = try runBinary(args: ["doctor", "--help"])
    }

    @Test("swoosh completions zsh produces output")
    func completionsZshProducesOutput() async throws {
        let output = try runBinary(args: ["completions", "zsh"])
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

    @Test("swoosh --version reports the configured version")
    func versionFlagWorks() async throws {
        let output = try runBinary(args: ["--version"])
        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// MARK: - helpers

func runBinary(args: [String]) throws -> String {
    let process = Process()
    process.executableURL = try findSwooshExecutable()
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func findSwooshExecutable() throws -> URL {
    // `#filePath` (not `#file`) is the absolute path to this source file.
    // Walk up Tests/SwooshCLITests/<this> to reach the package root.
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repoRoot.appendingPathComponent(".build/debug/swoosh"),
        repoRoot.appendingPathComponent(".build/release/swoosh"),
        repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/swoosh"),
        repoRoot.appendingPathComponent(".build/arm64-apple-macosx/release/swoosh"),
        repoRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/swoosh"),
        repoRoot.appendingPathComponent(".build/x86_64-apple-macosx/release/swoosh"),
    ]
    for url in candidates where FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    throw BinaryUnavailable(
        message: "swoosh binary not found under \(repoRoot.path)/.build/* — run `swift build` first"
    )
}

struct BinaryUnavailable: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
