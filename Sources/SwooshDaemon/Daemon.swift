// SwooshDaemon/Daemon.swift — swooshd entry point
//
// The local daemon: manages sessions, workflows, triggers,
// memory, and local model service.

import Foundation

@main
struct SwooshDaemon {
    static func main() async throws {
        print("swooshd starting...")
        // In production: start the Hummingbird server, register triggers,
        // load scheduled workflows, and start the background agent loop.
        print("swooshd is not yet implemented. Run `swoosh chat` instead.")
    }
}
