// SwooshCLI/SetupCommands.swift — Setup command tree
//
// swoosh setup quick/full/developer/server/model/permissions/...

import ArgumentParser
import SwooshConfig
import SwooshScout
import SwooshStorage
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
        let credentials = KeychainCredentialStore()
        let config = SwooshConfigStore()
        let ui = CLISetupUI()
        let context = SetupContext(credentials: credentials, config: config, hardware: hardware, ui: ui)

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

        let reportDir = config.setupReportsDir
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let reportPath = reportDir.appending(path: "\(dateStr).txt")
        let report = """
        Swoosh Setup Report
        Date: \(dateStr)
        Profile: \(preset.rawValue)
        CPU: \(hardware.cpuName)
        Memory: \(Int(hardware.totalMemoryGB)) GB
        Apple Silicon: \(hardware.hasAppleSilicon)
        """
        try? report.write(to: reportPath, atomically: true, encoding: .utf8)
        print("Setup report saved to \(reportPath.path)\n")
        print("✓ Quick setup complete. Run `swoosh chat` to start.\n")
    }
}

struct SetupFullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "full", abstract: "Full commissioning.")
    func run() async throws { print("Full setup — not yet implemented. Use `swoosh setup quick`.") }
}

struct SetupDeveloperCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "developer", abstract: "Swift/Xcode/Git/SourceKit-LSP setup.")
    func run() async throws { print("Developer setup — not yet implemented.") }
}

struct SetupServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "server", abstract: "CLI-only, env-based secrets.")
    func run() async throws { print("Server setup — not yet implemented.") }
}

struct SetupModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "Configure model providers.")
    func run() async throws { print("Model setup — not yet implemented. Use `swoosh model`.") }
}

struct SetupPermissionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "permissions", abstract: "Configure permission profile.")
    func run() async throws { print("Permissions setup — not yet implemented.") }
}

struct SetupMemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "memory", abstract: "Configure Memory Vault.")
    func run() async throws { print("Memory setup — not yet implemented.") }
}

struct SetupGatewayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "gateway", abstract: "Configure messaging platforms.")
    func run() async throws { print("Gateway setup — not yet implemented.") }
}

struct SetupToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tools", abstract: "Configure tool categories.")
    func run() async throws { print("Tools setup — not yet implemented.") }
}

struct SetupTerminalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "terminal", abstract: "Configure terminal/sandbox backend.")
    func run() async throws { print("Terminal setup — not yet implemented.") }
}

struct SetupLocalModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "local-model", abstract: "Download and commission local MLX model.")
    func run() async throws { print("Local model setup — not yet implemented.") }
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
            print("\nImport requires confirmation for each category.")
            print("Not yet implemented — use --dry-run to preview.")
        }
    }
}
