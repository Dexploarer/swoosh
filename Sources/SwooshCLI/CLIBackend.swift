// SwooshCLI/CLIBackend.swift — ActantDB backend bootstrap for the CLI (0.4A)
//
// Both `scout` / `memory` and `chat` / `ask` build their backend from the
// same env vars `swooshd` exports. The CLI is the only consumer of this
// helper; it is intentionally a plain free function so subcommands stay
// stateless and the bootstrap is a one-liner.

import Foundation
import ActantDB
import ActantAgent

/// Build an `AgentBackend` if `ACTANT_BASE_URL` is set. Returns nil when the
/// user is running the CLI standalone (no swooshd, no env), in which case
/// callers should fall back to in-memory behaviour.
func loadCLIBackend() -> AgentBackend? {
    let env = ProcessInfo.processInfo.environment
    guard let raw = env["ACTANT_BASE_URL"], let url = URL(string: raw) else { return nil }
    return AgentBackend(
        client: ActantClient(baseURL: url, token: env["ACTANT_TOKEN"]),
        workspaceID: env["ACTANT_WORKSPACE_ID"] ?? "ws_swoosh",
        actorID: env["ACTANT_ACTOR_ID"] ?? "act_swoosh_cli"
    )
}

/// "ACTANT_BASE_URL is unset — start `swooshd` first or set it manually."
let cliBackendUnsetMessage = """
    ActantDB backend is not configured.
    Either start swooshd (which exports ACTANT_BASE_URL) or set
    ACTANT_BASE_URL=http://127.0.0.1:PORT manually before running this command.
    """
