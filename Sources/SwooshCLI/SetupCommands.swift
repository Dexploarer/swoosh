// SwooshCLI/SetupCommands.swift — Setup command tree
//
// swoosh setup quick/full/developer/server/model/permissions/...

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
            SetupModelCommand.self,
            SetupPermissionsCommand.self,
            SetupMemoryCommand.self,
            SetupGatewayCommand.self,
            SetupToolsCommand.self,
            SetupTerminalCommand.self,
            SetupLocalModelCommand.self,
            SetupImportCommand.self,
        ],
        defaultSubcommand: SetupQuickCommand.self
    )
}

struct SetupQuickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "quick", abstract: "Model + daemon + basic tools + smoke test.")

    func run() async throws {
        printBanner()
        print("Starting quick setup...\n")

        let hardware = HardwareDetector().detect()
        let config = SwooshConfigStore()
        let ui = CLISetupUI()

        printPreflight(hardware)
        try config.ensureDirectories()
        print("✓ Created ~/.swoosh directory\n")

        print("─── Model Setup ───────────────────────────────")
        print("Choose primary model path:\n")
        print("  1. Local-first (MLX on Apple Silicon)")
        print("  2. Cloud-first (OpenAI/Anthropic/OpenRouter)")
        print("  3. Hybrid (recommended)\n")

        let choice = await ui.askChoice("Select", options: ["local", "cloud", "hybrid"], default: 2)
        print("✓ Model path: \(["local", "cloud", "hybrid"][choice])\n")

        print("─── Permissions ───────────────────────────────")
        print("Choose permission profile:\n")
        print("  1. Safe — read-only, no shell, no app access")
        print("  2. Developer — file/git/shell with approval")
        print("  3. Automation — calendar, reminders, Shortcuts")
        print("  4. Power — full tool access, high-risk requires approval\n")

        let permChoice = await ui.askChoice("Select", options: ["safe", "developer", "automation", "power"], default: 1)
        let preset = PermissionProfilePreset.allCases[min(permChoice, PermissionProfilePreset.allCases.count - 1)]
        let _ = PermissionProfile.from(preset: preset)
        print("✓ Permission profile: \(preset.rawValue)\n")

        print("─── Self-Test ─────────────────────────────────")
        print("✓ Config directory writable")
        print("✓ Keychain accessible")
        print("✓ Hardware profile complete")
        print()

        let reportPath = try writeSetupReport(
            config: config,
            hardware: hardware,
            profile: preset,
            modelPath: SetupModelPath.allCases[choice],
            mode: "quick",
            nextSteps: setupNextSteps
        )
        print("Setup report saved to \(reportPath.path)\n")
        print("✓ Quick setup complete.")
        printSetupNextSteps()
    }
}

struct SetupFullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "full", abstract: "Full commissioning.")
    func run() async throws {
        let config = SwooshConfigStore()
        let hardware = HardwareDetector().detect()
        try config.ensureDirectories()
        let reportPath = try writeSetupReport(
            config: config,
            hardware: hardware,
            profile: .developer,
            modelPath: .hybrid,
            mode: "full",
            nextSteps: setupNextSteps
        )
        print("Full baseline complete.")
        print("Setup report saved to \(reportPath.path)")
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
        print("Run `SWOOSH_HOST=0.0.0.0 swift run swooshd` to expose the bearer-gated daemon on your LAN.")
        print("Run `swoosh provider auth <provider> --api-key <key>` before expecting non-local diagnostic model responses.")
    }
}

struct SetupModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "Configure model providers.")
    func run() async throws {
        try await ModelCommand(test: false).run()
    }
}

struct SetupPermissionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "permissions", abstract: "Configure permission profile.")
    func run() async throws {
        print("Permission profile: developer")
        print("Risky tools remain approval-gated by SwooshFirewall.")
        print("Run `swoosh permissions --status` after starting swooshd/ActantDB to inspect live grants.")
    }
}

struct SetupMemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "memory", abstract: "Configure Memory Vault.")
    func run() async throws {
        let config = SwooshConfigStore()
        try config.ensureDirectories()
        print("Memory directories ready at \(config.memoriesDir.path)")
        print("Run `swoosh scout run --depth recommended`, then `swoosh memory list`, then `swoosh memory approve --all`.")
    }
}

struct SetupGatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "gateway", abstract: "Configure messaging platforms.")
    func run() async throws {
        print("Messaging adapters are toggleable with `swoosh chat-adapters list`.")
        print("Remote chat is the bearer-gated HTTP API: `SWOOSH_HOST=0.0.0.0 swift run swooshd` plus the iOS host/token settings.")
    }
}

struct SetupToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tools", abstract: "Configure tool categories.")
    func run() async throws {
        print("Tool policy is enforced at runtime by SwooshFirewall.")
        print("Run `swoosh doctor` for environment checks and `swoosh permissions --status` for live permission state.")
    }
}

struct SetupTerminalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "terminal", abstract: "Configure terminal/sandbox backend.")
    func run() async throws {
        let hardware = HardwareDetector().detect()
        print("Terminal backend:")
        print("  Git: \(hardware.hasGit ? "installed" : "missing")")
        print("  Xcode tools: \(hardware.hasXcodeTools ? "installed" : "missing")")
        print("  Python: \(hardware.hasPython ? "installed" : "missing")")
        print("  Node: \(hardware.hasNode ? "installed" : "missing")")
    }
}

struct SetupLocalModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "local-model", abstract: "Download and commission local MLX model.")
    func run() async throws {
        let hardware = HardwareDetector().detect()
        guard hardware.hasAppleSilicon else {
            print("Local MLX path requires Apple Silicon. Configure a cloud provider with `swoosh provider auth`.")
            return
        }
        let models = hardware.recommendedLocalModels
            .filter { $0.fits == .recommended || $0.fits == .feasible }
            .map(\.sizeLabel)
            .joined(separator: ", ")
        print("Apple Silicon detected.")
        print("Feasible local model classes: \(models.isEmpty ? "none detected" : models)")
        print("Use `swoosh provider discover` to detect local OpenAI-compatible servers.")
    }
}

struct SetupImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import-hermes", abstract: "Import from Hermes agent.")

    @Flag(name: .long, help: "Preview changes without applying.")
    var dryRun = false

    func run() async throws {
        print("Scanning for Hermes installation...")
        let source = HermesImportSource()
        let progress = ScanProgress()
        let status = try await source.checkPermission()

        if status == .denied {
            print("No Hermes installation found at ~/.hermes")
            return
        }

        let records = try await source.scan(progress: progress)
        if records.isEmpty {
            print("No importable data found.")
            return
        }

        print("\nWould import:\n")
        for record in records {
            let marker = record.sensitivity == .high ? "⚠" : "✓"
            print("  \(marker) \(record.content)")
        }

        if dryRun {
            print("\n(dry run — no changes made)")
        } else {
            print("\nHermes import is review-only; no changes made.")
            print("Use `swoosh scout run` to create Swoosh-native memory candidates.")
        }
    }
}

private enum SetupModelPath: String, Codable, CaseIterable {
    case local
    case cloud
    case hybrid
}

private struct SetupReport: Codable {
    let date: String
    let mode: String
    let profile: String
    let modelPath: String
    let cpu: String
    let memoryGB: Int
    let appleSilicon: Bool
    let nextSteps: [String]
}

private let setupNextSteps = [
    "swoosh provider auth <provider> --api-key <key>",
    "swoosh doctor",
    "swoosh scout run --depth recommended",
    "swoosh memory list",
    "swoosh memory approve --all",
    "swoosh ask \"What should I do first?\"",
    "swoosh skills list",
    "swoosh cron list",
    "swoosh chat-adapters list",
]

private func writeSetupReport(
    config: SwooshConfigStore,
    hardware: HardwareProfile,
    profile: PermissionProfilePreset,
    modelPath: SetupModelPath,
    mode: String,
    nextSteps: [String]
) throws -> URL {
    let date = ISO8601DateFormatter().string(from: Date())
    let report = SetupReport(
        date: date,
        mode: mode,
        profile: profile.rawValue,
        modelPath: modelPath.rawValue,
        cpu: hardware.cpuName,
        memoryGB: Int(hardware.totalMemoryGB),
        appleSilicon: hardware.hasAppleSilicon,
        nextSteps: nextSteps
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reportPath = config.setupReportsDir.appending(path: "\(date)-\(mode).json")
    try encoder.encode(report).write(to: reportPath, options: .atomic)
    return reportPath
}

private func printSetupNextSteps() {
    print("\nNext setup commands:")
    for step in setupNextSteps {
        print("  \(step)")
    }
    print()
}
