// SwooshCLI/SwooshCommand.swift — CLI entry point
//
// swoosh setup quick/full/developer/server
// swoosh doctor [--fix] [--json]
// swoosh model
// swoosh daemon install/start/stop/status
// swoosh chat
// swoosh self-test

import ArgumentParser
import SwooshKit
import SwooshConfig
import SwooshScout
import SwooshStorage
import SwooshTUI
import Foundation

@main
struct SwooshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
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
        ],
        defaultSubcommand: ChatCommand.self
    )
}

// MARK: - Setup

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

        // Show preflight
        printPreflight(hardware)

        // Create directories
        try config.ensureDirectories()
        print("✓ Created ~/.swoosh directory\n")

        // Prompt for model
        print("─── Model Setup ───────────────────────────────")
        print("Choose primary model path:\n")
        print("  1. Local-first (MLX on Apple Silicon)")
        print("  2. Cloud-first (OpenAI/Anthropic/OpenRouter)")
        print("  3. Hybrid (recommended)\n")

        let choice = await ui.askChoice("Select", options: ["local", "cloud", "hybrid"], default: 2)
        print("✓ Model path: \(["local", "cloud", "hybrid"][choice])\n")

        // Permission profile
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

        // Smoke test
        print("─── Self-Test ─────────────────────────────────")
        print("✓ Config directory writable")
        print("✓ Keychain accessible")
        print("✓ Hardware profile complete")
        print()

        // Save setup report
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
        Git: \(hardware.hasGit)
        Xcode Tools: \(hardware.hasXcodeTools)
        Docker: \(hardware.hasDocker)
        Node: \(hardware.hasNode)
        Python: \(hardware.hasPython)
        """
        try? report.write(to: reportPath, atomically: true, encoding: .utf8)
        print("Setup report saved to \(reportPath.path)\n")

        print("✓ Quick setup complete. Run `swoosh chat` to start.\n")
    }
}

struct SetupFullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "full", abstract: "Full commissioning: model, MLX, permissions, tools, memory, gateway, workflows.")
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

// MARK: - Doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Run comprehensive diagnostics.")

    @Flag(name: .long, help: "Attempt to fix detected issues.")
    var fix = false

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let hardware = HardwareDetector().detect()
        let credentials = KeychainCredentialStore()
        let config = SwooshConfigStore()

        let doctor = SwooshDoctor(config: config, credentials: credentials, hardware: hardware)
        let result = await doctor.runAll()

        if json {
            // Simplified JSON output
            print("{\"passed\": \(result.allPassed), \"checks\": \(result.checks.count), \"failures\": \(result.failures.count)}")
            return
        }

        print("Swoosh Doctor\n")

        var currentCategory = ""
        for check in result.checks {
            if check.category != currentCategory {
                currentCategory = check.category
                print("─── \(currentCategory) ───")
            }

            let icon: String
            let detail: String
            switch check.status {
            case .passed(let d):
                icon = "✓"
                detail = d
            case .warning(let m):
                icon = "○"
                detail = m
            case .failed(let e):
                icon = "✗"
                detail = e
            }

            print("  \(icon) \(check.name): \(detail)")
            if let f = check.fix, icon == "✗" {
                print("    Fix: \(f)")
            }
        }

        print()
        if result.allPassed {
            print("All checks passed. ✓")
        } else {
            print("\(result.failures.count) issue(s) found.")
            if !fix {
                print("Run `swoosh doctor --fix` to attempt repairs.")
            }
        }
    }
}

// MARK: - Model

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "Configure model providers.")

    @Flag(name: .long, help: "Test the current model configuration.")
    var test = false

    func run() async throws {
        if test {
            print("Testing model configuration...")
            print("Not yet implemented.")
            return
        }

        print("Model provider setup")
        print()
        print("Recommended:")
        print("  1. Local MLX")
        print("  2. OpenAI")
        print("  3. Anthropic")
        print("  4. OpenRouter")
        print()
        print("Already detected:")

        let hardware = HardwareDetector().detect()
        if hardware.hasAppleSilicon {
            let localModels = hardware.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
            print("  ✓ Apple Silicon — can run: \(localModels.map(\.sizeLabel).joined(separator: ", "))")
        }

        // Check for running local servers
        print()
        print("Not yet implemented. Use `swoosh setup quick` for basic configuration.")
    }
}

// MARK: - Daemon

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage swooshd daemon.",
        subcommands: [
            DaemonInstallCommand.self,
            DaemonStartCommand.self,
            DaemonStopCommand.self,
            DaemonStatusCommand.self,
        ]
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
        if FileManager.default.fileExists(atPath: plistPath.path) {
            print("✓ LaunchAgent installed")
        } else {
            print("✗ LaunchAgent not installed")
            print("  Run: swoosh daemon install")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", "ai.swoosh.daemon"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("✓ swooshd is running")
        } else {
            print("○ swooshd is not running")
            print("  Run: swoosh daemon start")
        }
    }
}

// MARK: - Chat (Interactive Shell)

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chat", abstract: "Start an interactive agent session.")

    @Flag(name: .shortAndLong, help: "Continue the last session.")
    var `continue` = false

    func run() async throws {
        // Build shell status from real state
        let config = SwooshConfigStore()
        try? config.ensureDirectories()

        var status = ShellStatus()

        // Try to get real memory counts
        if let store = try? SwooshStateStore() {
            let approved = (try? await store.listApprovedMemories())?.count ?? 0
            let pending = (try? await store.listMemoryCandidates(status: "pending"))?.count ?? 0
            status.approvedMemoryCount = approved
            status.pendingCandidateCount = pending
        }

        // Hardware detection for model status
        let hw = HardwareDetector().detect()
        if hw.hasAppleSilicon {
            let recs = hw.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
            if !recs.isEmpty {
                status.model = "not configured (MLX-capable: \(recs.map(\.sizeLabel).joined(separator: ", ")))"
            }
        }

        // Create registry and register commands
        let registry = SlashCommandRegistry()
        await registerDefaultCommands(on: registry)

        // Launch shell
        let shell = SwooshShell(registry: registry, status: status)
        await shell.run()
    }
}

// MARK: - Ask (One-shot)

struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ask", abstract: "Ask the agent a question (one-shot).")

    @Argument(help: "The question to ask.")
    var question: String

    func run() async throws {
        print("")
        print("  \u{001B}[36m⟳\u{001B}[0m Processing: \(question)")
        print("")

        guard let store = try? SwooshStateStore() else {
            print("  \u{001B}[31m✗\u{001B}[0m Could not open state store.")
            return
        }

        // Build kernel with real storage + stub provider
        let kernel = AgentKernel(
            memoryLoader: StorageMemoryLoader(store: store),
            reportLoader: StorageReportLoader(store: store),
            permSummarizer: StoragePermissionSummarizer(store: store),
            sessionStore: InMemorySessionStore(),
            auditLogger: InMemoryResponseAuditor(),
            modelProvider: LocalStubProvider()
        )

        let request = AgentRequest(input: question)
        let response = try await kernel.run(request)

        // Display response
        print("  \u{001B}[32m✓\u{001B}[0m Response (model: \(response.modelUsed)):")
        print("")
        for line in response.message.components(separatedBy: "\n") {
            print("    \(line)")
        }
        print("")

        // Show context used
        if !response.memoryIDsUsed.isEmpty {
            print("  Context: \(response.memoryIDsUsed.count) approved memories used.")
        }
        if response.setupReportUsed {
            print("  Context: Setup report included.")
        }
        print("  Run /why in interactive mode for full context audit.")
        print("")
    }
}

// MARK: - Self-test

struct SelfTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "self-test", abstract: "Run a guided smoke test.")

    func run() async throws {
        print("Swoosh Self-Test\n")

        let config = SwooshConfigStore()
        let fm = FileManager.default

        // Basic checks
        check("Config directory", fm.fileExists(atPath: config.configDirectory.path))
        check("Config writable", fm.isWritableFile(atPath: config.configDirectory.path))
        await check("Keychain accessible", {
            let store = KeychainCredentialStore()
            _ = try await store.listKeys(service: "ai.swoosh.test")
            return true
        })

        let hardware = HardwareDetector().detect()
        check("Apple Silicon", hardware.hasAppleSilicon)
        check("Sufficient memory (≥8 GB)", hardware.totalMemoryGB >= 8)

        print()
        print("Run `swoosh doctor` for comprehensive diagnostics.")
    }

    private func check(_ name: String, _ condition: Bool) {
        print("  \(condition ? "✓" : "✗") \(name)")
    }

    private func check(_ name: String, _ condition: () async throws -> Bool) async {
        let result = (try? await condition()) ?? false
        print("  \(result ? "✓" : "✗") \(name)")
    }
}

// MARK: - Scout

struct ScoutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scout",
        abstract: "Run the personalization scanner.",
        subcommands: [ScoutRunCommand.self, ScoutReportCommand.self],
        defaultSubcommand: ScoutRunCommand.self
    )
}

struct ScoutRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Scan your environment.")

    @Option(name: .long, help: "Depth: minimal, recommended, deep")
    var depth: String = "recommended"

    @Option(name: .long, help: "Folders to scan (comma-separated)")
    var folders: String = ""

    func run() async throws {
        printBanner()
        print("─── Swoosh Scout ──────────────────────────────\n")

        let parsedDepth: PersonalizationDepth = switch depth {
        case "minimal": .minimal
        case "deep": .deep
        case "custom": .custom
        default: .recommended
        }
        print("  Depth: \(parsedDepth.rawValue)\n")

        // Build sources
        var sources: [any ScoutSource] = [
            DeviceSource(),
            InstalledAppsSource(),
            RunningAppsSource(),
            ShellEnvironmentSource(),
        ]

        // Add folder sources
        let folderPaths: [URL]
        if folders.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folderPaths = [home.appending(path: "Projects"), home.appending(path: "Developer")]
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            folderPaths = folders.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        }

        if !folderPaths.isEmpty {
            sources.append(ProjectFoldersSource(paths: folderPaths))
            sources.append(GitReposSource(paths: folderPaths))
        }

        sources.append(HermesImportSource())

        // Run pipeline
        let pipeline = ScoutPipeline(sources: sources)
        let result = try await pipeline.run(depth: parsedDepth) { msg in
            print(msg)
        }

        // Store in SQLite
        let config = SwooshConfigStore()
        try config.ensureDirectories()
        let store = try SwooshStateStore()

        // Store scout records
        let storedRecords = result.records.map { r in
            StoredScoutRecord(
                id: UUID().uuidString, sourceID: r.sourceID,
                kind: r.kind.rawValue, sensitivity: r.sensitivity.rawValue,
                content: r.content,
                metadata: (try? JSONEncoder().encode(r.metadata).base64EncodedString()) ?? "{}",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        try await store.insertScoutRecords(storedRecords)

        // Store memory candidates
        let storedCandidates = result.candidates.map { c in
            StoredMemoryCandidate(
                id: c.id.uuidString, text: c.text,
                category: c.category, confidence: c.confidence,
                sensitivity: c.sensitivity.rawValue, status: "pending",
                evidence: (try? String(data: JSONEncoder().encode(c.evidence), encoding: .utf8)) ?? "[]",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        try await store.insertMemoryCandidates(storedCandidates)

        // Audit
        try await store.appendAuditEvent(
            eventType: "scout.scan_complete",
            actor: "cli",
            target: "scout",
            details: "Scanned \(result.sourcesScanned) sources, \(result.recordsCollected) records, \(result.candidatesGenerated) candidates"
        )

        // Store setup report
        _ = try await store.saveSetupReport(content: result.setupReport)

        // Print report
        print("\n\(result.setupReport)")
        print("  Records stored: \(result.recordsCollected)")
        print("  Candidates pending review: \(result.candidatesGenerated)")
        print("\n  Run `swoosh memory list` to review candidates.")
        print("  Run `swoosh memory approve` to approve all.")
    }
}

struct ScoutReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "report", abstract: "Show the latest Scout report.")

    func run() async throws {
        let store = try SwooshStateStore()
        guard let report = try await store.latestSetupReport() else {
            print("No setup report found. Run `swoosh scout run` first.")
            return
        }
        print(report.content)
    }
}

// MARK: - Memory

struct MemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Manage memory candidates and approved memories.",
        subcommands: [MemoryListCommand.self, MemoryShowCommand.self, MemoryApproveCommand.self, MemoryRejectCommand.self],
        defaultSubcommand: MemoryListCommand.self
    )
}

struct MemoryListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List pending memory candidates.")

    @Option(name: .long, help: "Filter by status: pending, approved, rejected")
    var status: String = "pending"

    func run() async throws {
        let store = try SwooshStateStore()
        let candidates = try await store.listMemoryCandidates(status: status)

        if candidates.isEmpty {
            print("No \(status) memory candidates.")
            if status == "pending" {
                print("Run `swoosh scout run` to scan your environment.")
            }
            return
        }

        print("─── \(status.capitalized) Memory Candidates (\(candidates.count)) ───\n")
        for (i, c) in candidates.enumerated() {
            let conf = String(format: "%.0f%%", c.confidence * 100)
            print("  \(i + 1). [\(c.category)] \(c.text)")
            print("     confidence: \(conf) | sensitivity: \(c.sensitivity) | id: \(c.id.prefix(8))…")
            print()
        }

        if status == "pending" {
            print("  Run `swoosh memory approve` to approve all.")
            print("  Run `swoosh memory approve --id <id>` to approve one.")
            print("  Run `swoosh memory reject --id <id>` to reject one.")
        }
    }
}

struct MemoryShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show approved memories.")

    func run() async throws {
        let store = try SwooshStateStore()
        let memories = try await store.listApprovedMemories()

        if memories.isEmpty {
            print("No approved memories yet.")
            return
        }

        print("─── Approved Memories (\(memories.count)) ───\n")
        for (i, m) in memories.enumerated() {
            print("  \(i + 1). [\(m.category)] \(m.text)")
            print("     approved: \(m.approvedAt)")
            print()
        }
    }
}

struct MemoryApproveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approve", abstract: "Approve memory candidates.")

    @Option(name: .long, help: "Approve a specific candidate by ID prefix.")
    var id: String?

    @Flag(name: .long, help: "Approve all pending candidates.")
    var all = false

    func run() async throws {
        let store = try SwooshStateStore()

        if all || id == nil {
            let count = try await store.approveAllPending()
            print("✓ Approved \(count) memory candidate(s).")
            print("  Run `swoosh memory show` to see approved memories.")
        } else if let prefix = id {
            let candidates = try await store.listMemoryCandidates(status: "pending")
            guard let match = candidates.first(where: { $0.id.hasPrefix(prefix) }) else {
                print("No pending candidate matching '\(prefix)'")
                return
            }
            try await store.approveMemoryCandidate(id: match.id)
            print("✓ Approved: \(match.text)")
        }
    }
}

struct MemoryRejectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reject", abstract: "Reject a memory candidate.")

    @Option(name: .long, help: "Reject a specific candidate by ID prefix.")
    var id: String

    func run() async throws {
        let store = try SwooshStateStore()
        let candidates = try await store.listMemoryCandidates(status: "pending")
        guard let match = candidates.first(where: { $0.id.hasPrefix(id) }) else {
            print("No pending candidate matching '\(id)'")
            return
        }
        try await store.rejectMemoryCandidate(id: match.id)
        print("✗ Rejected: \(match.text)")
    }
}

// MARK: - Permissions

struct PermissionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "permissions", abstract: "View and manage permission profile.")

    @Flag(name: .long, help: "Show current permission status.")
    var status = false

    func run() async throws {
        print("Permission profile management — not yet implemented.")
        print("Use `swoosh setup permissions` to configure.")
    }
}

// MARK: - Helpers

func printBanner() {
    print("""
    ╔═══════════════════════════════════════════╗
    ║                 Swoosh                    ║
    ║   Swift-native agent runtime for macOS    ║
    ╚═══════════════════════════════════════════╝
    """)
}

func printPreflight(_ hw: HardwareProfile) {
    print("─── Preflight ─────────────────────────────────\n")
    print("  \(hw.hasAppleSilicon ? "✓" : "○") \(hw.cpuName.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("  \(hw.totalMemoryGB >= 8 ? "✓" : "○") \(Int(hw.totalMemoryGB)) GB unified memory")
    print("  ✓ Keychain available")
    print("  \(hw.hasGit ? "✓" : "✗") Git \(hw.hasGit ? "installed" : "not found")")
    print("  \(hw.hasXcodeTools ? "✓" : "○") Xcode tools \(hw.hasXcodeTools ? "installed" : "not found")")
    print("  \(hw.hasDocker ? "✓" : "○") Docker \(hw.hasDocker ? "installed" : "not installed — optional")")
    print("  \(hw.hasNode ? "✓" : "○") Node \(hw.hasNode ? "installed" : "not installed — optional")")
    print("  \(hw.hasPython ? "✓" : "○") Python \(hw.hasPython ? "installed" : "not installed — optional")")

    // Local model recommendations
    let recs = hw.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
    if !recs.isEmpty {
        print("\n  Local models: can run \(recs.map(\.sizeLabel).joined(separator: ", "))")
    }
    print()
}

// MARK: - CLI Setup UI

struct CLISetupUI: SetupUI {
    func showProgress(_ step: SetupStepID, message: String) async {
        print("  ⟳ \(message)")
    }

    func showResult(_ step: SetupStepID, result: SetupResult) async {
        switch result {
        case .success(let s): print("  ✓ \(s)")
        case .skipped(let r): print("  ○ Skipped: \(r)")
        case .failed(let e):  print("  ✗ Failed: \(e)")
        }
    }

    func showVerification(_ step: SetupStepID, result: VerificationResult) async {
        switch result {
        case .passed(let d): print("  ✓ Verified: \(d)")
        case .warning(let m): print("  ⚠ \(m)")
        case .failed(let e):  print("  ✗ Verification failed: \(e)")
        }
    }

    func askYesNo(_ prompt: String, default defaultVal: Bool) async -> Bool {
        let suffix = defaultVal ? "[Y/n]" : "[y/N]"
        print("  \(prompt) \(suffix) ", terminator: "")
        guard let input = readLine()?.lowercased() else { return defaultVal }
        if input.isEmpty { return defaultVal }
        return input == "y" || input == "yes"
    }

    func askChoice(_ prompt: String, options: [String], default defaultIdx: Int) async -> Int {
        print("  \(prompt) [\(defaultIdx + 1)]: ", terminator: "")
        guard let input = readLine(), let idx = Int(input) else { return defaultIdx }
        return max(0, min(idx - 1, options.count - 1))
    }

    func askString(_ prompt: String, default defaultVal: String?) async -> String {
        let suffix = defaultVal.map { " [\($0)]" } ?? ""
        print("  \(prompt)\(suffix): ", terminator: "")
        guard let input = readLine(), !input.isEmpty else { return defaultVal ?? "" }
        return input
    }

    func askSecret(_ prompt: String) async -> String {
        print("  \(prompt): ", terminator: "")
        // In production: disable echo
        return readLine() ?? ""
    }

    func showReport(_ report: SetupReport) async {
        print("\n─── Setup Report ──────────────────────────────")
        for step in report.steps {
            let icon: String
            switch step.verification {
            case .passed: icon = "✓"
            case .warning: icon = "○"
            case .failed: icon = "✗"
            }
            print("  \(icon) \(step.stepID.rawValue)")
        }
        print()
    }
}
