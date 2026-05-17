// SwooshDBClient/SpacetimeSupervisor.swift — Local SpacetimeDB process supervisor
//
// swooshd uses this to manage a local SpacetimeDB standalone instance.
// Binds to 127.0.0.1 only. No SSL (local-only).

import Foundation

public actor SpacetimeSupervisor {
    private var process: Process?
    private let dataDir: URL
    private let listenAddr: String

    /// Path to the spacetime CLI binary.
    private let binaryPath: String

    public init(
        dataDir: URL? = nil,
        listenAddr: String = "127.0.0.1:3000",
        binaryPath: String? = nil
    ) {
        self.dataDir = dataDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".swoosh/spacetimedb")
        self.listenAddr = listenAddr

        // Try common install locations
        if let path = binaryPath {
            self.binaryPath = path
        } else {
            let candidates = [
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/spacetime",
                "/usr/local/bin/spacetime",
                "/opt/homebrew/bin/spacetime",
            ]
            self.binaryPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
                ?? "spacetime"
        }
    }

    /// Start the local SpacetimeDB instance if not already running.
    public func start() async throws -> Bool {
        guard process == nil || process?.isRunning != true else {
            return true // already running
        }

        // Ensure data directory exists
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "start",
            "--listen-addr", listenAddr,
        ]
        proc.environment = [
            "STDB_PATH": dataDir.path,
            "PATH": "/usr/local/bin:/usr/bin:/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"
        ]

        // Redirect output to logs
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".swoosh/logs")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let stdoutFile = FileHandle(forWritingAtPath: logDir.appending(path: "spacetimedb.log").path)
        let stderrFile = FileHandle(forWritingAtPath: logDir.appending(path: "spacetimedb.err").path)
        proc.standardOutput = stdoutFile ?? FileHandle.nullDevice
        proc.standardError = stderrFile ?? FileHandle.nullDevice

        try proc.run()
        self.process = proc

        // Wait a moment for the server to start
        try await Task.sleep(for: .seconds(2))

        return proc.isRunning
    }

    /// Stop the local SpacetimeDB instance.
    public func stop() {
        process?.terminate()
        process = nil
    }

    /// Check if the local instance is running.
    public func isRunning() -> Bool {
        process?.isRunning == true
    }

    /// Get the WebSocket URL for client connections.
    public func connectionURL(database: String = "swoosh") -> String {
        "ws://\(listenAddr)/database/subscribe/\(database)"
    }

    /// Get the HTTP URL for REST-style calls.
    public func httpURL(database: String = "swoosh") -> String {
        "http://\(listenAddr)/database/call/\(database)"
    }

    /// Publish the SwooshDB module to the local instance.
    public func publishModule(wasmPath: String, database: String = "swoosh") async throws -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["publish", "--server", "http://\(listenAddr)", database, "--project-path", wasmPath]
        proc.environment = [
            "PATH": "/usr/local/bin:/usr/bin:/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin"
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()
        proc.waitUntilExit()

        return proc.terminationStatus == 0
    }
}
