// SwooshTUI/SystemDevCommands.swift — System and Development slash commands

import Foundation
import SwooshTools

func makeSystemDevCommands() -> [SlashCommandDefinition] {
    // ── System ───────────────────────────────────────────────

    let doctorCmd = SlashCommandDefinition(
        name: "doctor",
        aliases: ["dx"],
        summary: "Run system diagnostics and optimization checks.",
        category: .system
    ) { _ in
        .success("""

          ─── Doctor ───────────────────────────────────────
            Full system diagnostics:
              • Disk, memory, platform
              • Provider keys, Keychain
              • Config, budget, storage
              • Privacy (log leak detection)

            Use: swoosh doctor
                 swoosh doctor --fix
                 swoosh doctor --json

        """)
    }

    let permissionsCmd = SlashCommandDefinition(
        name: "permissions",
        aliases: ["perms", "p"],
        summary: "Show and manage permission profile.",
        category: .system
    ) { _ in
        .success("""

          ─── Permissions ──────────────────────────────────
            Profile: safe (default)

            Granted: deviceProfileRead, installedAppsRead
            Gated:   shellRun, fileWrite, networkFetch,
                     calendarRead, browserHistoryRead

            Use: swoosh permissions grant <name>
                 swoosh setup permissions

        """)
    }

    let firewallCmd = SlashCommandDefinition(
        name: "firewall",
        aliases: ["fw"],
        summary: "Show firewall and tool approval rules.",
        category: .system
    ) { _ in
        .success("""

          ─── Firewall ─────────────────────────────────────
            Read-only tools:  auto-approved
            Shell:            requires approval
            File write:       requires approval
            Network:          requires approval

            Use: swoosh approvals list
                 swoosh firewall allow <tool>
                 swoosh firewall deny <tool>

        """)
    }

    let budgetCmd = SlashCommandDefinition(
        name: "budget",
        aliases: ["cost"],
        summary: "Show token and cost usage.",
        category: .system
    ) { _ in
        .success("""

          ─── Budget ───────────────────────────────────────
            Use: swoosh usage
                 swoosh usage --week
                 swoosh budget set --daily 25.00
                 swoosh budget set --session 5.00

        """)
    }

    // ── Development ──────────────────────────────────────────

    let localCmd = SlashCommandDefinition(
        name: "local",
        summary: "Show local model (MLX) status.",
        category: .development
    ) { _ in
        let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let modelDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh/models")
        let modelCount = (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path))?.count ?? 0
        #if arch(arm64)
        let silicon = "✅ Apple Silicon"
        #else
        let silicon = "⚠️  Intel — MLX not available"
        #endif
        return .success("""

          ─── Local Models ─────────────────────────────────
            Platform: \(silicon)  ·  \(ram)GB RAM
            Installed: \(modelCount) model(s) in ~/.swoosh/models/
            Use: swoosh model pull <name>   — download
                 swoosh model list          — list local
                 swoosh model use local     — switch to local

        """)
    }

    let skillsCmd = SlashCommandDefinition(
        name: "skills",
        aliases: ["sk"],
        summary: "Show agent skills (learned behaviors).",
        category: .development
    ) { _ in
        let skillDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh/skills")
        let skillCount = (try? FileManager.default.contentsOfDirectory(atPath: skillDir.path))?.count ?? 0
        return .success("""

          ─── Skills ───────────────────────────────────────
            Learned: \(skillCount) skill(s) in ~/.swoosh/skills/

            The agent saves skills from completed tasks.
            Use: swoosh skills list
                 swoosh skills search <query>
                 swoosh skills show <id>

        """)
    }

    let dbCmd = SlashCommandDefinition(
        name: "db",
        summary: "Show storage backend status.",
        category: .development
    ) { ctx in
        switch ctx.arguments.first ?? "status" {
        case "start": return .success("  Use: swoosh db start")
        case "stop":  return .success("  Use: swoosh db stop")
        default:
            let dbPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".swoosh/actant.db").path
            let exists = FileManager.default.fileExists(atPath: dbPath)
            let baseURL = ProcessInfo.processInfo.environment["ACTANT_BASE_URL"] ?? "(unset — start swooshd)"
            return .success("""

              ─── Storage ──────────────────────────────────────
                Backend: ActantDB  ·  \(exists ? "✅ actant.db exists" : "⚠️ actant.db not yet created")
                Server:  \(baseURL)
                Paths:   ~/.swoosh/actant.db
                         ~/.swoosh/checkpoints/
                         ~/.swoosh/skills/

            """)
        }
    }

    return [doctorCmd, permissionsCmd, firewallCmd, budgetCmd, localCmd, skillsCmd, dbCmd]
}
