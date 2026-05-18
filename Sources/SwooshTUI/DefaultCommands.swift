// SwooshTUI/DefaultCommands.swift — Built-in slash commands
//
// Returns an array of SlashCommandDefinitions.
// The caller (SwooshShell) registers them into the SlashCommandRegistry.
// Commands reflect real runtime state where possible — no stale milestones.

import Foundation
import SwooshTools

public func makeDefaultCommandDefinitions() -> [SlashCommandDefinition] {
    // ── Core ─────────────────────────────────────────────────

    let helpCmd = SlashCommandDefinition(
        name: "help",
        aliases: ["h", "?"],
        summary: "Show available commands.",
        category: .general
    ) { ctx in
        .success("""

          ─── Swoosh Commands ──────────────────────────────
            GENERAL
              /help               Show this help
              /exit               Exit Swoosh
              /clear              Clear terminal

            AGENT
              /status             Provider, session, budget
              /model [list|set]   Show or switch model
              /tools              List available tools
              /sessions           Manage sessions
              /why                Explain last response context
              /repeat             Save last task as workflow

            PERSONALIZATION
              /scout              Run personalization scan
              /vault [pending|approved]  Manage memory

            SYSTEM
              /doctor             System diagnostics
              /permissions        View and manage permissions
              /firewall           Firewall and approval rules
              /budget             Token and cost usage

            DEVELOPMENT
              /local              Local model (MLX) status
              /skills             Agent learned behaviors
              /db                 Storage backend status

          Type any message to chat with the agent.

        """)
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

    let statusCmd = SlashCommandDefinition(
        name: "status",
        aliases: ["s"],
        summary: "Show provider, session, and budget status.",
        category: .agent
    ) { ctx in
        let env = ProcessInfo.processInfo.environment
        let providerKeys: [(String, String)] = [
            ("OPENAI_API_KEY", "openai"), ("ANTHROPIC_API_KEY", "anthropic"),
            ("OPENROUTER_API_KEY", "openrouter"), ("GEMINI_API_KEY", "gemini"),
            ("DEEPSEEK_API_KEY", "deepseek"), ("GROQ_API_KEY", "groq"),
        ]
        let active = providerKeys.first { env[$0.0] != nil }
        let providerStr = active.map { "✅ \($0.1)" } ?? "⚠️  none — run `swoosh discover-credentials`"
        return .success("""

          ─── Status ───────────────────────────────────────
            Session:  \(ctx.sessionID)
            Provider: \(providerStr)
            Doctor:   `swoosh doctor` for full system check

        """)
    }

    let modelCmd = SlashCommandDefinition(
        name: "model",
        aliases: ["m"],
        summary: "Show or change the current model.",
        category: .agent
    ) { ctx in
        let sub = ctx.arguments.first ?? "show"
        if sub == "list" {
            return .success("""

              ─── Providers ────────────────────────────────────
                Remote:
                  openai       gpt-4o, o3, o4-mini, codex-mini
                  anthropic    claude-sonnet-4, claude-3.5-haiku
                  openrouter   200+ models
                  gemini       gemini-2.5-pro/flash
                  deepseek     deepseek-chat/reasoner
                  groq         llama-4-scout, llama-3.3-70b

                Local (Apple Silicon):
                  mlx          ~/.swoosh/models/

                Use: swoosh config set provider <name>

            """)
        }
        let env = ProcessInfo.processInfo.environment
        let keys: [(String, String)] = [
            ("OPENAI_API_KEY", "openai"), ("ANTHROPIC_API_KEY", "anthropic"),
            ("OPENROUTER_API_KEY", "openrouter"), ("GEMINI_API_KEY", "gemini"),
        ]
        let active = keys.first { env[$0.0] != nil }.map { $0.1 } ?? "not configured"
        return .success("""

          ─── Model ────────────────────────────────────────
            Active: \(active)
            Use /model list   — see all providers
            Use /model set <provider> — switch

        """)
    }

    let toolsCmd = SlashCommandDefinition(
        name: "tools",
        aliases: ["t"],
        summary: "List available tools.",
        category: .agent
    ) { _ in
        .success("""

          ─── Tools ────────────────────────────────────────
            File:    file.read  file.write  file.list  file.find
            Shell:   shell.run  shell.script
            Browser: browser.navigate  browser.click  browser.type
                     browser.screenshot  browser.extract
            Memory:  memory.listApproved  memory.listPending
            Git:     git.status  git.diff  git.commit  git.push
            MCP:     mcp.<server>.<tool>  (auto-discovered)

            Use: swoosh tools list   for full details

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

    let whyCmd = SlashCommandDefinition(
        name: "why",
        summary: "Explain what context was used in the last response.",
        category: .agent
    ) { _ in
        .success("""

          ─── /why ─────────────────────────────────────────
            After an agent reply, /why shows:
              • Approved memories injected
              • Setup report used
              • Permissions considered
              • Firewall decisions

        """)
    }

    let repeatCmd = SlashCommandDefinition(
        name: "repeat",
        aliases: ["r"],
        summary: "Turn the last task into a repeatable workflow.",
        category: .agent
    ) { _ in
        .success("""

          ─── /repeat ──────────────────────────────────────
            After a successful task, /repeat:
              1. Inspects the session trace
              2. Generates a workflow draft
              3. Lists required permissions
              4. Saves as a disabled workflow

            Use: swoosh workflow list   to see saved workflows

        """)
    }

    // ── Personalization ──────────────────────────────────────

    let scoutCmd = SlashCommandDefinition(
        name: "scout",
        summary: "Run Swoosh Scout personalization scan.",
        category: .personalization
    ) { _ in
        .success("""

          ─── Scout ────────────────────────────────────────
            Scans your environment to build memory candidates.

            Use:  swoosh scout run
                  swoosh scout run --depth deep
                  swoosh scout run --folders ~/Projects

        """)
    }

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
        statusCmd, modelCmd, toolsCmd, sessionsCmd, whyCmd, repeatCmd,
        scoutCmd, vaultCmd,
    ] + makeSystemDevCommands()
}
