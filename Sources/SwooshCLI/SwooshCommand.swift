// SwooshCLI/SwooshCommand.swift — 0.6A CLI entry point + Doctor/Model/Daemon
//
// swoosh <subcommand>  — see subcommands below.
// The DaemonPair subcommand and its QR/IP helpers live in
// DaemonPairCommand.swift. All commissioning runtime (writeSetupReport,
// commissionLocalRuntime, etc) lives in SetupCommissioning.swift.
//
// 0.6A revision: the agent runtime is now hosted in-process by the macOS
// app (daemon→app merge), so there is no standalone `swooshd` binary and
// no launchd service. The `daemon install/start/stop/status` subcommands
// (which wrote a KeepAlive LaunchAgent pointing at /usr/local/bin/swooshd)
// were removed — launch/quit the app to start/stop the runtime. Only
// `daemon pair` remains.

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
        print("  4. Detour Cloud")
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
        abstract: "Pair an iPhone with the in-process agent runtime.",
        // The agent runtime is hosted in-process by the macOS app (see
        // App/SwooshApp.swift → SwooshDaemon.start). There is no standalone
        // `swooshd` binary and no launchd service, so the old
        // install/start/stop/status (launchd KeepAlive) subcommands were
        // removed — launch/quit the app to start/stop the runtime. `pair`
        // remains: it mints the bearer token / QR an iPhone uses to reach
        // the app-hosted HTTP API.
        subcommands: [DaemonPairCommand.self]
    )
}
