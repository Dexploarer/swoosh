// SwooshDaemon/DaemonSignalHandler.swift — 0.9S SIGTERM/SIGINT trap
//
// Installs a C-convention signal handler so Ctrl-C and `kill <pid>`
// gracefully exit the daemon. Process exit is the contract.

import Foundation

final class SignalHandler: @unchecked Sendable {
    init() {}

    func install() {
        let action: @convention(c) (Int32) -> Void = { sig in
            print("[swooshd] received signal \(sig), shutting down…")
            exit(0)
        }
        signal(SIGTERM, action)
        signal(SIGINT,  action)
    }
}
