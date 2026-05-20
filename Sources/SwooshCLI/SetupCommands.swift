// SwooshCLI/SetupCommands.swift — Setup command tree
//
// swoosh setup quick/full/developer/server/model/permissions/...

import ArgumentParser
import SwooshClient
import SwooshConfig
import SwooshScout
import SwooshSkills
import SwooshTools
import Foundation
#if canImport(Security)
import Security
#endif

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

    @Option(name: .customLong("daemon-start-timeout"), help: "Seconds to wait for swooshd readiness after launch.")
    var daemonStartTimeout: Double = 60

    @Flag(name: .customLong("skip-daemon-start"), help: "Do not launch swooshd during setup.")
    var skipDaemonStart = false

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
        let commissioning = try await commissionLocalRuntime(
            config: config,
            hardware: hardware,
            profile: preset,
            modelPath: modelPath,
            mode: "quick",
            daemonHost: daemonHost,
            daemonPort: daemonPort,
            startDaemon: !skipDaemonStart,
            daemonStartTimeout: daemonStartTimeout
        )
        printReadiness(commissioning.readiness)
        print()

        let reportPath = try writeSetupReport(
            config: config,
            hardware: hardware,
            profile: preset,
            modelPath: modelPath,
            mode: "quick",
            commissioning: commissioning,
            nextSteps: setupNextSteps
        )
        print("Setup report saved to \(reportPath.path)\n")
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

    @Option(name: .customLong("daemon-start-timeout"), help: "Seconds to wait for swooshd readiness after launch.")
    var daemonStartTimeout: Double = 60

    @Flag(name: .customLong("skip-daemon-start"), help: "Do not launch swooshd during setup.")
    var skipDaemonStart = false

    func run() async throws {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let hardware = HardwareDetector().detect()
        try config.ensureDirectories()
        let commissioning = try await commissionLocalRuntime(
            config: config,
            hardware: hardware,
            profile: .developer,
            modelPath: .hybrid,
            mode: "full",
            daemonHost: daemonHost,
            daemonPort: daemonPort,
            startDaemon: !skipDaemonStart,
            daemonStartTimeout: daemonStartTimeout
        )
        let scoutResult = try await ScoutPipeline(
            sources: ScoutSourceCatalog.operationalLocalSources()
        ).run(
            depth: .recommended,
            options: ScoutPipelineOptions(permissionMode: .skipUnavailable, minimumConfidence: 0.7)
        )
        let reportPath = try writeSetupReport(
            config: config,
            hardware: hardware,
            profile: .developer,
            modelPath: .hybrid,
            mode: "full",
            commissioning: commissioning,
            scoutSummary: "Scout collected \(scoutResult.recordsCollected) record(s) and generated \(scoutResult.candidatesGenerated) candidate(s).",
            nextSteps: setupNextSteps
        )
        print("Full baseline complete.")
        printReadiness(commissioning.readiness, prefix: "  ")
        print("  ✓ Scout dry run: \(scoutResult.recordsCollected) record(s), \(scoutResult.candidatesGenerated) candidate(s)")
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

enum SetupModelPath: String, Codable, CaseIterable {
    case local
    case cloud
    case hybrid
}

extension SetupModelPath: ExpressibleByArgument {}

extension PermissionProfilePreset: ExpressibleByArgument {}

private struct CommissioningCheck: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

private struct SetupCommissioningResult: Codable {
    let configPath: String
    let apiTokenPath: String
    let stateDirectories: [String]
    let checks: [CommissioningCheck]
    let readiness: SwooshReadinessReport
}

private struct SetupReport: Codable {
    let date: String
    let mode: String
    let profile: String
    let modelPath: String
    let cpu: String
    let memoryGB: Int
    let appleSilicon: Bool
    let commissioning: SetupCommissioningResult
    let scoutSummary: String?
    let nextSteps: [String]
}

private let setupNextSteps = [
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
    commissioning: SetupCommissioningResult,
    scoutSummary: String? = nil,
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
        commissioning: commissioning,
        scoutSummary: scoutSummary,
        nextSteps: nextSteps
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reportPath = config.setupReportsDir.appending(path: "\(date)-\(mode).json")
    try encoder.encode(report).write(to: reportPath, options: .atomic)
    return reportPath
}

private func commissionLocalRuntime(
    config: SwooshConfigStore,
    hardware: HardwareProfile,
    profile: PermissionProfilePreset,
    modelPath: SetupModelPath,
    mode: String,
    daemonHost: String,
    daemonPort: Int,
    startDaemon: Bool,
    daemonStartTimeout: Double
) async throws -> SetupCommissioningResult {
    try config.ensureDirectories()
    let tokenPath = config.apiTokenFile
    if !FileManager.default.fileExists(atPath: tokenPath.path) {
        let token = try generateBearerToken()
        try token.write(to: tokenPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenPath.path)
    }

    let runtimeConfig = SwooshRuntimeConfig(
        setupMode: mode,
        permissionProfile: profile.rawValue,
        modelPath: modelPath.rawValue,
        daemonHost: daemonHost,
        daemonPort: daemonPort,
        localDiagnosticFallback: true,
        toolPolicy: profile.defaultToolPolicy,
        safetyConfig: profile.defaultSafetyConfig,
        configuredAt: ISO8601DateFormatter().string(from: Date())
    )
    try config.save(runtimeConfig)

    let directories = config.requiredStateDirectories
    let promptableSkillCount = try await installBundledSkills(config: config)
    let readiness = await verifiedReadiness(
        config: config,
        host: daemonHost,
        port: daemonPort,
        startDaemon: startDaemon,
        timeout: daemonStartTimeout,
        promptableSkillCount: promptableSkillCount
    )
    let checks = [
        CommissioningCheck(
            name: "Config",
            passed: FileManager.default.fileExists(atPath: config.configFile.path),
            detail: config.configFile.path
        ),
        CommissioningCheck(
            name: "API token",
            passed: FileManager.default.fileExists(atPath: tokenPath.path),
            detail: tokenPath.path
        ),
        CommissioningCheck(
            name: "State directories",
            passed: directories.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
            detail: "\(directories.count) local state directories ready"
        ),
        CommissioningCheck(
            name: "Local model path",
            passed: hardware.hasAppleSilicon || modelPath == .hybrid,
            detail: hardware.hasAppleSilicon ? "Apple Silicon available" : "diagnostic fallback enabled"
        ),
        CommissioningCheck(
            name: "Promptable skills",
            passed: promptableSkillCount > 0,
            detail: "\(promptableSkillCount) reviewed or promoted skill(s)"
        ),
        CommissioningCheck(
            name: "Daemon readiness",
            passed: readiness.state == .ready,
            detail: readiness.summary
        ),
    ]
    return SetupCommissioningResult(
        configPath: config.configFile.path,
        apiTokenPath: tokenPath.path,
        stateDirectories: directories.map(\.path),
        checks: checks,
        readiness: readiness
    )
}

private func installBundledSkills(config: SwooshConfigStore) async throws -> Int {
    let store = FileSkillStore(directory: config.skillsDir)
    _ = try await BundledSkillLoader(
        store: store,
        directory: BundledSkillLoader.defaultDirectory()
    ).loadAll()
    let skills = try await store.listAll()
    return skills.filter { SkillTrust.promptable.contains($0.trust) }.count
}

private func verifiedReadiness(
    config: SwooshConfigStore,
    host: String,
    port: Int,
    startDaemon: Bool,
    timeout: Double,
    promptableSkillCount: Int
) async -> SwooshReadinessReport {
    let client = makeReadinessClient(config: config, host: host, port: port)
    if let live = await liveReadiness(client: client), live.state == .ready {
        return live
    }
    if startDaemon {
        try? launchSwooshDaemon(config: config, host: host, port: port)
    }
    if let live = await waitForLiveReadiness(client: client, timeout: timeout) {
        return live
    }
    return SwooshReadinessDetector(config: config).report(inputs: SwooshReadinessInputs(
        daemonReachable: await client.health(),
        promptableSkillCount: promptableSkillCount
    ))
}

private func makeReadinessClient(config: SwooshConfigStore, host: String, port: Int) -> SwooshAPIClient {
    let token = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let baseURL = URL(string: "http://\(host):\(port)")!
    return SwooshAPIClient(baseURL: baseURL, token: token)
}

private func liveReadiness(client: SwooshAPIClient) async -> SwooshReadinessReport? {
    guard await client.health() else { return nil }
    return try? await client.readiness()
}

private func waitForLiveReadiness(client: SwooshAPIClient, timeout: Double) async -> SwooshReadinessReport? {
    let deadline = Date().addingTimeInterval(max(1, timeout))
    while Date() < deadline {
        if let report = await liveReadiness(client: client) {
            return report
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return nil
}

private func launchSwooshDaemon(config: SwooshConfigStore, host: String, port: Int) throws {
    try FileManager.default.createDirectory(at: config.logsDir, withIntermediateDirectories: true)
    let process = Process()
    let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appendingPathComponent("swooshd")
    if FileManager.default.isExecutableFile(atPath: sibling.path) {
        process.executableURL = sibling
        process.arguments = []
    } else if FileManager.default.fileExists(atPath: "Package.swift") {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "run", "swooshd"]
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swooshd"]
    }
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var environment = ProcessInfo.processInfo.environment
    environment["SWOOSH_CONFIG_DIR"] = config.configDirectory.path
    environment["SWOOSH_HOST"] = host
    environment["SWOOSH_PORT"] = String(port)
    process.environment = environment
    process.standardOutput = try FileHandle(forWritingTo: setupLogFile(config: config, name: "swooshd-setup.log"))
    process.standardError = try FileHandle(forWritingTo: setupLogFile(config: config, name: "swooshd-setup.err.log"))
    try process.run()
}

private func setupLogFile(config: SwooshConfigStore, name: String) throws -> URL {
    let url = config.logsDir.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    return url
}

private func generateBearerToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    #if canImport(Security)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw CocoaError(.fileWriteUnknown)
    }
    #else
    for index in bytes.indices {
        bytes[index] = UInt8.random(in: 0...255)
    }
    #endif
    return bytes.map { String(format: "%02x", $0) }.joined()
}

private func printSetupNextSteps() {
    print("\nNext setup commands:")
    for step in setupNextSteps {
        print("  \(step)")
    }
    print()
}

private func printReadiness(_ report: SwooshReadinessReport, prefix: String = "") {
    print("\(prefix)Readiness: \(report.state.rawValue) — \(report.summary)")
    for component in report.components {
        print("\(prefix)\(readinessIcon(component.status)) \(component.title): \(component.detail)")
    }
}

private func readinessIcon(_ status: SwooshReadinessStatus) -> String {
    switch status {
    case .ready:
        return "✓"
    case .warning:
        return "○"
    case .blocked:
        return "✗"
    }
}
