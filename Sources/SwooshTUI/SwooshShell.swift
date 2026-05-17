// SwooshTUI/SwooshShell.swift — Hermes-like interactive shell
//
// The core REPL loop: banner → prompt → parse → execute → display.
// Preserves Hermes-style flow with Swoosh-native commands.
// 0.9P: Now wired to AgentKernel for real inference.

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
    public var providerStatus: String

    public init(
        model: String = "not configured",
        mode: String = "interactive",
        approvedMemoryCount: Int = 0,
        pendingCandidateCount: Int = 0,
        permissionProfile: String = "safe",
        statePlane: String = "SQLite",
        sessionID: String = "default",
        providerStatus: String = "none"
    ) {
        self.model = model
        self.mode = mode
        self.approvedMemoryCount = approvedMemoryCount
        self.pendingCandidateCount = pendingCandidateCount
        self.permissionProfile = permissionProfile
        self.statePlane = statePlane
        self.sessionID = sessionID
        self.providerStatus = providerStatus
    }
}

// MARK: - Agent handler

/// Callback that the shell invokes when the user types plain text (non-slash input).
/// Input: plain text. Output: agent response string + model name used.
public typealias AgentHandler = @Sendable (String, String) async throws -> (response: String, model: String)

// MARK: - Shell

/// The interactive Swoosh shell — Hermes-like REPL with slash commands.
public final class SwooshShell: @unchecked Sendable {
    public let registry: SlashCommandRegistry
    private var status: ShellStatus
    private let sessionID: String
    private var running = true
    private let agentHandler: AgentHandler?

    public init(registry: SlashCommandRegistry, status: ShellStatus = ShellStatus(),
                agentHandler: AgentHandler? = nil) {
        self.registry = registry
        self.status = status
        self.sessionID = status.sessionID
        self.agentHandler = agentHandler
    }

    /// Print the Hermes-style banner with current status.
    public func printBanner() {
        let memStr = "\(status.approvedMemoryCount) approved, \(status.pendingCandidateCount) pending"
        let providerLine = status.providerStatus == "none"
            ? "\u{001B}[33mnot configured\u{001B}[0m"
            : "\u{001B}[32m\(status.providerStatus)\u{001B}[0m"
        print("""

        ╔═══════════════════════════════════════════════╗
        ║                   Swoosh                      ║
        ║     Swift-native agent runtime for macOS      ║
        ╚═══════════════════════════════════════════════╝

          Model:        \(status.model)
          Provider:     \(providerLine)
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

            // Plain text → agent
            await handleAgentRequest(trimmed)
        }

        print("\nGoodbye.\n")
    }

    /// Handle plain text input → route to agent kernel.
    private func handleAgentRequest(_ input: String) async {
        guard let handler = agentHandler else {
            print("")
            print("  \u{001B}[33m⟳\u{001B}[0m Agent kernel not yet connected.")
            print("  Run `swoosh setup quick` to configure a model,")
            print("  or use `/help` to explore available commands.")
            print("")
            return
        }

        // Show thinking indicator
        print("")
        print("  \u{001B}[36m⟳\u{001B}[0m Thinking...", terminator: "")
        fflush(stdout)

        do {
            let (response, model) = try await handler(input, sessionID)

            // Clear thinking indicator and show response
            print("\r\u{001B}[K") // clear line
            print("  \u{001B}[32m◆\u{001B}[0m \u{001B}[90m(\(model))\u{001B}[0m")
            print("")
            for responseLine in response.components(separatedBy: "\n") {
                print("    \(responseLine)")
            }
            print("")
        } catch {
            print("\r\u{001B}[K") // clear line
            print("  \u{001B}[31m✗\u{001B}[0m Agent error: \(error)")
            print("")
            // Provide actionable guidance
            let errStr = "\(error)"
            if errStr.contains("authMissing") || errStr.contains("API key") {
                print("    Run: swoosh provider auth <provider> --api-key")
            } else if errStr.contains("allRoutesFailed") {
                print("    No providers configured. Run: swoosh provider setup")
            }
            print("")
        }
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
