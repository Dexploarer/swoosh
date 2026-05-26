// DetourPersonalizationScanCommands.swift — local scan command execution helpers (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

@MainActor
extension DetourPersonalizationRunner {
    func runScout(
        logHandle: FileHandle,
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async throws {
        let projectRoot = Self.projectRoot
        if let swoosh = executable(named: "swoosh") {
            try await runCommand(
                executable: swoosh,
                arguments: ["scout", "run", "--depth", "recommended"],
                currentDirectory: projectRoot,
                logHandle: logHandle,
                progressStart: 0.28,
                progressEnd: 0.54,
                title: "Running Scout",
                onProgress: onProgress
            )
        } else {
            try await runCommand(
                executable: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: ["run", "swoosh", "scout", "run", "--depth", "recommended"],
                currentDirectory: projectRoot,
                logHandle: logHandle,
                progressStart: 0.28,
                progressEnd: 0.54,
                title: "Running Scout",
                onProgress: onProgress
            )
        }
    }

    func runCredentialInheritance(
        consent: DetourCredentialInheritanceConsent,
        logHandle: FileHandle,
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async throws {
        let arguments = ["provider", "inherit", "--quiet", "--discover-only"]
            + (consent.keychainCredentials ? ["--allow-keychain"] : [])
            + (consent.keychainCredentials ? ["--prompt-keychain"] : [])
            + (consent.browserCookies ? ["--allow-browser-cookies"] : [])
        guard let command = providerInheritCommand(logHandle: logHandle) else {
            appendLog(
                "Provider inherit skipped: deterministic Keychain and browser metadata scan will run in-app.",
                to: logHandle
            )
            await setProgress(0.25, "Checking auth", onProgress)
            return
        }
        try await runCommand(
            executable: command.executable,
            arguments: command.argumentsPrefix + arguments,
            currentDirectory: command.currentDirectory,
            logHandle: logHandle,
            progressStart: 0.12,
            progressEnd: 0.25,
            title: "Checking auth",
            onProgress: onProgress
        )
    }

    func runAgentContext(
        logHandle: FileHandle,
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async throws {
        guard let executable = executable(named: "agent-context") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await runCommand(
            executable: executable,
            arguments: ["collect", "--all", "--quiet"],
            currentDirectory: nil,
            logHandle: logHandle,
            progressStart: 0.56,
            progressEnd: 0.82,
            title: "Reading local context",
            onProgress: onProgress
        )
    }

    func runCommand(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        logHandle: FileHandle,
        progressStart: Double,
        progressEnd: Double,
        title: String,
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        var tick = 0
        while process.isRunning {
            let fraction = min(progressEnd - 0.02, progressStart + (Double(tick) * 0.015))
            await setProgress(fraction, title, onProgress, tick: tick)
            tick += 1
            try await Task.sleep(for: .seconds(2))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DetourPersonalizationError.commandFailed(process.terminationStatus)
        }
        await setProgress(progressEnd, title, onProgress)
    }
}
