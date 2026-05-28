// SwooshDaemon/DaemonPaths.swift — 0.9S State directory paths
//
// File-system locations the daemon consults at boot: the canonical
// `~/.swoosh/` state directory. Extracted from `Daemon.swift` so the
// boot orchestration there stays focused.

import Foundation

extension SwooshDaemon {

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
