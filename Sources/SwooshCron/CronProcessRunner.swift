// SwooshCron/CronProcessRunner.swift — Process runner for scheduled job scripts
import Foundation
import SwooshTools

public struct CronProcessPolicy: Sendable {
    public let allowedExecutables: Set<String>
    public let blockedExecutables: Set<String>
    public let timeoutSeconds: Int
    public let maxOutputBytes: Int
    public let inheritEnvironment: Bool

    public init(
        allowedExecutables: Set<String> = Self.defaultAllowedExecutables,
        blockedExecutables: Set<String> = Self.defaultBlockedExecutables,
        timeoutSeconds: Int = 120,
        maxOutputBytes: Int = 512_000,
        inheritEnvironment: Bool = true
    ) {
        self.allowedExecutables = allowedExecutables
        self.blockedExecutables = blockedExecutables
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
        self.inheritEnvironment = inheritEnvironment
    }

    public static let defaultAllowedExecutables: Set<String> = [
        "/bin/sh",
        "/bin/zsh",
        "/usr/bin/env",
        "sh",
        "zsh",
        "env",
    ]

    public static let defaultBlockedExecutables: Set<String> = [
        "sudo",
        "su",
        "doas",
    ]

    public static let scheduledScripts = CronProcessPolicy()
}

public enum CronProcessError: Error, Sendable, LocalizedError {
    case executableBlocked(String)
    case executableNotAllowed(String)
    case invalidWorkingDirectory(String)
    case timeout(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .executableBlocked(let executable):
            return "cron executable is blocked: \(executable)"
        case .executableNotAllowed(let executable):
            return "cron executable is not allowed: \(executable)"
        case .invalidWorkingDirectory(let path):
            return "cron working directory does not exist or is not a directory: \(path)"
        case .timeout(let seconds):
            return "cron process timed out after \(seconds) seconds"
        }
    }
}

public struct CronProcessRunner: ProcessRunning, Sendable {
    public let policy: CronProcessPolicy

    public init(policy: CronProcessPolicy = .scheduledScripts) {
        self.policy = policy
    }

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult {
        try validate(executable: executable, workingDirectory: workingDirectory)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = buildEnvironment(custom: environment)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let deadline = Date().addingTimeInterval(TimeInterval(policy.timeoutSeconds))
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(policy.timeoutSeconds))
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        timeoutTask.cancel()

        if Date() >= deadline && process.terminationStatus != 0 {
            throw CronProcessError.timeout(seconds: policy.timeoutSeconds)
        }

        var stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        var stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        if stdoutData.count > policy.maxOutputBytes { stdoutData = stdoutData.prefix(policy.maxOutputBytes) }
        if stderrData.count > policy.maxOutputBytes { stderrData = stderrData.prefix(policy.maxOutputBytes) }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func validate(executable: String, workingDirectory: URL?) throws {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent
        guard !policy.blockedExecutables.contains(executableName) else {
            throw CronProcessError.executableBlocked(executableName)
        }
        guard policy.allowedExecutables.contains(executable) || policy.allowedExecutables.contains(executableName) else {
            throw CronProcessError.executableNotAllowed(executable)
        }
        if let workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw CronProcessError.invalidWorkingDirectory(workingDirectory.path)
            }
        }
    }

    private func buildEnvironment(custom: [String: String]?) -> [String: String] {
        var env = policy.inheritEnvironment ? ProcessInfo.processInfo.environment : [:]
        let secretKeys = [
            "API_KEY",
            "SECRET",
            "TOKEN",
            "PASSWORD",
            "PRIVATE_KEY",
            "AWS_SECRET",
            "OPENAI_API_KEY",
            "OPENROUTER_API_KEY",
            "ELIZA_CLOUD_API_KEY",
        ]
        for key in env.keys {
            let upper = key.uppercased()
            if secretKeys.contains(where: { upper.contains($0) }) {
                env.removeValue(forKey: key)
            }
        }
        if let custom {
            env.merge(custom) { _, new in new }
        }
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        if env["TERM"] == nil {
            env["TERM"] = "dumb"
        }
        return env
    }
}
