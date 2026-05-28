// SwooshCLI/ScoutMemoryCommands.swift — Scout, Memory, Permissions commands + Helpers — 0.4B

import ArgumentParser
import SwooshConfig
import SwooshScout
import SwooshSecrets
import SwooshTools
import Foundation

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

        let folderPaths: [URL]
        if folders.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folderPaths = [home.appending(path: "Projects"), home.appending(path: "Developer")]
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            folderPaths = folders.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
            }
        }

        var sources = ScoutSourceCatalog.operationalLocalSources(folderURLs: folderPaths)
        sources.append(PersonalizationSignalSource())

        let existingMemories = await loadExistingMemorySummaries()
        let pipeline = ScoutPipeline(sources: sources)
        let progressBar = CLIProgress(total: 0, label: "Scanning")
        let result = try await pipeline.run(
            depth: parsedDepth,
            options: ScoutPipelineOptions(existingMemories: existingMemories),
            log: { msg in print(msg) },
            progress: { current, total, name in
                if progressBar.total == 0 { progressBar.total = total }
                progressBar.update(step: current, detail: name)
            }
        )
        progressBar.finish(message: "Scanned \(result.sourcesScanned) source(s), \(result.recordsCollected) record(s)")

        // TODO: wire durable backend — persist scout records and candidates
        // The CLI now runs with in-memory stores; scan results are displayed
        // but not persisted across runs. Launch the Detour app for durable storage.
        if !hasCLIBackendEnvironment() {
            print("  ⚠ \(cliBackendUnsetMessage)")
            print("  Pipeline ran but results were not persisted.")
        }

        print("\n\(result.setupReport)")
        print("  Records collected: \(result.recordsCollected)")
        print("  Candidates generated: \(result.candidatesGenerated)")
        print("\n  Run `swoosh memory list` to review candidates.")
        print("  Run `swoosh memory approve` to approve all.")
    }
}

struct ScoutReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "report", abstract: "Show the latest Scout report.")
    func run() async throws {
        // TODO: wire durable backend — retrieve persisted reports
        print("Scout report requires a durable backend (the Detour app).")
        print("Run `swoosh scout run` to perform a fresh scan.")
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
        // TODO: wire durable backend — in-memory stores don't persist across CLI invocations
        print("Memory listing requires a durable backend (the Detour app).")
        print("Run `swoosh scout run` to scan, then use the Detour app for persistent memory management.")
    }

    /// Extracts rejected candidates from a list of candidates.
    /// `internal` so the SwooshCLI test target can pin the pattern-match
    /// behaviour without needing a live backend.
    static func rejectedCandidates(from candidates: [SwooshTools.MemoryCandidate]) -> [SwooshTools.MemoryCandidate] {
        candidates.filter { $0.status == .rejected }
    }
}

struct MemoryShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show approved memories.")
    func run() async throws {
        // TODO: wire durable backend
        print("Memory display requires a durable backend (the Detour app).")
        print("Launch the Detour app for persistent memory management.")
    }
}

struct MemoryApproveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approve", abstract: "Approve memory candidates.")
    @Option(name: .long, help: "Approve a specific candidate by ID prefix.")
    var id: String?
    @Flag(name: .long, help: "Approve all pending candidates.")
    var all = false

    func run() async throws {
        // TODO: wire durable backend
        print("Memory approval requires a durable backend (the Detour app).")
        print("Launch the Detour app for persistent memory management.")
    }
}

struct MemoryRejectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reject", abstract: "Reject a memory candidate.")
    @Option(name: .long, help: "Reject by ID prefix.")
    var id: String
    @Option(name: .long, help: "Optional reason.")
    var reason: String?
    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force = false
    func run() async throws {
        // TODO: wire durable backend
        print("Memory rejection requires a durable backend (the Detour app).")
        print("Launch the Detour app for persistent memory management.")
    }
}

// MARK: - Permissions

struct PermissionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "permissions", abstract: "View and manage permission profile.")
    @Flag(name: .long, help: "Show current permission status.")
    var status = false
    func run() async throws {
        guard status else {
            print("Use `swoosh setup permissions` for the profile summary.")
            print("Use `swoosh permissions --status` to view the runtime policy.")
            return
        }
        printRuntimePolicyStatus()
        // TODO: wire durable backend — show live ActantDB grants
        print("─── Permissions ──────────────────────────────")
        print("  Durable approval backend not wired. Showing runtime policy only.")
    }
}

private func printRuntimePolicyStatus() {
    let runtime = try? SwooshConfigStore().load(SwooshRuntimeConfig.self)
    let preset = PermissionProfilePreset(rawValue: runtime?.permissionProfile ?? "") ?? .developer
    let policy = runtime?.toolPolicy ?? preset.defaultToolPolicy
    let safety = runtime?.safetyConfig ?? preset.defaultSafetyConfig
    print("─── Runtime Policy ───────────────────────────")
    print("Profile: \(runtime?.permissionProfile ?? preset.rawValue)")
    print("Granted permissions: \(preset.grantedSwooshPermissions.count)")
    print("Model tool calls: \(policy.allowModelToolCalls ? "enabled" : "disabled")")
    print("Max tool calls: \(policy.maxToolCallsPerTurn)")
    print("Max chain depth: \(policy.maxToolChainDepth)")
    print("Human-only from model: \(policy.allowHumanOnlyFromModel ? "allowed" : "blocked")")
    print("Critical tools from model: \(policy.allowCriticalToolsFromModel ? "allowed" : "blocked")")
    print("Medium-risk approval: \(policy.requireApprovalForMediumRiskAndAbove ? "required" : "optional")")
    print("Model self-approval: \(safety.modelSelfApprovalEnabled ? "enabled" : "disabled")")
    print("Mainnet writes by default: \(safety.mainnetWritesByDefault ? "enabled" : "disabled")")
}

// MARK: - Sensitivity bridge
// Bridge SwooshScout.Sensitivity → SwooshTools.Sensitivity via raw string.
// Both enums are String-backed.

private func toToolsSensitivity(_ raw: String) -> SwooshTools.Sensitivity {
    switch raw {
    case "normal":   return .normal
    case "sensitive": return .sensitive
    case "secret":   return .secret
    default:         return .normal
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

    let recs = hw.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
    if !recs.isEmpty {
        print("\n  Local models: can run \(recs.map(\.sizeLabel).joined(separator: ", "))")
    }
    print()
}

/// Returns existing memory summaries for deduplication during Scout runs.
/// Without a durable backend, returns an empty array — the Scout pipeline
/// treats this as "no prior memories" and generates all candidates fresh.
private func loadExistingMemorySummaries() async -> [ExistingMemorySummary] {
    // TODO: wire durable backend — query persisted approved + pending memories
    return []
}

// CLISetupUI now lives in CLISetupUI.swift.
