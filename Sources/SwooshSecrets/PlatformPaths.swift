// SwooshSecrets/PlatformPaths.swift — 0.9S Cross-platform path helpers
//
// macOS uses `~` as the canonical Swoosh state root (`~/.swoosh/...`).
// On iOS that path is unavailable; sandboxed apps must write under
// `Application Support/`. The helper below returns the right base so
// existing `.appending(path: ".swoosh/foo")` call sites keep working
// in both environments.
//
// Lives in SwooshSecrets because it is the lowest-level module that
// needs it (config-file scavenger, env scavenger). SwooshConfig re-uses
// the same definition through its SwooshSecrets dependency.

import Foundation

public func swooshHomeDirectoryForCurrentUser() -> URL {
    #if os(macOS)
    return FileManager.default.homeDirectoryForCurrentUser
    #else
    return (try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    #endif
}
