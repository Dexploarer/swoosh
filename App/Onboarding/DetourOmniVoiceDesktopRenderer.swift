// DetourOmniVoiceDesktopRenderer.swift — local OmniVoice bridge for macOS onboarding (0.5A)

import Foundation
import OSLog

private let detourOmniVoiceLog = Logger(subsystem: "ai.swoosh.detour.mac", category: "OmniVoice")

actor DetourOmniVoiceDesktopRenderer {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func prepare() async throws {
        let directories = try DetourPaths.ensureDirectories()
        _ = try resolveOrBootstrapExecutable(directories: directories)
    }

    func render(text: String, referenceAudio: URL?, referenceText: String?) async throws -> URL {
        let directories = try DetourPaths.ensureDirectories()
        let executablePath = try resolveOrBootstrapExecutable(directories: directories)
        let output = directories.voice.appendingPathComponent("omnivoice-\(UUID().uuidString).wav", isDirectory: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments(
            text: text,
            output: output,
            referenceAudio: existingReferenceAudio(referenceAudio),
            referenceText: referenceText
        )

        var environment = ProcessInfo.processInfo.environment
        environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        environment["HF_HOME"] = directories.voice.appendingPathComponent("hf", isDirectory: true).path(percentEncoded: false)
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "OmniVoice failed."
            throw DetourOmniVoiceDesktopRendererError.renderFailed(message)
        }

        return output
    }

    private func arguments(
        text: String,
        output: URL,
        referenceAudio: URL?,
        referenceText: String?
    ) -> [String] {
        var args = [
            "--model", "k2-fsa/OmniVoice",
            "--text", text,
            "--output", output.path(percentEncoded: false)
        ]
        if let referenceAudio {
            args += ["--ref_audio", referenceAudio.path(percentEncoded: false)]
            if let referenceText,
               !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                args += ["--ref_text", referenceText]
            }
        } else {
            args += ["--instruct", "male, American accent, natural, low pitch"]
        }
        return args
    }

    private func existingReferenceAudio(_ referenceAudio: URL?) -> URL? {
        if let referenceAudio,
           FileManager.default.fileExists(atPath: referenceAudio.path(percentEncoded: false)) {
            return referenceAudio
        }
        return nil
    }

    private func resolveOrBootstrapExecutable(directories: DetourDirectories) throws -> String {
        if let executable = Self.resolveExecutable(environment: environment, directories: directories) {
            return executable
        }

        detourOmniVoiceLog.info("[DetourOmniVoiceDesktopRenderer] bootstrapping local OmniVoice runtime")
        let executable = try bootstrapExecutable(directories: directories)
        detourOmniVoiceLog.info("[DetourOmniVoiceDesktopRenderer] local OmniVoice runtime ready")
        return executable
    }

    private func bootstrapExecutable(directories: DetourDirectories) throws -> String {
        let fileManager = FileManager.default
        let venv = directories.voice.appendingPathComponent("omnivoice-python", isDirectory: true)
        let venvPython = venv.appendingPathComponent("bin/python", isDirectory: false).path(percentEncoded: false)
        let executable = venv.appendingPathComponent("bin/omnivoice-infer", isDirectory: false).path(percentEncoded: false)
        let environment = bootstrapEnvironment(directories: directories)

        if fileManager.isExecutableFile(atPath: executable) {
            return executable
        }

        let python = try Self.resolvePython(environment: environment)
        let uv = Self.resolveUV(environment: environment)

        if fileManager.fileExists(atPath: venv.path(percentEncoded: false)),
           fileManager.isExecutableFile(atPath: venvPython),
           !Self.isUsablePython(venvPython, environment: environment) {
            try Self.moveBrokenRuntimeAside(venv)
        }

        if !fileManager.isExecutableFile(atPath: venvPython) {
            try Self.createVirtualEnvironment(
                at: venv,
                python: python,
                uv: uv,
                environment: environment
            )
        }

        if !Self.isUsablePython(venvPython, environment: environment) {
            try Self.moveBrokenRuntimeAside(venv)
            try Self.createVirtualEnvironment(
                at: venv,
                python: python,
                uv: uv,
                environment: environment
            )
        }

        if let uv {
            try Self.run(
                executable: uv,
                arguments: [
                    "pip", "install",
                    "--python", venvPython,
                    "torch==2.8.0",
                    "torchaudio==2.8.0",
                    "omnivoice"
                ],
                environment: environment
            )
        } else {
            try Self.run(
                executable: venvPython,
                arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
                environment: environment
            )
            try Self.run(
                executable: venvPython,
                arguments: ["-m", "pip", "install", "torch==2.8.0", "torchaudio==2.8.0"],
                environment: environment
            )
            try Self.run(
                executable: venvPython,
                arguments: ["-m", "pip", "install", "omnivoice"],
                environment: environment
            )
        }

        guard fileManager.isExecutableFile(atPath: executable) else {
            throw DetourOmniVoiceDesktopRendererError.bootstrapFailed("omnivoice-infer was not created")
        }
        return executable
    }

    private static func createVirtualEnvironment(
        at venv: URL,
        python: String,
        uv: String?,
        environment: [String: String]
    ) throws {
        if let uv {
            try run(
                executable: uv,
                arguments: ["venv", "--python", python, venv.path(percentEncoded: false)],
                environment: environment
            )
        } else {
            try run(
                executable: python,
                arguments: ["-m", "venv", venv.path(percentEncoded: false)],
                environment: environment
            )
        }
    }

    private static func moveBrokenRuntimeAside(_ venv: URL) throws {
        let fileManager = FileManager.default
        let path = venv.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return }

        let parent = venv.deletingLastPathComponent()
        let timestamp = Int(Date().timeIntervalSince1970)
        var backup = parent.appendingPathComponent("omnivoice-python.broken-\(timestamp)", isDirectory: true)
        if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
            backup = parent.appendingPathComponent("omnivoice-python.broken-\(timestamp)-\(UUID().uuidString)", isDirectory: true)
        }
        detourOmniVoiceLog.error("[DetourOmniVoiceDesktopRenderer] moving broken OmniVoice runtime to \(backup.path(percentEncoded: false), privacy: .public)")
        try fileManager.moveItem(at: venv, to: backup)
    }

    private func bootstrapEnvironment(directories: DetourDirectories) -> [String: String] {
        var values = environment
        values["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        values["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        values["HF_HOME"] = directories.voice.appendingPathComponent("hf", isDirectory: true).path(percentEncoded: false)
        return values
    }

    private static func resolveExecutable(environment: [String: String], directories: DetourDirectories) -> String? {
        if let configured = environment["SWOOSH_OMNIVOICE_INFER"],
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }

        let localExecutable = directories.voice
            .appendingPathComponent("omnivoice-python/bin/omnivoice-infer", isDirectory: false)
            .path(percentEncoded: false)
        if FileManager.default.isExecutableFile(atPath: localExecutable) {
            return localExecutable
        }

        for directory in environment["PATH", default: ""].split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("omnivoice-infer", isDirectory: false)
                .path(percentEncoded: false)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private static func resolvePython(environment: [String: String]) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [String] = []
        if let configured = environment["SWOOSH_OMNIVOICE_PYTHON"] {
            candidates.append(configured)
        }
        candidates += [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            home.appendingPathComponent(".local/bin/python3.12").path(percentEncoded: false),
            home.appendingPathComponent(".local/bin/python3.11").path(percentEncoded: false),
            home.appendingPathComponent(".local/bin/python3.10").path(percentEncoded: false)
        ]
        for name in ["python3.12", "python3.11", "python3.10", "python3"] {
            if let path = resolvePath(name, environment: environment) {
                candidates.append(path)
            }
        }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            if isSupportedPython(candidate) {
                return candidate
            }
        }
        throw DetourOmniVoiceDesktopRendererError.pythonMissing
    }

    private static func resolvePath(_ executable: String, environment: [String: String]) -> String? {
        for directory in environment["PATH", default: ""].split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executable, isDirectory: false)
                .path(percentEncoded: false)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func resolveUV(environment: [String: String]) -> String? {
        if let configured = environment["SWOOSH_UV"],
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        if let path = resolvePath("uv", environment: environment) {
            return path
        }
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/uv", isDirectory: false)
            .path(percentEncoded: false)
        if FileManager.default.isExecutableFile(atPath: local) {
            return local
        }
        return nil
    }

    private static func isSupportedPython(_ executable: String) -> Bool {
        do {
            let output = try runCapturingOutput(
                executable: executable,
                arguments: ["-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
                environment: ProcessInfo.processInfo.environment
            )
            let parts = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ".")
                .compactMap { Int($0) }
            guard parts.count == 2 else { return false }
            return parts[0] == 3
                && (10...13).contains(parts[1])
                && isUsablePython(executable, environment: ProcessInfo.processInfo.environment)
        } catch {
            return false
        }
    }

    private static func isUsablePython(_ executable: String, environment: [String: String]) -> Bool {
        do {
            _ = try runCapturingOutput(
                executable: executable,
                arguments: ["-c", "import platform, sys; sys.exit(0 if platform.mac_ver()[0] else 1)"],
                environment: environment
            )
            return true
        } catch {
            return false
        }
    }

    private static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = [
                String(data: output, encoding: .utf8),
                String(data: error, encoding: .utf8)
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw DetourOmniVoiceDesktopRendererError.bootstrapFailed(message)
        }
    }

    private static func runCapturingOutput(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? "Python version check failed."
            throw DetourOmniVoiceDesktopRendererError.bootstrapFailed(message)
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}

enum DetourOmniVoiceDesktopRendererError: LocalizedError {
    case pythonMissing
    case bootstrapFailed(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            "Python 3.10-3.13 is required for OmniVoice."
        case .bootstrapFailed(let message):
            message.isEmpty ? "OmniVoice setup failed." : message
        case .renderFailed(let message):
            message
        }
    }
}
