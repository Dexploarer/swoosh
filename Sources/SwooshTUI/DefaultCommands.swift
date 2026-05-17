// SwooshTUI/DefaultCommands.swift — Built-in slash command definitions
//
// Registers all Hermes-like + Swoosh-native commands.
// Implementation-heavy commands delegate to modules;
// placeholder commands clearly state what milestone implements them.

import Foundation

/// Register all default Swoosh slash commands.
public func registerDefaultCommands(on registry: SlashCommandRegistry) async {
    await registry.registerAll([

        // ── General ──────────────────────────────────────────────

        SlashCommandDefinition(
            name: "help",
            aliases: ["h", "?"],
            summary: "Show available commands.",
            category: .general
        ) { _ in
            let text = await registry.helpText()
            return .success(text)
        },

        SlashCommandDefinition(
            name: "exit",
            aliases: ["quit", "q"],
            summary: "Exit the Swoosh shell.",
            category: .general
        ) { _ in
            return .exit
        },

        SlashCommandDefinition(
            name: "clear",
            summary: "Clear the screen.",
            category: .general
        ) { _ in
            print("\u{001B}[2J\u{001B}[H")
            return .success("")
        },

        SlashCommandDefinition(
            name: "status",
            aliases: ["s"],
            summary: "Show current session status.",
            category: .general
        ) { ctx in
            return .success("""

              ─── Session Status ───────────────────────────────
                Session:   \(ctx.sessionID)
                Ready for agent queries after model configuration.
                Run /model to configure, or /scout to personalize.

            """)
        },

        // ── Agent ────────────────────────────────────────────────

        SlashCommandDefinition(
            name: "model",
            aliases: ["m"],
            summary: "Show or change the current model.",
            category: .agent
        ) { _ in
            return .success("""

              ─── Model ────────────────────────────────────────
                Current: not configured
                Available:
                  1. Local MLX (Apple Silicon)
                  2. OpenAI-compatible
                  3. Anthropic
                  4. OpenRouter

                Use: /model set <provider>
                → Milestone 0.3A: Model router integration.

            """)
        },

        SlashCommandDefinition(
            name: "tools",
            aliases: ["t"],
            summary: "List available tools.",
            category: .agent
        ) { _ in
            return .success("""

              ─── Tools ────────────────────────────────────────
                Built-in:
                  • memory.listApproved     (ready)
                  • memory.listPending      (ready)
                  • scout.status            (ready)
                  • permissions.summary     (ready)
                  • setupReport.latest      (ready)

                Shell/file/browser tools → Milestone 0.4A.

            """)
        },

        SlashCommandDefinition(
            name: "sessions",
            summary: "Manage chat sessions.",
            category: .agent
        ) { _ in
            return .success("""

              ─── Sessions ─────────────────────────────────────
                Current: default
                No saved sessions yet.

                Use: /sessions list | new | resume <id>
                → Milestone 0.3A: Session persistence.

            """)
        },

        SlashCommandDefinition(
            name: "why",
            summary: "Explain what context was used in the last response.",
            category: .agent
        ) { _ in
            return .success("""

              ─── /why ─────────────────────────────────────────
                No agent response yet in this session.

                After an agent response, /why will show:
                  • Approved memories used
                  • Setup report used
                  • Permissions considered
                  • Data sources NOT used (cookies, raw secrets, etc.)
                  • Whether rejected memories were excluded

                → Milestone 0.3A: Audit + context transparency.

            """)
        },

        SlashCommandDefinition(
            name: "repeat",
            aliases: ["r"],
            summary: "Turn the last successful task into a repeatable workflow.",
            category: .agent
        ) { _ in
            return .success("""

              ─── /repeat ──────────────────────────────────────
                No completed task to repeat yet.

                After a successful agent task, /repeat will:
                  1. Inspect the session
                  2. Generate a draft workflow
                  3. List required permissions
                  4. Ask for confirmation
                  5. Save as disabled workflow

                → Milestone 0.5A: Workflow generator.

            """)
        },

        // ── Personalization ──────────────────────────────────────

        SlashCommandDefinition(
            name: "scout",
            summary: "Run Swoosh Scout personalization scan.",
            category: .personalization
        ) { _ in
            return .success("""

              ─── Swoosh Scout ─────────────────────────────────
                Scout scans your environment with permission to
                generate memory candidates for personalization.

                Use the CLI for a full scan:
                  swoosh scout run
                  swoosh scout run --depth deep
                  swoosh scout run --folders ~/Projects

                Or run inline:
                  /scout run           (safe default scan)
                  /scout folders       (select folders to scan)

                → Scout is ready. Run `swoosh scout run` in a terminal.

            """)
        },

        SlashCommandDefinition(
            name: "vault",
            aliases: ["v", "memory"],
            summary: "View and manage memory candidates and approved memories.",
            category: .personalization
        ) { ctx in
            let sub = ctx.arguments.first ?? "status"
            switch sub {
            case "pending", "list":
                return .success("""

                  ─── Memory Vault — Pending ───────────────────────
                    Use: swoosh memory list
                    Or:  swoosh memory list --status approved

                """)
            case "approved", "show":
                return .success("""

                  ─── Memory Vault — Approved ──────────────────────
                    Use: swoosh memory show

                """)
            default:
                return .success("""

                  ─── Memory Vault ─────────────────────────────────
                    Vault manages your memory candidates and
                    approved memories.

                    Subcommands:
                      /vault pending    — show pending candidates
                      /vault approved   — show approved memories

                    CLI commands:
                      swoosh memory list
                      swoosh memory approve
                      swoosh memory reject --id <id>
                      swoosh memory show

                """)
            }
        },

        // ── System ───────────────────────────────────────────────

        SlashCommandDefinition(
            name: "permissions",
            aliases: ["perms", "p"],
            summary: "Show permission profile and status.",
            category: .system
        ) { _ in
            return .success("""

              ─── Permissions ──────────────────────────────────
                Profile: safe (default)

                Granted:
                  ✓ deviceProfileRead
                  ✓ installedAppsRead
                  ✓ runningAppsRead

                Pending:
                  ○ selectedFolderRead
                  ○ calendarRead

                Denied:
                  ✗ browserHistoryRead
                  ✗ shellRun

                Use: swoosh setup permissions
                     /permissions grant <name>
                     /permissions deny <name>

            """)
        },

        SlashCommandDefinition(
            name: "firewall",
            aliases: ["fw"],
            summary: "Show firewall rules and tool approval status.",
            category: .system
        ) { _ in
            return .success("""

              ─── Firewall ─────────────────────────────────────
                The firewall controls which tools the agent can
                use and which operations require approval.

                Current rules:
                  • Read-only tools: auto-approved
                  • Shell execution: requires approval
                  • File write: requires approval
                  • Network access: requires approval

                → Milestone 0.4A: Typed tool approvals.

            """)
        },

        // ── Development ──────────────────────────────────────────

        SlashCommandDefinition(
            name: "local",
            summary: "Show local model and MLX status.",
            category: .development
        ) { _ in
            return .success("""

              ─── Local Models ─────────────────────────────────
                MLX status: not configured
                Use `swoosh model` to set up local inference.

                → Milestone 0.3A: MLX model integration.

            """)
        },

        SlashCommandDefinition(
            name: "db",
            summary: "Show SwooshDB / SpacetimeDB status.",
            category: .development
        ) { ctx in
            let sub = ctx.arguments.first ?? "status"
            switch sub {
            case "start":
                return .success("""

                  Use: swoosh db start
                  (CLI command — runs SpacetimeDB locally)

                """)
            case "stop":
                return .success("  Use: swoosh db stop")
            default:
                return .success("""

                  ─── SwooshDB ─────────────────────────────────────
                    Backend: SQLite (default)
                    SpacetimeDB: spike available (0.2A)
                    Status: local SQLite at ~/.swoosh/state.db

                    CLI commands:
                      swoosh db start    — start local SpacetimeDB
                      swoosh db stop     — stop local SpacetimeDB
                      swoosh db status   — check status

                """)
            }
        },
    ])
}
