// SwooshTUI/SystemDevCommands.swift — 0.9S Development commands that show real state
//
// Three commands that read live filesystem / env state instead of
// printing prose: `/local` (Apple-Silicon detection + model count in
// `~/.swoosh/models`), `/skills` (skill count in `~/.swoosh/skills`),
// `/db` (ActantDB file existence + ACTANT_BASE_URL).
//
// Pure-prose helpers (`/doctor`, `/permissions`, `/firewall`, `/budget`)
// were removed in 0.9S — they printed "Use: `swoosh foo`" templates
// that misled users about what the in-shell command actually did.
// Run those subsystems directly from the CLI instead.

import Foundation
import SwooshTools

func makeSystemDevCommands() -> [SlashCommandDefinition] {

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

    return [localCmd, skillsCmd, dbCmd]
}
