// SwooshSecrets/PlatformPaths.swift — Cross-platform path helpers
//
// See SwooshConfig/PlatformPaths.swift — same shape, kept local to the
// module to avoid leaking an internal helper across module boundaries.

import Foundation

internal func swooshHomeDirectoryForCurrentUser() -> URL {
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
