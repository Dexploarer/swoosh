// SwooshDaemon/DaemonHelp.swift — 0.9S Banner / help / log helpers
//
// Static console-output helpers used by `SwooshDaemon.main()`. Extracted
// from `Daemon.swift` so the boot orchestration there stays focused.

import Foundation

extension SwooshDaemon {

    static func printBanner(version: String) {
        print("""

        ┌──────────────────────────────────────┐
        │  swooshd v\(version) — Swoosh Daemon     │
        │  Press Ctrl-C to stop                │
        └──────────────────────────────────────┘
        """)
    }

    static func printDaemonHelp(version: String) {
        print("""
        swooshd \(version) — Swoosh local daemon

        Runs the Swoosh agent kernel, spawns ActantDB, and serves the
        bearer-gated HTTP API that the Swoosh CLI and iPhone app talk to.

        USAGE:
            swooshd [--help] [--version]

        swooshd takes no subcommands — it runs until stopped with Ctrl-C.
        Configuration is by environment variable:

            SWOOSH_HOST          Bind address (default 127.0.0.1; 0.0.0.0 for LAN)
            SWOOSH_PORT          TCP port (default 8787)
            SWOOSH_API_TOKEN     Bearer token (default: persisted/generated)
            SWOOSH_CONFIG_DIR    State directory (default ~/.swoosh)
            SWOOSH_ACTANTDB_PATH Explicit path to the actantdb binary

        The resolved API token is written to ~/.swoosh/api_token — paste it
        into the Swoosh iOS app to pair an iPhone.
        """)
    }

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] swooshd: \(message)")
    }
}
