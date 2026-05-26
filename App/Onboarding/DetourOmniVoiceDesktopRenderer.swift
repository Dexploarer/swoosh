// DetourOmniVoiceDesktopRenderer.swift — local OmniVoice bridge for macOS onboarding (0.5A)

import Foundation
import CryptoKit
import OSLog

private let detourOmniVoiceLog = Logger(subsystem: "ai.swoosh.detour.mac", category: "OmniVoice")

actor DetourOmniVoiceDesktopRenderer {
    private let environment: [String: String]
    private var worker: DetourOmniVoiceWorker?
    private var workerStartupTask: Task<DetourOmniVoiceWorker, Error>?
    private var renderTasks: [String: Task<URL, Error>] = [:]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func prepare() async throws {
        let directories = try DetourPaths.ensureDirectories()
        _ = try resolveOrBootstrapExecutable(directories: directories)
        _ = try await resolveWorker(directories: directories)
    }

    func render(text: String, referenceAudio: URL?, referenceText: String?) async throws -> URL {
        let directories = try DetourPaths.ensureDirectories()
        _ = try resolveOrBootstrapExecutable(directories: directories)
        let referenceAudio = existingReferenceAudio(referenceAudio)
        let cacheURL = try cachedOutputURL(
            directories: directories,
            text: text,
            referenceAudio: referenceAudio,
            referenceText: referenceText
        )
        if FileManager.default.fileExists(atPath: cacheURL.path(percentEncoded: false)) {
            return cacheURL
        }
        let cacheKey = cacheURL.deletingPathExtension().lastPathComponent
        if let renderTask = renderTasks[cacheKey] {
            return try await renderTask.value
        }

        let worker = try await resolveWorker(directories: directories)
        let output = directories.voice.appendingPathComponent("omnivoice-\(UUID().uuidString).wav", isDirectory: false)
        let request = DetourOmniVoiceWorkerRequest(
            text: text,
            output: output.path(percentEncoded: false),
            refAudio: referenceAudio?.path(percentEncoded: false),
            refText: referenceText,
            instruct: referenceAudio == nil ? "male, American accent, natural, low pitch" : nil,
            numStep: omniVoiceStepCount,
            guidanceScale: omniVoiceGuidanceScale,
            speed: omniVoiceSpeed
        )

        let renderTask = Task<URL, Error> {
            let renderedURL = try await worker.render(request: request)
            return try Self.moveRenderedAudio(renderedURL, to: cacheURL)
        }
        renderTasks[cacheKey] = renderTask
        defer { renderTasks[cacheKey] = nil }

        do {
            return try await renderTask.value
        } catch {
            if !worker.isRunning {
                self.worker = nil
            }
            throw error
        }
    }

    private func resolveWorker(directories: DetourDirectories) async throws -> DetourOmniVoiceWorker {
        if let worker, worker.isRunning {
            return worker
        }
        if let workerStartupTask {
            return try await workerStartupTask.value
        }

        let executablePath = try resolveOrBootstrapExecutable(directories: directories)
        let python = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .appendingPathComponent("python", isDirectory: false)
            .path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw DetourOmniVoiceDesktopRendererError.bootstrapFailed("OmniVoice Python runtime was not found.")
        }

        let script = try writeWorkerScript(directories: directories)
        var workerEnvironment = environment
        workerEnvironment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        workerEnvironment["HF_HOME"] = directories.voice.appendingPathComponent("hf", isDirectory: true).path(percentEncoded: false)
        let device = omniVoiceDevice
        let startupTask = Task<DetourOmniVoiceWorker, Error> {
            try await DetourOmniVoiceWorker.start(
                python: python,
                script: script,
                model: "k2-fsa/OmniVoice",
                device: device,
                environment: workerEnvironment
            )
        }
        workerStartupTask = startupTask
        do {
            let worker = try await startupTask.value
            self.worker = worker
            workerStartupTask = nil
            return worker
        } catch {
            workerStartupTask = nil
            throw error
        }
    }

    private var omniVoiceDevice: String? {
        environment["SWOOSH_OMNIVOICE_DEVICE"]
    }

    private var omniVoiceStepCount: Int {
        Int(environment["SWOOSH_OMNIVOICE_NUM_STEP"] ?? "") ?? 12
    }

    private var omniVoiceGuidanceScale: Double {
        Double(environment["SWOOSH_OMNIVOICE_GUIDANCE_SCALE"] ?? "") ?? 1.5
    }

    private var omniVoiceSpeed: Double? {
        Double(environment["SWOOSH_OMNIVOICE_SPEED"] ?? "")
    }

    private func writeWorkerScript(directories: DetourDirectories) throws -> String {
        let url = directories.voice.appendingPathComponent("omnivoice-worker.py", isDirectory: false)
        let content = Self.workerScript
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           existing == content {
            return url.path(percentEncoded: false)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path(percentEncoded: false)
    }

    private func existingReferenceAudio(_ referenceAudio: URL?) -> URL? {
        if let referenceAudio,
           FileManager.default.fileExists(atPath: referenceAudio.path(percentEncoded: false)) {
            return referenceAudio
        }
        return nil
    }

    private func cachedOutputURL(
        directories: DetourDirectories,
        text: String,
        referenceAudio: URL?,
        referenceText: String?
    ) throws -> URL {
        let cacheDirectory = directories.voice.appendingPathComponent("render-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let key = Self.cacheKey(
            text: text,
            referenceAudio: referenceAudio,
            referenceText: referenceText,
            instruct: referenceAudio == nil ? "male, American accent, natural, low pitch" : nil,
            numStep: omniVoiceStepCount,
            guidanceScale: omniVoiceGuidanceScale,
            speed: omniVoiceSpeed
        )
        return cacheDirectory.appendingPathComponent("\(key).wav", isDirectory: false)
    }

    private static func cacheKey(
        text: String,
        referenceAudio: URL?,
        referenceText: String?,
        instruct: String?,
        numStep: Int,
        guidanceScale: Double,
        speed: Double?
    ) -> String {
        let key = DetourOmniVoiceCacheKey(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            referenceAudio: referenceAudio.map(referenceFingerprint),
            referenceText: referenceText?.trimmingCharacters(in: .whitespacesAndNewlines),
            instruct: instruct,
            numStep: numStep,
            guidanceScale: guidanceScale,
            speed: speed
        )
        let data = (try? JSONEncoder().encode(key)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func referenceFingerprint(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)|\(size)|\(modified)"
    }

    private static func moveRenderedAudio(_ renderedURL: URL, to cacheURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let renderedPath = renderedURL.path(percentEncoded: false)
        let cachePath = cacheURL.path(percentEncoded: false)
        if fileManager.fileExists(atPath: cachePath) {
            if renderedPath != cachePath {
                try? fileManager.removeItem(at: renderedURL)
            }
            return cacheURL
        }
        try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: renderedURL, to: cacheURL)
        } catch {
            if fileManager.fileExists(atPath: cachePath) {
                try? fileManager.removeItem(at: renderedURL)
                return cacheURL
            }
            throw error
        }
        return cacheURL
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

    private static let workerScript = """
import argparse
import json
import logging
import sys
import traceback

import soundfile as sf
import torch

from omnivoice.cli.infer import get_best_device
from omnivoice.models.omnivoice import OmniVoice


def compact(values):
    return {key: value for key, value in values.items() if value is not None}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="k2-fsa/OmniVoice")
    parser.add_argument("--device", default=None)
    args = parser.parse_args()

    logging.basicConfig(
        format="%(asctime)s %(levelname)s [%(filename)s:%(lineno)d] %(message)s",
        level=logging.INFO,
        stream=sys.stderr,
        force=True,
    )
    device = args.device or get_best_device()
    logging.info("Loading model from %s on %s ...", args.model, device)
    model = OmniVoice.from_pretrained(args.model, device_map=device, dtype=torch.float16)
    print(json.dumps({"ready": True, "device": device}), flush=True)

    for line in sys.stdin:
        try:
            request = json.loads(line)
            audios = model.generate(**compact({
                "text": request["text"],
                "ref_audio": request.get("ref_audio"),
                "ref_text": request.get("ref_text"),
                "instruct": request.get("instruct"),
                "num_step": request.get("num_step"),
                "guidance_scale": request.get("guidance_scale"),
                "speed": request.get("speed"),
            }))
            sf.write(request["output"], audios[0], model.sampling_rate)
            print(json.dumps({"ok": True, "output": request["output"]}), flush=True)
        except BaseException as error:
            logging.error("Render failed: %s\\n%s", error, traceback.format_exc())
            print(json.dumps({"ok": False, "error": str(error)}), flush=True)


if __name__ == "__main__":
    main()
"""
}

private struct DetourOmniVoiceWorkerRequest: Codable, Sendable {
    var text: String
    var output: String
    var refAudio: String?
    var refText: String?
    var instruct: String?
    var numStep: Int
    var guidanceScale: Double
    var speed: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case output
        case refAudio = "ref_audio"
        case refText = "ref_text"
        case instruct
        case numStep = "num_step"
        case guidanceScale = "guidance_scale"
        case speed
    }
}

private struct DetourOmniVoiceCacheKey: Codable, Sendable {
    var text: String
    var referenceAudio: String?
    var referenceText: String?
    var instruct: String?
    var numStep: Int
    var guidanceScale: Double
    var speed: Double?
}

private struct DetourOmniVoiceWorkerReady: Decodable, Sendable {
    var ready: Bool
    var device: String?
    var error: String?
}

private struct DetourOmniVoiceWorkerResponse: Decodable, Sendable {
    var ok: Bool
    var output: String?
    var error: String?
}

private final class DetourOmniVoiceWorker: @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let renderLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(process: Process, input: FileHandle, output: FileHandle, errorOutput: FileHandle) {
        self.process = process
        self.input = input
        self.output = output
        self.errorOutput = errorOutput
        self.errorOutput.readabilityHandler = { handle in
            _ = handle.availableData
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    static func start(
        python: String,
        script: String,
        model: String,
        device: String?,
        environment: [String: String]
    ) async throws -> DetourOmniVoiceWorker {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        var arguments = [script, "--model", model]
        if let device {
            arguments += ["--device", device]
        }
        process.arguments = arguments
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let worker = DetourOmniVoiceWorker(
            process: process,
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading,
            errorOutput: errorPipe.fileHandleForReading
        )
        let ready: DetourOmniVoiceWorkerReady = try await worker.readDecodableLine()
        guard ready.ready else {
            worker.terminate()
            throw DetourOmniVoiceDesktopRendererError.renderFailed(ready.error ?? "OmniVoice worker did not become ready.")
        }
        detourOmniVoiceLog.info("[DetourOmniVoiceDesktopRenderer] worker ready device=\(ready.device ?? "unknown", privacy: .public)")
        return worker
    }

    func render(request: DetourOmniVoiceWorkerRequest) async throws -> URL {
        try await Task.detached { [self] in
            try renderBlocking(request: request)
        }.value
    }

    private func renderBlocking(request: DetourOmniVoiceWorkerRequest) throws -> URL {
        renderLock.lock()
        defer { renderLock.unlock() }
        guard process.isRunning else {
            throw DetourOmniVoiceDesktopRendererError.renderFailed("OmniVoice worker is not running.")
        }

        var data = try encoder.encode(request)
        data.append(0x0A)
        input.write(data)

        let response: DetourOmniVoiceWorkerResponse = try readDecodableLineBlocking()
        guard response.ok,
              let output = response.output,
              FileManager.default.fileExists(atPath: output) else {
            throw DetourOmniVoiceDesktopRendererError.renderFailed(response.error ?? "OmniVoice did not render audio.")
        }
        return URL(fileURLWithPath: output)
    }

    private func readDecodableLine<Value: Decodable & Sendable>() async throws -> Value {
        try await Task.detached { [self] in
            try readDecodableLineBlocking()
        }.value
    }

    private func readDecodableLineBlocking<Value: Decodable>() throws -> Value {
        let line = try readLineBlocking()
        guard let data = line.data(using: .utf8) else {
            throw DetourOmniVoiceDesktopRendererError.renderFailed("OmniVoice returned invalid UTF-8.")
        }
        return try decoder.decode(Value.self, from: data)
    }

    private func readLineBlocking() throws -> String {
        var data = Data()
        while true {
            let byte = output.readData(ofLength: 1)
            if byte.isEmpty {
                throw DetourOmniVoiceDesktopRendererError.renderFailed("OmniVoice worker closed stdout.")
            }
            if byte[0] == 0x0A {
                return String(decoding: data, as: UTF8.self)
            }
            data.append(byte)
        }
    }

    func terminate() {
        errorOutput.readabilityHandler = nil
        try? input.close()
        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        terminate()
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
