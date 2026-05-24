// SwooshCLI/SwooshCommand.swift — 0.5C CLI entry point + Doctor/Model/Daemon
//
// swoosh <subcommand>  — see subcommands below.
// The DaemonPair subcommand and its QR/IP helpers live in
// DaemonPairCommand.swift. All commissioning runtime (writeSetupReport,
// commissionLocalRuntime, etc) lives in SetupCommissioning.swift.
//
// 0.5B revision: `swoosh daemon install` no longer hardcodes
// `/usr/local/bin/swooshd` in the LaunchAgent plist. The binary path is
// resolved at install time (override → sibling-of-swoosh → $PATH →
// /usr/local/bin), and the command refuses to write a plist that points
// at a non-existent executable.
//
// 0.5C revision: Codacy follow-ups — rename `fm` → `fileManager`, wrap
// the >120-char `--swooshd-path` help string into `ArgumentHelp`, and
// extract the LaunchAgent plist template into a private constant so
// `makeLaunchAgentPlist` stays under the per-method LOC limit.

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
            GoalCommand.self,
            ManifestCommand.self,
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

    @Option(name: .customLong("swooshd-path"),
            help: ArgumentHelp(
                "Absolute path to the swooshd binary the LaunchAgent should run.",
                discussion: "If omitted, swoosh searches the swoosh sibling directory, $PATH, and /usr/local/bin."
            ))
    var swooshdPath: String?

    func run() async throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")

        guard let swooshd = DaemonInstallCommand.resolveSwooshdURL(override: swooshdPath) else {
            print("✗ Couldn't locate swooshd. Pass --swooshd-path <path>, or install swooshd")
            print("  (e.g. `swift build -c release` then `cp .build/release/swooshd /usr/local/bin/`)")
            print("  before running `swoosh daemon install`.")
            throw ExitCode.failure
        }

        // launchd opens StandardOutPath / StandardErrorPath at load time
        // and silently fails if the parent directory is missing — create
        // it up front so the agent can start cleanly on a fresh machine.
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".swoosh/logs")
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        let plist = DaemonInstallCommand.makeLaunchAgentPlist(swooshdPath: swooshd.path, logsDir: logsURL.path)

        try plist.write(to: plistPath, atomically: true, encoding: .utf8)
        print("✓ LaunchAgent installed at \(plistPath.path)")
        print("  swooshd: \(swooshd.path)")
        print("  Run `swoosh daemon start` to start.")
    }

    /// Resolve the absolute path to the swooshd binary the LaunchAgent
    /// should invoke. Precedence: `--swooshd-path` override → swooshd
    /// sibling next to the current swoosh binary → `$PATH` lookup via
    /// `/usr/bin/which` → `/usr/local/bin/swooshd` last-resort. Returns
    /// `nil` if no executable is found, so the caller can surface an
    /// actionable error instead of writing a plist that points at a
    /// non-existent path.
    static func resolveSwooshdURL(override: String?) -> URL? {
        let fileManager = FileManager.default

        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        // 1. Sibling of the currently-running swoosh binary.
        let invokedPath = CommandLine.arguments.first ?? ""
        let resolvedInvoked = URL(fileURLWithPath: invokedPath).standardizedFileURL
        let sibling = resolvedInvoked.deletingLastPathComponent().appendingPathComponent("swooshd")
        if fileManager.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        // 2. $PATH lookup via `which`.
        if let onPath = whichSwooshd() {
            return onPath
        }

        // 3. The legacy convention path.
        let legacy = URL(fileURLWithPath: "/usr/local/bin/swooshd")
        return fileManager.isExecutableFile(atPath: legacy.path) ? legacy : nil
    }

    /// `/usr/bin/which swooshd` — used as a fallback when the swooshd
    /// binary isn't a sibling of `swoosh`. Returns the resolved
    /// executable URL, or `nil` if `which` doesn't find it.
    private static func whichSwooshd() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["swooshd"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Build the LaunchAgent plist body. Extracted so tests can pin the
    /// generated XML without writing to `~/Library/LaunchAgents`. The
    /// body itself lives in `launchAgentPlistTemplate` so this method
    /// stays small enough for Codacy's per-method LOC limit.
    static func makeLaunchAgentPlist(swooshdPath: String, logsDir: String) -> String {
        launchAgentPlistTemplate
            .replacingOccurrences(of: "{SWOOSHD_PATH}", with: swooshdPath)
            .replacingOccurrences(of: "{LOGS_DIR}", with: logsDir)
    }

    /// LaunchAgent plist template with `{SWOOSHD_PATH}` / `{LOGS_DIR}`
    /// placeholders. Kept as a file-scoped constant so the multi-line
    /// literal doesn't blow the per-method LOC budget.
    private static let launchAgentPlistTemplate: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>ai.swoosh.daemon</string>
        <key>ProgramArguments</key>
        <array>
            <string>{SWOOSHD_PATH}</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>{LOGS_DIR}/swooshd.log</string>
        <key>StandardErrorPath</key>
        <string>{LOGS_DIR}/swooshd.err</string>
    </dict>
    </plist>
    """
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
