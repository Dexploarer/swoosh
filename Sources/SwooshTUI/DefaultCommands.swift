// SwooshTUI/DefaultCommands.swift — 0.9S Built-in slash commands
//
// Returns an array of SlashCommandDefinitions wired into
// `SlashCommandRegistry` by `SwooshShell`'s caller (today, the
// `swoosh chat` subcommand).
//
// Scope intentionally narrow: only commands that actually do something
// inside the shell ship here. Status / personalization / firewall / etc.
// live as standalone `swoosh <subcommand>` CLIs — the previous TUI shipped
// prose stubs ("Use: `swoosh foo`") that pretended to be implementations;
// those were removed in 0.9S because they misled users about what
// `/scout` or `/doctor` actually did from inside the shell.
//
// `/help` is rendered live from the registry (`registry.helpText()` —
// see SlashCommand.swift), so adding a new command auto-surfaces in
// the help output instead of waiting for someone to update a literal.

import Foundation
import SwooshTools

/// Build the default set of in-shell slash commands.
///
/// `registry` is passed in so `/help` can render the live command list
/// via `registry.helpText()` rather than a hand-typed literal that
/// silently drifts as commands are added/removed.
public func makeDefaultCommandDefinitions(
    registry: SlashCommandRegistry
) -> [SlashCommandDefinition] {

    // ── Core ─────────────────────────────────────────────────

    let helpCmd = SlashCommandDefinition(
        name: "help",
        aliases: ["h", "?"],
        summary: "Show available commands.",
        category: .general
    ) { [weak registry] _ in
        guard let registry else { return .success("") }
        let text = await registry.helpText()
        return .success(text)
    }

    let exitCmd = SlashCommandDefinition(
        name: "exit",
        aliases: ["quit", "q"],
        summary: "Exit Swoosh.",
        category: .general,
        handler: { _ in .exit }
    )

    let clearCmd = SlashCommandDefinition(
        name: "clear",
        aliases: ["cls"],
        summary: "Clear the terminal.",
        category: .general,
        handler: { _ in .success("\u{001B}[2J\u{001B}[H") }
    )

    // ── Agent ─────────────────────────────────────────────────

    let toolsCmd = SlashCommandDefinition(
        name: "tools",
        aliases: ["t"],
        summary: "Pointers to tool discovery.",
        category: .agent
    ) { _ in
        .success("""

          ─── Tools ────────────────────────────────────────
            The live tool registry lives in `swooshd` — query it from
            outside the shell:

              swoosh tools list                — all tools + risk + policy
              swoosh tools schema <tool-name>  — JSON schema for one tool
              swoosh tools enabled             — only enabled tools

        """)
    }

    let sessionsCmd = SlashCommandDefinition(
        name: "sessions",
        summary: "Manage chat sessions.",
        category: .agent
    ) { ctx in
        .success("""

          ─── Sessions ─────────────────────────────────────
            Current: \(ctx.sessionID)
            Use: swoosh sessions list | resume <id> | delete <id>

        """)
    }

    // ── Personalization ──────────────────────────────────────

    let vaultCmd = SlashCommandDefinition(
        name: "vault",
        aliases: ["v", "memory"],
        summary: "View and manage memories.",
        category: .personalization
    ) { ctx in
        switch ctx.arguments.first ?? "status" {
        case "pending", "list":
            return .success("\n  ─── Pending Memory Candidates ───\n  Use: swoosh memory list\n")
        case "approved", "show":
            return .success("\n  ─── Approved Memories ───\n  Use: swoosh memory show\n")
        default:
            return .success("""

              ─── Memory Vault ─────────────────────────────────
                /vault pending    — pending candidates
                /vault approved   — approved memories
                swoosh memory list | approve | reject --id <id>

            """)
        }
    }

    return [
        helpCmd, exitCmd, clearCmd,
        toolsCmd, sessionsCmd,
        vaultCmd
    ] + makeSystemDevCommands()
}
