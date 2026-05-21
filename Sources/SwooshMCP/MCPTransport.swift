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
    private var stderrReadHandle: FileHandle?
    private var stderrDrainTask: Task<Void, Never>?
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

        // Close the parent's copy of every pipe end the child owns. The
        // child inherits the *other* end of each pipe; if the parent keeps
        // its copy open, EOF never propagates when the child exits and the
        // drain tasks below sit forever in a blocking `read()`. This is
        // the standard fork-exec hygiene step that `Foundation.Process`
        // does NOT do for you.
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stderrReadHandle = stderrPipe.fileHandleForReading
        self.started = true

        // Drain stderr on a detached task so the child never blocks.
        // We retain the task handle so `close()` can cancel it and
        // (more importantly) close the FD it's reading from to unblock
        // the in-flight syscall — `Task.cancel()` alone doesn't interrupt
        // a blocking `read()`.
        let sink = stderrSink
        let stderrHandle = stderrPipe.fileHandleForReading
        self.stderrDrainTask = Task.detached {
            // Swallow read errors — they are expected when close() shuts
            // the FD down, and the sink only cares about successfully
            // received lines.
            try? await {
                for try await line in Self.lineStream(from: stderrHandle) {
                    sink(line)
                }
            }()
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
        // Close every parent FD we still hold. Closing stdin's write end
        // causes a child blocked in `read(0)` to see EOF and exit cleanly;
        // closing the read ends of stdout/stderr makes any further
        // `read()` on them return zero bytes so the drain tasks unwind.
        try? stdinHandle?.close()
        try? stdoutPipeHandle?.close()
        try? stderrReadHandle?.close()
        stdinHandle = nil
        stdoutPipeHandle = nil
        stderrReadHandle = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        process = nil
    }

    // ── Line splitting ────────────────────────────────────────────

    /// Reads a FileHandle and yields one entry per newline-terminated line.
    /// A trailing partial line (no newline) at EOF is yielded if non-empty.
    ///
    /// Uses `readabilityHandler` rather than a blocking `read()` loop on a
    /// `Task.detached`. The blocking variant parks a Swift cooperative
    /// pool thread per FileHandle, and the stdio transport opens two
    /// streams per spawned child (stdout + stderr) — two simultaneous
    /// reads in `read()` can starve the cooperative pool of the threads
    /// it needs to deliver in-flight actor hops (e.g. the MCPClient
    /// reader task forwarding frames to pending requests). That
    /// deadlocks the transport mid-request. `readabilityHandler`
    /// schedules its callback on a FileHandle-private dispatch queue, so
    /// the cooperative pool stays free.
    static func lineStream(from handle: FileHandle) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let buffer = LineBuffer()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    // EOF — flush any trailing partial line, then teardown.
                    if let trailing = buffer.flush(), !trailing.isEmpty {
                        continuation.yield(trailing)
                    }
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                for line in buffer.consume(chunk) {
                    continuation.yield(line)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Line buffer (used by readabilityHandler-driven lineStream)
// ═══════════════════════════════════════════════════════════════════

/// Accumulates pipe chunks and yields newline-delimited lines. Guarded
/// by an NSLock because `readabilityHandler` callbacks fire on whatever
/// thread the FileHandle picks — they need not be serialized with each
/// other across handles.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func consume(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: data.startIndex..<nl)
            data.removeSubrange(data.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
        }
        return lines
    }

    func flush() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return nil }
        data = Data()
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#endif
