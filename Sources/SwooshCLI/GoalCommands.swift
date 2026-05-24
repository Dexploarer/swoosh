// SwooshCLI/GoalCommands.swift — Manage standing goals through the daemon — 0.1A
//
// All operations go through the bearer-gated `/api/goals` surface on the
// local daemon. The CLI doesn't touch the goal store directly — it's the
// human-friendly way to drive the same goal queue the iOS app and the
// daemon autopilot use. Mirrors the shape of PluginCommands.swift.

import ArgumentParser
import Foundation
import SwooshClient
import SwooshConfig

struct GoalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "goal",
        abstract: "List, inspect, set, and abandon standing goals via the daemon.",
        subcommands: [
            GoalListCommand.self,
            GoalShowCommand.self,
            GoalSetCommand.self,
            GoalAbandonCommand.self,
            GoalUpdateCommand.self,
        ],
        defaultSubcommand: GoalListCommand.self
    )
}

// MARK: - list

struct GoalListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List standing goals and their state."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.goals()
        if json {
            try printAsJSON(response)
            return
        }
        guard !response.goals.isEmpty else {
            print("No goals. Create one with `swoosh goal set --statement '…'`.")
            return
        }
        print("ID                       STATE     PROGRESS  STATEMENT")
        for goal in response.goals {
            // `padding(toLength:)` already truncates when the source is
            // longer — matches the pattern used by `swoosh plugin list`.
            let id = goal.id.padding(toLength: 24, withPad: " ", startingAt: 0)
            let state = goal.state.padding(toLength: 9, withPad: " ", startingAt: 0)
            let progress = goal.progress.padding(toLength: 9, withPad: " ", startingAt: 0)
            print("\(id) \(state) \(progress) \(goal.statement)")
        }
    }
}

// MARK: - show

struct GoalShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a goal's iteration trail and current state."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Argument(help: "Goal id.")
    var id: String

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let detail = try await client.goal(id: id)
        if json {
            try printAsJSON(detail)
            return
        }
        print("Goal: \(detail.goal.statement)")
        print("ID:        \(detail.goal.id)")
        print("State:     \(detail.goal.state)")
        print("Progress:  \(detail.goal.progress)")
        print("Created:   \(detail.createdAt)")
        if let parent = detail.parentSessionID {
            print("Session:   \(parent)")
        }
        if detail.iterations.isEmpty {
            print("No iterations yet.")
            return
        }
        print("Iterations:")
        for iteration in detail.iterations {
            let when = ISO8601DateFormatter().string(from: iteration.createdAt)
            print("  \(when)  \(iteration.iteration)/\(detail.maxIterations)  [\(iteration.judgement)] \(iteration.observation)")
            if let rationale = iteration.judgeRationale {
                print("      ↳ \(rationale)")
            }
        }
    }
}

// MARK: - set

struct GoalSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Create a new standing goal."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Option(name: .long, help: "Goal statement, e.g. 'Ship the iOS app to TestFlight'.")
    var statement: String

    @Option(name: .long, help: "Hard ceiling on iterations (default: 20).")
    var maxIterations: Int?

    @Option(name: .long, help: "Optional session id that owns this goal.")
    var sessionID: String?

    func run() async throws {
        let client = try daemon.makeClient()
        let body = GoalSetRequest(
            statement: statement,
            maxIterations: maxIterations,
            parentSessionID: sessionID
        )
        let response = try await client.setGoal(body)
        print("Created \(response.goal.id) — \(response.goal.statement)")
        print(response.message)
    }
}

// MARK: - abandon

struct GoalAbandonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "abandon",
        abstract: "Mark a goal abandoned. Stops the daemon autopilot from advancing it."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Argument(help: "Goal id.")
    var id: String

    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force = false

    func run() async throws {
        let client = try daemon.makeClient()
        if !force {
            print("Abandon goal \(id)? [y/N] ", terminator: "")
            guard let input = readLine()?.lowercased(), input == "y" || input == "yes" else {
                print("Aborted.")
                return
            }
        }
        let response = try await client.abandonGoal(id: id)
        print(response.message)
    }
}

// MARK: - update

struct GoalUpdateCommand: AsyncParsableCommand {
    /// Allowed states the CLI accepts for `--state`. Mirrors
    /// `SwooshGoals.GoalState.allCases` — kept as a local list because
    /// SwooshCLI deliberately doesn't depend on SwooshGoals (the daemon
    /// owns the goal store).
    static let allowedStates: [String] = [
        "pending", "active", "paused", "completed", "abandoned",
    ]

    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Set a goal's state (pending, active, paused, completed, abandoned)."
    )

    @OptionGroup var daemon: DaemonConnectionOptions

    @Argument(help: "Goal id.")
    var id: String

    @Option(name: .long, help: "New state (pending, active, paused, completed, abandoned).")
    var state: String

    mutating func validate() throws {
        guard GoalUpdateCommand.allowedStates.contains(state.lowercased()) else {
            throw ValidationError("Invalid state '\(state)'. Must be one of: \(GoalUpdateCommand.allowedStates.joined(separator: ", ")).")
        }
    }

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.updateGoal(id: id, body: GoalUpdateRequest(state: state.lowercased()))
        print(response.message)
    }
}
