// SwooshCLI/ScoutMemoryCommands.swift — Scout, Memory, Permissions commands + Helpers

import ArgumentParser
import ActantDB
import ActantAgent
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
        sources.append(HermesImportSource())

        let backend = loadCLIBackend()
        let existingMemories = await loadExistingMemorySummaries(backend: backend)
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

        guard let backend else {
            print("  ⚠ \(cliBackendUnsetMessage)")
            print("  Pipeline ran but results were not persisted.")
            return
        }
        let client      = await backend.client
        let workspaceID = await backend.workspaceID
        let actorID     = await backend.actorID
        let memory      = MemoryStore(backend: backend)

        // Save scout records via the low-level client (no facade method yet).
        for r in result.records {
            let metadataJSON = (try? JSONSerialization.data(withJSONObject: r.metadata))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let metadata: ActantDB.JSONValue =
                (try? JSONDecoder().decode(ActantDB.JSONValue.self, from: Data(metadataJSON.utf8))) ?? .object([:])
            _ = try await client.saveScoutRecord(
                workspaceID: workspaceID, actorID: actorID,
                sourceID: r.sourceID, kind: r.kind.rawValue,
                sensitivity: toActantSensitivity(r.sensitivity.rawValue),
                content: r.content, metadata: metadata
            )
        }

        for c in result.candidates {
            let evidenceData = (try? JSONEncoder().encode(c.evidence)) ?? Data()
            let evidence: ActantDB.JSONValue =
                (try? JSONDecoder().decode(ActantDB.JSONValue.self, from: evidenceData)) ?? .array([])
            _ = try await memory.propose(
                text: c.text, category: c.category,
                sensitivity: toActantSensitivity(c.sensitivity.rawValue),
                confidence: c.confidence, evidence: evidence
            )
        }

        _ = try await client.saveSetupReport(
            workspaceID: workspaceID, actorID: actorID,
            content: result.setupReport
        )

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
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let client      = await backend.client
        let workspaceID = await backend.workspaceID
        guard let report = try await client.latestSetupReport(workspaceID: workspaceID) else {
            print("No setup report found. Run `swoosh scout run` first."); return
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
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let memory = MemoryStore(backend: backend)
        let candidates: [ActantDB.MemoryCandidate]
        switch status {
        case "approved":
            // Show approved memories via the MemoryShowCommand path.
            let approved = try await memory.listApproved()
            if approved.isEmpty { print("No approved memories."); return }
            print("─── Approved Memories (\(approved.count)) ───\n")
            for (i, m) in approved.enumerated() {
                print("  \(i + 1). [\(m.category)] \(m.text)")
                print("     id: \(m.id.prefix(8))…\n")
            }
            return
        case "rejected":
            // The facade exposes pending only; pull all and filter by status.
            let rows = try await backend.client.memories(workspaceID: await backend.workspaceID, status: "rejected")
            candidates = rows.compactMap {
                if case let .pending(c) = $0 { return c } else { return nil }
            }
        default:
            candidates = try await memory.listPending()
        }

        if candidates.isEmpty {
            print("No \(status) memory candidates.")
            if status == "pending" { print("Run `swoosh scout run` to scan.") }
            return
        }

        print("─── \(status.capitalized) Memory Candidates (\(candidates.count)) ───\n")
        for (i, c) in candidates.enumerated() {
            print("  \(i + 1). [\(c.category)] \(c.text)")
            print("     confidence: \(String(format: "%.0f%%", c.confidence * 100)) | sensitivity: \(c.sensitivity.rawValue) | id: \(c.id.prefix(8))…\n")
        }
        if status == "pending" {
            print("  Run `swoosh memory approve` to approve all.")
            print("  Run `swoosh memory reject --id <id>` to reject one.")
        }
    }
}

struct MemoryShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show approved memories.")
    func run() async throws {
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let memory = MemoryStore(backend: backend)
        let memories = try await memory.listApproved()
        guard !memories.isEmpty else { print("No approved memories yet."); return }
        print("─── Approved Memories (\(memories.count)) ───\n")
        for (i, m) in memories.enumerated() {
            print("  \(i + 1). [\(m.category)] \(m.text)")
            print("     id: \(m.id.prefix(8))…\n")
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
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let memory = MemoryStore(backend: backend)
        let pending = try await memory.listPending()

        if all || id == nil {
            for c in pending {
                try await memory.approve(candidateID: c.id)
            }
            print("✓ Approved \(pending.count) memory candidate(s).")
        } else if let prefix = id {
            guard let match = pending.first(where: { $0.id.hasPrefix(prefix) }) else {
                print("No pending candidate matching '\(prefix)'"); return
            }
            try await memory.approve(candidateID: match.id)
            print("✓ Approved: \(match.text)")
        }
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
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let memory = MemoryStore(backend: backend)
        let pending = try await memory.listPending()
        guard let match = pending.first(where: { $0.id.hasPrefix(id) }) else {
            print("No pending candidate matching '\(id)'"); return
        }
        if !force {
            print("Reject candidate '\(match.text)'? [y/N] ", terminator: "")
            guard let input = readLine()?.lowercased(), input == "y" || input == "yes" else {
                print("Aborted.")
                return
            }
        }
        try await memory.reject(candidateID: match.id, reason: reason)
        print("✗ Rejected: \(match.text)")
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
            print("Use `swoosh permissions --status` to view live ActantDB grants.")
            return
        }
        printRuntimePolicyStatus()
        guard let backend = loadCLIBackend() else { print(cliBackendUnsetMessage); return }
        let center = ApprovalCenter(backend: backend)
        let summary = try await center.permissionSummary()
        print("─── Permissions ──────────────────────────────")
        print(summary)
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
// `Sensitivity` is ambiguous because ActantAgent re-exports its own enum.
// Bridge through the raw string instead — both enums are String-backed.

private func toActantSensitivity(_ raw: String) -> ActantDB.Sensitivity {
    switch raw {
    case "low":      return .low
    case "medium":   return .medium
    case "high":     return .high
    case "critical": return .high   // ActantDB caps at .high
    default:         return .low
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

private func loadExistingMemorySummaries(backend: AgentBackend?) async -> [ExistingMemorySummary] {
    guard let backend else { return [] }
    let memory = MemoryStore(backend: backend)
    let approved = (try? await memory.listApproved()) ?? []
    let pending = (try? await memory.listPending()) ?? []
    return approved.map { ExistingMemorySummary(text: $0.text, category: $0.category) } +
        pending.map { ExistingMemorySummary(text: $0.text, category: $0.category) }
}

// MARK: - CLI Setup UI

struct CLISetupUI: SetupUI {
    func showProgress(_ step: SetupStepID, message: String) async { print("  ⟳ \(message)") }

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
        return input.isEmpty ? defaultVal : (input == "y" || input == "yes")
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
