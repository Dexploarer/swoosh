// SwooshToolsets/NitroGen/NitroGenToolDependencies.swift — 0.9U NitroGen tool deps
//
// Shared state for NitroGen tools. Owns the Python child processes
// (serve_mac.py for inference, play_mac.py for capture+injection).
// Injected into all nitrogen_* tools via the registrar.

#if os(macOS)

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - NitroGen status
// ═══════════════════════════════════════════════════════════════════

public enum NitroGenStatus: String, Codable, Sendable {
    case idle
    case serverStarting
    case serverReady
    case playing
    case stopping
    case error
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - NitroGen controller actor
// ═══════════════════════════════════════════════════════════════════

public actor NitroGenController {
    public private(set) var status: NitroGenStatus = .idle
    public private(set) var serverProcess: Process?
    public private(set) var playerProcess: Process?
    public private(set) var stepCount: Int = 0
    public private(set) var currentFPS: Double = 0
    public private(set) var lastError: String?

    /// Path to the NitroGen Python scripts directory
    private let scriptsPath: String

    /// Port the ZMQ inference server listens on
    public let serverPort: Int

    /// Path to model checkpoint (ng.pt)
    private let modelPath: String

    public init(
        scriptsPath: String = "",
        serverPort: Int = 5555,
        modelPath: String = "~/.swoosh/models/ng.pt"
    ) {
        self.scriptsPath = scriptsPath.isEmpty
            ? Self.defaultScriptsPath()
            : scriptsPath
        self.serverPort = serverPort
        self.modelPath = modelPath
    }

    // ── Start ─────────────────────────────────────────────────────

    public func start(
        windowTitle: String?,
        bundleID: String?,
        keymap: String?,
        fps: Int,
        dryRun: Bool
    ) async throws -> NitroGenStartOutput {
        guard status == .idle || status == .error else {
            throw NitroGenError.alreadyRunning
        }

        status = .serverStarting
        lastError = nil
        stepCount = 0

        // 1. Spawn serve_mac.py
        let servePath = "\(scriptsPath)/serve_mac.py"
        let serveProc = Process()
        serveProc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        serveProc.arguments = [servePath, "--port", "\(serverPort)"]
        serveProc.environment = ProcessInfo.processInfo.environment

        do {
            try serveProc.run()
            serverProcess = serveProc
        } catch {
            status = .error
            lastError = "Failed to start serve_mac.py: \(error.localizedDescription)"
            throw NitroGenError.serverStartFailed(lastError!)
        }

        // Give server a moment to bind
        try await Task.sleep(for: .seconds(2))

        guard serveProc.isRunning else {
            status = .error
            lastError = "serve_mac.py exited prematurely"
            throw NitroGenError.serverStartFailed(lastError!)
        }

        status = .serverReady

        // 2. Spawn play_mac.py
        let playPath = "\(scriptsPath)/play_mac.py"
        let playProc = Process()
        playProc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")

        var playArgs = [playPath, "--port", "\(serverPort)", "--fps", "\(fps)"]
        if let windowTitle { playArgs += ["--window", windowTitle] }
        if let bundleID { playArgs += ["--bundle-id", bundleID] }
        if let keymap { playArgs += ["--keymap", keymap] }
        if dryRun { playArgs.append("--dry-run") }

        playProc.arguments = playArgs
        playProc.environment = ProcessInfo.processInfo.environment

        do {
            try playProc.run()
            playerProcess = playProc
            status = .playing
        } catch {
            // Kill server if player fails
            serveProc.terminate()
            serverProcess = nil
            status = .error
            lastError = "Failed to start play_mac.py: \(error.localizedDescription)"
            throw NitroGenError.playerStartFailed(lastError!)
        }

        return NitroGenStartOutput(
            status: status.rawValue,
            serverPID: Int(serveProc.processIdentifier),
            playerPID: Int(playProc.processIdentifier),
            port: serverPort
        )
    }

    // ── Stop ──────────────────────────────────────────────────────

    public func stop() -> NitroGenStopOutput {
        status = .stopping
        let finalSteps = stepCount

        playerProcess?.terminate()
        playerProcess = nil

        serverProcess?.terminate()
        serverProcess = nil

        status = .idle
        return NitroGenStopOutput(
            status: "stopped",
            totalSteps: finalSteps
        )
    }

    // ── Status ────────────────────────────────────────────────────

    public func getStatus() -> NitroGenStatusOutput {
        // Check if processes are still alive
        if status == .playing, let player = playerProcess, !player.isRunning {
            status = .error
            lastError = "play_mac.py exited unexpectedly"
        }

        return NitroGenStatusOutput(
            status: status.rawValue,
            stepCount: stepCount,
            currentFPS: currentFPS,
            serverPort: serverPort,
            lastError: lastError
        )
    }

    // ── Internal ──────────────────────────────────────────────────

    public func updateMetrics(steps: Int, fps: Double) {
        stepCount = steps
        currentFPS = fps
    }

    private static func defaultScriptsPath() -> String {
        // Look relative to the package source
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/NitroGen/nitrogen_mac",
            NSHomeDirectory() + "/.swoosh/nitrogen/nitrogen_mac",
            FileManager.default.currentDirectoryPath + "/Sources/SwooshToolsets/NitroGen/nitrogen_mac"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path + "/serve_mac.py") {
                return path
            }
        }
        return candidates.last!
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum NitroGenError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    case serverStartFailed(String)
    case playerStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "NitroGen is already running"
        case .notRunning: return "NitroGen is not running"
        case .serverStartFailed(let msg): return "Server start failed: \(msg)"
        case .playerStartFailed(let msg): return "Player start failed: \(msg)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool I/O types
// ═══════════════════════════════════════════════════════════════════

public struct NitroGenStartInput: Codable, Sendable {
    public let windowTitle: String?
    public let bundleID: String?
    public let keymap: String?
    public let fps: Int?
    public let dryRun: Bool?
}

public struct NitroGenStartOutput: Codable, Sendable {
    public let status: String
    public let serverPID: Int
    public let playerPID: Int
    public let port: Int
}

public struct NitroGenStopInput: Codable, Sendable {}

public struct NitroGenStopOutput: Codable, Sendable {
    public let status: String
    public let totalSteps: Int
}

public struct NitroGenStatusInput: Codable, Sendable {}

public struct NitroGenStatusOutput: Codable, Sendable {
    public let status: String
    public let stepCount: Int
    public let currentFPS: Double
    public let serverPort: Int
    public let lastError: String?
}

public struct NitroGenScreenshotInput: Codable, Sendable {}

public struct NitroGenScreenshotOutput: Codable, Sendable {
    public let status: String
    public let message: String
}

#endif
