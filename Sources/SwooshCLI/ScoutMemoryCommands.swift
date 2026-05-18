// SwooshCLI/ScoutMemoryCommands.swift — Scout, Memory, Permissions commands + Helpers

import ArgumentParser
import SwooshConfig
import SwooshScout
import SwooshStorage
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

        var sources: [any ScoutSource] = [
            DeviceSource(), InstalledAppsSource(),
            RunningAppsSource(), ShellEnvironmentSource(),
        ]

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

        if !folderPaths.isEmpty {
            sources.append(ProjectFoldersSource(paths: folderPaths))
            sources.append(GitReposSource(paths: folderPaths))
        }
        sources.append(HermesImportSource())

        let pipeline = ScoutPipeline(sources: sources)
        let result = try await pipeline.run(depth: parsedDepth) { msg in print(msg) }

        let config = SwooshConfigStore()
        try config.ensureDirectories()
        let store = try SwooshStateStore()

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

        try await store.appendAuditEvent(
            eventType: "scout.scan_complete", actor: "cli", target: "scout",
            details: "Scanned \(result.sourcesScanned) sources, \(result.recordsCollected) records, \(result.candidatesGenerated) candidates"
        )
        _ = try await store.saveSetupReport(content: result.setupReport)

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
        let store = try SwooshStateStore()
        let candidates = try await store.listMemoryCandidates(status: status)

        if candidates.isEmpty {
            print("No \(status) memory candidates.")
            if status == "pending" { print("Run `swoosh scout run` to scan.") }
            return
        }

        print("─── \(status.capitalized) Memory Candidates (\(candidates.count)) ───\n")
        for (i, c) in candidates.enumerated() {
            print("  \(i + 1). [\(c.category)] \(c.text)")
            print("     confidence: \(String(format: "%.0f%%", c.confidence * 100)) | sensitivity: \(c.sensitivity) | id: \(c.id.prefix(8))…\n")
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
        let store = try SwooshStateStore()
        let memories = try await store.listApprovedMemories()
        guard !memories.isEmpty else { print("No approved memories yet."); return }
        print("─── Approved Memories (\(memories.count)) ───\n")
        for (i, m) in memories.enumerated() {
            print("  \(i + 1). [\(m.category)] \(m.text)")
            print("     approved: \(m.approvedAt)\n")
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
        } else if let prefix = id {
            let candidates = try await store.listMemoryCandidates(status: "pending")
            guard let match = candidates.first(where: { $0.id.hasPrefix(prefix) }) else {
                print("No pending candidate matching '\(prefix)'"); return
            }
            try await store.approveMemoryCandidate(id: match.id)
            print("✓ Approved: \(match.text)")
        }
    }
}

struct MemoryRejectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reject", abstract: "Reject a memory candidate.")
    @Option(name: .long, help: "Reject by ID prefix.")
    var id: String
    func run() async throws {
        let store = try SwooshStateStore()
        let candidates = try await store.listMemoryCandidates(status: "pending")
        guard let match = candidates.first(where: { $0.id.hasPrefix(id) }) else {
            print("No pending candidate matching '\(id)'"); return
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

    let recs = hw.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
    if !recs.isEmpty {
        print("\n  Local models: can run \(recs.map(\.sizeLabel).joined(separator: ", "))")
    }
    print()
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
