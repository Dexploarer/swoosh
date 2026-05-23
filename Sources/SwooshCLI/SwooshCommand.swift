// SwooshCLI/SwooshCommand.swift — 0.5A CLI entry point + Doctor/Model/Daemon
//
// swoosh <subcommand>  — see subcommands below.
// The DaemonPair subcommand and its QR/IP helpers live in
// DaemonPairCommand.swift. All commissioning runtime (writeSetupReport,
// commissionLocalRuntime, etc) lives in SetupCommissioning.swift.

import ArgumentParser
import SwooshKit
import SwooshConfig
import SwooshDoctor
import SwooshProviders
import SwooshSecrets
import SwooshTools
import SwooshChatSDK
import Foundation

/// Root `swoosh` command tree. `public` so the thin `SwooshCLIRunner`
/// executable target can invoke `await SwooshCommand.main()`. Subcommands
/// stay internal — tests reach them via `@testable import SwooshCLI`.
public struct SwooshCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swoosh",
        abstract: "Swift-native autonomous agent runtime.",
        version: "0.1.0",
        subcommands: [
            SetupCommand.self,
            AskCommand.self,
            DoctorCommand.self,
            ScoutCommand.self,
            MemoryCommand.self,
            ModelCommand.self,
            DaemonCommand.self,
            ChatCommand.self,
            SelfTestCommand.self,
            PermissionsCommand.self,
            ProviderCommand.self,
            SkillsCommand.self,
            CronCommand.self,
            TerminalCommand.self,
            ChatAdaptersCommand.self,
            PluginCommand.self,
            CompletionsCommand.self,
        ],
        defaultSubcommand: ChatCommand.self
    )

    public init() {}
}

// MARK: - Model

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "Configure model providers.")

    @Flag(name: .long, help: "Test the current model configuration.")
    var test = false

    func run() async throws {
        if test {
            try await runProviderTests(provider: nil)
            return
        }

        print("Model provider setup\n")
        print("Recommended:")
        print("  1. Local MLX")
        print("  2. OpenAI")
        print("  3. OpenRouter")
        print("  4. Eliza Cloud")
        print("\nAlready detected:")

        let hardware = HardwareDetector().detect()
        if hardware.hasAppleSilicon {
            let localModels = hardware.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
            print("  ✓ Apple Silicon — can run: \(localModels.map(\.sizeLabel).joined(separator: ", "))")
        }
        print("")
        try await ProviderListCommand().run()
    }
}

// MARK: - Daemon

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage swooshd daemon.",
        subcommands: [DaemonInstallCommand.self, DaemonStartCommand.self, DaemonStopCommand.self, DaemonStatusCommand.self, DaemonPairCommand.self]
    )
}

struct DaemonInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install swooshd LaunchAgent.")
    func run() async throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>ai.swoosh.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/swooshd</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.swoosh/logs/swooshd.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.swoosh/logs/swooshd.err</string>
        </dict>
        </plist>
        """

        try plist.write(to: plistPath, atomically: true, encoding: .utf8)
        print("✓ LaunchAgent installed at \(plistPath.path)")
        print("  Run `swoosh daemon start` to start.")
    }
}

struct DaemonStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start swooshd.")
    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w",
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist").path]
        try process.run()
        process.waitUntilExit()
        print(process.terminationStatus == 0 ? "✓ swooshd started" : "✗ Failed to start swooshd")
    }
}

struct DaemonStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop swooshd.")
    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload",
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist").path]
        try process.run()
        process.waitUntilExit()
        print(process.terminationStatus == 0 ? "✓ swooshd stopped" : "✗ Failed to stop swooshd")
    }
}

struct DaemonStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Check swooshd status.")
    func run() async throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("✗ LaunchAgent not installed")
            print("  Run: swoosh daemon install")
            return
        }
        print("✓ LaunchAgent installed")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", "ai.swoosh.daemon"]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        print(process.terminationStatus == 0 ? "✓ swooshd is running" : "○ swooshd is not running\n  Run: swoosh daemon start")
    }
}
