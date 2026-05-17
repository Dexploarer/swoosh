// SwooshFiles/SensitiveFilePolicy.swift — Sensitive file blocking (0.4C)
//
// Blocks access to secrets, keys, env files, and large build artifacts.
// Default-deny for sensitive patterns.

import Foundation

public struct SensitiveFilePolicy: Sendable {

    public init() {}

    public let blockedNames: Set<String> = [
        ".env", ".env.local", ".env.production", ".env.development", ".env.staging",
        "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
        "credentials.json", "secrets.json", "service-account.json",
        ".netrc", ".npmrc", ".pypirc",
        "keystore.jks", "keystore.p12",
    ]

    public let blockedExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "jks", "keystore",
    ]

    public let blockedDirectories: Set<String> = [
        ".git", ".ssh", ".gnupg", ".aws", ".azure",
        "node_modules", ".build", "DerivedData", "target", "vendor",
        ".cocoapods", "Pods", "__pycache__", ".venv",
    ]

    /// Returns true if the path should be blocked from read/write.
    public func shouldBlock(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if blockedNames.contains(name) { return true }
        if blockedExtensions.contains(ext) { return true }

        let components = url.pathComponents
        if components.contains(where: { blockedDirectories.contains($0) }) {
            return true
        }

        return false
    }

    /// Returns true if the path should be skipped during listing/search
    /// (includes blocked + large artifact directories).
    public func shouldSkip(path: String) -> Bool {
        shouldBlock(path: path)
    }

    /// Returns the reason a file is blocked, or nil if not blocked.
    public func blockReason(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if blockedNames.contains(name) { return "Sensitive file: \(name)" }
        if blockedExtensions.contains(ext) { return "Sensitive extension: .\(ext)" }

        let components = url.pathComponents
        if let dir = components.first(where: { blockedDirectories.contains($0) }) {
            return "Inside blocked directory: \(dir)"
        }

        return nil
    }
}
