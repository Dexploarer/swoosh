// SwooshTUI/SwooshShell.swift — Hermes-like interactive shell
//
// The core REPL loop: banner → prompt → parse → execute → display.
// Preserves Hermes-style flow with Swoosh-native commands.

import Foundation

// MARK: - Shell state

/// Current shell display state, shown in the banner/status bar.
public struct ShellStatus: Sendable {
    public var model: String
    public var mode: String
    public var approvedMemoryCount: Int
    public var pendingCandidateCount: Int
    public var permissionProfile: String
    public var statePlane: String
    public var sessionID: String

    public init(
        model: String = "not configured",
        mode: String = "interactive",
        approvedMemoryCount: Int = 0,
        pendingCandidateCount: Int = 0,
        permissionProfile: String = "safe",
        statePlane: String = "SQLite",
        sessionID: String = "default"
    ) {
        self.model = model
        self.mode = mode
        self.approvedMemoryCount = approvedMemoryCount
        self.pendingCandidateCount = pendingCandidateCount
        self.permissionProfile = permissionProfile
        self.statePlane = statePlane
        self.sessionID = sessionID
    }
}

// MARK: - Shell

/// The interactive Swoosh shell — Hermes-like REPL with slash commands.
public final class SwooshShell: @unchecked Sendable {
    public let registry: SlashCommandRegistry
    private var status: ShellStatus
    private let sessionID: String
    private var running = true

    public init(registry: SlashCommandRegistry, status: ShellStatus = ShellStatus()) {
        self.registry = registry
        self.status = status
        self.sessionID = status.sessionID
    }

    /// Print the Hermes-style banner with current status.
    public func printBanner() {
        let memStr = "\(status.approvedMemoryCount) approved, \(status.pendingCandidateCount) pending"
        print("""

        ╔═══════════════════════════════════════════════╗
        ║                   Swoosh                      ║
        ║     Swift-native agent runtime for macOS      ║
        ╚═══════════════════════════════════════════════╝

          Model:        \(status.model)
          Mode:         \(status.mode)
          Memory:       \(memStr)
          Permissions:  \(status.permissionProfile)
          State plane:  \(status.statePlane)
          Session:      \(sessionID)

          Type /help for commands, or ask a question.

        """)
    }

    /// Print the prompt and read a line.
    private func readPrompt() -> String? {
        print("\u{001B}[36mswoosh>\u{001B}[0m ", terminator: "")
        return readLine()
    }

    /// Run the interactive REPL loop.
    public func run() async {
        printBanner()

        while running {
            guard let line = readPrompt() else {
                // EOF
                running = false
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Slash command?
            if trimmed.hasPrefix("/") {
                guard let result = await registry.parse(line: trimmed, sessionID: sessionID) else {
                    continue
                }
                handleResult(result)
                continue
            }

            // Plain text → agent ask (placeholder for 0.3A)
            print("")
            print("  \u{001B}[33m⟳\u{001B}[0m Agent kernel not yet connected.")
            print("  Run `swoosh setup quick` to configure a model,")
            print("  or use `/help` to explore available commands.")
            print("")
        }

        print("\nGoodbye.\n")
    }

    /// Handle a slash command result.
    private func handleResult(_ result: SlashCommandResult) {
        switch result {
        case .success(let msg):
            if !msg.isEmpty { print(msg) }
        case .error(let msg):
            print("\n  \u{001B}[31m✗\u{001B}[0m \(msg)\n")
        case .exit:
            running = false
        case .multiline(let lines):
            for line in lines { print(line) }
        }
    }

    /// Update the status (for live refresh).
    public func updateStatus(_ newStatus: ShellStatus) {
        self.status = newStatus
    }
}
