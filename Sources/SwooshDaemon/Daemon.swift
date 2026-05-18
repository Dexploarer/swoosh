// SwooshDaemon/Daemon.swift — swooshd background service
//
// Manages: API server, trigger polling, session cleanup, budget monitoring.
// Run as: swooshd  (launchd: ~/Library/LaunchAgents/ai.swoosh.daemon.plist)

import Foundation
import SwooshAPI

@main
struct SwooshDaemon {
    static func main() async throws {
        let version = "0.9P"
        printBanner(version: version)

        let port = Int(ProcessInfo.processInfo.environment["SWOOSH_PORT"] ?? "8787") ?? 8787
        let host = ProcessInfo.processInfo.environment["SWOOSH_HOST"] ?? "127.0.0.1"

        log("API server starting on http://\(host):\(port)")
        log("Health: http://\(host):\(port)/health")

        // Start the API server (blocks until terminated)
        let server = SwooshAPIServer(port: port, hostname: host)
        let app = server.build()
        try await app.run()
    }

    static func printBanner(version: String) {
        print("""

        ┌──────────────────────────────────────┐
        │  swooshd v\(version) — Swoosh Daemon     │
        │  Press Ctrl-C to stop                │
        └──────────────────────────────────────┘
        """)
    }

    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] swooshd: \(message)")
    }
}
