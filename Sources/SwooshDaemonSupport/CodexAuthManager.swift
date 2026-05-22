// SwooshDaemonSupport/CodexAuthManager.swift — Spawn-and-track `codex login`
//
// `codex login` opens a browser and runs a local HTTP server to receive
// the OAuth callback. The callback always lands on the Mac (where codex
// is running), so this manager lives daemon-side. iOS triggers it via
// `POST /api/codex/auth/start` and polls `GET /api/codex/auth/status`.
//
// We keep at most one live `codex login` process at a time. Starting a
// new one while another is alive cancels the old one — the user almost
// always means "try again, the last attempt is dead to me."

import Foundation

public actor CodexAuthManager {
    public enum State: String, Sendable, Codable {
        case idle
        case pending
        case signedIn = "signed_in"
        case failed
        case cancelled
    }

    public struct Status: Sendable, Codable {
        public let state: State
        public let message: String?
        public let startedAt: Date?
        public let url: String?

        public init(state: State, message: String? = nil,
                    startedAt: Date? = nil, url: String? = nil) {
            self.state = state
            self.message = message
            self.startedAt = startedAt
            self.url = url
        }
    }

    private var process: Process?
    private var currentState: State = .idle
    private var currentMessage: String?
    private var startedAt: Date?
    private var capturedURL: String?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    /// `codex` executable path. Resolved at init.
    private let codexBinary: URL?
    /// Working directory passed to `codex` (non-repo). Must exist.
    private let workingDirectory: URL

    public init(workingDirectory: URL) {
        self.codexBinary = Self.findCodex()
        self.workingDirectory = workingDirectory
    }

    /// Returns the current snapshot without spawning anything.
    public func snapshot() -> Status {
        Status(state: currentState, message: currentMessage,
               startedAt: startedAt, url: capturedURL)
    }

    /// Spawn `codex login` if no live process exists, otherwise return the
    /// current snapshot. Always returns the most recent URL the codex
    /// process emitted (parsed from stdout).
    public func start() throws -> Status {
        guard let codex = codexBinary else {
            currentState = .failed
            currentMessage = "codex CLI not installed. Install via `npm i -g @openai/codex`."
            return snapshot()
        }
        // If a previous attempt is still running, surface its state
        // (don't start a duplicate).
        if let process, process.isRunning {
            return snapshot()
        }

        try FileManager.default.createDirectory(
            at: workingDirectory, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = codex
        proc.arguments = ["login"]
        proc.currentDirectoryURL = workingDirectory

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        stdoutBuffer = Data()
        stderrBuffer = Data()
        capturedURL = nil

        // Stream stdout — codex prints the OAuth URL early. We watch for
        // any `https://…` string and surface it as `capturedURL`.
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            Task { await self.appendStdout(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            Task { await self.appendStderr(chunk) }
        }

        proc.terminationHandler = { [weak self] terminated in
            guard let self else { return }
            Task { await self.handleTermination(exitCode: terminated.terminationStatus) }
        }

        do {
            try proc.run()
        } catch {
            currentState = .failed
            currentMessage = "codex login could not start: \(error.localizedDescription)"
            return snapshot()
        }

        process = proc
        currentState = .pending
        currentMessage = "Opened ChatGPT sign-in in your browser. Complete sign-in there."
        startedAt = Date()
        return snapshot()
    }

    /// Terminate any in-flight login attempt.
    public func cancel() {
        if let process, process.isRunning {
            process.terminate()
            currentState = .cancelled
            currentMessage = "Sign-in cancelled."
        }
    }

    // MARK: - Private

    private func appendStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        if capturedURL == nil,
           let text = String(data: stdoutBuffer, encoding: .utf8),
           let url = Self.extractURL(text) {
            capturedURL = url
        }
    }

    private func appendStderr(_ chunk: Data) {
        stderrBuffer.append(chunk)
        // Some codex versions print the URL on stderr.
        if capturedURL == nil,
           let text = String(data: stderrBuffer, encoding: .utf8),
           let url = Self.extractURL(text) {
            capturedURL = url
        }
    }

    private func handleTermination(exitCode: Int32) {
        process = nil
        switch exitCode {
        case 0:
            currentState = .signedIn
            currentMessage = "Signed in to ChatGPT."
        default:
            // Don't overwrite a manual cancel.
            if currentState != .cancelled {
                let stderr = String(data: stderrBuffer, encoding: .utf8) ?? ""
                currentState = .failed
                currentMessage = stderr.isEmpty
                    ? "codex login exited with code \(exitCode)."
                    : "codex login failed: \(stderr.prefix(400))"
            }
        }
    }

    private nonisolated static func extractURL(_ text: String) -> String? {
        let pattern = #"https://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range, in: text) else { return nil }
        return String(text[captured])
    }

    private nonisolated static func findCodex() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.bun/bin/codex",
            "\(NSHomeDirectory())/.npm-global/bin/codex"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
