// SwooshDaemon/Daemon.swift — swooshd background service
//
// Spawns and supervises an `actantdb serve` child process for the lifetime
// of the daemon, then runs the API server. The supervised base URL is
// exported as ACTANT_BASE_URL so any in-process Swoosh.configure() call
// picks up the live ledger via SwooshKit's env-var path.

import Foundation
import ActantAgent
import SwooshAPI

@main
struct SwooshDaemon {
    static func main() async throws {
        let version = "0.9P"
        printBanner(version: version)

        let port = Int(ProcessInfo.processInfo.environment["SWOOSH_PORT"] ?? "8787") ?? 8787
        let host = ProcessInfo.processInfo.environment["SWOOSH_HOST"] ?? "127.0.0.1"

        // ── Spawn the ActantDB subprocess. Fail loudly if the binary's missing.
        let swooshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
        try? FileManager.default.createDirectory(at: swooshDir, withIntermediateDirectories: true)

        let supervisor = ActantDBSupervisor(
            logOutputTo: swooshDir.appendingPathComponent("logs/actantdb.log")
        )

        let baseURL: URL
        do {
            baseURL = try await supervisor.start(
                dbPath: swooshDir.appendingPathComponent("actant.db")
            )
        } catch {
            log("FATAL: \(error)")
            exit(1)
        }
        log("ActantDB ready at \(baseURL)")
        setenv("ACTANT_BASE_URL", baseURL.absoluteString, 1)

        // ── SIGTERM / SIGINT → cleanly stop the supervisor before exiting.
        let signalHandler = SignalHandler(supervisor: supervisor)
        signalHandler.install()

        log("API server starting on http://\(host):\(port)")
        log("Health: http://\(host):\(port)/health")
        let server = SwooshAPIServer(port: port, hostname: host)
        let app = server.build()

        defer {
            Task { await supervisor.stop() }
        }
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

// MARK: - Signal handler

final class SignalHandler: @unchecked Sendable {
    let supervisor: ActantDBSupervisor
    init(supervisor: ActantDBSupervisor) { self.supervisor = supervisor }

    func install() {
        let action: @convention(c) (Int32) -> Void = { sig in
            // Best-effort: nudge the supervisor and let `defer` in main do the rest.
            print("[swooshd] received signal \(sig), shutting down…")
            exit(0)
        }
        signal(SIGTERM, action)
        signal(SIGINT,  action)
    }
}
