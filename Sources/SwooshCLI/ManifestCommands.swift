// SwooshCLI/ManifestCommands.swift — Manage manifestation passes through the daemon — 0.1A
//
// `swoosh manifest now / history / show` — the operator-facing surface
// for Swoosh's "dreaming" pillar. All operations go through the
// bearer-gated `/api/manifestations` surface on the local daemon; the
// scheduler still drives automatic firing — these commands just expose
// the manual triggers and inspection endpoints.

import ArgumentParser
import Foundation
import SwooshClient
import SwooshConfig

struct ManifestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "manifest",
        abstract: "List, inspect, and trigger manifestation passes via the daemon.",
        subcommands: [
            ManifestHistoryCommand.self,
            ManifestShowCommand.self,
            ManifestNowCommand.self,
            ManifestDeleteCommand.self,
        ],
        defaultSubcommand: ManifestHistoryCommand.self
    )
}

// MARK: - history

struct ManifestHistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List recent manifestation passes."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.manifestations()
        if json {
            try printAsJSON(response)
            return
        }
        guard !response.manifestations.isEmpty else {
            print("No manifestations recorded. Trigger one with `swoosh manifest now`.")
            return
        }
        print("ID                       STATUS     STARTED              PROPOSALS  TRIGGER")
        for record in response.manifestations {
            // `padding(toLength:)` already truncates when the source is
            // longer — matches the pattern used by `swoosh plugin list`.
            let id = record.id.padding(toLength: 24, withPad: " ", startingAt: 0)
            let status = record.status.padding(toLength: 10, withPad: " ", startingAt: 0)
            let started = ISO8601DateFormatter().string(from: record.startedAt)
                .padding(toLength: 20, withPad: " ", startingAt: 0)
            let proposals = "\(record.proposalCount)".padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(id) \(status) \(started) \(proposals) \(record.triggerReason)")
        }
    }
}

// MARK: - show

struct ManifestShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show one manifestation pass — full phase trace and proposal list."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Argument(help: "Manifestation id.")
    var id: String

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let detail = try await client.manifestation(id: id)
        if json {
            try printAsJSON(detail)
            return
        }
        print("Manifestation: \(detail.manifestation.id)")
        print("Status:        \(detail.manifestation.status)")
        print("Trigger:       \(detail.manifestation.triggerReason)")
        print("Started:       \(ISO8601DateFormatter().string(from: detail.manifestation.startedAt))")
        if let finished = detail.finishedAt {
            print("Finished:      \(ISO8601DateFormatter().string(from: finished))")
        }
        if let summary = detail.manifestation.summary {
            print("Summary:")
            for line in summary.components(separatedBy: "\n") {
                print("  \(line)")
            }
        }
        if !detail.phases.isEmpty {
            print("Phases:")
            for phase in detail.phases {
                let when = ISO8601DateFormatter().string(from: phase.startedAt)
                print("  \(when)  \(phase.name) — \(phase.observation ?? "")")
            }
        }
        if !detail.proposals.isEmpty {
            print("Proposals (\(detail.proposals.count)):")
            for proposal in detail.proposals {
                let confidence = String(format: "%.2f", proposal.confidence)
                print("  [\(proposal.kind)] \(proposal.title)  (confidence \(confidence))")
                print("      ↳ \(proposal.rationale)")
            }
        }
    }
}

// MARK: - now

struct ManifestNowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "now",
        abstract: "Trigger a manifestation pass immediately."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Option(name: .long, help: "Reason string recorded on the pass (default: 'manual-cli').")
    var reason: String?

    func run() async throws {
        let client = try daemon.makeClient()
        let body = ManifestationRunRequest(triggerReason: reason ?? "manual-cli")
        let detail = try await client.runManifestation(body)
        print("Manifestation \(detail.manifestation.id) — \(detail.manifestation.status)")
        if let summary = detail.manifestation.summary {
            print(summary)
        }
        if !detail.proposals.isEmpty {
            print("Proposals: \(detail.proposals.count)")
        }
    }
}

// MARK: - delete

struct ManifestDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a manifestation record from the store."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Argument(help: "Manifestation id.")
    var id: String

    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force = false

    func run() async throws {
        let client = try daemon.makeClient()
        if !force {
            print("Delete manifestation \(id)? [y/N] ", terminator: "")
            guard let input = readLine()?.lowercased(), input == "y" || input == "yes" else {
                print("Aborted.")
                return
            }
        }
        _ = try await client.deleteManifestation(id: id)
        print("Deleted \(id).")
    }
}
