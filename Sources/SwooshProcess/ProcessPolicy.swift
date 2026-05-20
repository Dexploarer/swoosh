// SwooshProcess/ProcessPolicy.swift — Process execution policy (0.4C)
//
// Controls what executables can run, with what constraints.
// No arbitrary shell. No sudo. Only allowlisted executables.

import Foundation

// MARK: - Process policy

public struct ProcessPolicy: Codable, Sendable {
    public let allowedExecutables: Set<String>
    public let timeoutSeconds: Int
    public let maxOutputBytes: Int
    public let environmentPolicy: EnvironmentPolicy
    public let streamOutput: Bool

    public init(
        allowedExecutables: Set<String> = Self.defaultAllowed,
        timeoutSeconds: Int = 120,
        maxOutputBytes: Int = 512_000,
        environmentPolicy: EnvironmentPolicy = .minimal,
        streamOutput: Bool = true
    ) {
        self.allowedExecutables = allowedExecutables
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
        self.environmentPolicy = environmentPolicy
        self.streamOutput = streamOutput
    }

    public static let defaultAllowed: Set<String> = [
        "git", "swift", "xcrun",
        "/usr/bin/git", "/usr/bin/swift", "/usr/bin/xcrun"
    ]

    public static let defaultDev = ProcessPolicy()

    /// Blocked executables — never allowed regardless of policy.
    public static let blockedExecutables: Set<String> = [
        "sh", "bash", "zsh", "fish", "csh", "tcsh",
        "sudo", "su", "doas",
        "python", "python3", "node", "ruby", "perl",
        "rm", "mv", "cp",  // use file tools instead
        "curl", "wget",    // use web tools instead
        "ssh", "scp", "sftp",
        "open",            // don't launch apps
    ]
}

// MARK: - Environment policy

public enum EnvironmentPolicy: String, Codable, Sendable {
    /// Only PATH, HOME, LANG, TERM.
    case minimal
    /// Inherit safe env vars (no secrets, no API keys).
    case inheritSafe
    /// Custom env dict only.
    case custom
}

// MARK: - Process errors

public enum ProcessError: Error, Sendable {
    case executableNotAllowed(String)
    case executableBlocked(String)
    case workingDirectoryOutsideRoot
    case timeout(seconds: Int)
    case outputExceeded(bytes: Int)
    case executionFailed(String)
}
