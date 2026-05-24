// SwooshDaemon/DaemonPaths.swift — 0.9S State + ActantDB search paths
//
// File-system locations the daemon consults at boot: the canonical
// `~/.swoosh/` state directory and the ordered list of paths searched
// for the `actantdb` binary. Extracted from `Daemon.swift` so the
// boot orchestration there stays focused.

import Foundation

extension SwooshDaemon {

    /// Ordered candidates for the `actantdb` binary when it isn't on
    /// `PATH`. Matches the three remediation paths surfaced in the
    /// `FATAL: could not start ActantDB` error message.
    static func actantDBSearchPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".cache/cargo-actantdb/debug", isDirectory: true),
            home.appendingPathComponent("actantDB/target/debug", isDirectory: true),
            home.appendingPathComponent("actantDB/node_modules/.bin", isDirectory: true),
        ]
    }

    /// Resolved Swoosh state root. Respects `SWOOSH_CONFIG_DIR` /
    /// `SWOOSH_STATE_DIR` env overrides, otherwise `~/.swoosh/`.
    static func stateDirectory(env: [String: String]) -> URL {
        if let configured = env["SWOOSH_CONFIG_DIR"] ?? env["SWOOSH_STATE_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
    }
}
