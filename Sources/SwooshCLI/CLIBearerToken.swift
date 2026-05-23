// SwooshCLI/CLIBearerToken.swift — Shared bearer-token generator — 0.4A
//
// Previously duplicated in SwooshCommand.swift and SetupCommands.swift —
// the daemon and CLI both mint the same 32-byte hex token, so the helper
// belongs in one place.

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
