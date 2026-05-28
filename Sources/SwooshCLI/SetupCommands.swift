// SwooshCLI/SetupCommands.swift — Setup command tree (commands only) — 0.4B
//
// `swoosh setup quick` and `swoosh setup full` are the two real flows;
// `developer` and `server` print profile-specific cheatsheets. Earlier
// placeholder subcommands (model/permissions/memory/gateway/tools/
// terminal/local-model/import-hermes) were stubs that print-only hints
// without doing any configuration — removed to stop advertising
// capability the CLI doesn't actually provide. Runtime helpers
// (commissionLocalRuntime, writeSetupReport, etc) live in
// SetupCommissioning.swift.

import ArgumentParser
import SwooshConfig
import SwooshScout
import SwooshTools
import Foundation

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Commission your Swoosh agent system.",
        subcommands: [
            SetupQuickCommand.self,
            SetupFullCommand.self,
            SetupDeveloperCommand.self,
            SetupServerCommand.self,
        ],
        defaultSubcommand: SetupQuickCommand.self
    )
}

struct SetupQuickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "quick", abstract: "Model + daemon + basic tools + smoke test.")

    @Flag(name: [.customLong("non-interactive"), .customLong("yes")], help: "Run with defaults and do not prompt.")
    var nonInteractive = false

    @Option(name: .customLong("model-path"), help: "Model path to write when running without prompts: local, cloud, or hybrid.")
    var requestedModelPath: SetupModelPath?

    @Option(name: .customLong("permission-profile"), help: "Permission profile to write when running without prompts: safe, developer, automation, power, or custom.")
    var requestedPermissionProfile: PermissionProfilePreset?

    @Option(name: .customLong("config-dir"), help: "State directory to configure instead of ~/.swoosh.")
    var configDirectory: String?

    @Option(name: .customLong("daemon-host"), help: "Daemon host to write and verify.")
    var daemonHost = "127.0.0.1"

    @Option(name: .customLong("daemon-port"), help: "Daemon port to write and verify.")
    var daemonPort = 8787

    @Option(name: .customLong("daemon-start-timeout"), help: "Seconds to wait for the app-hosted runtime to become ready.")
    var daemonStartTimeout: Double = 60

    func run() async throws {
        printBanner()
        print("Starting quick setup...\n")

        let hardware = HardwareDetector().detect()
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let ui = CLISetupUI()

        printPreflight(hardware)
        try config.ensureDirectories()
        print("✓ Created \(config.configDirectory.path) directory\n")

        let modelPath: SetupModelPath
        if let requestedModelPath {
            modelPath = requestedModelPath
        } else if nonInteractive {
            modelPath = .hybrid
        } else {
            print("─── Model Setup ───────────────────────────────")
            print("Choose primary model path:\n")
            print("  1. Local-first (MLX on Apple Silicon)")
            print("  2. Hybrid local + diagnostic fallback\n")

            let choice = await ui.askChoice("Select", options: ["local", "hybrid"], default: 1)
            modelPath = [SetupModelPath.local, .hybrid][choice]
        }
        print("✓ Model path: \(modelPath.rawValue)\n")

        let preset: PermissionProfilePreset
        if let requestedPermissionProfile {
            preset = requestedPermissionProfile
        } else if nonInteractive {
            preset = .developer
        } else {
            print("─── Permissions ───────────────────────────────")
            print("Choose permission profile:\n")
            print("  1. Safe — read-only, no shell, no app access")
            print("  2. Developer — file/git/shell with approval")
            print("  3. Automation — calendar, reminders, Shortcuts")
            print("  4. Power — full tool access, high-risk requires approval")
            print("  5. Trader — mainnet trading, every write requires human approval\n")

            let profiles: [PermissionProfilePreset] = [.safe, .developer, .automation, .power, .trader, .autonomous]
            let permChoice = await ui.askChoice("Select", options: profiles.map(\.rawValue), default: 1)
            preset = profiles[min(permChoice, profiles.count - 1)]
        }
        let _ = PermissionProfile.from(preset: preset)
        print("✓ Permission profile: \(preset.rawValue)\n")

        print("─── Commissioning ─────────────────────────────")
        let ctx = CommissioningContext(
            config: config,
            hardware: hardware,
            profile: preset,
            modelPath: modelPath,
            mode: "quick",
            daemonHost: daemonHost,
            daemonPort: daemonPort,
            daemonStartTimeout: daemonStartTimeout
        )
        let result = try await runCommissioning(ctx)
        printReadiness(result.commissioning.readiness)
        print()
        print("Setup report saved to \(result.reportPath.path)\n")
        print("✓ Quick setup complete.")
        printSetupNextSteps()
    }
}

struct SetupFullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "full", abstract: "Full commissioning.")

    @Flag(name: [.customLong("non-interactive"), .customLong("yes")], help: "Accepted for automation; full setup already runs without prompts.")
    var nonInteractive = false

    @Option(name: .customLong("config-dir"), help: "State directory to configure instead of ~/.swoosh.")
    var configDirectory: String?

    @Option(name: .customLong("daemon-host"), help: "Daemon host to write and verify.")
    var daemonHost = "127.0.0.1"

    @Option(name: .customLong("daemon-port"), help: "Daemon port to write and verify.")
    var daemonPort = 8787

    @Option(name: .customLong("daemon-start-timeout"), help: "Seconds to wait for the app-hosted runtime to become ready.")
    var daemonStartTimeout: Double = 60

    func run() async throws {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let hardware = HardwareDetector().detect()
        let scoutResult = try await ScoutPipeline(
            sources: ScoutSourceCatalog.operationalLocalSources()
        ).run(
            depth: .recommended,
            options: ScoutPipelineOptions(permissionMode: .skipUnavailable, minimumConfidence: 0.7)
        )
        let ctx = CommissioningContext(
            config: config,
            hardware: hardware,
            profile: .developer,
            modelPath: .hybrid,
            mode: "full",
            daemonHost: daemonHost,
            daemonPort: daemonPort,
            daemonStartTimeout: daemonStartTimeout
        )
        let result = try await runCommissioning(
            ctx,
            scoutSummary: "Scout collected \(scoutResult.recordsCollected) record(s) and generated \(scoutResult.candidatesGenerated) candidate(s)."
        )
        print("Full baseline complete.")
        printReadiness(result.commissioning.readiness, prefix: "  ")
        print("  ✓ Scout dry run: \(scoutResult.recordsCollected) record(s), \(scoutResult.candidatesGenerated) candidate(s)")
        print("Setup report saved to \(result.reportPath.path)")
        printSetupNextSteps()
    }
}

struct SetupDeveloperCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "developer", abstract: "Swift/Xcode/Git/SourceKit-LSP setup.")
    func run() async throws {
        let hardware = HardwareDetector().detect()
        printPreflight(hardware)
        print("Developer profile:")
        print("  swift build")
        print("  swift test")
        print("  xcodegen generate")
        print("  xcodebuild -project Swoosh.xcodeproj -scheme Swoosh -destination 'platform=macOS' build")
        print("  xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build")
    }
}

struct SetupServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "server", abstract: "CLI-only, env-based secrets.")
    func run() async throws {
        let config = SwooshConfigStore()
        try config.ensureDirectories()
        print("Server baseline ready at \(config.configDirectory.path)")
        print("Launch the Detour app — it hosts the bearer-gated agent runtime in-process and binds the LAN automatically.")
        print("Run `swoosh provider auth <provider> --api-key <key>` before expecting non-local diagnostic model responses.")
    }
}

enum SetupModelPath: String, Codable, CaseIterable, Sendable {
    case local
    case cloud
    case hybrid
}

extension SetupModelPath: ExpressibleByArgument {}

extension PermissionProfilePreset: ExpressibleByArgument {}
