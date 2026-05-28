// SwooshCLI/CLIBackend.swift — Backend availability check for the CLI (0.4A)
//
// Previously bootstrapped an ActantDB AgentBackend from env vars.
// Now returns nil unconditionally — the CLI uses in-memory stores
// until a durable backend is re-wired through the SwooshTools protocol layer.

import Foundation

/// Returns `true` when `ACTANT_BASE_URL` is set, indicating `swooshd` is
/// running and a durable backend *could* be available. Individual commands
/// use this as a hint to display appropriate messages.
func hasCLIBackendEnvironment() -> Bool {
    ProcessInfo.processInfo.environment["ACTANT_BASE_URL"] != nil
}

/// "Durable backend is not wired — start `swooshd` first or set it up manually."
let cliBackendUnsetMessage = """
    Durable backend is not configured.
    The CLI is running with in-memory stores — data will not persist across runs.
    Start swooshd for durable storage, or set ACTANT_BASE_URL manually.
    """
