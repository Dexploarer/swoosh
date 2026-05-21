// SwooshMCP/MCPTransport.swift — 0.8C MCP transport seam + stdio impl
//
// The transport carries newline-delimited string frames. The JSON-RPC
// layer (MCPClient) sits above this. Keeping a protocol seam here means
// the client can be exercised against a mock transport with zero process
// spawning, which is how the tests stay deterministic.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Transport errors
// ═══════════════════════════════════════════════════════════════════

public enum MCPTransportError: Error, Sendable, Equatable {
    case notConnected
    case alreadyConnected
    case spawnFailed(String)
    case writeFailed(String)
    case processExited(code: Int32)
    case closed
    case unsupportedPlatform
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Transport protocol
// ═══════════════════════════════════════════════════════════════════

/// A bidirectional, newline-delimited frame channel to an MCP server.
/// Implementations must guarantee that `frames` terminates (finishes or
/// throws) when the underlying channel closes, so the client's reader
/// task can unwind and fail any pending requests.
public protocol MCPTransport: Sendable {
    /// Begin the channel. For stdio this spawns the child process.
    func start() async throws

    /// Send one frame. The frame must not contain a newline; the
    /// transport appends the delimiter.
    func send(_ line: String) async throws

    /// A stream of inbound frames, one per line. Finishes on clean close,
    /// throws `MCPTransportError.processExited` on abnormal child exit.
    func frames() -> AsyncThrowingStream<String, Error>

    /// Tear the channel down. Idempotent.
    func close() async
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stdio transport
// ═══════════════════════════════════════════════════════════════════

#if os(macOS) || os(Linux)

/// Spawns an MCP server as a child process and speaks newline-delimited
/// JSON-RPC over its stdin/stdout. Stderr is drained concurrently (MCP
/// servers log there) so a chatty server cannot deadlock on a full pipe.
public actor StdioMCPTransport: MCPTransport {

    public struct Configuration: Sendable {
        public let executable: String
        public let arguments: [String]
        public let workingDirectory: String?
        public let environment: [String: String]

        public init(executable: String, arguments: [String] = [],
                    workingDirectory: String? = nil, environment: [String: String] = [:]) {
            self.executable = executable
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.environment = environment
        }
    }

    private let config: Configuration
    private let stderrSink: @Sendable (String) -> Void

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var started = false
    private var closed = false

    /// - Parameter stderrSink: receives the server's stderr lines (for logs).
    public init(config: Configuration,
                stderrSink: @escaping @Sendable (String) -> Void = { _ in }) {
        self.config = config
        self.stderrSink = stderrSink
    }

    // ── Lifecycle ─────────────────────────────────────────────────

    public func start() async throws {
        guard !started else { throw MCPTransportError.alreadyConnected }
        guard !closed else { throw MCPTransportError.closed }

        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Resolve the executable. A bare name is run via /usr/bin/env so a
        // PATH lookup works (e.g. `npx`, `uvx`, `python`); an absolute or
        // relative path is used directly.
        if config.executable.contains("/") {
            proc.executableURL = URL(fileURLWithPath: config.executable)
            proc.arguments = config.arguments
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [config.executable] + config.arguments
        }

        if let wd = config.workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        if !config.environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in config.environment { env[k] = v }
            proc.environment = env
        }

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
        } catch {
            throw MCPTransportError.spawnFailed("\(config.executable): \(error.localizedDescription)")
        }

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.started = true

        // Drain stderr on a detached task so the child never blocks.
        let sink = stderrSink
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached {
            for try await line in Self.lineStream(from: stderrHandle) {
                sink(line)
            }
        }

        // Hold the stdout pipe for the frame stream.
        self.stdoutPipeHandle = stdoutPipe.fileHandleForReading
    }

    private var stdoutPipeHandle: FileHandle?

    public func send(_ line: String) async throws {
        guard started, !closed, let handle = stdinHandle else {
            throw MCPTransportError.notConnected
        }
        guard !line.contains("\n") else {
            throw MCPTransportError.writeFailed("frame contains embedded newline")
        }
        guard let data = (line + "\n").data(using: .utf8) else {
            throw MCPTransportError.writeFailed("frame is not valid UTF-8")
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw MCPTransportError.writeFailed(error.localizedDescription)
        }
    }

    public nonisolated func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let handle = try await self.stdoutHandleForReading()
                    for try await line in Self.lineStream(from: handle) {
                        continuation.yield(line)
                    }
                    // stdout closed — surface the exit status.
                    let code = await self.terminationStatus()
                    if code == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: MCPTransportError.processExited(code: code))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stdoutHandleForReading() throws -> FileHandle {
        guard let h = stdoutPipeHandle else { throw MCPTransportError.notConnected }
        return h
    }

    private func terminationStatus() -> Int32 {
        guard let proc = process else { return 0 }
        // Process must have exited for stdout EOF; this read is safe.
        return proc.isRunning ? 0 : proc.terminationStatus
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        try? stdinHandle?.close()
        try? stdoutPipeHandle?.close()
        stdinHandle = nil
        stdoutPipeHandle = nil
        process = nil
    }

    // ── Line splitting ────────────────────────────────────────────

    /// Reads a FileHandle and yields one entry per newline-terminated line.
    /// A trailing partial line (no newline) at EOF is yielded if non-empty.
    static func lineStream(from handle: FileHandle) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                var buffer = Data()
                do {
                    while true {
                        let chunk = try handle.read(upToCount: 4096) ?? Data()
                        if chunk.isEmpty {
                            // EOF — flush any trailing partial line.
                            if !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8) {
                                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty { continuation.yield(trimmed) }
                            }
                            continuation.finish()
                            return
                        }
                        buffer.append(chunk)
                        while let nl = buffer.firstIndex(of: 0x0A) {
                            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                            buffer.removeSubrange(buffer.startIndex...nl)
                            if let line = String(data: lineData, encoding: .utf8) {
                                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty { continuation.yield(trimmed) }
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
