// SwooshCLI/SetupCommissioning.swift — Setup runtime (commissioning, reports) — 0.4A
//
// Pulled out of SetupCommands.swift so the command structs in that file
// stay short and so the same commissioning path can be reused by future
// menu-bar / iOS setup flows without re-importing the whole CLI.

import Foundation
import SwooshClient
import SwooshConfig
import SwooshSkills
import SwooshTools

// MARK: - Report shape

struct CommissioningCheck: Codable, Sendable {
    let name: String
    let passed: Bool
    let detail: String
}

struct SetupCommissioningResult: Codable, Sendable {
    let configPath: String
    let apiTokenPath: String
    let stateDirectories: [String]
    let checks: [CommissioningCheck]
    let readiness: SwooshReadinessReport
}

/// Local Codable record written to `setupReportsDir`. Distinct from the
/// `SetupReport` type in `SwooshScout` (which models the interactive
/// setup-UI step trace) — both names exist in the module and the disk
/// schema below is internal to the CLI.
struct SetupCommissioningReport: Codable, Sendable {
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

let setupNextSteps: [String] = [
    "swoosh doctor",
    "swoosh scout run --depth recommended",
    "swoosh memory list",
    "swoosh memory approve --all",
    "swoosh ask \"What should I do first?\"",
    "swoosh skills list",
    "swoosh cron list",
    "swoosh chat-adapters list",
]

// MARK: - Commissioning context

/// Groups the parameter block that flows through the commissioning
/// pipeline. Replaces a previous 9-argument call chain that triggered
/// a "too many parameters" review finding and made the call sites hard
/// to read at a glance. Add fields here rather than threading new
/// parameters through every function.
struct CommissioningContext: Sendable {
    let config: SwooshConfigStore
    let hardware: HardwareProfile
    let profile: PermissionProfilePreset
    let modelPath: SetupModelPath
    let mode: String
    let daemonHost: String
    let daemonPort: Int
    /// How long to wait for the app-hosted runtime to answer the readiness
    /// probe. Setup no longer launches anything — the runtime is in-process
    /// in the macOS app — so this is purely a readiness timeout.
    let daemonStartTimeout: Double
}

// MARK: - Public surface used by SetupCommands

/// Shared scaffolding behind `swoosh setup quick` and `swoosh setup full`.
/// Both subcommands plug in their own profile / model-path / scout step;
/// everything else (config dirs, runtime config, readiness probe, report
/// write) lives here so the two paths can't drift.
@discardableResult
func runCommissioning(
    _ ctx: CommissioningContext,
    scoutSummary: String? = nil
) async throws -> (commissioning: SetupCommissioningResult, reportPath: URL) {
    try ctx.config.ensureDirectories()
    let commissioning = try await commissionLocalRuntime(ctx)
    let reportPath = try writeSetupReport(
        ctx,
        commissioning: commissioning,
        scoutSummary: scoutSummary,
        nextSteps: setupNextSteps
    )
    return (commissioning, reportPath)
}

func writeSetupReport(
    _ ctx: CommissioningContext,
    commissioning: SetupCommissioningResult,
    scoutSummary: String? = nil,
    nextSteps: [String]
) throws -> URL {
    let date = ISO8601DateFormatter().string(from: Date())
    let report = SetupCommissioningReport(
        date: date,
        mode: ctx.mode,
        profile: ctx.profile.rawValue,
        modelPath: ctx.modelPath.rawValue,
        cpu: ctx.hardware.cpuName,
        memoryGB: Int(ctx.hardware.totalMemoryGB),
        appleSilicon: ctx.hardware.hasAppleSilicon,
        commissioning: commissioning,
        scoutSummary: scoutSummary,
        nextSteps: nextSteps
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reportPath = ctx.config.setupReportsDir.appending(path: "\(date)-\(ctx.mode).json")
    try encoder.encode(report).write(to: reportPath, options: .atomic)
    return reportPath
}

func commissionLocalRuntime(_ ctx: CommissioningContext) async throws -> SetupCommissioningResult {
    let config = ctx.config
    let hardware = ctx.hardware
    let profile = ctx.profile
    let modelPath = ctx.modelPath
    let mode = ctx.mode
    let daemonHost = ctx.daemonHost
    let daemonPort = ctx.daemonPort
    let daemonStartTimeout = ctx.daemonStartTimeout
    try config.ensureDirectories()
    let tokenPath = config.apiTokenFile
    _ = try ensureBearerTokenFile(at: tokenPath)

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
    timeout: Double,
    promptableSkillCount: Int
) async -> SwooshReadinessReport {
    let client = makeReadinessClient(config: config, host: host, port: port)
    if let live = await liveReadiness(client: client), live.state == .ready {
        return live
    }
    // Setup does not launch anything: the agent runtime is hosted
    // in-process by the macOS app. Give it a brief window to answer in
    // case the app is starting up, then fall back to a static report.
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
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = port
    // Should never fail with a valid host string; if it does, fall back
    // to a loopback URL so the caller can surface a real network error
    // instead of crashing the CLI.
    let baseURL = components.url ?? URL(string: "http://127.0.0.1:\(port)")!
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

// MARK: - Pretty-printers used by setup subcommands

func printSetupNextSteps() {
    print("\nNext setup commands:")
    for step in setupNextSteps {
        print("  \(step)")
    }
    print()
}

func printReadiness(_ report: SwooshReadinessReport, prefix: String = "") {
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
