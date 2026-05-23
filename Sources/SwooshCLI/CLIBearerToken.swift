// SwooshCLI/CLIBearerToken.swift — Shared bearer-token generator — 0.4B
//
// Previously duplicated in SwooshCommand.swift and SetupCommands.swift —
// the daemon and CLI both mint the same 32-byte hex token, so the helper
// belongs in one place.
//
// 0.4B revision: adds `ensureBearerTokenFile` which creates the token
// file atomically with 0o600 permissions, fixing the brief world-
// readable window between `write(to:)` and `setAttributes`.

import Foundation
#if canImport(Security)
import Security
#endif

/// Mint a 32-byte hex bearer token. Uses `SecRandomCopyBytes` when
/// available (macOS/iOS); falls back to `UInt8.random` for Linux/CI.
func generateBearerToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    #if canImport(Security)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
        throw CocoaError(.fileWriteUnknown)
    }
    #else
    for index in bytes.indices {
        bytes[index] = UInt8.random(in: 0...255)
    }
    #endif
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// Ensure a 0o600-permissioned token file exists at `path`. If the
/// file already exists, returns its trimmed contents; otherwise mints a
/// fresh token, creates the file *atomically with restricted permissions*
/// via `FileManager.createFile(atPath:contents:attributes:)` so the
/// token never has a brief world-readable window. Also ensures the
/// parent directory exists (the CLI is sometimes the first thing run
/// on a fresh machine).
///
/// - Returns: the bearer token bytes (already trimmed of whitespace).
/// - Throws: `CocoaError(.fileWriteUnknown)` on randomness / write
///   failures; `CocoaError(.fileReadCorruptFile)` when the existing
///   file is empty or unreadable.
func ensureBearerTokenFile(at path: URL) throws -> String {
    let fm = FileManager.default
    let directory = path.deletingLastPathComponent()
    if !fm.fileExists(atPath: directory.path) {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    }
    if !fm.fileExists(atPath: path.path) {
        let token = try generateBearerToken()
        let data = Data(token.utf8)
        let created = fm.createFile(
            atPath: path.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else { throw CocoaError(.fileWriteUnknown) }
    }
    let contents = try String(contentsOf: path, encoding: .utf8)
    let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return trimmed
}
