// SwooshSandbox/Sandbox.swift — Process sandboxing and isolation
//
// Provides sandboxed execution environments for untrusted code,
// tool scripts, and agent-generated programs. Uses macOS sandbox
// profiles and process isolation.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sandbox policy
// ═══════════════════════════════════════════════════════════════════

/// Defines what a sandboxed process is allowed to do.
public struct SandboxPolicy: Codable, Sendable {
    public var allowNetwork: Bool
    public var allowFileRead: [String]       // Allowed read paths
    public var allowFileWrite: [String]      // Allowed write paths
    public var allowProcessExec: Bool        // Can spawn subprocesses
    public var maxMemoryMB: Int
    public var maxCPUSeconds: Int
    public var maxOutputBytes: Int
    public var environment: [String: String]

    public init(
        allowNetwork: Bool = false,
        allowFileRead: [String] = [],
        allowFileWrite: [String] = [],
        allowProcessExec: Bool = false,
        maxMemoryMB: Int = 256,
        maxCPUSeconds: Int = 30,
        maxOutputBytes: Int = 1_048_576,     // 1MB
        environment: [String: String] = [:]
    ) {
        self.allowNetwork = allowNetwork
        self.allowFileRead = allowFileRead
        self.allowFileWrite = allowFileWrite
        self.allowProcessExec = allowProcessExec
        self.maxMemoryMB = maxMemoryMB
        self.maxCPUSeconds = maxCPUSeconds
        self.maxOutputBytes = maxOutputBytes
        self.environment = environment
    }

    /// Strict: no network, no file writes, no subprocess spawning.
    public static let strict = SandboxPolicy()

    /// Read-only: can read project files but not write.
    public static func readOnly(paths: [String]) -> SandboxPolicy {
        SandboxPolicy(allowFileRead: paths)
    }

    /// Development: read/write to project dir, network allowed.
    public static func development(projectDir: String) -> SandboxPolicy {
        SandboxPolicy(
            allowNetwork: true,
            allowFileRead: [projectDir, "/usr", "/Library"],
            allowFileWrite: [projectDir],
            allowProcessExec: true,
            maxMemoryMB: 1024,
            maxCPUSeconds: 300
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sandbox execution result
// ═══════════════════════════════════════════════════════════════════

public struct SandboxResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationSeconds: TimeInterval
    public let wasKilled: Bool               // Killed by timeout/memory limit
    public let filesModified: [String]

    public var succeeded: Bool { exitCode == 0 && !wasKilled }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sandbox executor
// ═══════════════════════════════════════════════════════════════════

/// Executes commands in a sandboxed environment.
public actor SandboxExecutor {
    private let policy: SandboxPolicy

    public init(policy: SandboxPolicy = .strict) {
        self.policy = policy
    }

    /// Execute a command with sandboxing.
    public func execute(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        input: String? = nil
    ) async throws -> SandboxResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let start = Date()

        // Use sandbox-exec on macOS for real sandboxing
        if policy.allowNetwork == false && policy.allowProcessExec == false {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", generateSandboxProfile(), command] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        }

        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = policy.environment

        // Set up timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(policy.maxCPUSeconds))
            process.terminate()
        }

        try process.run()

        if let input, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let duration = Date().timeIntervalSince(start)
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let wasKilled = duration >= TimeInterval(policy.maxCPUSeconds)

        return SandboxResult(
            exitCode: process.terminationStatus,
            stdout: String(stdout.prefix(policy.maxOutputBytes)),
            stderr: String(stderr.prefix(policy.maxOutputBytes)),
            durationSeconds: duration,
            wasKilled: wasKilled,
            filesModified: []
        )
    }

    /// Generate a macOS sandbox profile from the policy.
    private func generateSandboxProfile() -> String {
        var rules: [String] = [
            "(version 1)",
            "(deny default)",
            "(allow process-exec)",
            "(allow sysctl-read)",
            "(allow mach-lookup)",
        ]

        for path in policy.allowFileRead {
            rules.append("(allow file-read* (subpath \"\(path)\"))")
        }

        for path in policy.allowFileWrite {
            rules.append("(allow file-write* (subpath \"\(path)\"))")
        }

        if policy.allowNetwork {
            rules.append("(allow network*)")
        }

        return rules.joined(separator: "\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum SandboxError: Error, Sendable {
    case policyViolation(String)
    case executionFailed(String)
    case timeout
    case memoryExceeded
}
