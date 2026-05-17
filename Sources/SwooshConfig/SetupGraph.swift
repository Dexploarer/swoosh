// SwooshConfig/SetupGraph.swift — Typed setup graph with detect/configure/verify/rollback
//
// Every setup step is a Swift type with lifecycle phases.
// The wizard can run in CLI, SwiftUI, or headless mode.
// "Do not let users complete setup with broken credentials or untested gateways."

import Foundation

// MARK: - Setup step protocol

/// A typed, verifiable step in the Swoosh commissioning process.
/// Each step can detect existing state, configure, verify, and rollback.
public protocol SetupStep: Sendable {
    var id: SetupStepID { get }
    var title: String { get }
    var description: String { get }
    var dependencies: [SetupStepID] { get }
    var isRequired: Bool { get }

    /// Check if this step is already configured.
    func detect(context: SetupContext) async throws -> SetupStatus

    /// Run the configuration for this step.
    func configure(context: SetupContext) async throws -> SetupResult

    /// Verify the configuration actually works.
    func verify(context: SetupContext) async throws -> VerificationResult

    /// Undo this step's configuration.
    func rollback(context: SetupContext) async throws
}

// MARK: - Setup identifiers

public struct SetupStepID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

// MARK: - Status types

public enum SetupStatus: Sendable {
    case missing
    case configured(summary: String)
    case needsUpdate(reason: String)
    case broken(error: String)
}

public enum SetupResult: Sendable {
    case success(summary: String)
    case skipped(reason: String)
    case failed(error: String)
}

public enum VerificationResult: Sendable {
    case passed(details: String)
    case warning(message: String)
    case failed(error: String)
}

// MARK: - Setup context

/// Shared context passed to every setup step. 
/// Provides access to credentials, config, UI, and system info.
public final class SetupContext: Sendable {
    public let credentials: CredentialStore
    public let config: SwooshConfigStore
    public let hardware: HardwareProfile
    public let ui: any SetupUI
    public let homeDirectory: URL

    public init(
        credentials: CredentialStore,
        config: SwooshConfigStore,
        hardware: HardwareProfile,
        ui: any SetupUI,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.credentials = credentials
        self.config = config
        self.hardware = hardware
        self.ui = ui
        self.homeDirectory = homeDirectory
    }

    public var swooshDirectory: URL {
        homeDirectory.appending(path: ".swoosh")
    }
}

// MARK: - Setup UI protocol (CLI or SwiftUI can implement this)

public protocol SetupUI: Sendable {
    func showProgress(_ step: SetupStepID, message: String) async
    func showResult(_ step: SetupStepID, result: SetupResult) async
    func showVerification(_ step: SetupStepID, result: VerificationResult) async
    func askYesNo(_ prompt: String, default: Bool) async -> Bool
    func askChoice(_ prompt: String, options: [String], default: Int) async -> Int
    func askString(_ prompt: String, default: String?) async -> String
    func askSecret(_ prompt: String) async -> String
    func showReport(_ report: SetupReport) async
}

// MARK: - Setup modes

public enum SetupMode: String, Codable, Sendable, CaseIterable {
    case quick       // model + daemon + basic tools + smoke test
    case full        // everything
    case developer   // swift/xcode/git/sourcekit-lsp
    case server      // CLI-only, env-based secrets
    case importAgent // import from Hermes/Claude Code/Codex
}

// MARK: - Setup graph executor

/// Executes setup steps in dependency order with verification gates.
public actor SetupGraphExecutor {
    private let steps: [any SetupStep]
    private var results: [SetupStepID: StepExecutionRecord] = [:]

    public init(steps: [any SetupStep]) {
        self.steps = steps
    }

    /// Run setup in the given mode.
    public func execute(mode: SetupMode, context: SetupContext) async -> SetupReport {
        let ordered = topologicalSort(steps)
        let applicable = ordered.filter { shouldRun($0, mode: mode) }

        for step in applicable {
            // Check dependencies
            let depsMet = step.dependencies.allSatisfy { depID in
                guard let record = results[depID] else {
                    return !steps.contains(where: { $0.id == depID && $0.isRequired })
                }
                switch record.verification {
                case .passed: return true
                case .warning: return true
                case .failed: return false
                }
            }

            guard depsMet else {
                let record = StepExecutionRecord(
                    stepID: step.id,
                    status: .missing,
                    result: .skipped(reason: "Dependencies not met"),
                    verification: .warning(message: "Skipped")
                )
                results[step.id] = record
                await context.ui.showResult(step.id, result: record.result)
                continue
            }

            await context.ui.showProgress(step.id, message: "Checking \(step.title)...")

            // Phase 1: Detect
            let status: SetupStatus
            do {
                status = try await step.detect(context: context)
            } catch {
                status = .broken(error: error.localizedDescription)
            }

            // Phase 2: Configure (if needed)
            let result: SetupResult
            switch status {
            case .configured(let summary):
                result = .success(summary: "Already configured: \(summary)")
            case .missing, .needsUpdate, .broken:
                do {
                    result = try await step.configure(context: context)
                } catch {
                    result = .failed(error: error.localizedDescription)
                }
            }

            await context.ui.showResult(step.id, result: result)

            // Phase 3: Verify
            let verification: VerificationResult
            switch result {
            case .success:
                do {
                    verification = try await step.verify(context: context)
                } catch {
                    verification = .failed(error: error.localizedDescription)
                }
            case .skipped:
                verification = .warning(message: "Skipped")
            case .failed(let err):
                verification = .failed(error: err)
            }

            await context.ui.showVerification(step.id, result: verification)

            results[step.id] = StepExecutionRecord(
                stepID: step.id,
                status: status,
                result: result,
                verification: verification
            )
        }

        return buildReport()
    }

    /// Rollback all completed steps in reverse order.
    public func rollbackAll(context: SetupContext) async {
        let completed = results.values
            .filter { if case .success = $0.result { return true }; return false }
            .sorted { $0.stepID.rawValue > $1.stepID.rawValue }

        for record in completed {
            if let step = steps.first(where: { $0.id == record.stepID }) {
                try? await step.rollback(context: context)
            }
        }
    }

    // MARK: - Internals

    private func shouldRun(_ step: any SetupStep, mode: SetupMode) -> Bool {
        switch mode {
        case .quick:
            return step.isRequired
        case .full, .importAgent:
            return true
        case .developer:
            let devSteps: Set<SetupStepID> = [
                "preflight", "daemon", "model.provider", "model.local",
                "permissions", "terminal", "memory",
                "tools.file", "tools.shell", "tools.git", "tools.lsp",
                "tools.github", "tools.mcp", "smoke-test"
            ]
            return step.isRequired || devSteps.contains(step.id)
        case .server:
            let serverSteps: Set<SetupStepID> = [
                "preflight", "model.provider", "permissions",
                "terminal", "memory", "smoke-test"
            ]
            return step.isRequired || serverSteps.contains(step.id)
        }
    }

    private func topologicalSort(_ steps: [any SetupStep]) -> [any SetupStep] {
        // Simple stable topo sort
        var sorted: [any SetupStep] = []
        var visited = Set<SetupStepID>()

        func visit(_ step: any SetupStep) {
            guard !visited.contains(step.id) else { return }
            visited.insert(step.id)
            for dep in step.dependencies {
                if let depStep = steps.first(where: { $0.id == dep }) {
                    visit(depStep)
                }
            }
            sorted.append(step)
        }

        for step in steps { visit(step) }
        return sorted
    }

    private func buildReport() -> SetupReport {
        SetupReport(
            timestamp: Date(),
            steps: Array(results.values).sorted { $0.stepID.rawValue < $1.stepID.rawValue }
        )
    }
}

// MARK: - Execution record

public struct StepExecutionRecord: Sendable {
    public let stepID: SetupStepID
    public let status: SetupStatus
    public let result: SetupResult
    public let verification: VerificationResult
}

// MARK: - Setup report

public struct SetupReport: Sendable {
    public let timestamp: Date
    public let steps: [StepExecutionRecord]

    public var allPassed: Bool {
        steps.allSatisfy {
            if case .passed = $0.verification { return true }
            if case .warning = $0.verification { return true }
            return false
        }
    }

    public var failures: [StepExecutionRecord] {
        steps.filter {
            if case .failed = $0.verification { return true }
            return false
        }
    }
}
