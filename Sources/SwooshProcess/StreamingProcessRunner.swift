// SwooshProcess/StreamingProcessRunner.swift — Safe streaming process runner (0.4C)
//
// Runs allowlisted executables with timeout, output caps, and minimal environment.
// Conforms to ProcessRunning from SwooshTools.

import Foundation
import SwooshTools

// MARK: - Process output event

public enum ProcessOutputEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(code: Int32)
    case timeout
}

// MARK: - Streaming process runner

public struct StreamingProcessRunner: ProcessRunning, Sendable {
    public let policy: ProcessPolicy
    public let approvedRoots: [String]

    public init(policy: ProcessPolicy = .defaultDev, approvedRoots: [String] = []) {
        self.policy = policy
        self.approvedRoots = approvedRoots
    }

    // MARK: - ProcessRunning conformance

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        // 1. Validate executable against allowlist
        let execName = URL(fileURLWithPath: executable).lastPathComponent
        guard !ProcessPolicy.blockedExecutables.contains(execName) else {
            throw ProcessError.executableBlocked(execName)
        }
        guard policy.allowedExecutables.contains(executable) ||
              policy.allowedExecutables.contains(execName) else {
            throw ProcessError.executableNotAllowed(executable)
        }

        // 2. Validate working directory is inside an approved root
        if let workDir = workingDirectory {
            let workPath = workDir.standardizedFileURL.path
            let isInApprovedRoot = approvedRoots.isEmpty || approvedRoots.contains {
                path(workPath, isInsideOrEqualTo: $0)
            }
            guard isInApprovedRoot else {
                throw ProcessError.workingDirectoryOutsideRoot
            }
        }

        // 3. Validate arguments for injection
        try validateArguments(arguments)

        // 4. Resolve executable path
        let resolvedExec = resolveExecutable(executable)

        // 5. Build environment
        let env = buildEnvironment(custom: environment)

        // 6. Run with timeout and output caps
        return try await runProcess(
            executable: resolvedExec,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: env
        )
    }

    // MARK: - Streaming variant

    public func runStreaming(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?
    ) async throws -> (result: ProcessResult, events: [ProcessOutputEvent]) {
        // Same validation as run()
        let execName = URL(fileURLWithPath: executable).lastPathComponent
        guard !ProcessPolicy.blockedExecutables.contains(execName) else {
            throw ProcessError.executableBlocked(execName)
        }
        guard policy.allowedExecutables.contains(executable) ||
              policy.allowedExecutables.contains(execName) else {
            throw ProcessError.executableNotAllowed(executable)
        }

        if let workDir = workingDirectory {
            let workPath = workDir.standardizedFileURL.path
            let isInApprovedRoot = approvedRoots.isEmpty || approvedRoots.contains {
                path(workPath, isInsideOrEqualTo: $0)
            }
            guard isInApprovedRoot else {
                throw ProcessError.workingDirectoryOutsideRoot
            }
        }

        try validateArguments(arguments)
        let resolvedExec = resolveExecutable(executable)
        let env = buildEnvironment(custom: environment)

        let result = try await runProcess(
            executable: resolvedExec,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: env
        )

        var events: [ProcessOutputEvent] = []
        if !result.stdout.isEmpty { events.append(.stdout(result.stdout)) }
        if !result.stderr.isEmpty { events.append(.stderr(result.stderr)) }
        events.append(.exit(code: result.exitCode))

        return (result, events)
    }

    // MARK: - Private

    private func validateArguments(_ arguments: [String]) throws {
        for arg in arguments {
            // Block shell injection patterns
            let dangerous = [";", "&&", "||", "|", "`", "$(", "${", ">", "<", "\n", "\r"]
            for pattern in dangerous {
                if arg.contains(pattern) {
                    throw ProcessError.executionFailed(
                        "Argument contains shell injection pattern: \(pattern)"
                    )
                }
            }
        }
    }

    private func path(_ candidate: String, isInsideOrEqualTo root: String) -> Bool {
        let rootPath = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }

    private func resolveExecutable(_ executable: String) -> String {
        if executable.hasPrefix("/") { return executable }
        // Resolve common names to full paths
        switch executable {
        case "git":   return "/usr/bin/git"
        case "swift": return "/usr/bin/swift"
        case "xcrun": return "/usr/bin/xcrun"
        default:      return executable
        }
    }

    private func buildEnvironment(custom: [String: String]?) -> [String: String] {
        switch policy.environmentPolicy {
        case .minimal:
            var env: [String: String] = [:]
            if let path = ProcessInfo.processInfo.environment["PATH"] { env["PATH"] = path }
            if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
            env["LANG"] = "en_US.UTF-8"
            env["TERM"] = "dumb"
            return env
        case .inheritSafe:
            var env = ProcessInfo.processInfo.environment
            // Remove known secret-like variables
            let secretKeys = ["API_KEY", "SECRET", "TOKEN", "PASSWORD", "PRIVATE_KEY",
                              "AWS_SECRET", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"]
            for key in env.keys {
                let upper = key.uppercased()
                if secretKeys.contains(where: { upper.contains($0) }) {
                    env.removeValue(forKey: key)
                }
            }
            return env
        case .custom:
            return custom ?? [:]
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workDir = workingDirectory {
            process.currentDirectoryURL = workDir
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Timeout
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(policy.timeoutSeconds))
            if process.isRunning { process.terminate() }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        var stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        var stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // Cap output
        if stdoutData.count > policy.maxOutputBytes {
            stdoutData = stdoutData.prefix(policy.maxOutputBytes)
        }
        if stderrData.count > policy.maxOutputBytes {
            stderrData = stderrData.prefix(policy.maxOutputBytes)
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
