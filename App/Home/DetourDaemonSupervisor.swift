// DetourDaemonSupervisor.swift — app-side local daemon bootstrap (0.5A)

import Foundation

@MainActor
final class DetourDaemonSupervisor: ObservableObject {
    static let shared = DetourDaemonSupervisor()

    @Published private(set) var state = "Starting local runtime"

    private var process: Process?
    private var startTask: Task<Void, Error>?

    func ensureRunning() async throws {
        if await Self.isHealthy() {
            try Self.persistToken()
            state = "Runtime ready"
            return
        }
        if let startTask {
            try await startTask.value
            return
        }
        let task = Task { try await Self.startAndWait() }
        startTask = task
        do {
            try await task.value
            state = "Runtime ready"
        } catch {
            state = Self.display(error)
            throw error
        }
        startTask = nil
    }

    private static func startAndWait() async throws {
        let binary = try swooshdBinary()
        let logs = logsDirectory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        process.environment = daemonEnvironment()
        process.standardOutput = try logHandle(logs.appendingPathComponent("detour-swooshd.log"))
        process.standardError = try logHandle(logs.appendingPathComponent("detour-swooshd.err.log"))
        try process.run()
        shared.process = process

        for _ in 0..<80 {
            if await isHealthy() {
                try persistToken()
                return
            }
            if !process.isRunning {
                throw DetourDaemonSupervisorError.exited(process.terminationStatus)
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw DetourDaemonSupervisorError.timeout
    }

    private static func isHealthy() async -> Bool {
        let url = DetourHomeDaemonClient.baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private static func persistToken() throws {
        let token = try daemonToken()
        if TokenStore.load() != token {
            try TokenStore.save(token)
        }
        HostStore.current = DetourHomeDaemonClient.baseURL
    }

    private static func daemonToken() throws -> String {
        let url = swooshDirectory().appendingPathComponent("api_token")
        let token = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw DetourDaemonSupervisorError.missingToken }
        return token
    }

    private static func swooshdBinary() throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["SWOOSHD_PATH"].flatMap(URL.init(fileURLWithPath:)),
            Bundle.main.url(forAuxiliaryExecutable: "swooshd"),
            repoRoot().appendingPathComponent(".build/debug/swooshd"),
            repoRoot().appendingPathComponent(".build/arm64-apple-macosx/debug/swooshd"),
            URL(fileURLWithPath: "/opt/homebrew/bin/swooshd"),
            URL(fileURLWithPath: "/usr/local/bin/swooshd"),
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw DetourDaemonSupervisorError.missingBinary(candidates.map(\.path))
    }

    private static func daemonEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["SWOOSH_HOST"] = "127.0.0.1"
        env["SWOOSH_PORT"] = "8787"
        let actant = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("actantDB/target/debug/actantdb")
        if FileManager.default.isExecutableFile(atPath: actant.path) {
            env["SWOOSH_ACTANTDB_PATH"] = actant.path
        }
        return env
    }

    private static func logHandle(_ url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    private static func logsDirectory() -> URL {
        swooshDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    private static func swooshDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh", isDirectory: true)
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func display(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private enum DetourDaemonSupervisorError: LocalizedError {
    case missingBinary([String])
    case exited(Int32)
    case timeout
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingBinary(let paths):
            "Could not find swooshd. Checked \(paths.joined(separator: ", "))."
        case .exited(let status):
            "swooshd exited with status \(status)."
        case .timeout:
            "swooshd did not become ready."
        case .missingToken:
            "swooshd started without writing an API token."
        }
    }
}
