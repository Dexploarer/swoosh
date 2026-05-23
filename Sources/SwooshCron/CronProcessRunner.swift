// SwooshCron/CronProcessRunner.swift — 0.5B Process runner for scheduled job scripts
//
// 0.5A: stopped blocking the cooperative thread pool. `run` no longer
// calls `process.waitUntilExit()` (a synchronous parks-the-thread syscall);
// it suspends on a CheckedContinuation that the process's terminationHandler
// resumes. Timeout is a sibling Task that calls `terminate()`, which trips
// the handler. Stdout/stderr pipes are drained on background queues during
// process lifetime so a chatty child cannot fill a pipe buffer and deadlock.
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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = PipeCollector(limit: policy.maxOutputBytes)
        let stderrCollector = PipeCollector(limit: policy.maxOutputBytes)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutCollector.append(chunk)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrCollector.append(chunk)
            }
        }

        let timedOut = TimeoutFlag()
        let timeoutSeconds = policy.timeoutSeconds
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            if Task.isCancelled { return }
            timedOut.fire()
            process.terminate()
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            timeoutTask.cancel()
            throw error
        }
        timeoutTask.cancel()

        // Drain any data buffered between the last readabilityHandler call
        // and process exit, then clear the handlers so the pipes can close.
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        if timedOut.didFire {
            throw CronProcessError.timeout(seconds: timeoutSeconds)
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutCollector.string,
            stderr: stderrCollector.string
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

// MARK: - Pipe helpers
//
// File-scope so Swift 6 strict-concurrency doesn't choke on nested
// classes captured in `@Sendable` `readabilityHandler` closures (the
// nested-type form fails with "cannot find in scope" at the call site
// despite being declared lexically inside the struct).

/// Thread-safe bounded byte accumulator used by both stdout and stderr
/// readability handlers. We need a lock because `readabilityHandler`
/// callbacks fire on Foundation's IO queue, not the actor that owns us.
fileprivate final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = limit - buffer.count
        guard remaining > 0 else { return }
        if chunk.count <= remaining {
            buffer.append(chunk)
        } else {
            buffer.append(chunk.prefix(remaining))
        }
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}

/// One-shot atomic flag set by the timeout task. Read after the process
/// exits to distinguish "child terminated normally" from "we killed it".
fileprivate final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() { lock.lock(); fired = true; lock.unlock() }
    var didFire: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}
